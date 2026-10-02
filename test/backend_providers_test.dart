import 'package:commonslens/backend_providers.dart';
import 'package:commonslens/commons_backend.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('backend and autocomplete providers are shared per container', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      identical(
        container.read(commonsBackendProvider),
        container.read(commonsBackendProvider),
      ),
      isTrue,
    );
    expect(
      identical(
        container.read(commonsAutocompleteProvider),
        container.read(commonsAutocompleteProvider),
      ),
      isTrue,
    );
  });

  test('the complete provider graph follows a backend override', () {
    final backend = CommonsBackend();
    final container = ProviderContainer(
      overrides: [commonsBackendProvider.overrideWithValue(backend)],
    );
    addTearDown(container.dispose);

    expect(container.read(commonsBackendProvider), same(backend));
    expect(
      container.read(commonsAutocompleteProvider),
      same(container.read(commonsAutocompleteProvider)),
    );
  });
}
