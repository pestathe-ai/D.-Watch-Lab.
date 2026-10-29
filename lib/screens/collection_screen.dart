import 'dart:io';

import 'package:flutter/material.dart';

import '../models/appraisal.dart';
import '../services/storage.dart';
import 'result_screen.dart';

/// Somma i valori della collezione (probabile, minimo, massimo).
({double likely, double low, double high}) collectionTotals(
    List<SavedValuation> items) {
  var likely = 0.0, low = 0.0, high = 0.0;
  for (final v in items) {
    final a = v.appraisal;
    likely += a.priceLikely ?? 0;
    low += a.priceLow ?? a.priceLikely ?? 0;
    high += a.priceHigh ?? a.priceLikely ?? 0;
  }
  return (likely: likely, low: low, high: high);
}

class CollectionScreen extends StatefulWidget {
  final Storage storage;
  final VoidCallback onChanged;
  const CollectionScreen(
      {super.key, required this.storage, required this.onChanged});

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  List<SavedValuation>? items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await widget.storage.loadCollection();
    if (mounted) setState(() => items = list);
  }

  Future<void> _open(SavedValuation v) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => ResultScreen.fromSaved(widget.storage, v)),
    );
    if (changed == true) {
      await _load();
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final list = items;
    return Scaffold(
      appBar: AppBar(title: const Text('Collezione')),
      body: list == null
          ? const Center(child: CircularProgressIndicator())
          : list.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.watch_outlined,
                            size: 56, color: t.colorScheme.primary),
                        const SizedBox(height: 12),
                        Text('Nessun orologio salvato',
                            style: t.textTheme.titleMedium),
                        const SizedBox(height: 6),
                        Text(
                          'Valuta un orologio e aggiungilo: qui vedrai il '
                          'valore totale e come cambia nel tempo.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: t.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      _TotalCard(items: list),
                      const SizedBox(height: 16),
                      for (final v in list) ...[
                        _WatchTile(v: v, onTap: () => _open(v)),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  final List<SavedValuation> items;
  const _TotalCard({required this.items});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tot = collectionTotals(items);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Valore della collezione · ${items.length} '
                '${items.length == 1 ? 'orologio' : 'orologi'}',
                style: t.textTheme.labelLarge
                    ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(formatMoney(tot.likely),
                  style: t.textTheme.displaySmall?.copyWith(
                      color: t.colorScheme.primary,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 4),
            Text('Forbice: ${formatMoney(tot.low)} – ${formatMoney(tot.high)}',
                style: t.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _WatchTile extends StatelessWidget {
  final SavedValuation v;
  final VoidCallback onTap;
  const _WatchTile({required this.v, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final a = v.appraisal;
    final tl = v.timeline;
    double? delta;
    if (tl.length > 1) delta = tl.last.value - tl.first.value;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: v.photoPaths.isEmpty
                      ? const ColoredBox(
                          color: Colors.black26, child: Icon(Icons.watch))
                      : Image.file(File(v.photoPaths.first),
                          fit: BoxFit.cover,
                          cacheWidth: 216,
                          errorBuilder: (_, __, ___) => const ColoredBox(
                              color: Colors.black26,
                              child: Icon(Icons.watch))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.titleMedium),
                    if (a.reference != null)
                      Text('Ref. ${a.reference}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: t.colorScheme.onSurfaceVariant,
                              fontSize: 13)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(formatMoney(a.priceLikely, a.currency),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: t.colorScheme.primary,
                                  fontWeight: FontWeight.w700)),
                        ),
                        if (delta != null && delta != 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            '${delta > 0 ? '▲' : '▼'} '
                            '${formatMoney(delta.abs(), a.currency)}',
                            style: TextStyle(
                                fontSize: 12,
                                color: delta > 0
                                    ? const Color(0xFF6BCB8B)
                                    : const Color(0xFFE57373)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (a.redFlags.any((f) => f.severity == 'alta'))
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.warning_amber_rounded,
                      color: Color(0xFFE57373), size: 20),
                ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
