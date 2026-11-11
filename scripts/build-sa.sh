#!/bin/bash
# Builds the SkyRose scripting addition (arm64e): SkyRoseSA.dylib (runs inside the Dock) and
# skyrose-sa-loader (run once per boot with sudo by the user). Output: $1 (default dist/sa).
# Nothing is loaded or installed here.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/dist/sa}"
SRC="$ROOT/Packaging/sa"
mkdir -p "$OUT"
CC="$(xcrun --find clang)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
FLAGS=(-arch arm64e -isysroot "$SDK" -mmacosx-version-min=14.0 -O2 -Wall -Wextra -Wno-unused-parameter)
"$CC" "${FLAGS[@]}" -dynamiclib -fvisibility=hidden \
  -framework CoreFoundation -framework CoreGraphics \
  -install_name "@rpath/SkyRoseSA.dylib" -o "$OUT/SkyRoseSA.dylib" "$SRC/payload.c"
"$CC" "${FLAGS[@]}" -o "$OUT/skyrose-sa-loader" "$SRC/loader.c" "$SRC/trampoline.s"
# The boot daemon's scripts ship next to the loader; the user runs the installer with sudo.
for f in install-sa-daemon.sh uninstall-sa-daemon.sh skyrose-sa-daemon.sh com.skyrose.sa-loader.plist; do cp "$SRC/$f" "$OUT/$f"; done
echo "    built $(basename "$OUT")/SkyRoseSA.dylib and skyrose-sa-loader (arm64e)"
