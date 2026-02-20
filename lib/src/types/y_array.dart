library;

import '../utils/transaction.dart';
import 'abstract_type.dart';

/// A shared Array.
///
/// Mirrors: `YArray` in YArray.js
class YArray<T> extends AbstractType<dynamic> {
  final List<T> _prelimContent = [];

  YArray() : super() {
    legacyTypeRef = typeRefArray;
  }

  @override
  void integrate(dynamic doc, dynamic item) {
    super.integrate(doc, item);
    if (_prelimContent.isNotEmpty) {
      insert(0, List.from(_prelimContent));
      _prelimContent.clear();
    }
  }

  /// Inserts content at [index].
  void insert(int index, List<T> content) {
    if (doc != null) {
      doc!.transact((Transaction tr) {
        typeListInsertGenerics(tr, this, index, content);
      });
    } else {
      _prelimContent.insertAll(index, content);
    }
  }

  /// Appends content to the end.
  void push(List<T> content) {
    insert(length, content);
  }

  /// Prepends content to the beginning.
  void unshift(List<T> content) {
    insert(0, content);
  }

  /// Deletes [length] elements starting at [index].
  void delete(int index, [int length = 1]) {
    if (doc != null) {
      doc!.transact((Transaction tr) {
        typeListDelete(tr, this, index, length);
      });
    } else {
      warnPrematureAccess();
    }
  }

  /// Returns the element at [index].
  T get(int index) {
    return typeListGet(this, index) as T;
  }

  /// Returns a portion of the content as a list.
  List<T> slice([int start = 0, int? end]) {
    return typeListSlice(this, start, end ?? length).cast<T>();
  }

  /// Returns all children as a list.
  List<T> toArray() {
    return slice(0, length);
  }

  /// Maps each child element with function [f].
  List<R> map<R>(R Function(T, int) f) {
    final arr = toArray();
    return List.generate(arr.length, (i) => f(arr[i], i));
  }

  /// Executes [f] on every child element.
  void forEach(void Function(T, int) f) {
    final arr = toArray();
    for (var i = 0; i < arr.length; i++) {
      f(arr[i], i);
    }
  }
  @override
  List<Object?> toJson() {
    return toArray().map((c) => c is AbstractType ? c.toJson() : c).toList();
  }

  @override
  String toString() {
    return toArray().toString();
  }

  @override
  YArray<T> clone() {
    final newType = YArray<T>();
    newType.insert(0, toArray().map((c) => c is AbstractType ? c.clone() : c).toList().cast<T>());
    return newType;
  }
}
