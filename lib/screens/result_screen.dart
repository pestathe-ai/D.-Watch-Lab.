import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/appraisal.dart';
import '../services/appraisal_runner.dart';
import '../services/storage.dart';

class ResultScreen extends StatefulWidget {
  final Storage storage;
  final WatchAppraisal appraisal;
  final List<File> photos;
  final List<String> labels;
  final bool box;
  final bool papers;
  final String extraInfo;

  /// Presente se l'orologio è già in collezione.
  final SavedValuation? saved;

  const ResultScreen({
    super.key,
    required this.storage,
    required this.appraisal,
    required this.photos,
    required this.labels,
    this.box = false,
    this.papers = false,
    this.extraInfo = '',
    this.saved,
  });

  factory ResultScreen.fromSaved(Storage storage, SavedValuation v) =>
      ResultScreen(
        storage: storage,
        appraisal: v.appraisal,
        photos: v.photoPaths.map(File.new).toList(),
        labels: v.photoLabels.length == v.photoPaths.length
            ? v.photoLabels
            : List.filled(v.photoPaths.length, 'Foto'),
        box: v.box,
        papers: v.papers,
        extraInfo: v.extraInfo,
        saved: v,
      );

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late WatchAppraisal a = widget.appraisal;
  late SavedValuation? saved = widget.saved;
  bool busy = false;
  bool changed = false;

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      saved = await widget.storage.add(a, widget.photos,
          labels: widget.labels,
          box: widget.box,
          papers: widget.papers,
          extraInfo: widget.extraInfo);
      changed = true;
      _snack('Aggiunto alla collezione');
    } catch (e) {
      _snack('Errore nel salvataggio: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _revalue() async {
    final s = saved;
    if (s == null) return;
    setState(() => busy = true);
    try {
      final fresh = await runAppraisal(
        storage: widget.storage,
        photos: widget.photos,
        labels: widget.labels,
        extraInfo: widget.extraInfo,
        box: widget.box,
        papers: widget.papers,
      );
      final v = await widget.storage.add(fresh, widget.photos,
          replaceId: s.id,
          labels: widget.labels,
          box: widget.box,
          papers: widget.papers,
          extraInfo: widget.extraInfo);
      setState(() {
        a = fresh;
        saved = v;
        changed = true;
      });
      _snack('Valore aggiornato');
    } on MissingKeyException {
      _snack('Aggiungi la chiave gratuita nelle Impostazioni.');
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _delete() async {
    final s = saved;
    if (s == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminare questo orologio?'),
        content: const Text('Verranno cancellate anche le sue foto.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Elimina')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.storage.delete(s.id);
    if (mounted) Navigator.pop(context, true);
  }

  void _copyListing() {
    Clipboard.setData(
        ClipboardData(text: a.listingText(box: widget.box, papers: widget.papers)));
    _snack('Testo annuncio copiato');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(saved != null ? 'Il tuo orologio' : 'Valutazione'),
          actions: [
            if (saved != null)
              IconButton(
                  tooltip: 'Elimina',
                  onPressed: busy ? null : _delete,
                  icon: const Icon(Icons.delete_outline)),
          ],
        ),
        body: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
              children: [
                _Gallery(photos: widget.photos, labels: widget.labels),
                const SizedBox(height: 16),
                if (!a.isWatch)
                  _InfoCard(
                    icon: Icons.help_outline,
                    title: 'Non vedo un orologio',
                    body: 'Riprova con una foto frontale e nitida del '
                        'quadrante, ben illuminata e senza riflessi.',
                  )
                else ...[
                  _Header(a: a),
                  const SizedBox(height: 14),
                  _PriceCard(a: a),
                  if (a.alternatives.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _AlternativesCard(a: a),
                  ],
                  const SizedBox(height: 14),
                  _DetailsCard(a: a, box: widget.box, papers: widget.papers),
                  const SizedBox(height: 14),
                  _FlagsCard(a: a),
                  if (a.morePhotos.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _InfoCard(
                      icon: Icons.add_a_photo_outlined,
                      title: 'Per una stima più precisa',
                      body: a.morePhotos.map((e) => '• $e').join('\n'),
                    ),
                  ],
                  if (saved != null && saved!.timeline.length > 1) ...[
                    const SizedBox(height: 14),
                    _HistoryCard(points: saved!.timeline, currency: a.currency),
                  ],
                  if (a.comparables.isNotEmpty || a.sources.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _SourcesCard(a: a),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    'Stima indicativa generata dall\'IA, non è una perizia né '
                    'un\'autenticazione. Per orologi di valore rivolgiti a un '
                    'rivenditore autorizzato o a un perito.',
                    style: t.textTheme.bodySmall
                        ?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Row(
                children: [
                  if (a.isWatch)
                    IconButton.filledTonal(
                      tooltip: 'Copia testo annuncio',
                      onPressed: _copyListing,
                      icon: const Icon(Icons.sell_outlined),
                      style: IconButton.styleFrom(
                          minimumSize: const Size(54, 54)),
                    ),
                  if (a.isWatch) const SizedBox(width: 10),
                  Expanded(
                    child: saved == null
                        ? FilledButton.icon(
                            onPressed: busy || !a.isWatch ? null : _save,
                            icon: const Icon(Icons.add),
                            label: const Text('Aggiungi alla collezione'),
                          )
                        : FilledButton.icon(
                            onPressed: busy ? null : _revalue,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Aggiorna il valore'),
                          ),
                  ),
                ],
              ),
            ),
            if (busy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Colors.black54,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Gallery extends StatelessWidget {
  final List<File> photos;
  final List<String> labels;
  const _Gallery({required this.photos, required this.labels});

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 240,
      child: PageView.builder(
        controller: PageController(viewportFraction: 0.86),
        itemCount: photos.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(right: 10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(photos[i],
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const ColoredBox(
                        color: Colors.black26,
                        child: Icon(Icons.broken_image_outlined))),
                Positioned(
                  left: 10,
                  bottom: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      labels.length > i
                          ? labels[i].split(' (').first
                          : 'Foto ${i + 1}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Color confidenceColor(int c) => c >= 75
    ? const Color(0xFF6BCB8B)
    : c >= 45
        ? const Color(0xFFE8C468)
        : const Color(0xFFE57373);

class _Header extends StatelessWidget {
  final WatchAppraisal a;
  const _Header({required this.a});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = confidenceColor(a.confidence);
    final level = a.confidence >= 75
        ? 'alta'
        : a.confidence >= 45
            ? 'media'
            : 'bassa';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (a.brand.isNotEmpty)
          Text(a.brand.toUpperCase(),
              style: t.textTheme.labelLarge?.copyWith(
                  color: t.colorScheme.primary, letterSpacing: 2)),
        Text(a.model.isEmpty ? a.title : a.model,
            style: t.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        if (a.reference != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('Ref. ${a.reference}',
                style: t.textTheme.bodyLarge
                    ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.verified_outlined, size: 18, color: c),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Identificazione: certezza $level (${a.confidence}%)',
                style: TextStyle(color: c, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PriceCard extends StatelessWidget {
  final WatchAppraisal a;
  const _PriceCard({required this.a});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final hasRange = a.priceLow != null && a.priceHigh != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Valore di mercato stimato (usato)',
                style: t.textTheme.labelLarge
                    ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(formatMoney(a.priceLikely, a.currency),
                  style: t.textTheme.displaySmall?.copyWith(
                      color: t.colorScheme.primary,
                      fontWeight: FontWeight.w700)),
            ),
            if (hasRange) ...[
              const SizedBox(height: 14),
              _RangeBar(
                  low: a.priceLow!, high: a.priceHigh!, likely: a.priceLikely),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(formatMoney(a.priceLow, a.currency),
                      style: t.textTheme.bodySmall),
                  Text(formatMoney(a.priceHigh, a.currency),
                      style: t.textTheme.bodySmall),
                ],
              ),
            ],
            if (a.retailNew != null) ...[
              const SizedBox(height: 10),
              Text('Prezzo del nuovo: ${formatMoney(a.retailNew, a.currency)}',
                  style: t.textTheme.bodyMedium),
            ],
            if (a.priceRationale.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(a.priceRationale,
                  style: t.textTheme.bodyMedium
                      ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}

class _RangeBar extends StatelessWidget {
  final double low;
  final double high;
  final double? likely;
  const _RangeBar({required this.low, required this.high, this.likely});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final span = (high - low).abs();
    final pos = (likely == null || span == 0)
        ? 0.5
        : ((likely! - low) / span).clamp(0.0, 1.0);
    return LayoutBuilder(builder: (_, c) {
      final w = c.maxWidth;
      return SizedBox(
        height: 16,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 5,
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  gradient: LinearGradient(colors: [
                    t.colorScheme.primary.withValues(alpha: 0.25),
                    t.colorScheme.primary,
                    t.colorScheme.primary.withValues(alpha: 0.25),
                  ]),
                ),
              ),
            ),
            Positioned(
              left: (w * pos - 8).clamp(0.0, w - 16),
              top: 0,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: t.colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: t.colorScheme.surface, width: 3),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _AlternativesCard extends StatelessWidget {
  final WatchAppraisal a;
  const _AlternativesCard({required this.a});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Potrebbe anche essere', style: t.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final alt in a.alternatives)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(alt.name)),
                    if (alt.probability > 0)
                      Text('${alt.probability}%',
                          style: TextStyle(
                              color: t.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  final WatchAppraisal a;
  final bool box;
  final bool papers;
  const _DetailsCard(
      {required this.a, required this.box, required this.papers});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final rows = <(String, String?)>[
      ('Calibro', a.caliber),
      ('Periodo', a.era),
      ('Cassa', a.caseMaterial),
      ('Quadrante', a.dial),
      ('Condizioni', a.condition),
      ('Corredo', box && papers
          ? 'Full set (scatola e documenti)'
          : box
              ? 'Solo scatola'
              : papers
                  ? 'Solo documenti'
                  : 'Solo orologio'),
    ].where((r) => r.$2 != null && r.$2!.isNotEmpty).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Dettagli', style: t.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(r.$1,
                          style: TextStyle(
                              color: t.colorScheme.onSurfaceVariant)),
                    ),
                    Expanded(child: Text(r.$2!)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FlagsCard extends StatelessWidget {
  final WatchAppraisal a;
  const _FlagsCard({required this.a});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    Color col(String s) => s == 'alta'
        ? const Color(0xFFE57373)
        : s == 'media'
            ? const Color(0xFFE8C468)
            : t.colorScheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                    a.redFlags.isEmpty
                        ? Icons.shield_outlined
                        : Icons.warning_amber_rounded,
                    color: a.redFlags.isEmpty
                        ? const Color(0xFF6BCB8B)
                        : col(a.redFlags.first.severity)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      a.redFlags.isEmpty
                          ? 'Nessun segnale sospetto evidente'
                          : 'Segnali da verificare (${a.redFlags.length})',
                      style: t.textTheme.titleMedium),
                ),
              ],
            ),
            for (final f in a.redFlags)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 5, right: 10),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: col(f.severity), shape: BoxShape.circle),
                    ),
                    Expanded(child: Text(f.description)),
                  ],
                ),
              ),
            if (a.authenticityNote.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(a.authenticityNote,
                  style: t.textTheme.bodyMedium
                      ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final List<PricePoint> points;
  final String currency;
  const _HistoryCard({required this.points, required this.currency});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final first = points.first.value;
    final last = points.last.value;
    final diff = last - first;
    final pct = first == 0 ? 0 : (diff / first * 100);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Andamento del valore', style: t.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '${diff >= 0 ? '+' : ''}${formatMoney(diff, currency)} '
              '(${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%) '
              'dalla prima valutazione',
              style: TextStyle(
                  color: diff >= 0
                      ? const Color(0xFF6BCB8B)
                      : const Color(0xFFE57373)),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 90,
              width: double.infinity,
              child: CustomPaint(
                  painter: SparklinePainter(
                      points.map((p) => p.value).toList(),
                      t.colorScheme.primary)),
            ),
          ],
        ),
      ),
    );
  }
}

class SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  SparklinePainter(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final span = (maxV - minV) == 0 ? 1 : (maxV - minV);
    Offset pt(int i) => Offset(
          size.width * i / (values.length - 1),
          size.height - 6 - (values[i] - minV) / span * (size.height - 12),
        );
    final path = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(pt(i).dx, pt(i).dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round);
    for (var i = 0; i < values.length; i++) {
      canvas.drawCircle(pt(i), 3.5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant SparklinePainter old) =>
      old.values != values || old.color != color;
}

class _SourcesCard extends StatelessWidget {
  final WatchAppraisal a;
  const _SourcesCard({required this.a});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Theme(
        data: t.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: const Text('Prezzi di confronto e fonti'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final c in a.comparables)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('• $c'),
              ),
            if (a.sources.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Fonti consultate',
                  style: t.textTheme.labelLarge
                      ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              for (final s in a.sources)
                InkWell(
                  onTap: () {
                    final url = s.contains('|') ? s.split('|').last : s;
                    Clipboard.setData(ClipboardData(text: url));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Link copiato')));
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      s.contains('|') ? s.split('|').first : s,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: t.colorScheme.primary,
                          decoration: TextDecoration.underline),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _InfoCard(
      {required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: t.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
