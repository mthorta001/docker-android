"""Unit tests for the Android version mapping (src/versions.py)."""
from unittest import TestCase

from src import versions


class TestMapAndroidVersion(TestCase):
    """Tests for map_android_version, mirroring the old bash behavior."""

    def test_full_version_is_passed_through(self):
        # Anything containing a dot is already a full version.
        self.assertEqual(versions.map_android_version('7.1.1'), '7.1.1')
        self.assertEqual(versions.map_android_version('9.0'), '9.0')

    def test_short_version_is_mapped(self):
        self.assertEqual(versions.map_android_version('7'), '7.0')
        self.assertEqual(versions.map_android_version('8'), '8.0')
        self.assertEqual(versions.map_android_version('16'), '16.0')

    def test_short_version_with_minor_is_mapped(self):
        # Keys with a dot are looked up directly (the dot short-circuit only
        # returns input unchanged when the key is NOT a known mapping; here the
        # values intentionally equal their full forms).
        self.assertEqual(versions.map_android_version('5'), '5.0.1')

    def test_16k_variant_is_preserved(self):
        self.assertEqual(versions.map_android_version('16.0_16k'), '16.0_16k')
        self.assertEqual(versions.map_android_version('17.0_16k'), '17.0_16k')

    def test_unknown_version_is_returned_unchanged(self):
        self.assertEqual(versions.map_android_version('99'), '99')
        self.assertEqual(versions.map_android_version('foo'), 'foo')


class TestVersionsCli(TestCase):
    """Tests for the CLI entry point used by travis.sh."""

    def test_map_command_succeeds(self):
        self.assertEqual(versions.main(['map', '7']), 0)

    def test_invalid_usage_returns_error_code(self):
        self.assertEqual(versions.main([]), 2)
        self.assertEqual(versions.main(['unknown', '7']), 2)
