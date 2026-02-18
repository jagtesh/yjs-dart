/// Native Dart implementation of lib0/observable.
///
/// Provides an Observable mixin/class for event-driven programming.
/// Mirrors: lib0/observable.js
library;

/// A typed event emitter / observable.
///
/// Mirrors: lib0/observable.Observable
class Observable<EventName> {
  final Map<EventName, List<Function>> _listeners = {};

  /// Register a listener for [eventName].
  void on(EventName eventName, Function f) {
    _listeners.putIfAbsent(eventName, () => []).add(f);
  }

  /// Remove a specific listener for [eventName].
  void off(EventName eventName, Function f) {
    final list = _listeners[eventName];
    if (list != null) {
      list.remove(f);
      if (list.isEmpty) {
        _listeners.remove(eventName);
      }
    }
  }

  /// Register a listener that fires only once.
  void once(EventName eventName, Function f) {
    late final Function wrapper;
    wrapper = ([a, b, c, d]) {
      off(eventName, wrapper);
      Function.apply(f, [a, b, c, d].where((x) => x != null).toList());
    };
    on(eventName, wrapper);
  }

  /// Emit [eventName] with optional arguments.
  void emit(EventName eventName, List<Object?> args) {
    final list = _listeners[eventName];
    if (list != null) {
      for (final f in List.of(list)) {
        Function.apply(f, args);
      }
    }
  }

  /// Check if there are any listeners for [eventName].
  bool hasObserver(EventName eventName) {
    final list = _listeners[eventName];
    return list != null && list.isNotEmpty;
  }

  /// Remove all listeners.
  void destroy() {
    _listeners.clear();
  }
}
