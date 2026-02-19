library;

import 'abstract_type.dart';
import 'y_array.dart';
import 'y_map.dart';
import 'y_text.dart';

import 'y_xml_fragment.dart';

/// Read a Yjs type from [decoder].
///
/// Mirrors: `readYType` in ytype.js
AbstractType<dynamic> readYType(dynamic decoder) {
  // ignore: avoid_dynamic_calls
  final typeRef = decoder.readTypeRef() as int;
  // ignore: avoid_dynamic_calls
  final name = (typeRef == typeRefXmlElement || typeRef == typeRefXmlHook)
      // ignore: avoid_dynamic_calls
      ? decoder.readKey() as String
      : null;
  
  AbstractType<dynamic> ytype;
  
  switch (typeRef) {
    case typeRefArray:
      ytype = YArray<dynamic>();
      break;
    case typeRefMap:
      ytype = YMap<dynamic>();
      break;
    case typeRefText:
      ytype = YText();
      break;
    case typeRefXmlFragment:
      ytype = YXmlFragment();
      break;
    default:
      // Fallback for types not implemented yet (XML) or unknown
      throw FormatException('Unknown type reference: $typeRef or XML type not implemented');
  }

  ytype.legacyTypeRef = typeRef;
  if (name != null) ytype.name = name;
  return ytype;
}
