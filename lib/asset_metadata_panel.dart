part of 'asset_viewer.dart';

class _MetadataInspector extends StatelessWidget {
  final SearchItem item;
  final _ViewerImageQuality? imageQuality;
  final ValueChanged<_ViewerImageQuality>? onImageQualityChanged;
  final VoidCallback onLaunchCommons;

  const _MetadataInspector({
    required this.item,
    required this.imageQuality,
    required this.onImageQualityChanged,
    required this.onLaunchCommons,
  });

  String _cleanHtml(String html) {
    if (html.isEmpty) return '';
    final exp = RegExp(r'<[^>]*>', multiLine: true, caseSensitive: true);
    return html.replaceAll(exp, '').trim();
  }

  /// Shared section header, used everywhere below instead of one-off
  /// Text+Divider blocks, so every section in the panel reads with the
  /// same rhythm as it flows from Title -> Author -> Download ->
  /// Description -> Dates -> Metadata -> Global Usage.
  Widget _sectionHeader(String label, {bool withDivider = true}) {
    return Padding(
      padding: EdgeInsets.only(top: withDivider ? 0 : 24, bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (withDivider) ...[
            const Divider(color: Color(0xFF222222)),
            const SizedBox(height: 24),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF666666),
              fontSize: 10,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // 1. TITLE
        SelectableText(
          item.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            height: 1.3,
          ),
        ),

        // 2. AUTHOR — who made it and who uploaded it, together, right
        // under the title since that's the first thing after "what is
        // this" that a person orients on.
        _buildAuthorSection(context),

        // Keep the image-loading choice with the file details rather than
        // obscuring the media itself. Non-image assets have no alternate
        // preview URL, so the control is omitted for them.
        if (imageQuality != null && onImageQualityChanged != null)
          _buildImageQualityControl(),

        // 3. DOWNLOAD — get the file, plus the one action that starts a
        // new exploration from this file: finding everything else shot
        // near it.
        _sectionHeader('DOWNLOAD & ACTIONS', withDivider: false),
        _DownloadSection(item: item, onLaunchCommons: onLaunchCommons),

        // 4. DESCRIPTION — every free-text descriptive field together,
        // rather than split between a top-level "snippet" and a buried
        // "Additional Details" entry.
        _buildDescriptionSection(),

        // 5. REUSE — turn Commons' rights metadata into practical credit and
        // embed snippets instead of making people interpret raw fields.
        _sectionHeader('HOW TO USE THIS FILE'),
        _ReuseSection(item: item, onLaunchCommons: onLaunchCommons),

        // 6. DATES — created vs. uploaded, side by side.
        _buildDatesSection(),

        // 7. FILE DETAILS — structural/technical facts plus, lazily,
        // Structured Data on Commons statements (creator/institution/depicts
        // and anything else editors have added as SDC claims).
        _buildMetadataSection(context),

        // 8. RELATED MEDIA — CirrusSearch's own similarity engine
        // (morelike:), for "find me more like this" discovery.
        if (item.hasCoordinates) ...[
          const SizedBox(height: 10),
          _NearbyMediaButton(item: item),
        ],
        _RelatedMediaSection(fileTitle: item.title),

        // 9. GLOBAL USAGE — a real-world "is this used anywhere" signal,
        // the natural last stop after everything the file itself says
        // about itself.
        _GlobalUsageSection(fileTitle: item.title),
      ],
    );
  }

  Widget _buildAuthorSection(BuildContext context) {
    final cleanArtist = _cleanHtml(item.artistHtml);
    if (cleanArtist.isEmpty && item.uploader.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPropertyRow('AUTHOR / CREATOR', cleanArtist),
          _buildUploaderRow(context, item.uploader),
        ],
      ),
    );
  }

  Widget _buildImageQualityControl() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PREVIEW QUALITY',
            style: TextStyle(
              color: Color(0xFF666666),
              fontSize: 10,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          _ImageQualitySelector(
            value: imageQuality!,
            onChanged: onImageQualityChanged!,
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionSection() {
    final snippet = item.snippet.isEmpty ? '' : _cleanHtml(item.snippet);
    final imageDescription = _cleanHtml(item.imageDescriptionHtml);
    final objectName = item.objectName.trim();

    final hasAnyDescription = snippet.isNotEmpty ||
        imageDescription.isNotEmpty ||
        objectName.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('DESCRIPTION'),
          if (!hasAnyDescription)
            const Text(
              'No description provided by the archivist.',
              style: TextStyle(
                color: Color(0xFFB0B0B0),
                fontSize: 14,
                height: 1.6,
              ),
            )
          else ...[
            _buildPropertyRow('OBJECT NAME', objectName),
            _buildPropertyRow('IMAGE DESCRIPTION', imageDescription),
            if (snippet.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: SelectableText(
                  snippet,
                  style: const TextStyle(
                    color: Color(0xFFB0B0B0),
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildDatesSection() {
    final created = item.dateTimeOriginal.trim();
    final uploaded = item.uploadDateTime.trim().isNotEmpty
        ? item.uploadDateTime.trim()
        : (item.timestamp ?? '').trim();

    if (created.isEmpty && uploaded.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('DATES'),
          _buildPropertyRow('CREATED', created),
          _buildPropertyRow('UPLOADED', uploaded),
        ],
      ),
    );
  }

  /// Structural/technical facts and location. Rights and reuse instructions
  /// intentionally live in the dedicated section above instead of being
  /// buried among dimensions and categories.
  Widget _buildMetadataSection(BuildContext context) {
    final dimensions = (item.width > 0 && item.height > 0)
        ? '${item.width} × ${item.height} px'
        : '';
    final coordinates = (item.gpsLatitude.trim().isNotEmpty &&
            item.gpsLongitude.trim().isNotEmpty)
        ? '${item.gpsLatitude}, ${item.gpsLongitude}'
        : '';

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('FILE DETAILS'),
          _buildPropertyRow('FILE TYPE', item.mime.toUpperCase()),
          _buildPropertyRow('EXTENSION', item.extension.toUpperCase()),
          _buildPropertyRow('DIMENSIONS', dimensions),
          _buildPropertyRow('CATEGORIES', item.categories.trim()),
          _buildPropertyRow('ASSESSMENTS', item.assessments.trim()),
          _buildPropertyRow('GPS COORDINATES', coordinates),
          _StructuredDataSection(fileTitle: item.title),
        ],
      ),
    );
  }

  Widget _buildUploaderRow(BuildContext context, String uploader) {
    if (uploader.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'UPLOADER',
            style: TextStyle(
              color: Color(0xFF666666),
              fontSize: 10,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: SelectableText(
                  uploader,
                  style: const TextStyle(
                    color: Color(0xFFE0E0E0),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => context.push(
                  Uri(path: '/author', queryParameters: {'name': uploader})
                      .toString(),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF7AABFF),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.person_search_rounded, size: 15),
                label: const Text('Portfolio',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPropertyRow(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF666666),
              fontSize: 10,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            value,
            style: const TextStyle(
              color: Color(0xFFE0E0E0),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Deep-links into the map's browse mode around this file's coordinates.
/// Named for what geosearch actually returns — every media kind in the
/// File: namespace within range (see SearchService.geosearch's
/// ggsnamespace:'6' with no filetype: clause), not just images — so the
/// label doesn't overpromise "photos" when a document or video could
/// legitimately show up in the results too.
class _NearbyMediaButton extends StatelessWidget {
  final SearchItem item;
  const _NearbyMediaButton({required this.item});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          AnalyticsService.nearbyMediaFromAssetOpened(item.title);
          context.push(
            Uri(path: '/map', queryParameters: {
              'lat': item.resolvedLatitude!.toStringAsFixed(6),
              'lng': item.resolvedLongitude!.toStringAsFixed(6),
              'radiusKm': '10',
            }).toString(),
          );
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF7AABFF),
          side: const BorderSide(color: Color(0xFF2A2A2A)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: const Icon(Icons.travel_explore, size: 16),
        label: const Text('Search All Media Near This File',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// Collapsed-by-default Structured Data on Commons read-back — captions
/// plus every claim (creator, institution, depicts, coordinates of
/// depicted place, and anything else editors have added), lazily fetched
/// via [structuredDataProvider] the same on-expand-only way as
/// [_GlobalUsageSection]. This is what actually backs "depicts" in the
/// panel — SearchItem itself never carries depicts, since that's an SDC
/// statement, not an extmetadata field.
class _LazyMetadataSection extends StatefulWidget {
  final String title;
  final String analyticsName;
  final WidgetBuilder contentBuilder;
  final bool showDivider;
  final double contentGap;
  final EdgeInsetsGeometry padding;

  const _LazyMetadataSection({
    required this.title,
    required this.analyticsName,
    required this.contentBuilder,
    this.showDivider = false,
    this.contentGap = 12,
    this.padding = const EdgeInsets.only(bottom: 16),
  });

  @override
  State<_LazyMetadataSection> createState() => _LazyMetadataSectionState();
}

class _LazyMetadataSectionState extends State<_LazyMetadataSection> {
  bool _expanded = false;

  void _toggle() {
    if (!_expanded) AnalyticsService.sectionExpanded(widget.analyticsName);
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showDivider) ...[
            const Divider(color: Color(0xFF222222)),
            const SizedBox(height: 14),
          ],
          GestureDetector(
            onTap: _toggle,
            child: Row(
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: Color(0xFF666666),
                    fontSize: 10,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 16,
                  color: const Color(0xFF5C5C5C),
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            SizedBox(height: widget.contentGap),
            widget.contentBuilder(context),
          ],
        ],
      ),
    );
  }
}

Widget _metadataLoading() => const SizedBox(
      height: 24,
      width: 24,
      child: CircularProgressIndicator(
        strokeWidth: 1.5,
        color: Color(0xFF3D7EFF),
      ),
    );

Widget _metadataMessage(String message, {bool muted = false}) => Text(
      message,
      style: TextStyle(
        color: muted ? const Color(0xFF888888) : const Color(0xFF666666),
        fontSize: 13,
        height: muted ? 1.5 : null,
      ),
    );

class _StructuredDataSection extends StatelessWidget {
  final String fileTitle;
  const _StructuredDataSection({required this.fileTitle});

  @override
  Widget build(BuildContext context) {
    return _LazyMetadataSection(
      title: 'STRUCTURED DATA (WIKIDATA)',
      analyticsName: 'structured_data',
      contentBuilder: (_) => Consumer(
        builder: (context, ref, _) {
          final sdcAsync = ref.watch(structuredDataProvider(fileTitle));

          return sdcAsync.when(
            loading: _metadataLoading,
            error: (_, __) =>
                _metadataMessage('Could not load structured data.'),
            data: (result) {
              if (result == null || result.statements.isEmpty) {
                return _metadataMessage(
                  'No structured data statements on this file.',
                  muted: true,
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: result.statements.map((statement) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '${statement.propertyLabel}: ',
                            style: const TextStyle(
                              color: Color(0xFF9A9A9A),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(
                            text: statement.valueDisplay,
                            style: const TextStyle(
                              color: Color(0xFFE0E0E0),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          );
        },
      ),
    );
  }
}

/// Collapsed-by-default "find more like this" grid, backed by
/// [morelikeProvider] — CirrusSearch's own `morelike:` similarity engine,
/// the same mechanism the advanced filters drawer exposes as a manual
/// search input, run here as a one-off query against just this file.
/// Fetch only fires on first expand, same contract as every other lazy
/// section in this panel.
class _RelatedMediaSection extends StatelessWidget {
  final String fileTitle;
  const _RelatedMediaSection({required this.fileTitle});

  @override
  Widget build(BuildContext context) {
    return _LazyMetadataSection(
      title: 'RELATED MEDIA',
      analyticsName: 'related_media',
      showDivider: true,
      padding: const EdgeInsets.only(top: 24),
      contentBuilder: (_) => Consumer(
        builder: (context, ref, _) {
          final relatedAsync = ref.watch(morelikeProvider(fileTitle));

          return relatedAsync.when(
            loading: _metadataLoading,
            error: (_, __) => _metadataMessage('Could not load related media.'),
            data: (items) {
              if (items.isEmpty) {
                return _metadataMessage('No related media found.', muted: true);
              }
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 110,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final related = items[index];
                  return Tooltip(
                    message: related.title,
                    child: GestureDetector(
                      onTap: () {
                        AnalyticsService.relatedMediaClicked(
                          fromTitle: fileTitle,
                          toTitle: related.title,
                        );
                        context.push(
                          Uri(
                            path: '/view',
                            queryParameters: {'id': related.title},
                          ).toString(),
                        );
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: ColoredBox(
                          color: const Color(0xFF1A1A1A),
                          child: related.thumb.isNotEmpty
                              ? Image.network(
                                  related.thumb,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.image,
                                    size: 24,
                                    color: Colors.white24,
                                  ),
                                )
                              : const Icon(
                                  Icons.image,
                                  size: 24,
                                  color: Colors.white24,
                                ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// Collapsed-by-default section showing every Wikimedia page (any
/// language, any project) currently embedding this file — see
/// [CommonsBackend.globalUsage] / [globalUsageProvider]. The fetch only
/// fires the first time this is expanded (Riverpod's FutureProvider only
/// runs once something actually watches it), so browsing a results grid
/// or scrolling through the asset viewer never costs an extra request per
/// file — only opening this section does, and only once per file per
/// session.
class _GlobalUsageSection extends StatelessWidget {
  final String fileTitle;
  const _GlobalUsageSection({required this.fileTitle});

  Future<void> _launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _LazyMetadataSection(
      title: 'GLOBAL USAGE',
      analyticsName: 'global_usage',
      showDivider: true,
      contentGap: 14,
      padding: const EdgeInsets.only(top: 24),
      contentBuilder: (_) => Consumer(
        builder: (context, ref, _) {
          final usageAsync = ref.watch(globalUsageProvider(fileTitle));

          return usageAsync.when(
            loading: _metadataLoading,
            error: (_, __) => _metadataMessage('Could not load usage data.'),
            data: (entries) {
              if (entries.isEmpty) {
                return _metadataMessage(
                  'Not currently used on any Wikimedia project.',
                  muted: true,
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: entries.map((entry) {
                  final hasUrl = (entry.url ?? '').trim().isNotEmpty;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      onTap: hasUrl ? () => _launch(entry.url!) : null,
                      child: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: '${entry.wiki}  ',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextSpan(
                              text: entry.title,
                              style: TextStyle(
                                color: hasUrl
                                    ? const Color(0xFF7AABFF)
                                    : const Color(0xFFB0B0B0),
                                fontSize: 13,
                                decoration:
                                    hasUrl ? TextDecoration.underline : null,
                                decorationColor: const Color(0xFF7AABFF),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          );
        },
      ),
    );
  }
}

class _ReuseSection extends StatefulWidget {
  final SearchItem item;
  final VoidCallback onLaunchCommons;

  const _ReuseSection({
    required this.item,
    required this.onLaunchCommons,
  });

  @override
  State<_ReuseSection> createState() => _ReuseSectionState();
}

class _ReuseSectionState extends State<_ReuseSection> {
  static const _reuseGuidanceUrl =
      'https://commons.wikimedia.org/wiki/Commons:Reusing_content_outside_Wikimedia';

  AssetReuseFormat _format = AssetReuseFormat.attribution;

  AssetReuseGuide get _guide => AssetReuseGuide(widget.item);

  String get _formatLabel => switch (_format) {
        AssetReuseFormat.attribution => 'attribution',
        AssetReuseFormat.html => 'HTML embed',
        AssetReuseFormat.wikiText => 'WikiText',
      };

  Future<void> _copy(BuildContext context, String value, String format) async {
    await Clipboard.setData(ClipboardData(text: value));
    AnalyticsService.reuseSnippetCopied(
      title: widget.item.title,
      format: format,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text('${format[0].toUpperCase()}${format.substring(1)} copied.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _launch(String url, String target) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !await canLaunchUrl(uri)) return;
    AnalyticsService.reuseReferenceOpened(
      title: widget.item.title,
      target: target,
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _fact(String label, String value, {bool warning = false}) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color:
                  warning ? const Color(0xFFE7B75C) : const Color(0xFF777777),
              fontSize: 9.5,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          SelectableText(
            value,
            style: TextStyle(
              color:
                  warning ? const Color(0xFFFFD994) : const Color(0xFFD6D6D6),
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final guide = _guide;
    final attributionStatus = guide.attributionRequired;
    final snippet = guide.snippetFor(_format);
    final statusLabel = attributionStatus == true
        ? 'Attribution required'
        : attributionStatus == false
            ? 'Not flagged as required'
            : 'Verify attribution terms';
    final statusIcon = attributionStatus == true
        ? Icons.person_outline
        : attributionStatus == false
            ? Icons.check_circle_outline
            : Icons.help_outline;
    final statusColor = attributionStatus == true
        ? const Color(0xFF7AABFF)
        : attributionStatus == false
            ? const Color(0xFF6ED6A0)
            : const Color(0xFFE7B75C);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF171717),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: const Color(0xFF2A2A2A)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3D7EFF).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.verified_user_outlined,
                        size: 19, color: Color(0xFF7AABFF)),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          guide.licenseName.isEmpty
                              ? 'License information incomplete'
                              : guide.licenseName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Icon(statusIcon, size: 14, color: statusColor),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                statusLabel,
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (!guide.hasCompleteReuseMetadata) ...[
                const SizedBox(height: 12),
                const Text(
                  'Commons did not provide complete machine-readable rights metadata for this file. Check the source page before reuse.',
                  style: TextStyle(
                    color: Color(0xFFFFD994),
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ],
              _fact('CREATOR', guide.creator),
              _fact('PREFERRED CREDIT', guide.creditLine),
              _fact('USAGE TERMS', guide.usageTerms),
              _fact('COPYRIGHT STATUS', guide.copyrightStatus),
              _fact('SPECIAL PERMISSION', guide.permission),
              _fact('RESTRICTIONS', guide.restrictions, warning: true),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'COPY-READY FORMAT',
          style: TextStyle(
            color: Color(0xFF777777),
            fontSize: 9.5,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _ReuseFormatButton(
                label: 'ATTRIBUTION',
                selected: _format == AssetReuseFormat.attribution,
                onTap: () =>
                    setState(() => _format = AssetReuseFormat.attribution),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _ReuseFormatButton(
                label: 'HTML',
                selected: _format == AssetReuseFormat.html,
                onTap: () => setState(() => _format = AssetReuseFormat.html),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _ReuseFormatButton(
                label: 'WIKITEXT',
                selected: _format == AssetReuseFormat.wikiText,
                onTap: () =>
                    setState(() => _format = AssetReuseFormat.wikiText),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(minHeight: 96),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D0D),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: const Color(0xFF292929)),
          ),
          child: SelectableText(
            snippet,
            style: TextStyle(
              color: const Color(0xFFD8D8D8),
              fontSize: 12,
              height: 1.5,
              fontFamily:
                  _format == AssetReuseFormat.attribution ? null : 'monospace',
            ),
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: () => _copy(context, snippet, _formatLabel),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3D7EFF),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          ),
          icon: const Icon(Icons.content_copy, size: 16),
          label: Text('Copy $_formatLabel',
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (guide.sourceUrl.isNotEmpty)
              _ReuseReferenceButton(
                icon: Icons.open_in_new,
                label: 'Source file',
                onTap: () {
                  AnalyticsService.reuseReferenceOpened(
                    title: widget.item.title,
                    target: 'source',
                  );
                  widget.onLaunchCommons();
                },
              ),
            if (guide.licenseUrl.isNotEmpty)
              _ReuseReferenceButton(
                icon: Icons.gavel_outlined,
                label: 'Full license',
                onTap: () => _launch(guide.licenseUrl, 'license'),
              ),
            _ReuseReferenceButton(
              icon: Icons.menu_book_outlined,
              label: 'Reuse guidance',
              onTap: () => _launch(_reuseGuidanceUrl, 'guidance'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Attribution helpers are generated from the file’s Wikimedia metadata. Verify the source page and full license before publishing; this is not legal advice.',
          style: TextStyle(
            color: Color(0xFF777777),
            fontSize: 10.5,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _ReuseFormatButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ReuseFormatButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? const Color(0xFF3D7EFF).withValues(alpha: 0.16)
          : const Color(0xFF1A1A1A),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color:
                  selected ? const Color(0xFF3D7EFF) : const Color(0xFF292929),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF999999),
              fontSize: 9.5,
              letterSpacing: 0.7,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReuseReferenceButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ReuseReferenceButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFB8CFFF),
        side: const BorderSide(color: Color(0xFF303030)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      icon: Icon(icon, size: 14),
      label: Text(label,
          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
    );
  }
}

class _DownloadSection extends StatelessWidget {
  final SearchItem item;
  final VoidCallback onLaunchCommons;

  const _DownloadSection({
    required this.item,
    required this.onLaunchCommons,
  });

  Future<void> _handleDownload(BuildContext context, String url) async {
    AnalyticsService.mediaDownloaded(
      title: item.title,
      size: url == item.url
          ? 'original'
          : url.contains('/640px-')
              ? 'small'
              : url.contains('/1280px-')
                  ? 'medium'
                  : url.contains('/1920px-')
                      ? 'large'
                      : 'original',
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Downloading media...'),
        duration: Duration(seconds: 2),
      ),
    );

    await DownloadService.downloadSingleFile(url, item.title, item.extension);
  }

  String _getResizedUrl(int width) {
    if (item.thumb.isEmpty) return item.url;
    final regExp = RegExp(r'\/(\d+)px-([^/]+)$');
    if (regExp.hasMatch(item.thumb)) {
      return item.thumb.replaceAllMapped(
        regExp,
        (m) => '/${width}px-${m.group(2)}',
      );
    }
    return item.url;
  }

  @override
  Widget build(BuildContext context) {
    final isScalable =
        item.mediaKind == MediaKind.image || item.mediaKind == MediaKind.vector;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: () => _handleDownload(context, item.url),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3D7EFF),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 0,
          ),
          icon: const Icon(Icons.download, size: 18),
          label: const Text(
            'Download Original',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        if (isScalable) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _SizeButton(
                  label: 'SMALL',
                  onTap: () => _handleDownload(context, _getResizedUrl(640)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SizeButton(
                  label: 'MEDIUM',
                  onTap: () => _handleDownload(context, _getResizedUrl(1280)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SizeButton(
                  label: 'LARGE',
                  onTap: () => _handleDownload(context, _getResizedUrl(1920)),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () {
            AnalyticsService.sourcePageOpened(item.title);
            onLaunchCommons();
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFAAAAAA),
            side: const BorderSide(color: Color(0xFF2A2A2A)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text(
            'View Source Page',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _SizeButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SizeButton({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1E1E1E),
        foregroundColor: const Color(0xFFCCCCCC),
        padding: const EdgeInsets.symmetric(vertical: 12),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _NavigationButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _NavigationButton({
    required this.icon,
    required this.onTap,
  });

  @override
  State<_NavigationButton> createState() => _NavigationButtonState();
}

class _NavigationButtonState extends State<_NavigationButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _isHovered
                ? Colors.white.withValues(alpha: 0.15)
                : Colors.black.withValues(alpha: 0.4),
            shape: BoxShape.circle,
            border: Border.all(
              color: _isHovered
                  ? Colors.white.withValues(alpha: 0.3)
                  : Colors.transparent,
            ),
          ),
          child: Icon(
            widget.icon,
            color: _isHovered ? Colors.white : const Color(0xFFCCCCCC),
            size: 20,
          ),
        ),
      ),
    );
  }
}
