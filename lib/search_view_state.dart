import 'search_models.dart';

class SearchViewState {
  final SearchState filterState;
  final SearchSession activeSession;
  final QueryBuildResult? lastBuiltQuery;
  final String? externalQueueNodeId;

  const SearchViewState({
    required this.filterState,
    required this.activeSession,
    this.lastBuiltQuery,
    this.externalQueueNodeId,
  });

  SearchViewState copyWith({
    SearchState? filterState,
    SearchSession? activeSession,
    QueryBuildResult? lastBuiltQuery,
    String? externalQueueNodeId,
    bool clearExternalQueueNodeId = false,
  }) {
    return SearchViewState(
      filterState: filterState ?? this.filterState,
      activeSession: activeSession ?? this.activeSession,
      lastBuiltQuery: lastBuiltQuery ?? this.lastBuiltQuery,
      externalQueueNodeId: clearExternalQueueNodeId
          ? null
          : (externalQueueNodeId ?? this.externalQueueNodeId),
    );
  }
}
