/// Dart translation of src/utils/EventHandler.js
///
/// Mirrors: yjs/src/utils/EventHandler.js (v14.0.0-22)
library;

/// General event handler implementation.
///
/// Mirrors: `EventHandler` in EventHandler.js
class EventHandler<Arg0, Arg1> {
  /// List of registered listeners.
  final List<void Function(Arg0, Arg1)> l = [];
}

/// Create a new [EventHandler].
///
/// Mirrors: `createEventHandler` in EventHandler.js
EventHandler<A, B> createEventHandler<A, B>() => EventHandler<A, B>();

/// Add an event listener to [eventHandler].
///
/// Mirrors: `addEventHandlerListener` in EventHandler.js
void addEventHandlerListener<A, B>(
  EventHandler<A, B> eventHandler,
  void Function(A, B) f,
) {
  eventHandler.l.add(f);
}

/// Remove a specific event listener from [eventHandler].
///
/// Mirrors: `removeEventHandlerListener` in EventHandler.js
void removeEventHandlerListener<A, B>(
  EventHandler<A, B> eventHandler,
  void Function(A, B) f,
) {
  final lenBefore = eventHandler.l.length;
  eventHandler.l.removeWhere((g) => identical(f, g));
  if (eventHandler.l.length == lenBefore) {
    // ignore: avoid_print
    // print('[yjs] Tried to remove event handler that doesn\'t exist.');
  }
}

/// Remove all event listeners from [eventHandler].
///
/// Mirrors: `removeAllEventHandlerListeners` in EventHandler.js
void removeAllEventHandlerListeners<A, B>(EventHandler<A, B> eventHandler) {
  eventHandler.l.clear();
}

/// Call all event listeners with [arg0] and [arg1].
///
/// Mirrors: `callEventHandlerListeners` in EventHandler.js
void callEventHandlerListeners<A, B>(
  EventHandler<A, B> eventHandler,
  A arg0,
  B arg1,
) {
  // Copy the list to avoid concurrent modification if a listener removes itself.
  for (final f in List.of(eventHandler.l)) {
    f(arg0, arg1);
  }
}
