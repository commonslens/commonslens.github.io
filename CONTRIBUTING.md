# Contributing to CommonsLens

Thank you for your interest in improving CommonsLens. Contributions,
well-scoped bug reports, documentation improvements, and thoughtful feature
proposals are welcome.

## Before you start

CommonsLens is a Flutter web application that reads public media and metadata
from Wikimedia Commons. You do not need a Wikimedia account to develop or run
the project.

Please check the existing issues and documentation before starting a large
change. For substantial feature work, opening an issue first can help confirm
the scope and avoid duplicated effort.

## Development setup

You will need:

- Flutter stable
- A Dart SDK compatible with `^3.6.0`
- A modern browser, preferably Chrome or Chromium

From a checkout of the repository:

```bash
flutter pub get
flutter run -d chrome
```

## Making changes

1. Fork the repository and create a focused branch from `master`.
2. Keep changes small enough to review and preserve the existing responsive
   web and mobile behaviour.
3. Add or update tests for changed behaviour where practical.
4. Keep Wikimedia API usage courteous. Do not add polling, retries, or bulk
   requests that could place unnecessary load on Wikimedia services.
5. Do not treat incomplete metadata as proof of a licence or other legal
   status. User-facing rights guidance should continue to direct users to the
   original Commons file page and its complete licence information.

For changes to the static site metadata, documentation, or web shell, remember
that files under `web/` are copied into the deployed Flutter web output. The
Toolhub metadata is maintained in [`web/toolinfo.json`](web/toolinfo.json).

## Formatting and tests

Format Dart files that you change and run the static analyser and test suites:

```bash
dart format lib test packages/commonslens_core/lib
flutter analyze
flutter test
```

The reusable core package has its own test command:

```bash
cd packages/commonslens_core
dart test
```

Tests that exercise live Wikimedia services are opt-in. Run them only when
network access is available and the upstream service can be queried safely:

```bash
flutter test --dart-define=RUN_LIVE_WIKIMEDIA_TESTS=true
```

Before submitting a web-specific change, it is also useful to verify a
production build locally:

```bash
flutter build web --release --base-href /
dart run tool/generate_seo_pages.dart build/web
```

## Pull requests

A pull request should:

- Explain what changed and why.
- Describe any user-visible behaviour or compatibility considerations.
- Include the tests and checks you ran.
- Include screenshots or a short recording for meaningful UI changes.
- Call out known limitations, upstream Wikimedia dependencies, or follow-up
  work.

The deployment workflow publishes the `master` branch to GitHub Pages. Pull
requests should be ready to build with the repository’s Flutter stable
workflow before they are merged.

## Reporting issues

Use the issue tracker for reproducible bugs, documentation problems, and
focused feature requests. Include the affected page or route, steps to
reproduce, expected and actual behaviour, browser/device details, and any
relevant Wikimedia source URLs. Please avoid including private or sensitive
information in issue reports.

## Licensing

Unless explicitly stated otherwise, contributions submitted for inclusion in
CommonsLens are accepted under the Apache License 2.0. See [LICENSE](LICENSE)
for the full terms.
