import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:latlong2/latlong.dart';

import '../state/land_map_notifier.dart';

enum _ViewMode { combined, basic, text, photo }

class SavedLocationsPage extends ConsumerStatefulWidget {
  final VoidCallback? onOpenMapRequested;

  const SavedLocationsPage({super.key, this.onOpenMapRequested});

  @override
  ConsumerState<SavedLocationsPage> createState() => _SavedLocationsPageState();
}

class _SavedLocationsPageState extends ConsumerState<SavedLocationsPage> {
  _ViewMode _viewMode = _ViewMode.combined;

  @override
  Widget build(BuildContext context) {
    final box = Hive.box('landbox');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              const Spacer(),
              IconButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Filter - Coming soon')),
                  );
                },
                icon: const Icon(Icons.tune, size: 20),
              ),
              IconButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Sort - Coming soon')),
                  );
                },
                icon: const Icon(Icons.sort, size: 20),
              ),
              IconButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('More - Coming soon')),
                  );
                },
                icon: const Icon(Icons.more_vert, size: 20),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _ViewModeChip(
                label: 'Combined',
                icon: Icons.view_list,
                isSelected: _viewMode == _ViewMode.combined,
                onTap: () => setState(() => _viewMode = _ViewMode.combined),
              ),
              const SizedBox(width: 8),
              _ViewModeChip(
                label: 'Basic',
                icon: Icons.view_agenda,
                isSelected: _viewMode == _ViewMode.basic,
                onTap: () => setState(() => _viewMode = _ViewMode.basic),
              ),
              const SizedBox(width: 8),
              _ViewModeChip(
                label: 'Text',
                icon: Icons.notes,
                isSelected: _viewMode == _ViewMode.text,
                onTap: () => setState(() => _viewMode = _ViewMode.text),
              ),
              const SizedBox(width: 8),
              _ViewModeChip(
                label: 'Photo',
                icon: Icons.photo_camera,
                isSelected: _viewMode == _ViewMode.photo,
                onTap: () => setState(() => _viewMode = _ViewMode.photo),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ValueListenableBuilder(
            valueListenable: box.listenable(),
            builder: (context, Box box, _) {
              final items =
                  box.values
                      .whereType<Map>()
                      .map((e) => Map<String, dynamic>.from(e))
                      .where((e) {
                        final entityType = e['entityType']?.toString();
                        if (entityType == 'marker') return false;
                        return true;
                      })
                      .toList()
                    ..sort(
                      (a, b) => (b['createdAt'] ?? '').toString().compareTo(
                        (a['createdAt'] ?? '').toString(),
                      ),
                    );

              if (items.isEmpty) {
                return _EmptyState();
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final id = item['id']?.toString() ?? '';
                  return _SavedLocationCard(
                    name: item['name']?.toString() ?? 'Saved location',
                    createdAt: item['createdAt']?.toString(),
                    points: (item['points'] as List?)?.length ?? 0,
                    viewMode: _viewMode,
                    onTap: () => _showDetails(context, item),
                    onMore: () => _showActions(context, id, item),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showActions(
    BuildContext context,
    String id,
    Map<String, dynamic> item,
  ) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                _ActionTile(
                  icon: Icons.map_outlined,
                  label: 'Open on map',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openSavedLandOnMap(context, item);
                  },
                ),
                _ActionTile(
                  icon: Icons.edit,
                  label: 'Rename',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _renameItem(context, id, item['name']?.toString() ?? '');
                  },
                ),
                _ActionTile(
                  icon: Icons.copy,
                  label: 'Copy coordinates',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _copyCoordinates(context, item);
                  },
                ),
                _ActionTile(
                  icon: Icons.share,
                  label: 'Share',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _shareItem(context, item);
                  },
                ),
                _ActionTile(
                  icon: Icons.delete_outline,
                  label: 'Delete',
                  isDestructive: true,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _deleteItem(context, id);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDetails(BuildContext context, Map<String, dynamic> item) {
    final points = (item['points'] as List?) ?? [];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    item['name']?.toString() ?? 'Saved location',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${points.length} points · ${_formatDate(item['createdAt']?.toString())}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.black54),
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _openSavedLandOnMap(context, item);
                    },
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Open on map'),
                  ),
                ),
                const SizedBox(height: 12),
                if (points.isEmpty)
                  const Text('No points saved.')
                else
                  SizedBox(
                    height: 180,
                    child: ListView.separated(
                      itemCount: points.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final p = points[index] as Map;
                        final lat = p['lat'];
                        final lng = p['lng'];
                        return ListTile(
                          dense: true,
                          leading: Text('#${index + 1}'),
                          title: Text('$lat, $lng'),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openSavedLandOnMap(BuildContext context, Map<String, dynamic> item) {
    final pointsRaw = (item['points'] as List?) ?? const [];
    if (pointsRaw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No points found for this land')),
      );
      return;
    }

    final points = <LatLng>[];
    for (final e in pointsRaw) {
      if (e is! Map) continue;
      final lat = (e['lat'] as num?)?.toDouble();
      final lng = (e['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      points.add(LatLng(lat, lng));
    }

    if (points.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved points are invalid')));
      return;
    }

    ref
        .read(landMapProvider.notifier)
        .loadSavedFieldPoints(
          points,
          fieldId: item['id']?.toString(),
          fieldName: item['name']?.toString(),
        );
    widget.onOpenMapRequested?.call();
  }

  void _renameItem(BuildContext context, String id, String currentName) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename location'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              final box = Hive.box('landbox');
              final raw = box.get(id);
              if (raw == null) return;
              final item = Map<String, dynamic>.from(raw);
              item['name'] = name;
              await box.put(id, item);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _deleteItem(BuildContext context, String id) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete location?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final box = Hive.box('landbox');
              await box.delete(id);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _copyCoordinates(
    BuildContext context,
    Map<String, dynamic> item,
  ) async {
    final points = (item['points'] as List?) ?? [];
    if (points.isEmpty) return;
    final coords = points
        .map((p) => '${p['lat']},${p['lng']}')
        .toList()
        .join('\n');
    await Clipboard.setData(ClipboardData(text: coords));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Coordinates copied')));
    }
  }

  Future<void> _shareItem(
    BuildContext context,
    Map<String, dynamic> item,
  ) async {
    final points = (item['points'] as List?) ?? [];
    final name = item['name']?.toString() ?? 'Saved location';
    final createdAt = _formatDate(item['createdAt']?.toString());
    final coords = points
        .map((p) => '${p['lat']},${p['lng']}')
        .toList()
        .join('\n');
    final text = '$name\n$createdAt\n\n$coords';
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Share text copied')));
    }
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return 'Unknown';
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return 'Unknown';
    final yyyy = parsed.year.toString().padLeft(4, '0');
    final mm = parsed.month.toString().padLeft(2, '0');
    final dd = parsed.day.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy';
  }
}

class _ViewModeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ViewModeChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isSelected ? theme.colorScheme.primary : Colors.black54;
    final bgColor = isSelected
        ? theme.colorScheme.primary.withValues(alpha: 0.1)
        : Colors.grey.shade100;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedLocationCard extends StatelessWidget {
  final String name;
  final String? createdAt;
  final int points;
  final _ViewMode viewMode;
  final VoidCallback onTap;
  final VoidCallback onMore;

  const _SavedLocationCard({
    required this.name,
    required this.createdAt,
    required this.points,
    required this.viewMode,
    required this.onTap,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateText = _formatDate(createdAt);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: _buildContent(theme, dateText),
      ),
    );
  }

  Widget _buildContent(ThemeData theme, String dateText) {
    switch (viewMode) {
      case _ViewMode.basic:
        return _buildBasic(theme, dateText);
      case _ViewMode.text:
        return _buildText(theme, dateText);
      case _ViewMode.photo:
        return _buildPhoto(theme, dateText);
      case _ViewMode.combined:
        return _buildCombined(theme, dateText);
    }
  }

  Widget _buildCombined(ThemeData theme, String dateText) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.place, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$points points · $dateText',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.black54,
                ),
              ),
            ],
          ),
        ),
        IconButton(onPressed: onMore, icon: const Icon(Icons.more_vert)),
      ],
    );
  }

  Widget _buildBasic(ThemeData theme, String dateText) {
    return Row(
      children: [
        Icon(Icons.place, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          dateText,
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
        ),
        const SizedBox(width: 6),
        IconButton(onPressed: onMore, icon: const Icon(Icons.more_vert)),
      ],
    );
  }

  Widget _buildText(ThemeData theme, String dateText) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(onPressed: onMore, icon: const Icon(Icons.more_vert)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Points: $points',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
        ),
        const SizedBox(height: 4),
        Text(
          'Created: $dateText',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
        ),
      ],
    );
  }

  Widget _buildPhoto(ThemeData theme, String dateText) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 120,
          width: double.infinity,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Icon(
              Icons.photo,
              size: 32,
              color: theme.colorScheme.primary.withValues(alpha: 0.6),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(onPressed: onMore, icon: const Icon(Icons.more_vert)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '$points points · $dateText',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
        ),
      ],
    );
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return 'Unknown';
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return 'Unknown';
    final yyyy = parsed.year.toString().padLeft(4, '0');
    final mm = parsed.month.toString().padLeft(2, '0');
    final dd = parsed.day.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy';
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDestructive;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    this.isDestructive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? Colors.red : Colors.black87;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color)),
      onTap: onTap,
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bookmark_border,
            size: 56,
            color: Colors.black.withValues(alpha: 0.25),
          ),
          const SizedBox(height: 12),
          Text(
            'No saved locations',
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Your saved places will appear here.',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.black45),
          ),
        ],
      ),
    );
  }
}
