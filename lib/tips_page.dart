import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'landing_tips.dart';
import 'legal_pages.dart';

/// A readable index of the short workflow tips bundled with the app.
class TipsPage extends StatelessWidget {
  const TipsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          tooltip: 'Back to search',
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
          icon: const Icon(Icons.arrow_back, color: Colors.white70),
        ),
        title: const Text(
          'TIPS',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        actions: const [
          DocsSectionLink(
            section: 'index',
            label: 'User Guide',
          ),
          SizedBox(width: 4),
        ],
      ),
      body: FutureBuilder<List<LandingTip>>(
        future: LandingTips.load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Tips could not be loaded right now.',
                  style: TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final tips = snapshot.data ?? const <LandingTip>[];
          if (tips.isEmpty) {
            return const Center(
              child: Text(
                'No tips are available yet.',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          return _TipsList(tips: tips);
        },
      ),
    );
  }
}

class _TipsList extends StatelessWidget {
  const _TipsList({required this.tips});

  final List<LandingTip> tips;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return SelectionArea(
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          isMobile ? 14 : 24,
          isMobile ? 22 : 34,
          isMobile ? 14 : 24,
          isMobile ? 32 : 56,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.lightbulb_outline_rounded,
                    color: Color(0xFF8EAFFF),
                    size: 30,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Small ideas, better searches.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${tips.length} quick tips for getting more from CommonsLens.\nOpen the user guide from any card when you want the longer explanation.',
                    style: const TextStyle(
                      color: Color(0xFFBDBDBD),
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ...tips.indexed.map(
                    (entry) => Padding(
                      padding: EdgeInsets.only(
                        bottom: entry.$1 == tips.length - 1 ? 0 : 12,
                      ),
                      child: _TipCard(
                        number: entry.$1 + 1,
                        tip: entry.$2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({required this.number, required this.tip});

  final int number;
  final LandingTip tip;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF292929)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF3D7EFF).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$number'.padLeft(2, '0'),
              style: const TextStyle(
                color: Color(0xFF9AB9FF),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tip.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  tip.message,
                  style: const TextStyle(
                    color: Color(0xFFBDBDBD),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => openDocsSection(tip.guideSection),
                  icon: const Icon(Icons.menu_book_outlined, size: 15),
                  label: Text(tip.guideLabel),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF9AB9FF),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 0,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
