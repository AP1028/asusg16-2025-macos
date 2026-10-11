# SMBIOS — generating a valid identity

> ## ⚠️ Never commit a real identity
>
> A valid serial + MLB + UUID is a **cloneable Apple identity**. Once committed it is public
> permanently — deleting the file later does not remove it from git history, forks, or caches.
>
> This repo deliberately ships **masked placeholders only**. Generate your identity locally, put it
> on your own ESP, and keep it out of version control. The examples below use `<your-serial>`
> rather than a real one for exactly this reason.

The stock `EFI/` tree ships **masked placeholders**. The NullMoth installer will not touch a config
until the running machine's identity matches it, so a self-consistent SMBIOS is a **prerequisite
for the driver install**, not a nicety. This folder is how the identity in `EFI-RUNNING/` was made.

---

## Use macserial — it is the community-standard generator

`macserial` ships with **OpenCorePkg**, under `Utilities/macserial`. It is a single C99 file plus a
generated model table, so it builds anywhere:

```sh
# from an OpenCorePkg checkout
cd Utilities/macserial
cc -std=c99 -O2 -I. -o macserial macserial.c UserPseudoRandom.c \
   -Wl,-framework,IOKit -Wl,-framework,CoreFoundation      # macOS
# on Linux drop the two -Wl,-framework flags
```

`UserPseudoRandom.c` lives in `User/Library/` of the same checkout; `UserPseudoRandom.h` in
`User/Include/`.

## Generate

```sh
./macserial -m MacBookPro16,2 -n 1
#   C02XXXXXXXXML7H | C02YYYYYYYYP8PG8C
#   ^ serial          ^ MLB      (yours will differ — these are shape only)
```

Verify before you use it:

```sh
./macserial --info   <your-serial>   # decodes country/year/week/model
./macserial --verify <your-mlb>      # "Valid MLB checksum."
```

---


## ⚠️ Use the PAIRED `-n` output — do not re-derive the MLB

`macserial --mlb <serial>` looks like the canonical "MLB for this serial", but **it re-randomises
the suffix on every call**:

```
$ ./macserial --mlb <your-serial>
C02XXXXXXXXP8PGJA
$ ./macserial --mlb <your-serial>
C02YYYYYYYYP8PGFB          <- different, same input
```

Both carry a valid checksum, so *either* works alone — but if you generated your serial with `-n`
and then replaced its MLB with a `--mlb` result, you have silently discarded the pair macserial
designed. **Take both fields from one `-n` line.**

---

## What a generated serial is and is not

| | |
|---|---|
| ✅ format-valid, correctly shaped for the model | `--info` decodes it cleanly |
| ✅ unique | random suffix, collision-free in practice |
| ✅ enough for SMBIOS identity, `ioreg`, model gating | |
| ❌ **not a serial Apple ever shipped** | will not satisfy purchase-record checks |

**Expect iMessage / FaceTime activation to fail.** That is true of every hackintosh SMBIOS
generator, not a defect in this one. If those matter, the only route is an identity you own.

## Setting the UUID

`SystemUUID` should be the value the machine **already reports**:

```sh
ioreg -l | grep IOPlatformUUID
```

That is the firmware UUID, so it is stable across rebuilds. A freshly generated UUID also works but
makes every rebuild look like new hardware.

## Where it goes

```
PlatformInfo → Generic → SystemSerialNumber   ← serial
PlatformInfo → Generic → MLB                  ← MLB
PlatformInfo → Generic → SystemUUID           ← UUID
PlatformInfo → Generic → SystemProductName    ← must match hw.model, or the installer refuses
```

`SystemProductName` is the gate: the installer matches `hw.model` against it, and falls back to
`IOPlatformSerialNumber` vs `SystemSerialNumber`. If nothing matches it refuses to edit any config.
