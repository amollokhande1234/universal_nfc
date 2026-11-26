# universal_nfc

One API to **read and write NFC tags** from a desktop or mobile app.

- Works today with **any PC/SC reader on Windows** (ACR1552, ACR1252, ACR122U, and others through a generic profile).
- Android, iOS, macOS and Linux plug into the **same API** (see [Roadmap](#roadmap)).
- Tag data becomes **typed Dart objects** through models you define.
- Nested JSON, card UID, raw bytes, safe writing, **instant reader detection** and a built-in **health check**.

---

## Features

| Feature                     | What it gives you                                                                                                          |
| --------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| Reader hot-plug             | Start the app first, plug the reader in later; it connects by itself. Unplug it and you are told within about 200 ms.      |
| Probe statuses and interval | Know why there is no reader (none plugged in, service stopped) and choose how often it checks, in milliseconds or seconds. |
| Full lifecycle events       | Reader connected / disconnected, tag detected / read / removed / written, state changes, failures.                         |
| Typed models                | Describe a tag type once; the reader turns tag data into your own object. Add or remove models at any time.                |
| Safe by design              | Unknown, blank or corrupt tags become events, never crashes. A model that throws is caught.                                |
| Rich data                   | Key-values, nested objects, lists, numbers, booleans, text in any language.                                                |
| Card UID and raw bytes      | Every read event carries `uid`, `rawBytes` and `rawHex`.                                                                   |
| Safe writing                | Capacity check, keeps control TLVs, never locks, writes the header last, reads back to verify.                             |
| Reader profiles             | Add support for another reader model with one small profile.                                                               |
| Pluggable layers            | Swap the backend (hardware), the codec (card layout) or the models (meaning) independently.                                |
| Diagnostics                 | `diagnose()` says what is wrong on this laptop and how to fix it.                                                          |
| Fails soft                  | On a platform without a backend, `isAvailable()` is false and the app keeps running.                                       |

## Platform support

| Platform      | Status  | How                            |
| ------------- | ------- | ------------------------------ |
| Windows 10/11 | Working | PC/SC (`winscard.dll`) via FFI |
| Android       | Planned | Phone NFC chip                 |
| iOS           | Planned | Core NFC                       |
| macOS         | Planned | Built-in PC/SC framework       |
| Linux         | Planned | `pcscd` + `libpcsclite`        |

Tags: NFC Forum **Type 2** tags (NTAG213 / 215 / 216, MIFARE Ultralight) holding NDEF text with JSON. Other tag families can be added through a codec.

## Install

```
dart pub add universal_nfc        # Dart
flutter pub add universal_nfc     # Flutter
```

or in `pubspec.yaml`:

```yaml
dependencies:
  universal_nfc: ^0.4.1
```

The package depends on `win32` and `ffi`. If your app already uses `win32`, keep the versions compatible.

---

## Understand it in one minute

```
 hardware ──► BACKEND ──► CODEC ──► data {ind:2, sub:1} ──► MODEL ──► typed object ──► your app
 (reader)    how a        how data    key / value map       what the     IndustryTag
             reader       is laid                           data MEANS
             connects     out on the
                          card
```

| Layer          | Question                          | Default                            | To extend               |
| -------------- | --------------------------------- | ---------------------------------- | ----------------------- |
| Backend        | How do I talk to this reader?     | `PcscBackend` (Windows)            | implement `NfcBackend`  |
| Reader profile | What does this reader model need? | ACR1552, ACR1252, ACR122U, generic | add a `ReaderProfile`   |
| Codec          | How is data stored on the card?   | NDEF Text record with JSON         | implement `NfcTagCodec` |
| Model          | What does the data mean?          | none, you register yours           | `NfcTagModel`           |

### What happens on one tap

1. The reader layer sees a card and emits `TagDetected`.
2. It reads the card UID and the memory (the tag tells the reader how big it is).
3. The codec decodes the memory into data.
4. The model registry picks a model:
   - the tag names one (`{"m":"industry",...}`), or
   - the model whose `requiredKeys` are all present (most specific wins).
5. The model's `parse` builds your object and you get `TagRead`.

When a step fails you get an event instead: `UnknownTag` (no model fits, raw data included) or `TagUnreadable` (error message included). The reader keeps running either way.

### How it detects things

| What                    | How                                                                | How often                                                                   |
| ----------------------- | ------------------------------------------------------------------ | --------------------------------------------------------------------------- |
| Reader plugged in / out | the fast probe's answer changes, then the reader list is rescanned | about 200 ms by default, configurable (full scan every 1 s as a safety net) |
| Tag placed              | asks the reader for its card state                                 | every 250 ms                                                                |
| Tag removed             | no card, confirmed after 400 ms so a flicker is not a removal      | 400 ms debounce                                                             |

### States

`idle` -> `waitingForReader` -> `listening` -> `tagPresent`, and back. `nfc.state` and `nfc.states` expose them for a status badge.

---

## Quick start

```dart
import 'package:universal_nfc/universal_nfc.dart';

final nfc = UniversalNfc();

nfc.events.listen((event) {
  switch (event) {
    case TagRead(:final value):      print('Tag: $value');
    case UnknownTag(:final fields):  print('Raw data: $fields');
    case TagRemoved():               print('Removed');
    case ReaderDisconnected():       print('Reader unplugged');
    default:                         break;
  }
});

await nfc.start();   // fine even if no reader is plugged in yet
// ...
await nfc.dispose();
```

Always keep a `default:` branch in `switch (event)`; new event types are added in minor releases.

### Print everything coming from a card

```dart
final nfc = UniversalNfc(logger: print);
nfc.events.listen(print);
await nfc.start();
```

A tag with `{"ind":"2","sub":"1"}` prints roughly:

```
ReaderConnected(ACS ACR1552 ...)
TagDetected
UnknownTag({ind: 2, sub: 1}, uid: 04A1B2C3D4E580)
TagRemoved
```

## Events

| Event                                    | When                                                              |
| ---------------------------------------- | ----------------------------------------------------------------- |
| `NfcStateChanged`                        | the reader state changed                                          |
| `ReaderConnected` / `ReaderDisconnected` | a reader was plugged in / unplugged                               |
| `ReaderProbeChanged`                     | the probe status changed (see below)                              |
| `TagDetected`                            | a tag touched the reader; reading started                         |
| `TagRead`                                | a model understood the tag; `value` is your object                |
| `UnknownTag`                             | read fine, no model fits; raw `fields` included                   |
| `TagUnreadable`                          | tag present but could not be read or parsed; `error` explains why |
| `TagRemoved`                             | the tag was taken away                                            |
| `TagWritten`                             | `write` succeeded                                                 |
| `NfcFailure`                             | something went wrong in the backend; the reader keeps running     |

`TagRead`, `UnknownTag` and `TagUnreadable` carry `uid`, `rawBytes` and `rawHex`.

## Models

```dart
class IndustryTag {
  IndustryTag(this.industry, this.sector, {this.process, this.challenge});
  final int industry, sector;
  final int? process, challenge;
}

final industryModel = NfcTagModel<IndustryTag>.define(
  id: 'industry',
  requiredKeys: {'ind', 'sub'},
  parse: (f) => IndustryTag(
    f.requireInt('ind'),
    f.requireInt('sub'),
    process: f.integer('cat'),
    challenge: f.integer('cha'),
  ),
);

final nfc = UniversalNfc(models: [industryModel]);

// any time, also while running
nfc.models.register(visitorModel);
nfc.models.unregister('visitor');
```

Typed accessors on the data (work for `2` and `"2"` alike): `str`, `integer`, `number`, `boolean`, `object`, `list`, `requireString`, `requireInt` (the last two throw a `FormatException`, which the reader turns into `TagUnreadable`).

| Tag content                                     | Result                                            |
| ----------------------------------------------- | ------------------------------------------------- |
| `{"ind":"2","sub":"1"}`                         | `TagRead` with `IndustryTag`                      |
| `{"m":"visitor","name":"Asha","company":"ABC"}` | `TagRead` with `Visitor` (model named on the tag) |
| `{"ind":"abc","sub":"1"}`                       | `TagUnreadable` (the model could not parse it)    |
| `{"ind":"2"}`                                   | `UnknownTag` (no model's keys are all present)    |
| blank or damaged tag                            | `TagUnreadable`                                   |

## Reader probe: instant connect / disconnect

A tiny probe (`NfcReaderProbe.check()`) asks Windows "is any reader plugged in?" every 200 ms by default. It is very cheap because it only asks for the size of the reader list. When its answer changes, the reader list is rescanned immediately, so `ReaderConnected` / `ReaderDisconnected` arrive within about 200 ms.

**Choose how often it runs** (the default is unchanged, so nothing changes unless you ask):

```dart
UniversalNfc(probe: const NfcProbeConfig());                 // default, 200 ms
UniversalNfc(probe: NfcProbeConfig.milliseconds(100)); // faster
UniversalNfc(probe: NfcProbeConfig.seconds(2));        // gentler
UniversalNfc(probe: const NfcProbeConfig.off());             // regular 1 s scan only

nfc.setProbe(NfcProbeConfig.seconds(5));               // change it while running
```

Anything under 50 ms is raised to 50 ms so the check cannot hog the CPU. With `.off()` readers are still found, just by the regular scan every second.

**Probe statuses**

| `ProbeStatus`        | Meaning                                   | What to do                           |
| -------------------- | ----------------------------------------- | ------------------------------------ |
| `unknown`            | Not checked yet, or the probe is off      | wait                                 |
| `readerPresent`      | A reader is plugged in                    | nothing                              |
| `noReader`           | The service works, no reader plugged in   | plug a reader in                     |
| `serviceUnavailable` | The Windows Smart Card service is stopped | start "Smart Card" in `services.msc` |
| `unsupported`        | No probe on this platform                 | nothing                              |
| `error`              | The check itself failed                   | see `diagnose()`                     |

```dart
nfc.probeStatus;                       // latest status
nfc.probeStatuses.listen((s) { ... }); // every change
// or as an event: case ReaderProbeChanged(:final status): ...

NfcReaderProbe.check();                // one-off status
NfcReaderProbe.hasReader();            // true only for readerPresent
```

Using your own backend object? Pass the same setting there: `PcscBackend(codec: const NdefJsonCodec(), probe: NfcProbeConfig.milliseconds(100))`.

## Writing tags

```dart
final size = nfc.estimateSize(data);          // will it fit?
final result = await nfc.write(
  {'ind': '2', 'sub': '1', 'pass': {'zone': 'A', 'days': [1, 2, 3]}},
  modelId: 'industry',                         // optional: store the model name
);
print(result.ok ? 'Written (${result.bytesFree} bytes free)' : result.error);
```

A tag must be on the reader. `write` never throws for expected problems, it returns an `NfcWriteResult`.

**How your tags are protected:** only NDEF-formatted Type 2 tags; checks the data fits before writing anything; keeps control TLVs (such as a Lock Control TLV) in front of your data; never writes outside the tag's data area; writes the page holding the message header last; reads everything back and compares; never sets a lock bit.

**Try writing on a spare tag first.** It follows the PC/SC standard but must be confirmed on your own reader and tags.

### How much fits

| Tag     | Data area | Roughly free for your JSON |
| ------- | --------- | -------------------------- |
| NTAG213 | 144 bytes | about 130                  |
| NTAG215 | 496 bytes | about 480                  |
| NTAG216 | 872 bytes | about 855                  |

| Data                                           | Space                                                      |
| ---------------------------------------------- | ---------------------------------------------------------- |
| `{"ind":"2","sub":"1","cat":"3","cha":"5"}`    | about 50 bytes                                             |
| Number `2` vs text `"2"`                       | 1 byte vs 3 bytes                                          |
| English character / Marathi or Hindi character | 1 byte / 3 bytes                                           |
| Images or files                                | do not fit; store an id or link and fetch from your server |

## Diagnostics: making it work on any laptop

```dart
print(await UniversalNfc().diagnose());
```

```
Platform           : Windows
Supported          : yes
NFC service        : reachable
Readers found      : ACS ACR1552 3S CL Reader 0
Selected reader    : ACS ACR1552 3S CL Reader 0
Reader profile     : acr1552
Probe status       : readerPresent
Healthy            : yes
```

| Symptom                               | Likely fix                                                                                                          |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| Probe status `serviceUnavailable`     | start the **Smart Card** service in `services.msc` and set it to Automatic                                          |
| Probe status `noReader`               | check the cable, try another USB port, look under "Smart card readers" in Device Manager, install the vendor driver |
| Reader found but profile is `generic` | fine for most readers; add a `ReaderProfile` if reading fails                                                       |
| Tag shows `TagUnreadable`             | the tag is blank or not NDEF; check `rawHex` in the event                                                           |

Some laptops have a built-in NFC reader. If its driver exposes it as a PC/SC reader, it is detected like any USB reader.

## Supporting more readers

**Another PC/SC reader (same protocol):**

```dart
UniversalNfc(readerProfiles: [
  ReaderProfile(id: 'acme', nameContains: ['ACME NFC'], maxPage: 40),
  ...ReaderProfile.defaults,
]);
```

If the reader needs other commands, set `buildReadApdu` / `buildWriteApdu` / `uidApdu` on the profile.

**A different kind of reader (serial, HID, vendor SDK):** implement `NfcBackend` and pass `UniversalNfc(backend: MyBackend())`. `test/universal_nfc_test.dart` contains a complete fake backend to copy from.

**Another card layout:** implement `NfcTagCodec` and pass `codec:`.

When you pass your own `backend`, set reader profiles, `allowAnyReader`, the probe and the logger on that backend instead; `UniversalNfc` ignores those options.

## Flutter integration (cubit and router)

```dart
Future<void> initializeNfc({
  required UniversalNfc nfc,
  required SelectionCubit selectionCubit,
  required GoRouter router,
}) async {
  if (!await nfc.isAvailable()) {
    debugPrint((await nfc.diagnose()).report());   // why not
    return;                                         // app continues without NFC
  }

  nfc.events.listen((event) {
    switch (event) {
      case TagRead(:final value):
        final tag = value as IndustryTag;
        selectionCubit.selectFromNfc(
          industryIndex: tag.industry,
          sectorIndex: tag.sector,
          processId: tag.process,
          challengeid: tag.challenge,
        );
        router.go(tag.challenge != null ? '/product_screen' : '/industry_detailed_screen');

      case TagRemoved() || ReaderDisconnected():
        selectionCubit.clear();
        router.go('/landingPage');

      default:
        break; // UnknownTag / TagUnreadable / probe changes: stay on the current screen
    }
  });

  await nfc.start();
}
```

Create it once: `UniversalNfc(models: [industryModel], logger: debugPrint)`.

## Examples

Run these on a Windows machine with a reader:

| File                            | What it does                                                |
| ------------------------------- | ----------------------------------------------------------- |
| `example/print_everything.dart` | diagnostics, then prints every event with UID and raw bytes |
| `example/models_example.dart`   | two models, including nested data                           |
| `example/write_example.dart`    | checks size, writes a tag, verifies                         |

```
dart run example/print_everything.dart
```

## Development

```
dart pub get                          # install dependencies
dart format .                         # format
dart analyze                          # static checks, must report no issues
dart test                             # run all tests
dart test test/universal_nfc_test.dart   # one file
dart test -n "write"                  # tests whose name contains "write"
dart test -r expanded                 # one line per test
dart pub publish --dry-run            # check the package before publishing
dart pub publish                      # publish (permanent)
```

The tests need no hardware: a fake backend drives the whole lifecycle, and the NDEF, codec, model, write-planning, probe and profile logic are plain functions. Two probe tests depend on the operating system and run only where they apply.

## Upgrading

| From  | To 0.4.x                                                                                                                                                                                                                         |
| ----- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0.3.x | New event `ReaderProbeChanged`: add a `default:` branch to any `switch (event)` that has none. `PcscBackend(probeInterval:)` and `readerProbe:` still work but are deprecated; use `probe: NfcProbeConfig...` and `probeCheck:`. |
| 0.4.0 | Use 0.4.1: it fixes two compile errors (`setProbe` and the `const` probe constructors).                                                                                                                                          |

In an app, raise the constraint (`^0.3.1` does not accept 0.4.x) and run `flutter pub upgrade universal_nfc`.

## Roadmap

1. macOS and Linux PC/SC backends (same reader profiles and codec).
2. Android backend (phone NFC chip).
3. iOS backend.
4. Background isolate for polling.
5. More tag families through codecs.

## Limitations

- Windows is the only backend right now.
- Polling and reads run on the calling isolate; move the reader to a background isolate if the UI janks.
- A tag swapped for another within the 400 ms removal debounce is not re-read.
- ACR1252 and ACR122U use the standard PC/SC commands; confirm on your hardware.
- Writing needs NDEF-formatted Type 2 tags.
