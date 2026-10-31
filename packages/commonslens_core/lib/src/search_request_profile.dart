/// Selects the Wikimedia batch size for a media fetch.
///
/// UI and map callers deliberately use smaller pages. Pipeline ETL callers
/// opt into the larger page only when materializing data for extraction.
enum SearchRequestProfile {
  ui,
  pipelineEtl,
}

extension SearchRequestProfileX on SearchRequestProfile {
  int get pageSize => switch (this) {
        SearchRequestProfile.ui => 50,
        SearchRequestProfile.pipelineEtl => 200,
      };
}
