import unittest

from note_gui import NoteEvent, parse_note_line


class ParseNoteLineTests(unittest.TestCase):
    def test_valid_csv_line(self) -> None:
        self.assertEqual(parse_note_line("49,A4,440.00\n"), NoteEvent(49, "A4", 440.0))

    def test_ready_line_is_ignored(self) -> None:
        self.assertIsNone(parse_note_line("READY,note_uart_app,115200\n"))

    def test_malformed_lines_are_ignored(self) -> None:
        self.assertIsNone(parse_note_line(""))
        self.assertIsNone(parse_note_line("49,A4"))
        self.assertIsNone(parse_note_line("not-a-key,A4,440.00"))
        self.assertIsNone(parse_note_line("89,C8,4186.01"))
        self.assertIsNone(parse_note_line("49,A4,-1.00"))


if __name__ == "__main__":
    unittest.main()
