#!/usr/bin/env python3
"""Validated, atomic certificate-pair promotion for the existing Certbot hook.

No issuance, timer, DNS change or service restart. Installation/prepare and live
promotion are operator actions; see go-relay-server/docs/turn-operations.md.
"""

import argparse
import fcntl
import grp
import hashlib
import os
from pathlib import Path
import shutil
import socket
import ssl
import subprocess
import tempfile
import time


class InvalidCertificate(RuntimeError):
    pass


def openssl(*args, data=None):
    result = subprocess.run(['openssl', *map(str, args)], input=data,
                            capture_output=True, timeout=15)
    if result.returncode:
        # OpenSSL diagnostics can contain paths and certificate identities.
        raise InvalidCertificate('Certificate/key preflight rejected the input')
    return result.stdout


def validate_pair(directory, trust, hostname, min_validity=604800):
    """Only trust is a CAfile; all served intermediates remain untrusted."""
    import re
    fullchain = (directory / 'fullchain.pem').read_bytes()
    certs = re.findall(b'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----',
                       fullchain, re.S)
    if not certs or len(certs) > 8 or re.sub(
            b'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----',
            b'', fullchain, flags=re.S).strip():
        raise InvalidCertificate('Malformed or excessive certificate chain')
    for cert in certs:
        openssl('x509', '-noout', '-checkend', min_validity, data=cert)
    with tempfile.TemporaryDirectory(prefix='coturn-chain-') as temporary:
        leaf = Path(temporary) / 'leaf.pem'
        chain = Path(temporary) / 'intermediates.pem'
        leaf.write_bytes(certs[0] + b'\n')
        chain.write_bytes(b'\n'.join(certs[1:]) + b'\n')
        args = ['verify', '-no-CApath', '-no-CAstore', '-purpose', 'sslserver',
                '-verify_hostname', hostname, '-CAfile', trust]
        if len(certs) > 1:
            args += ['-untrusted', chain]
        openssl(*args, leaf)
        # Verify order as well as the trusted path. Intermediates never become
        # trust anchors, even in this structural check.
        for child, issuer in zip(certs, certs[1:]):
            child_issuer = openssl('x509', '-noout', '-issuer', '-nameopt',
                                   'RFC2253', data=child).split(b'=', 1)[1].strip()
            issuer_subject = openssl('x509', '-noout', '-subject', '-nameopt',
                                     'RFC2253', data=issuer).split(b'=', 1)[1].strip()
            if child_issuer != issuer_subject:
                raise InvalidCertificate('Certificate chain is not in issuer order')
    cert_public = openssl('x509', '-pubkey', '-noout', data=certs[0])
    cert_public = openssl('pkey', '-pubin', '-outform', 'DER', data=cert_public)
    key_public = openssl('pkey', '-in', directory / 'privkey.pem',
                         '-pubout', '-outform', 'DER')
    if cert_public != key_public:
        raise InvalidCertificate('Certificate and private key do not match')
    return hashlib.sha256(openssl('x509', '-outform', 'DER', data=certs[0])).hexdigest()


def atomic_link(target, path):
    temporary = path.with_name(path.name + '.next')
    # The directory is root-owned, locked and not writable by the daemon.
    temporary.unlink(missing_ok=True)
    temporary.symlink_to(target)
    os.replace(temporary, path)


def copy_pair(source, destination, gid):
    for name in ('fullchain.pem', 'privkey.pem'):
        target = destination / name
        # Never overwrite an existing generation or follow a target symlink.
        with target.open('xb') as output, (source / name).open('rb') as input_file:
            os.fchmod(output.fileno(), 0o640)
            os.fchown(output.fileno(), os.getuid(), gid)
            shutil.copyfileobj(input_file, output)
            output.flush()
            os.fsync(output.fileno())


def promote(lineage, destination, trust, hostname, gid, reload_and_verify,
            *, prepare=False, min_validity=604800):
    """On any preflight/reload error retain/restore the working generation."""
    # The caller owns this protected directory; lock spans snapshot, promotion
    # and served-certificate verification, including rollback.
    if destination.is_symlink() or not destination.is_dir():
        raise RuntimeError('A protected certificate directory must already exist')
    if destination.stat().st_uid != os.getuid() or destination.stat().st_mode & 0o022:
        raise RuntimeError('Certificate directory must be owned and not group/world writable')
    with (destination / '.deploy.lock').open('a') as lock:
        os.chmod(lock.name, 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)
        current = destination / 'current'
        generations = destination / 'generations'
        if generations.is_symlink():
            raise RuntimeError('Generation directory must not be a symlink')
        generations.mkdir(mode=0o750, exist_ok=True)
        os.chown(generations, os.getuid(), gid)
        os.chmod(generations, 0o750)
        if prepare:
            if current.exists() or current.is_symlink():
                raise RuntimeError('Already prepared; use the existing generation')
            if any((destination / n).is_symlink() for n in ('fullchain.pem', 'privkey.pem')):
                raise RuntimeError('Inspect existing certificate links before preparing')
            source = destination
        else:
            if not current.is_symlink() or current.resolve().parent != generations.resolve():
                raise RuntimeError('Run the reviewed prepare operation first')
            if any(not (destination / n).is_symlink() or
                   os.readlink(destination / n) != f'current/{n}'
                   for n in ('fullchain.pem', 'privkey.pem')):
                raise RuntimeError('Configured files must use the atomic current pair')
            source = lineage
        stage = Path(tempfile.mkdtemp(prefix='cert-', dir=generations))
        os.chmod(stage, 0o750)
        os.chown(stage, os.getuid(), gid)
        try:
            # Validate the private snapshot, never the changing Certbot symlinks.
            copy_pair(source, stage, gid)
            fingerprint = validate_pair(stage, trust, hostname, min_validity)
        except BaseException:
            shutil.rmtree(stage)
            raise
        relative_stage = str(stage.relative_to(destination))
        if prepare:
            # Both generations contain the same bytes throughout conversion.
            # A protected operator backup remains required before installation.
            atomic_link(relative_stage, current)
            for name in ('fullchain.pem', 'privkey.pem'):
                atomic_link(f'current/{name}', destination / name)
            return fingerprint
        previous = os.readlink(current)
        # A delayed renewal must still be able to replace an expired old leaf.
        # The rollback identity is the previously configured certificate, not
        # a second admission gate on the already validated new snapshot.
        old_fingerprint = hashlib.sha256(openssl(
            'x509', '-in', current / 'fullchain.pem', '-outform', 'DER')).hexdigest()
        atomic_link(relative_stage, current)
        try:
            reload_and_verify(fingerprint)
        except BaseException:
            atomic_link(previous, current)
            # Retain candidate/previous bytes privately for diagnosis and never
            # turn a failed promotion into a reported success after rollback.
            reload_and_verify(old_fingerprint)
            raise
        return fingerprint


def reload_and_probe(fingerprint, trust, hostname):
    subprocess.run(['systemctl', 'kill', '--kill-who=main', '--signal=SIGUSR2',
                    'coturn.service'], check=True, capture_output=True, timeout=15)
    context = ssl.create_default_context(cafile=str(trust))
    deadline = time.monotonic() + 10
    while True:
        try:
            for address in ('127.0.0.1', '::1'):
                with socket.create_connection((address, 5349), timeout=2) as connection:
                    with context.wrap_socket(connection, server_hostname=hostname) as tls:
                        if hashlib.sha256(tls.getpeercert(binary_form=True)).hexdigest() != fingerprint:
                            raise RuntimeError('Listener still serves a different certificate')
            return
        except (OSError, RuntimeError):
            if time.monotonic() >= deadline:
                raise RuntimeError('coturn did not serve the validated pair on both loopbacks') from None
            time.sleep(0.2)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['check', 'prepare', 'deploy'])
    parser.add_argument('--lineage', type=Path, required=True)
    parser.add_argument('--destination', type=Path, default=Path('/etc/coturn/tls'))
    parser.add_argument('--trust', type=Path, required=True)
    parser.add_argument('--hostname', default='mknoun.xyz')
    args = parser.parse_args()
    os.umask(0o077)
    if args.action == 'check':
        validate_pair(args.lineage, args.trust, args.hostname)
    else:
        if os.getuid() != 0:
            parser.error('Live preparation/promotion must run as root')
        promote(args.lineage, args.destination, args.trust, args.hostname,
                grp.getgrnam('turnserver').gr_gid,
                lambda fingerprint: reload_and_probe(fingerprint, args.trust, args.hostname),
                prepare=args.action == 'prepare')
    print('PASS: certificate operation completed')


if __name__ == '__main__':
    main()
