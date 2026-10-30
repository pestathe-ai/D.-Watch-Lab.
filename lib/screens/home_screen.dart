import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/appraisal.dart';
import '../services/prompt.dart';
import '../services/storage.dart';
import '../widgets/ebay_setup.dart';
import '../widgets/key_setup.dart';
import 'analyze_screen.dart';
import 'result_screen.dart';

class HomeScreen extends StatefulWidget {
  final Storage storage;
  final ValueNotifier<bool> hasKey;
  final VoidCallback onSaved;
  final int collectionVersion;
  const HomeScreen({
    super.key,
    required this.storage,
    required this.hasKey,
    required this.onSaved,
    required this.collectionVersion,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final picker = ImagePicker();
  late final AnimationController pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat();
  List<SavedValuation> recent = const [];
  bool ebayConnected = true;

  @override
  void initState() {
    super.initState();
    _loadRecent();
    _checkEbay();
  }

  Future<void> _checkEbay() async {
    final k = await widget.storage.loadEbay();
    if (mounted) {
      setState(() => ebayConnected = k.id.isNotEmpty && k.secret.isNotEmpty);
    }
  }

  Future<void> _openEbaySetup() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 0, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: EbaySetupCard(
            storage: widget.storage,
            onConnected: () => Navigator.of(ctx).pop(),
          ),
        ),
      ),
    );
    _checkEbay();
  }

  @override
  void didUpdateWidget(HomeScreen old) {
    super.didUpdateWidget(old);
    if (old.collectionVersion != widget.collectionVersion) _loadRecent();
    _checkEbay();
  }

  Future<void> _loadRecent() async {
    final all = await widget.storage.loadCollection();
    if (mounted) setState(() => recent = all.take(6).toList());
  }

  @override
  void dispose() {
    pulse.dispose();
    super.dispose();
  }

  Future<void> _start(ImageSource source) async {
    HapticFeedback.selectionClick();
    if (!widget.hasKey.value) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Prima attiva l\'IA gratuita qui sopra (1 minuto).')));
      return;
    }
    XFile? x;
    try {
      x = await picker.pickImage(
          source: source, maxWidth: 1280, maxHeight: 1280, imageQuality: 82);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fotocamera non disponibile: $e')));
      return;
    }
    if (x == null || !mounted) return;
    final file = File(x.path);
    final dial = photoSlots.first;
    final labels = ['${dial.label} (${dial.hint})'];
    final result = await analyze(context,
        storage: widget.storage, photos: [file], labels: labels);
    if (result == null || !mounted) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          storage: widget.storage,
          appraisal: result,
          photos: [file],
          labels: labels,
        ),
      ),
    );
    if (saved == true) {
      widget.onSaved();
      _loadRecent();
    }
  }

  Future<void> _openSaved(SavedValuation v) async {
    final changed = await Navigator.push<bool>(context,
        MaterialPageRoute(builder: (_) => ResultScreen.fromSaved(widget.storage, v)));
    if (changed == true) {
      widget.onSaved();
      _loadRecent();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ValueListenableBuilder<bool>(
          valueListenable: widget.hasKey,
          builder: (_, hasKey, __) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              Text('D. WATCH LAB',
                  style: t.textTheme.labelLarge?.copyWith(
                      color: t.colorScheme.primary, letterSpacing: 3)),
              const SizedBox(height: 6),
              Text('Quanto vale\nil tuo orologio?',
                  style: t.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700, height: 1.15)),
              const SizedBox(height: 20),
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                child: hasKey
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: KeySetupCard(
                          storage: widget.storage,
                          onConnected: () {
                            widget.hasKey.value = true;
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'IA attivata! Ora fotografa il quadrante.')));
                          },
                        ),
                      ),
              ),
              _CameraHero(
                pulse: pulse,
                enabled: hasKey,
                onCamera: () => _start(ImageSource.camera),
                onGallery: () => _start(ImageSource.gallery),
              ),
              if (hasKey && !ebayConnected) ...[
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: Icon(Icons.storefront_outlined,
                        color: t.colorScheme.primary),
                    title: const Text('Prezzi da annunci reali'),
                    subtitle: const Text(
                        'Collega eBay (gratis) per un prezzo di mercato vero'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openEbaySetup,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              const _Tips(),
              if (recent.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('Ultime valutazioni', style: t.textTheme.titleMedium),
                const SizedBox(height: 10),
                SizedBox(
                  height: 168,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: recent.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => _RecentCard(
                        v: recent[i], onTap: () => _openSaved(recent[i])),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CameraHero extends StatelessWidget {
  final AnimationController pulse;
  final bool enabled;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  const _CameraHero({
    required this.pulse,
    required this.enabled,
    required this.onCamera,
    required this.onGallery,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final gold = t.colorScheme.primary;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: enabled ? 1 : 0.45,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
          child: Column(
            children: [
              GestureDetector(
                onTap: onCamera,
                child: SizedBox(
                  width: 170,
                  height: 170,
                  child: AnimatedBuilder(
                    animation: pulse,
                    builder: (_, child) => Stack(
                      alignment: Alignment.center,
                      children: [
                        if (enabled)
                          Container(
                            width: 120 + 50 * pulse.value,
                            height: 120 + 50 * pulse.value,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: gold.withValues(
                                      alpha: 0.5 * (1 - pulse.value)),
                                  width: 2),
                            ),
                          ),
                        child!,
                      ],
                    ),
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFE3C98B), Color(0xFFA9893F)],
                        ),
                        boxShadow: [
                          BoxShadow(
                              color: gold.withValues(alpha: 0.35),
                              blurRadius: 30,
                              offset: const Offset(0, 8)),
                        ],
                      ),
                      child: const Icon(Icons.photo_camera,
                          size: 48, color: Color(0xFF1A1508)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text('Fotografa il quadrante',
                  style: t.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Basta una foto. Il valore arriva in pochi secondi.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onGallery,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Oppure scegli dalla galleria'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tips extends StatelessWidget {
  const _Tips();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    Widget tip(IconData i, String s) => Expanded(
          child: Column(
            children: [
              Icon(i, color: t.colorScheme.primary, size: 22),
              const SizedBox(height: 6),
              Text(s,
                  textAlign: TextAlign.center,
                  style: t.textTheme.bodySmall
                      ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ],
          ),
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tip(Icons.crop_free, 'Quadrante dritto e a tutto schermo'),
        tip(Icons.wb_sunny_outlined, 'Luce naturale, niente flash'),
        tip(Icons.blur_off, 'Nessun riflesso sul vetro'),
      ],
    );
  }
}

class _RecentCard extends StatelessWidget {
  final SavedValuation v;
  final VoidCallback onTap;
  const _RecentCard({required this.v, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SizedBox(
      width: 130,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 92,
                width: double.infinity,
                child: v.photoPaths.isEmpty
                    ? const ColoredBox(color: Colors.black26)
                    : Image.file(File(v.photoPaths.first),
                        fit: BoxFit.cover,
                        cacheWidth: 260,
                        errorBuilder: (_, __, ___) =>
                            const ColoredBox(color: Colors.black26)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                child: Text(v.appraisal.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
                child: Text(
                    formatMoney(v.appraisal.displayLikely, v.appraisal.currency),
                    maxLines: 1,
                    style: TextStyle(
                        color: t.colorScheme.primary,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
