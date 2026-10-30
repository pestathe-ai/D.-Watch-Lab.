import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Mostra un mercato (Chrono24, Subito, eBay…) dentro l'app.
class MarketWebScreen extends StatefulWidget {
  final String title;
  final Uri url;
  const MarketWebScreen({super.key, required this.title, required this.url});

  @override
  State<MarketWebScreen> createState() => _MarketWebScreenState();
}

class _MarketWebScreenState extends State<MarketWebScreen> {
  late final WebViewController controller;
  int progress = 0;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => progress = p);
        },
        onNavigationRequest: (req) {
          // Link a app esterne (intent://, market://…): apri fuori.
          final u = Uri.tryParse(req.url);
          if (u != null && u.scheme != 'https' && u.scheme != 'http') {
            launchUrl(u, mode: LaunchMode.externalApplication)
                .catchError((_) => false);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(widget.url);
  }

  Future<void> _openOutside() async {
    final current = await controller.currentUrl();
    final u = Uri.tryParse(current ?? '') ?? widget.url;
    await launchUrl(u, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await controller.canGoBack()) {
          await controller.goBack();
        } else if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            IconButton(
              tooltip: 'Ricarica',
              icon: const Icon(Icons.refresh),
              onPressed: () => controller.reload(),
            ),
            IconButton(
              tooltip: 'Apri nel browser o nell\'app',
              icon: const Icon(Icons.open_in_new),
              onPressed: _openOutside,
            ),
          ],
          bottom: progress < 100
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: LinearProgressIndicator(
                      value: progress / 100, minHeight: 2),
                )
              : null,
        ),
        body: WebViewWidget(controller: controller),
      ),
    );
  }
}
