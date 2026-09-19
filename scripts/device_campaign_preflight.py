"""Small setup checks for existing campaigns; never drives or repairs a device.

Appium MCP owns exploratory UI work. Existing protocol campaigns keep their
assertions, and must receive exclusive UI ownership before they start.
"""
from contextlib import contextmanager
import fcntl
import hashlib
import os
from pathlib import Path
import re
import stat


# These entry points return before device work with --list-scenarios. Keeping
# the commands here prevents a config typo from accidentally running a journey.
HOST_PROBES = {
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
    return check.get('device_roles', sorted(config.get('devices', {})) if check.get('sims_mode')
                     else ['android_physical', 'android_emulator'])


def validate_metadata(check):
    errors = []
    probe = check.get('host_preflight')
    if probe is not None and (not isinstance(probe, str) or probe not in HOST_PROBES):
        errors.append('Unknown safe host preflight')
    if check.get('kind') in ('sims', 'legacy') and (check.get('device_roles') or check.get('sims_mode')):
        if check.get('ui_driver') != 'existing_campaign' or not isinstance(check.get('ui_driver_reason'), str) or not check['ui_driver_reason'].strip():
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
        completed = code == 0 and not timeout and expected in output.splitlines()
        observations.append({'probe': probe, 'state': 'ready' if completed else 'unavailable',
                             'exit_status': code, 'timed_out': timeout, 'duration_seconds': seconds,
                             'output_sha256': hashlib.sha256(output.encode()).hexdigest()})
        if not completed:
            return result('device_runner_dependencies_unready',
                          'Run this exact no-device scenario listing to diagnose the SDK or native-asset hook. Repair dependencies without changing pinned versions, then retry with a fresh receipt.')
    return {'status': 'PASS', 'checkpoint': 'device_preflight_completed', 'observations': observations,
            'scope': 'Setup only. Campaign-specific peer/provider readiness, artifact identity and restoration remain required.'}
