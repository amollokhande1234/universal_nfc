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
