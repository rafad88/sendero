import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gpx/gpx.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../data/app_route.dart';
import '../data/route_repository.dart';
import '../providers/route_provider.dart';

// ── Internal state ────────────────────────────────────────────────────────────

class _ParsedGpx {
  const _ParsedGpx({
    required this.rawContent,
    required this.suggestedTitle,
    required this.distanceM,
    required this.elevationGainM,
    required this.elevationLossM,
    required this.startLat,
    required this.startLon,
    required this.bboxMinLat,
    required this.bboxMinLon,
    required this.bboxMaxLat,
    required this.bboxMaxLon,
  });

  final String rawContent;
  final String suggestedTitle;
  final double distanceM;
  final double elevationGainM;
  final double elevationLossM;
  final double startLat;
  final double startLon;
  final double bboxMinLat;
  final double bboxMinLon;
  final double bboxMaxLat;
  final double bboxMaxLon;
}

_ParsedGpx _parseGpxContent(String raw, String fileName) {
  final gpx = GpxReader().fromString(raw);

  final trkpts = gpx.trks
      .expand((t) => t.trksegs)
      .expand((s) => s.trkpts)
      .where((p) => p.lat != null && p.lon != null)
      .toList();

  if (trkpts.isEmpty) throw Exception('GPX has no track points');

  final points = trkpts.map((p) => LatLng(p.lat!, p.lon!)).toList();

  double distanceM = 0;
  for (var i = 1; i < points.length; i++) {
    distanceM += _haversineM(points[i - 1], points[i]);
  }

  double gainM = 0, lossM = 0;
  for (var i = 1; i < trkpts.length; i++) {
    final prev = trkpts[i - 1].ele;
    final curr = trkpts[i].ele;
    if (prev == null || curr == null) continue;
    final diff = curr - prev;
    if (diff > 0) gainM += diff;
    if (diff < 0) lossM += diff.abs();
  }

  final lats = points.map((p) => p.latitude);
  final lons = points.map((p) => p.longitude);

  final title = (gpx.trks.isNotEmpty && gpx.trks.first.name != null && gpx.trks.first.name!.isNotEmpty)
      ? gpx.trks.first.name!
      : fileName.replaceAll(RegExp(r'\.gpx$', caseSensitive: false), '').replaceAll('_', ' ');

  return _ParsedGpx(
    rawContent:     raw,
    suggestedTitle: title,
    distanceM:      distanceM,
    elevationGainM: gainM,
    elevationLossM: lossM,
    startLat:       points.first.latitude,
    startLon:       points.first.longitude,
    bboxMinLat:     lats.reduce(math.min),
    bboxMinLon:     lons.reduce(math.min),
    bboxMaxLat:     lats.reduce(math.max),
    bboxMaxLon:     lons.reduce(math.max),
  );
}

double _haversineM(LatLng a, LatLng b) {
  const r = 6371000.0;
  final dLat = _rad(b.latitude - a.latitude);
  final dLon = _rad(b.longitude - a.longitude);
  final sinLat = math.sin(dLat / 2);
  final sinLon = math.sin(dLon / 2);
  final h = sinLat * sinLat +
      math.cos(_rad(a.latitude)) * math.cos(_rad(b.latitude)) * sinLon * sinLon;
  return 2 * r * math.asin(math.sqrt(h));
}

double _rad(double deg) => deg * math.pi / 180;

String _slugify(String title) {
  return title
      .toLowerCase()
      .replaceAll(RegExp(r'[áàäâ]'), 'a')
      .replaceAll(RegExp(r'[éèëê]'), 'e')
      .replaceAll(RegExp(r'[íìïî]'), 'i')
      .replaceAll(RegExp(r'[óòöô]'), 'o')
      .replaceAll(RegExp(r'[úùüû]'), 'u')
      .replaceAll(RegExp(r'ñ'), 'n')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

// ── Screen ────────────────────────────────────────────────────────────────────

class CreateRouteScreen extends ConsumerStatefulWidget {
  const CreateRouteScreen({super.key});

  @override
  ConsumerState<CreateRouteScreen> createState() => _CreateRouteScreenState();
}

class _CreateRouteScreenState extends ConsumerState<CreateRouteScreen> {
  _ParsedGpx? _parsed;
  bool _isParsing   = false;
  bool _isUploading = false;
  String? _error;

  final _titleController = TextEditingController();
  final _descController  = TextEditingController();
  String     _activityType = 'hike';
  int        _difficulty   = 1;
  RouteShape _shape        = RouteShape.circular;

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickGpx() async {
    setState(() { _isParsing = true; _error = null; });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (result == null || result.files.single.bytes == null) {
        setState(() => _isParsing = false);
        return;
      }
      final ext = result.files.single.extension?.toLowerCase();
      if (ext != 'gpx') {
        setState(() { _isParsing = false; _error = 'Selecciona un archivo .gpx'; });
        return;
      }
      final bytes    = result.files.single.bytes!;
      final fileName = result.files.single.name;
      final raw      = String.fromCharCodes(bytes);
      final parsed   = _parseGpxContent(raw, fileName);

      setState(() {
        _parsed = parsed;
        _titleController.text = parsed.suggestedTitle;
        _isParsing = false;
      });
    } catch (e) {
      setState(() { _isParsing = false; _error = e.toString(); });
    }
  }

  Future<void> _publish() async {
    final parsed = _parsed;
    if (parsed == null) return;
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'El título no puede estar vacío');
      return;
    }

    setState(() { _isUploading = true; _error = null; });
    try {
      final user = Supabase.instance.client.auth.currentUser!;
      final slug = _slugify(title);
      final gpxPath = '${user.id}/$slug.gpx';

      final gpxBytes = parsed.rawContent.codeUnits
          .map((c) => c & 0xFF)
          .toList();
      await Supabase.instance.client.storage
          .from('gpx-files')
          .uploadBinary(
            gpxPath,
            Uint8List.fromList(gpxBytes),
            fileOptions: const FileOptions(contentType: 'application/gpx+xml', upsert: true),
          );

      await ref.read(routeRepositoryProvider).createRoute(
        slug:           slug,
        title:          title,
        description:    _descController.text.trim().isEmpty ? null : _descController.text.trim(),
        activityType:   _activityType,
        difficulty:     _difficulty,
        shape:          _shape,
        gpxPath:        gpxPath,
        distanceM:      parsed.distanceM,
        elevationGainM: parsed.elevationGainM,
        elevationLossM: parsed.elevationLossM,
        startLat:       parsed.startLat,
        startLon:       parsed.startLon,
        bboxMinLat:     parsed.bboxMinLat,
        bboxMinLon:     parsed.bboxMinLon,
        bboxMaxLat:     parsed.bboxMaxLat,
        bboxMaxLon:     parsed.bboxMaxLon,
        authorId:       user.id,
      );

      ref.invalidate(routesProvider);
      if (mounted) context.go('/explore/route/$slug');
    } catch (e) {
      setState(() { _isUploading = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva ruta')),
      body: _isUploading
          ? const Center(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Subiendo ruta...'),
              ],
            ))
          : _parsed == null
              ? _PickGpxView(
                  isParsing: _isParsing,
                  error: _error,
                  onPick: _pickGpx,
                )
              : _FormView(
                  parsed:          _parsed!,
                  titleController: _titleController,
                  descController:  _descController,
                  activityType:    _activityType,
                  difficulty:      _difficulty,
                  shape:           _shape,
                  error:           _error,
                  onActivityType:  (v) => setState(() => _activityType = v),
                  onDifficulty:    (v) => setState(() => _difficulty = v),
                  onShape:         (v) => setState(() => _shape = v),
                  onPublish:       _publish,
                  onChangGpx:      _pickGpx,
                ),
    );
  }
}

// ── Pick GPX view ─────────────────────────────────────────────────────────────

class _PickGpxView extends StatelessWidget {
  const _PickGpxView({required this.isParsing, required this.error, required this.onPick});
  final bool isParsing;
  final String? error;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.upload_file, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 24),
            Text('Importa un archivo GPX',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'La ruta se analizará automáticamente para calcular distancia y desnivel.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 32),
            if (isParsing)
              const CircularProgressIndicator()
            else
              FilledButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.folder_open),
                label: const Text('Seleccionar archivo GPX'),
              ),
            if (error != null) ...[
              const SizedBox(height: 16),
              Text(error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Form view ─────────────────────────────────────────────────────────────────

class _FormView extends StatelessWidget {
  const _FormView({
    required this.parsed,
    required this.titleController,
    required this.descController,
    required this.activityType,
    required this.difficulty,
    required this.shape,
    required this.error,
    required this.onActivityType,
    required this.onDifficulty,
    required this.onShape,
    required this.onPublish,
    required this.onChangGpx,
  });

  final _ParsedGpx parsed;
  final TextEditingController titleController;
  final TextEditingController descController;
  final String activityType;
  final int difficulty;
  final RouteShape shape;
  final String? error;
  final ValueChanged<String> onActivityType;
  final ValueChanged<int> onDifficulty;
  final ValueChanged<RouteShape> onShape;
  final VoidCallback onPublish;
  final VoidCallback onChangGpx;

  static const _activities = [
    ('hike', Icons.hiking,          'Senderismo'),
    ('bike', Icons.directions_bike, 'Bici'),
    ('run',  Icons.directions_run,  'Running'),
  ];

  static const _difficultyLabels = ['Fácil', 'Moderado', 'Difícil', 'Experto'];
  static const _difficultyColors = [Colors.green, Colors.orange, Colors.deepOrange, Colors.red];

  @override
  Widget build(BuildContext context) {
    final distKm  = (parsed.distanceM / 1000).toStringAsFixed(1);
    final gainM   = parsed.elevationGainM.round();
    final lossM   = parsed.elevationLossM.round();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // GPX stats card
        Card(
          color: AppColors.forestGreen.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatChip(icon: Icons.straighten,    label: '$distKm km'),
                _StatChip(icon: Icons.arrow_upward,  label: '+$gainM m'),
                _StatChip(icon: Icons.arrow_downward, label: '-$lossM m'),
                TextButton(
                  onPressed: onChangGpx,
                  child: const Text('Cambiar'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Title
        TextField(
          controller: titleController,
          decoration: const InputDecoration(
            labelText: 'Nombre de la ruta *',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 16),

        // Description
        TextField(
          controller: descController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Descripción (opcional)',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 20),

        // Activity type
        Text('Actividad', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Row(
          children: _activities.map(((String, IconData, String) rec) {
            final selected = activityType == rec.$1;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _ToggleCard(
                  icon: rec.$2,
                  label: rec.$3,
                  selected: selected,
                  onTap: () => onActivityType(rec.$1),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),

        // Difficulty
        Text('Dificultad', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Row(
          children: List.generate(4, (i) {
            final selected = difficulty == i;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i < 3 ? 8 : 0),
                child: GestureDetector(
                  onTap: () => onDifficulty(i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? _difficultyColors[i].withValues(alpha: 0.15)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: selected
                          ? Border.all(color: _difficultyColors[i], width: 1.5)
                          : null,
                    ),
                    child: Text(
                      _difficultyLabels[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                        color: selected ? _difficultyColors[i] : Colors.grey.shade700,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 20),

        // Shape
        Text('Tipo de recorrido', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Row(
          children: RouteShape.values.map((s) {
            final selected = shape == s;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: s != RouteShape.linearOutBack ? 8 : 0),
                child: _ToggleCard(
                  icon: switch (s) {
                    RouteShape.circular      => Icons.loop,
                    RouteShape.linearOneWay  => Icons.arrow_forward,
                    RouteShape.linearOutBack => Icons.swap_horiz,
                  },
                  label: s.label,
                  selected: selected,
                  onTap: () => onShape(s),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),

        if (error != null) ...[
          Text(error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 12),
        ],

        FilledButton.icon(
          onPressed: onPublish,
          icon: const Icon(Icons.cloud_upload_outlined),
          label: const Text('Publicar ruta'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: AppColors.forestGreen),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    ],
  );
}

class _ToggleCard extends StatelessWidget {
  const _ToggleCard({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: selected ? AppColors.forestGreen.withValues(alpha: 0.12) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: selected ? Border.all(color: AppColors.forestGreen, width: 1.5) : null,
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: selected ? AppColors.forestGreen : Colors.grey.shade600),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              color: selected ? AppColors.forestGreen : Colors.grey.shade700,
            ),
          ),
        ],
      ),
    ),
  );
}
