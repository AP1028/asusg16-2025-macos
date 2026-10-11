# What makes Arrow Lake work

Three things, all required, all already in this repo's `config.plist` and `EFI/OC/ACPI/`.
This is the technical detail behind the "What makes Arrow Lake work" summary in the root README.

---

## 1. Repaired `DSDT.aml`

macOS embeds **ACPICA 20160930**, which performs a *two-pass* namespace load: pass 1 skips every
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
[`DSDT-fixed.patch.txt`](DSDT-fixed.patch.txt).

> This removes a genuine defect but was **not** the step that got the boot to userland. Ship it
> because the table is malformed for macOS's parser.

The shipped table is `1da5017b6a147719`, 430,760 bytes, and is **not** modified at runtime — no
`ACPI → Patch` entry touches it. (`ACPI → Patch` contains only two unrelated renames:
`GPI0 _STA → XSTA` and `_OSI → XOSI`.)

### A note on the 24 `_STA` fallbacks

This DSDT declares 24 touchpad devices (`TPD0`/`TPL1`) whose `_STA` methods fall back to
`Return (Zero)`. At one point those were patched to `Return (Ones)` (AML `A4 00` → `A4 FF`, 24
sites, length-preserving) in an attempt to make the devices appear. **It did not work, and the
change was deliberately reverted** — the table shipped here is the reverted one.

> **Correction to an earlier claim in this repo.** The patch was described as making the devices
> *appear*, and `Return (Ones)` was described as *clearing* the ACPI present bit. That is
> arithmetically wrong: `Ones & 1 == 1`, so bit 0 (the *present* bit) is **set**. The devices did
> not appear because the objects are never *created* — they sit inside a root-level
> `If ((PCHA == Zero))` spanning 3,638 DSDT lines that macOS's ACPICA never executes. See
> [`../trackpad/README.md`](../trackpad/README.md) §5.

Full detail of that investigation: `iasl-defects.txt` in this folder.

---

## 2. `ProvideCurrentCpuInfo` + permuted `APIC.aml`

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

---

## 3. `SSDT-PLUG-ALT`, and `CpuTopologyRebuild` disabled

`SSDT-PLUG` injects `plugin-type=1` only where `ObjectType == 0x0C` (a `Processor`). Arrow Lake
declares CPUs as **`Device`** objects (`_HID "ACPI0007"`), so plain `SSDT-PLUG` **silently does
nothing** and XCPM never attaches. `SSDT-PLUG-ALT` creates `Processor (CP00…CP63)` under `\_SB`
with a Darwin-gated `_STA`.

`CpuTopologyRebuild.kext` is present but **disabled** — its author states it cannot handle the
mobile P + E + LP-E layout, and it is what panics. No `ctrsmt=` boot argument.

---

## Files here

| file | contents |
|---|---|
| `DSDT-fixed.patch.txt` | exact byte-level DSDT repair (6 substitutions) + verification |
| `iasl-defects.txt` | the six malformed `Scope()` sites, as reported by `iasl` |
