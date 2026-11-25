// Writes data to a tag. TRY IT ON A SPARE TAG FIRST.
//
//   dart run example/write_example.dart
//
// Safety: it only writes NDEF-formatted NTAG / Ultralight tags, checks the data
// fits, never locks the tag, and reads everything back to verify.
import 'dart:async';

import 'package:universal_nfc/universal_nfc.dart';

Future<void> main() async {
  final nfc = UniversalNfc();

  // Listen BEFORE start so the first tag is not missed.
  final tagReady = nfc.events.firstWhere(
    (e) => e is TagRead || e is UnknownTag || e is TagUnreadable,
  );

  await nfc.start();
  print('Place a tag on the reader...');
  await tagReady;

  final data = <String, Object?>{
    'ind': '2',
    'sub': '1',
    'cat': '3',
    'pass': {
      'zone': 'A',
      'days': [1, 2, 3],
    },
  };

  // Ask first: will it fit? (NTAG213 = 144 bytes, NTAG215 = 496, NTAG216 = 872)
  print('This needs about ${nfc.estimateSize(data)} bytes.');

  final result = await nfc.write(data, modelId: 'industry');
  if (result.ok) {
    print('Written. ${result.bytesUsed} of ${result.capacity} bytes used, '
        '${result.bytesFree} free.');
  } else {
    print('Not written: ${result.error}');
  }

  await nfc.dispose();
}
