import unittest

from confkit.parse import ParseError, parse_ini


class ParseIniTest(unittest.TestCase):
    def test_reads_sections_and_keys_skipping_comments(self):
        text = "# top\n[db]\nhost = localhost\n; note\nport=5432\n\n[app]\nname = demo\n"
        self.assertEqual(
            parse_ini(text),
            {"db": {"host": "localhost", "port": "5432"}, "app": {"name": "demo"}},
        )

    def test_later_duplicate_key_wins(self):
        self.assertEqual(parse_ini("[a]\nk = 1\nk = 2\n"), {"a": {"k": "2"}})

    def test_key_before_any_section_is_an_error_with_its_line(self):
        with self.assertRaises(ParseError) as caught:
            parse_ini("\nk = 1\n")
        self.assertEqual(caught.exception.line_no, 2)

    def test_line_without_equals_is_an_error(self):
        with self.assertRaises(ParseError):
            parse_ini("[a]\njust words\n")


if __name__ == "__main__":
    unittest.main()
