# commonslens_core

Pure Dart Wikimedia search, metadata, pagination, and pipeline backend used by
CommonsLens. The package has no Flutter or browser dependency.

Run the headless JSON interface:

```sh
echo '{"operation":"search","filters":{"queryText":"Eiffel Tower"}}' |
  dart run bin/commonslens.dart
```
