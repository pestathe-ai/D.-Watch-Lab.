import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/appraisal_runner.dart';
import '../services/prompt.dart';
import '../services/storage.dart';
import 'result_screen.dart';

class CaptureScreen extends StatefulWidget {
  final Storage storage;
  final VoidCallback onSaved;
  final VoidCallback openSettings;
  const CaptureScreen({
    super.key,
    required this.storage,
    required this.onSaved,
    required this.openSettings,
  });

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final picker = ImagePicker();
  final photos = <String, File>{};
  final extraCtrl = TextEditingController();
  bool box = false;
  bool papers = false;
  bool busy = false;

  Future<void> _pick(PhotoSlot slot) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(slot.label,
                  style: Theme.of(ctx).textTheme.titleMedium),
              subtitle: Text(slot.hint),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Scatta una foto'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Scegli dalla galleria'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            if (photos.containsKey(slot.key))
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Rimuovi foto'),
                onTap: () {
                  setState(() => photos.remove(slot.key));
                  Navigator.pop(ctx);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final x = await picker.pickImage(
        source: source,
        maxWidth: 1800,
        maxHeight: 1800,
        imageQuality: 88,
      );
      if (x != null) setState(() => photos[slot.key] = File(x.path));
    } catch (e) {
      _snack('Impossibile aprire la fotocamera o la galleria: $e');
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _appraise() async {
    if (!photos.containsKey('dial')) {
      _snack('Serve almeno la foto del quadrante.');
      return;
    }
    final slots = photoSlots.where((s) => photos.containsKey(s.key)).toList();
    final files = slots.map((s) => photos[s.key]!).toList();
    final labels = slots.map((s) => '${s.label} (${s.hint})').toList();
    setState(() => busy = true);
    try {
      final result = await runAppraisal(
        storage: widget.storage,
        photos: files,
        labels: labels,
        extraInfo: extraCtrl.text,
        box: box,
        papers: papers,
      );
      if (!mounted) return;
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            storage: widget.storage,
            appraisal: result,
            photos: files,
            labels: labels,
            box: box,
            papers: papers,
            extraInfo: extraCtrl.text,
          ),
        ),
      );
      if (saved == true) {
        widget.onSaved();
        setState(() {
          photos.clear();
          extraCtrl.clear();
          box = false;
          papers = false;
        });
      }
    } on MissingKeyException {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Manca la chiave gratuita'),
          content: const Text(
              'Per analizzare le foto serve una chiave Google Gemini gratuita. '
              'Ci vuole un minuto: vai nelle Impostazioni.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Dopo')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () {
                Navigator.pop(ctx);
                widget.openSettings();
              },
              child: const Text('Impostazioni'),
            ),
          ],
        ),
      );
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final count = photos.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('D. Watch Lab'),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
            children: [
              Text('Quanto vale il tuo orologio?',
                  style: t.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(
                'Il quadrante basta per iniziare. Ogni foto in più '
                '(fondello, anse, fibbia) rende la stima più precisa.',
                style: t.textTheme.bodyMedium
                    ?.copyWith(color: t.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.82,
                children: [
                  for (final s in photoSlots)
                    _SlotTile(
                        slot: s, file: photos[s.key], onTap: () => _pick(s)),
                ],
              ),
              const SizedBox(height: 10),
              _PrecisionMeter(count: count),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('Scatola originale'),
                    selected: box,
                    onSelected: (v) => setState(() => box = v),
                  ),
                  FilterChip(
                    label: const Text('Garanzia / documenti'),
                    selected: papers,
                    onSelected: (v) => setState(() => papers = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: extraCtrl,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText:
                      'Info utili (opzionale): anno di acquisto, revisioni, '
                      'referenza se la conosci…',
                ),
              ),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: FilledButton.icon(
              onPressed: busy ? null : _appraise,
              icon: const Icon(Icons.auto_awesome),
              label: Text(count == 0
                  ? 'Aggiungi la foto del quadrante'
                  : 'Valuta ($count ${count == 1 ? 'foto' : 'foto'})'),
            ),
          ),
          if (busy) const _BusyOverlay(),
        ],
      ),
    );
  }
}

class _SlotTile extends StatelessWidget {
  final PhotoSlot slot;
  final File? file;
  final VoidCallback onTap;
  const _SlotTile({required this.slot, required this.file, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: t.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: file != null
                ? t.colorScheme.primary
                : (slot.required
                    ? t.colorScheme.primary.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.08)),
            width: file != null ? 2 : 1,
          ),
          image: file != null
              ? DecorationImage(image: FileImage(file!), fit: BoxFit.cover)
              : null,
        ),
        child: file != null
            ? Align(
                alignment: Alignment.bottomLeft,
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(12)),
                  ),
                  child: Text(slot.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12)),
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo_outlined,
                        color: slot.required
                            ? t.colorScheme.primary
                            : t.colorScheme.onSurfaceVariant),
                    const SizedBox(height: 6),
                    Text(slot.label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                    if (slot.required)
                      Text('obbligatoria',
                          style: TextStyle(
                              fontSize: 10, color: t.colorScheme.primary)),
                  ],
                ),
              ),
      ),
    );
  }
}

class _PrecisionMeter extends StatelessWidget {
  final int count;
  const _PrecisionMeter({required this.count});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final level = count == 0
        ? 0.0
        : count == 1
            ? 0.35
            : count == 2
                ? 0.6
                : count == 3
                    ? 0.8
                    : 1.0;
    final label = count == 0
        ? 'Nessuna foto'
        : count == 1
            ? 'Precisione base'
            : count <= 3
                ? 'Precisione buona'
                : 'Precisione massima';
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: level,
              minHeight: 6,
              backgroundColor: t.colorScheme.surfaceContainerHigh,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(label, style: t.textTheme.bodySmall),
      ],
    );
  }
}

class _BusyOverlay extends StatefulWidget {
  const _BusyOverlay();

  @override
  State<_BusyOverlay> createState() => _BusyOverlayState();
}

class _BusyOverlayState extends State<_BusyOverlay> {
  static const steps = [
    'Leggo quadrante e incisioni…',
    'Identifico marca e referenza…',
    'Cerco prezzi di vendita reali…',
    'Controllo i dettagli sospetti…',
    'Calcolo la forbice di prezzo…',
  ];
  int i = 0;
  bool alive = true;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  Future<void> _tick() async {
    while (alive) {
      await Future<void>.delayed(const Duration(seconds: 4));
      if (!alive || !mounted) return;
      setState(() => i = (i + 1) % steps.length);
    }
  }

  @override
  void dispose() {
    alive = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.75),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(steps[i],
                      key: ValueKey(i),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 8),
                const Text('Può richiedere fino a un minuto',
                    style: TextStyle(fontSize: 12, color: Colors.white60)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
