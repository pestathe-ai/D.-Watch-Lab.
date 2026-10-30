import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/alt_client.dart';
import '../services/gemini_client.dart';
import '../services/storage.dart';

/// Riserva IA: chiavi Gemini extra + un servizio alternativo gratuito,
/// usati in automatico quando Gemini raggiunge il limite.
class BackupSetupCard extends StatefulWidget {
  final Storage storage;
  const BackupSetupCard({super.key, required this.storage});

  @override
  State<BackupSetupCard> createState() => _BackupSetupCardState();
}

class _BackupSetupCardState extends State<BackupSetupCard> {
  final keysCtrl = TextEditingController();
  final altKeyCtrl = TextEditingController();
  AltProvider provider = AltProvider.groq;
  String altModel = '';
  bool busy = false;
  String? status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final keys = await widget.storage.loadBackupKeys();
    final alt = await widget.storage.loadAlt();
    if (!mounted) return;
    setState(() {
      keysCtrl.text = keys.join('\n');
      if (alt != null) {
        provider = alt.provider;
        altKeyCtrl.text = alt.key;
        altModel = alt.model;
      }
    });
  }

  @override
  void dispose() {
    keysCtrl.dispose();
    altKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      busy = true;
      status = null;
    });
    final msgs = <String>[];
    try {
      // Chiavi Gemini di riserva: verifico ognuna.
      final keys = keysCtrl.text
          .split(RegExp(r'[\s,;]+'))
          .map((k) => k.trim())
          .where((k) => k.isNotEmpty)
          .toSet()
          .toList();
      final good = <String>[];
      for (var i = 0; i < keys.length; i++) {
        try {
          await GeminiClient(keys[i]).resolveModel();
          good.add(keys[i]);
        } catch (e) {
          msgs.add('✗ Chiave Gemini ${i + 1}: $e');
        }
      }
      await widget.storage.saveBackupKeys(good);
      keysCtrl.text = good.join('\n');
      if (good.isNotEmpty) {
        msgs.add('✓ ${good.length} chiav${good.length == 1 ? 'e' : 'i'} '
            'Gemini di riserva pronte');
      }

      // Servizio alternativo.
      final k = altKeyCtrl.text.trim();
      if (k.isEmpty) {
        await widget.storage.saveAlt(null, '', '');
        altModel = '';
      } else {
        try {
          final m = await AltClient(AltConfig(provider, k, '')).resolveModel();
          await widget.storage.saveAlt(provider, k, m);
          altModel = m;
          msgs.add('✓ ${provider.label} pronto (modello $m)');
        } catch (e) {
          msgs.add('✗ $e');
        }
      }
      HapticFeedback.mediumImpact();
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          status = msgs.isEmpty ? 'Nessuna riserva impostata.' : msgs.join('\n');
        });
      }
    }
  }

  Future<void> _paste(TextEditingController c, {bool append = false}) async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final v = (d?.text ?? '').trim();
    if (v.isEmpty) return;
    setState(() {
      c.text = append && c.text.trim().isNotEmpty ? '${c.text.trim()}\n$v' : v;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = TextStyle(color: t.colorScheme.onSurfaceVariant);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.swap_horiz, color: t.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('Riserva IA (gratis)',
                        style: t.textTheme.titleMedium)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
                'Se Gemini raggiunge il limite gratuito, l\'app passa da sola '
                'alla riserva e continui a valutare.',
                style: muted),
            const SizedBox(height: 16),
            Text('1 · Altre chiavi Gemini', style: t.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
                'Su AI Studio crea un nuovo progetto e una chiave: ogni '
                'progetto ha i suoi limiti. Una chiave per riga.',
                style: muted),
            const SizedBox(height: 8),
            TextField(
              controller: keysCtrl,
              minLines: 1,
              maxLines: 4,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                hintText: 'Chiavi di riserva',
                suffixIcon: IconButton(
                    tooltip: 'Incolla',
                    icon: const Icon(Icons.content_paste),
                    onPressed: () => _paste(keysCtrl, append: true)),
              ),
            ),
            TextButton.icon(
              onPressed: () => launchUrl(
                  Uri.parse('https://aistudio.google.com/apikey'),
                  mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Apri Google AI Studio'),
            ),
            const SizedBox(height: 10),
            Text('2 · Un altro servizio IA', style: t.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
                'Groq è il più veloce e generoso (senza carta di credito). '
                'OpenRouter e Mistral sono alternative.',
                style: muted),
            const SizedBox(height: 8),
            SegmentedButton<AltProvider>(
              segments: [
                for (final p in AltProvider.values)
                  ButtonSegment(
                      value: p,
                      label: FittedBox(
                          fit: BoxFit.scaleDown, child: Text(p.label))),
              ],
              selected: {provider},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() {
                provider = s.first;
                altModel = '';
              }),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: altKeyCtrl,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                hintText: 'Chiave ${provider.label}',
                suffixIcon: IconButton(
                    tooltip: 'Incolla',
                    icon: const Icon(Icons.content_paste),
                    onPressed: () => _paste(altKeyCtrl)),
              ),
            ),
            TextButton.icon(
              onPressed: () => launchUrl(Uri.parse(provider.keysUrl),
                  mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text('Crea chiave ${provider.label}'),
            ),
            if (altModel.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Modello in uso: $altModel', style: muted),
              ),
            FilledButton(
              onPressed: busy ? null : _save,
              child: busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Verifica e salva riserva'),
            ),
            if (status != null) ...[
              const SizedBox(height: 10),
              Text(status!),
            ],
          ],
        ),
      ),
    );
  }
}
