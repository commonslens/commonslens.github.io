part of 'asset_viewer.dart';

class _NativeMediaRenderer extends StatefulWidget {
  final SearchItem item;
  final String imageUrl;

  const _NativeMediaRenderer({
    super.key,
    required this.item,
    required this.imageUrl,
  });

  @override
  State<_NativeMediaRenderer> createState() => _NativeMediaRendererState();
}

class _NativeMediaRendererState extends State<_NativeMediaRenderer> {
  late final String _viewId;
  bool _isNativeHtml = false;

  bool _isSafariWeb() {
    final userAgent = html.window.navigator.userAgent.toLowerCase();
    final hasSafari = userAgent.contains('safari');
    final hasChromeLike = userAgent.contains('chrome') ||
        userAgent.contains('chromium') ||
        userAgent.contains('crios');
    return hasSafari && !hasChromeLike;
  }

  bool _shouldRenderPdfInBrowser() {
    if (!kIsWeb) return false;

    final isPdf = widget.item.extension.toLowerCase() == 'pdf' ||
        widget.item.mime.toLowerCase() == 'application/pdf';
    final isDjVu = widget.item.extension.toLowerCase() == 'djvu' ||
        widget.item.mime.toLowerCase() == 'image/vnd.djvu';

    return isPdf &&
        !isDjVu &&
        !_isSafariWeb() &&
        _isSafeWikimediaPdfUrl(widget.item.url);
  }

  @override
  void initState() {
    super.initState();
    _viewId =
        'media-view-${widget.imageUrl.hashCode}-${DateTime.now().microsecondsSinceEpoch}';

    final isVideo = widget.item.mediaKind == MediaKind.video;
    final isAudio = widget.item.mediaKind == MediaKind.audio;
    final isImage = widget.item.mediaKind == MediaKind.image ||
        widget.item.mediaKind == MediaKind.vector;
    final shouldRenderStl =
        _isStl(widget.item) && _isSafeWikimediaUploadUrl(widget.item.url);
    final shouldRenderPdf = widget.item.mediaKind == MediaKind.document &&
        _shouldRenderPdfInBrowser();

    // PDFs are only inlined in a restricted iframe on browsers that render
    // them reliably. DjVu remains blocked because the browser fallback is
    // unreliable there. Download verification is a separate boundary.
    if (isVideo || isAudio || isImage || shouldRenderPdf || shouldRenderStl) {
      _isNativeHtml = true;

      ui_web.platformViewRegistry.registerViewFactory(_viewId, (int viewId) {
        if (shouldRenderStl) {
          return html.IFrameElement()
            ..src = _stlViewerUrl(widget.item.url, widget.item.fileSizeBytes)
            ..title = 'Interactive 3D model viewer'
            ..setAttribute('referrerpolicy', 'no-referrer')
            // Keep the viewer's JavaScript in an opaque origin, separate from
            // the main Flutter document. It only needs scripts and network
            // access to the validated Wikimedia model URL.
            ..setAttribute('sandbox', 'allow-scripts')
            ..allow = 'fullscreen'
            ..setAttribute('allowfullscreen', '')
            ..style.width = '100%'
            ..style.height = '100%'
            ..style.border = 'none'
            ..style.backgroundColor = '#070707'
            ..style.outline = 'none';
        } else if (isImage) {
          return html.ImageElement()
            ..src = widget.imageUrl
            ..setAttribute('referrerpolicy', 'no-referrer')
            ..style.width = '100%'
            ..style.height = '100%'
            ..style.objectFit = 'contain'
            ..style.backgroundColor =
                _isSvgAsset(widget.item) ? '#FFFFFF' : 'transparent'
            ..style.outline = 'none';
        } else if (isVideo) {
          return html.VideoElement()
            ..src = widget.item.url
            ..setAttribute('referrerpolicy', 'no-referrer')
            ..controls = true
            ..autoplay = false
            ..style.width = '100%'
            ..style.height = '100%'
            ..style.objectFit = 'contain'
            ..style.backgroundColor = '#070707'
            ..style.outline = 'none';
        } else if (shouldRenderPdf) {
          return html.IFrameElement()
            ..src = widget.item.url
            // Do not add an iframe sandbox here: Chromium blocks its native
            // PDF viewer inside sandboxed frames, including frames that grant
            // allow-scripts or allow-downloads. Safety comes from admitting
            // only exact Wikimedia upload URLs; the browser's native PDF
            // viewer handles the document rather than embedding provider HTML.
            ..setAttribute('referrerpolicy', 'no-referrer')
            ..style.width = '100%'
            ..style.height = '100%'
            ..style.border = 'none'
            ..style.backgroundColor = '#070707'
            ..style.outline = 'none';
        } else {
          // isAudio — the only remaining branch.
          final container = html.DivElement()
            ..style.display = 'flex'
            ..style.alignItems = 'center'
            ..style.justifyContent = 'center'
            ..style.width = '100%'
            ..style.height = '100%';

          final audio = html.AudioElement()
            ..src = widget.item.url
            ..setAttribute('referrerpolicy', 'no-referrer')
            ..controls = true
            ..autoplay = false
            ..style.width = '80%'
            ..style.outline = 'none';

          container.append(audio);
          return container;
        }
      });
    }
  }

  bool _isSvgAsset(SearchItem item) =>
      item.isSvg ||
      item.mediaKind == MediaKind.vector ||
      item.extension.toLowerCase() == 'svg' ||
      item.mime.toLowerCase() == 'image/svg+xml';

  bool _isStl(SearchItem item) =>
      item.extension.toLowerCase() == 'stl' ||
      item.mime.toLowerCase() == 'application/sla';

  bool _isSafeWikimediaUploadUrl(String value) {
    try {
      final uri = DownloadSecurityPolicy.requireTrustedMediaUri(value);
      return DownloadSecurityPolicy.extensionFromUri(uri) == 'stl';
    } on DownloadSecurityException {
      return false;
    }
  }

  bool _isSafeWikimediaPdfUrl(String value) {
    try {
      final uri = DownloadSecurityPolicy.requireTrustedMediaUri(value);
      return DownloadSecurityPolicy.extensionFromUri(uri) == 'pdf';
    } on DownloadSecurityException {
      return false;
    }
  }

  String _stlViewerUrl(String modelUrl, int fileSizeBytes) => Uri(
        path: 'stl_viewer.html',
        queryParameters: {
          'url': modelUrl,
          if (fileSizeBytes > 0) 'size': '$fileSizeBytes',
        },
      ).toString();

  @override
  Widget build(BuildContext context) {
    if (_isNativeHtml) {
      final isDesktop = MediaQuery.of(context).size.width >= 800;
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: isDesktop ? 80.0 : 0.0),
        child: HtmlElementView(viewType: _viewId),
      );
    }

    return _buildFallbackUI(widget.item);
  }

  Widget _buildFallbackUI(SearchItem item) {
    IconData icon;
    String typeLabel;

    if (_isStl(item)) {
      icon = Icons.view_in_ar_outlined;
      typeLabel = '3D MODEL';
    } else {
      switch (item.mediaKind) {
        case MediaKind.vector:
          icon = Icons.polyline_outlined;
          typeLabel = 'VECTOR GRAPHIC';
          break;
        case MediaKind.document:
          icon = Icons.description_outlined;
          typeLabel = 'DOCUMENT (${item.extension.toUpperCase()})';
          break;
        default:
          icon = Icons.insert_drive_file_outlined;
          typeLabel = 'FILE';
      }
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (item.thumb.isNotEmpty) Image.network(item.thumb, fit: BoxFit.cover),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            color: Colors.black.withValues(alpha: 0.65),
          ),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 72, color: Colors.white60),
              const SizedBox(height: 16),
              Text(
                typeLabel,
                style: const TextStyle(
                  color: Color(0xFFAAAAAA),
                  fontSize: 12,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () async {
                  final uri = Uri.parse(item.url);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3D7EFF),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 0,
                ),
                icon: const Icon(Icons.open_in_browser, size: 20),
                label: const Text(
                  'Open Media / Download',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 8),
              const CommonsLensDownloadSecurityButton(),
            ],
          ),
        ),
      ],
    );
  }
}

class _ImageQualitySelector extends StatelessWidget {
  final _ViewerImageQuality value;
  final ValueChanged<_ViewerImageQuality> onChanged;

  const _ImageQualitySelector({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ImageQualityButton(
            label: 'WEB',
            icon: Icons.speed_rounded,
            tooltip: '1920px web-optimized preview',
            selected: value == _ViewerImageQuality.webOptimized,
            onTap: () => onChanged(_ViewerImageQuality.webOptimized),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ImageQualityButton(
            label: 'FULL',
            icon: Icons.hd_outlined,
            tooltip: 'Full-resolution original',
            selected: value == _ViewerImageQuality.fullResolution,
            onTap: () => onChanged(_ViewerImageQuality.fullResolution),
          ),
        ),
      ],
    );
  }
}

class _ImageQualityButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  const _ImageQualityButton({
    required this.label,
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: ElevatedButton.icon(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor:
              selected ? const Color(0xFF3D7EFF) : const Color(0xFF1E1E1E),
          foregroundColor: selected ? Colors.white : const Color(0xFFCCCCCC),
          padding: const EdgeInsets.symmetric(vertical: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        icon: Icon(icon, size: 16),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}
