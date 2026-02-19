library;

import 'types/abstract_type.dart';

export 'types/abstract_type.dart';
export 'types/utils.dart';
export 'types/y_array.dart';
export 'types/y_map.dart';
export 'types/y_text.dart';
export 'types/y_xml_fragment.dart';

// Backward compatibility for type checking.
// Note: AbstractType is abstract, so YType() constructor will fail,
// forcing migration to YArray()/YMap()/YText().
typedef YType<T> = AbstractType<T>;
