import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/appraisal.dart';
import '../services/appraisal_runner.dart';
import '../services/ebay_client.dart';
import '../services/gemini_client.dart';
import '../services/storage.dart';

/// Apre la schermata di analisi e restituisce il risultato (o null).
Future<WatchAppraisal?> analyze(
  BuildContext context, {
  required Storage storage,
  required List<File> photos,
  required List<String> labels,
  String extraInfo = '',
  bool box = false,
  bool papers = false,
}) {
  return Navigator.of(context).push<WatchAppraisal>(PageRouteBuilder(
    transitionDuration: const Duration(milliseconds: 350),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (_, __, ___) => AnalyzeScreen(
      storage: storage,
      photos: photos,
      labels: labels,
      extraInfo: extraInfo,
      box: box,
      papers: papers,
    ),
    transitionsBuilder: (_, anim, __, child) =>
        FadeTransition(opacity: anim, child: child),
  ));
}

class AnalyzeScreen extends StatefulWidget {
  final Storage storage;
  final List<File> photos;
  final List<String> labels;
  final String extraInfo;
  final bool box;
  final bool papers;

  const AnalyzeScreen({
    super.key,
    required this.storage,
    required this.photos,
    required this.labels,
    this.extraInfo = '',
    this.box = false,
    this.papers = false,
  });

  @override
  State<AnalyzeScreen> createState() => _AnalyzeScreenState();
}

class _AnalyzeScreenState extends State<AnalyzeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController scan = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800))
    ..repeat(reverse: true);

  static const steps = [
    'Leggo quadrante e scritte…',
    'Riconosco marca e modello…',
    'Cerco la referenza esatta…',
    'Preparo la ricerca dei prezzi…',
    'Controllo i dettagli sospetti…',
    'Calcolo il valore…',
  ];
  int step = 0;
  String? statusOverride;
  String? error;
  Timer? timer;
  int run = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    final myRun = ++run;
    setState(() {
      error = null;
      statusOverride = null;
      step = 0;
    });
    timer?.cancel();
    timer = Timer.periodic(const Duration(milliseconds: 2600), (_) {
      if (mounted && step < steps.length - 1) setState(() => step++);
    });
    scan.repeat(reverse: true);
    _work(myRun);
  }

  Future<void> _work(int myRun) async {
    void status(String s) {
      if (mounted && myRun == run) setState(() => statusOverride = s);
    }

    try {
      final ai = await runAppraisal(
        storage: widget.storage,
        photos: widget.photos,
        labels: widget.labels,
        extraInfo: widget.extraInfo,
        box: widget.box,
        papers: widget.papers,
        onStatus: status,
      );
      if (!mounted || myRun != run) return;
      final (r, warn) =
          await addMarketPrice(widget.storage, ai, onStatus: status);
      if (!mounted || myRun != run) return;
      if (warn != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(warn)));
      }
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(r);
    } catch (e) {
      if (!mounted || myRun != run) return;
      timer?.cancel();
      scan.stop();
      HapticFeedback.heavyImpact();
      setState(() => error = e is MissingKeyException
          ? 'Manca la chiave gratuita di Google. Collegala nella schermata '
              'principale o nelle Impostazioni.'
          : (e is GeminiException || e is EbayException)
              ? e.toString()
              : 'Qualcosa è andato storto. Controlla la connessione e '
                  'riprova.\n\n($e)');
    }
  }

  @override
  void dispose() {
    run++;
    timer?.cancel();
    scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final gold = t.colorScheme.primary;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Hero(
            tag: widget.photos.first.path,
            child: Image.file(widget.photos.first,
                fit: BoxFit.cover,
                color: Colors.black.withValues(alpha: 0.35),
                colorBlendMode: BlendMode.darken),
          ),
          if (error == null)
            AnimatedBuilder(
              animation: scan,
              builder: (_, __) => LayoutBuilder(builder: (_, c) {
                final top = c.maxHeight * (0.15 + 0.55 * scan.value);
                return Stack(children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: top,
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(boxShadow: [
                        BoxShadow(
                            color: gold.withValues(alpha: 0.8),
                            blurRadius: 24,
                            spreadRadius: 4),
                      ], color: gold),
                    ),
                  ),
                ]);
              }),
            ),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const Spacer(),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: error == null ? _progress(t) : _errorPanel(t),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _progress(ThemeData t) {
    final text = statusOverride ?? steps[step];
    return Container(
      key: const ValueKey('progress'),
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: t.colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                    position: Tween(
                            begin: const Offset(0, 0.3), end: Offset.zero)
                        .animate(a),
                    child: c)),
            child: Text(text,
                key: ValueKey(text),
                textAlign: TextAlign.center,
                style: t.textTheme.titleMedium),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: (step + 1) / (steps.length + 1)),
              duration: const Duration(milliseconds: 600),
              builder: (_, v, __) => LinearProgressIndicator(
                value: v,
                minHeight: 5,
                backgroundColor: t.colorScheme.surfaceContainerHigh,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text('Di solito 10–30 secondi',
              style: t.textTheme.bodySmall
                  ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _errorPanel(ThemeData t) {
    return Container(
      key: const ValueKey('error'),
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined, size: 40, color: t.colorScheme.primary),
          const SizedBox(height: 10),
          Text('Valutazione non riuscita', style: t.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.refresh),
            label: const Text('Riprova'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Indietro'),
          ),
        ],
      ),
    );
  }
}
