import 'package:yjs_dart/yjs_dart.dart';

void main() {
  final doc1 = Doc();
  final ytext1 = doc1.get('content', () => YText())!;
  
  doc1.transact((tr) {
    ytext1.insert(0, "abc");
  });
  
  print('doc1 after insert: "${ytext1.toString()}" (length: ${ytext1.length})');
  
  doc1.transact((tr) {
    ytext1.delete(1, 1); // delete 'b'
  });
  
  print('doc1 after delete 1: "${ytext1.toString()}" (length: ${ytext1.length})');
  
  final update = encodeStateAsUpdate(doc1);
  
  final doc2 = Doc();
  final ytext2 = doc2.get('content', () => YText())!;
  applyUpdate(doc2, update);
  
  print('doc2 after sync: "${ytext2.toString()}" (length: ${ytext2.length})');
}
