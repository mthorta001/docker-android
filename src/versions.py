#!/usr/bin/env python3
"""Android version mapping.

Single source of truth for translating short Android version identifiers
(e.g. ``7``, ``8.1``) into their full version strings (e.g. ``7.1.1``).

This logic used to be duplicated in ``travis.sh`` (an associative array plus a
bash ``map_android_version`` function). Keeping it here lets both the shell
build pipeline and the Python code share one definition and lets us unit-test
it.

Usage from shell::

    mapped=$(python3 -m src.versions map "$ANDROID_VERSION")

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


def main(argv=None) -> int:
    """CLI entry point so shell scripts can reuse the mapping.

    :param argv: Argument list (defaults to ``sys.argv[1:]``).
    :return: Process exit code.
    """
    args = list(sys.argv[1:] if argv is None else argv)
    if len(args) == 2 and args[0] == 'map':
        print(map_android_version(args[1]))
        return 0

    sys.stderr.write('usage: python3 -m src.versions map <android_version>\n')
    return 2


if __name__ == '__main__':
    sys.exit(main())
