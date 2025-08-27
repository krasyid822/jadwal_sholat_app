import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'qibla_iframe_registry.dart';

/// QiblaIframeScreen: on web, embeds an <iframe> with the provided URL using
/// HtmlElementView; on other platforms, falls back to QiblaWebViewScreen.
class QiblaIframeScreen extends StatefulWidget {
  final String url;
  final String title;

  const QiblaIframeScreen({
    super.key,
    required this.url,
    this.title = 'Google Qibla Finder',
  });

  @override
  State<QiblaIframeScreen> createState() => _QiblaIframeScreenState();
}

class _QiblaIframeScreenState extends State<QiblaIframeScreen> {
  bool _isRegistered = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) _registerView();
  }

  void _registerView() {
    if (_isRegistered) return;
    // Register a view factory for the iframe using the conditional helper
    final viewType = 'qibla-iframe-${widget.url.hashCode}';
    registerQiblaIFrame(viewType, widget.url);

    setState(() {
      _isRegistered = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      // On native platforms, fall back to the existing WebView screen if available
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(
          child: Text('Unsupported platform for iframe viewer'),
        ),
      );
    }

    final viewType = 'qibla-iframe-${widget.url.hashCode}';

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: HtmlElementView(viewType: viewType),
    );
  }
}
