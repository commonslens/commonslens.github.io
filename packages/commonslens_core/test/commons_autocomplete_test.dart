import 'dart:async';

import 'package:commonslens_core/commonslens_core.dart';
import 'package:test/test.dart';

class _ControlledSearchService extends SearchService {
  int categoryCalls = 0;
  String? lastCategoryQuery;
  Completer<List<String>>? pendingCategories;
  bool failNext = false;

  @override
  Future<List<String>> searchCategories(String query) {
    categoryCalls++;
    lastCategoryQuery = query;
    if (failNext) {
      failNext = false;
      return Future.error(StateError('temporary failure'));
    }
    final completer = Completer<List<String>>();
    pendingCategories = completer;
    return completer.future;
  }
}

void main() {
  test('ignores empty autocomplete requests', () async {
    final service = _ControlledSearchService();
    final autocomplete = CommonsAutocomplete(service: service);

    expect(await autocomplete.categories('   '), isEmpty);
    expect(service.categoryCalls, 0);
  });

  test('coalesces identical in-flight requests and caches their result',
      () async {
    final service = _ControlledSearchService();
    final autocomplete = CommonsAutocomplete(service: service);

    final first = autocomplete.categories('  Architecture  ');
    final second = autocomplete.categories('Architecture');

    expect(service.categoryCalls, 1);
    expect(service.lastCategoryQuery, 'Architecture');

    service.pendingCategories!.complete(['Architecture']);
    expect(await first, ['Architecture']);
    expect(await second, ['Architecture']);
    expect(await autocomplete.categories('Architecture'), ['Architecture']);
    expect(service.categoryCalls, 1);
  });

  test('does not leave failed requests in the in-flight cache', () async {
    final service = _ControlledSearchService()..failNext = true;
    final autocomplete = CommonsAutocomplete(service: service);

    await expectLater(
      autocomplete.categories('Architecture'),
      throwsStateError,
    );

    final retry = autocomplete.categories('Architecture');
    service.pendingCategories!.complete(['Architecture']);

    expect(await retry, ['Architecture']);
    expect(service.categoryCalls, 2);
  });
}
