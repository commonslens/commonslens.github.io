import 'dart:async';

/// Coordinates one asynchronous autocomplete field.
///
/// Calls are delayed until typing pauses, and results from an older query are
/// discarded when a newer query has started. The backend remains responsible
/// for fetching and caching; this class only controls UI request timing.
class AutocompleteRequestCoordinator<T> {
  AutocompleteRequestCoordinator({
    this.delay = const Duration(milliseconds: 220),
  });

  final Duration delay;
  int _generation = 0;
  bool _disposed = false;
  Timer? _timer;
  Completer<void>? _delayCompleter;

  Future<Iterable<T>> load(
    String rawQuery,
    Future<Iterable<T>> Function(String query) fetch,
  ) async {
    final query = rawQuery.trim();
    final generation = ++_generation;
    _cancelDelay();
    if (_disposed || query.isEmpty) return <T>[];

    if (delay > Duration.zero) {
      final completer = Completer<void>();
      _delayCompleter = completer;
      _timer = Timer(delay, completer.complete);
      await completer.future;
      if (identical(_delayCompleter, completer)) {
        _delayCompleter = null;
        _timer = null;
      }
    }
    if (_disposed || generation != _generation) return <T>[];

    late final Iterable<T> results;
    try {
      results = await fetch(query);
    } catch (_) {
      if (_disposed || generation != _generation) return <T>[];
      rethrow;
    }
    if (_disposed || generation != _generation) return <T>[];
    return results;
  }

  void _cancelDelay() {
    _timer?.cancel();
    _timer = null;
    final completer = _delayCompleter;
    _delayCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  void cancel() {
    _generation++;
    _cancelDelay();
  }

  void dispose() {
    _disposed = true;
    cancel();
  }
}
