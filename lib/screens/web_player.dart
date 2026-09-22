import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../theme/cartoon_style.dart';

/// Full-screen embedded web player for a saved [RadioStationType.web] link
/// (YouTube video/live stream, or any other page with its own player).
/// Only ever pushed on Android/iOS — radio.dart checks `webViewAvailable`
/// before navigating here, since webview_flutter has no desktop backend.
class WebPlayerScreen extends StatefulWidget {
  final String title;
  final String url;
  const WebPlayerScreen({super.key, required this.title, required this.url});

  @override
  State<WebPlayerScreen> createState() => _WebPlayerScreenState();
}

class _WebPlayerScreenState extends State<WebPlayerScreen> {
  late final WebViewController _controller;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onWebResourceError: (_) => setState(() => _loadFailed = true),
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title, style: CartoonStyle.body(Colors.white, size: 16)),
      ),
      body: _loadFailed
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'This page didn\'t load.',
                  textAlign: TextAlign.center,
                  style: CartoonStyle.body(Colors.white70),
                ),
              ),
            )
          : WebViewWidget(controller: _controller),
    );
  }
}
