import 'dart:typed_data';
import 'package:yjs_dart/yjs_dart.dart';

void main() {
  final updates = <List<int>>[];
  
  final doc1 = Doc();
  doc1.on('update', (update, [_1, _2, _3]) {
    updates.add(update as List<int>);
  });
  
  final ytext1 = doc1.get('content', () => YText())!;
  
  doc1.transact((tr) {
    ytext1.insert(0, "a");
  });
  doc1.transact((tr) {
    ytext1.delete(0, 1);
    ytext1.insert(0, "ab");
  });
  doc1.transact((tr) {
    ytext1.delete(0, 2);
    ytext1.insert(0, "abc");
  });
  doc1.transact((tr) {
    ytext1.delete(0, 3);
    ytext1.insert(0, "ab"); // I hit backspace, the UI says 'ab'
  });
  
  print('doc1 final: "${ytext1.toString()}" (length: ${ytext1.length})');
  print('Collected ${updates.length} updates');
  
  final doc2 = Doc();
  final ytext2 = doc2.get('content', () => YText())!;
  
  // Replicate what IndexedDB does: all in one transaction
  doc2.transact((tr) {
    for (var update in updates) {
      if (update is! Uint8List) {
        update = Uint8List.fromList(update);
      }
      applyUpdate(doc2, update as Uint8List, 'indexeddb');
    }
  });
  
  print('doc2 after sync: "${ytext2.toString()}" (length: ${ytext2.length})');
}
