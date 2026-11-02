import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'commons_backend.dart';

/// Loads a Wikimedia-hosted image through the shared HTTP transport.
///
/// Flutter's built-in [Image.network] lets the browser fetch bytes outside the
/// app transport, which means its response status cannot be recorded. This
/// widget keeps thumbnails on the same transport as the API calls, then hands
/// the returned bytes to Flutter's normal image decoder.
class WikimediaNetworkImage extends StatefulWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final int? cacheWidth;
  final int? cacheHeight;
  final FilterQuality filterQuality;
  final WikimediaRequestCategory category;
  final ImageErrorWidgetBuilder? errorBuilder;
  final Widget Function(BuildContext, Widget, ImageChunkEvent?)? loadingBuilder;

  const WikimediaNetworkImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.cacheWidth,
    this.cacheHeight,
    this.filterQuality = FilterQuality.low,
    this.category = WikimediaRequestCategory.thumbnail,
    this.errorBuilder,
    this.loadingBuilder,
  });

  @override
  State<WikimediaNetworkImage> createState() => _WikimediaNetworkImageState();
}

class _WikimediaNetworkImageState extends State<WikimediaNetworkImage> {
  late Future<Uint8List> _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = _load(widget.url, widget.category);
  }

  @override
  void didUpdateWidget(covariant WikimediaNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.category != widget.category) {
      _bytes = _load(widget.url, widget.category);
    }
  }

  Future<Uint8List> _load(
    String rawUrl,
    WikimediaRequestCategory category,
  ) async {
    final uri = DownloadSecurityPolicy.requireTrustedMediaUri(rawUrl);
    final response = await WikimediaRequestLoggerTransport.get(
      uri,
      category: category,
    );
    if (response.statusCode != 200) {
      throw StateError('HTTP ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return widget.errorBuilder?.call(
                context,
                snapshot.error!,
                snapshot.stackTrace ?? StackTrace.current,
              ) ??
              const SizedBox.shrink();
        }
        if (!snapshot.hasData) {
          return widget.loadingBuilder?.call(
                context,
                const SizedBox.shrink(),
                null,
              ) ??
              const SizedBox.shrink();
        }

        return Image.memory(
          snapshot.data!,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          cacheWidth: widget.cacheWidth,
          cacheHeight: widget.cacheHeight,
          filterQuality: widget.filterQuality,
          errorBuilder: widget.errorBuilder,
        );
      },
    );
  }
}

/// App-local façade kept separate from the widget state so every thumbnail
/// uses the same gated transport and therefore the same request logger.
class WikimediaRequestLoggerTransport {
  WikimediaRequestLoggerTransport._();

  static final _transport = GatedWikimediaTransport();

  static Future<http.Response> get(
    Uri uri, {
    required WikimediaRequestCategory category,
  }) {
    return _transport.get(
      uri,
      timeout: const Duration(seconds: 30),
      maxAttempts: 1,
      category: category,
    );
  }
}
