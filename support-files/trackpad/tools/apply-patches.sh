#!/usr/bin/env bash
# Apply the trackpad patches to a freshly cloned upstream VoodooI2C tree.
#
# Verified against VoodooI2C `5c0c99c`, VoodooGPIO `733dc80`,
# VoodooI2CHID `27277936bc16c215ae7f9b31e76e3231778d04bd`.
#
# No upstream source is redistributed with this repo - this script patches whatever
# you fetched yourself.
#
# Usage:  ./apply-patches.sh /path/to/VoodooI2C
set -eu

TREE="${1:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PATCHES="$HERE/../patches"

die(){ printf 'error: %s\n' "$*" >&2; exit 1; }
say(){ printf '\n=== %s ===\n' "$*"; }
ok(){  printf '  OK    %s\n' "$*"; }

[ -n "$TREE" ] || die "usage: $0 /path/to/VoodooI2C"
[ -d "$TREE" ] || die "no such directory: $TREE"
[ -d "$PATCHES" ] || die "no patches/ next to this script"

GPIO="$TREE/Dependencies/VoodooGPIO"
HID="$TREE/VoodooI2C Satellites/VoodooI2CHID"
[ -d "$GPIO" ] || die "VoodooGPIO submodule missing at $GPIO (clone with --recurse-submodules)"
[ -d "$HID" ]  || die "VoodooI2CHID submodule missing at $HID"

apply(){
  local patchfile="$1" where="$2" label="$3"
  printf '\n--- %s (%s) ---\n' "$label" "$where"
  # --dry-run first: never half-apply
  if ! ( cd "$where" && patch -p1 --dry-run --silent < "$patchfile" ); then
    die "$label does not apply cleanly to $where"
  fi
  ( cd "$where" && patch -p1 --silent < "$patchfile" )
  ok "$label applied"
}

apply "$PATCHES/01-voodooi2c-controller-driver.patch" "$TREE"  "VoodooI2CControllerDriver.cpp"
apply "$PATCHES/02-voodooi2chid-device.patch"         "$HID"   "VoodooI2CHIDDevice.cpp"
apply "$PATCHES/03-voodoogpio-intel.patch"            "$GPIO"  "VoodooGPIOIntel.cpp"
apply "$PATCHES/04-voodoogpio-intel-header.patch"     "$GPIO"  "VoodooGPIOIntel.hpp"

say "verify the result"
# Post-patch files must hash exactly as recorded. If they do not, the upstream commit is
# wrong - see ../README.md section 1.
declare -A WANT=(
  ["$TREE/VoodooI2C/VoodooI2C/VoodooI2CController/VoodooI2CControllerDriver.cpp"]=80b1b275dd4dfa754bf45ce20860178c9bc4d4e2b36f04e85f4446e6801b2a61
  ["$HID/VoodooI2CHID/VoodooI2CHIDDevice.cpp"]=a0738ef750c121148a6d3b96d77c6bfac6588c1ed177e36318afdf367e022123
  ["$GPIO/VoodooGPIO/VoodooGPIOIntel.cpp"]=6b5b7a7de53463226af14a5301a0597e03bfe1c18524555a8eded51e342f639e
  ["$GPIO/VoodooGPIO/VoodooGPIOIntel.hpp"]=0e50d3649471be1f3c9e883de866e8df34a3b711ca3d97d02b37dc399cbc69a0
)
fail=0
for f in "${!WANT[@]}"; do
  if [ ! -f "$f" ]; then printf '  MISSING  %s\n' "$f"; fail=1; continue; fi
  got=$(shasum -a 256 "$f" 2>/dev/null | cut -d' ' -f1)
  [ -n "$got" ] || got=$(sha256sum "$f" | cut -d' ' -f1)
  if [ "$got" = "${WANT[$f]}" ]; then printf '  OK    %s\n' "$(basename "$f")"
  else printf '  MISMATCH %s\n      got  %s\n      want %s\n' "$(basename "$f")" "$got" "${WANT[$f]}"; fail=1; fi
done
echo
if [ $fail -eq 0 ]; then
  echo "  All four files match. Build with the commands in ../README.md section 3."
else
  echo "  Hashes do NOT match - check you are on VoodooI2C 5c0c99c (README section 1)." >&2
fi
echo "  Remember the hand-added VoodooI2CPCIIceLakeControllerI2C3 personality"
echo "  (../README.md section 6) - a clean build does NOT produce it."
exit $fail
