import 'dart:convert';
import 'dart:io';
import 'package:yjs_dart/yjs.dart';

void main() {
  // Read fixtures
  final f = jsonDecode(File('test/fixtures/fixtures.json').readAsStringSync());
  final fixture = f['array_delete'];
  
  final doc = Doc(DocOpts(clientID: 1));
  final arr = doc.get('arr', () => YType());
  arr.insert(0, ['a', 'b', 'c']);
  arr.delete(1, 1); // delete 'b'
  
  final actual = encodeStateAsUpdate(doc);
  final expected = List<int>.from(fixture['update'] as List);
  
  print('Expected: $expected');
  print('Actual:   ${actual.toList()}');
  print('Lengths: expected=${expected.length}, actual=${actual.length}');
  
  // Find first difference
  final minLen = actual.length < expected.length ? actual.length : expected.length;
  for (int i = 0; i < minLen; i++) {
    if (actual[i] != expected[i]) {
      print('First diff at index $i: expected=${expected[i]}, actual=${actual[i]}');
      // Show context
      final start = i > 5 ? i - 5 : 0;
      final end = i + 5 < minLen ? i + 5 : minLen;
      print('Context expected [${start}..${end}]: ${expected.sublist(start, end)}');
      print('Context actual   [${start}..${end}]: ${actual.sublist(start, end)}');
      break;
    }
  }
}
