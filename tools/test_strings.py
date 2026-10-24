#!/usr/bin/env python3
"""Generator regression checks; run with python3 -m unittest discover -s tools -p 'test_*.py'."""
import unittest
from strings import parse_declarations


class StringGeneratorTests(unittest.TestCase):
    def test_computed_extensions_member_access_and_nullable_enum(self):
        declarations = parse_declarations('''
val Str.notice get() = tipRecord().lead
val Str.bullets: String get() = "${result.imported}"
fun Str.local(canton: dev.peringer.limen.data.SwissCanton?) = when (canton) {
  dev.peringer.limen.data.SwissCanton.FR, dev.peringer.limen.data.SwissCanton.TI -> words("en", "fr", "de", "it", "rm")
  else -> ""
}
''')
        self.assertEqual(declarations[0]['value'], 'tipRecord().lead')
        self.assertEqual(declarations[1]['value'], '"\\(result.imported)"')
        self.assertEqual(declarations[2]['params'], [('canton', 'SwissCanton?')])
        self.assertIn('case .fr, .ti:', declarations[2]['value'])

    def test_unknown_syntax_fails_instead_of_partially_generating(self):
        for source in ['val x = "a" - "b"', 'val x get() { return "a" }',
                       'val x: Map = "bad"', 'val x = "${a + b}"',
                       'fun x(role: Role) = if (role != Role.Tenant) "a" else "b"']:
            with self.subTest(source=source), self.assertRaises(SystemExit):
                parse_declarations(source)

    def test_a_count_picks_its_singular_by_number(self):
        declarations = parse_declarations('fun Str.defectCount(n: Int): String = when (lang) {\n  Lang.En -> if (n == 1) "1 defect" else "$n defects"\n  Lang.Fr -> if (n == 1) "1 défaut" else "$n défauts"\n}')
        self.assertEqual(declarations[0]['params'], [('n', 'Int')])
        self.assertIn('case .en: return n == 1 ? "1 defect" : "\\(n) defects"', declarations[0]['value'])

    def test_a_refusal_names_its_reason_and_its_remedy_for_a_whole_library(self):
        declarations = parse_declarations('''
fun Str.archiveFailure(refused: dev.peringer.limen.data.ArchiveRefused?, wholeLibrary: Boolean): String = if (refused == null) archiveFailed else when (refused.reason) {
  dev.peringer.limen.data.ArchiveRefused.Reason.UnreadableRecord -> words("a", "b", "c", "d", "e")
  dev.peringer.limen.data.ArchiveRefused.Reason.DamagedEvidence -> words("for ${refused.record}." + if (wholeLibrary) " More." else "", "b", "c", "d", "e")
}
''')
        self.assertEqual(declarations[0]['params'], [('refused', 'ArchiveRefused?'), ('wholeLibrary', 'Boolean')])
        value = declarations[0]['value']
        self.assertTrue(value.startswith('guard let refused else { return archiveFailed }\n        switch refused.reason {'))
        self.assertIn('case .unreadableRecord: return pick("a", "b", "c", "d", "e")', value)
        self.assertIn('case .damagedEvidence: return pick("for \\(refused.record)." + (wholeLibrary ? " More." : ""), "b", "c", "d", "e")', value)

    def test_collision_property_and_function(self):
        declarations = parse_declarations('val furniture = "word"\nfun furniture(f: Furniture) = when (f) { Furniture.Bed -> furniture }')
        self.assertEqual(declarations[0]['name'], 'furnitureLabel')
        self.assertIn('return furnitureLabel', declarations[1]['value'])


if __name__ == '__main__':
    unittest.main()
