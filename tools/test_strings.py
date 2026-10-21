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
        for source in ['val x = "a" + "b"', 'val x get() { return "a" }',
                       'val x: Map = "bad"', 'val x = "${a + b}"',
                       'fun x(role: Role) = if (role != Role.Tenant) "a" else "b"']:
            with self.subTest(source=source), self.assertRaises(SystemExit):
                parse_declarations(source)

    def test_a_count_picks_its_singular_by_number(self):
        declarations = parse_declarations('fun Str.defectCount(n: Int): String = when (lang) {\n  Lang.En -> if (n == 1) "1 defect" else "$n defects"\n  Lang.Fr -> if (n == 1) "1 défaut" else "$n défauts"\n}')
        self.assertEqual(declarations[0]['params'], [('n', 'Int')])
        self.assertIn('case .en: return n == 1 ? "1 defect" : "\\(n) defects"', declarations[0]['value'])

    def test_collision_property_and_function(self):
        declarations = parse_declarations('val furniture = "word"\nfun furniture(f: Furniture) = when (f) { Furniture.Bed -> furniture }')
        self.assertEqual(declarations[0]['name'], 'furnitureLabel')
        self.assertIn('return furnitureLabel', declarations[1]['value'])


if __name__ == '__main__':
    unittest.main()
