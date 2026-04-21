import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:latlong2/latlong.dart';

import '../../auth/models/auth_models.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/ui/account_page.dart';
import '../models/land_api_models.dart';
import '../providers/land_cloud_provider.dart';
import '../state/land_map_notifier.dart';

enum _ViewMode { combined, basic, text, photo }
enum _SavedSort { newest, oldest, nameAsc, nameDesc, pointsDesc }
enum _SavedFilter { all, threePlusPoints, updatedOnly }

class SavedLocationsPage extends ConsumerStatefulWidget {
  final VoidCallback? onOpenMapRequested;

  const SavedLocationsPage({super.key, this.onOpenMapRequested});

  @override
  ConsumerState<SavedLocationsPage> createState() => _SavedLocationsPageState();
}

class _SavedLocationsPageState extends ConsumerState<SavedLocationsPage> {
  static const String _prefViewModeKey = 'prefs_saved_locations_view_mode';
  static const String _prefCompactModeKey = 'prefs_saved_locations_compact_mode';

  _ViewMode _viewMode = _ViewMode.combined;
  _SavedSort _sort = _SavedSort.newest;
  _SavedFilter _filter = _SavedFilter.all;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _selectionMode = false;
  final Set<String> _selectedIds = <String>{};
  String _groupFilter = 'All groups';
  bool _compactMode = false;
  ProviderSubscription<AuthSession>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _restoreDisplayPreferences();
    _authSubscription = ref.listenManual(authSessionProvider, (previous, next) {
      if (next.isLoggedIn && next.isVerified) {
        _fetchRemoteData();
        return;
      }
    });

    Future.microtask(_fetchRemoteData);
  }

  @override
  void dispose() {
    _authSubscription?.close();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchRemoteData() async {
    final session = ref.read(authSessionProvider);
    if (!session.isLoggedIn || !session.isVerified) return;
    await ref.read(remoteLandsProvider.notifier).fetch(
      search: _searchQuery.isEmpty ? null : _searchQuery,
    );
    await ref.read(remoteLandSummaryProvider.notifier).fetch();
  }

  void _restoreDisplayPreferences() {
    final box = Hive.box('landbox');
    final savedMode = box.get(_prefViewModeKey)?.toString();
    final savedCompact = box.get(_prefCompactModeKey);
    if (savedMode != null) {
      _viewMode = _viewModeFromStorage(savedMode);
    }
    if (savedCompact is bool) {
      _compactMode = savedCompact;
    }
  }

  Future<void> _setViewMode(_ViewMode mode) async {
    if (_viewMode == mode) return;
    setState(() => _viewMode = mode);
    final box = Hive.box('landbox');
    await box.put(_prefViewModeKey, mode.name);
  }

  Future<void> _toggleCompactMode() async {
    final next = !_compactMode;
    setState(() => _compactMode = next);
    final box = Hive.box('landbox');
    await box.put(_prefCompactModeKey, next);
  }

  _ViewMode _viewModeFromStorage(String raw) {
    for (final mode in _ViewMode.values) {
      if (mode.name == raw) return mode;
    }
    return _ViewMode.combined;
  }

  @override
  Widget build(BuildContext context) {
    final box = Hive.box('landbox');
    final authSession = ref.watch(authSessionProvider);
    final remoteLandsState = ref.watch(remoteLandsProvider);
    final remoteSummaryState = ref.watch(remoteLandSummaryProvider);
    final canUseCloud = authSession.isLoggedIn && authSession.isVerified;

    return Container(
      color: Colors.white70,
      child: Column(
        children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              if (_selectionMode)
                Text(
                  '${_selectedIds.length} selected',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              const Spacer(),
              if (_selectionMode)
                IconButton(
                  onPressed: _selectedIds.isEmpty
                      ? null
                      : _setGroupForSelectedItems,
                  icon: const Icon(Icons.folder_outlined, size: 20),
                  tooltip: 'Set group',
                ),
              if (_selectionMode)
                IconButton(
                  onPressed: _selectedIds.isEmpty ? null : _shareSelectedItems,
                  icon: const Icon(Icons.share_outlined, size: 20),
                  tooltip: 'Share selected',
                ),
              if (_selectionMode)
                IconButton(
                  onPressed: _selectedIds.isEmpty ? null : _deleteSelectedItems,
                  icon: const Icon(Icons.delete_outline, size: 20),
                  tooltip: 'Delete selected',
                ),
              if (_selectionMode)
                IconButton(
                  onPressed: _exitSelectionMode,
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: 'Exit selection',
                ),
              if (!_selectionMode) ...[
              IconButton(
                onPressed: _showFilterSheet,
                icon: const Icon(Icons.tune, size: 20),
              ),
              IconButton(
                onPressed: _showSortSheet,
                icon: const Icon(Icons.sort, size: 20),
              ),
              IconButton(
                onPressed: _showPageMenu,
                icon: const Icon(Icons.more_vert, size: 20),
              ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _searchQuery = value.trim()),
            decoration: InputDecoration(
              hintText: 'Search saved locations',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                      icon: const Icon(Icons.close),
                    )
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (_searchQuery.isNotEmpty ||
            _filter != _SavedFilter.all ||
            _sort != _SavedSort.newest ||
            _groupFilter != 'All groups')
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_searchQuery.isNotEmpty)
                  _ActiveTag(
                    label: 'Search: $_searchQuery',
                    onClear: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  ),
                if (_filter != _SavedFilter.all)
                  _ActiveTag(
                    label: 'Filter: ${_filterLabel(_filter)}',
                    onClear: () => setState(() => _filter = _SavedFilter.all),
                  ),
                if (_sort != _SavedSort.newest)
                  _ActiveTag(
                    label: 'Sort: ${_sortLabel(_sort)}',
                    onClear: () => setState(() => _sort = _SavedSort.newest),
                  ),
                if (_groupFilter != 'All groups')
                  _ActiveTag(
                    label: 'Group: $_groupFilter',
                    onClear: () => setState(() => _groupFilter = 'All groups'),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _ViewModeChip(
                        label: 'Combined',
                        icon: Icons.view_list,
                        isSelected: _viewMode == _ViewMode.combined,
                        onTap: () => _setViewMode(_ViewMode.combined),
                      ),
                      const SizedBox(width: 8),
                      _ViewModeChip(
                        label: 'Basic',
                        icon: Icons.view_agenda,
                        isSelected: _viewMode == _ViewMode.basic,
                        onTap: () => _setViewMode(_ViewMode.basic),
                      ),
                      const SizedBox(width: 8),
                      _ViewModeChip(
                        label: 'Text',
                        icon: Icons.notes,
                        isSelected: _viewMode == _ViewMode.text,
                        onTap: () => _setViewMode(_ViewMode.text),
                      ),
                      const SizedBox(width: 8),
                      _ViewModeChip(
                        label: 'Photo',
                        icon: Icons.photo_camera,
                        isSelected: _viewMode == _ViewMode.photo,
                        onTap: () => _setViewMode(_ViewMode.photo),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _toggleCompactMode,
                tooltip: _compactMode ? 'Disable compact mode' : 'Enable compact mode',
                icon: Icon(
                  _compactMode ? Icons.compress : Icons.expand,
                  color: _compactMode ? Theme.of(context).colorScheme.primary : null,
                ),
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
                      .toList();

              final filteredSorted = _applyFilterAndSort(items);
              final searched = _applySearch(filteredSorted);
              final groups = _groupOptions(items);

              return Column(
                children: [
                  if (groups.length > 1)
                    SizedBox(
                      height: 40,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        scrollDirection: Axis.horizontal,
                        itemCount: groups.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final group = groups[index];
                          return ChoiceChip(
                            label: Text(group),
                            selected: _groupFilter == group,
                            onSelected: (_) =>
                                setState(() => _groupFilter = group),
                          );
                        },
                      ),
                    ),
                  if (groups.length > 1) const SizedBox(height: 8),
                  if (authSession.isLoggedIn && !authSession.isVerified)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: _CloudInfoBanner(
                        title: 'Cloud sync is locked',
                        subtitle:
                            'Verify your email to load lands from the server.',
                        actionLabel: 'Account',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const AccountPage(),
                            ),
                          );
                        },
                      ),
                    ),
                  if (canUseCloud)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: _RemoteLandsSection(
                        landsState: remoteLandsState,
                        summaryState: remoteSummaryState,
                        compactMode: _compactMode,
                        onRefresh: _fetchRemoteData,
                        onOpenLand: _showRemoteLandDetails,
                      ),
                    ),
                  if (searched.isEmpty)
                    Expanded(
                      child: _searchQuery.isNotEmpty ||
                              _filter != _SavedFilter.all ||
                              _sort != _SavedSort.newest ||
                              _groupFilter != 'All groups'
                          ? const _EmptyState(
                              title: 'No matching saved locations',
                              subtitle:
                                  'Try changing search text, filter, sort, or group.',
                            )
                          : const _EmptyState(),
                    )
                  else
                    ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${searched.length} result${searched.length == 1 ? '' : 's'}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.black54,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: searched.length,
                      separatorBuilder: (_, _) =>
                          SizedBox(height: _compactMode ? 8 : 12),
                      itemBuilder: (context, index) {
                        final item = searched[index];
                        final id = item['id']?.toString() ?? '';
                        final isSelected = _selectedIds.contains(id);
                        return _SavedLocationCard(
                          id: id,
                          name: item['name']?.toString() ?? 'Saved location',
                          group: _groupOf(item),
                          createdAt: item['createdAt']?.toString(),
                          updatedAt: item['updatedAt']?.toString(),
                          points: (item['points'] as List?)?.length ?? 0,
                          viewMode: _viewMode,
                          compactMode: _compactMode,
                          selectionMode: _selectionMode,
                          isSelected: isSelected,
                          onTap: () {
                            if (_selectionMode) {
                              _toggleSelection(id);
                              return;
                            }
                            _showDetails(context, item);
                          },
                          onLongPress: () {
                            if (_selectionMode) {
                              _toggleSelection(id);
                              return;
                            }
                            _enterSelectionModeWith(id);
                          },
                          onMore: () {
                            if (_selectionMode) {
                              _toggleSelection(id);
                              return;
                            }
                            _showActions(context, id, item);
                          },
                        );
                      },
                    ),
                  ),
                    ],
                ],
              );
            },
          ),
        ),
      ],
      ),
    );
  }

  List<Map<String, dynamic>> _applyFilterAndSort(List<Map<String, dynamic>> src) {
    final out = src.where((item) {
      final points = (item['points'] as List?)?.length ?? 0;
      if (_groupFilter != 'All groups' && _groupOf(item) != _groupFilter) {
        return false;
      }
      switch (_filter) {
        case _SavedFilter.all:
          return true;
        case _SavedFilter.threePlusPoints:
          return points >= 3;
        case _SavedFilter.updatedOnly:
          return (item['updatedAt']?.toString().isNotEmpty ?? false);
      }
    }).toList();

    out.sort((a, b) {
      switch (_sort) {
        case _SavedSort.oldest:
          return (a['createdAt'] ?? '')
              .toString()
              .compareTo((b['createdAt'] ?? '').toString());
        case _SavedSort.nameAsc:
          return (a['name'] ?? '')
              .toString()
              .toLowerCase()
              .compareTo((b['name'] ?? '').toString().toLowerCase());
        case _SavedSort.nameDesc:
          return (b['name'] ?? '')
              .toString()
              .toLowerCase()
              .compareTo((a['name'] ?? '').toString().toLowerCase());
        case _SavedSort.pointsDesc:
          final aPoints = (a['points'] as List?)?.length ?? 0;
          final bPoints = (b['points'] as List?)?.length ?? 0;
          return bPoints.compareTo(aPoints);
        case _SavedSort.newest:
          return (b['createdAt'] ?? '')
              .toString()
              .compareTo((a['createdAt'] ?? '').toString());
      }
    });
    return out;
  }

  List<Map<String, dynamic>> _applySearch(List<Map<String, dynamic>> src) {
    if (_searchQuery.isEmpty) return src;
    final q = _searchQuery.toLowerCase();
    return src.where((item) {
      final name = item['name']?.toString().toLowerCase() ?? '';
      final created = _formatDate(item['createdAt']?.toString()).toLowerCase();
      final points = (item['points'] as List?)?.length ?? 0;
      final group = _groupOf(item).toLowerCase();
      return name.contains(q) ||
          created.contains(q) ||
          '$points'.contains(q) ||
          group.contains(q);
    }).toList();
  }

  String _groupOf(Map<String, dynamic> item) {
    final value = item['group']?.toString().trim() ?? '';
    return value.isEmpty ? 'General' : value;
  }

  List<String> _groupOptions(List<Map<String, dynamic>> items) {
    final options = <String>{'All groups'};
    for (final item in items) {
      options.add(_groupOf(item));
    }
    final sorted = options.where((e) => e != 'All groups').toList()..sort();
    return ['All groups', ...sorted];
  }

  String _filterLabel(_SavedFilter filter) {
    switch (filter) {
      case _SavedFilter.all:
        return 'All';
      case _SavedFilter.threePlusPoints:
        return '3+ points';
      case _SavedFilter.updatedOnly:
        return 'Updated only';
    }
  }

  String _sortLabel(_SavedSort sort) {
    switch (sort) {
      case _SavedSort.newest:
        return 'Newest';
      case _SavedSort.oldest:
        return 'Oldest';
      case _SavedSort.nameAsc:
        return 'Name A-Z';
      case _SavedSort.nameDesc:
        return 'Name Z-A';
      case _SavedSort.pointsDesc:
        return 'Most points';
    }
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const Text(
              'Filter',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _FilterTile(
              title: 'All saved lands',
              selected: _filter == _SavedFilter.all,
              onTap: () {
                setState(() => _filter = _SavedFilter.all);
                Navigator.pop(sheetContext);
              },
            ),
            _FilterTile(
              title: '3+ points only',
              selected: _filter == _SavedFilter.threePlusPoints,
              onTap: () {
                setState(() => _filter = _SavedFilter.threePlusPoints);
                Navigator.pop(sheetContext);
              },
            ),
            _FilterTile(
              title: 'Updated only',
              selected: _filter == _SavedFilter.updatedOnly,
              onTap: () {
                setState(() => _filter = _SavedFilter.updatedOnly);
                Navigator.pop(sheetContext);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const Text(
              'Sort',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _FilterTile(
              title: 'Newest first',
              selected: _sort == _SavedSort.newest,
              onTap: () {
                setState(() => _sort = _SavedSort.newest);
                Navigator.pop(sheetContext);
              },
            ),
            _FilterTile(
              title: 'Oldest first',
              selected: _sort == _SavedSort.oldest,
              onTap: () {
                setState(() => _sort = _SavedSort.oldest);
                Navigator.pop(sheetContext);
              },
            ),
            _FilterTile(
              title: 'Name A-Z',
              selected: _sort == _SavedSort.nameAsc,
              onTap: () {
                setState(() => _sort = _SavedSort.nameAsc);
                Navigator.pop(sheetContext);
              },
            ),
            _FilterTile(
              title: 'Name Z-A',
              selected: _sort == _SavedSort.nameDesc,
              onTap: () {
                setState(() => _sort = _SavedSort.nameDesc);
                Navigator.pop(sheetContext);
              },
            ),
            _FilterTile(
              title: 'Most points',
              selected: _sort == _SavedSort.pointsDesc,
              onTap: () {
                setState(() => _sort = _SavedSort.pointsDesc);
                Navigator.pop(sheetContext);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showPageMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.checklist_outlined),
              title: const Text('Select multiple'),
              onTap: () {
                Navigator.pop(sheetContext);
                setState(() => _selectionMode = true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.filter_alt_off_outlined),
              title: const Text('Reset filters/sort/group'),
              onTap: () {
                Navigator.pop(sheetContext);
                setState(() {
                  _filter = _SavedFilter.all;
                  _sort = _SavedSort.newest;
                  _groupFilter = 'All groups';
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined, color: Colors.red),
              title: const Text('Delete all saved lands'),
              textColor: Colors.red,
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmDeleteAll();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteAll() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete all saved lands?'),
        content: const Text('Markers will be kept. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final box = Hive.box('landbox');
              final keysToDelete = box.toMap().entries.where((entry) {
                final value = entry.value;
                if (value is! Map) return false;
                return value['entityType']?.toString() != 'marker';
              }).map((e) => e.key).toList();
              await box.deleteAll(keysToDelete);
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
  }

  void _enterSelectionModeWith(String id) {
    setState(() {
      _selectionMode = true;
      if (id.isNotEmpty) _selectedIds.add(id);
    });
  }

  void _toggleSelection(String id) {
    if (id.isEmpty) return;
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      if (_selectedIds.isEmpty) {
        _selectionMode = false;
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _shareSelectedItems() async {
    if (_selectedIds.isEmpty) return;
    final box = Hive.box('landbox');
    final out = StringBuffer();
    for (final id in _selectedIds) {
      final raw = box.get(id);
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final name = item['name']?.toString() ?? 'Saved location';
      final group = _groupOf(item);
      final points = (item['points'] as List?) ?? const [];
      final createdAt = _formatDate(item['createdAt']?.toString());
      out
        ..writeln(name)
        ..writeln('Group: $group')
        ..writeln('Points: ${points.length}')
        ..writeln('Created: $createdAt');
      for (final p in points) {
        if (p is Map) {
          out.writeln('${p['lat']},${p['lng']}');
        }
      }
      out.writeln('');
    }
    await Clipboard.setData(ClipboardData(text: out.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Selected items copied')));
  }

  void _deleteSelectedItems() {
    if (_selectedIds.isEmpty) return;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete selected locations?'),
        content: Text(
          'This will delete ${_selectedIds.length} selected item(s). This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final box = Hive.box('landbox');
              await box.deleteAll(_selectedIds.toList());
              if (!mounted) return;
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              _exitSelectionMode();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Selected items deleted')),
              );
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _setGroupForSelectedItems() {
    if (_selectedIds.isEmpty) return;
    final controller = TextEditingController(text: 'General');
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Set group for selected'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Group name',
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
              final group = controller.text.trim().isEmpty
                  ? 'General'
                  : controller.text.trim();
              final now = DateTime.now().toIso8601String();
              final box = Hive.box('landbox');
              for (final id in _selectedIds) {
                final raw = box.get(id);
                if (raw is! Map) continue;
                final item = Map<String, dynamic>.from(raw);
                item['group'] = group;
                item['updatedAt'] = now;
                await box.put(id, item);
              }
              if (!mounted) return;
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Group updated for selected items')),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
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
                  icon: Icons.folder_outlined,
                  label: 'Set group',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _setGroupForItem(context, id, item);
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
    final points = _extractLatLngPoints(item);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.82,
            minChildSize: 0.5,
            maxChildSize: 0.94,
            builder: (context, scrollController) => SingleChildScrollView(
              controller: scrollController,
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
                    '${points.length} points',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.black54),
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Group: ${_groupOf(item)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Created: ${_formatDate(item['createdAt']?.toString())}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.black54),
                  ),
                ),
                if ((item['updatedAt']?.toString().isNotEmpty ?? false))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Updated: ${_formatDate(item['updatedAt']?.toString())}',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.black54),
                    ),
                  ),
                const SizedBox(height: 16),
                if (points.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 180,
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: points.first,
                          initialZoom: 17,
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.none,
                          ),
                          cameraConstraint: CameraConstraint.contain(
                            bounds: LatLngBounds.fromPoints(points),
                          ),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.example.geo_coordinates',
                          ),
                          if (points.length >= 2)
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: points,
                                  strokeWidth: 3,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ],
                            ),
                          if (points.length >= 3)
                            PolygonLayer(
                              polygons: [
                                Polygon(
                                  points: points,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.16),
                                  borderStrokeWidth: 2,
                                  borderColor: Theme.of(
                                    context,
                                  ).colorScheme.primary,
                                ),
                              ],
                            ),
                          MarkerLayer(
                            markers: points
                                .map(
                                  (p) => Marker(
                                    width: 20,
                                    height: 20,
                                    point: p,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (points.isNotEmpty) const SizedBox(height: 16),
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
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: points.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final p = points[index];
                      return ListTile(
                        dense: true,
                        leading: Text('#${index + 1}'),
                        title: Text('${p.latitude}, ${p.longitude}'),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showRemoteLandDetails(LandListItem land) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _RemoteLandDetailSheet(
        land: land,
        onRemoteChanged: _fetchRemoteData,
      ),
    );
  }

  void _openSavedLandOnMap(BuildContext context, Map<String, dynamic> item) {
    final points = _extractLatLngPoints(item);
    if (points.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No points found for this land')),
      );
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

  void _setGroupForItem(
    BuildContext context,
    String id,
    Map<String, dynamic> item,
  ) {
    final controller = TextEditingController(text: _groupOf(item));
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Set group'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Group name',
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
              final group = controller.text.trim().isEmpty
                  ? 'General'
                  : controller.text.trim();
              final box = Hive.box('landbox');
              final raw = box.get(id);
              if (raw is! Map) return;
              final data = Map<String, dynamic>.from(raw);
              data['group'] = group;
              data['updatedAt'] = DateTime.now().toIso8601String();
              await box.put(id, data);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  List<LatLng> _extractLatLngPoints(Map<String, dynamic> item) {
    final pointsRaw = (item['points'] as List?) ?? const [];
    final points = <LatLng>[];
    for (final e in pointsRaw) {
      if (e is! Map) continue;
      final lat = (e['lat'] as num?)?.toDouble();
      final lng = (e['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      points.add(LatLng(lat, lng));
    }
    return points;
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
    final group = _groupOf(item);
    final createdAt = _formatDate(item['createdAt']?.toString());
    final updatedAt = _formatDate(item['updatedAt']?.toString());
    final hasUpdated = item['updatedAt']?.toString().isNotEmpty ?? false;
    final coords = points
        .map((p) => '${p['lat']},${p['lng']}')
        .toList()
        .join('\n');
    final text = (StringBuffer()
          ..writeln(name)
          ..writeln('Group: $group')
          ..writeln('Points: ${points.length}')
          ..writeln('Created: $createdAt')
          ..writeln(hasUpdated ? 'Updated: $updatedAt' : 'Updated: -')
          ..writeln('')
          ..writeln(coords))
        .toString();
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
  final String id;
  final String name;
  final String group;
  final String? createdAt;
  final String? updatedAt;
  final int points;
  final _ViewMode viewMode;
  final bool compactMode;
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMore;

  const _SavedLocationCard({
    required this.id,
    required this.name,
    required this.group,
    required this.createdAt,
    required this.updatedAt,
    required this.points,
    required this.viewMode,
    required this.compactMode,
    required this.selectionMode,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateText = _formatDate(createdAt);
    final updatedText = _formatDate(updatedAt);
    final hasUpdated = (updatedAt ?? '').isNotEmpty;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: EdgeInsets.all(compactMode ? 12 : 16),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : Colors.grey.withValues(alpha: 0.12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: _buildContent(theme, dateText, hasUpdated, updatedText),
      ),
    );
  }

  Widget _buildContent(
    ThemeData theme,
    String dateText,
    bool hasUpdated,
    String updatedText,
  ) {
    switch (viewMode) {
      case _ViewMode.basic:
        return _buildBasic(theme, dateText);
      case _ViewMode.text:
        return _buildText(theme, dateText);
      case _ViewMode.photo:
        return _buildPhoto(theme, dateText);
      case _ViewMode.combined:
        return _buildCombined(theme, dateText, hasUpdated, updatedText);
    }
  }

  Widget _buildCombined(
    ThemeData theme,
    String dateText,
    bool hasUpdated,
    String updatedText,
  ) {
    final subtitle = hasUpdated
        ? '$points points · Updated $updatedText'
        : '$points points · Created $dateText';
    return Row(
      children: [
        if (selectionMode) ...[
          Icon(
            isSelected ? Icons.check_circle : Icons.circle_outlined,
            color: isSelected ? theme.colorScheme.primary : Colors.black45,
          ),
          SizedBox(width: compactMode ? 8 : 10),
        ],
        Container(
          width: compactMode ? 40 : 48,
          height: compactMode ? 40 : 48,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.place, color: theme.colorScheme.primary),
        ),
        SizedBox(width: compactMode ? 10 : 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: compactMode ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: compactMode ? 2 : 4),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.black54,
                ),
              ),
              SizedBox(height: compactMode ? 0 : 2),
              Text(
                group,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        if (!selectionMode)
          IconButton(onPressed: onMore, icon: const Icon(Icons.more_vert)),
      ],
    );
  }

  Widget _buildBasic(ThemeData theme, String dateText) {
    return Row(
      children: [
        if (selectionMode) ...[
          Icon(
            isSelected ? Icons.check_circle : Icons.circle_outlined,
            color: isSelected ? theme.colorScheme.primary : Colors.black45,
          ),
          SizedBox(width: compactMode ? 8 : 10),
        ],
        Icon(Icons.place, color: theme.colorScheme.primary),
        SizedBox(width: compactMode ? 8 : 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '$points pts · $group',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.black54,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: compactMode ? 72 : 84,
          child: Text(
            dateText,
            textAlign: TextAlign.right,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.black54,
            ),
          ),
        ),
        if (!selectionMode) ...[
          SizedBox(width: compactMode ? 2 : 6),
          IconButton(onPressed: onMore, icon: const Icon(Icons.more_vert)),
        ],
      ],
    );
  }

  Widget _buildText(ThemeData theme, String dateText) {
    final updatedText = _formatDate(updatedAt);
    final hasUpdated = (updatedAt ?? '').isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (selectionMode) ...[
              Icon(
                isSelected ? Icons.check_circle : Icons.circle_outlined,
                color: isSelected ? theme.colorScheme.primary : Colors.black45,
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (!selectionMode)
              IconButton(onPressed: onMore, icon: const Icon(Icons.more_vert)),
          ],
        ),
        SizedBox(height: compactMode ? 4 : 6),
        Text(
          'Points: $points',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
        ),
        const SizedBox(height: 2),
        Text(
          'Group: $group',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Created: $dateText',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
        ),
        const SizedBox(height: 2),
        Text(
          hasUpdated ? 'Updated: $updatedText' : 'Updated: -',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
        ),
      ],
    );
  }

  Widget _buildPhoto(ThemeData theme, String dateText) {
    final topHeight = compactMode ? 92.0 : 120.0;
    final iconSize = compactMode ? 26.0 : 32.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: topHeight,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.primary.withValues(alpha: 0.22),
                theme.colorScheme.primary.withValues(alpha: 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            children: [
              Center(
                child: Icon(
                  Icons.landscape_rounded,
                  size: iconSize,
                  color: theme.colorScheme.primary.withValues(alpha: 0.7),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '$points pts',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: compactMode ? 8 : 12),
        Row(
          children: [
            if (selectionMode) ...[
              Icon(
                isSelected ? Icons.check_circle : Icons.circle_outlined,
                color: isSelected ? theme.colorScheme.primary : Colors.black45,
              ),
              const SizedBox(width: 8),
            ],
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
            if (!selectionMode)
              IconButton(onPressed: onMore, icon: const Icon(Icons.more_vert)),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '$group · $dateText',
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

class _RemoteLandsSection extends StatelessWidget {
  final AsyncValue<PaginatedLands?> landsState;
  final AsyncValue<LandSummary?> summaryState;
  final bool compactMode;
  final Future<void> Function() onRefresh;
  final ValueChanged<LandListItem> onOpenLand;

  const _RemoteLandsSection({
    required this.landsState,
    required this.summaryState,
    required this.compactMode,
    required this.onRefresh,
    required this.onOpenLand,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = summaryState.asData?.value;
    final lands = landsState.asData?.value?.items ?? const <LandListItem>[];
    final isLoading = landsState.isLoading || summaryState.isLoading;
    final error = landsState.hasError
        ? landsState.error.toString()
        : (summaryState.hasError ? summaryState.error.toString() : null);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_done_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Cloud lands',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: isLoading ? null : onRefresh,
                icon: const Icon(Icons.refresh, size: 20),
              ),
            ],
          ),
          if (summary != null) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _CloudPill(label: 'Total', value: '${summary.totalLands}'),
                _CloudPill(label: 'Synced', value: '${summary.syncedCount}'),
                _CloudPill(label: 'Pending', value: '${summary.pendingCount}'),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (error != null)
            Text(
              error,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
            )
          else if (isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (lands.isEmpty)
            Text(
              'No cloud lands found for this account.',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
            )
          else
            SizedBox(
              height: compactMode ? 170 : 190,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: lands.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) => _RemoteLandCard(
                  land: lands[index],
                  compactMode: compactMode,
                  onTap: () => onOpenLand(lands[index]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RemoteLandDetailSheet extends ConsumerStatefulWidget {
  final LandListItem land;
  final Future<void> Function() onRemoteChanged;

  const _RemoteLandDetailSheet({
    required this.land,
    required this.onRemoteChanged,
  });

  @override
  ConsumerState<_RemoteLandDetailSheet> createState() =>
      _RemoteLandDetailSheetState();
}

class _RemoteLandDetailSheetState extends ConsumerState<_RemoteLandDetailSheet> {
  bool _isDeleting = false;
  bool _isSyncing = false;

  @override
  Widget build(BuildContext context) {
    final detailState = ref.watch(remoteLandDetailProvider(widget.land.id));

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.94,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: detailState.when(
            data: (detail) => _buildLoaded(context, detail),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 36),
                  const SizedBox(height: 12),
                  Text(
                    error.toString(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => ref.invalidate(
                      remoteLandDetailProvider(widget.land.id),
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoaded(BuildContext context, LandDetail detail) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                detail.name,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              onPressed: () => ref.invalidate(
                remoteLandDetailProvider(widget.land.id),
              ),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _RemoteDetailRow(label: 'Place', value: detail.place ?? '—'),
        _RemoteDetailRow(label: 'Phone', value: detail.phone ?? '—'),
        _RemoteDetailRow(
          label: 'Area',
          value: detail.area == null ? '—' : detail.area!.toStringAsFixed(2),
        ),
        _RemoteDetailRow(
          label: 'Perimeter',
          value: detail.perimeter == null
              ? '—'
              : detail.perimeter!.toStringAsFixed(2),
        ),
        _RemoteDetailRow(label: 'Sync', value: detail.syncStatus),
        _RemoteDetailRow(
          label: 'Created',
          value: _formatStaticDate(detail.createdAt),
        ),
        _RemoteDetailRow(
          label: 'Updated',
          value: _formatStaticDate(detail.updatedAt),
        ),
        if ((detail.description ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            detail.description!,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _CloudPill(label: 'Points', value: '${detail.points.length}'),
            _CloudPill(label: 'Markers', value: '${detail.markers.length}'),
            _CloudPill(label: 'Media', value: '${detail.media.length}'),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isSyncing ? null : () => _markSynced(detail),
                icon: _isSyncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_done_outlined),
                label: const Text('Mark synced'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _showEditMetadataSheet(detail),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isDeleting ? null : () => _deleteLand(detail),
            icon: _isDeleting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline, color: Colors.red),
            label: const Text(
              'Delete land',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                'Markers',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => _showMarkerSheet(detail),
              icon: const Icon(Icons.add),
              label: const Text('Add marker'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (detail.markers.isEmpty)
          Text(
            'No cloud markers found for this land.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.black54,
            ),
          )
        else
          ...detail.markers.map(
            (marker) => ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.place_outlined),
              title: Text(marker.name),
              subtitle: Text(
                '${marker.latitude?.toStringAsFixed(6) ?? '—'}, ${marker.longitude?.toStringAsFixed(6) ?? '—'}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _showMarkerSheet(detail, marker: marker),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _deleteMarker(detail, marker),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _markSynced(LandDetail detail) async {
    final session = ref.read(authSessionProvider);
    final token = session.token.trim();
    if (token.isEmpty) return;

    setState(() => _isSyncing = true);
    try {
      await ref.read(landCloudServiceProvider).markLandSynced(token, detail.id);
      ref.invalidate(remoteLandDetailProvider(detail.id));
      await widget.onRemoteChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Land marked as synced')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _deleteLand(LandDetail detail) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete cloud land?'),
        content: Text('This will delete "${detail.name}" from the server.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final session = ref.read(authSessionProvider);
    final token = session.token.trim();
    if (token.isEmpty) return;

    setState(() => _isDeleting = true);
    try {
      await ref.read(landCloudServiceProvider).deleteLand(token, detail.id);
      await widget.onRemoteChanged();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cloud land deleted')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
    }
  }

  Future<void> _showEditMetadataSheet(LandDetail detail) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditRemoteLandSheet(
        land: detail,
        onSaved: () async {
          ref.invalidate(remoteLandDetailProvider(detail.id));
          await widget.onRemoteChanged();
        },
      ),
    );
  }

  Future<void> _showMarkerSheet(
    LandDetail detail, {
    LandMarker? marker,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditRemoteMarkerSheet(
        land: detail,
        marker: marker,
        onSaved: () async {
          ref.invalidate(remoteLandDetailProvider(detail.id));
          await widget.onRemoteChanged();
        },
      ),
    );
  }

  Future<void> _deleteMarker(LandDetail detail, LandMarker marker) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete marker?'),
        content: Text('This will delete marker "${marker.name}".'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final token = ref.read(authSessionProvider).token.trim();
    if (token.isEmpty) return;

    try {
      await ref
          .read(landCloudServiceProvider)
          .deleteMarker(token, detail.id, marker.id);
      ref.invalidate(remoteLandDetailProvider(detail.id));
      await widget.onRemoteChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marker deleted')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _EditRemoteLandSheet extends ConsumerStatefulWidget {
  final LandDetail land;
  final Future<void> Function() onSaved;

  const _EditRemoteLandSheet({
    required this.land,
    required this.onSaved,
  });

  @override
  ConsumerState<_EditRemoteLandSheet> createState() =>
      _EditRemoteLandSheetState();
}

class _EditRemoteLandSheetState extends ConsumerState<_EditRemoteLandSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _placeController;
  late final TextEditingController _phoneController;
  late final TextEditingController _descriptionController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.land.name);
    _placeController = TextEditingController(text: widget.land.place ?? '');
    _phoneController = TextEditingController(text: widget.land.phone ?? '');
    _descriptionController = TextEditingController(
      text: widget.land.description ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _placeController.dispose();
    _phoneController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final token = ref.read(authSessionProvider).token.trim();
    if (token.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      await ref.read(landCloudServiceProvider).updateLand(
            token,
            widget.land.id,
            UpdateLandRequest(
              name: _nameController.text.trim(),
              place: _placeController.text.trim(),
              phone: _phoneController.text.trim(),
              description: _descriptionController.text.trim(),
            ),
          );
      await widget.onSaved();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Land metadata updated')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 12, 12, bottomInset + 12),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
          ),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Edit cloud land',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (value) =>
                        value == null || value.trim().isEmpty
                        ? 'Name is required'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _placeController,
                    decoration: const InputDecoration(labelText: 'Place'),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(labelText: 'Phone'),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _descriptionController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _submit,
                      child: _isSaving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Save changes'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EditRemoteMarkerSheet extends ConsumerStatefulWidget {
  final LandDetail land;
  final LandMarker? marker;
  final Future<void> Function() onSaved;

  const _EditRemoteMarkerSheet({
    required this.land,
    required this.onSaved,
    this.marker,
  });

  @override
  ConsumerState<_EditRemoteMarkerSheet> createState() =>
      _EditRemoteMarkerSheetState();
}

class _EditRemoteMarkerSheetState extends ConsumerState<_EditRemoteMarkerSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _latitudeController;
  late final TextEditingController _longitudeController;
  late final TextEditingController _altitudeController;
  late final TextEditingController _propertiesController;
  String _markerType = 'pin';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final marker = widget.marker;
    _nameController = TextEditingController(text: marker?.name ?? '');
    _descriptionController = TextEditingController(
      text: marker?.description ?? '',
    );
    _latitudeController = TextEditingController(
      text: marker?.latitude?.toString() ?? '',
    );
    _longitudeController = TextEditingController(
      text: marker?.longitude?.toString() ?? '',
    );
    _altitudeController = TextEditingController(
      text: marker?.altitude?.toString() ?? '',
    );
    _propertiesController = TextEditingController(
      text: marker?.properties ?? '',
    );
    _markerType = (marker?.markerType ?? 'pin').trim().isEmpty
        ? 'pin'
        : marker!.markerType!;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _altitudeController.dispose();
    _propertiesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final token = ref.read(authSessionProvider).token.trim();
    if (token.isEmpty) return;

    final latitude = double.tryParse(_latitudeController.text.trim());
    final longitude = double.tryParse(_longitudeController.text.trim());
    final altitude = double.tryParse(_altitudeController.text.trim());
    if (latitude == null || longitude == null) return;

    setState(() => _isSaving = true);
    try {
      if (widget.marker == null) {
        await ref.read(landCloudServiceProvider).createMarker(
              token,
              widget.land.id,
              LandMarkerRequest(
                name: _nameController.text.trim(),
                description: _descriptionController.text.trim(),
                latitude: latitude,
                longitude: longitude,
                altitude: altitude,
                markerType: _markerType,
                properties: _propertiesController.text.trim(),
              ),
            );
      } else {
        await ref.read(landCloudServiceProvider).updateMarker(
              token,
              widget.land.id,
              widget.marker!.id,
              UpdateLandMarkerRequest(
                name: _nameController.text.trim(),
                description: _descriptionController.text.trim(),
                latitude: latitude,
                longitude: longitude,
                altitude: altitude,
                markerType: _markerType,
                properties: _propertiesController.text.trim(),
              ),
            );
      }
      await widget.onSaved();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.marker == null
                ? 'Marker created successfully'
                : 'Marker updated successfully',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 12, 12, bottomInset + 12),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
          ),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    widget.marker == null ? 'Add marker' : 'Edit marker',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (value) =>
                        value == null || value.trim().isEmpty
                        ? 'Name is required'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _latitudeController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Latitude',
                          ),
                          validator: (value) {
                            final parsed = double.tryParse(value?.trim() ?? '');
                            if (parsed == null) return 'Required';
                            if (parsed < -90 || parsed > 90) {
                              return '-90 to 90';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _longitudeController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Longitude',
                          ),
                          validator: (value) {
                            final parsed = double.tryParse(value?.trim() ?? '');
                            if (parsed == null) return 'Required';
                            if (parsed < -180 || parsed > 180) {
                              return '-180 to 180';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _altitudeController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Altitude',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _markerType,
                          decoration: const InputDecoration(
                            labelText: 'Marker type',
                          ),
                          items: const [
                            DropdownMenuItem(value: 'pin', child: Text('Pin')),
                            DropdownMenuItem(
                              value: 'waypoint',
                              child: Text('Waypoint'),
                            ),
                            DropdownMenuItem(
                              value: 'checkpoint',
                              child: Text('Checkpoint'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _markerType = value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _propertiesController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Properties JSON',
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _submit,
                      child: _isSaving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              widget.marker == null
                                  ? 'Create marker'
                                  : 'Save marker',
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RemoteLandCard extends StatelessWidget {
  final LandListItem land;
  final bool compactMode;
  final VoidCallback onTap;

  const _RemoteLandCard({
    required this.land,
    required this.compactMode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: compactMode ? 220 : 250,
        padding: EdgeInsets.all(compactMode ? 12 : 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.cloud_outlined,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const Spacer(),
                Text(
                  land.syncStatus,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              land.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              land.place ?? 'No place',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
            ),
            const Spacer(),
            Text(
              '${land.pointsCount} pts · ${land.markersCount} markers',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: 2),
            Text(
              _formatStaticDate(land.updatedAt ?? land.createdAt),
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.black45),
            ),
          ],
        ),
      ),
    );
  }
}

class _CloudPill extends StatelessWidget {
  final String label;
  final String value;

  const _CloudPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CloudInfoBanner extends StatelessWidget {
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;

  const _CloudInfoBanner({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFE2B8)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Color(0xFFB26A00)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onTap, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _RemoteDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _RemoteDetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

String _formatStaticDate(String? iso) {
  if (iso == null || iso.isEmpty) return 'Unknown';
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return 'Unknown';
  final yyyy = parsed.year.toString().padLeft(4, '0');
  final mm = parsed.month.toString().padLeft(2, '0');
  final dd = parsed.day.toString().padLeft(2, '0');
  return '$dd/$mm/$yyyy';
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

class _FilterTile extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _FilterTile({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      trailing: selected
          ? const Icon(Icons.check_circle, color: Color(0xFF0B8A8D))
          : const Icon(Icons.circle_outlined),
      onTap: onTap,
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;

  const _EmptyState({
    this.title = 'No saved locations',
    this.subtitle = 'Your saved places will appear here.',
  });

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
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.black45),
          ),
        ],
      ),
    );
  }
}

class _ActiveTag extends StatelessWidget {
  final String label;
  final VoidCallback onClear;

  const _ActiveTag({required this.label, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0B8A8D).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0B8A8D),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onClear,
            child: const Icon(Icons.close, size: 14, color: Color(0xFF0B8A8D)),
          ),
        ],
      ),
    );
  }
}
