#!/usr/bin/env bash
# Rewrite the BROKEN _DSM GUID test in SSDT-TPDHID to a valid buffer comparison.
#
# WHY: the shipped table's _DSM opens with
#       If ((Arg0 == 0x3CDFF6F7))
#   Arg0 is a 16-byte Buffer and 0x3CDFF6F7 is an Integer, so ACPICA reports a type
#   mismatch and the test is UNSATISFIABLE - _DSM always falls through to
#   `Return (Buffer (One) { 0x00 })`. The table works only because a separate `XDSM`
#   method does the real job, and XDSM has been deprecated upstream since 2020
#   (VoodooI2C PR #391).
#
# ToUUID() is a COMPILE-TIME operator and is NOT valid inside a method body, so the GUID
# must first be bound to a Name in the device scope.
#
# NOTE: the output is intentionally NOT byte-identical to the shipped table. This is a
# fix, not a reproduction. Verify on hardware before deploying.
#
# Usage:  ./patch-ssdt-dsm.sh [outdir]
set -eu

OUT="${1:-./ssdt-dsm-out}"
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/../SSDT-TPDHID.dsl"
WANT=330b29ff2716f75b

say(){ printf '\n=== %s ===\n' "$*"; }
ok(){  printf '  OK    %s\n' "$*"; }
die(){ printf 'error: %s\n' "$*" >&2; exit 1; }

h(){ if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -c1-16
     else sha256sum "$1" | cut -c1-16; fi; }

# ---- locate iasl -----------------------------------------------------------
IASL="${IASL:-}"
if [ -z "$IASL" ]; then
  for c in /nix/store/*-acpica-tools-*/bin/iasl \
           /usr/bin/iasl /usr/local/bin/iasl \
           /Applications/MaciASL.app/Contents/MacOS/iasl-stable \
           /Applications/MaciASL.app/Contents/MacOS/iasl; do
    [ -x "$c" ] && { IASL="$c"; break; }
  done
fi
[ -n "$IASL" ] && [ -x "$IASL" ] || die "no iasl found - set IASL=/path/to/iasl"

say "0. environment"
printf '  iasl : %s\n' "$IASL"
printf '  src  : %s\n' "$SRC"
printf '  out  : %s\n' "$OUT"
[ -f "$SRC" ] || die "source ASL not found at $SRC"
mkdir -p "$OUT"

say "1. rewrite the _DSM GUID test"
cp "$SRC" "$OUT/SSDT-TPDHID.dsl"
python3 - "$OUT/SSDT-TPDHID.dsl" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8", errors="surrogateescape").read()

# a) bind the GUID to a Name in the device scope (ToUUID is compile-time only)
line = 'Name (DSGD, ToUUID ("3cdff6f7-4267-4555-ad05-b30a3d8938de"))'
first = s.find('Method (')
if first < 0:
    print("  !! no Method found"); sys.exit(1)
ls = s.rfind('\n', 0, first) + 1
indent = re.match(r'[ \t]*', s[ls:]).group(0)
if 'DSGD' not in s:
    s = s[:ls] + f"{indent}{line}\n" + s[ls:]
    print("  inserted Name (DSGD, ToUUID(...)) into the device scope")

# b) the broken integer comparison -> buffer comparison
s, n = re.subn(r'If \(\(Arg0 == 0x3CDFF6F7\)\)', 'If ((Arg0 == DSGD))', s)
if n == 0:
    print("  !! broken GUID test not found - already fixed?"); sys.exit(1)
print(f"  rewrote {n} GUID test(s) to a 16-byte buffer comparison")

open(p, "w", encoding="utf-8", errors="surrogateescape").write(s)
PY

say "2. recompile"
# iasl rejects `-o` in some builds and derives the .aml name from the input, so compile
# in a clean subdirectory.
rm -rf "$OUT/compile"; mkdir -p "$OUT/compile"
cp "$OUT/SSDT-TPDHID.dsl" "$OUT/compile/"
( cd "$OUT/compile" && "$IASL" SSDT-TPDHID.dsl ) > "$OUT/iasl.log" 2>&1 || true
grep -E 'Compilation (successful|failed)|Error' "$OUT/iasl.log" | head -5 | sed 's/^/  /' || true
[ -f "$OUT/compile/SSDT-TPDHID.aml" ] || die "compile failed - see $OUT/iasl.log"
cp "$OUT/compile/SSDT-TPDHID.aml" "$OUT/SSDT-TPDHID.aml"

say "3. result"
printf '  built   : %s  %s bytes\n' "$(h "$OUT/SSDT-TPDHID.aml")" "$(wc -c < "$OUT/SSDT-TPDHID.aml" | tr -d ' ')"
printf '  shipped : %s  284 bytes  (the unfixed table, for reference)\n' "$WANT"
echo
echo "  This is a FIX, not a reproduction - differing from $WANT is expected."
echo "  The change makes _DSM return the descriptor instead of always 0x00."
echo "  XDSM is deliberately left in place as a fallback."
echo
echo "  VERIFY ON HARDWARE before deploying."
