"""Small setup checks for existing campaigns; never drives or repairs a device.

Appium MCP owns exploratory UI work. Existing protocol campaigns keep their
assertions, and must receive exclusive UI ownership before they start.
"""
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import stat


# These entry points return before device work with --list-scenarios. Keeping
# the commands here prevents a config typo from accidentally running a journey.
HOST_PROBES = {
    'production-group-removed-reaction': ('integration_test/scripts/run_production_group_removed_reaction.dart', 'production.group_catalog.private_removed_reaction_rejected'),
    'production-group-reaction': ('integration_test/scripts/run_production_group_reaction.dart', 'production.group_catalog.private_reaction_roundtrip'),
    'production-group-reaction-toggle': ('integration_test/scripts/run_production_group_reaction_toggle.dart', 'production.group_catalog.private_reaction_toggle_convergence'),
    'production-group-create': ('integration_test/scripts/run_production_group_create.dart', 'production.group_catalog.private_abc_create'),
    'production-group-invites': ('integration_test/scripts/run_production_group_invite_reliability.dart', 'production.group_invite_reliability'),
    'production-group-delete-preserves-friends': ('integration_test/scripts/run_production_group_delete_preserves_friends.dart', 'production.group_delete_preserves_friends'),
    'production-group-invite-accept-spinner': ('integration_test/scripts/run_production_group_invite_accept_spinner.dart', 'production.group_invite_accept_spinner'),
    'production-group-new-member-media': ('integration_test/scripts/run_production_group_new_member_media.dart', 'production.group_new_member_media'),
    'production-group-online-remove': ('integration_test/scripts/run_production_group_online_remove.dart', 'production.group_catalog.private_online_remove'),
    'production-group-relay-only': ('integration_test/scripts/run_production_group_relay_only.dart', 'production.group_catalog.private_relay_only_delivery'),
    'production-group-process-death': ('integration_test/scripts/run_production_group_process_death.dart', 'production.group_catalog.private_process_death_matrix'),
    'production-group-gm004': ('integration_test/scripts/run_production_group_gm004.dart', 'production.group_catalog.gm004'),
    'production-group-gm005': ('integration_test/scripts/run_production_group_gm005.dart', 'production.group_catalog.gm005'),
    'production-group-offline-remove': ('integration_test/scripts/run_production_group_offline_remove.dart', 'production.group_catalog.private_offline_remove'),
    'production-group-gm006': ('integration_test/scripts/run_production_group_gm006.dart', 'production.group_catalog.gm006'),
    'production-group-offline-readd': ('integration_test/scripts/run_production_group_offline_readd.dart', 'production.group_catalog.private_offline_readd'),
    'production-group-gm001': ('integration_test/scripts/run_production_group_gm001.dart', 'production.group_catalog.gm001'),
    'production-group-ge001': ('integration_test/scripts/run_production_group_ge001.dart', 'production.group_catalog.ge001'),
    'production-group-de003': ('integration_test/scripts/run_production_group_de003.dart', 'production.group_catalog.de003'),
    'production-group-ge002': ('integration_test/scripts/run_production_group_ge002.dart', 'production.group_catalog.ge002'),
    'production-group-ge003': ('integration_test/scripts/run_production_group_ge003.dart', 'production.group_catalog.ge003'),
    'production-group-gm020': ('integration_test/scripts/run_production_group_gm020.dart', 'production.group_catalog.gm020'),
    'production-group-gm034': ('integration_test/scripts/run_production_group_gm034.dart', 'production.group_catalog.gm034'),
    'production-group-gm016': ('integration_test/scripts/run_production_group_gm016.dart', 'production.group_catalog.gm016'),
    'production-group-ge004': ('integration_test/scripts/run_production_group_ge004.dart', 'production.group_catalog.ge004'),
    'production-group-gm007': ('integration_test/scripts/run_production_group_gm007.dart', 'production.group_catalog.gm007'),
    'production-group-gm019': ('integration_test/scripts/run_production_group_gm019.dart', 'production.group_catalog.gm019'),
    'production-group-ge009': ('integration_test/scripts/run_production_group_ge009.dart', 'production.group_catalog.ge009'),
    'production-group-rapid-readd': ('integration_test/scripts/run_production_group_rapid_readd.dart', 'production.group_catalog.private_rapid_readd'),
    'production-group-ir001': ('integration_test/scripts/run_production_group_ir001.dart', 'production.group_catalog.ir001'),
    'production-group-gm008': ('integration_test/scripts/run_production_group_gm008.dart', 'production.group_catalog.gm008'),
    'production-group-ge007': ('integration_test/scripts/run_production_group_ge007.dart', 'production.group_catalog.ge007'),
    'production-group-ge008': ('integration_test/scripts/run_production_group_ge008.dart', 'production.group_catalog.ge008'),
    'production-group-ge005': ('integration_test/scripts/run_production_group_ge005.dart', 'production.group_catalog.ge005'),
    'production-group-readd-cycles': ('integration_test/scripts/run_production_group_readd_cycles.dart', 'production.group_catalog.private_readd_cycles'),
    'production-group-ge010': ('integration_test/scripts/run_production_group_ge010.dart', 'production.group_catalog.ge010'),
    'production-group-go001': ('integration_test/scripts/run_production_group_go001.dart', 'production.group_catalog.go001'),
    'production-group-ge011': ('integration_test/scripts/run_production_group_ge011.dart', 'production.group_catalog.ge011'),
    'production-group-full-mesh': ('integration_test/scripts/run_production_group_full_mesh.dart', 'production.group_catalog.private_full_mesh_online'),
    'production-group-de002': ('integration_test/scripts/run_production_group_de002.dart', 'production.group_catalog.de002'),
    'production-group-ge006': ('integration_test/scripts/run_production_group_ge006.dart', 'production.group_catalog.ge006'),
    'production-group-de007': ('integration_test/scripts/run_production_group_de007.dart', 'production.group_catalog.de007'),
    'production-group-voluntary-leave': ('integration_test/scripts/run_production_group_voluntary_leave.dart', 'production.group_catalog.private_voluntary_leave_convergence'),
    'production-group-gm015': ('integration_test/scripts/run_production_group_gm015.dart', 'production.group_catalog.gm015'),
    'production-group-ge024': ('integration_test/scripts/run_production_group_ge024.dart', 'production.group_catalog.ge024'),
    'production-group-media-reaction': ('integration_test/scripts/run_production_group_media_reaction.dart', 'production.group_catalog.private_media_reaction_roundtrip'),
    'production-group-gm002': ('integration_test/scripts/run_production_group_gm002.dart', 'production.group_catalog.gm002'),
    'production-group-ml002': ('integration_test/scripts/run_production_group_ml002.dart', 'production.group_catalog.private_online_add'),
    'production-group-gm003': ('integration_test/scripts/run_production_group_gm003.dart', 'production.group_catalog.gm003'),
    'production-group-ml003': ('integration_test/scripts/run_production_group_ml003.dart', 'production.group_catalog.private_offline_add'),
    'production-group-nw006': ('integration_test/scripts/run_production_group_nw006.dart', 'production.group_catalog.private_peer_disconnect_not_removal'),
    'production-group-invite-matrix': ('integration_test/scripts/run_production_group_invite_status_matrix.dart', 'production.group_invite_status_matrix'),
    'production-startup-resume-performance': ('integration_test/scripts/run_production_startup_resume_performance.dart', 'production.startup_resume_performance'),
    'production-private-media': ('integration_test/scripts/run_production_private_media_local.dart', 'production.private_media_local'),
    'production-routing': ('integration_test/scripts/run_production_routing.dart', 'production.routing_smoke'),
    'production-notification-open': ('integration_test/scripts/run_production_notification_open.dart', 'production.notification_open'),
    'production-notification-sound': ('integration_test/scripts/run_production_notification_sound.dart', 'production.notification_sound'),
    'production-foreground-group-push': ('integration_test/scripts/run_production_foreground_group_push.dart', 'production.foreground_group_push'),
    'notification-runner': ('integration_test/scripts/run_notification_tap_device_real.dart', 'tc_a6_replay_before_ack_custody'),
    'one-to-one-runner': ('integration_test/scripts/run_1to1_device_real.dart', 'android.production_1to1_audio_call'),
}


class DeviceLeaseBusy(RuntimeError):
    pass


class PreflightBlocked(RuntimeError):
    def __init__(self, receipt):
        self.receipt = receipt
        super().__init__(receipt['checkpoint'])


def device_roles(check, config):
    required = check.get('device_roles', [] if check.get('sims_mode') else ['android_physical', 'android_emulator'])
    # Nested SIMS routes can use more roles than the outer legacy wrapper.
    extra = sorted(set(config.get('devices', {})) - set(required)) if check.get('kind') in ('sims', 'legacy') else []
    return list(required) + extra


def validate_metadata(check):
    errors = []
    probe = check.get('host_preflight')
    if probe is not None and (not isinstance(probe, str) or probe not in HOST_PROBES):
        errors.append('Unknown safe host preflight')
    if check.get('kind') in ('sims', 'legacy') and (check.get('device_roles') or check.get('sims_mode')):
        reason = check.get('ui_driver_reason')
        if check.get('ui_driver') == 'maestro':
            flows = check.get('maestro_flows')
            if (not isinstance(flows, list) or not flows
                    or any(not isinstance(flow, str) or '..' in flow.split('/')
                           or not flow.startswith('integration_test/maestro/')
                           or not flow.endswith(('.yaml', '.yml')) for flow in flows)
                    or len(set(flows)) != len(flows)
                    or not isinstance(reason, str) or not reason.strip()):
                errors.append('Maestro campaigns require exact flows and a proof boundary reason')
        elif check.get('ui_driver') != 'existing_campaign' or not isinstance(reason, str) or not reason.strip():
            errors.append('Existing device campaigns must explain their non-Appium proof requirement')
    return errors


@contextmanager
def device_leases(targets, directory=None):
    """Serialize cooperating launchers across checkouts, without device actions."""
    directory = Path(directory) if directory else Path('/tmp') / f'mknoon-device-leases-{os.getuid()}'
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = directory.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise DeviceLeaseBusy('Device lease directory must be private and owned by the current user')
    handles = []
    try:
        for target in sorted(set(targets)):
            path = directory / (hashlib.sha256(target.encode()).hexdigest() + '.lock')
            fd = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
            handle = os.fdopen(fd, 'r+')
            handles.append(handle)
            info = os.fstat(fd)
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
                raise DeviceLeaseBusy('Device lease file must be private and owned by the current user')
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise DeviceLeaseBusy('Another campaign owns a selected device; let its cleanup finish') from None
        yield
    finally:
        for handle in reversed(handles):
            handle.close()
        # Do not unlink lock files: replacing an inode can admit two owners.


def instrumentation_state(output):
    """Require the process census ending, not just a successful shell exit.

    ProcessList.dumpProcessesLSP runs dumpActiveInstruments before calling
    ActivityManagerService.dumpOtherProcessesInfoLSP. That routine prints the
    process-ready state and ends unconditionally with mForceBackgroundCheck.
    Unknown/truncated formats cannot establish an idle instrumentation census.
    """
    if re.search(r'^\s*(?:Active instrumentation:|Instrumentation #\d+:)', output, re.M):
        return 'busy'
    # Android dumpsys prints its internal timeout/error then can return zero.
    # Its default 10-second timeout precedes our external 15-second limit.
    if re.search(r'DUMP TIMEOUT|DUMP FAILED|Permission Denial|SecurityException|'
                 r'Can.t find service|Error(?::| with service| while )|'
                 r'Exception occurred while dumping:', output):
        return 'unavailable'
    lines = [line for line in output.splitlines() if line.strip()]
    header = 'ACTIVITY MANAGER RUNNING PROCESSES (dumpsys activity processes)'
    if (not lines or lines[0] != header or lines.count(header) != 1
            or not re.fullmatch(r'\s+mForceBackgroundCheck=(?:true|false)', lines[-1])):
        return 'unavailable'
    ready = r'^\s+mProcessesReady=(?:true|false) mSystemReady=(?:true|false) '
    ready += r'mBooted=(?:true|false) mFactoryTest=-?\d+$'
    if len(re.findall(ready, output, re.M)) != 1:
        return 'unavailable'
    return 'idle'


def run(check, root, config, launch, env):
    """Fresh observations before each campaign. Returns closed, shareable facts."""
    observations = []

    def result(checkpoint, remediation):
        return {'status': 'BLOCKED', 'checkpoint': checkpoint,
                'remediation': remediation, 'observations': observations}

    if check.get('sims_mode') and 'SIMS_PROTECTED_DEVICE_ASSIGNMENTS_JSON' not in env:
        return result('device_binding_unprotected', 'Pass the leased target assignments to SIMS before running proofs.')

    # New native/XCTest recipes must recheck their leased simulator before a
    # wrapper can boot it. This observes availability, never automation idleness.
    if check.get('kind') == 'full_adapter':
        for role in device_roles(check, config):
            if not role.startswith('ios_simulator'):
                continue
            target = config.get('devices', {}).get(role)
            pins = json.loads(env.get('SIMS_PROTECTED_DEVICE_ASSIGNMENTS_JSON', '{}'))
            if not target or target not in pins.values():
                return result('device_binding_unprotected', 'Pin and lease the exact simulator before invoking its native wrapper.')
            output, code, timeout, seconds = launch(['xcrun', 'simctl', 'list', 'devices', 'available', '-j'], root, 15, env)
            try:
                available = any(row.get('udid') == target and row.get('isAvailable', True)
                                for rows in json.loads(output)['devices'].values() for row in rows)
            except (ValueError, KeyError, TypeError):
                available = False
            ready = available and code == 0 and not timeout
            observations.append(dict(probe='ios_simulator_availability', role=role,
                                     state='ready' if ready else 'unavailable', exit_status=code,
                                     timed_out=timeout, duration_seconds=seconds,
                                     output_sha256=hashlib.sha256(output.encode()).hexdigest()))
            if not ready:
                return result('device_target_unavailable', 'Recheck the exact pinned simulator; do not substitute another target.')

    for role in device_roles(check, config):
        if not role.startswith('android'):
            continue
        target = config.get('devices', {}).get(role)
        if not target:
            return result('device_target_missing', 'Resolve the available device matrix and pin this role before retrying.')
        command = ['adb', '-s', target, 'shell', 'dumpsys', 'activity', 'processes']
        output, code, timeout, seconds = launch(command, root, 15, env)
        state = instrumentation_state(output) if code == 0 and not timeout else 'unavailable'
        observations.append({'probe': 'android_automation', 'role': role, 'state': state,
                             'exit_status': code, 'timed_out': timeout, 'duration_seconds': seconds,
                             'output_sha256': hashlib.sha256(output.encode()).hexdigest()})
        if state == 'busy':
            return result('device_automation_busy',
                          'Identify the active owner. For your own Appium session, use Appium MCP to end it before this CLI campaign; preserve foreign sessions. Recheck before retrying.')
        if state != 'idle':
            return result('device_automation_unobserved',
                          'Inspect the pinned target and the failed automation observation. Empty or unfamiliar output is not an idle device; repair the observation before retrying.')

    probe = check.get('host_preflight')
    if probe:
        entrypoint, expected = HOST_PROBES[probe]
        command = ['dart', 'run', entrypoint, '--list-scenarios']
        output, code, timeout, seconds = launch(command, root, 120, env)
        # Dart can prepend its native-hook progress without a newline. Keep
        # exact scenario-line matching after removing only that known prefix.
        listing = output
        while listing.startswith('Running build hooks...'):
            listing = listing[len('Running build hooks...'):]
        completed = code == 0 and not timeout and expected in listing.splitlines()
        observations.append({'probe': probe, 'state': 'ready' if completed else 'unavailable',
                             'exit_status': code, 'timed_out': timeout, 'duration_seconds': seconds,
                             'output_sha256': hashlib.sha256(output.encode()).hexdigest()})
        if not completed:
            return result('device_runner_dependencies_unready',
                          'Run this exact no-device scenario listing to diagnose the SDK or native-asset hook. Repair dependencies without changing pinned versions, then retry with a fresh receipt.')
    return {'status': 'PASS', 'checkpoint': 'device_preflight_completed', 'observations': observations,
            'scope': 'Setup only. Campaign-specific peer/provider readiness, artifact identity and restoration remain required.'}
