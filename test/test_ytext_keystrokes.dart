import 'package:yjs_dart/yjs_dart.dart';

void main() {
  final doc = Doc();
  final ytext = doc.getText('content')!;
  
  // Simulate keystrokes: "W", "Wh", "Who", "Who "
  final strokes = ["W", "Wh", "Who", "Who "];
  
  for (final s in strokes) {
    doc.transact((tr) {
      if (ytext.length > 0) {
        ytext.delete(0, ytext.length);
      }
      ytext.insert(0, s);
    });
    print('After "$s": "${ytext.toString()}" (length: ${ytext.length})');
  }
}
