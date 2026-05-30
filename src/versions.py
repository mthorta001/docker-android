#!/usr/bin/env python3
"""Android version & per-version build configuration.

Single source of truth for everything the build pipeline needs to know about an
Android version:

* mapping short identifiers (e.g. ``7``, ``8.1``) to full version strings
  (e.g. ``7.1.1``);
* per-version build attributes used as Docker ``--build-arg`` values:
  ``api_level``, ``chromedriver`` (ChromeDriver version), ``img_type``,
  ``browser``, ``processor`` and ``sys_img``;
* the list of supported versions.

Historically this information was duplicated as bash ``case`` statements in
``travis.sh`` (short->full mapping), ``release.sh`` and ``build-optimized.sh``
(per-version attributes). The bash copies had already drifted apart (e.g.
``build-optimized.sh`` was missing the ``16.0`` / ``16.0_16k`` entries present
in ``release.sh``). Centralizing here lets the shell pipeline and the Python
code share one definition and lets us unit-test it.

Usage from shell::

    mapped=$(python3 -m src.versions map "$ANDROID_VERSION")
    api=$(python3 -m src.versions api_level "$version")
    versions=$(python3 -m src.versions supported)        # pipe-separated
    list=$(python3 -m src.versions list)                 # space-separated

The module purposely avoids importing :mod:`src.app`, which validates emulator
environment variables at import time, so it can run standalone in CI.
"""

import sys

# Short version identifier -> full Android version string.
ANDROID_VERSION_MAP = {
    '5': '5.0.1',
    '5.0': '5.0.1',
    '5.1': '5.1.1',
    '6': '6.0',
    '7': '7.0',
    '7.1': '7.1.1',
    '8': '8.0',
    '8.1': '8.1',
    '9': '9.0',
    '10': '10.0',
    '11': '11.0',
    '12': '12.0',
    '13': '13.0',
    '14': '14.0',
    '15': '15.0',
    '16': '16.0',
    '16.0_16k': '16.0_16k',
    '17.0_16k': '17.0_16k',
}

# Ordered list of supported (full) Android versions. Order matters: it is used
# to drive ``ANDROID_VERSION=all`` builds and the usage/help strings.
SUPPORTED_VERSIONS = [
    '5.0.1', '5.1.1', '6.0', '7.0', '7.1.1', '8.0', '8.1', '9.0',
    '10.0', '11.0', '12.0', '13.0', '14.0', '15.0', '16.0',
    '16.0_16k', '17.0_16k',
]

# Full Android version -> API level. (Mirrors release.sh get_api_level.)
API_LEVEL_MAP = {
    '5.0.1': '21',
    '5.1.1': '22',
    '6.0': '23',
    '7.0': '24',
    '7.1.1': '25',
    '8.0': '26',
    '8.1': '27',
    '9.0': '28',
    '10.0': '29',
    '11.0': '30',
    '12.0': '31',
    '13.0': '33',
    '14.0': '34',
    '15.0': '35',
    '16.0': '36',
    '16.0_16k': '36',
    '17.0_16k': '37.0',
}

# Full Android version -> ChromeDriver version. (Mirrors release.sh.)
CHROMEDRIVER_MAP = {
    '5.0.1': '2.21',
    '5.1.1': '2.13',
    '6.0': '2.18',
    '7.0': '2.23',
    '7.1.1': '2.28',
    '8.0': '2.31',
    '8.1': '2.33',
    '9.0': '2.40',
    '10.0': '74.0.3729.6',
    '11.0': '83.0.4103.39',
    '12.0': '92.0.4515.107',
    '13.0': '104.0.5112.29',
    '14.0': '114.0.5735.90',
    '15.0': '114.0.5735.90',
    '16.0': '137.0.7151.70',
    '16.0_16k': '137.0.7151.70',
    '17.0_16k': '137.0.7151.70',
}

DEFAULT_PROCESSOR = 'x86_64'


def map_android_version(input_version: str) -> str:
    """Map a short Android version to its full form.

    Mirrors the previous bash implementation:

    * a version that already contains a dot is returned unchanged;
    * a known short version is mapped via :data:`ANDROID_VERSION_MAP`;
    * anything else is returned unchanged.

    :param input_version: Version string provided by the build pipeline.
    :return: The full/normalized version string.
    """
    # If already a full version (contains dot), return as is.
    if '.' in input_version:
        return input_version

    # Try to map short version to full version, otherwise return original.
    return ANDROID_VERSION_MAP.get(input_version, input_version)


def get_api_level(version: str) -> str:
    """Return the API level for a full Android version (or ``''`` if unknown)."""
    return API_LEVEL_MAP.get(version, '')


def get_chromedriver_version(version: str) -> str:
    """Return the ChromeDriver version for a full Android version."""
    return CHROMEDRIVER_MAP.get(version, '')


def get_img_type(version: str) -> str:
    """Return the system-image type (``default``/``google_apis``/``..._ps16k``)."""
    if version in ('5.0.1', '5.1.1'):
        return 'default'
    if version.endswith('_16k'):
        return 'google_apis_ps16k'
    return 'google_apis'


def get_browser(version: str) -> str:
    """Return the default browser for a version (``browser`` for old, else ``chrome``)."""
    if version in ('5.0.1', '5.1.1', '6.0'):
        return 'browser'
    return 'chrome'


def get_processor(version: str) -> str:
    """Return the CPU architecture build-arg for a version."""
    return DEFAULT_PROCESSOR


def get_sys_img(version: str) -> str:
    """Return the system-image ABI for a version."""
    if version == '8.1':
        return 'x86'
    return DEFAULT_PROCESSOR


def is_supported_version(version: str) -> bool:
    """Return ``True`` if the (full) version has a known API level."""
    return get_api_level(version) != ''


# Dispatch table for the per-version query CLI sub-commands.
_QUERY_COMMANDS = {
    'api_level': get_api_level,
    'chromedriver': get_chromedriver_version,
    'img_type': get_img_type,
    'browser': get_browser,
    'processor': get_processor,
    'sys_img': get_sys_img,
}

_USAGE = (
    'usage:\n'
    '  python3 -m src.versions map <android_version>\n'
    '  python3 -m src.versions {api_level|chromedriver|img_type|browser|'
    'processor|sys_img} <android_version>\n'
    '  python3 -m src.versions supported   # pipe-separated supported versions\n'
    '  python3 -m src.versions list        # space-separated supported versions\n'
)


def main(argv=None) -> int:
    """CLI entry point so shell scripts can reuse the configuration.

    :param argv: Argument list (defaults to ``sys.argv[1:]``).
    :return: Process exit code.
    """
    args = list(sys.argv[1:] if argv is None else argv)

    if len(args) == 1 and args[0] == 'supported':
        print('|'.join(SUPPORTED_VERSIONS))
        return 0

    if len(args) == 1 and args[0] == 'list':
        print(' '.join(SUPPORTED_VERSIONS))
        return 0

    if len(args) == 2 and args[0] == 'map':
        print(map_android_version(args[1]))
        return 0

    if len(args) == 2 and args[0] in _QUERY_COMMANDS:
        print(_QUERY_COMMANDS[args[0]](args[1]))
        return 0

    sys.stderr.write(_USAGE)
    return 2


if __name__ == '__main__':
    sys.exit(main())
