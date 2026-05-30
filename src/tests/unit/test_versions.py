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


class TestPerVersionConfig(TestCase):
    """Tests for the per-version build attributes (single source of truth).

    These mirror the behaviour of the bash case statements that previously
    lived in release.sh / build-optimized.sh.
    """

    def test_api_level(self):
        self.assertEqual(versions.get_api_level('7.1.1'), '25')
        self.assertEqual(versions.get_api_level('16.0'), '36')
        self.assertEqual(versions.get_api_level('16.0_16k'), '36')
        self.assertEqual(versions.get_api_level('17.0_16k'), '37.0')
        self.assertEqual(versions.get_api_level('99.0'), '')

    def test_chromedriver_version(self):
        self.assertEqual(versions.get_chromedriver_version('7.1.1'), '2.28')
        self.assertEqual(versions.get_chromedriver_version('16.0'), '137.0.7151.70')
        self.assertEqual(versions.get_chromedriver_version('unknown'), '')

    def test_img_type(self):
        self.assertEqual(versions.get_img_type('5.0.1'), 'default')
        self.assertEqual(versions.get_img_type('5.1.1'), 'default')
        self.assertEqual(versions.get_img_type('16.0_16k'), 'google_apis_ps16k')
        self.assertEqual(versions.get_img_type('17.0_16k'), 'google_apis_ps16k')
        self.assertEqual(versions.get_img_type('12.0'), 'google_apis')

    def test_browser(self):
        self.assertEqual(versions.get_browser('5.0.1'), 'browser')
        self.assertEqual(versions.get_browser('6.0'), 'browser')
        self.assertEqual(versions.get_browser('7.1.1'), 'chrome')

    def test_processor(self):
        self.assertEqual(versions.get_processor('9.0'), 'x86_64')
        self.assertEqual(versions.get_processor('12.0'), 'x86_64')

    def test_sys_img(self):
        self.assertEqual(versions.get_sys_img('8.1'), 'x86')
        self.assertEqual(versions.get_sys_img('9.0'), 'x86_64')
        self.assertEqual(versions.get_sys_img('12.0'), 'x86_64')

    def test_is_supported_version(self):
        self.assertTrue(versions.is_supported_version('7.1.1'))
        self.assertTrue(versions.is_supported_version('17.0_16k'))
        self.assertFalse(versions.is_supported_version('99.0'))

    def test_supported_versions_list(self):
        # 16.0 / 16.0_16k must be present (build-optimized.sh had drifted and
        # was missing them before centralization).
        for v in ('5.0.1', '16.0', '16.0_16k', '17.0_16k'):
            self.assertIn(v, versions.SUPPORTED_VERSIONS)
        # Every supported version must have an API level (no dangling entries).
        for v in versions.SUPPORTED_VERSIONS:
            self.assertNotEqual(versions.get_api_level(v), '', v)


class TestVersionsCli(TestCase):
    """Tests for the CLI entry point used by the shell build scripts."""

    def test_map_command_succeeds(self):
        self.assertEqual(versions.main(['map', '7']), 0)

    def test_query_commands_succeed(self):
        for cmd in ('api_level', 'chromedriver', 'img_type', 'browser',
                    'processor', 'sys_img'):
            self.assertEqual(versions.main([cmd, '7.1.1']), 0, cmd)

    def test_supported_and_list_commands_succeed(self):
        self.assertEqual(versions.main(['supported']), 0)
        self.assertEqual(versions.main(['list']), 0)

    def test_invalid_usage_returns_error_code(self):
        self.assertEqual(versions.main([]), 2)
        self.assertEqual(versions.main(['unknown', '7']), 2)
        self.assertEqual(versions.main(['map']), 2)
