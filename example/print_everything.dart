// Prints everything that happens: reader plugged in / out, tag placed / removed,
// the card UID, the raw bytes and the decoded data. No models needed.
//
//   dart run example/print_everything.dart
import 'dart:async';
import 'dart:io';

import 'package:universal_nfc/universal_nfc.dart';

Future<void> main() async {
  final nfc = UniversalNfc(logger: print); // logger prints the raw bytes too

  // 1. Health check first: tells you what is wrong on this laptop, if anything.
  print((await nfc.diagnose()).report());
  print('');

  if (!await nfc.isAvailable()) {
    print('NFC is not available on this machine. See the report above.');
    return;
  }

  // 2. Print every event.
  nfc.events.listen((event) {
    switch (event) {
      case ReaderConnected(:final readerName):
        print('Reader plugged in: $readerName');
      case ReaderDisconnected(:final readerName):
        print('Reader unplugged: $readerName');
      case TagDetected():
        print('Tag detected, reading...');
      case UnknownTag(:final fields, :final uid, :final rawHex):
        print('Tag $uid\n  data: $fields\n  raw : $rawHex');
      case TagRead(:final fields, :final uid):
        print('Tag $uid understood by a model: $fields');
      case TagUnreadable(:final error, :final uid, :final rawHex):
        print('Tag $uid could not be read: $error\n  raw : $rawHex');
      case TagRemoved():
        print('Tag removed');
      case NfcStateChanged(:final state):
        print('State: ${state.name}');
      default:
        print(event);
    }
  });

  await nfc.start(); // fine even if the reader is not plugged in yet
  print('Listening. Plug in the reader and tap a tag. Ctrl+C to quit.');

  await ProcessSignal.sigint.watch().first;
  await nfc.dispose();
  exit(0);
}
