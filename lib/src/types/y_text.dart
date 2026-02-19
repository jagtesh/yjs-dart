library;

import '../utils/transaction.dart';
import '../utils/id_set.dart' show createIdSet, mergeIdSets, IdSet;
import '../utils/struct_store.dart';
import '../structs/item.dart';
import '../structs/content.dart';
import 'abstract_type.dart';
import '../utils/id.dart';

/// A shared Text.
///
/// Mirrors: `YText` in YText.js
class YText extends AbstractType<dynamic> {
  YText([String? string]) : super() {
      legacyTypeRef = typeRefText;
      if (string != null) {
          insert(0, string);
      }
  }

  /// Inserts text at [index] with optional [attributes].
  void insert(int index, String text, [Map<String, Object?>? attributes]) {
    if (text.isEmpty) return;
    if (doc != null) {
      doc!.transact((Transaction tr) {
        typeListInsertGenerics(tr, this, index, [text]); // helper handles ContentString optimization?
        if (attributes != null && attributes.isNotEmpty) {
            format(index, text.length, attributes);
        }
      });
    } else {
        warnPrematureAccess();
    }
  }

  /// Deletes [length] characters starting at [index].
  void delete(int index, [int length = 1]) {
    if (doc != null) {
      doc!.transact((Transaction tr) {
        typeListDelete(tr, this, index, length);
      });
    } else {
      warnPrematureAccess();
    }
  }

  /// Apply formatting to [length] characters starting at [index].
  void format(int index, int length, Map<String, Object?> formats) {
      if (doc != null) {
        doc!.transact((Transaction tr) {
            // ... implementation of format ...
            // Wait, format logic was in AbstractType. I need to copy it or call helper.
            // AbstractType had format method.
            // I'll copy the body.
            final currPos = ItemTextListPosition(null, start, 0, {});
            // ... (copy logic from AbstractType.format)
             // Advance to position [index]
            var remaining = index;
            while (remaining > 0 && currPos.right != null) {
              if (!currPos.right!.deleted && currPos.right!.countable) {
                if (remaining < currPos.right!.length) {
                  getItemCleanStart(tr,
                      createID(currPos.right!.id.client, currPos.right!.id.clock + remaining));
                }
                remaining -= currPos.right!.length;
              }
              currPos.forward();
            }
            currPos.formatText(tr, this, length, formats);
        });
      } else {
          warnPrematureAccess();
      }
  }
  
  /// Returns the Delta representation of this type (for rich text).
  List<Map<String, Object?>> toDelta(
      [dynamic snapshot, dynamic prevSnapshot, Function? computeYChange]) {
      // ... copy toDelta from AbstractType ...
      // Can I just copy paste the huge function? Yes.
      // But I need to import libraries.
      // AbstractType has toDelta.
      // I'll copy it.
      
       final ops = <Map<String, Object?>>[];
       final currentAttributes = <String, Object?>{};
       final doc = this.doc;
       var str = '';
       var node = start;

       final dst = createIdSet();
       if (snapshot != null) {
         // ignore: avoid_dynamic_calls
         final ds = snapshot.ds as IdSet;
         // ignore: avoid_dynamic_calls
         final store = doc!.store;
         final storeDs = createDeleteSetFromStructStore(store);
         mergeIdSets([dst, storeDs]);
         ds.clients.forEach((client, ranges) {
           final clientranges = ranges.getIds();
           for (final id in clientranges) {
              final range = createIdSet();
              range.add(client, id.clock, id.len);
              mergeIdSets([dst, range]);
           }
         });
       }

       while (node != null) {
         if (isVisible(node, snapshot) || (prevSnapshot != null && isVisible(node, prevSnapshot))) {
           if (node.content is ContentFormat) {
             final content = node.content as ContentFormat;
             if (str.isNotEmpty) {
               final op = <String, Object?>{'insert': str};
               if (currentAttributes.isNotEmpty) {
                 op['attributes'] = Map<String, Object?>.from(currentAttributes);
               }
               ops.add(op);
               str = '';
             }
             if (content.value == null) {
               currentAttributes.remove(content.key);
             } else {
               currentAttributes[content.key] = content.value;
             }
           } else if (node.countable && !node.deleted) {
              if (node.content is ContentString) {
                str += (node.content as ContentString).str;
              } else if (node.content is ContentType || node.content is ContentEmbed) {
                if (str.isNotEmpty) {
                  final op = <String, Object?>{'insert': str};
                  if (currentAttributes.isNotEmpty) {
                    op['attributes'] = Map<String, Object?>.from(currentAttributes);
                  }
                  ops.add(op);
                  str = '';
                }
                final contentList = node.content.getContent();
                final Object? val = (contentList.length == 1) ? contentList[0] : contentList;
                final op = <String, Object?>{'insert': val};
                if (currentAttributes.isNotEmpty) {
                  op['attributes'] = Map<String, Object?>.from(currentAttributes);
                }
                ops.add(op);
              } else {
                // specific content types like ContentBinary or others
                 if (str.isNotEmpty) {
                  final op = <String, Object?>{'insert': str};
                  if (currentAttributes.isNotEmpty) {
                    op['attributes'] = Map<String, Object?>.from(currentAttributes);
                  }
                  ops.add(op);
                  str = '';
                }
                final contentList = node.content.getContent();
                final Object? val = (contentList.length == 1) ? contentList[0] : contentList;
                final op = <String, Object?>{'insert': val};
                if (currentAttributes.isNotEmpty) {
                  op['attributes'] = Map<String, Object?>.from(currentAttributes);
                }
                ops.add(op);
              }
           }
         }
         node = node.right as Item?;
       }

       if (str.isNotEmpty) {
         final op = <String, Object?>{'insert': str};
         if (currentAttributes.isNotEmpty) {
           op['attributes'] = Map<String, Object?>.from(currentAttributes);
         }
         ops.add(op);
       }
       return ops;
  }

  @override
  String toJson() {
    return toString();
  }

  @override
  String toString() {
      final sb = StringBuffer();
      var n = start;
      while (n != null) {
          if (!n.deleted && n.countable) {
              if (n.content is ContentString) {
                sb.write((n.content as ContentString).str);
              } else if (n.content is ContentType || n.content is ContentEmbed) {
                 // For text, we usually just append the embed/type placeholder or skip?
                 // Yjs text.toString() usually just returns the string content.
                 // Embeds are ignored in toString()? 
                 // Let's check YText.js. It iterates and concatenates strings.
                 // Complex content is ignored or simplified.
                 // For now, only string content.
              } else {
                  // other content
                  final c = n.content.getContent();
                  for (final item in c) {
                      if (item is String) {
                          sb.write(item);
                      }
                  }
              }
          }
          n = n.right as Item?;
      }
      return sb.toString();
  }

  @override
  YText clone() {
    return YText(toString());
  }
}
