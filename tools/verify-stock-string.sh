#!/usr/bin/env bash
# Verify that a built kernel reports the expected stock release string.
#
# usage: tools/verify-stock-string.sh <expected-uts-release> [image-path]
#
# Reads the linux_banner ("Linux version <release> (<user>@<host>) ...") out of
# the built arm64 Image and compares the release part with the expected value.
set -euo pipefail

EXPECT="${1:?usage: $0 <expected-uts-release> [image-path]}"
IMG="${2:-}"

find_image() {
  local c
  # 1) build.sh (legacy GKI) writes to $OUT_DIR (default /home/runner/out)
  for c in \
    "${OUT_DIR:-}/dist/Image" \
    "$HOME/out/dist/Image" \
    "/home/runner/out/dist/Image" \
    "out/dist/Image" \
    "$HOME/out/common/arch/arm64/boot/Image" \
    "out/common/arch/arm64/boot/Image" \
    kernel/common/out/*/dist/Image \
    kernel/common/out/*/common/arch/arm64/boot/Image \
    kernel/out/*/common/arch/arm64/boot/Image \
    kernel/common/arch/arm64/boot/Image; do
    [ -f "$c" ] && { printf '%s\n' "$c"; return 0; }
  done
  # 2) fallback: any Image under the build dirs
  for d in "$HOME/out" out kernel; do
    [ -d "$d" ] || continue
    c="$(find "$d" -type f -name Image 2>/dev/null | head -n 1 || true)"
    [ -n "$c" ] && { printf '%s\n' "$c"; return 0; }
  done
  return 1
}


if [ -z "$IMG" ]; then
  IMG="$(find_image)" || { echo "ERROR: built Image not found (procurei $OUT_DIR/dist, $HOME/out/dist, kernel/**/Image)" >&2; exit 1; }
fi
[ -f "$IMG" ] || { echo "ERROR: image not found: $IMG" >&2; exit 1; }

TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT

case "$IMG" in
  *.gz)  gzip -dc "$IMG" > "$TMP" ;;
  *.lz4) lz4 -dc "$IMG" > "$TMP" ;;
  *.zst) zstd -dcq "$IMG" > "$TMP" ;;
  *)     cp "$IMG" "$TMP" ;;
esac

# The banner is a read-only C string inside the image, so it survives verbatim.
# Split the binary on non-printable bytes and pick the banner line.
BANNER="$(LC_ALL=C tr -c '\11\12\15\40-\176' '\n' < "$TMP" | LC_ALL=C grep -E '^Linux version [0-9]+\.[0-9]+' | head -n 1 || true)"

echo "image  : $IMG"
echo "banner : $BANNER"
echo "expect : Linux version ${EXPECT} (..."

if printf '%s' "$BANNER" | grep -qF "Linux version ${EXPECT} "; then
  echo "RESULT : OK - stock release string matches"
  exit 0
fi

echo "RESULT : FAIL - kernel does not report the expected stock release" >&2
exit 1
