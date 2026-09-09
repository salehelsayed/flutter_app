#!/usr/bin/env python3
"""Regenerate app diagnostic vocabularies from schema_v1.json, or check parity."""

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'tool/app_diagnostics/schema_v1.json'
FIELDS = (
    'required', 'optional', 'uuidFields', 'feature', 'stage', 'outcome',
    'reason', 'booleanValues', 'integerValues', 'hashValues',
)


def quoted(values):
    return ', '.join(json.dumps(value) for value in values)


def dart_value(value, indent=0, prefix=''):
    """Keep the schema's existing 80-column Dart constant layout deterministic."""
    if isinstance(value, dict):
        lines = [prefix + '{']
        for key, child in value.items():
            entry = dart_value(child, indent + 2,
                               ' ' * (indent + 2) + json.dumps(key) + ': ')
            entry[-1] += ','
            lines.extend(entry)
        return lines + [' ' * indent + '}']
    if isinstance(value, list):
        inline = prefix + '[' + quoted(value) + ']'
        if len(inline) + 1 <= 80:
            return [inline]
        return [prefix + '['] + [
            ' ' * (indent + 2) + json.dumps(item) + ',' for item in value
        ] + [' ' * indent + ']']
    return [prefix + json.dumps(value)]


def outputs():
    canonical = SOURCE.read_text()
    schema = json.loads(canonical)
    swift = [
        'import Foundation', '',
        '// Generated from tool/app_diagnostics/schema_v1.json; verified by parity tests.',
        'internal enum MknoonAppDiagnosticSchema {',
    ]
    kotlin = [
        'package com.mknoon.app.diagnostics', '',
        '// Generated from tool/app_diagnostics/schema_v1.json; verified by parity tests.',
        'internal object MknoonAppDiagnosticSchema {',
    ]
    for field in FIELDS:
        values = quoted(schema[field])
        swift.append(f'  static let {field}: Set<String> = [{values}]')
        kotlin.append(f'    val {field} = setOf({values})')
    swift.append('  static let enumValues: [String: Set<String>] = [')
    kotlin.append('    val enumValues = mapOf(')
    entries = list(schema['enumValues'].items())
    for index, (field, options) in enumerate(entries):
        suffix = ',' if index < len(entries) - 1 else ''
        key, values = json.dumps(field), quoted(options)
        swift.append(f'    {key}: [{values}]{suffix}')
        kotlin.append(f'        {key} to setOf({values}){suffix}')
    swift.extend(['  ]', '}'])
    kotlin.extend(['    )', '}'])
    return {
        'lib/core/diagnostics/app_diagnostic_schema.dart':
            '// Generated from tool/app_diagnostics/schema_v1.json.\n'
            + '\n'.join(dart_value(schema,
                                     prefix='const Map<String, dynamic> appDiagnosticSchemaV1 = '))
            + ';\n',
        'ios/Runner/MknoonAppDiagnosticSchema.swift': '\n'.join(swift) + '\n',
        'android/app/src/main/kotlin/com/mknoon/app/diagnostics/MknoonAppDiagnosticSchema.kt':
            '\n'.join(kotlin) + '\n',
        'go-relay-server/app_diagnostics_schema_v1.json': canonical,
        'docker-ws/app_diagnostics_schema_v1.json': canonical,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Fail if generated files differ.')
    args = parser.parse_args()
    changed = []
    for name, expected in outputs().items():
        path = ROOT / name
        if path.exists() and path.read_text() == expected:
            continue
        changed.append(name)
        if not args.check:
            path.write_text(expected)
    if changed:
        print(('Out of date: ' if args.check else 'Generated: ') + ', '.join(changed))
    else:
        print('App diagnostic schema copies match the canonical source.')
    return 1 if args.check and changed else 0


if __name__ == '__main__':
    raise SystemExit(main())
