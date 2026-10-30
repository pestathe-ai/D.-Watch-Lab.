import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/gemini_client.dart';
import '../services/storage.dart';
import '../widgets/ebay_setup.dart';
import '../widgets/key_setup.dart';

class SettingsScreen extends StatefulWidget {
  final Storage storage;
  final ValueChanged<bool>? onKeyChanged;
  const SettingsScreen({super.key, required this.storage, this.onKeyChanged});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final keyCtrl = TextEditingController();
  final modelCtrl = TextEditingController();
  bool webSearch = false;
  bool fastMode = true;
  bool obscure = true;
  bool busy = false;
  String? status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await widget.storage.loadSettings();
    final fast = await widget.storage.loadFastMode();
    if (!mounted) return;
    fastMode = fast;
    setState(() {
      keyCtrl.text = s.apiKey;
      modelCtrl.text = s.model;
      webSearch = s.webSearch;
    });
  }

  Future<void> _save({bool quiet = false}) async {
    await widget.storage.saveSettings(Settings(
        apiKey: keyCtrl.text, model: modelCtrl.text, webSearch: webSearch));
    widget.onKeyChanged?.call(keyCtrl.text.trim().isNotEmpty);
    if (!quiet && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Impostazioni salvate')));
    }
  }

  Future<void> _test() async {
    if (keyCtrl.text.trim().isEmpty) {
      setState(() => status = 'Incolla prima la chiave.');
      return;
    }
    setState(() {
      busy = true;
      status = null;
    });
    try {
      final model = await GeminiClient(keyCtrl.text.trim()).resolveModel();
      modelCtrl.text = model;
      await _save(quiet: true);
      setState(() => status = '✓ Chiave valida. Modello: $model');
    } catch (e) {
      setState(() => status = '✗ $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Impostazioni')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Chiave Google Gemini (gratuita)',
                      style: t.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text(
                    '1. Apri aistudio.google.com/apikey e accedi con Google\n'
                    '2. Tocca "Create API key" e copiala\n'
                    '3. Incollala qui sotto e tocca "Verifica"',
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => openKeyPage(context),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Apri Google AI Studio'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: keyCtrl,
                    onChanged: (_) => setState(() {}),
                    obscureText: obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      hintText: 'Incolla la chiave API',
                      suffixIcon: keyCtrl.text.isEmpty
                          ? IconButton(
                              tooltip: 'Incolla',
                              icon: const Icon(Icons.content_paste),
                              onPressed: () async {
                                final d = await Clipboard.getData(
                                    Clipboard.kTextPlain);
                                setState(() =>
                                    keyCtrl.text = (d?.text ?? '').trim());
                              },
                            )
                          : IconButton(
                        icon: Icon(
                            obscure ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => obscure = !obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: busy ? null : _test,
                    child: busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Verifica e salva'),
                  ),
                  if (status != null) ...[
                    const SizedBox(height: 10),
                    Text(status!),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          EbaySetupCard(storage: widget.storage),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Modalità veloce'),
                  subtitle: const Text(
                      'Riconosce l\'orologio con il modello IA più rapido e '
                      'mostra subito il prezzo eBay; i dettagli arrivano dopo. '
                      'Spenta: riconoscimento con il modello più preciso.'),
                  value: fastMode,
                  onChanged: (v) {
                    setState(() => fastMode = v);
                    widget.storage.saveFastMode(v);
                  },
                ),
                SwitchListTile(
                  title: const Text('Prezzi reali dal web'),
                  subtitle: const Text(
                      'L\'IA cerca su Google prezzi recenti di esemplari '
                      'venduti. Richiede il piano a pagamento di Gemini: con '
                      'la chiave gratuita lascialo spento.'),
                  value: webSearch,
                  onChanged: (v) {
                    setState(() => webSearch = v);
                    _save(quiet: true);
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: TextField(
                    controller: modelCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Modello (automatico)',
                      helperText:
                          'Lascia vuoto: viene scelto il migliore disponibile',
                    ),
                    onSubmitted: (_) => _save(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Le foto vengono inviate a Google per l\'analisi. Con il piano '
            'gratuito Google può usarle per migliorare i suoi modelli. '
            'La stima è indicativa e non sostituisce un perito o '
            'un\'autenticazione.',
            style: t.textTheme.bodySmall
                ?.copyWith(color: t.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
