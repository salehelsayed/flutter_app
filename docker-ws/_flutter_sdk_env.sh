#!/bin/bash
# Source this from any script that shells out to `flutter`/`dart`.
#
# The checkout requires Flutter 3.47.2 (pubspec `flutter: '>=3.47.2'`), but the
# Mac's PATH still resolves `flutter` to 3.41.4. The 3.41.4 tool either refuses
# to resolve dependencies or compiles 3.47.2 framework sources with a 3.41.4
# engine and dies inside flutter/lib/src. Prepend the matching SDK instead.
_MKNOON_SDK="${MKNOON_FLUTTER_SDK:-$HOME/development/flutter-3.47.2}"
if [ -x "$_MKNOON_SDK/bin/flutter" ]; then
  PATH="$_MKNOON_SDK/bin:$PATH"
  export PATH
fi
unset _MKNOON_SDK
