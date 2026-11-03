import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'legal_pages.dart';

/// The public-facing introduction to CommonsLens.
///
/// The user guide owns the detailed explanations. This page is deliberately
/// more like an interactive editorial: one big idea, one big visual, then the
/// next idea arrives as the previous one recedes.
class FeaturesPage extends StatefulWidget {
  const FeaturesPage({super.key});

  static const _mobileBreakpoint = 600.0;

  // Swap the assetPath values below when the final campaign artwork is ready.
  // The media frame accepts GIFs, illustrations, screenshots, or still images.
  static const _showcase = <_ShowcaseFeature>[
    _ShowcaseFeature(
      number: '01',
      eyebrow: 'START WITH THE OPEN WEB',
      title: 'The world’s visual archive. One clear starting point.',
      description:
          'CommonsLens searches Wikimedia Commons across images, audio, video, documents, vectors, and 3D. Type the thing you want — or the thing you almost remember — and let the archive meet you halfway.',
      points: [
        'Switch media families without rebuilding your search.',
        'Use examples and focused result tabs when the right words are still hiding.',
        'Stay close to the source: every result leads back to Commons.',
      ],
      assetPath: 'assets/features_media/glacier_point.jpg',
      mediaLabel: 'Glacier Point at Sunset, Yosemite NP, CA, US',
      mediaCredit: 'Diliff · Own work · CC BY-SA 3.0 · Wikimedia Commons',
      sourceUrl:
          'https://commons.wikimedia.org/wiki/File:Glacier_Point_at_Sunset,_Yosemite_NP,_CA,_US_-_Diliff.jpg',
      accent: Color(0xFF7AABFF),
      ctaLabel: 'Start exploring',
      route: '/',
      guideSection: 'search',
    ),
    _ShowcaseFeature(
      number: '02',
      eyebrow: 'FOLLOW THE THREAD',
      title: 'Precision without the paperwork.',
      description:
          'A good filter should sharpen the picture, not bury the idea. Combine subjects, categories, templates, rights, quality, dates, dimensions, file size, metadata, and location while your search keeps taking shape.',
      points: [
        'Instant choices update the result set as you make them.',
        'Technical filters find files that fit the job, not just the topic.',
        'Keep rights and attribution in view before you fall in love with a file.',
      ],
      assetPath: 'assets/features_media/midtown_manhattan.jpg',
      mediaLabel: 'Midtown Manhattan from Weehawken, September 2021',
      mediaCredit:
          'King of Hearts · Own work · CC BY-SA 4.0 · Wikimedia Commons',
      sourceUrl:
          'https://commons.wikimedia.org/wiki/File:Midtown_Manhattan_from_Weehawken_September_2021_HDR.jpg',
      accent: Color(0xFFB5CF8A),
      ctaLabel: 'See the filters',
      guideSection: 'advanced-filters',
    ),
    _ShowcaseFeature(
      number: '03',
      eyebrow: 'PLACE MATTERS',
      title: 'Search by where the story happened.',
      description:
          'Some media only makes sense when you know where it belongs. Put a point on the map, set a radius, or explore geographic context, then move from place to file without losing the thread.',
      points: [
        'Use nearby coordinates to turn a place into a search.',
        'Move between map and grid when context or comparison matters.',
        'Let geography surface the unexpected.',
      ],
      assetPath: 'assets/features_media/iss_aug2005.jpg',
      mediaLabel: 'ISS, August 2005',
      mediaCredit: 'NASA · Public domain · Wikimedia Commons',
      sourceUrl: 'https://commons.wikimedia.org/wiki/File:ISS_Aug2005.jpg',
      accent: Color(0xFFE4A36C),
      ctaLabel: 'Open the map',
      route: '/map',
      guideSection: 'map',
    ),
    _ShowcaseFeature(
      number: '04',
      eyebrow: 'LOOK CLOSER',
      title: 'An image is not the whole file.',
      description:
          'Open an asset and get the context that makes it usable: metadata, structured data, related media, source links, reported rights, and a ready-to-edit attribution starting point.',
      points: [
        'See dimensions, dates, creators, categories, and structured statements together.',
        'Trace a promising file back to its Commons source.',
        'Make the reuse decision with evidence, not a guess.',
      ],
      assetPath: 'assets/features_media/monet_bridge.jpg',
      mediaLabel: "Claude Monet — Le Pont d'Argenteuil",
      mediaCredit: 'Pierre André Leclercq · Public domain · Wikimedia Commons',
      sourceUrl:
          "https://commons.wikimedia.org/wiki/File:Claude_Monet.-_Le_Pont_d'Argenteuil.JPG",
      accent: Color(0xFFD09BE8),
      ctaLabel: 'Learn about reuse',
      guideSection: 'reuse',
    ),
    _ShowcaseFeature(
      number: '05',
      eyebrow: 'KEEP THE GOOD STUFF',
      title: 'Collect discoveries before they disappear.',
      description:
          'The best research rarely arrives in one sitting. Bookmark files, arrange them in folders, download what you need, and export the metadata that lets your work travel.',
      points: [
        'Build local collections of references without copying the Commons catalogue.',
        'Download media separately from CSV metadata and URLs.',
        'Explore an uploader’s portfolio when one good file opens a larger trail.',
      ],
      assetPath: 'assets/features_media/jaws_of_death.jpg',
      mediaLabel: 'Into the Jaws of Death',
      mediaCredit:
          'CPHoM Robert F. Sargent · Public domain · Wikimedia Commons',
      sourceUrl:
          'https://commons.wikimedia.org/wiki/File:Into_the_Jaws_of_Death_23-0455M_edit.jpg',
      accent: Color(0xFFF0C66D),
      ctaLabel: 'See saved work',
      route: '/bookmarks',
      guideSection: 'bookmarks',
    ),
    _ShowcaseFeature(
      number: '06',
      eyebrow: 'BUILD WORKFLOWS',
      title: 'Build a visual pipeline',
      description:
          'Pipelines connect fetching, filtering, enrichment, and export into a visual workflow. Start with a question; come back later with a process you can inspect, change, and run again.',
      points: [
        'Keep each step visible instead of hiding the method in a tangle of tabs.',
        'Reuse a workflow when the question grows from one file to a collection.',
        'Export the result when it is ready for the next tool.',
      ],
      assetPath: 'assets/features_media/dna_orbit.gif',
      mediaLabel: 'DNA Orbit Animated Clean',
      mediaCredit: 'Circli · Own work · CC BY-SA 4.0 · Wikimedia Commons',
      sourceUrl:
          'https://commons.wikimedia.org/wiki/File:DNA_Orbit_Animated_Clean.gif',
      accent: Color(0xFF84D3CB),
      ctaLabel: 'Build a pipeline',
      route: '/pipeline',
      guideSection: 'pipelines',
      showOnMobile: false,
    ),
  ];

  @override
  State<FeaturesPage> createState() => _FeaturesPageState();
}

class _FeaturesPageState extends State<FeaturesPage>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late final AnimationController _heroController;

  @override
  void initState() {
    super.initState();
    _heroController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();
  }

  @override
  void dispose() {
    _heroController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile =
        MediaQuery.of(context).size.width < FeaturesPage._mobileBreakpoint;
    final visibleShowcase = FeaturesPage._showcase.where(
      (feature) => !isMobile || feature.showOnMobile,
    );
    final viewportHeight =
        (math.max(600.0, MediaQuery.sizeOf(context).height - kToolbarHeight))
            .toDouble();
    final heroHeight = (math.max(
      isMobile ? 610.0 : 700.0,
      viewportHeight * 0.88,
    )).toDouble();
    final pairHeight = (math.max(
      isMobile ? 620.0 : 680.0,
      viewportHeight * 0.96,
    )).toDouble();

    final heroWidth = math.min(
      900.0,
      MediaQuery.sizeOf(context).width - (isMobile ? 28.0 : 56.0),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: 'Back to search',
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
          icon: const Icon(Icons.arrow_back, color: Colors.white70),
        ),
        title: const Text(
          'COMMONSLENS',
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.8,
          ),
        ),
        actions: const [
          DocsSectionLink(section: 'index', label: 'User Guide'),
          SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _FeaturePageBackdrop()),
          SelectionArea(
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.only(
                top: isMobile ? 18 : 30,
                bottom: isMobile ? 36 : 64,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: heroHeight,
                    width: double.infinity,
                    child: AnimatedBuilder(
                      animation: _heroController,
                      builder: (context, child) {
                        final progress = Curves.easeOutCubic.transform(
                          _heroController.value,
                        );
                        return Opacity(
                          opacity: progress,
                          child: Transform.translate(
                            offset: Offset(0, 34 * (1 - progress)),
                            child: child,
                          ),
                        );
                      },
                      child: Center(
                        child: SizedBox(
                          width: heroWidth,
                          child: _buildHero(context, isMobile),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: isMobile ? 16 : 22),
                  _buildShowcaseIntro(isMobile),
                  SizedBox(height: isMobile ? 14 : 22),
                  ...visibleShowcase.map(
                    (feature) => _ShowcaseRow(
                      key: ValueKey(feature.number),
                      feature: feature,
                      reversed: int.parse(feature.number).isEven,
                      isMobile: isMobile,
                      featureHeight: pairHeight,
                      scrollController: _scrollController,
                    ),
                  ),
                  SizedBox(height: isMobile ? 28 : 48),
                  _buildNextStep(context, isMobile),
                  const SizedBox(height: 46),
                  const SiteFooter(),
                ],
              ),
            ),
          ),
          if (!isMobile)
            Positioned(
              top: 112,
              right: 14,
              bottom: 112,
              child: _FeatureProgressRail(
                controller: _scrollController,
                count: visibleShowcase.length,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHero(BuildContext context, bool isMobile) {
    final titleStyle = TextStyle(
      color: Colors.white,
      fontSize: isMobile ? 39 : 64,
      height: 0.99,
      fontWeight: FontWeight.w700,
      letterSpacing: isMobile ? -1.2 : -2.5,
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 2,
                color: const Color(0xFF3D7EFF),
              ),
              const SizedBox(width: 12),
              const Text(
                'A VISUAL RESEARCH WORKSPACE',
                style: TextStyle(
                  color: Color(0xFF8CAFFF),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.8,
                ),
              ),
            ],
          ),
          SizedBox(height: isMobile ? 24 : 30),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Find the image.\n'),
                const TextSpan(
                  text: 'Keep the story.',
                  style: TextStyle(color: Color(0xFF8CAFFF)),
                ),
              ],
            ),
            textAlign: TextAlign.center,
            style: titleStyle,
          ),
          SizedBox(height: isMobile ? 22 : 26),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Text(
              'CommonsLens helps you move through Wikimedia Commons with more intention — from the first spark of an idea to a find you can understand, save, and use responsibly.',
              style: TextStyle(
                color: const Color(0xFFC4C8D0),
                fontSize: isMobile ? 15 : 18,
                height: 1.55,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: isMobile ? 26 : 32),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              _RouteButton(
                label: 'Start exploring',
                icon: Icons.arrow_forward_rounded,
                filled: true,
                onPressed: () => context.go('/'),
              ),
              _RouteButton(
                label: 'Browse the archive',
                icon: Icons.grid_view_rounded,
                onPressed: () => context.push('/browse'),
              ),
            ],
          ),
          SizedBox(height: isMobile ? 28 : 38),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: const [
              _HeroSignal(icon: Icons.search_rounded, label: 'Discover'),
              _HeroSignal(icon: Icons.tune_rounded, label: 'Refine'),
              _HeroSignal(
                icon: Icons.auto_stories_outlined,
                label: 'Understand',
              ),
              _HeroSignal(icon: Icons.ios_share_rounded, label: 'Reuse'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShowcaseIntro(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          'THE SHAPE OF A GOOD FIND',
          style: TextStyle(
            color: Color(0xFF73819A),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.7,
          ),
        ),
        const SizedBox(height: 9),
        Text(
          isMobile ? 'Five ways to look closer.' : 'Six ways to look closer.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: isMobile ? 26 : 34,
            height: 1.05,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
          ),
        ),
        if (!isMobile) ...[
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 560),
            child: Text(
              'A quick introduction to the parts of CommonsLens that help an interesting file become a useful one.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF8D96A6),
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildNextStep(BuildContext context, bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 22 : 32),
      color: Colors.black,
      child: Flex(
        direction: isMobile ? Axis.vertical : Axis.horizontal,
        crossAxisAlignment:
            isMobile ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          if (isMobile)
            const _NextStepCopy(compact: true)
          else
            const Expanded(child: _NextStepCopy(compact: false)),
          SizedBox(
            width: isMobile ? 0 : 22,
            height: isMobile ? 20 : 0,
          ),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              _RouteButton(
                label: 'Search Wikimedia Commons',
                icon: Icons.search_rounded,
                filled: true,
                onPressed: () => context.go('/'),
              ),
              if (!isMobile)
                _RouteButton(
                  label: 'Read the user guide',
                  icon: Icons.menu_book_outlined,
                  onPressed: openDocs,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShowcaseFeature {
  const _ShowcaseFeature({
    required this.number,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.points,
    required this.assetPath,
    required this.mediaLabel,
    required this.mediaCredit,
    required this.sourceUrl,
    required this.accent,
    required this.ctaLabel,
    required this.guideSection,
    this.route,
    this.showOnMobile = true,
  });

  final String number;
  final String eyebrow;
  final String title;
  final String description;
  final List<String> points;
  final String assetPath;
  final String mediaLabel;
  final String mediaCredit;
  final String sourceUrl;
  final Color accent;
  final String ctaLabel;
  final String guideSection;
  final String? route;
  final bool showOnMobile;
}

class _ShowcaseRow extends StatefulWidget {
  const _ShowcaseRow({
    super.key,
    required this.feature,
    required this.reversed,
    required this.isMobile,
    required this.featureHeight,
    required this.scrollController,
  });

  final _ShowcaseFeature feature;
  final bool reversed;
  final bool isMobile;
  final double featureHeight;
  final ScrollController scrollController;

  @override
  State<_ShowcaseRow> createState() => _ShowcaseRowState();
}

class _ShowcaseRowState extends State<_ShowcaseRow> {
  double _focus = 0;
  double _signedPosition = 1;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_updateMotion);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateMotion());
  }

  @override
  void didUpdateWidget(covariant _ShowcaseRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_updateMotion);
      widget.scrollController.addListener(_updateMotion);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateMotion());
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_updateMotion);
    super.dispose();
  }

  void _updateMotion() {
    if (!mounted) return;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;

    final top = renderObject.localToGlobal(Offset.zero).dy;
    final center = top + renderObject.size.height / 2;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final bodyTop = kToolbarHeight;
    final bodyHeight = math.max(1.0, screenHeight - bodyTop);
    final target = bodyTop + bodyHeight * 0.5;
    final signed =
        ((center - target) / (bodyHeight * 0.82)).clamp(-1.0, 1.0).toDouble();
    final focus = (1 - signed.abs()).clamp(0.0, 1.0).toDouble();

    if ((signed - _signedPosition).abs() < 0.002 &&
        (focus - _focus).abs() < 0.002) {
      return;
    }
    setState(() {
      _signedPosition = signed;
      _focus = focus;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mediaTravel = -_signedPosition * (widget.isMobile ? 22.0 : 46.0);
    final copyTravel = (widget.reversed ? -1.0 : 1.0) *
        _signedPosition *
        (widget.isMobile ? 20.0 : 38.0);
    final scale = 0.975 + (_focus * 0.025);
    final opacity = 0.72 + (_focus * 0.28);

    final media = Transform.translate(
      offset: Offset(0, mediaTravel),
      child: _FeatureMedia(
        feature: widget.feature,
        compact: widget.isMobile,
        fillAvailable: true,
      ),
    );
    final copy = Transform.translate(
      offset: Offset(copyTravel, 0),
      child: _FeatureCopy(
        feature: widget.feature,
        compact: widget.isMobile,
      ),
    );

    final scene = widget.isMobile
        ? ConstrainedBox(
            constraints: BoxConstraints(minHeight: widget.featureHeight),
            child: Column(
              children: widget.reversed
                  ? [
                      copy,
                      SizedBox(
                        height: widget.featureHeight * 0.42,
                        child: media,
                      ),
                    ]
                  : [
                      SizedBox(
                        height: widget.featureHeight * 0.42,
                        child: media,
                      ),
                      copy,
                    ],
            ),
          )
        : ConstrainedBox(
            constraints: BoxConstraints(minHeight: widget.featureHeight),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.reversed
                    ? [
                        Expanded(child: copy),
                        Expanded(child: media),
                      ]
                    : [
                        Expanded(child: media),
                        Expanded(child: copy),
                      ],
              ),
            ),
          );

    return Opacity(
      opacity: opacity,
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.center,
        child: ColoredBox(
          color: Colors.black,
          child: ClipRect(child: scene),
        ),
      ),
    );
  }
}

class _FeatureMedia extends StatelessWidget {
  const _FeatureMedia({
    required this.feature,
    required this.compact,
    this.fillAvailable = false,
  });

  final _ShowcaseFeature feature;
  final bool compact;
  final bool fillAvailable;

  Future<void> _openSource() async {
    final uri = Uri.parse(feature.sourceUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final frame = Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          feature.assetPath,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stackTrace) => ColoredBox(
            color: feature.accent.withValues(alpha: 0.12),
            child: Icon(
              Icons.image_outlined,
              color: feature.accent,
              size: 42,
            ),
          ),
        ),
        Positioned(
          top: compact ? 14 : 22,
          left: compact ? 14 : 22,
          child: _MediaBadge(
            label: feature.number,
            accent: feature.accent,
          ),
        ),
        Positioned(
          left: compact ? 14 : 22,
          right: compact ? 14 : 22,
          bottom: compact ? 13 : 22,
          child: Material(
            color: Colors.black,
            child: InkWell(
              onTap: _openSource,
              borderRadius: BorderRadius.circular(7),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      feature.mediaLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 12 : 14,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            feature.mediaCredit,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: const Color(0xFFC1C7D2),
                              fontSize: compact ? 10 : 11,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Icon(
                          Icons.open_in_new_rounded,
                          color: Color(0xFFC1C7D2),
                          size: 12,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );

    if (fillAvailable) return frame;
    return AspectRatio(
      aspectRatio: compact ? 1.62 : 1.22,
      child: frame,
    );
  }
}

class _FeatureCopy extends StatelessWidget {
  const _FeatureCopy({required this.feature, required this.compact});

  final _ShowcaseFeature feature;
  final bool compact;

  void _openRoute(BuildContext context) {
    if (feature.route == null) return;
    if (feature.route == '/') {
      context.go('/');
    } else {
      context.push(feature.route!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(compact ? 22 : 58),
      child: Column(
        crossAxisAlignment:
            compact ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            feature.eyebrow,
            style: TextStyle(
              color: feature.accent,
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.7,
            ),
          ),
          const SizedBox(height: 15),
          Text(
            feature.title,
            textAlign: compact ? TextAlign.start : TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 25 : 42,
              height: 1.05,
              fontWeight: FontWeight.w700,
              letterSpacing: compact ? -0.6 : -1.2,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            feature.description,
            textAlign: compact ? TextAlign.start : TextAlign.center,
            style: TextStyle(
              color: const Color(0xFFB1B8C5),
              fontSize: compact ? 14 : 16,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 22),
          ...feature.points.map(
            (point) => Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Icon(
                      Icons.add_rounded,
                      color: feature.accent,
                      size: 15,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      point,
                      style: TextStyle(
                        color: const Color(0xFFD1D5DD),
                        fontSize: compact ? 12.5 : 13.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: compact ? WrapAlignment.start : WrapAlignment.center,
            spacing: 4,
            runSpacing: 0,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (feature.route != null)
                TextButton.icon(
                  onPressed: () => _openRoute(context),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: Text(feature.ctaLabel),
                  style: TextButton.styleFrom(
                    foregroundColor: feature.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 0),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              DocsSectionLink(
                section: feature.guideSection,
                label: feature.route == null ? feature.ctaLabel : 'User guide',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeatureProgressRail extends StatefulWidget {
  const _FeatureProgressRail({
    required this.controller,
    required this.count,
  });

  final ScrollController controller;
  final int count;

  @override
  State<_FeatureProgressRail> createState() => _FeatureProgressRailState();
}

class _FeatureProgressRailState extends State<_FeatureProgressRail> {
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant _FeatureProgressRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!mounted || !widget.controller.hasClients) return;
    final max = widget.controller.position.maxScrollExtent;
    final next = max <= 0 ? 0.0 : widget.controller.offset / max;
    if ((next - _progress).abs() > 0.002) {
      setState(() => _progress = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active =
        (_progress * widget.count).floor().clamp(0, widget.count - 1);
    return IgnorePointer(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 1,
            height: 48,
            color: const Color(0xFF5C6B84).withValues(alpha: 0.45),
          ),
          const SizedBox(height: 12),
          ...List.generate(
            widget.count,
            (index) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: index == active ? 9 : 5,
                height: index == active ? 9 : 5,
                decoration: BoxDecoration(
                  color: index == active
                      ? const Color(0xFF8CAFFF)
                      : const Color(0xFF506078),
                  shape: BoxShape.circle,
                  boxShadow: index == active
                      ? const [
                          BoxShadow(
                            color: Color(0x668CAFFF),
                            blurRadius: 10,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: 1,
            height: 48,
            color: const Color(0xFF5C6B84).withValues(alpha: 0.45),
          ),
        ],
      ),
    );
  }
}

class _NextStepCopy extends StatelessWidget {
  const _NextStepCopy({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'READY WHEN YOU ARE',
          style: TextStyle(
            color: Color(0xFF8CAFFF),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.7,
          ),
        ),
        const SizedBox(height: 9),
        Text(
          'Bring a question. Leave with a trail.',
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 22 : 27,
            height: 1.1,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'The archive is open. CommonsLens gives your looking somewhere to go.',
          style: TextStyle(
            color: Color(0xFFAAB5C8),
            fontSize: 14,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _MediaBadge extends StatelessWidget {
  const _MediaBadge({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xD90B0D12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: TextStyle(
            color: accent,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}

class _HeroSignal extends StatelessWidget {
  const _HeroSignal({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF111722).withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFF242D3C)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xFF8CAFFF)),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFB9C2D1),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeaturePageBackdrop extends StatelessWidget {
  const _FeaturePageBackdrop();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: ColoredBox(color: Colors.black),
    );
  }
}

class _RouteButton extends StatelessWidget {
  const _RouteButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: filled ? const Color(0xFF07101E) : Colors.white70,
        backgroundColor: filled ? const Color(0xFF8CAFFF) : null,
        side: BorderSide(
          color: filled ? const Color(0xFF8CAFFF) : const Color(0xFF303A4B),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
      icon: Icon(icon, size: 17),
      label: Text(label),
    );
  }
}
