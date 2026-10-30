import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/ebay_client.dart';
import '../services/storage.dart';

const ebayKeysUrl = 'https://developer.ebay.com/my/keys';

/// Collegamento dei codici eBay (gratuiti) per i prezzi reali.
class EbaySetupCard extends StatefulWidget {
  final Storage storage;
  final VoidCallback? onConnected;
  final bool compact;
  const EbaySetupCard(
      {super.key, required this.storage, this.onConnected, this.compact = false});

  @override
  State<EbaySetupCard> createState() => _EbaySetupCardState();
}

class _EbaySetupCardState extends State<EbaySetupCard> {
  final idCtrl = TextEditingController();
  final secretCtrl = TextEditingController();
  bool busy = false;
  bool connected = false;
  bool obscure = true;
  String? status;

  @override
  void initState() {
    super.initState();
    widget.storage.loadEbay().then((k) {
      if (!mounted) return;
      setState(() {
        idCtrl.text = k.id;
        secretCtrl.text = k.secret;
        connected = k.id.isNotEmpty && k.secret.isNotEmpty;
      });
    });
  }

  @override
  void dispose() {
    idCtrl.dispose();
    secretCtrl.dispose();
    super.dispose();
  }

  Future<void> _paste(TextEditingController c) async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    setState(() => c.text = (d?.text ?? '').trim());
  }

  Future<void> _verify() async {
    final id = idCtrl.text.trim();
    final secret = secretCtrl.text.trim();
    if (id.isEmpty || secret.isEmpty) {
      setState(() => status = 'Servono entrambi i codici.');
      return;
    }
    setState(() {
      busy = true;
      status = null;
    });
    try {
      await EbayClient(id, secret).verify();
      await widget.storage.saveEbay(id, secret);
      HapticFeedback.mediumImpact();
      setState(() {
        connected = true;
        status = '✓ eBay collegato: i prezzi verranno dagli annunci reali.';
      });
      widget.onConnected?.call();
    } catch (e) {
      setState(() => status = '✗ $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _disconnect() async {
    await widget.storage.saveEbay('', '');
    EbayClient.resetToken();
    setState(() {
      idCtrl.clear();
      secretCtrl.clear();
      connected = false;
      status = 'eBay scollegato.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.storefront_outlined, color: t.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Prezzi reali da eBay (gratis)',
                      style: t.textTheme.titleMedium),
                ),
                if (connected)
                  const Icon(Icons.check_circle, color: Color(0xFF6BCB8B)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              connected
                  ? 'Collegato. Ogni valutazione legge gli annunci eBay di '
                      'Italia e Germania e calcola un prezzo ponderato.'
                  : '1. Apri il sito sviluppatori eBay e accedi col tuo account\n'
                      '2. Crea un\'app (keyset "Production")\n'
                      '3. Copia App ID (Client ID) e Cert ID (Client Secret)',
              style: TextStyle(color: t.colorScheme.onSurfaceVariant),
            ),
            if (!connected) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse(ebayKeysUrl),
                    mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Apri eBay Developers'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: idCtrl,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'App ID (Client ID)',
                  suffixIcon: IconButton(
                      tooltip: 'Incolla',
                      icon: const Icon(Icons.content_paste),
                      onPressed: () => _paste(idCtrl)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: secretCtrl,
                obscureText: obscure,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Cert ID (Client Secret)',
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                          icon: Icon(obscure
                              ? Icons.visibility
                              : Icons.visibility_off),
                          onPressed: () => setState(() => obscure = !obscure)),
                      IconButton(
                          tooltip: 'Incolla',
                          icon: const Icon(Icons.content_paste),
                          onPressed: () => _paste(secretCtrl)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: busy ? null : _verify,
                child: busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Collega eBay'),
              ),
            ] else ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                    onPressed: _disconnect, child: const Text('Scollega')),
              ),
            ],
            if (status != null) ...[
              const SizedBox(height: 8),
              Text(status!),
            ],
          ],
        ),
      ),
    );
  }
}
