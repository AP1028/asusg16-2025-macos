# Trackpad fix — ASUS ROG Zephyrus G16 GU605CW (Arrow Lake-H)

Getting the I2C-HID touchpad working on macOS 15.8.1. This folder is self-contained: patches,
the authored ACPI table, build instructions, and the technical explanation.

**No upstream kext source is redistributed here.** The patches are unified diffs against upstream
files; you fetch the upstream commits yourself (below) and apply them.

---

## Result

| | |
|---|---|
| Touchpad | **working** — multitouch, gestures, tap-to-click |
| macOS | 15.8.1 (24G90) |
| Applied to | the ESP in this repo |
| Kexts involved | `VoodooI2C` + `VoodooI2CHID` + `VoodooGPIO` + `VoodooInput` |

---

## 1. Upstream commits — patch against **exactly** these

The patches are generated against these revisions. A different commit may still apply, but it is
not verified.

| repo | commit | note |
|---|---|---|
| [VoodooI2C/VoodooI2C](https://github.com/VoodooI2C/VoodooI2C) | **`5c0c99c`** — *"Apply clock gating only to Broadwell/Lynxpoint I2C controllers (#578)"* | the top-level project |
| VoodooGPIO (submodule of the above) | **`733dc80`** | `Dependencies/VoodooGPIO` |
| VoodooI2CHID (submodule of the above) | **`27277936bc16c215ae7f9b31e76e3231778d04bd`** | `VoodooI2C Satellites/VoodooI2CHID` |
| [acidanthera/MacKernelSDK](https://github.com/acidanthera/MacKernelSDK) | current `master` | clone into the project root |

```bash
git clone --depth 1 --recurse-submodules --shallow-submodules \
    https://github.com/VoodooI2C/VoodooI2C.git
cd VoodooI2C
git clone --depth 1 https://github.com/acidanthera/MacKernelSDK.git
git -C Dependencies/VoodooGPIO        checkout 733dc80
git -C "VoodooI2C Satellites/VoodooI2CHID" checkout 27277936bc16c215ae7f9b31e76e3231778d04bd
```

---

## 2. Patches

Apply from each repo/project root with `-p1`. See `tools/apply-patches.sh`.

### Verified post-patch hashes

After applying, these four files must hash exactly as follows. If they do not, you are on the
wrong upstream commit.

| file | sha256 |
|---|---|
| `VoodooI2CControllerDriver.cpp` | `80b1b275dd4dfa754bf45ce20860178c9bc4d4e2b36f04e85f4446e6801b2a61` |
| `VoodooI2CHIDDevice.cpp` | `a0738ef750c121148a6d3b96d77c6bfac6588c1ed177e36318afdf367e022123` |
| `VoodooGPIOIntel.cpp` | `6b5b7a7de53463226af14a5301a0597e03bfe1c18524555a8eded51e342f639e` |
| `VoodooGPIOIntel.hpp` | `0e50d3649471be1f3c9e883de866e8df34a3b711ca3d97d02b37dc399cbc69a0` |

`tools/apply-patches.sh` checks these for you.

| patch | target file | changed lines | what it does |
|---|---|---|---|
| `patches/01-voodooi2c-controller-driver.patch` | `VoodooI2C/VoodooI2C/VoodooI2CController/VoodooI2CControllerDriver.cpp` | 79 | **the core fix** — locates the synthesised ACPI device and creates the nub |
| `patches/02-voodooi2chid-device.patch` | `VoodooI2CHID/VoodooI2CHIDDevice.cpp` | 39 | **real upstream bug** — input-report length |
| `patches/03-voodoogpio-intel.patch` | `VoodooGPIO/VoodooGPIOIntel.cpp` | 11 | routes `GPI_IS` through `is_offset` |
| `patches/04-voodoogpio-intel-header.patch` | `VoodooGPIO/VoodooGPIOIntel.hpp` | 2 | adds the `is_offset` field |

**Patches 03/04 are required, not optional** — the Meteor Lake port cannot compile without
`is_offset`. **Patches 01/02 are the functional fix.**

> ⚠️ `VoodooGPIO#19` ("Raptor Lake-S support") already implements an equivalent `is_offset`.
> If that has landed, patches 03/04 may be unnecessary or conflict.

---

## 3. Build

Requires **Xcode 16.4 (16F6)** and the **macOS 15.5 SDK (24F74)**. Other toolchains may work but
the verification hashes below were produced with those.

```bash
# VoodooI2C  — note: do NOT pass `rm -rf build` here; the recorded original build did not
xcodebuild -workspace VoodooI2C.xcworkspace -scheme VoodooI2C \
  -configuration Release -arch x86_64 \
  CONFIGURATION_BUILD_DIR=<out>/products \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

# VoodooGPIO — MUST use its own scheme, or a stale GPIO binary ships silently
xcodebuild -workspace VoodooI2C.xcworkspace -scheme VoodooGPIO \
  -configuration Release -arch x86_64 \
  CONFIGURATION_BUILD_DIR=<out>/gpio \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

# VoodooI2CHID — separate project; `rm -rf build` IS required here (stale-object failures)
cd "VoodooI2C Satellites/VoodooI2CHID" && rm -rf build
xcodebuild -project VoodooI2CHID.xcodeproj -target VoodooI2CHID \
  -configuration Release -arch x86_64 \
  CONFIGURATION_BUILD_DIR=<out>/chid \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

### Installing

`VoodooI2C.kext` carries the others as **plugins**. The layout is:

```
OC/Kexts/VoodooI2C.kext/Contents/MacOS/VoodooI2C
OC/Kexts/VoodooI2C.kext/Contents/PlugIns/VoodooGPIO.kext/…
OC/Kexts/VoodooI2C.kext/Contents/PlugIns/VoodooI2CHID.kext/…
OC/Kexts/VoodooI2C.kext/Contents/PlugIns/VoodooInput.kext/…      ← must be ENABLED
OC/Kexts/VoodooI2C.kext/Contents/PlugIns/VoodooI2CServices.kext/… ← never delete
```

In `config.plist → Kernel → Add`, all five of these must be `Enabled=true`:

```
VoodooI2C.kext
VoodooI2C.kext/Contents/PlugIns/VoodooI2CServices.kext
VoodooI2C.kext/Contents/PlugIns/VoodooGPIO.kext
VoodooI2C.kext/Contents/PlugIns/VoodooI2CHID.kext
VoodooI2C.kext/Contents/PlugIns/VoodooInput.kext
```

`VoodooPS2Controller.kext/Contents/PlugIns/VoodooInput.kext` must stay **disabled** — two
`VoodooInput` instances conflict.

> **Enabling `VoodooInput` was one of the two changes that actually made the touchpad work.**
> It is a single token, `<false/>` → `<true/>`. Do not skip it.

---

## 4. ACPI — `SSDT-TPDHID.aml`

The **only** ACPI table you add. `SSDT-TPDHID.dsl` is the source; it compiles byte-exactly with
`iasl` from ACPICA **20260408**:

```bash
iasl SSDT-TPDHID.dsl          # -> SSDT-TPDHID.aml, 284 bytes
```

| | |
|---|---|
| size | **284 bytes** |
| sha256 (first 16) | **`330b29ff2716f75b`** |
| OEM ID / Table ID | `ZPSS` / `TPDHID` |

Enable it in `config.plist → ACPI → Add` as `SSDT-TPDHID.aml`. It declares **one device**:

```asl
Scope (\_SB.PC00) {
    Device (ZTPD) {
        Name (_HID, "ASUP1207")            // ASUS touchpad
        Name (_CID, EisaId ("PNP0C50"))    // HID Protocol Device (I2C)
        Name (_UID, One)
        Name (_S0W, 0x03)
        Method (_STA, 0) { Return (0x0F) } // unconditional: always present
        Method (_DSM, 4, Serialized) { … } // GUID test — KNOWN BROKEN, see §7
        Method (XDSM, 4, Serialized) { … } // the working method
        Method (_CRS, 0) { … }             // I2cSerialBus + GpioInt
    }
}
```

Two details in `_CRS` are **hand-assembled** and must not be "cleaned up":

* `I2cSerialBus` — slave address **`0x15` (21)**, 400 kHz, source `\_SB.PC00.I2C3`
* `GpioInt` — **pin 23, hand-tuned**, because VoodooI2C reads the pin-table offset from raw bytes
  `+14..15` of the descriptor rather than parsing it

Positioning matters: `ZTPD` must be under `\_SB.PC00`, **not** inside `Scope(\_SB.PC00.I2C3)`.
Publishing it inside `I2C3` yields **0 devices**.

---

## 5. Why this is needed — the technical explanation

### The firmware's own touchpad devices are never created

The DSDT declares 24 touchpad devices (`TPD0`/`TPL1`) across six I2C controllers, but **macOS
never creates any of them**. They sit inside a root-level conditional spanning **3,638 DSDT lines**:

```asl
If ((PCHA == Zero))
    … 3,638 lines …
```

macOS embeds **ACPICA 20160930**, which performs a *two-pass* namespace load: pass 1 skips every
`If`/`Else`/`While` body, and the module-level code that would create these devices is never
executed. Measured: `TPD0`/`TPL1` count **= 0**, while `I2C0..I2C5` exist (their `Device`
declarations lie *outside* the block).

This was chased for a long time and three plausible fixes were each **measured and disproved**:

| attempt | result |
|---|---|
| The `_STA` fallbacks patched `Return (Zero)` → `Return (Ones)` (AML `A4 00` → `A4 FF`, 24 sites, length-preserving) | devices **still absent**; later **deliberately reverted** |
| Flipping the outer gate (`93 PCHA 00` → `94 PCHA 00`) | count still **0** |
| Exposing the EC gate fields as ACPI methods and reading them (`SSDT-DSHEC`) | gate values read fine (`PCHA=0`, `TPDT=5`, `I2SB=3`) — **gate is satisfied, devices still absent** |

That last measurement is the decisive one: the gate **passes**, and the devices still do not
exist. So the problem is not the gate's *value* — it is that the enclosing block never *runs*.

> **Correcting a widespread claim.** `Return (Ones)` marks an ACPI device **present**, it does not
> hide it: `Ones & 1 == 1`, so bit 0 (the *present* bit) is **set**. An earlier version of this
> repo's README stated the opposite. The `_STA` patch failed because the device objects are never
> created — not because of any `_STA` return value.

### The fix: synthesise the device where it is not gated

Since the firmware devices cannot be created, declare an equivalent device **outside** the
conditional — under `\_SB.PC00`. That is `SSDT-TPDHID.aml` above.

But a device alone is not enough. macOS also does not create injected ACPI devices **beneath an I2C
controller node**, so `\_SB.PC00.I2C3` has no children and `VoodooI2C`'s normal child-walk finds
nothing to attach to → **no `VoodooI2CDeviceNub` is ever created**. (Six controlled attempts to
inject a device under `I2C3` all failed; the identical declaration under `\_SB.PC00` publishes
fine.) That is what **patch 01** addresses: when the child walk comes up empty, search the ACPI
plane for the synthesised device and create the nub from it.

One more piece: `VoodooI2CHID`'s personality matches on
`IOPropertyMatch = { compatible = PNP0C50 }`. That property normally arrives because the child is a
real ACPI-plane device and Apple's ACPI layer publishes `_HID`/`_CID` as `compatible`. The
synthesised device does not carry it, so the personality could never match — which is why
`VoodooI2CHIDDevice` instances were always 0 with no error: it was never *considered*, not a
failed start. Patch 01 sets `compatible` on the nub.

### The two changes that actually made it work

1. the **`XDSM` method** in `SSDT-TPDHID.aml`
2. **enabling `VoodooInput.kext`** in `Kernel → Add` — one token

Everything else here is either a hard requirement (the I2C3 personality below) or a genuine bug fix
(the report length).

---

## 6. `VoodooI2CPCIIceLakeControllerI2C3` — required, and easy to lose

The shipped `VoodooI2C.kext/Contents/Info.plist` has **13** personalities; a clean build of the
patched source yields **12**. The extra one is:

```
VoodooI2CPCIIceLakeControllerI2C3
  IOClass        VoodooI2CPIController
  IOPCIMatch     0x777b8086&0xFFFFFFFF
  IOProbeScore   10000
  Comment        "Arrow Lake-H I2C3 only (8086:777b) -- keeps the nub off I2C0"
```

It exists **nowhere in the source tree** — it was added to the deployed kext's plist after the
build. Reproduce it by hand, or copy it from the ESP in this repo.

**Do not drop it.** Removing it made the boot **hang** at:

```
VoodooI2CPCIController: pci8086,777b starting i2c controller
```

It looks like inert configuration because no C++ references it. It is not: a personality is
declarative configuration that decides *which node the driver binds and at what probe score*.

Related, on `VoodooI2CPCIIceLakeController`:

```
IOPCIMatch    0x34e88086&0xFFFCFFFF 0x77788086&0xFFFCFFFF
```

The second entry is load-bearing. **Narrowing it made the machine unbootable.**

---

## 7. Known defects in what is shipped here

Stated plainly so nobody is surprised.

### `_DSM` is unsatisfiable — `XDSM` is what works

```asl
If ((Arg0 == 0x3CDFF6F7))     // 16-byte Buffer compared to an Integer
```

ACPICA reports a type mismatch and this can never be true, so `_DSM` always falls through and
returns `0x00`. The table works only because `XDSM` does the real job. Note `XDSM` has been
**deprecated upstream since 2020** (VoodooI2C PR #391).

The correct form compares the GUID as a **buffer**. `ToUUID()` is a compile-time operator and is
**not valid inside a method body**, so bind it to a `Name` in the device scope first:

```asl
Name (DSGD, ToUUID ("3cdff6f7-4267-4555-ad05-b30a3d8938de"))
…
If ((Arg0 == DSGD))           // 16-byte buffer vs 16-byte buffer
```

`tools/patch-ssdt-dsm.sh` performs this rewrite. It is **not** what is deployed — the deployed
table is the byte-exact 284-byte original.

### Patch 01 is machine-specific and not upstreamable as-is

It hard-codes the device name `"ZTPD"` (invented here) and fabricates the `compatible` property.
It also uses `Dsh`-prefixed identifiers that are meaningless outside this machine. It is correct
for this laptop and would need real work before it could go upstream.

### `SSDT-DSHEC.aml` is inert

The shipped config also enables `SSDT-DSHEC.aml` (502 B, `a9a81f988ef01cf5`) — 11 read-only methods
returning EC fields. Its only caller was a diagnostic kext that is disabled and not compiled into a
clean build. It is harmless and changes nothing; it is enabled on the working machine only by
inertia. You may omit it.

---

## 8. What was verified

| check | result |
|---|---|
| all four patches apply to fresh `5c0c99c` with `-p1` | **clean** |
| patched sources vs known-good sources | **byte-identical** (all 4) |
| `SSDT-TPDHID.dsl` → `.aml` with iasl 20260408 | **byte-identical**, `330b29ff2716f75b` |
| `VoodooGPIO` rebuilt from patched source | `309632 B`, same size as deployed |
| `VoodooI2CHID` rebuilt from patched source | `233744 B`, same size as deployed |

**Not verified:** the from-scratch `VoodooI2C` build has not been boot-tested on hardware. The
kexts shipped in this repo's ESP are the ones that *are* known to work.

---

## 9. Tools

| script | purpose |
|---|---|
| `tools/apply-patches.sh` | apply the four patches to a freshly cloned upstream tree |
| `tools/patch-ssdt-dsm.sh` | rewrite the broken `_DSM` GUID test to a valid buffer comparison |
