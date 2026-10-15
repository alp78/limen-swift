#!/usr/bin/env python3
"""Generate the ordered codec from the actual Android serializable constructors.

LIMEN_ANDROID must name the reviewed reference. Unsupported syntax fails generation.
The model remains Swift code; this removes duplicate hand-maintained omission rules.
"""
import argparse
import os
import re
from pathlib import Path
from strings import swift_case

ROOT = Path(__file__).resolve().parent.parent
REFERENCE = Path(os.environ['LIMEN_ANDROID']) / 'app/src/main/java/dev/peringer/limen/data'


def split(text):
    return re.split(r',\s*(?=(?:@|val\s|$))', text.strip())


def constructors():
    result = {}
    for filename in ['Protocol.kt', 'RecordDetails.kt', 'LegalOverlay.kt']:
        text = (REFERENCE / filename).read_text()
        text = re.sub(r'"(?:\\.|[^"\\])*"|/\*[\s\S]*?\*/|//[^\n]*',
                      lambda m: m[0] if m[0].startswith('"') else '', text)
        for match in re.finditer(r'@Serializable\s+data class (\w+)\(', text):
            position, depth, quoted, escaped = match.end(), 1, False, False
            end = position
            while depth:
                c = text[end]
                if quoted:
                    if escaped:
                        escaped = False
                    elif c == '\\':
                        escaped = True
                    elif c == '"':
                        quoted = False
                elif c == '"':
                    quoted = True
                elif c == '(':
                    depth += 1
                elif c == ')':
                    depth -= 1
                end += 1
            fields = []
            for field in split(text[position:end-1]):
                if not field:
                    continue
                mode = 'never' if 'Mode.NEVER' in field else 'always' if 'Mode.ALWAYS' in field else None
                clean = re.sub(r'@[\w.]+\([^)]*\)\s*', '', field).strip()
                parsed = re.fullmatch(r'val (\w+): ([\w?<>, ]+?)(?:\s*=\s*(.*))?', clean, re.S)
                if not parsed:
                    raise SystemExit(f'Unsupported constructor field: {field}')
                name, typ, default = parsed.groups()
                fields.append((name, typ.strip(), default.strip() if default is not None else None, mode))
            result[match[1]] = fields
    return result


SCHEMA = constructors()
NAME = {'Protocol': 'HandoverProtocol'}


def generic(typ):
    match = re.fullmatch(r'(List|Set|Map)<(.+)>', typ)
    if not match:
        return None
    args, start, depth = [], 0, 0
    for i, c in enumerate(match[2]):
        depth += (c == '<') - (c == '>')
        if c == ',' and depth == 0:
            args.append(match[2][start:i].strip())
            start = i + 1
    args.append(match[2][start:].strip())
    return match[1], args


def swift_type(typ):
    g = generic(typ)
    if g:
        return f'OrderedMap<{swift_type(g[1][0])}, {swift_type(g[1][1])}>' if g[0] == 'Map' else f'[{swift_type(g[1][0])}]'
    return {'Long': 'Int64', 'Boolean': 'Bool'}.get(typ, NAME.get(typ, typ))


def default_value(value):
    if value is None:
        return None
    if value == 'null':
        return 'nil'
    if value in ('emptyList()', 'emptySet()'):
        return '[]'
    if value == 'emptyMap()':
        return 'OrderedMap()'
    if re.fullmatch(r'\w+\.\w+', value):
        return '.' + swift_case(value.split('.')[1])
    if re.fullmatch(r'-?\d+|true|false|"(?:\\.|[^"\\])*"|\w+\(\)', value):
        return value
    raise SystemExit(f'Unsupported default: {value}')


def encode(typ, value):
    g = generic(typ)
    if g:
        kind, args = g
        if kind == 'Map':
            key = '$0.key' if args[0] == 'String' else '$0.key.rawValue'
            return f'.object({value}.entries.map {{ ({key}, {encode(args[1], "$0.value")}) }})'
        return f'.array({value}.map {{ {encode(args[0], "$0")} }})'
    if typ.endswith('?'):
        return f'{value}.map {{ {encode(typ[:-1], "$0")} }} ?? .null'
    if typ in SCHEMA:
        return f'write{typ}({value}, d)'
    return {'String': f'.string({value})', 'Boolean': f'.bool({value})',
            'Int': f'.int(Int64({value}))', 'Long': f'.int({value})'}.get(typ, f'.string({value}.rawValue)')


def read_value(typ, value):
    g = generic(typ)
    if g:
        kind, args = g
        if kind == 'Map':
            key = 'name' if args[0] == 'String' else f'try JSONRead.enumValue(name, as: {args[0]}.self)'
            return f'try JSONRead.map({value}) {{ name, value in ({key}, {read_value(args[1], "value")}) }}'
        result = f'try JSONRead.array({value}).map {{ {read_value(args[0], "$0")} }}'
        return '(' + result + ').distinct()' if kind == 'Set' else result
    if typ.endswith('?'):
        return f'try JSONRead.optional({value}) {{ {read_value(typ[:-1], "$0")} }}'
    if typ in SCHEMA:
        return f'try read{typ}({value})'
    method = {'String': 'string', 'Boolean': 'bool', 'Int': 'int32', 'Long': 'int64'}.get(typ)
    return f'try JSONRead.{method}({value})' if method else f'try JSONRead.enumeration({value}, as: {typ}.self)'


def initializer(name, fields):
    required = [f for f in fields if f[2] is None]
    args = []
    for field, typ, _, _ in required:
        unlabeled = (name, field) in [('Party', 'role'), ('KeyCount', 'kind'), ('RoomItem', 'key'),
                                    ('PhotoEvidence', 'file'), ('DeliveryReceipt', 'role'), ('Signature', 'role')]
        args.append(('' if unlabeled else field + ': ') + f'{field}')
    return f'{NAME.get(name, name)}(' + ', '.join(args) + ')'


def codec():
    lines = ['// Generated by tools/schema.py from Android serializable constructors. Do not edit.',
             'import Foundation', '', 'public enum ProtocolJSON {',
             '    public static func encode(_ p: HandoverProtocol, encodeDefaults: Bool) -> JSON { writeProtocol(p, encodeDefaults) }',
             '    public static func decode(_ data: Data) throws -> HandoverProtocol {',
             '        guard data.count <= 8 * 1024 * 1024 else { throw ProtocolJSONError.limit }',
             '        let p = try readProtocol(JSON.parse(data))',
             '        guard (1...2).contains(p.schema) else { throw ProtocolJSONError.unsupported("schema") }',
             '        return p', '    }']
    for name, fields in SCHEMA.items():
        lines += [f'    private static func write{name}(_ v: {NAME.get(name, name)}, _ d: Bool) -> JSON {{',
                  '        var b = ObjectBuilder(encodeDefaults: d)']
        for field, typ, default, mode in fields:
            if default is None or mode == 'always':
                lines.append(f'        b.always("{field}", {encode(typ, "v." + field)})')
            else:
                lines.append(f'        b.put("{field}", v.{field}, default: {default_value(default)}' +
                             (', never: true' if mode == 'never' else '') + f') {{ {encode(typ, "$0")} }}')
        lines += ['        return b.json', '    }', f'    private static func read{name}(_ json: JSON) throws -> {NAME.get(name, name)} {{',
                  '        let r = try JSONRead.object(json, allowed: [' + ', '.join(f'"{f[0]}"' for f in fields) + '])']
        for field, typ, default, _ in fields:
            if default is None:
                lines.append(f'        let {field} = {read_value(typ, "JSONRead.required(r, " + chr(34) + field + chr(34) + ")")}')
        lines.append(f'        var v = {initializer(name, fields)}')
        for field, typ, default, _ in fields:
            if default is not None:
                lines.append(f'        if let value = r["{field}"] {{ v.{field} = {read_value(typ, "value")} }}')
        lines += ['        return v', '    }']
    return '\n'.join(lines + ['}', ''])


def new_models():
    names = ['RecordDetails', 'MeterReading', 'AccessDevice', 'SupportingDocument', 'FollowUp',
             'ReplacementEstimate', 'LegalSnapshot', 'ExportCopy', 'TenantPosition']
    lines = ['// Generated by tools/schema.py from Android constructors. Do not edit.',
             'import Foundation', '',
             'public enum DocumentKind: String, CaseIterable, Hashable, Sendable {',
             '    case lease = "Lease", rentForm = "RentForm", mandate = "Mandate", priorReport = "PriorReport"',
             '    case deposit = "Deposit", delivery = "Delivery", other = "Other"', '}']
    for name in names:
        fields = SCHEMA[name]
        lines += ['', f'public struct {name}: Hashable, Sendable {{']
        for field, typ, default, _ in fields:
            lines.append(f'    public var {field}: {swift_type(typ)}' + (f' = {default_value(default)}' if default is not None else ''))
        params = ', '.join(f'{f}: {swift_type(t)}' + (f' = {default_value(d)}' if d is not None else '') for f, t, d, _ in fields)
        lines.append(f'    public init({params}) {{')
        lines += [f'        self.{f} = {f}' for f, _, _, _ in fields]
        lines += ['    }', '}']
    return '\n'.join(lines + [''])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    check = parser.parse_args().check
    for path, content in [('LimenKit/Sources/JSON/ProtocolJSON.swift', codec()),
                          ('LimenKit/Sources/Model/RecordDetails.swift', new_models())]:
        destination = ROOT / path
        if check:
            if destination.read_text() != content:
                raise SystemExit(f'Generation drift: {path}')
        else:
            destination.write_text(content)
    print(f'{len(SCHEMA)} constructors, {sum(map(len, SCHEMA.values()))} fields')


if __name__ == '__main__':
    main()
