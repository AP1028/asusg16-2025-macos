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
| Firmware | see [Firmware settings](#firmware-settings) · **MUX = dGPU** |

> **⚠️ This is the pre-install EFI. Fill in your own SMBIOS first — see the next section.**

## Before you boot: fill in a valid SMBIOS

The shipped `config.plist` has **masked placeholders**:

```
SystemSerialNumber = REPLACE0000
MLB                = REPLACE00000000000
SystemUUID         = 00000000-0000-0000-0000-000000000000
ROM                = 00:11:22:33:44:55
```

**A masked or inconsistent SMBIOS will stop the driver installing.** This is not about iMessage —
the installer's helper identifies *which EFI it may edit* by matching the running machine against
the config:

- `hw.model` must equal the config's `PlatformInfo → Generic → SystemProductName`
- if OpenCore's `boot-path` variable is absent, it falls back to matching
  `IOPlatformSerialNumber` against the config's `SystemSerialNumber` — *"the running Mac's serial
  number IS the config's SystemSerialNumber, OpenCore wrote it into this boot"*

If nothing matches, it refuses to touch any config and stops with:

```
no OpenCore config for this Mac (<hw.model>) on any connected disk - plug in the disk or USB
stick OpenCore started from, then try again (the NOTE lines above show what each partition holds)
```

So a well-formed, self-consistent identity is a **prerequisite for the driver install**, not a
bonus. A real serial does *not* promise working iMessage/FaceTime — but a placeholder or a
mismatched one will block the install outright.

Generate yours with [**GenSMBIOS**](https://github.com/corpnewt/GenSMBIOS):

1. Run `python3 GenSMBIOS.command`
2. Option **2** (Generate SMBIOS), model **`MacBookPro16,2`**, count `1`
3. It prints a `Serial`, `Board Serial` (MLB) and `SmUUID`
4. Put them in `config.plist` → `PlatformInfo → Generic`:
   - `SystemSerialNumber` ← Serial
   - `MLB` ← Board Serial
   - `SystemUUID` ← SmUUID
   - `ROM` ← your NIC's MAC as 6 raw bytes (`<001122334455>`), or keep the placeholder
5. **Leave `SystemProductName = MacBookPro16,2` and `UpdateSMBIOSMode = Custom` as they are.**
   Changing the model changes `hw.model`, and then the installer cannot match the config to the Mac
6. Sanity-check before rebooting — `hw.model` and the config must agree:

   ```sh
   sysctl -n hw.model
   plutil -extract PlatformInfo.Generic.SystemProductName raw -o - /Volumes/EFI/EFI/OC/config.plist
   ```

`MacBookPro16,2` is a MacBook Pro 13" 2020 (Ice Lake) — the closest XCPM-capable quad-core laptop
tier, and what this machine runs.

## Firmware settings

**This laptop's BIOS does not expose "Above 4G Decoding" or "Resizable BAR" at all.** That is
normal for ASUS laptops — those toggles belong to desktop boards, and the usual
"Above 4G on / ReBAR off" advice copied from desktop guides does not apply and will send you
looking for menus that are not there. Both behaviours are simply on:

| | measured on this machine |
|---|---|
| 64-bit PCI decoding | **active** — the driver's BAR1 is `0x3f800000000+0x400000000`, a **16 GB** aperture above 4 GB |
| Resizable BAR | **not a toggle, and not needed** — BAR1 already comes up at its full 16 GB |
| Firmware | `2094.80.5.0.0`, OpenCore `REL-109-2026-09-30` |
| SIP | `csr-active-config = 0x0A43` (set by the installer) |

### Secure Boot — must be **off**

Measured: the UEFI `SecureBoot` variable reads `%01`… but no kext in this setup is Apple-signed
(the NullMoth kexts are ad-hoc signed), so Apple Secure Boot refuses them. Turn **Secure Boot off**
in the BIOS. The installer also sets `Misc → Security → SecureBootModel = Disabled` for the same
reason, and that is an OpenCore setting, separate from the firmware toggle — you need the firmware
one off to boot at all, and the OpenCore one is handled for you.

### Fast Boot — leave it **off**

Fast Boot can skip USB enumeration to shorten POST, which is exactly what you do not want when
booting OpenCore from a USB stick: the stick can simply not appear in the boot menu. Leave it off
while installing, and while you still need the USB as a way back in. Once macOS boots from the
internal disk on its own, it can go back on — but there is no benefit here.

### Also worth knowing

- **CFG Lock / VT-d** — if your unit exposes them, turn CFG Lock off and VT-d off (or keep
  `DisableIoMapper = true`, which this config sets). Not all ASUS laptop BIOS revisions show them.
- **`ScanPolicy = 0` — the picker lists every bootable volume.** Zero means no file-system filter
  and no device-type filter: APFS, HFS+, ESP, NTFS and Linux volumes on SATA, NVMe, USB, SD and PCI
  devices are all scanned. This matters because a macOS installer — including an Apple
  `createinstallmedia` stick — is **HFS+ on a USB device**, so any policy that does not allow both
  hides exactly the volume you are trying to boot. Raise this value later only if you want to hide
  other operating systems; OpenCore's own failsafe is `0x10F0103` (APFS on SATA/SAS/SCSI/NVMe,
  which excludes USB and HFS).
- **`Misc → Tools` ships empty, on purpose.** The `1401: Remove NVIDIA driver` picker entry and
  `NullMothSafe.efi` belong to the post-install state; the driver installer adds both. Before the
  driver is installed there is nothing to remove, and the entry is a dead end that also delays
  finding the real problem.
- **Do not let tooling "help" with the BAR quirks.** The installer sets `ResizeGpuBars = 13` and
  `ResizeAppleGpuBars = -1` after the driver is in. Since this BIOS has no ReBAR toggle to fight
  with, those settings are the whole story.

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

## After macOS is installed: run the driver installer — it flips the EFI for you

**You do not edit `config.plist` by hand.** The NullMoth installer's privileged helper
(`nullmoth-setup.sh`, shipped in the 1401 Mac app) rewrites the OpenCore config itself once the
driver is in. This repo ships the **pre-install** state; the installer converts it.

The helper makes these changes, and backs up your config to
`config.plist.nullmoth-<timestamp>` first:

| Setting | Pre-install (shipped here) | What the installer sets |
|---|---|---|
| `Booter → Quirks → ResizeAppleGpuBars` | `0` | **`-1`** — macOS sees the full BAR |
| `UEFI → Quirks → ResizeGpuBars` | `-1` | **`13`** — 8 GB BAR, full memory bandwidth |
| `Kernel → Block` | *absent* | **adds `com.apple.iokit.IONDRVSupport` (`Strategy: Exclude`)** — otherwise the firmware framebuffer takes display index 0 from NVRMFB |
| `Misc → Security → SecureBootModel` | *unchanged* | **`Disabled`** unless SIP is fully on — Apple Secure Boot refuses kexts Apple did not sign |
| `Booter → Quirks → AllowRelocationBlock` | *unchanged* | **`true`**, only where `ProvideCustomSlide` and `AvoidRuntimeDefrag` are already on — the bigger BAR moves memory around and `boot.efi` otherwise stops at `STOP 0x16` |
| `NVRAM → Delete` | *unchanged* | adds `boot-args` and `csr-active-config`, so OpenCore rewrites them every boot |
| `Misc → Tools` | **empty** — no entries, no `Tools/` | adds `NullMothSafe.efi` and the boot-picker entry — the way back if the driver ever stops macOS starting |

So the sequence is: **boot this EFI → install macOS → run the driver installer → reboot.** The
installer does the rest. It prints every change it makes (`CHANGE …`) and keeps a timestamped
backup, and `nullmoth-setup.sh` is re-runnable — if OpenCore already has every setting it needs
it reports `OpenCore already has every setting the driver needs` and changes nothing.

One caveat from the installer's own notes: if SIP is still fully enabled in the running system,
it defers the SIP/Secure-Boot/boot-args changes and only applies the `UEFI`/`Booter`/`Kernel.Block`
ones — so run it again after adjusting SIP.

Getting the driver: [nullmoth/nvidia-macos-driver](https://github.com/nullmoth/nvidia-macos-driver)
releases (1.5.0 validated here). On a machine you install by hand rather than via 1401, the Mac app
is the thing that calls the helper.

## Status

| | Component | State | Notes |
|---|---|---|---|
| ✅ | **NVIDIA dGPU + Metal** | **Working** | Metal 3, after the driver install above |
| ✅ | **Internal display (eDP)** | **Working** | 2560×1600 @ 240 Hz |
| ✅ | **External display (DP)** | **Working** | 3440×1440 @ 60 Hz, hot-plug |
| ✅ | **Internal keyboard** | **Working** | PS/2 via VoodooPS2Controller |
| ✅ | **USB-A** | **Working** | |
| ✅ | **USB-C** | **Working** | Data **and DP alt mode** |
| 🚧 | **Keyboard function keys** | **Partial** | Consumer-page HID reports work; the vendor page `0xFF31` reports (brightness, touchpad toggle) are discarded by macOS. Workable with `BrightnessKeys.kext` + a Karabiner rule on Ctrl+F1/F2 |
| 🚧 | **Trackpad** | **WIP** | `VoodooI2C`/`VoodooI2CHID` load and drive the I2C controller, but **all 24 touchpad ACPI devices (`TPD0`/`TPL1`) are never created** — see below |
| 🔧 | **Bluetooth** | **Needs upstream** | Intel `8087:0037` ("BlazarU") is absent from `IntelBluetoothFirmware`. It is a standard USB device and the framework already drives 12 other Intel chips — **path: add the device ID + a firmware blob from `linux-firmware`** |
| ❌ | **Wi-Fi** | **Not possible** | Intel `8086:7740` CNVi; appears nowhere in itlwm. No driver exists. Use a USB Ethernet adapter |
| ❌ | **Audio (internal)** | **Not possible** | Realtek **ALC1308 on SoundWire**, not legacy HDA — macOS `AppleHDA` has no SoundWire transport. AppleALC loads correctly and has no codec to patch. **Use USB audio, which works natively.** NVIDIA HDMI/DP audio over the dGPU is not working |

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
    config.plist            ← pre-install (ScanPolicy 0, ResizeAppleGpuBars 0,
                              no IONDRVSupport block, Misc → Tools empty)
    ACPI/   DSDT.aml (repaired) · APIC.aml (permuted) · SSDT-PLUG-ALT + 9 more
    Drivers/ HfsPlus.efi · OpenRuntime.efi · ResetNvramEntry.efi
    Kexts/   22 kexts
    (no Tools/ — the NullMoth picker entry and NullMothSafe.efi arrive with the installer)
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
