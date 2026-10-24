#!/usr/bin/env python3
"""Turns Android Strings.kt and RecordStrings.kt into the port's Str.swift.

Nothing is retyped: `ui/Strings.kt` in the Android repository holds every word the instrument
speaks in its five languages, as one Kotlin class of `pick(en, fr, de, it, rm)` calls, and this
script reads that class and writes the same class in Swift. A `val` becomes a computed property,
a `fun` over an enum becomes a `switch`, a `Tip(...)` keeps its lead and bullets, and a Kotlin
string template becomes Swift interpolation. Kotlin enum cases (`Role.Tenant`) become the port's
lower camel cases (`.tenant`) by the one rule `swift_case` spells out, which the model follows.

Run whenever the Android strings change: `make strings`.
"""
from __future__ import annotations

import os
import argparse
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
ANDROID = Path(os.environ.get("LIMEN_ANDROID", HERE / ".." / ".." / "ANDROID" / "limen"))
SOURCE = ANDROID / "app" / "src" / "main" / "java" / "dev" / "peringer" / "limen" / "ui" / "Strings.kt"
OUT = HERE / "LimenKit" / "Sources" / "Strings" / "Str.swift"

TYPE_NAMES = {"Int": "Int", "String": "String", "Boolean": "Bool"}


def swift_case(name: str) -> str:
    """`Tenant` to `tenant`, `WCSeat` to `wcSeat`, `AG` to `ag`, `VaudRulv2020` to `vaudRulv2020`."""
    match = re.match(r"^([A-Z]+)(.*)$", name)
    if not match:
        return name
    upper, rest = match.group(1), match.group(2)
    if len(upper) == 1:
        return upper.lower() + rest
    if rest == "":
        return upper.lower()
    return upper[:-1].lower() + upper[-1] + rest


class Parser:
    def __init__(self, text: str, renamed: dict[str, str] | None = None) -> None:
        self.text = text
        self.pos = 0
        # Kotlin lets a property and a function share a name (`furniture` the word, `furniture(f)`
        # the lookup); Swift does not, so the property side is renamed wherever it is referenced.
        self.renamed = renamed or {}

    def skip_ws(self) -> None:
        while self.pos < len(self.text):
            ch = self.text[self.pos]
            if ch in " \t\r\n":
                self.pos += 1
            elif self.text.startswith("//", self.pos):
                end = self.text.find("\n", self.pos)
                self.pos = len(self.text) if end < 0 else end + 1
            elif self.text.startswith("/*", self.pos):
                end = self.text.find("*/", self.pos)
                self.pos = len(self.text) if end < 0 else end + 2
            else:
                return

    def peek(self, s: str) -> bool:
        self.skip_ws()
        return self.text.startswith(s, self.pos)

    def expect(self, s: str) -> None:
        self.skip_ws()
        if not self.text.startswith(s, self.pos):
            raise SystemExit(f"expected {s!r} at {self.pos}: {self.text[self.pos:self.pos + 60]!r}")
        self.pos += len(s)

    def identifier(self) -> str:
        self.skip_ws()
        match = re.match(r"[A-Za-z_][A-Za-z0-9_]*", self.text[self.pos:])
        if not match:
            raise SystemExit(f"expected identifier at {self.pos}: {self.text[self.pos:self.pos + 60]!r}")
        self.pos += match.end()
        return match.group(0)

    def dotted(self) -> str:
        name = self.identifier()
        while self.peek("."):
            self.pos += 1
            name += "." + self.identifier()
        return name

    def string(self) -> str:
        """A Kotlin string literal, returned as a Swift string literal (quotes included)."""
        self.expect('"')
        out = ['"']
        while True:
            ch = self.text[self.pos]
            if ch == '"':
                self.pos += 1
                break
            if ch == "\\":
                nxt = self.text[self.pos + 1]
                self.pos += 2
                if nxt == "'":
                    out.append("'")
                elif nxt == "$":
                    out.append("$")
                elif nxt == '"':
                    out.append('\\"')
                elif nxt in "nrtb\\":
                    out.append("\\" + nxt)
                else:
                    raise SystemExit(f"unknown escape \\{nxt} at {self.pos}")
                continue
            if ch == "$":
                if self.text[self.pos + 1] == "{":
                    end = self.text.index("}", self.pos)
                    expr = self.text[self.pos + 2:end]
                    self.pos = end + 1
                    nested = Parser(expr, self.renamed)
                    # One operand: an interpolation that computes is still a generator gap.
                    translated = nested.operand()
                    nested.skip_ws()
                    if nested.pos != len(expr):
                        raise SystemExit(f"unsupported interpolation: {expr!r}")
                    out.append("\\(" + translated + ")")
                    continue
                match = re.match(r"[A-Za-z_][A-Za-z0-9_]*", self.text[self.pos + 1:])
                if match:
                    self.pos += 1 + match.end()
                    out.append("\\(" + self.renamed.get(match.group(0), match.group(0)) + ")")
                    continue
            if ch == "\\":
                out.append("\\\\")
            else:
                out.append(ch)
            self.pos += 1
        out.append('"')
        return "".join(out)

    def arguments(self) -> list[str]:
        self.expect("(")
        args: list[str] = []
        while True:
            self.skip_ws()
            if self.peek(")"):
                self.pos += 1
                return args
            args.append(self.expression())
            self.skip_ws()
            if self.peek(","):
                self.pos += 1
            elif self.peek(")"):
                self.pos += 1
                return args
            else:
                raise SystemExit(f"bad argument list at {self.pos}: {self.text[self.pos:self.pos + 40]!r}")

    def expression(self) -> str:
        # Since 1.2.7 a sentence can be a string joined by `+` to a conditional tail (the remedy a
        # refused backup names only for a whole library): each piece is an operand on its own, and
        # a conditional operand is parenthesised, as Swift's `+` binds tighter than `?:`.
        pieces = [self.operand()]
        while self.peek("+"):
            self.pos += 1
            pieces.append(self.operand())
        if len(pieces) == 1:
            return pieces[0]
        return " + ".join(f"({piece})" if " ? " in piece else piece for piece in pieces)

    def operand(self) -> str:
        self.skip_ws()
        if self.peek('"'):
            return self.string()
        if self.peek("when"):
            return self.when()
        if self.text.startswith(("if (", "if("), self.pos):
            return self.if_else()
        name = self.dotted()
        if self.peek("("):
            args = self.arguments()
            result = self.call(name, args)
        else:
            result = self.reference(name)
        # Member access after a call: tipClocks().bullets
        while self.peek("."):
            self.pos += 1
            member = self.identifier()
            result += "." + member
        return result

    def call(self, name: str, args: list[str]) -> str:
        if name in ("pick", "words"):
            return "pick(" + ", ".join(args) + ")"
        if name == "listOf":
            return "[" + ", ".join(args) + "]"
        if name == "Tip":
            if len(args) == 1:
                return f"Tip(lead: {args[0]})"
            return f"Tip(lead: {args[0]}, bullets: {args[1]})"
        return name + "(" + ", ".join(args) + ")"

    def reference(self, name: str) -> str:
        parts = name.split(".")
        if len(parts) >= 2 and parts[-2][0].isupper():
            return "." + swift_case(parts[-1])
        return self.renamed.get(name, name)

    def if_else(self) -> str:
        # The two shapes the Kotlin strings use besides `when`: `if (param == Enum.CASE) a else b`,
        # a ternary over an enum case in Swift, and since 1.2.6 `if (n == 1) a else b`, a ternary
        # over a number (the singular of a count). Anything else here is a generator gap, and it
        # stops rather than guessing.
        self.expect("if")
        self.expect("(")
        subject = self.identifier()
        self.skip_ws()
        if self.peek(")"):
            # `if (wholeLibrary) a else b`: a Boolean parameter read as it is, since 1.2.7.
            condition = subject
        else:
            if not self.peek("=="):
                raise SystemExit(f"if without == at {self.pos}: {self.text[self.pos:self.pos + 40]!r}")
            self.pos += 2
            self.skip_ws()
            literal = re.match(r"\d+", self.text[self.pos:])
            if literal:
                self.pos += literal.end()
                case = literal.group(0)
            elif self.peek("null"):
                # `if (refused == null) a else b`: an optional parameter absent, since 1.2.7.
                self.pos += 4
                case = "nil"
            else:
                case = self.reference(self.dotted())
            condition = f"{subject} == {case}"
        self.expect(")")
        then = self.expression()
        self.skip_ws()
        self.expect("else")
        otherwise = self.expression()
        if otherwise.startswith("switch"):
            # The else branch is a whole `when`: statements, since a switch is no expression here,
            # and an optional subject is unwrapped for the switch that reads it.
            if condition.endswith(" == nil"):
                return f"guard let {subject} else {{ return {then} }}\n        {otherwise}"
            return f"if {condition} {{ return {then} }}\n        {otherwise}"
        return f"{condition} ? {then} : {otherwise}"

    def when(self) -> str:
        self.expect("when")
        self.expect("(")
        subject = self.dotted()
        self.expect(")")
        self.expect("{")
        branches: list[tuple[str, str]] = []
        while True:
            self.skip_ws()
            if self.peek("}"):
                self.pos += 1
                break
            cases = [self.dotted()]
            while self.peek(","):
                self.expect(",")
                cases.append(self.dotted())
            self.expect("->")
            value = self.expression()
            case = "default" if cases == ["else"] else "case " + ", ".join("." + swift_case(c.split(".")[-1]) for c in cases)
            branches.append((case, value))
            if self.peek(";"):
                self.expect(";")
        lines = [f"switch {subject} {{"]
        for case, value in branches:
            lines.append(f"        {case}: return {value}")
        lines.append("        }")
        return "\n".join(lines)


def collisions(body: str) -> dict[str, str]:
    vals = set(re.findall(r"^\s*(?:private\s+)?val\s+(\w+)\b", body, re.M))
    funs = set(re.findall(r"^\s*(?:private\s+)?fun\s+(\w+)\s*\(", body, re.M))
    return {name: name + "Label" for name in vals & funs}


def parse_declarations(body: str) -> list[dict]:
    renamed = collisions(body)
    parser = Parser(body, renamed)
    declarations: list[dict] = []
    while True:
        parser.skip_ws()
        if parser.pos >= len(body):
            break
        private = False
        if parser.peek("private") or parser.peek("internal"):
            parser.identifier()
            private = True
        if parser.peek("val"):
            parser.expect("val")
            name = parser.identifier()
            if name == "Str" and parser.peek("."):
                parser.expect(".")
                name = parser.identifier()
            declared_type = None
            if parser.peek(":"):
                parser.expect(":")
                declared_type = parser.dotted()
                if declared_type not in ("String", "Tip"):
                    raise SystemExit(f"unsupported property type: {declared_type}")
            if parser.peek("get"):
                parser.expect("get")
                parser.expect("(")
                parser.expect(")")
            parser.expect("=")
            value = parser.expression()
            declarations.append({"kind": "val", "name": renamed.get(name, name), "private": private, "value": value, "type": declared_type})
        elif parser.peek("fun"):
            parser.expect("fun")
            name = parser.identifier()
            if name == "Str" and parser.peek("."):
                parser.expect(".")
                name = parser.identifier()
            parser.expect("(")
            params: list[tuple[str, str]] = []
            while not parser.peek(")"):
                pname = parser.identifier()
                parser.expect(":")
                ptype = parser.dotted()
                if parser.peek("?"):
                    parser.expect("?")
                    ptype += "?"
                params.append((pname, ptype.split(".")[-1]))
                if parser.peek(","):
                    parser.pos += 1
            parser.expect(")")
            if parser.peek(":"):
                parser.expect(":")
                parser.dotted()
            if name in ("pick", "words"):
                # The selector itself is hand-written in Swift; skip its Kotlin body.
                parser.expect("=")
                parser.when()
                continue
            parser.expect("=")
            value = parser.expression()
            declarations.append({"kind": "fun", "name": name, "private": private, "params": params, "value": value})
        else:
            raise SystemExit(f"unexpected declaration at {parser.pos}: {body[parser.pos:parser.pos + 60]!r}")
    return declarations


def main() -> None:
    arguments = argparse.ArgumentParser()
    arguments.add_argument("--check", action="store_true")
    args = arguments.parse_args()
    text = SOURCE.read_text(encoding="utf-8")
    start = text.index("class Str(val lang: Lang) {")
    body_start = text.index("{", start) + 1
    # The class runs to the end of the file; its closing brace is the last one.
    body_end = text.rindex("}")
    declarations = parse_declarations(text[body_start:body_end])
    core_count = len(declarations)
    extra = SOURCE.with_name("RecordStrings.kt").read_text(encoding="utf-8")
    extensions = parse_declarations(extra[extra.index("internal fun Str.words"):])
    declared_extensions = re.findall(r"^\s*(?:internal\s+)?(?:val|fun)\s+Str\.(\w+)", extra, re.M)
    if len(extensions) != len([name for name in declared_extensions if name != "words"]):
        raise SystemExit("RecordStrings.kt declaration coverage mismatch")
    declarations += extensions
    names = [d["name"] for d in declarations]
    if len(names) != len(set(names)):
        raise SystemExit("Duplicate generated member")
    overrides = json.loads((HERE / "tools" / "ios-strings.json").read_text())
    for name, translations in overrides.items():
        if name not in names or len(translations) != 5:
            raise SystemExit(f"Invalid iOS override: {name}")
        declaration = declarations[names.index(name)]
        declaration["value"] = "pick(" + ", ".join(Parser(json.dumps(t, ensure_ascii=False)).string() for t in translations) + ")"

    lines = [
        "// Generated by tools/strings.py from Android Strings.kt, RecordStrings.kt and ios-strings.json. Do not edit.",
        "//",
        "// Every word the instrument speaks, in all five languages at once. German follows Swiss",
        "// usage, ss and never the eszett. Legal terms follow each language's own canon (etat des",
        "// lieux, Uebergabeprotokoll, verbale di consegna), not translations of one another.",
        "",
        "// swiftlint:disable all",
        "",
        "public struct Str: Sendable {",
        "    public let lang: Lang",
        "",
        "    public init(_ lang: Lang) { self.lang = lang }",
        "",
        "    private func pick(_ en: String, _ fr: String, _ de: String, _ it: String, _ rm: String) -> String {",
        "        switch lang {",
        "        case .en: return en",
        "        case .fr: return fr",
        "        case .de: return de",
        "        case .it: return it",
        "        case .rm: return rm",
        "        }",
        "    }",
        "",
    ]
    for d in declarations:
        access = "private" if d["private"] else "public"
        value = d["value"]
        if d["kind"] == "val":
            rtype = d.get("type") or ("[String]" if value.startswith("[") or value.endswith(".bullets") else "String")
            lines.append(f"    {access} var {d['name']}: {rtype} {{ {value} }}")
        else:
            rtype = "Tip" if value.startswith("Tip(") else "String"
            params = ", ".join(f"_ {p}: {TYPE_NAMES.get(t, t)}" for p, t in d["params"])
            if value.startswith(("switch", "if ", "guard ")):
                lines.append(f"    {access} func {d['name']}({params}) -> {rtype} {{")
                lines.append("        " + value)
                lines.append("    }")
            else:
                lines.append(f"    {access} func {d['name']}({params}) -> {rtype} {{ {value} }}")
    lines.append("}")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    generated = "\n".join(lines) + "\n"
    if args.check:
        if OUT.read_text(encoding="utf-8") != generated:
            raise SystemExit("Generated strings have drifted; run make strings with LIMEN_ANDROID set")
    else:
        OUT.write_text(generated, encoding="utf-8")
    print(f"{len(declarations)} declarations ({core_count} core, {len(extensions)} extensions), {len(overrides)} iOS overrides")


if __name__ == "__main__":
    main()
