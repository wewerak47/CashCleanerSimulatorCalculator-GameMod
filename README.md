# Cash Cleaner Simulator — Scanner Export Mod

UE4SS Lua mod for [Cash Cleaner Simulator](https://store.steampowered.com/app/2488370/Cash_Cleaner_Simulator/)
that reads the game's built-in cash scanner result and copies a plain-text
breakdown of bill/coin counts per currency and denomination to the Windows
clipboard — for pasting into the companion web calculator
([CashCleanerSimulatorCalculator](https://github.com/wewerak47/CashCleanerSimulatorCalculator))
instead of typing stock counts in by hand.

## Contents

- **`CCS_ScanExport/`** — the mod you actually use.
- **`CCS_ScannerProbe/`** — a throwaway diagnostic mod used to reverse-engineer
  the scanner UI's widget structure (`W_ScanCurrencyIcon_C` etc.). Not needed
  for normal use; kept in case the game updates and the UI class names
  change, so the discovery process doesn't have to start from scratch.

## Requirements

- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) installed in the game
  (tested against v3.0.1 Beta).

## Installation

Copy `CCS_ScanExport` (and optionally `CCS_ScannerProbe`) into the game's
UE4SS mods folder:

```
<game install>/CashCleanerSimulator/Binaries/Win64/ue4ss/Mods/
```

## Usage

1. In-game, use the scanner to get an "Area scan result".
2. Press **F8**. The breakdown is copied to the clipboard, and a confirmation
   (`Copied N denomination(s) to clipboard.`) is printed to the UE4SS
   console/log.
3. Paste the clipboard content into the web calculator's "Import from game"
   dialog.

## Clipboard format

A simple, versioned plain-text protocol:

```
CCS-SCAN v1
USD 100 x26800
USD 50 x14900
...
```

One `<CURRENCY> <denomination> x<count>` line per denomination tile shown
on the scanner result panel. Counts are raw piece counts (individual bills
or coins), not bundles/rolls.

## How it works

The scanner's result panel (`W_ScanObjectsOverlay_C` → `ScanObjectsResult`
→ `DenominationCounters` → one `W_ScanCurrencyIcon_C` per tile) is read
directly from its `Label`/`Counter` `TextBlock`s rather than from the
backing `S_ScanResult` struct's `DenominationToBillNum`/`DenominationToCoinNum`
maps, because this UE4SS build's `TMap:ForEach()` only yields opaque
parameter-wrapper objects for map keys/values, not usable data.

The game never destroys a scan result's icon widgets when a new scan
replaces it on screen — it only detaches them from their `WrapBox` panel.
Detached (stale) icons keep `Visibility = SelfHitTestInvisible`, so
`Visibility` alone can't tell current tiles from leftovers of a previous
scan. `GetParent()` is the reliable signal: it's `nil` for detached/stale
icons and the real `WrapBox` for currently-displayed ones — see the
comment in `CCS_ScanExport/Scripts/main.lua` for details.

## License

MIT
