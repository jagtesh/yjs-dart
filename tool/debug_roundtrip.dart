import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:yjs_dart/yjs.dart';
import 'package:yjs_dart/src/utils/struct_store.dart' as struct_store;

void main() {
  // Read fixtures
  final f = jsonDecode(File('test/fixtures/fixtures.json').readAsStringSync());
  final fixture = f['array_insert'];
  
  final jsUpdate = List<int>.from(fixture['update'] as List).let((l) => l);
  
  print('JS update bytes: $jsUpdate');
  
  // Apply JS update to empty doc
  final doc = Doc(DocOpts(clientID: 2));
  doc.get('arr', () => YType());
  applyUpdate(doc, Uint8List.fromList(jsUpdate));
  
  // Debug the store
  print('\nStore clients: ${doc.store.clients.keys.toList()}');
  for (final entry in doc.store.clients.entries) {
    print('  Client ${entry.key}: ${entry.value.length} structs');
    for (final s in entry.value) {
      print('    $s (type: ${s.runtimeType}, deleted: ${s.deleted}, length: ${s.length})');
      // Access content via dynamic to inspect
      final dynamic item = s;
      try {
        final dynamic content = item.content;
        print('      content type: ${content.runtimeType}');
        try {
          print('      content.length: ${content.length}');
        } catch (_) {}
        try {
          print('      content.arr: ${content.arr}');
        } catch (_) {}
        try {
          print('      content.getRef(): ${content.getRef()}');
        } catch (_) {}
      } catch(_) {}
    }
  }

  
  // Re-encode and compare
  final dartUpdate = encodeStateAsUpdate(doc);
  print('\nExpected: $jsUpdate');
  print('Actual:   ${dartUpdate.toList()}');
}

extension Let<T> on T {
  R let<R>(R Function(T) op) => op(this);
}
