"""Unit test to test appium service."""
import os
from unittest import TestCase

import mock

from src import app


class TestAppium(TestCase):
    """Unit test class to test appium methods."""

    def setUp(self):
        os.environ['CONNECT_TO_GRID'] = str(True)
        self.avd_name = 'test_avd'

    @mock.patch('subprocess.check_call')
    def test_chrome_driver(self, mocked_subprocess):
        os.environ['CONNECT_TO_GRID'] = str(False)
        os.environ['BROWSER'] = 'chrome'
        self.assertFalse(mocked_subprocess.called)
        app.appium_run(self.avd_name)
        self.assertTrue(mocked_subprocess.called)

    @mock.patch('subprocess.check_call')
    def test_without_selenium_grid(self, mocked_subprocess):
        os.environ['CONNECT_TO_GRID'] = str(False)
        self.assertFalse(mocked_subprocess.called)
        app.appium_run(self.avd_name)
        self.assertTrue(mocked_subprocess.called)

    @mock.patch('os.popen')
    @mock.patch('subprocess.check_call')
    def test_with_selenium_grid(self, mocked_os, mocked_subprocess):
        with mock.patch('src.app.create_node_config') as mocked_config:
            self.assertFalse(mocked_config.called)
            self.assertFalse(mocked_os.called)
            self.assertFalse(mocked_subprocess.called)
            app.appium_run(self.avd_name)
            self.assertTrue(mocked_config.called)
            self.assertTrue(mocked_os.called)
            self.assertTrue(mocked_subprocess.called)

    @mock.patch('os.popen')
    @mock.patch('subprocess.check_call')
    @mock.patch('src.app.logger')
    def test_invalid_integer(self, mocked_logger, mocked_subprocess, mocked_os):
        os.environ['APPIUM_PORT'] = 'test'
        with mock.patch('src.app.create_node_config') as mocked_config:
            self.assertFalse(mocked_config.called)
            self.assertFalse(mocked_os.called)
            self.assertFalse(mocked_subprocess.called)
            app.appium_run(self.avd_name)
            # Should gracefully handle invalid port and use default 4723
            self.assertTrue(mocked_logger.warning.called)
            self.assertTrue(mocked_os.called)
            self.assertTrue(mocked_subprocess.called)
            # Verify that the warning was logged about invalid port value
            warning_calls = [call for call in mocked_logger.warning.call_args_list 
                           if 'Invalid integer value for APPIUM_PORT' in str(call)]
            self.assertTrue(len(warning_calls) > 0)

    def test_config_creation(self):
        from src import CONFIG_FILE
        self.assertFalse(os.path.exists(CONFIG_FILE))
        app.create_node_config('test', 'android', '127.0.0.1', 4723, '127.0.0.1', 4444, 30)
        self.assertTrue(os.path.exists(CONFIG_FILE))
        os.remove(CONFIG_FILE)

    def tearDown(self):
        del os.environ['CONNECT_TO_GRID']
        if os.getenv('APPIUM_PORT'):
            del os.environ['APPIUM_PORT']
        if os.getenv('BROWSER'):
            del os.environ['BROWSER']
