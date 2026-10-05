#!/bin/bash
# Runs the tests. With only the Command Line Tools installed, SwiftPM can't find Testing.framework
# on its own, so point the compiler and the test runner at it.
set -euo pipefail
cd "$(dirname "$0")/.."

CLT=/Library/Developer/CommandLineTools/Library/Developer
if [[ -d "$CLT/Frameworks/Testing.framework" ]]; then
    swift test -Xswiftc -F"$CLT/Frameworks" \
        -Xlinker -rpath -Xlinker "$CLT/Frameworks" -Xlinker -rpath -Xlinker "$CLT/usr/lib" "$@"
else
    swift test "$@"
fi
