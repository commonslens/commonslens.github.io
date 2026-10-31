// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:commonslens/browse_page.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'search_page.dart';
import 'asset_viewer.dart';
import 'author_portfolio_page.dart';
import 'pipeline_page.dart';
import 'features_page.dart';
import 'bookmarks_page.dart';
import 'legal_pages.dart';
import 'seo_service.dart';
import 'media_queue.dart';

/// Keeps SEO metadata in sync on every route push, pop, or replacement.
/// Reads the live browser URL (accurate thanks to usePathUrlStrategy() in
/// main.dart) rather than trying to reconstruct a path from GoRouter's own
/// route objects, which is simpler and can't drift out of sync with what's
/// actually in the address bar.
class _NavigationObserver extends NavigatorObserver {
  void _track() {
    final loc = html.window.location;
    SeoService.sync(Uri.parse('${loc.pathname}${loc.search}'));
  }

  @override
  void didPush(Route route, Route? previousRoute) => _track();
  @override
  void didPop(Route route, Route? previousRoute) => _track();
  @override
  void didReplace({Route? newRoute, Route? oldRoute}) => _track();
}

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  observers: [_NavigationObserver()],
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => SearchPage(
        queryParameters: Map<String, String>.from(state.uri.queryParameters),
      ),
    ),
    GoRoute(
      path: '/browse',
      builder: (context, state) => const BrowsePage(),
    ),
    GoRoute(
      path: '/map',
      redirect: (context, state) {
        final params = Map<String, String>.from(state.uri.queryParameters);
        final legacyRadius = params.remove('radiusKm');
        if (legacyRadius != null && !params.containsKey('radius')) {
          params['radius'] = legacyRadius;
        }
        params['view'] = 'map';
        return Uri(path: '/', queryParameters: params).toString();
      },
    ),
    GoRoute(
      path: '/pipeline',
      builder: (context, state) => const PipelinePage(),
    ),
    GoRoute(
      path: '/features',
      builder: (context, state) => const FeaturesPage(),
    ),
    GoRoute(
      path: '/bookmarks',
      builder: (context, state) => BookmarksPage(
        initialQuery: state.uri.queryParameters['bq'] ?? '',
      ),
    ),
    GoRoute(
      path: '/terms',
      builder: (context, state) => const TermsOfUsePage(),
    ),
    GoRoute(
      path: '/privacy',
      builder: (context, state) => const PrivacyPolicyPage(),
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
        final viewerContext = Map<String, String>.from(params)..remove('id');
        final source = MediaQueueSource.fromUrl(params);
        final returnUrl = params['from'] == 'map' && source.kind == 'direct'
            ? '/map'
            : source.returnUrl;

        return AssetViewer(
          key: ValueKey(Uri(queryParameters: viewerContext).query),
          fileId: fileId,
          returnUrl: returnUrl,
        );
      },
    ),
  ],
);
