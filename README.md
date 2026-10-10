# ASUS ROG Zephyrus G16 GU605CW (2025) — OpenCore EFI

OpenCore EFI for **Arrow Lake-H**, for the NVIDIA driver **pre-install** state. This is the
first documented Arrow Lake-H **laptop** to reach a working macOS desktop.

| | |
|---|---|
| Model | ASUS ROG Zephyrus G16 **GU605CW** (2025) |
| CPU | Intel Core Ultra 9 **285H** (Arrow Lake-H) — 6 P + 8 E + 2 LP-E, 16 threads, **no HT** |
| iGPU | Intel Arc / Xe-LPG (no macOS driver in any version) |
| dGPU | NVIDIA GeForce **RTX 5080 Laptop** (10de:2c59) |
| MUX | **must be on dGPU** |
| macOS | 15 Sequoia (validated on 15.8.1 / 24H32) |
| SMBIOS | `MacBookPro16,2` |
| BIOS | Above 4G **on** · ReBAR **off** · CFG Lock **off** · VT-d off (or `DisableIoMapper`) · **MUX = dGPU** |

> **⚠️ This is the pre-install EFI. Fill in your own SMBIOS first — see the next section.**

## Before you boot: generate your own SMBIOS

The shipped `config.plist` has **masked placeholders**. Replace them or macOS will not activate
properly and Apple services will not work:

```
SystemSerialNumber = REPLACE0000
MLB                = REPLACE00000000000
SystemUUID         = 00000000-0000-0000-0000-000000000000
ROM                = 00:11:22:33:44:55
```

These are not shipped filled in on purpose: **serial + MLB + ROM together are what registers
iMessage, FaceTime and Find My**, so publishing a working set lets anyone else use that
identity.

Generate your own with [**GenSMBIOS**](https://github.com/corpnewt/GenSMBIOS):

1. Run `python3 GenSMBIOS.command`
2. Option **2** (Generate SMBIOS), type the model: **`MacBookPro16,2`**, count `1`
3. It prints a `Serial`, `Board Serial` (MLB) and `SmUUID`
4. Put them in `config.plist` → `PlatformInfo → Generic`:
   - `SystemSerialNumber` ← Serial
   - `MLB` ← Board Serial
   - `SystemUUID` ← SmUUID
   - `ROM` ← your NIC's MAC as 6 raw bytes (`<001122334455>`), or leave the placeholder
   - Leave `SystemProductName = MacBookPro16,2` and `UpdateSMBIOSMode = Custom` as they are
5. Verify the serial is not already registered with Apple (GenSMBIOS option 4 checks it)

`MacBookPro16,2` is a MacBook Pro 13" 2020 (Ice Lake) — the closest SMBIOS tier for an
XCPM-capable quad-core laptop, and what this machine runs.

## What makes Arrow Lake work

Three things, all required, all already in this config.

### 1. Repaired `DSDT.aml`

macOS embeds **ACPICA 20160930**, which does a *two-pass* namespace load: pass 1 skips every
`If`/`Else`/`While` body, yet still requires every top-level `Scope()` target to exist. On
`AE_NOT_FOUND` it deletes everything the table created and the whole load fails. Modern ACPICA
executes the table as a single term list, which is why Linux and Windows load the same table.

This DSDT has **six** such `Scope()` statements. The repair wraps them so pass 1 skips them and
module-level execution creates the targets:

- `Scope(_SB.PC00.XHCI.RHUB.HS07)` → `If (Zero) { … }` — length-preserving, *could* be an `ACPI → Patch`
- the five forward references (`HDAS` ×2, `SPI0` ×3) → `If (One) { Scope(X) { … } }` — **+4 bytes each**

**It cannot be an `ACPI → Patch`.** The five growths total **+20 bytes** (430740 → 430760), and
OpenCore's patch is strictly in-place — `OcAcpiPatchTables()` drops any entry where
`Find.Size != Replace.Size`. Ship the finished table via `ACPI → Add`; it keeps the original
signature and OEM IDs so it replaces the firmware table, and OpenCore recomputes the checksum.

Verified with `acpiexec` built from ACPICA `R09_30_16` (= 20160930, the version macOS embeds):
original → `[DSDT] table load failed`; repaired → loads clean, namespace identical (5955 objects
/ 190 devices / 118 regions / 978 methods). On hardware: **14 table load failures → 4**.

Exact byte-level repair (all six substitutions, offsets and the checksum procedure):
[`arrow-lake/DSDT-fixed.patch.txt`](arrow-lake/DSDT-fixed.patch.txt).

> This removes a genuine defect but was **not** the step that got the boot to userland. Ship it
> because the table is malformed for macOS's parser.

### 2. `ProvideCurrentCpuInfo` + permuted `APIC.aml`

XNU's `x86_validate_topology()` panics when the CPUID-derived thread count disagrees with the
MADT count. Arrow Lake-H has **three core types** (P, E, LP-E) and **two Atom native model IDs**
(`0x2` Crestmont, `0x3` Skymont).

`ProvideCurrentCpuInfo = true` — despite its documentation saying *"e.g. Intel Alder Lake"*, the
implementation selects by arithmetic (`IsAmpCpu = ThreadCount % CoreCount != 0`) plus an
`_x86_validate_topology` → `ret` patch, so it engages on any hybrid P+E part.

The firmware MADT is replaced so the six P-cores hold UIDs 0–5. The LAPIC set is unchanged; only
the UID assignment moves:

```
OEM:      uid 2,3,4,5 → LAPIC 16,18,20,22
patched:  uid 2,3,4,5 → LAPIC 32,40,48,56
          (LAPIC 0,8 → 0,1    LAPIC 64,66 → 14,15)
```

Confirmed on hardware: `AppleACPICPU: ProcessorId=2 LocalApicId=32 Enabled`.

### 3. `SSDT-PLUG-ALT`, and `CpuTopologyRebuild` disabled

`SSDT-PLUG` injects `plugin-type=1` only where `ObjectType == 0x0C` (a `Processor`). Arrow Lake
declares CPUs as **`Device`** objects (`_HID "ACPI0007"`), so plain `SSDT-PLUG` **silently does
nothing** and XCPM never attaches. `SSDT-PLUG-ALT` creates `Processor (CP00…CP63)` under `\_SB`
with a Darwin-gated `_STA`.

`CpuTopologyRebuild.kext` is present but **disabled** — its author states it cannot handle the
mobile P + E + LP-E layout, and it is what panics. No `ctrsmt=` boot argument.

## After macOS is installed: the NVIDIA driver

**The driver does not write to the EFI.** Its installer puts kexts in `/Library/Extensions`,
bundles in `/Library/GPUBundles`, and rebuilds the auxiliary kernel collection. It never touches
`config.plist`. But the EFI **does** need different values once the driver is in, so this repo
ships the pre-install state and you apply the post-install changes yourself:

| | this repo (pre-install) | after installing the driver |
|---|---|---|
| `Booter → Quirks → ResizeAppleGpuBars` | **`0`** | **`-1`** |
| `UEFI → Quirks → ResizeGpuBars` | `-1` | `-1` (leave alone) |
| `Kernel → Block → com.apple.iokit.IONDRVSupport` | **absent** | **add it** |
| boot-args | `-v debug=0x100 keepsyms=1 -vi2c-force-polling amfi_get_out_of_my_way=0x1 amfi=0x80` | add `nvfb=1 nvaccel=1 -nvkmsnosmooth` |

- **`ResizeAppleGpuBars`** must be `0` while installing: with the full BAR, macOS re-places the
  large BAR during PCI setup and the firmware framebuffer goes with it, so the screen freezes
  right after `PCI configuration end`. The NVIDIA driver needs the **full BAR afterwards** (BAR1
  is 16 GB here), so switch to `-1`.
- **`IONDRVSupport` block** makes the driver hold display index 0. It must be **absent** while
  installing and added after.
- **Do not let tooling "help" with the BAR quirks.** Anything that sets `ResizeGpuBars` to `13`
  will cost you the display.

Install the driver from [nullmoth/nvidia-macos-driver](https://github.com/nullmoth/nvidia-macos-driver)
(1.5.0 validated here), then reboot.

## Status

| | Component | State | Notes |
|---|---|---|---|
| ✅ | **NVIDIA dGPU + Metal** | **Working** | Metal 3, after the driver install above |
| ✅ | **Internal display (eDP)** | **Working** | 2560×1600 @ 240 Hz |
| ✅ | **External display (DP)** | **Working** | 3440×1440 @ 60 Hz, hot-plug |
| ✅ | **Internal keyboard** | **Working** | PS/2 via VoodooPS2Controller |
| ✅ | **USB-A** | **Working** | |
| ✅ | **USB-C** | **Working** | Data; DP-alt-mode output untested |
| 🚧 | **Keyboard function keys** | **Partial** | Consumer-page HID reports work; the vendor page `0xFF31` reports (brightness, touchpad toggle) are discarded by macOS. Workable with `BrightnessKeys.kext` + a Karabiner rule on Ctrl+F1/F2 |
| 🚧 | **Trackpad** | **WIP** | `VoodooI2C`/`VoodooI2CHID` load and drive the I2C controller, but **all 24 touchpad ACPI devices (`TPD0`/`TPL1`) are never created** — see below |
| 🔧 | **Bluetooth** | **Needs upstream** | Intel `8087:0037` ("BlazarU") is absent from `IntelBluetoothFirmware`. It is a standard USB device and the framework already drives 12 other Intel chips — **path: add the device ID + a firmware blob from `linux-firmware`** |
| ❌ | **Wi-Fi** | **Not possible** | Intel `8086:7740` CNVi; appears nowhere in itlwm. No driver exists. Use a USB Ethernet adapter |
| ❌ | **Audio (internal)** | **Not possible** | Realtek **ALC1308 on SoundWire**, not legacy HDA — macOS `AppleHDA` has no SoundWire transport. AppleALC loads correctly and has no codec to patch. **USB and HDMI/DP (dGPU) audio work natively** |

### Trackpad (WIP)

Not a kext problem — the ACPI devices are missing. All 24 `TPD0`/`TPL1` devices across six I2C
controllers are gated by:

```asl
If (((TPDT != Zero) && (I2CN & One)))
    Return (0x0F)
Return (Zero)
```

where `I2CN = SDS0` (an EC value) is set in `_INI` and reads zero on macOS. The 24 `_STA`
fallbacks were already patched `Return (Zero)` → `Return (Ones)` (AML `A4 00` → `A4 FF`, same
length, verified surgical, table still loads with an identical namespace) — **devices still
absent**.

Next step: the whole block sits inside `If ((PCHA == Zero))` and **`PCHA` is referenced 22× but
declared nowhere**, likely in an ASUS SSDT. Try an SSDT defining `PCHA`, or patch the outer `If`.

## Known issues in this config

- **`layout-id` is an integer.** In `DeviceProperties → Add → PciRoot(0x0)/Pci(0x1f,0x3)`,
  `layout-id = 52` should be `<data>` (`<34000000>`). macOS requires data here; AppleALC
  compensates via its own `alc-layout-id`, so it is currently harmless. Moot regardless — the
  codec is SoundWire with no macOS driver.
- **`PciRoot(0x0)/Pci(0x2,0x0) → disable-gpu = True`** disables the Intel iGPU. This is
  **load-bearing**, not cosmetic: the Xe-LPG iGPU has no macOS driver in any version.

## Repo layout

```
EFI/
  BOOT/BOOTX64.EFI
  OC/
    OpenCore.efi
    config.plist            ← pre-install (ResizeAppleGpuBars 0, no IONDRVSupport block)
    ACPI/   DSDT.aml (repaired) · APIC.aml (permuted) · SSDT-PLUG-ALT + 9 more
    Drivers/ HfsPlus.efi · OpenRuntime.efi · ResetNvramEntry.efi
    Kexts/   22 kexts
    Tools/   NullMothSafe.efi
arrow-lake/
  DSDT-fixed.patch.txt   exact byte-level DSDT repair (6 substitutions) + verification
```

## Credits

- [NullMoth NVIDIA driver](https://github.com/nullmoth/nvidia-macos-driver) — the dGPU display
- [Acidanthera](https://github.com/acidanthera) — OpenCore, Lilu, VirtualSMC, WhateverGreen,
  AppleALC, VoodooPS2, and the `SSDT-PLUG-ALT` sample
- [VoodooI2C](https://github.com/VoodooI2C/VoodooI2C) — I2C trackpad (WIP here)
- [CpuTopologyRebuild](https://github.com/b00t0x/CpuTopologyRebuild) — where the mobile
  three-core-type problem is documented, and why it is disabled here
- [GenSMBIOS](https://github.com/corpnewt/GenSMBIOS) — for the SMBIOS values above
- 1401 — the USB builder whose base config this started from
