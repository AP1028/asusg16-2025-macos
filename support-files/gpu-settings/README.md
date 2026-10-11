# GPU driver settings — what the machine actually runs

Written because the root README previously described a set of `Booter`/`UEFI` GPU quirks as
"what the installer sets", and **that description does not match this machine**.

## Measured state

The NullMoth driver is confirmed running here:

```
Chipset Model:  NVIDIA GeForce RTX 5080 Laptop GPU
VRAM (Total):   16 GB
Metal Support:  Metal 3
```

and the config that produces that state contains **none** of the documented quirks:

| setting | README claimed post-install | **actual** | verdict |
|---|---|---|---|
| `Booter → Quirks → ResizeAppleGpuBars` | `-1` | **`0`** | mismatch |
| `UEFI → Quirks → ResizeGpuBars` | `13` | **`-1`** | mismatch |
| `Booter → Quirks → AllowRelocationBlock` | `true` (newly set) | `true` | already true, not a change |
| `Kernel → Block` (`IONDRVSupport`) | added | **empty** | mismatch |
| `Misc → Security → SecureBootModel` | `Disabled` | `Disabled` | matches |
| `NVRAM → Delete` | adds `boot-args`, `csr-active-config` | both present | matches |
| `Misc → Tools` | adds `NullMothSafe.efi` | **empty** | not present |

So three of the seven documented post-install changes are **absent** on a machine where the
driver demonstrably works. The table was describing a **different driver version's** installer,
not this system's state.

## What actually enables the driver here

One key:

```
NVRAM → Add → 7C436110-AB2A-4BBB-A880-FE41995C9F82 → boot-args
  … amfi_get_out_of_my_way=0x1 amfi=0x80 nvfb=1 nvaccel=1
```

- `nvfb=1 nvaccel=1` gate `com.nullmoth.NVRM` / `NVRMFB` / `NVAccel` / `NVRMAGDC`
- `amfi_get_out_of_my_way=0x1 amfi=0x80` are required because those kexts are **ad-hoc signed**

The driver's kexts are **not** in `OC/Kexts`. Nothing in this repo loads them — the flags only
*permit* them once the installer has placed them.

## Caveat on this record

This is measured from **one** machine, one driver version. It is not a statement that those quirks
are wrong in general — only that they are not what this system uses, and that presenting them as
post-install fact was incorrect.

If you hit `STOP 0x16` or the firmware framebuffer taking display index 0, the quirks in the
installer table are the documented remedies for those specific symptoms. Apply them if you see
those symptoms, not because a table said so.
