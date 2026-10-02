import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'commons_backend.dart';

/// One backend graph for the entire UI. Controllers and lazy detail
/// providers share its transport, autocomplete cache, and request policy.
final commonsBackendProvider = Provider<CommonsBackend>((ref) {
  return CommonsBackend();
});

final commonsAutocompleteProvider = Provider<CommonsAutocomplete>((ref) {
  return ref.watch(commonsBackendProvider).autocomplete;
});
