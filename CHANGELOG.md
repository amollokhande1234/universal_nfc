## 0.4.1

- Fix: `UniversalNfc.setProbe` now compiles (type promotion from `Object`).
- Fix: `NfcProbeConfig.milliseconds` / `.seconds` are valid `const` constructors.
- README rewritten: probe statuses and interval, events table, development commands.

## 0.4.0

- Probe statuses: `ProbeStatus` (unknown, readerPresent, noReader, serviceUnavailable,
  unsupported, error). `NfcReaderProbe.check()` returns it; `hasReader()` still works.
- Probe interval is configurable: `NfcProbeConfig()` (default 200 ms, same as before),
  `.milliseconds(n)`, `.seconds(n)`, `.off()`. Anything under 50 ms is raised to 50 ms.
- Change it while running: `nfc.setProbe(...)`.
- New: `nfc.probeStatus`, `nfc.probeStatuses`, event `ReaderProbeChanged`, and a probe line in `diagnose()`.
- When the Windows Smart Card service stops, the reader is dropped right away.
- `PcscBackend(probeInterval:)` and `readerProbe:` still work but are deprecated.
- New event type: add a `default:` branch to exhaustive `switch (event)` statements.

## 0.3.1

- Instant reader plug-in / unplug detection: `NfcReaderProbe` (a very cheap check) runs every
  200 ms and triggers a rescan the moment its answer changes. `NfcReaderProbe.hasReader()` is
  also public for a quick "is a reader plugged in?" check.

## 0.3.0

- Renamed to `universal_nfc`; main class is now `UniversalNfc`.
- Structured data: nested objects, lists, numbers and booleans (`NfcData` + typed accessors).
- Events now carry the card UID and the raw bytes (`uid`, `rawBytes`, `rawHex`).
- Safe writing for NFC Forum Type 2 tags (NTAG21x, Ultralight): capacity check, lock-TLV
  preservation, read-back verification, never locks the tag.
- `diagnose()` reports platform, PC/SC service, readers, chosen profile and fix hints.
- `UniversalNfc()` no longer throws on unsupported platforms; `isAvailable()` is false and
  `diagnose()` explains why.
- Read range follows the tag's own capability container.

## 0.2.0

- Full lifecycle events, tag models, reader profiles, pluggable backend and codec.

## 0.1.0

- Windows PC/SC reader support.
