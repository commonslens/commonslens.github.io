/// Selects the Wikimedia batch size for a media fetch.
///
/// UI and map callers deliberately use smaller pages. Pipeline ETL callers
/// opt into the larger page only when materializing data for extraction.
enum SearchRequestProfile {
  ui,
  pipelinePreview,
  pipelineEtl,
}

extension SearchRequestProfileX on SearchRequestProfile {
  int get pageSize => switch (this) {
        SearchRequestProfile.ui => 50,
        SearchRequestProfile.pipelinePreview => 50,
        SearchRequestProfile.pipelineEtl => 200,
      };

  /// The preview deliberately leaves the expensive legacy Commons metadata
  /// block out. Its Enrich node can request the selected non-extmetadata
  /// bundles separately, while the ordinary Search screen keeps its existing
  /// response shape for now. Both pipeline profiles intentionally defer it.
  bool get includeExtmetadata => this == SearchRequestProfile.ui;

  /// Pipeline preview and full ETL intentionally request the same metadata
  /// shape so their source prefixes can share a resumable cache entry. Their
  /// page sizes differ for transport efficiency, but that must not create two
  /// independent searches for the same dataset.
  String get cacheKey =>
      includeExtmetadata ? 'ui-extmetadata' : 'pipeline-core';
}
