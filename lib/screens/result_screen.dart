import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/appraisal.dart';
import '../services/prompt.dart';
import '../services/storage.dart';
import '../models/market.dart';
import 'analyze_screen.dart';
import 'market_web_screen.dart';

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
  late final List<File> photos = [...widget.photos];
  late final List<String> labels = [...widget.labels];
  late bool box = widget.box;
  late bool papers = widget.papers;
  late final TextEditingController extraCtrl =
      TextEditingController(text: widget.extraInfo);
  final picker = ImagePicker();

  /// Ci sono foto o informazioni nuove non ancora valutate.
  bool pending = false;
  bool busy = false;
  bool changed = false;

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  bool _hasSlot(PhotoSlot s) => labels.any((l) => l.startsWith(s.label));

  Future<void> _addPhoto(PhotoSlot slot) async {
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
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final x = await picker.pickImage(
          source: source, maxWidth: 1280, maxHeight: 1280, imageQuality: 82);
      if (x == null) return;
      HapticFeedback.selectionClick();
      setState(() {
        photos.add(File(x.path));
        labels.add('${slot.label} (${slot.hint})');
        pending = true;
      });
    } catch (e) {
      _snack('Fotocamera non disponibile: $e');
    }
  }

  Future<void> _revalue() async {
    final fresh = await analyze(context,
        storage: widget.storage,
        photos: photos,
        labels: labels,
        extraInfo: extraCtrl.text,
        box: box,
        papers: papers);
    if (fresh == null || !mounted) return;
    setState(() {
      a = fresh;
      pending = false;
    });
    if (saved != null) {
      await _persist(replace: true);
      _snack('Valore aggiornato');
    }
  }

  Future<void> _persist({bool replace = false}) async {
    setState(() => busy = true);
    try {
      saved = await widget.storage.add(a, photos,
          replaceId: replace ? saved?.id : null,
          labels: labels,
          box: box,
          papers: papers,
          extraInfo: extraCtrl.text);
      changed = true;
      HapticFeedback.mediumImpact();
      if (!replace) _snack('Aggiunto alla collezione');
    } catch (e) {
      _snack('Errore nel salvataggio: $e');
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
        ClipboardData(text: a.listingText(box: box, papers: papers)));
    HapticFeedback.selectionClick();
    _snack('Testo annuncio copiato');
  }

  @override
  void dispose() {
    extraCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cards = <Widget>[
      if (!a.isWatch)
        const _InfoCard(
          icon: Icons.help_outline,
          title: 'Non vedo un orologio',
          body: 'Riprova con una foto frontale e nitida del quadrante, ben '
              'illuminata e senza riflessi.',
        )
      else ...[
        _Header(a: a),
        _PriceCard(a: a),
        _MarketCard(a: a),
        _ImproveCard(
          slots: photoSlots.skip(1).where((s) => !_hasSlot(s)).toList(),
          onAdd: _addPhoto,
          box: box,
          papers: papers,
          extraCtrl: extraCtrl,
          tips: a.morePhotos,
          onBox: (v) => setState(() {
            box = v;
            pending = true;
          }),
          onPapers: (v) => setState(() {
            papers = v;
            pending = true;
          }),
          onExtraChanged: () => setState(() => pending = true),
        ),
        if (a.alternatives.isNotEmpty) _AlternativesCard(a: a),
        _FlagsCard(a: a),
        _DetailsCard(a: a, box: box, papers: papers),
        if (saved != null && saved!.timeline.length > 1)
          _HistoryCard(points: saved!.timeline, currency: a.currency),
        if (a.comparables.isNotEmpty || a.sources.isNotEmpty)
          _SourcesCard(a: a),
        Text(
          'Stima indicativa generata dall\'IA, non è una perizia né '
          'un\'autenticazione. Per orologi di valore rivolgiti a un '
          'rivenditore autorizzato o a un perito.',
          style: t.textTheme.bodySmall
              ?.copyWith(color: t.colorScheme.onSurfaceVariant),
        ),
      ],
    ];

    final Widget primary;
    if (pending) {
      primary = FilledButton.icon(
        key: const ValueKey('revalue'),
        onPressed: busy ? null : _revalue,
        icon: const Icon(Icons.auto_awesome),
        label: Text('Rivaluta con ${photos.length} '
            '${photos.length == 1 ? 'foto' : 'foto'}'),
      );
    } else if (saved == null) {
      primary = FilledButton.icon(
        key: const ValueKey('save'),
        onPressed: busy || !a.isWatch ? null : _persist,
        icon: const Icon(Icons.add),
        label: const Text('Aggiungi alla collezione'),
      );
    } else {
      primary = FilledButton.tonalIcon(
        key: const ValueKey('update'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
        onPressed: busy ? null : _revalue,
        icon: const Icon(Icons.refresh),
        label: const Text('Aggiorna il valore'),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(saved != null ? 'Il tuo orologio' : 'Valutazione'),
          actions: [
            if (a.isWatch)
              IconButton(
                  tooltip: 'Copia testo annuncio',
                  onPressed: _copyListing,
                  icon: const Icon(Icons.sell_outlined)),
            if (saved != null)
              IconButton(
                  tooltip: 'Elimina',
                  onPressed: busy ? null : _delete,
                  icon: const Icon(Icons.delete_outline)),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            _Gallery(photos: photos, labels: labels),
            const SizedBox(height: 16),
            for (var i = 0; i < cards.length; i++)
              _FadeIn(
                delay: Duration(milliseconds: 60 * i),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: cards[i],
                ),
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Comparsa morbida delle schede.
class _FadeIn extends StatelessWidget {
  final Duration delay;
  final Widget child;
  const _FadeIn({required this.delay, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380) + delay,
      curve: Interval(
          delay.inMilliseconds / (380 + delay.inMilliseconds), 1,
          curve: Curves.easeOutCubic),
      builder: (_, v, c) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 16 * (1 - v)), child: c),
      ),
      child: child,
    );
  }
}

class _ImproveCard extends StatelessWidget {
  final List<PhotoSlot> slots;
  final void Function(PhotoSlot) onAdd;
  final bool box;
  final bool papers;
  final TextEditingController extraCtrl;
  final List<String> tips;
  final ValueChanged<bool> onBox;
  final ValueChanged<bool> onPapers;
  final VoidCallback onExtraChanged;

  const _ImproveCard({
    required this.slots,
    required this.onAdd,
    required this.box,
    required this.papers,
    required this.extraCtrl,
    required this.tips,
    required this.onBox,
    required this.onPapers,
    required this.onExtraChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Theme(
        data: t.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(Icons.tune, color: t.colorScheme.primary),
          title: const Text('Migliora la stima'),
          subtitle: Text(
            tips.isNotEmpty
                ? 'Consiglio: ${tips.first}'
                : 'Aggiungi foto e dettagli, poi rivaluta',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (slots.isNotEmpty) ...[
              Text('Aggiungi una foto',
                  style: t.textTheme.labelLarge
                      ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in slots)
                    ActionChip(
                      avatar: const Icon(Icons.add_a_photo_outlined, size: 18),
                      label: Text(s.label),
                      onPressed: () => onAdd(s),
                    ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            Text('Corredo',
                style: t.textTheme.labelLarge
                    ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                    label: const Text('Scatola originale'),
                    selected: box,
                    onSelected: onBox),
                FilterChip(
                    label: const Text('Garanzia / documenti'),
                    selected: papers,
                    onSelected: onPapers),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: extraCtrl,
              minLines: 1,
              maxLines: 3,
              onChanged: (_) => onExtraChanged(),
              decoration: const InputDecoration(
                hintText: 'Altri dettagli: anno, revisioni, referenza…',
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
    final m = a.hasMarket ? a.market : null;
    final likely = a.displayLikely;
    final low = a.displayLow;
    final high = a.displayHigh;
    final hasRange = low != null && high != null;
    final muted = t.textTheme.bodyMedium
        ?.copyWith(color: t.colorScheme.onSurfaceVariant);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                      m != null
                          ? 'Prezzo di mercato (annunci reali)'
                          : 'Stima dell\'IA (usato)',
                      style: t.textTheme.labelLarge
                          ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                ),
                _Badge(
                  text: m != null
                      ? '${m.count} annunci'
                      : 'senza annunci',
                  good: m != null,
                ),
              ],
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: likely ?? 0),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => Text(
                    likely == null ? '—' : formatMoney(v, a.currency),
                    style: t.textTheme.displaySmall?.copyWith(
                        color: t.colorScheme.primary,
                        fontWeight: FontWeight.w700)),
              ),
            ),
            if (hasRange) ...[
              const SizedBox(height: 14),
              _RangeBar(low: low, high: high, likely: likely),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(formatMoney(low, a.currency),
                      style: t.textTheme.bodySmall),
                  Text(formatMoney(high, a.currency),
                      style: t.textTheme.bodySmall),
                ],
              ),
            ],
            const SizedBox(height: 12),
            if (m != null) ...[
              Text(
                  'Mediana ponderata di ${m.count} annunci eBay attivi '
                  '(${m.scanned} letti, scartati quelli fuori scala o non '
                  'pertinenti). Affidabilità: ${m.reliability}.',
                  style: muted),
              if (m.newMedian != null) ...[
                const SizedBox(height: 6),
                Text('Nuovo su eBay: ${formatMoney(m.newMedian, a.currency)}',
                    style: t.textTheme.bodyMedium),
              ],
              if (a.priceLikely != null) ...[
                const SizedBox(height: 6),
                Text('Stima dell\'IA: ${formatMoney(a.priceLikely, a.currency)}',
                    style: muted),
              ],
            ] else ...[
              if (a.retailNew != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                      'Prezzo del nuovo: ${formatMoney(a.retailNew, a.currency)}',
                      style: t.textTheme.bodyMedium),
                ),
              if (a.priceRationale.isNotEmpty) Text(a.priceRationale, style: muted),
            ],
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final bool good;
  const _Badge({required this.text, required this.good});

  @override
  Widget build(BuildContext context) {
    final c = good ? const Color(0xFF6BCB8B) : const Color(0xFFE8C468);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// Annunci reali + mercati di riferimento (Chrono24, Subito, eBay).
class _MarketCard extends StatelessWidget {
  final WatchAppraisal a;
  const _MarketCard({required this.a});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final m = a.market;
    final q = marketQuery(
        brand: a.brand, model: a.model, reference: a.reference);
    final listings = m?.listings ?? const <Listing>[];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Confronta sui mercati', style: t.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Ricerca già pronta per "$q"',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => MarketWebScreen(
                          title: 'Chrono24', url: chrono24Url(q)))),
              icon: const Icon(Icons.watch),
              label: const Text('Apri Chrono24 (prezzo crescente)'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => MarketWebScreen(
                                title: 'Subito', url: subitoUrl(q)))),
                    child: const Text('Subito'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => MarketWebScreen(
                                title: 'eBay', url: ebaySearchUrl(q)))),
                    child: const Text('eBay'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => MarketWebScreen(
                                title: 'Catawiki', url: catawikiUrl(q)))),
                    child: const Text('Catawiki'),
                  ),
                ),
              ],
            ),
            if (listings.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Annunci usati per il calcolo',
                  style: t.textTheme.labelLarge
                      ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              for (final l in listings.take(8)) _ListingRow(l: l),
              if (listings.length > 8)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (_) => DraggableScrollableSheet(
                        expand: false,
                        initialChildSize: 0.7,
                        builder: (_, sc) => ListView(
                          controller: sc,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          children: [
                            for (final l in listings) _ListingRow(l: l),
                          ],
                        ),
                      ),
                    ),
                    child: Text('Vedi tutti (${listings.length})'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ListingRow extends StatelessWidget {
  final Listing l;
  const _ListingRow({required this.l});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: l.url.isEmpty
          ? null
          : () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      MarketWebScreen(title: l.market, url: Uri.parse(l.url)))),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 48,
                height: 48,
                child: l.imageUrl == null
                    ? const ColoredBox(color: Colors.black26)
                    : Image.network(l.imageUrl!,
                        fit: BoxFit.cover,
                        cacheWidth: 144,
                        errorBuilder: (_, __, ___) =>
                            const ColoredBox(color: Colors.black26)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13)),
                  Text(
                      '${l.market}${l.condition.isEmpty ? '' : ' · ${l.condition}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          color: t.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(formatMoney(l.price, l.currency),
                style: TextStyle(
                    color: t.colorScheme.primary,
                    fontWeight: FontWeight.w700)),
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
