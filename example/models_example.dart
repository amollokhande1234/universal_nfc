// Typed tag models: the tag content becomes your own Dart objects.
//
//   dart run example/models_example.dart
import 'dart:async';
import 'dart:io';

import 'package:universal_nfc/universal_nfc.dart';

class IndustryTag {
  IndustryTag(this.industry, this.sector, {this.process, this.challenge});
  final int industry;
  final int sector;
  final int? process;
  final int? challenge;
  @override
  String toString() =>
      'IndustryTag(industry: $industry, sector: $sector, process: $process, challenge: $challenge)';
}

class Visitor {
  Visitor(this.name, this.company, this.days);
  final String name;
  final String company;
  final List<int> days;
  @override
  String toString() => 'Visitor($name from $company, days $days)';
}

// Model 1: your existing tags {"ind":"2","sub":"1","cat":"3","cha":"5"}
final industryModel = NfcTagModel<IndustryTag>.define(
  id: 'industry',
  requiredKeys: {'ind', 'sub'},
  parse: (f) => IndustryTag(
    f.requireInt('ind'),
    f.requireInt('sub'),
    process: f.integer('cat'), // optional
    challenge: f.integer('cha'), // optional
  ),
);

// Model 2: nested data {"name":"Asha","company":"ABC","pass":{"days":[1,2]}}
final visitorModel = NfcTagModel<Visitor>.define(
  id: 'visitor',
  requiredKeys: {'name', 'company'},
  parse: (f) => Visitor(
    f.requireString('name'),
    f.requireString('company'),
    (f.object('pass')?.list('days') ?? const []).whereType<int>().toList(),
  ),
);

Future<void> main() async {
  final nfc = UniversalNfc(models: [industryModel, visitorModel]);

  nfc.events.listen((event) {
    switch (event) {
      case TagRead(:final value):
        print('Typed object: $value');
      case UnknownTag(:final fields):
        print('No model for this tag: $fields');
      case TagUnreadable(:final error):
        print('Problem: $error');
      case TagRemoved():
        print('Tag removed');
      default:
        break;
    }
  });

  // Models can be added (or removed) at any time, even while running:
  // nfc.models.register(anotherModel);
  // nfc.models.unregister('visitor');

  await nfc.start();
  print('Tap a tag. Ctrl+C to quit.');
  await ProcessSignal.sigint.watch().first;
  await nfc.dispose();
  exit(0);
}
