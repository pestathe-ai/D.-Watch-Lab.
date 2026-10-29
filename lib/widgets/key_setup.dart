import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/gemini_client.dart';
import '../services/storage.dart';

const keyPageUrl = 'https://aistudio.google.com/apikey';

Future<void> openKeyPage(BuildContext context) async {
  final ok = await launchUrl(Uri.parse(keyPageUrl),
      mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    await Clipboard.setData(const ClipboardData(text: keyPageUrl));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Link copiato: incollalo nel browser')));
    }
  }
}

/// Collegamento guidato della chiave gratuita in 2 tocchi.
class KeySetupCard extends StatefulWidget {
  final Storage storage;
  final VoidCallback onConnected;
  const KeySetupCard(
      {super.key, required this.storage, required this.onConnected});

  @override
  State<KeySetupCard> createState() => _KeySetupCardState();
}

class _KeySetupCardState extends State<KeySetupCard> {
  bool busy = false;
  String? error;

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final key = (data?.text ?? '').trim();
    if (key.isEmpty) {
      setState(() =>
          error = 'Negli appunti non c\'è nulla. Copia prima la chiave.');
      return;
    }
    await connectKey(key);
  }

  Future<void> connectKey(String key) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final models = await GeminiClient(key).resolveModels();
      final old = await widget.storage.loadSettings();
      await widget.storage.saveSettings(Settings(
          apiKey: key, model: models.first, webSearch: old.webSearch));
      HapticFeedback.mediumImpact();
      widget.onConnected();
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt, color: t.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Attiva l\'IA gratuita (1 minuto)',
                      style: t.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _Step(
              n: 1,
              text: 'Apri Google AI Studio, accedi e tocca "Create API key". '
                  'Poi copia la chiave.',
              action: OutlinedButton.icon(
                onPressed: () => openKeyPage(context),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Apri Google AI Studio'),
              ),
            ),
            const SizedBox(height: 14),
            _Step(
              n: 2,
              text: 'Torna qui e incollala.',
              action: FilledButton.icon(
                style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 46)),
                onPressed: busy ? null : _paste,
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.content_paste, size: 18),
                label: Text(busy ? 'Verifico…' : 'Incolla chiave'),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!,
                  style: const TextStyle(color: Color(0xFFE57373))),
            ],
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final String text;
  final Widget action;
  const _Step({required this.n, required this.text, required this.action});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: t.colorScheme.primary.withValues(alpha: 0.15),
          child: Text('$n',
              style: TextStyle(
                  color: t.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text),
              const SizedBox(height: 8),
              action,
            ],
          ),
        ),
      ],
    );
  }
}
