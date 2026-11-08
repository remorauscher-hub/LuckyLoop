#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/native/midictl.m"
OUT="$ROOT/data/libmidictl.dylib"

JDK="${JAVA_HOME:-}"
if [[ -z "$JDK" || ! -f "$JDK/include/jni.h" ]]; then
  for c in \
    "/Applications/Processing.app/Contents/app/resources/jdk" \
    "/Applications/Processing-4.3.app/Contents/PlugIns/jdk-17.0.8+7/Contents/Home" \
    "$ROOT/native" \
    ; do
    if [[ -f "$c/include/jni.h" ]]; then JDK="$c"; break; fi
  done
fi
if [[ ! -f "$JDK/include/jni.h" ]]; then
  echo "jni.h not found. Set JAVA_HOME to a JDK." >&2
  exit 1
fi

SDK="$(xcrun --sdk macosx --show-sdk-path)"
clang -dynamiclib -O2 \
  -arch arm64 -arch x86_64 \
  -isysroot "$SDK" \
  -I"$JDK/include" -I"$JDK/include/darwin" \
  -framework CoreMIDI -framework CoreFoundation \
  -install_name @loader_path/libmidictl.dylib \
  -o "$OUT" "$SRC"
echo "Built $OUT"
file "$OUT"
nm -gU "$OUT" | grep Java_MidiCtl || true
