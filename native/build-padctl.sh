#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/native/padctl.m"
OUT="$ROOT/data/libpadctl.dylib"

JDK="${JAVA_HOME:-}"
if [[ -z "$JDK" || ! -f "$JDK/include/jni.h" ]]; then
  for c in \
    "/Volumes/Processing/Processing.app/Contents/app/resources/jdk" \
    "/Applications/Processing.app/Contents/app/resources/jdk" \
    "$ROOT/native" \
    ; do
    if [[ -f "$c/include/jni.h" ]]; then JDK="$c"; break; fi
    if [[ -f "$c/Contents/app/resources/jdk/include/jni.h" ]]; then JDK="$c/Contents/app/resources/jdk"; break; fi
  done
fi
if [[ ! -f "$JDK/include/jni.h" ]]; then
  echo "jni.h not found. Set JAVA_HOME to a JDK." >&2
  exit 1
fi

SDK="$(xcrun --sdk macosx --show-sdk-path)"
clang -dynamiclib -O2 -fobjc-arc \
  -arch arm64 -arch x86_64 \
  -isysroot "$SDK" \
  -I"$JDK/include" -I"$JDK/include/darwin" \
  -framework Foundation -framework AppKit \
  -install_name @loader_path/libpadctl.dylib \
  -o "$OUT" "$SRC"
echo "Built $OUT"
file "$OUT"
nm -gU "$OUT" | grep Java_PadCtl || true
