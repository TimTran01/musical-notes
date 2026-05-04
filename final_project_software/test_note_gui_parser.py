import random
import unittest

from note_gui import (
    DEFAULT_SAMPLE_COUNT,
    GeneratedSampleSet,
    LoadResponse,
    NoteEvent,
    generate_random_sample_set,
    generate_sample_set_for_key,
    parse_key_selection,
    parse_load_response,
    parse_note_line,
    piano_key_frequency_hz,
    piano_key_name,
    sample_checksum,
)
from pure_sine_note_test import generate_pure_sine_sample_set, pure_sine_samples


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


class LoadResponseTests(unittest.TestCase):
    def test_loaded_response(self) -> None:
        self.assertEqual(
            parse_load_response("LOADED,4096,1234ABCD\n"),
            LoadResponse(True, "LOADED,4096,1234ABCD"),
        )

    def test_error_response(self) -> None:
        self.assertEqual(
            parse_load_response("ERROR,load,checksum\n"),
            LoadResponse(False, "ERROR,load,checksum"),
        )

    def test_other_lines_are_ignored(self) -> None:
        self.assertIsNone(parse_load_response("49,A4,440.00\n"))


class SampleGenerationTests(unittest.TestCase):
    def test_key_mapping(self) -> None:
        self.assertEqual(piano_key_name(1), "A0")
        self.assertEqual(piano_key_name(49), "A4")
        self.assertAlmostEqual(piano_key_frequency_hz(49), 440.0)

    def test_checksum_uses_24_bit_words(self) -> None:
        self.assertEqual(sample_checksum(("000001", "FFFFFF")), 0x01000000)

    def test_random_sample_set_shape(self) -> None:
        sample_set = generate_random_sample_set(random.Random(615))
        self.assertIsInstance(sample_set, GeneratedSampleSet)
        self.assertTrue(1 <= sample_set.key <= 88)
        self.assertEqual(len(sample_set.words), DEFAULT_SAMPLE_COUNT)
        self.assertTrue(all(len(word) == 6 for word in sample_set.words))
        self.assertEqual(sample_set.checksum, sample_checksum(sample_set.words))

    def test_random_sample_set_can_use_explicit_key_list(self) -> None:
        sample_set = generate_random_sample_set(random.Random(615), allowed_keys=(49, 80))
        self.assertIn(sample_set.key, (49, 80))

    def test_selected_key_sample_set(self) -> None:
        sample_set = generate_sample_set_for_key(80, random.Random(615))
        self.assertEqual(sample_set.key, 80)
        self.assertEqual(sample_set.note, "E7")
        self.assertAlmostEqual(sample_set.frequency_hz, piano_key_frequency_hz(80))
        self.assertEqual(len(sample_set.words), DEFAULT_SAMPLE_COUNT)

    def test_selected_key_rejects_invalid_key(self) -> None:
        with self.assertRaises(ValueError):
            generate_sample_set_for_key(89, random.Random(615))

    def test_pure_sine_sample_set(self) -> None:
        sample_set = generate_pure_sine_sample_set(5)
        self.assertEqual(sample_set.key, 5)
        self.assertEqual(sample_set.note, "C#1")
        self.assertEqual(len(sample_set.words), DEFAULT_SAMPLE_COUNT)
        self.assertEqual(sample_set.words[0], "000000")
        self.assertEqual(sample_set.checksum, sample_checksum(sample_set.words))

    def test_pure_sine_rejects_invalid_amplitude(self) -> None:
        with self.assertRaises(ValueError):
            pure_sine_samples(
                sample_count=128,
                sample_rate_hz=48000.0,
                frequency_hz=440.0,
                amplitude=0.0,
            )


class KeySelectionTests(unittest.TestCase):
    def test_single_keys_and_ranges(self) -> None:
        self.assertEqual(parse_key_selection("49"), (49,))
        self.assertEqual(parse_key_selection("49,80"), (49, 80))
        self.assertEqual(parse_key_selection("47-49,80"), (47, 48, 49, 80))

    def test_invalid_selections_raise(self) -> None:
        for selection in ("", "52-49", "0", "89", "49,"):
            with self.subTest(selection=selection):
                with self.assertRaises(ValueError):
                    parse_key_selection(selection)


if __name__ == "__main__":
    unittest.main()
