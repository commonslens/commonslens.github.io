/// The request categories emitted by CommonsLens' Wikimedia transport.
enum WikimediaRequestCategory {
  autocomplete,
  search,
  pipeline,
  browse,
  metadata,
  thumbnail,
  media,
  download,
  other,
}

extension WikimediaRequestCategoryLabel on WikimediaRequestCategory {
  String get label => switch (this) {
        WikimediaRequestCategory.autocomplete => 'AUTOCOMPLETE',
        WikimediaRequestCategory.search => 'SEARCH',
        WikimediaRequestCategory.pipeline => 'PIPELINE',
        WikimediaRequestCategory.browse => 'BROWSE',
        WikimediaRequestCategory.metadata => 'METADATA',
        WikimediaRequestCategory.thumbnail => 'THUMBNAIL',
        WikimediaRequestCategory.media => 'MEDIA',
        WikimediaRequestCategory.download => 'DOWNLOAD',
        WikimediaRequestCategory.other => 'OTHER',
      };
}

/// A single completed Wikimedia request.
///
/// The text representation deliberately contains only the request category,
/// URL, and HTTP result status. A `NO_RESPONSE` status means the request was
/// attempted but no HTTP response was returned by the provider.
class WikimediaRequestLogEntry {
  final WikimediaRequestCategory category;
  final String url;
  final String status;

  const WikimediaRequestLogEntry({
    required this.category,
    required this.url,
    required this.status,
  });

  String get text => '[${category.label}] $url $status';

  @override
  String toString() => text;
}

/// In-memory text log for every app-managed Wikimedia request.
///
/// [sink] receives the same single-line text stored in [entries]. The default
/// sink is `print`, which makes the log immediately available in the browser's
/// console while keeping the framework usable by non-Flutter Dart callers.
class WikimediaRequestLogger {
  WikimediaRequestLogger({void Function(String line)? sink})
      : _sink = sink ?? print;

  static final WikimediaRequestLogger instance = WikimediaRequestLogger();

  final void Function(String line) _sink;
  final List<WikimediaRequestLogEntry> _entries = [];
  final List<void Function()> _listeners = [];

  List<WikimediaRequestLogEntry> get entries =>
      List<WikimediaRequestLogEntry>.unmodifiable(_entries);

  Map<WikimediaRequestCategory, List<WikimediaRequestLogEntry>> get grouped {
    final result = <WikimediaRequestCategory, List<WikimediaRequestLogEntry>>{};
    for (final entry in _entries) {
      result.putIfAbsent(entry.category, () => []).add(entry);
    }
    return {
      for (final entry in result.entries)
        entry.key: List<WikimediaRequestLogEntry>.unmodifiable(entry.value),
    };
  }

  String get text => _entries.map((entry) => entry.text).join('\n');

  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);

  void record(
    WikimediaRequestCategory category,
    Uri uri,
    String status,
  ) {
    final entry = WikimediaRequestLogEntry(
      category: category,
      url: uri.toString(),
      status: status,
    );
    _entries.add(entry);
    _sink(entry.text);
    for (final listener in List<void Function()>.from(_listeners)) {
      listener();
    }
  }

  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    for (final listener in List<void Function()>.from(_listeners)) {
      listener();
    }
  }
}
