import 'package:go_router/go_router.dart';

import 'search_page.dart';
import 'asset_viewer.dart';
import 'author_portfolio_page.dart';
import 'map_page.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const SearchPage(),
    ),
    GoRoute(
      path: '/map',
      builder: (context, state) => const MapPage(),
    ),
    GoRoute(
      path: '/author',
      builder: (context, state) {
        final name = state.uri.queryParameters['name'] ?? '';
        return AuthorPortfolioPage(username: name);
      },
    ),
    GoRoute(
      path: '/view',
      builder: (context, state) {
        final params = state.uri.queryParameters;
        final fileId = params['id'] ?? '';
        final author = params['author'];
        final from = params['from'];

        final String returnUrl;
        if (from == 'map') {
          // Map-originated navigation (see MapPage._openItem and
          // _ResultsSheet's MediaCard extraParams). Closing always goes
          // back to '/map' regardless of which geo mode (browse/filtered)
          // produced this item, or whether filterState params are also
          // present in the URL — those params are there for AssetViewer's
          // own gallery sourcing (see 'from' handling there), not for
          // reconstructing a return route. Without this branch, 'from' was
          // silently ignored and this fell through to the '/' case below —
          // which is what sent map taps back to the main search page.
          returnUrl = '/map';
        } else if (author != null && author.trim().isNotEmpty) {
          returnUrl =
              Uri(path: '/author', queryParameters: {'name': author}).toString();
        } else {
          final returnParams = Map<String, String>.from(params)..remove('id');
          returnUrl = Uri(
            path: '/',
            queryParameters: returnParams.isEmpty ? null : returnParams,
          ).toString();
        }

        return AssetViewer(fileId: fileId, returnUrl: returnUrl);
      },
    ),
  ],
);