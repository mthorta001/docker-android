#!/usr/bin/env python3
"""Proxy URL parsing helper.

Pure-logic replacement for the brittle bash URL parsing previously embedded in
``src/utils.sh::enable_proxy_if_needed``::

    protocol="$(echo $HTTP_PROXY | grep :// | sed -e's,^\\(.*://\\).*,\\1,g')"
    proxy="$(echo ${HTTP_PROXY/$protocol/})"
    IFS=':' read -r -a p <<< "$proxy"
    # p[0] -> host, p[1] -> port

That bash pipeline (``grep``/``sed``/``IFS`` splitting) is easy to get wrong with
quoting and edge cases. This module parses the proxy URL with the standard
library :mod:`urllib.parse`, which is clearer and unit-testable, while the
surrounding ``adb`` orchestration stays in shell (it is pure side effects, see
IMPROVEMENT_ROADMAP.md §2).

The module purposely avoids importing :mod:`src.app`, which validates emulator
environment variables at import time, so it can run standalone in CI / shell.

Usage from shell::

    # Prints "<host> <port>" (space separated); empty fields stay empty.
    read -r PROXY_HOST PROXY_PORT < <(python3 -m src.proxy parse "$HTTP_PROXY")
"""

import sys
from urllib.parse import urlparse


def parse_proxy_url(http_proxy):
    """Parse a proxy URL into its host and port components.

    Mirrors the behaviour of the previous bash implementation: it strips the
    ``<scheme>://`` prefix and splits the remainder into host and port. A proxy
    without an explicit scheme (e.g. ``1.2.3.4:8080``) is also handled.

    :param http_proxy: The proxy URL, e.g. ``http://1.2.3.4:8080``. May be
        ``None`` or empty.
    :return: A ``(host, port)`` tuple. ``host`` is an empty string when the
        input is empty/None; ``port`` is an empty string when no port is given.
    """
    if not http_proxy:
        return '', ''

    proxy = http_proxy.strip()

    # urlparse only populates hostname/port when a scheme (and "//") is present.
    # If the proxy was passed without a scheme (e.g. "1.2.3.4:8080"), add a
    # placeholder scheme so urlparse can split host/port reliably.
    if '://' not in proxy:
        proxy = '//' + proxy

    parsed = urlparse(proxy)

    host = parsed.hostname or ''
    port = str(parsed.port) if parsed.port is not None else ''
    return host, port


def main(argv=None) -> int:
    """CLI entry point so shell scripts can reuse the parsing logic.

    Prints ``"<host> <port>"`` (space separated) on success.

    :param argv: Argument list (defaults to ``sys.argv[1:]``).
    :return: Process exit code.
    """
    args = list(sys.argv[1:] if argv is None else argv)

    if len(args) == 2 and args[0] == 'parse':
        host, port = parse_proxy_url(args[1])
        print('{host} {port}'.format(host=host, port=port))
        return 0

    sys.stderr.write(
        'usage:\n'
        '  python3 -m src.proxy parse <http_proxy_url>\n'
    )
    return 2


if __name__ == '__main__':
    sys.exit(main())
