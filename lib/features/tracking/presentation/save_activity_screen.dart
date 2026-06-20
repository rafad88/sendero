import 'package:drift/drift.dart' hide Index;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_service.dart';

class SaveActivityScreen extends ConsumerStatefulWidget {
  const SaveActivityScreen({required this.trackId, super.key});
  final String trackId;

  @override
  ConsumerState<SaveActivityScreen> createState() => _SaveActivityScreenState();
}

class _SaveActivityScreenState extends ConsumerState<SaveActivityScreen> {
  final _titleController = TextEditingController();
  bool _isPublic = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Save Activity')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Title',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Make public'),
            subtitle: const Text('Visible to other Sendero users'),
            value: _isPublic,
            onChanged: (v) => setState(() => _isPublic = v),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const CircularProgressIndicator.adaptive(strokeWidth: 2)
                : const Text('Save Activity'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => context.go('/map'),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final db  = ref.read(appDatabaseProvider);
      final now = DateTime.now().millisecondsSinceEpoch;

      final title = _titleController.text.trim().isEmpty
          ? _generateDefaultTitle()
          : _titleController.text.trim();

      await (db.update(db.tracksTable)..where((t) => t.id.equals(widget.trackId))).write(
        TracksTableCompanion(
          title:     Value(title),
          isPublic:  Value(_isPublic ? 1 : 0),
          updatedAt: Value(now),
        ),
      );

      // Enqueue for cloud sync
      await ref.read(syncServiceProvider).enqueue(
        entityType: 'track',
        entityId:   widget.trackId,
        operation:  'upsert',
        payload:    {'id': widget.trackId},
        priority:   3,
      );

      if (mounted) context.go('/map');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _generateDefaultTitle() {
    final hour = DateTime.now().hour;
    final part = hour < 12 ? 'Morning' : hour < 17 ? 'Afternoon' : 'Evening';
    return '$part Activity';
  }
}
