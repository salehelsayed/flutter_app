"""Join existing iOS payload XCTest logs through verified artifact hashes.

This adapter launches nothing. Only exact source-declared selectors and counts
leave the private capture directory; filenames and diagnostic text stay local.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re

CAPABILITY = 'notifications.ios_payload_fast_path'
FORMAT = 'ios_payload_automation_receipts_v1'
PHASES = (
    ('fast-path', 'automationReceiptSha256', 'runId'),
    ('recovery', 'recoveryAutomationReceiptSha256', 'recoveryRunId'),
    ('retry', 'retryAutomationReceiptSha256', 'retryRunId'),
)


def validate_specs(specs):
    if not isinstance(specs, dict):
        return ['Native XCTest receipt declarations must be an object']
    errors = []
    for capability, spec in specs.items():
        if (capability != CAPABILITY or not isinstance(spec, dict) or
                set(spec) != {'format', 'counts'} or spec.get('format') != FORMAT):
            errors.append('Unknown native XCTest receipt producer')
            continue
        counts = spec['counts']
        if (not isinstance(counts, dict) or not counts or
                any(not isinstance(name, str) or
                    not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*/test[A-Za-z0-9_]+', name) or
                    type(count) is not int or count <= 0
                    for name, count in counts.items())):
            errors.append('Invalid native XCTest receipt selector counts')
    return errors


def _bytes(path, scope):
    path = Path(path)
    if (not path.resolve().is_relative_to(scope.resolve()) or
            not path.is_file() or path.stat().st_size > 64 * 1024 * 1024):
        raise ValueError('Unbound or oversized native receipt member')
    return path.read_bytes()


def _digest(data):
    return hashlib.sha256(data).hexdigest()


def _verified_payload_logs(root, verdict):
    scope = Path(root) / 'build/sims/proofs' / CAPABILITY
    envelope = verdict['artifactEvidence']
    artifact_path = Path(envelope['path'])
    if not artifact_path.is_absolute():
        artifact_path = Path(root) / artifact_path
    raw = _bytes(artifact_path, scope)
    if _digest(raw) != envelope['sha256']:
        raise ValueError('Changed native receipt parent artifact')
    artifact = json.loads(raw)
    if (artifact['capabilityId'] != CAPABILITY or
            artifact['schema'] != 'mknoon.sims.proof.v1'):
        raise ValueError('Wrong native receipt parent artifact')
    logs = []
    capture_parents = set()
    for phase, digest_key, run_key in PHASES:
        expected = artifact[digest_key]
        matches = []
        for path in scope.glob('capture-*/' + phase + '/automation_receipt.json'):
            receipt_bytes = _bytes(path, scope)
            if _digest(receipt_bytes) == expected:
                matches.append((path, json.loads(receipt_bytes)))
        if len(matches) != 1:
            raise ValueError('No unique hash-bound native phase receipt')
        path, receipt = matches[0]
        capture_parents.add(path.parent.parent.resolve())
        if receipt['runId'] != artifact[run_key]:
            raise ValueError('Native receipt phase run mismatch')
        log_bytes = _bytes(path.parent / 'ui-automation.redacted.log', scope)
        if _digest(log_bytes) != receipt['evidenceSha256']['uiAutomationLog']:
            raise ValueError('Changed native XCTest log')
        logs.append(log_bytes.decode('utf-8'))
    if len(capture_parents) != 1:
        raise ValueError('Native phase receipts came from different captures')
    return '\n'.join(logs)


def collect(root, report, attempt, specs):
    """Return typed, capability-scoped method receipts, never parent-only PASS."""
    from full_suite_adapters import native_xctest_receipts
    if validate_specs(specs):
        raise ValueError('Invalid native XCTest receipt declarations')
    results = []
    for capability, spec in specs.items():
        verdicts = [v for v in report.get('verdicts', [])
                    if v.get('capabilityId') == capability]
        status, checkpoint, reason = 'NOT RUN', 'native_capability_not_executed', None
        observed = None
        if len(verdicts) == 1:
            verdict = verdicts[0]
            if verdict.get('status') in ('FAIL', 'BLOCKED', 'NOT RUN'):
                status = verdict['status']
            elif not attempt.get('report_verification_observed'):
                status, checkpoint = 'BLOCKED', 'native_report_unverified'
            elif (verdict.get('status') == 'N/A' and
                  verdict.get('reason') == 'target_unavailable_by_project_policy'):
                status, reason = 'N/A', 'target_unavailable_by_project_policy'
            elif verdict.get('status') == 'PASS':
                try:
                    observed = native_xctest_receipts(
                        _verified_payload_logs(root, verdict), spec['counts'])
                except (OSError, ValueError, KeyError, TypeError, UnicodeError):
                    observed = None
                status = 'PASS' if observed is not None else 'BLOCKED'
                checkpoint = ('native_xctest_hash_chain_verified' if observed is not None
                              else 'native_xctest_evidence_incomplete')
        for selector, count in sorted(spec['counts'].items()):
            results.append(dict(id='xctest:' + selector, capability=capability,
                status=status, checkpoint=checkpoint,
                counts=dict(passed=count if status == 'PASS' else 0, failed=0, skipped=0),
                **({'reason': reason} if reason else {})))
    return results
