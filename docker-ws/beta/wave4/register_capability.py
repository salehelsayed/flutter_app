#!/usr/bin/env python3
"""Register one production SIMS capability in every manifest a module needs.

Usage: register_capability.py <spec.json> [--root <checkout>]

The spec gives: check (selection check id), capability, runner, test_glob,
boundary, limitations, assertions, proof_boundary, families, device_roles,
resources (device resource names), target_capabilities, build_profile,
artifact_validator, ui_driver_reason, maestro_flows, discovery_reason, reason,
timeout_seconds. Each JSON file is edited only if a json round trip keeps it
byte-identical, so its formatting is preserved. Already-present entries are
left alone (idempotent).
"""
import json
import pathlib
import sys

spec = json.load(open(sys.argv[1]))
root = pathlib.Path(sys.argv[sys.argv.index('--root') + 1]) if '--root' in sys.argv else pathlib.Path('.')


_ascii = {}


def load(path):
    raw = (root / path).read_text()
    data = json.loads(raw)
    for ascii_only in (False, True):
        if json.dumps(data, indent=2, ensure_ascii=ascii_only) + '\n' == raw:
            _ascii[path] = ascii_only
            return data
    raise AssertionError(f'{path} would be reformatted')


def save(path, data):
    (root / path).write_text(json.dumps(data, indent=2, ensure_ascii=_ascii[path]) + '\n')


runner = spec['runner']
cap_id = spec['capability']
check = spec['check']

# 1. critical_features.json: append the capability at the end of the capabilities array.
cf = load('tool/sims/critical_features.json')
caps = cf['capabilities']
index = next((i for i, c in enumerate(caps) if c['id'] == cap_id), None)
if index is None:
    profile = spec['build_profile']
    caps.append({
        'id': cap_id,
        'owner': 'reliability',
        'proofBoundary': spec['proof_boundary'],
        'assertions': spec['assertions'],
        'lane': 'reliability',
        'modes': ['major', 'full'],
        'families': spec['families'],
        'required': True,
        'command': ['dart', 'run', runner],
        'buildProfile': profile,
        'dependencies': [f'build.{profile}'],
        'resources': [{'name': f'build:{profile}', 'access': 'read'}]
        + [{'name': r, 'access': 'exclusive'} for r in spec['resources']]
        + [{'name': f'artifact:{cap_id.replace(".", "-").replace("_", "-")}', 'access': 'write'}],
        'targetCapabilities': spec['target_capabilities'],
        'allowedNaReason': 'target_unavailable_by_project_policy',
        'artifactRequired': True,
        'artifactValidator': spec['artifact_validator'],
        'automationReady': True,
        'active': True,
        'declaredBuildException': False,
    })
    index = len(caps) - 1
    save('tool/sims/critical_features.json', cf)

# 2. selection.json: check entry, production patterns, checks list, ownership.
sel = load('tool/testing/selection.json')


def find_lists(obj, needle, path=()):
    """Yield (container, key) of string lists that contain needle."""
    if isinstance(obj, dict):
        for k, v in obj.items():
            if isinstance(v, list) and needle in v:
                yield obj, k
            yield from find_lists(v, needle, path + (k,))
    elif isinstance(obj, list):
        for v in obj:
            yield from find_lists(v, needle, path)


checks_map = None
for container, key in [(sel, k) for k in sel]:
    pass


def find_check_map(obj):
    if isinstance(obj, dict):
        if 'production-routing' in obj and isinstance(obj['production-routing'], dict) and obj['production-routing'].get('kind') == 'sims':
            return obj
        for v in obj.values():
            r = find_check_map(v)
            if r is not None:
                return r
    elif isinstance(obj, list):
        for v in obj:
            r = find_check_map(v)
            if r is not None:
                return r
    return None


check_map = find_check_map(sel)
assert check_map is not None, 'check map not found'
if check not in check_map:
    entry = {
        'kind': 'sims',
        'capability': cap_id,
        'boundary': spec['boundary'],
        'timeout_seconds': spec.get('timeout_seconds', 7200),
        'estimated_seconds': None,
        'requirements': (['dart', 'flutter', 'xcrun'] if spec.get('platform') == 'ios'
                         else ['dart', 'flutter', 'adb'] + (['maestro'] if spec.get('maestro_flows') else [])),
        'device_roles': spec['device_roles'],
        'references': ['tool/sims/critical_features.json'],
        'investigate': ['lib/debug/production_journeys'],
        'limitations': spec['limitations'],
    }
    if spec.get('platform') != 'ios':
        entry['disposable_android_package'] = 'com.mknoon.sims.connectivity'
    if spec.get('maestro_flows'):
        entry['ui_driver'] = 'maestro'
        entry['ui_driver_reason'] = spec['ui_driver_reason']
        entry['maestro_flows'] = spec['maestro_flows']
    else:
        entry['ui_driver'] = 'existing_campaign'
        entry['ui_driver_reason'] = spec['ui_driver_reason']
    entry['host_preflight'] = check
    # Insert right after production-routing to keep related checks together.
    items = list(check_map.items())
    pos = [k for k, _ in items].index('production-routing') + 1
    items.insert(pos, (check, entry))
    check_map.clear()
    check_map.update(items)

for container, key in list(find_lists(sel, 'integration_test/scripts/run_production_routing.dart')):
    lst = container[key]
    for value in [runner, spec['test_glob']]:
        if value and value not in lst:
            lst.insert(lst.index('integration_test/scripts/run_production_routing.dart') + 1, value)
for container, key in list(find_lists(sel, 'production-routing')):
    lst = container[key]
    if check not in lst:
        lst.insert(lst.index('production-routing') + 1, check)


def find_ownership(obj):
    if isinstance(obj, list):
        if any(isinstance(v, dict) and v.get('capability') == 'production.routing_smoke' and 'patterns' in v for v in obj):
            return obj
        for v in obj:
            r = find_ownership(v)
            if r is not None:
                return r
    elif isinstance(obj, dict):
        for v in obj.values():
            r = find_ownership(v)
            if r is not None:
                return r
    return None


own = find_ownership(sel)
assert own is not None, 'ownership list not found'
if not any(isinstance(v, dict) and v.get('capability') == cap_id for v in own):
    pos = next(i for i, v in enumerate(own) if isinstance(v, dict) and v.get('capability') == 'production.routing_smoke') + 1
    own.insert(pos, {
        'owner': 'full-sims-major',
        'capability': cap_id,
        'patterns': [runner] + spec.get('maestro_flows', []),
        'reason': spec['reason'],
    })
save('tool/testing/selection.json', sel)

# 3. runtime_roots.json: external entrypoint bound to the manifest command.
rr = load('tool/runtime_roots/runtime_roots.json')
ee = rr['externalEntrypoints']
if not any(e['path'] == runner for e in ee):
    pos = next(i for i, e in enumerate(ee) if e['path'] == 'integration_test/scripts/run_production_routing.dart') + 1
    ee.insert(pos, {
        'path': runner,
        'owner': 'QA / production bootstrap migration',
        'reason': 'Additive production-main journey; the central Sims manifest owns the exact host invocation and the application owns service composition.',
        'condition': 'Retain alongside the original harness; retirement requires approved equivalent assertion and device evidence.',
        'seedsTooling': True,
        'evidence': [{
            'kind': 'json-value',
            'source': 'tool/sims/critical_features.json',
            'keyPath': f'capabilities.{index}.command.2',
            'value': runner,
        }],
    })
    save('tool/runtime_roots/runtime_roots.json', rr)

# 4. discovery script case.
disc = root / 'scripts/check_reliability_simulation_discovery.sh'
text = disc.read_text()
if f'    {runner})' not in text:
    anchor = '    integration_test/scripts/run_production_routing.dart)\n'
    assert text.count(anchor) == 1
    block = (f'    {runner})\n'
             f'      record "support" "$path" "support" "{spec["discovery_reason"]}"\n'
             '      return\n'
             '      ;;\n')
    disc.write_text(text.replace(anchor, block + anchor))

# 5. preflight host probe.
pre = root / 'scripts/device_campaign_preflight.py'
text = pre.read_text()
if f"'{check}':" not in text:
    anchor = "    'production-routing': ('integration_test/scripts/run_production_routing.dart', 'production.routing_smoke'),\n"
    assert text.count(anchor) == 1
    pre.write_text(text.replace(anchor, f"    '{check}': ('{runner}', '{cap_id}'),\n" + anchor))

print(f'registered {cap_id} as capability {index}, check {check}')
