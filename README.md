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

Three things, all required, all already in this config:

1. **Repaired `DSDT.aml`** — macOS embeds ACPICA 20160930, whose two-pass namespace load rejects
   six top-level `Scope()` forward references in the stock table. The repair wraps them; it cannot
   be an `ACPI → Patch` because the growth is +20 bytes and OpenCore's patch is in-place only.
   Result on hardware: **14 table load failures → 4**.
2. **`ProvideCurrentCpuInfo = true` + permuted `APIC.aml`** — XNU's `x86_validate_topology()`
   panics when CPUID and MADT disagree. Arrow Lake-H has three core types (P, E, LP-E) and two
   Atom native model IDs. The MADT is replaced so the six P-cores hold UIDs 0–5.
3. **`SSDT-PLUG-ALT`, not `SSDT-PLUG`** — Arrow Lake declares CPUs as `Device` objects
   (`_HID "ACPI0007"`), not `Processor`, so plain `SSDT-PLUG` silently does nothing and XCPM never
   attaches. `CpuTopologyRebuild.kext` is present but disabled; it is what panics.

Full technical detail, verification and the byte-level repair:
[`support-files/arrow-lake/README.md`](support-files/arrow-lake/README.md).

## This repo ships the PRE-INSTALL EFI only

`EFI/` is the pre-install OpenCore tree: what you boot to install macOS. Its SMBIOS is **masked
placeholders** on purpose — the NullMoth installer will not touch a config until the running
machine's identity matches it, so you must fill in your own before the driver install.

**A snapshot of a finished, working install is deliberately NOT in this repo.** It would carry a
real, valid SMBIOS — serial, MLB and UUID — and publishing that lets anyone clone the identity.
The post-install state is documented instead:

| what | where |
|---|---|
| how to generate a valid identity | [`support-files/smbios/`](support-files/smbios/README.md) |
| what the installer changes, and what a running machine ends up with | [`support-files/gpu-settings/`](support-files/gpu-settings/README.md) |

> ⚠️ **If you fork this repo, keep your own SMBIOS out of it.** A committed serial is public
> forever, including in the git history after you delete the file.

## Config variants: pre-NVIDIA vs post-install

`EFI/OC/` ships **three** configs. Only `config.plist` is read at boot; the other two are
reference copies you rename into place.

| file | use when | boot-args |
|---|---|---|
| `config.plist` | **default** — NullMoth driver installed | `… amfi=0x80 nvfb=1 nvaccel=1` |
| `config.plist.pre-nvidia` | **before** the NullMoth driver | `… amfi=0x80` |
| `config.plist.postinstall` | what the installer's boot-args change amounts to | `… amfi=0x80 nvfb=1 nvaccel=1` |

**The two NVIDIA flags are the only difference between these files**, and it is exactly one key:
`NVRAM → Add → … → boot-args`. `nvfb=1 nvaccel=1` gate the NullMoth driver's kexts
(`com.nullmoth.NVRM` / `NVRMFB` / `NVAccel` / `NVRMAGDC`). Without them the dGPU does not come up
at all. Those kexts are **not** in `OC/Kexts` — nothing in this repo loads them; the flags only
*permit* them once the installer has put them in place.

`config.plist` and `config.plist.postinstall` are **functionally identical**; they differ only in
debug hygiene (`AppleDebug` and one disabled `Misc.Entries` entry), which `postinstall` drops.

### What a running machine has that the stock tree does not

The installer rewrites the config, so a finished machine differs from `EFI/config.plist` like this:

```
boot-args        … amfi=0x80 nvfb=1 nvaccel=1 nvfbheads=4 -nvkmsnosmooth ipc_control_port_options=0
ResizeGpuBars    13          (stock: -1)
ResizeAppleGpuBars -1        (stock: 0)
Kernel → Block   1 entry     (com.apple.iokit.IONDRVSupport, Exclude)
Misc → Tools     1 entry     (NullMothSafe.efi — the recovery path)
ScanPolicy       524547      (stock: 0)
```

Note `ScanPolicy 524547` is **correct for a fixed disk** — it lists only APFS-on-NVMe. It is the
stock tree that must keep `0`, because an installer stick is HFS+ on USB.

### What is identical in all three

```
14 enabled ACPI entries   (12 baseline + SSDT-DSHEC + SSDT-TPDHID)
 5 enabled VoodooI2C entries, incl. the nested VoodooInput
ScanPolicy = 0            every bootable volume is listed
Misc → Tools             empty (see 64c7d6f — the NullMoth entry is a dead end pre-install)
PciRoot(0x0)/Pci(0x2,0x0) → disable-gpu = True
```

`disable-gpu` on the Intel iGPU stays in **all three**: the Xe-LPG iGPU has no macOS driver, so
this is load-bearing and unrelated to the NVIDIA driver being present.

### Runtime flags that had to survive the rebuild

Two settings are easy to lose and both are load-bearing:

- **`amfi_get_out_of_my_way=0x1 amfi=0x80`** — the NullMoth kexts are ad-hoc signed, so without
  these they are refused.
- **`-vi2c-force-polling` is deliberately absent.** The stock config carried it. The trackpad now
  works in interrupt mode, so polling was removed; re-adding it is unnecessary.

> ⚠️ `boot-args` also appears in `NVRAM → Delete`. OpenCore therefore **rewrites boot-args from
> the config on every boot** — flags typed at the picker do not persist, and the config is the
> single source of truth.

### Installing the driver

Run the NullMoth installer; its helper (`nullmoth-setup.sh`) rewrites `config.plist` itself, adds
`Misc → Tools → NullMothSafe.efi`, and copies the tool. You do not hand-edit the plist. If you
prefer to do it manually, apply exactly the one-key delta:

```sh
# pre-NVIDIA -> post-install: append the two flags
/usr/libexec/PlistBuddy -c "Set :NVRAM:Add:7C436110-AB2A-4BBB-A880-FE41995C9F82:boot-args \
  '-v debug=0x100 keepsyms=1 amfi_get_out_of_my_way=0x1 amfi=0x80 nvfb=1 nvaccel=1'" \
  EFI/OC/config.plist
```

## After macOS is installed: run the driver installer — it flips the EFI for you

**You do not edit `config.plist` by hand.** The NullMoth installer's privileged helper
(`nullmoth-setup.sh`, shipped in the 1401 Mac app) rewrites the OpenCore config itself once the
driver is in. This repo ships the **pre-install** state; the installer converts it.

The helper backs your config up to `config.plist.nullmoth-<timestamp>` first, then edits it.

> **Correction.** An earlier version of this README presented a table of `Booter`/`UEFI` GPU
> quirks as "what the installer sets". **That table does not describe the machine this repo was
> taken from.** The verified-working config here runs the NullMoth driver at full Metal 3 with
> `ResizeAppleGpuBars = 0`, `ResizeGpuBars = -1`, no `AllowRelocationBlock` change and no
> `Kernel → Block` entry — i.e. *none* of those quirks. Treat the table as installer documentation
> for a different driver version, **not** as post-install state.

What is **measured** in the shipped config, and therefore what the driver actually runs with here
(see [`support-files/gpu-settings/README.md`](support-files/gpu-settings/README.md) for the full
comparison):

| Setting | Value in this repo | note |
|---|---|---|
| `Booter → Quirks → ResizeAppleGpuBars` | `0` | unchanged from stock |
| `UEFI → Quirks → ResizeGpuBars` | `-1` | unchanged from stock |
| `Booter → Quirks → AllowRelocationBlock` | `true` | also `ProvideCustomSlide`/`AvoidRuntimeDefrag` are `true` |
| `Kernel → Block` | *empty* | **no** `IONDRVSupport` block |
| `Misc → Security → SecureBootModel` | `Disabled` | required — Apple Secure Boot refuses ad-hoc-signed kexts |
| `NVRAM → Delete` | includes `boot-args`, `csr-active-config` | so OpenCore rewrites them every boot |
| `Misc → Tools` | **empty** | see `64c7d6f`; the installer adds `NullMothSafe.efi` |
| `NVRAM → boot-args` | `… amfi=0x80 nvfb=1 nvaccel=1` | **this is what enables the driver** |

So the practical sequence is: **boot this EFI → install macOS → run the driver installer → reboot.**
The installer adds its own tool entry and tool binary; those are deliberately not shipped
pre-install. It prints every change it makes (`CHANGE …`) and is re-runnable — if OpenCore already
has every setting it needs it reports
`OpenCore already has every setting the driver needs` and changes nothing.

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
| ✅ | **Trackpad** | **Working** | Multitouch, gestures, tap-to-click. Requires patched `VoodooI2C`/`VoodooI2CHID`/`VoodooGPIO`, the authored `SSDT-TPDHID.aml`, and `VoodooInput.kext` **enabled** — see [`support-files/trackpad/`](support-files/trackpad/) |
| 🔧 | **Bluetooth** | **Needs upstream** | Intel `8087:0037` ("BlazarU") is absent from `IntelBluetoothFirmware`. It is a standard USB device and the framework already drives 12 other Intel chips — **path: add the device ID + a firmware blob from `linux-firmware`** |
| ❌ | **Wi-Fi** | **Not possible** | Intel `8086:7740` CNVi; appears nowhere in itlwm. No driver exists. Use a USB Ethernet adapter |
| ❌ | **Audio (internal)** | **Not possible** | Realtek **ALC1308 on SoundWire**, not legacy HDA — macOS `AppleHDA` has no SoundWire transport. AppleALC loads correctly and has no codec to patch. **Use USB audio, which works natively.** NVIDIA HDMI/DP audio over the dGPU is not working |

### Trackpad

**Working.** The firmware's own 24 touchpad devices (`TPD0`/`TPL1`) are never created by macOS —
they sit inside a root-level `If ((PCHA == Zero))` spanning 3,638 DSDT lines that macOS's ACPICA
never executes — so an equivalent device is **synthesised** by `SSDT-TPDHID.aml` under
`\_SB.PC00`, and patched `VoodooI2C` locates it and creates the nub.

The two changes that actually made it work were the **`XDSM` method** in that SSDT and
**enabling `VoodooInput.kext`**.

Patches, build instructions, the SSDT source and the full technical explanation:
[`support-files/trackpad/README.md`](support-files/trackpad/README.md).

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
  BOOT/BOOTX64.EFI          OpenCore's own launcher (self-contained; see note below)
  OC/
    OpenCore.efi
    config.plist            ← the default: NVIDIA flags present (nvfb/nvaccel)
    config.plist.pre-nvidia ← same, with those two flags removed
    config.plist.postinstall← same as config.plist, debug hygiene tidied
    ACPI/   26 tables on disk; 14 enabled. The enabled set is DSDT.aml (repaired),
            APIC.aml (permuted), SSDT-TPDHID.aml (the trackpad device), SSDT-PLUG-ALT
            and 10 others. The rest are disabled diagnostic probes — harmless, and
            left in place so the working set is reproducible.
    Drivers/ HfsPlus.efi · OpenRuntime.efi · ResetNvramEntry.efi
    Kexts/  21 kexts, + 4 plugins inside VoodooI2C.kext
    (no Tools/ — the NullMoth picker entry and NullMothSafe.efi arrive with the installer)
support-files/
  arrow-lake/    the Arrow Lake technical write-up + byte-level DSDT repair
  gpu-settings/  what the machine actually runs vs what the installer docs claim
  smbios/        generating a valid identity with macserial
  trackpad/      the trackpad fix: patches, SSDT, build instructions, technical explanation
```

> **`BOOT/BOOTX64.EFI` must be OpenCore's launcher** (`d0163dfbe5d2ea46`, 24,576 B) — it is
> self-contained and loads `OC/OpenCore.efi` from the same volume. Do **not** put a
> **systemd-boot** binary there: systemd-boot 261.3 (`5350e2e8bcbe9e73`) reads
> `\loader\entries\*.conf`, which only exist on a systemd-boot ESP, and fails everywhere else
> with *"No loader found."* This exact mix-up is called out in `.gitignore`.

## Credits

- [NullMoth NVIDIA driver](https://github.com/nullmoth/nvidia-macos-driver) — the dGPU display
- [Acidanthera](https://github.com/acidanthera) — OpenCore, Lilu, VirtualSMC, WhateverGreen,
  AppleALC, VoodooPS2, and the `SSDT-PLUG-ALT` sample
- [VoodooI2C](https://github.com/VoodooI2C/VoodooI2C) — I2C trackpad (WIP here)
- [CpuTopologyRebuild](https://github.com/b00t0x/CpuTopologyRebuild) — where the mobile
  three-core-type problem is documented, and why it is disabled here
- [GenSMBIOS](https://github.com/corpnewt/GenSMBIOS) — for the SMBIOS values above
- 1401 — the USB builder whose base config this started from
