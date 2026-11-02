/// Selects the Wikimedia batch size for a media fetch.
///
/// UI and map callers deliberately use smaller pages. Pipeline ETL callers
/// opt into the larger page only when materializing data for extraction.
enum SearchRequestProfile {
  ui,
  pipelinePreview,
  pipelineEtl,
  pipelinePreviewWithRights,
  pipelineEtlWithRights,
}

extension SearchRequestProfileX on SearchRequestProfile {
  int get pageSize => switch (this) {
        SearchRequestProfile.ui => 50,
        SearchRequestProfile.pipelinePreview => 50,
        SearchRequestProfile.pipelineEtl => 200,
        SearchRequestProfile.pipelinePreviewWithRights => 50,
        SearchRequestProfile.pipelineEtlWithRights => 200,
      };

  /// Lightweight pipeline runs leave the expensive legacy Commons metadata
  /// block out when the manifest's rights toggle is off. Rights-enabled runs
  /// include it so the manifest can carry artist, licence, credit, and
  /// attribution status fields. The ordinary Search screen keeps its existing
  /// response shape and already includes it.
  bool get includeExtmetadata => switch (this) {
        SearchRequestProfile.ui ||
        SearchRequestProfile.pipelinePreviewWithRights ||
        SearchRequestProfile.pipelineEtlWithRights =>
          true,
        SearchRequestProfile.pipelinePreview ||
        SearchRequestProfile.pipelineEtl =>
          false,
      };

  /// Rights-enabled pipeline profiles request Commons' extmetadata block so
  /// attribution and licence fields are available to the manifest. The
  /// lightweight profiles omit it for callers that explicitly opted out.
  /// Preview and full ETL still request the same metadata shape within each
  /// pair so their source prefixes can share a resumable cache entry.
  String get cacheKey => switch (this) {
        SearchRequestProfile.pipelinePreviewWithRights ||
        SearchRequestProfile.pipelineEtlWithRights =>
          'pipeline-rights',
        SearchRequestProfile.pipelinePreview ||
        SearchRequestProfile.pipelineEtl =>
          'pipeline-core',
        SearchRequestProfile.ui => 'ui-extmetadata',
      };

  bool get isPipelineEtl =>
      this == SearchRequestProfile.pipelineEtl ||
      this == SearchRequestProfile.pipelineEtlWithRights;

  bool get isPipelinePreview =>
      this == SearchRequestProfile.pipelinePreview ||
      this == SearchRequestProfile.pipelinePreviewWithRights;
}
