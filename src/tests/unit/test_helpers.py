"""Unit tests for small pure helpers in src/app.py.

These cover the environment-parsing / command-building logic that previously
had no direct coverage (get_env_int, get_env_port_from_udid, get_avd_abi and
the JSON produced by create_node_config). See IMPROVEMENT_ROADMAP.md §5.
"""
import json
import os
from unittest import TestCase

import mock

from src import CONFIG_FILE
from src import app


class TestGetEnvInt(TestCase):
    """Tests for app.get_env_int."""

    def tearDown(self):
        if 'SOME_INT' in os.environ:
            del os.environ['SOME_INT']

    def test_returns_default_when_unset(self):
        self.assertEqual(app.get_env_int('SOME_INT', 4723), 4723)

    def test_parses_valid_integer(self):
        os.environ['SOME_INT'] = '5555'
        self.assertEqual(app.get_env_int('SOME_INT', 4723), 5555)

    def test_returns_default_on_invalid_value(self):
        os.environ['SOME_INT'] = 'not-a-number'
        with mock.patch('src.app.logger') as mocked_logger:
            self.assertEqual(app.get_env_int('SOME_INT', 4723), 4723)
            self.assertTrue(mocked_logger.warning.called)


class TestGetEnvPortFromUdid(TestCase):
    """Tests for app.get_env_port_from_udid."""

    def tearDown(self):
        if 'UDID' in os.environ:
            del os.environ['UDID']

    def test_returns_default_when_unset(self):
        if 'UDID' in os.environ:
            del os.environ['UDID']
        self.assertEqual(app.get_env_port_from_udid('5554'), '5554')

    def test_extracts_port_from_emulator_udid(self):
        os.environ['UDID'] = 'emulator-5560'
        self.assertEqual(app.get_env_port_from_udid('5554'), '5560')

    def test_returns_udid_as_is_without_prefix(self):
        os.environ['UDID'] = '127.0.0.1:5555'
        self.assertEqual(app.get_env_port_from_udid('5554'), '127.0.0.1:5555')


class TestGetAvdAbi(TestCase):
    """Tests for app.get_avd_abi (standard vs 16k tags)."""

    def setUp(self):
        self._orig_sys_img = app.SYS_IMG
        self._orig_img_type = app.IMG_TYPE

    def tearDown(self):
        app.SYS_IMG = self._orig_sys_img
        app.IMG_TYPE = self._orig_img_type

    def test_standard_tag(self):
        app.SYS_IMG = 'x86_64'
        app.IMG_TYPE = 'google_apis'
        self.assertEqual(app.get_avd_abi(), 'google_apis/x86_64')

    def test_ps16k_tag_is_normalized(self):
        app.SYS_IMG = 'x86_64'
        app.IMG_TYPE = 'google_apis_ps16k'
        self.assertEqual(app.get_avd_abi(), 'google_apis/x86_64')


class TestCreateNodeConfig(TestCase):
    """Tests for the JSON payload written by app.create_node_config."""

    def tearDown(self):
        if os.path.exists(CONFIG_FILE):
            os.remove(CONFIG_FILE)

    def test_node_config_contents(self):
        app.create_node_config('avd1', 'android', '1.2.3.4', 4723, '5.6.7.8', 4444, 30)
        self.assertTrue(os.path.exists(CONFIG_FILE))
        with open(CONFIG_FILE, 'r') as cf:
            data = json.load(cf)

        capability = data['capabilities'][0]
        self.assertEqual(capability['deviceName'], 'avd1')
        self.assertEqual(capability['browserName'], 'android')
        self.assertEqual(capability['platformName'], 'Android')

        configuration = data['configuration']
        self.assertEqual(configuration['host'], '1.2.3.4')
        self.assertEqual(configuration['port'], 4723)
        self.assertEqual(configuration['hubHost'], '5.6.7.8')
        self.assertEqual(configuration['hubPort'], 4444)
        self.assertEqual(configuration['timeout'], 30)
        self.assertEqual(configuration['url'], 'http://1.2.3.4:4723/wd/hub')
