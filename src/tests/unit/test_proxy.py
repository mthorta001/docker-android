"""Unit tests for proxy URL parsing (src/proxy.py).

These mirror (and harden) the behaviour of the old bash grep/sed/IFS pipeline
that previously lived in src/utils.sh::enable_proxy_if_needed.
"""
from unittest import TestCase

from src import proxy


class TestParseProxyUrl(TestCase):
    """Tests for proxy.parse_proxy_url."""

    def test_http_with_port(self):
        self.assertEqual(proxy.parse_proxy_url('http://1.2.3.4:8080'), ('1.2.3.4', '8080'))

    def test_https_with_port(self):
        self.assertEqual(proxy.parse_proxy_url('https://proxy.example.com:3128'),
                         ('proxy.example.com', '3128'))

    def test_without_scheme(self):
        # The old bash code also handled "host:port" without a scheme.
        self.assertEqual(proxy.parse_proxy_url('1.2.3.4:8080'), ('1.2.3.4', '8080'))

    def test_host_without_port(self):
        self.assertEqual(proxy.parse_proxy_url('http://1.2.3.4'), ('1.2.3.4', ''))

    def test_surrounding_whitespace_is_stripped(self):
        self.assertEqual(proxy.parse_proxy_url('  http://1.2.3.4:8080  '), ('1.2.3.4', '8080'))

    def test_empty_input(self):
        self.assertEqual(proxy.parse_proxy_url(''), ('', ''))

    def test_none_input(self):
        self.assertEqual(proxy.parse_proxy_url(None), ('', ''))


class TestProxyCli(TestCase):
    """Tests for the CLI entry point used by src/utils.sh."""

    def test_parse_command_succeeds(self):
        self.assertEqual(proxy.main(['parse', 'http://1.2.3.4:8080']), 0)

    def test_parse_command_with_empty_value_succeeds(self):
        self.assertEqual(proxy.main(['parse', '']), 0)

    def test_invalid_usage_returns_error_code(self):
        self.assertEqual(proxy.main([]), 2)
        self.assertEqual(proxy.main(['parse']), 2)
        self.assertEqual(proxy.main(['unknown', 'x']), 2)
