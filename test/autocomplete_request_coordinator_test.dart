import 'dart:async';

import 'package:commonslens/autocomplete_request_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('does not fetch empty queries', () async {
    final coordinator = AutocompleteRequestCoordinator<String>(
      delay: Duration.zero,
    );
    addTearDown(coordinator.dispose);
    var calls = 0;

    final results = await coordinator.load('   ', (query) async {
      calls++;
      return [query];
    });

    expect(results, isEmpty);
    expect(calls, 0);
  });

  test('only fetches the latest query during the debounce window', () async {
    final coordinator = AutocompleteRequestCoordinator<String>(
      delay: const Duration(milliseconds: 10),
    );
    addTearDown(coordinator.dispose);
    final fetched = <String>[];

    final oldRequest = coordinator.load('arch', (query) async {
      fetched.add(query);
      return [query];
    });
    final newRequest = coordinator.load('architecture', (query) async {
      fetched.add(query);
      return [query];
    });

    expect(await oldRequest, isEmpty);
    expect(await newRequest, ['architecture']);
    expect(fetched, ['architecture']);
  });

  test('discards a completion made stale by a newer query', () async {
    final coordinator = AutocompleteRequestCoordinator<String>(
      delay: Duration.zero,
    );
    addTearDown(coordinator.dispose);
    final firstResult = Completer<Iterable<String>>();

    final first = coordinator.load('first', (_) => firstResult.future);
    await Future<void>.delayed(Duration.zero);
    final second = coordinator.load('second', (query) async => [query]);
    firstResult.complete(['first']);

    expect(await first, isEmpty);
    expect(await second, ['second']);
  });

  test('suppresses an error from a request made stale by a newer query',
      () async {
    final coordinator = AutocompleteRequestCoordinator<String>(
      delay: Duration.zero,
    );
    addTearDown(coordinator.dispose);
    final firstResult = Completer<Iterable<String>>();

    final first = coordinator.load('first', (_) => firstResult.future);
    final second = coordinator.load('second', (query) async => [query]);
    firstResult.completeError(StateError('stale failure'));

    expect(await first, isEmpty);
    expect(await second, ['second']);
  });
}
