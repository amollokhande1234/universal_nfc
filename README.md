# universal_nfc

One API to **read and write NFC tags** from a desktop or mobile app.

* Works today with **any PC/SC reader on Windows** (ACR1552, ACR1252, ACR122U, and others through a generic profile).
* Android, iOS, macOS and Linux plug into the **same API** (see [Roadmap](#roadmap)).
* Your tag data becomes **typed Dart objects** through models you define.
* Nested JSON, card UID, raw bytes, safe writing and a built-in **health check** for new readers and laptops.

---

## Features

| Feature | What it gives you |
|---|---|
| Reader hot-plug | Start the app first, plug the reader in later; it connects by itself. Unplug it and you are told. |
| Full lifecycle events | Reader connected / disconnected, tag detected / read / removed / written, state changes, failures. |
| Typed models | Describe a tag type once; the reader turns tag data into your own object. Add or remove models at any time. |
| Safe by design | Unknown, blank or corrupt tags become events, never crashes. A model that throws is caught. |
| Rich data | Key-values, nested objects, lists, numbers, booleans, text in any language. |
| Card UID and raw bytes | Every read event carries `uid`, `rawBytes` and `rawHex`. |
| Safe writing | Capacity check, keeps control TLVs, never locks, writes the header last, reads back to verify. |
| Reader profiles | Add support for another reader model with one small profile. |
| Pluggable layers | Swap the backend (hardware), the codec (card layout) or the models (meaning) independently. |
| Diagnostics | `diagnose()` says what is wrong on this laptop and how to fix it. |
| Fails soft | On a platform without a backend, `isAvailable()` is false and the app keeps running. |

## Platform support

| Platform | Status | How |
|---|---|---|
| Windows 10/11 | Working | PC/SC (`winscard.dll`) via FFI |
| Android | Planned | Phone NFC chip |
| iOS | Planned | Core NFC |
| macOS | Planned | Built-in PC/SC framework |
| Linux | Planned | `pcscd` + `libpcsclite` |

Tags: NFC Forum **Type 2** tags (NTAG213 / 215 / 216, MIFARE Ultralight) hold NDEF text with JSON. Other tag families can be added through a codec.

---

## Understand it in one minute

```
 hardware ──► BACKEND ──► CODEC ──► data {ind:2, sub:1} ──► MODEL ──► typed object ──► your app
 (reader)    how a        how data    key / value map       what the     IndustryTag
             reader       is laid                           data MEANS
             connects     out on the
                          card
```

| Layer | Question | Default | To extend |
|---|---|---|---|
| Backend | How do I talk to this reader? | `PcscBackend` (Windows) | implement `NfcBackend` |
| Reader profile | What does this reader model need? | ACR1552, ACR1252, ACR122U, generic | add a `ReaderProfile` |
| Codec | How is data stored on the card? | NDEF Text record with JSON | implement `NfcTagCodec` |
| Model | What does the data mean? | none, you register yours | `NfcTagModel` |

### What happens on one tap

1. The reader layer sees a card and emits `TagDetected`.
2. It reads the card UID and the memory (the tag tells the reader how big it is).
3. The codec decodes the memory into data.
4. The model registry picks a model:
   * the tag names one (`{"m":"industry",...}`), or
   * the model whose `requiredKeys` are all present (most specific wins).
5. The model's `parse` builds your object and you get `TagRead`.

When a step fails you get an event instead: `UnknownTag` (no model fits, raw data included) or `TagUnreadable` (error message included). The reader keeps running either way.

### How it detects things

| What | How | How often |
|---|---|---|
| Reader plugged in / out | compares the list of readers Windows reports | about every 1 s |
| Tag placed | asks the reader for its card state | every 250 ms |
| Tag removed | no card, confirmed after 400 ms so a flicker is not a removal | 400 ms debounce |

### States

`idle` -> `waitingForReader` -> `listening` -> `tagPresent`, and back. `nfc.state` and `nfc.states` expose them for a status badge.

---

## Quick start

```yaml
dependencies:
  universal_nfc:
    path: ../universal_nfc   # or a git url
```

```dart
import 'package:universal_nfc/universal_nfc.dart';

final nfc = UniversalNfc();

nfc.events.listen((event) {
  switch (event) {
    case TagRead(:final value):          print('Tag: $value');
    case UnknownTag(:final fields):      print('Raw data: $fields');
    case TagRemoved():                   print('Removed');
    case ReaderDisconnected():           print('Reader unplugged');
    default:                             break;
  }
});

await nfc.start();   // fine even if no reader is plugged in yet
// ...
await nfc.dispose();
```

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

| Tag content | Result |
|---|---|
| `{"ind":"2","sub":"1"}` | `TagRead` with `IndustryTag` |
| `{"m":"visitor","name":"Asha","company":"ABC"}` | `TagRead` with `Visitor` (model named on the tag) |
| `{"ind":"abc","sub":"1"}` | `TagUnreadable` (the model could not parse it) |
| `{"ind":"2"}` | `UnknownTag` (no model's keys are all present) |
| blank or damaged tag | `TagUnreadable` |

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

**What it does to protect your tags:** only NDEF-formatted Type 2 tags; checks the data fits before writing anything; keeps control TLVs (such as a Lock Control TLV) in front of your data; never writes outside the tag's data area; writes the page holding the message header last; reads everything back and compares; never sets a lock bit.

**Try it on a spare tag first.** Writing was written to the PC/SC standard but must be confirmed on your own reader and tags.

### How much fits

| Tag | Data area | Roughly free for your JSON |
|---|---|---|
| NTAG213 | 144 bytes | about 130 |
| NTAG215 | 496 bytes | about 480 |
| NTAG216 | 872 bytes | about 855 |

| Data | Space |
|---|---|
| `{"ind":"2","sub":"1","cat":"3","cha":"5"}` | about 50 bytes |
| Number `2` vs text `"2"` | 1 byte vs 3 bytes |
| English character / Marathi or Hindi character | 1 byte / 3 bytes |
| Images or files | do not fit; store an id or link and fetch from your server |

## Diagnostics: making it work on any laptop

```dart
final report = await UniversalNfc().diagnose();
print(report);
```

```
Platform           : Windows
Supported          : yes
NFC service        : reachable
Readers found      : ACS ACR1552 3S CL Reader 0
Selected reader    : ACS ACR1552 3S CL Reader 0
Reader profile     : acr1552
Healthy            : yes
```

When something is wrong it tells you what to do:

| Symptom | Likely fix |
|---|---|
| NFC service not reachable | Windows: start the **Smart Card** service in `services.msc` and set it to Automatic |
| No reader found | Check the cable, try another USB port, look under "Smart card readers" in Device Manager, install the vendor driver |
| Reader found but profile is `generic` | Fine for most readers; add a `ReaderProfile` if reading fails |
| Tag shows `TagUnreadable` | Tag is blank or not NDEF; check `rawHex` in the event |

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

**A different kind of reader (serial, HID, vendor SDK):** implement `NfcBackend` and pass `UniversalNfc(backend: MyBackend())`. The test `test/universal_nfc_test.dart` contains a complete fake backend to copy from.

**Another card layout:** implement `NfcTagCodec` and pass `codec:`.

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
        break; // UnknownTag / TagUnreadable: stay on the current screen
    }
  });

  await nfc.start();
}
```

Create it once: `UniversalNfc(models: [industryModel], logger: debugPrint)`.

## Examples

Run these on a Windows machine with a reader (`dart pub get` first):

| File | What it does |
|---|---|
| `example/print_everything.dart` | diagnostics, then prints every event with UID and raw bytes |
| `example/models_example.dart` | two models, including nested data |
| `example/write_example.dart` | checks size, writes a tag, verifies |

## Testing

```
dart pub get
dart test
```

The tests need no hardware: a fake backend drives the whole lifecycle, and the NDEF, codec, model, write-planning and profile logic are plain functions.

## Roadmap

1. macOS and Linux PC/SC backends (same reader profiles and codec).
2. Android backend (phone NFC chip).
3. iOS backend.
4. Background isolate for polling.
5. More tag families through codecs.

## Limitations

* Windows is the only backend right now.
* Polling and reads run on the calling isolate; move the reader to a background isolate if the UI janks.
* A tag swapped for another within the 400 ms removal debounce is not re-read.
* ACR1252 and ACR122U use the standard PC/SC commands; confirm on your hardware.
* Writing needs NDEF-formatted Type 2 tags.
