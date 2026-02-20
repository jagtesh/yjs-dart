import 'package:yjs_dart/yjs_dart.dart';

void main() {
  final doc1 = Doc();
  final doc2 = Doc();
  doc1.getArray<dynamic>('arr');
  doc2.getArray<dynamic>('arr');

  applyUpdate(doc2, encodeStateAsUpdate(doc1));
  applyUpdate(doc1, encodeStateAsUpdate(doc2));

  final arr1 = doc1.getArray<dynamic>('arr')!;
  final arr2 = doc2.getArray<dynamic>('arr')!;
  
  transact(doc1, (_) => arr1.insert(0, ['from-doc1']));
  transact(doc2, (_) => arr2.insert(0, ['from-doc2']));

  print('Doc1 before merge: ${arr1.toArray()}');
  print('Doc2 before merge: ${arr2.toArray()}');

  applyUpdate(doc1, encodeStateAsUpdate(doc2));
  applyUpdate(doc2, encodeStateAsUpdate(doc1));

  print('Doc1 after merge: ${doc1.getArray<dynamic>('arr')!.toArray()}');
  print('Doc2 after merge: ${doc2.getArray<dynamic>('arr')!.toArray()}');
}
