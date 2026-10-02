part of 'asset_viewer.dart';

class _NativeMediaRenderer extends StatefulWidget {
  final SearchItem item;

  const _NativeMediaRenderer({required this.item});

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

    return isPdf && !isDjVu && !_isSafariWeb();
  }

  @override
  void initState() {
    super.initState();
    _viewId =
        'media-view-${widget.item.url.hashCode}-${DateTime.now().millisecondsSinceEpoch}';

    final isVideo = widget.item.mediaKind == MediaKind.video;
    final isAudio = widget.item.mediaKind == MediaKind.audio;
    final isImage = widget.item.mediaKind == MediaKind.image ||
        widget.item.mediaKind == MediaKind.vector;
    final shouldRenderPdf = widget.item.mediaKind == MediaKind.document &&
        _shouldRenderPdfInBrowser();

    // PDFs are safe to inline in Chrome/Web, but Safari does not reliably
    // render cross-origin PDFs inside a browser iframe. DjVu remains blocked
    // because the browser fallback is unreliable there.
    if (isVideo || isAudio || isImage || shouldRenderPdf) {
      _isNativeHtml = true;

      ui_web.platformViewRegistry.registerViewFactory(_viewId, (int viewId) {
        if (isImage) {
          return html.ImageElement()
            ..src = widget.item.url
            ..style.width = '100%'
            ..style.height = '100%'
            ..style.objectFit = 'contain'
            ..style.backgroundColor = 'transparent'
            ..style.outline = 'none';
        } else if (isVideo) {
          return html.VideoElement()
            ..src = widget.item.url
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
            ],
          ),
        ),
      ],
    );
  }
}
