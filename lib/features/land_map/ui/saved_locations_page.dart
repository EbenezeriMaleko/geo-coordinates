import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

import '../../auth/models/auth_models.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/land_api_models.dart';
import '../models/reference_ellipsoid.dart';
import '../providers/land_cloud_provider.dart';
import '../state/land_map_notifier.dart';
import '../state/land_map_state.dart';
import '../state/settings_provider.dart';
import '../services/utm_converter.dart';

enum _ViewMode { combined, basic, text, photo }

enum _SavedSort { newest, oldest, nameAsc, nameDesc, pointsDesc }

enum _SavedFilter { all, threePlusPoints, updatedOnly }

enum _SavedContentSection { all, markers, fields, distances }

enum SavedLocationsToolbarAction {
  filter,
  sort,
  menu,
  setGroup,
  share,
  delete,
  exitSelection,
}

class SavedLocationsToolbarController extends ChangeNotifier {
  _SavedLocationsPageState? _state;

  void attach(_SavedLocationsPageState state) {
    _state = state;
    notifyListeners();
  }

  void detach(_SavedLocationsPageState state) {
    if (_state == state) {
      _state = null;
      notifyListeners();
    }
  }

  bool get isSelectionMode => _state?._selectionMode ?? false;

  int get selectedCount => _state?._selectedIds.length ?? 0;

  bool get hasSelection => (_state?._selectedIds.isNotEmpty ?? false);

  void dispatch(SavedLocationsToolbarAction action) {
    _state?.dispatchToolbarAction(action);
  }

  void refresh() {
    notifyListeners();
  }
}

String _navigationKind(String rawKind, int pointsCount) {
  final kind = rawKind.toLowerCase().trim();
  if (kind == 'marker' || kind == 'point') return 'point';
  if (kind == 'distance' || kind == 'line' || kind == 'polyline') {
    return 'polyline';
  }
  if (kind == 'field' || kind == 'area' || kind == 'polygon') {
    return 'polygon';
  }
  if (pointsCount >= 3) return 'polygon';
  if (pointsCount == 2) return 'polyline';
  return 'point';
}

class SavedLocationsPage extends ConsumerStatefulWidget {
  final VoidCallback? onOpenMapRequested;
  final VoidCallback? onToolbarStateChanged;
  final bool showEmbeddedToolbar;
  final SavedLocationsToolbarController? toolbarController;

  const SavedLocationsPage({
    super.key,
    this.onOpenMapRequested,
    this.onToolbarStateChanged,
    this.toolbarController,
    this.showEmbeddedToolbar = true,
  });

  @override
  ConsumerState<SavedLocationsPage> createState() => _SavedLocationsPageState();
}

typedef SavedLocationsPageState = _SavedLocationsPageState;

class _SavedLocationsPageState extends ConsumerState<SavedLocationsPage> {
  static const String _prefViewModeKey = 'prefs_saved_locations_view_mode';
  static const String _prefCompactModeKey =
      'prefs_saved_locations_compact_mode';

  _ViewMode _viewMode = _ViewMode.combined;
  _SavedSort _sort = _SavedSort.newest;
  _SavedFilter _filter = _SavedFilter.all;
  _SavedContentSection _contentSection = _SavedContentSection.all;
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
    widget.toolbarController?.attach(this);
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
    widget.toolbarController?.detach(this);
    _authSubscription?.close();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchRemoteData() async {
    final session = ref.read(authSessionProvider);
    if (!session.isLoggedIn || !session.isVerified) return;
    await ref
        .read(remoteLandsProvider.notifier)
        .fetch(search: _searchQuery.isEmpty ? null : _searchQuery);
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

  _ViewMode _viewModeFromStorage(String raw) {
    for (final mode in _ViewMode.values) {
      if (mode.name == raw) return mode;
    }
    return _ViewMode.combined;
  }

  bool get isSelectionMode => _selectionMode;

  int get selectedCount => _selectedIds.length;

  bool get hasSelection => _selectedIds.isNotEmpty;

  void dispatchToolbarAction(SavedLocationsToolbarAction action) {
    switch (action) {
      case SavedLocationsToolbarAction.filter:
        _showFilterSheet();
      case SavedLocationsToolbarAction.sort:
        _showSortSheet();
      case SavedLocationsToolbarAction.menu:
        _showPageMenu();
      case SavedLocationsToolbarAction.setGroup:
        if (hasSelection) {
          _setGroupForSelectedItems();
        }
      case SavedLocationsToolbarAction.share:
        if (hasSelection) {
          _shareSelectedItems();
        }
      case SavedLocationsToolbarAction.delete:
        if (hasSelection) {
          _deleteSelectedItems();
        }
      case SavedLocationsToolbarAction.exitSelection:
        _exitSelectionMode();
    }
  }

  void _notifyToolbarStateChanged() {
    widget.toolbarController?.refresh();
    widget.onToolbarStateChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final box = Hive.box('landbox');
    final authSession = ref.watch(authSessionProvider);
    final remoteLandsState = ref.watch(remoteLandsProvider);
    final canUseCloud = authSession.isLoggedIn && authSession.isVerified;

    return Container(
      color: Colors.white70,
      child: Column(
        children: [
          if (widget.showEmbeddedToolbar)
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
                      onPressed: _selectedIds.isEmpty
                          ? null
                          : _shareSelectedItems,
                      icon: const Icon(Icons.share_outlined, size: 20),
                      tooltip: 'Share selected',
                    ),
                  if (_selectionMode)
                    IconButton(
                      onPressed: _selectedIds.isEmpty
                          ? null
                          : _deleteSelectedItems,
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
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() => _searchQuery = value.trim());
                if (canUseCloud) {
                  _fetchRemoteData();
                }
              },
              decoration: InputDecoration(
                hintText: 'Search saved locations',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                          if (canUseCloud) {
                            _fetchRemoteData();
                          }
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
                      onClear: () =>
                          setState(() => _groupFilter = 'All groups'),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: box.listenable(),
              builder: (context, Box box, _) {
                final localItems = box.values
                    .whereType<Map>()
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList();

                final remoteItems =
                    remoteLandsState.asData?.value?.items ??
                    const <LandListItem>[];
                final items = _buildDisplayItems(
                  localItems: localItems,
                  remoteItems: remoteItems,
                  canUseCloud: canUseCloud,
                );

                final counts = _contentCounts(items);
                final sectioned = _applyContentSection(items);
                final filteredSorted = _applyFilterAndSort(sectioned);
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
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _SectionChip(
                              label: 'All',
                              count: items.length,
                              selected:
                                  _contentSection == _SavedContentSection.all,
                              onTap: () => setState(
                                () =>
                                    _contentSection = _SavedContentSection.all,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _SectionChip(
                              label: 'Markers',
                              count: counts.markers,
                              selected:
                                  _contentSection ==
                                  _SavedContentSection.markers,
                              onTap: () => setState(
                                () => _contentSection =
                                    _SavedContentSection.markers,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _SectionChip(
                              label: 'Fields',
                              count: counts.fields,
                              selected:
                                  _contentSection ==
                                  _SavedContentSection.fields,
                              onTap: () => setState(
                                () => _contentSection =
                                    _SavedContentSection.fields,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _SectionChip(
                              label: 'Distance',
                              count: counts.distances,
                              selected:
                                  _contentSection ==
                                  _SavedContentSection.distances,
                              onTap: () => setState(
                                () => _contentSection =
                                    _SavedContentSection.distances,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (searched.isEmpty)
                      Expanded(
                        child:
                            _searchQuery.isNotEmpty ||
                                _filter != _SavedFilter.all ||
                                _sort != _SavedSort.newest ||
                                _groupFilter != 'All groups' ||
                                _contentSection != _SavedContentSection.all
                            ? const _EmptyState(
                                title: 'No matching saved locations',
                                subtitle:
                                    'Try changing search text, filter, sort, or group.',
                              )
                            : const _EmptyState(),
                      )
                    else ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${searched.length} result${searched.length == 1 ? '' : 's'}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
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
                            final id = _selectionKey(item);
                            final isSelected = _selectedIds.contains(id);
                            final isRemote = _isRemoteItem(item);
                            return _SavedLocationCard(
                              id: id,
                              name:
                                  item['name']?.toString() ??
                                  item['place']?.toString() ??
                                  'Saved location',
                              group: _groupOf(item),
                              createdAt: item['createdAt']?.toString(),
                              updatedAt: item['updatedAt']?.toString(),
                              points: _pointsCount(item),
                              isCloudSynced: _isCloudSynced(item),
                              viewMode: _viewMode,
                              compactMode: _compactMode,
                              selectionMode: _selectionMode,
                              isSelected: isSelected,
                              onTap: () {
                                if (_selectionMode) {
                                  _toggleSelection(id);
                                  return;
                                }
                                if (isRemote) {
                                  final remoteLand = _remoteLandFromItem(item);
                                  if (remoteLand != null) {
                                    _showRemoteLandDetails(remoteLand);
                                    return;
                                  }
                                }
                                final linkedCloudId = _linkedCloudId(item);
                                if (linkedCloudId != null && canUseCloud) {
                                  _openCloudDetailsById(
                                    linkedCloudId,
                                    fallbackName:
                                        item['name']?.toString() ??
                                        'Cloud land',
                                  );
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
                                _showActions(
                                  context,
                                  id,
                                  item,
                                  isRemote: isRemote,
                                );
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

  List<Map<String, dynamic>> _applyFilterAndSort(
    List<Map<String, dynamic>> src,
  ) {
    final out = src.where((item) {
      final points = _pointsCount(item);
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
          return (a['createdAt'] ?? '').toString().compareTo(
            (b['createdAt'] ?? '').toString(),
          );
        case _SavedSort.nameAsc:
          return (a['name'] ?? '').toString().toLowerCase().compareTo(
            (b['name'] ?? '').toString().toLowerCase(),
          );
        case _SavedSort.nameDesc:
          return (b['name'] ?? '').toString().toLowerCase().compareTo(
            (a['name'] ?? '').toString().toLowerCase(),
          );
        case _SavedSort.pointsDesc:
          final aPoints = _pointsCount(a);
          final bPoints = _pointsCount(b);
          return bPoints.compareTo(aPoints);
        case _SavedSort.newest:
          return (b['createdAt'] ?? '').toString().compareTo(
            (a['createdAt'] ?? '').toString(),
          );
      }
    });
    return out;
  }

  List<Map<String, dynamic>> _applySearch(List<Map<String, dynamic>> src) {
    if (_searchQuery.isEmpty) return src;
    final q = _searchQuery.toLowerCase();
    return src.where((item) {
      final name = item['name']?.toString().toLowerCase() ?? '';
      final place = item['place']?.toString().toLowerCase() ?? '';
      final created = _formatDate(item['createdAt']?.toString()).toLowerCase();
      final points = _pointsCount(item);
      final group = _groupOf(item).toLowerCase();
      return name.contains(q) ||
          place.contains(q) ||
          created.contains(q) ||
          '$points'.contains(q) ||
          group.contains(q);
    }).toList();
  }

  List<Map<String, dynamic>> _applyContentSection(
    List<Map<String, dynamic>> src,
  ) {
    switch (_contentSection) {
      case _SavedContentSection.all:
        return src;
      case _SavedContentSection.markers:
        return src
            .where((item) => _sectionOf(item) == _SavedContentSection.markers)
            .toList();
      case _SavedContentSection.fields:
        return src
            .where((item) => _sectionOf(item) == _SavedContentSection.fields)
            .toList();
      case _SavedContentSection.distances:
        return src
            .where((item) => _sectionOf(item) == _SavedContentSection.distances)
            .toList();
    }
  }

  _SavedContentSection _sectionOf(Map<String, dynamic> item) {
    final rawType =
        (item['entityType']?.toString() ?? item['type']?.toString() ?? '')
            .toLowerCase()
            .trim();
    if (rawType == 'marker' || rawType == 'point') {
      return _SavedContentSection.markers;
    }
    if (rawType == 'polyline' || rawType == 'line' || rawType == 'distance') {
      return _SavedContentSection.distances;
    }
    if (rawType == 'polygon' || rawType == 'field' || rawType == 'area') {
      return _SavedContentSection.fields;
    }

    final points = _pointsCount(item);
    if (points <= 1) return _SavedContentSection.markers;
    if (points == 2) return _SavedContentSection.distances;
    return _SavedContentSection.fields;
  }

  ({int markers, int fields, int distances}) _contentCounts(
    List<Map<String, dynamic>> items,
  ) {
    var markers = 0;
    var fields = 0;
    var distances = 0;
    for (final item in items) {
      switch (_sectionOf(item)) {
        case _SavedContentSection.markers:
          markers++;
          break;
        case _SavedContentSection.fields:
          fields++;
          break;
        case _SavedContentSection.distances:
          distances++;
          break;
        case _SavedContentSection.all:
          break;
      }
    }
    return (markers: markers, fields: fields, distances: distances);
  }

  String _groupOf(Map<String, dynamic> item) {
    if (_isRemoteItem(item)) {
      return 'Cloud';
    }
    final value = item['group']?.toString().trim() ?? '';
    return value.isEmpty ? 'General' : value;
  }

  bool _isCloudSynced(Map<String, dynamic> item) {
    if (_isRemoteItem(item)) return true;

    final cloudId = item['cloudId']?.toString().trim() ?? '';
    return cloudId.isNotEmpty;
  }

  List<Map<String, dynamic>> _buildDisplayItems({
    required List<Map<String, dynamic>> localItems,
    required List<LandListItem> remoteItems,
    required bool canUseCloud,
  }) {
    if (!canUseCloud || remoteItems.isEmpty) {
      return localItems;
    }

    final remoteIds = remoteItems.map((e) => e.id).toSet();
    final merged = <Map<String, dynamic>>[];

    for (final remote in remoteItems) {
      merged.add(_remoteLandToDisplayItem(remote));
    }

    for (final local in localItems) {
      final cloudId = local['cloudId']?.toString().trim() ?? '';
      final localId = local['id']?.toString().trim() ?? '';
      if (cloudId.isNotEmpty && remoteIds.contains(cloudId)) {
        continue;
      }
      if (localId.isNotEmpty && remoteIds.contains(localId)) {
        continue;
      }
      merged.add(local);
    }

    return merged;
  }

  Map<String, dynamic> _remoteLandToDisplayItem(LandListItem remote) {
    return {
      'id': remote.id,
      'entityType': remote.type,
      'type': remote.type,
      'name': remote.name,
      'place': remote.place,
      'phone': remote.phone,
      'description': remote.description,
      'createdAt': remote.createdAt,
      'updatedAt': remote.updatedAt,
      'area': remote.area,
      'perimeter': remote.perimeter,
      'pointsCount': remote.pointsCount,
      'markersCount': remote.markersCount,
      'mediaCount': remote.mediaCount,
      '__isRemote': true,
    };
  }

  bool _isRemoteItem(Map<String, dynamic> item) {
    return item['__isRemote'] == true;
  }

  String _selectionKey(Map<String, dynamic> item) {
    final id = item['id']?.toString() ?? '';
    return _isRemoteItem(item) ? 'remote:$id' : id;
  }

  int _pointsCount(Map<String, dynamic> item) {
    final points = item['points'];
    if (points is List) return points.length;
    final lat = item['lat'];
    final lng = item['lng'];
    if (lat is num && lng is num) return 1;
    return (item['pointsCount'] as num?)?.toInt() ?? 0;
  }

  LandListItem? _remoteLandFromItem(Map<String, dynamic> item) {
    if (!_isRemoteItem(item)) return null;
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty) return null;

    return LandListItem(
      id: id,
      userId: '',
      type:
          item['type']?.toString() ??
          item['entityType']?.toString() ??
          'polygon',
      name: item['name']?.toString() ?? '',
      place: item['place']?.toString(),
      phone: item['phone']?.toString(),
      area: (item['area'] as num?)?.toDouble(),
      perimeter: (item['perimeter'] as num?)?.toDouble(),
      description: item['description']?.toString(),
      pointsCount: _pointsCount(item),
      markersCount: (item['markersCount'] as num?)?.toInt() ?? 0,
      mediaCount: (item['mediaCount'] as num?)?.toInt() ?? 0,
      createdAt: item['createdAt']?.toString(),
      updatedAt: item['updatedAt']?.toString(),
    );
  }

  String? _linkedCloudId(Map<String, dynamic> item) {
    final cloudId = item['cloudId']?.toString().trim() ?? '';
    if (cloudId.isNotEmpty) return cloudId;

    return null;
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
              leading: const Icon(
                Icons.delete_sweep_outlined,
                color: Colors.red,
              ),
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
        content: const Text(
          'Markers will be kept. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final box = Hive.box('landbox');
              final keysToDelete = box
                  .toMap()
                  .entries
                  .where((entry) {
                    final value = entry.value;
                    if (value is! Map) return false;
                    return value['entityType']?.toString() != 'marker';
                  })
                  .map((e) => e.key)
                  .toList();
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
    _notifyToolbarStateChanged();
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
    _notifyToolbarStateChanged();
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
    _notifyToolbarStateChanged();
  }

  Future<void> _shareSelectedItems() async {
    if (_selectedIds.isEmpty) return;
    final box = Hive.box('landbox');
    final blocks = <String>[];
    for (final selectionId in _selectedIds) {
      final block = await _shareBlockForSelection(selectionId, box);
      if (block != null && block.trim().isNotEmpty) {
        blocks.add(block.trimRight());
      }
    }

    if (blocks.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Nothing to share')));
      }
      return;
    }

    await SharePlus.instance.share(
      ShareParams(text: blocks.join('\n\n---\n\n')),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Selected items shared')));
  }

  Future<void> _deleteSelectedItems() async {
    if (_selectedIds.isEmpty) return;
    final selectedCount = _selectedIds.length;
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
              final session = ref.read(authSessionProvider);
              final token = session.token.trim();
              final cloudIdsToDelete = <String>{};
              final localKeysToDelete = <dynamic>{};

              for (final selectionId in _selectedIds) {
                if (selectionId.startsWith('remote:')) {
                  final landId = selectionId.substring('remote:'.length).trim();
                  if (landId.isNotEmpty) {
                    cloudIdsToDelete.add(landId);
                  }
                  continue;
                }

                final raw = box.get(selectionId);
                if (raw is! Map) continue;
                final item = Map<String, dynamic>.from(raw);
                localKeysToDelete.add(selectionId);
                final linkedCloudId = _linkedCloudId(item);
                if (linkedCloudId != null) {
                  cloudIdsToDelete.add(linkedCloudId);
                }
              }

              if (cloudIdsToDelete.isNotEmpty && token.isEmpty) {
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Sign in again to delete cloud records.'),
                    ),
                  );
                }
                return;
              }

              for (final landId in cloudIdsToDelete) {
                await ref
                    .read(landCloudServiceProvider)
                    .deleteLand(token, landId);
                final matchingKeys = box
                    .toMap()
                    .entries
                    .where((entry) {
                      final value = entry.value;
                      if (value is! Map) return false;
                      final raw = Map<String, dynamic>.from(value);
                      final localId = raw['id']?.toString().trim() ?? '';
                      final cloudId = raw['cloudId']?.toString().trim() ?? '';
                      return localId == landId || cloudId == landId;
                    })
                    .map((entry) => entry.key);
                localKeysToDelete.addAll(matchingKeys);
              }

              if (localKeysToDelete.isNotEmpty) {
                await box.deleteAll(localKeysToDelete.toList());
              }

              await _fetchRemoteData();
              if (!mounted) return;
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              _exitSelectionMode();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Deleted $selectedCount selected item${selectedCount == 1 ? '' : 's'}',
                  ),
                ),
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
        backgroundColor: Colors.white,
        title: Text(
          'Set group for selected',
          style: TextStyle(fontSize: 18, color: Color(0xFF111827)),
        ),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Group name',
            labelStyle: TextStyle(color: Colors.grey.shade600),
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
                const SnackBar(
                  content: Text('Group updated for selected items'),
                ),
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
    Map<String, dynamic> item, {
    required bool isRemote,
  }) {
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
                  icon: isRemote
                      ? Icons.visibility_outlined
                      : Icons.map_outlined,
                  label: isRemote ? 'View cloud details' : 'Go to',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    if (isRemote) {
                      final remoteLand = _remoteLandFromItem(item);
                      if (remoteLand != null) {
                        _showRemoteLandDetails(remoteLand);
                      }
                    } else {
                      _goToSavedItem(context, item);
                    }
                  },
                ),
                if (!isRemote)
                  _ActionTile(
                    icon: Icons.edit,
                    label: 'Rename',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _renameItem(context, id, item['name']?.toString() ?? '');
                    },
                  ),
                if (!isRemote)
                  _ActionTile(
                    icon: Icons.copy,
                    label: 'Copy coordinates',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _copyCoordinates(context, item);
                    },
                  ),
                if (!isRemote)
                  _ActionTile(
                    icon: Icons.share,
                    label: 'Share',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _shareItem(context, item);
                    },
                  ),
                if (!isRemote)
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
                    _deleteItem(context, id, item: item, isRemote: isRemote);
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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => _LandDetailSheet(
        localItem: item,
        onOpenMapRequested: widget.onOpenMapRequested,
      ),
    );
  }

  void _goToSavedItem(BuildContext context, Map<String, dynamic> item) {
    final target = _buildNavigationTarget(item);
    if (target == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No points found for guidance')),
      );
      return;
    }

    ref.read(landMapProvider.notifier).setNavigationTarget(target);
    widget.onOpenMapRequested?.call();
  }

  LandNavigationTarget? _buildNavigationTarget(Map<String, dynamic> item) {
    final points = _extractLatLngPoints(item);
    if (points.isEmpty) return null;
    final pointLabels = _extractPointLabels(item, points.length);

    final representative = _representativePoint(points);
    final label = item['name']?.toString().trim().isNotEmpty == true
        ? item['name'].toString().trim()
        : 'Saved location';
    final kind = item['entityType']?.toString().trim().isNotEmpty == true
        ? item['entityType'].toString().trim()
        : item['type']?.toString().trim().isNotEmpty == true
        ? item['type'].toString().trim()
        : 'land';

    return LandNavigationTarget(
      point: representative,
      points: points,
      pointLabels: pointLabels,
      label: label,
      kind: _navigationKind(kind, points.length),
    );
  }

  LatLng _representativePoint(List<LatLng> points) {
    if (points.length == 1) return points.first;

    final lat =
        points.fold<double>(0, (sum, point) => sum + point.latitude) /
        points.length;
    final lng =
        points.fold<double>(0, (sum, point) => sum + point.longitude) /
        points.length;
    return LatLng(lat, lng);
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
    if (points.isEmpty) {
      final lat = (item['lat'] as num?)?.toDouble();
      final lng = (item['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        points.add(LatLng(lat, lng));
      }
    }
    return points;
  }

  List<String> _extractPointLabels(Map<String, dynamic> item, int pointsCount) {
    if (pointsCount <= 0) return const [];

    final labels = List<String>.filled(pointsCount, '');
    final pointsRaw = (item['points'] as List?) ?? const [];
    for (int i = 0; i < pointsRaw.length && i < pointsCount; i++) {
      final point = pointsRaw[i];
      if (point is! Map) continue;
      final raw = point['label']?.toString().trim() ?? '';
      if (raw.isNotEmpty) {
        labels[i] = raw;
      }
    }

    final topLevel = (item['labels'] as List?) ?? const [];
    for (int i = 0; i < topLevel.length && i < pointsCount; i++) {
      if (labels[i].isNotEmpty) continue;
      final raw = topLevel[i]?.toString().trim() ?? '';
      if (raw.isNotEmpty) {
        labels[i] = raw;
      }
    }

    for (int i = 0; i < pointsCount; i++) {
      if (labels[i].isEmpty) {
        labels[i] = '${i + 1}';
      }
    }
    return labels;
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

  void _showRemoteLandDetails(LandListItem land) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => _LandDetailSheet(
        cloudItem: land,
        onRemoteChanged: _fetchRemoteData,
        onOpenMapRequested: widget.onOpenMapRequested,
      ),
    );
  }

  void _openCloudDetailsById(String landId, {required String fallbackName}) {
    final lands =
        ref.read(remoteLandsProvider).asData?.value?.items ??
        const <LandListItem>[];
    LandListItem? matched;
    for (final land in lands) {
      if (land.id == landId) {
        matched = land;
        break;
      }
    }
    if (matched != null) {
      _showRemoteLandDetails(matched);
      return;
    }

    _showRemoteLandDetails(
      LandListItem(
        id: landId,
        userId: '',
        type: 'polygon',
        name: fallbackName,
        place: null,
        phone: null,
        area: null,
        perimeter: null,
        description: null,
        pointsCount: 0,
        markersCount: 0,
        mediaCount: 0,
        createdAt: null,
        updatedAt: null,
      ),
    );
  }

  void _deleteItem(
    BuildContext context,
    String id, {
    required Map<String, dynamic> item,
    required bool isRemote,
  }) {
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
              if (isRemote) {
                await _deleteCloudItem(item);
              } else {
                final linkedCloudId = _linkedCloudId(item);
                if (linkedCloudId != null) {
                  await _deleteCloudItem({
                    'id': linkedCloudId,
                    'name': item['name'],
                  });
                }
                final box = Hive.box('landbox');
                await box.delete(id);
              }
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCloudItem(Map<String, dynamic> item) async {
    final session = ref.read(authSessionProvider);
    final token = session.token.trim();
    final landId = item['id']?.toString().trim() ?? '';
    if (token.isEmpty || landId.isEmpty) {
      throw Exception('Cloud deletion requires a valid session and land id.');
    }

    await ref.read(landCloudServiceProvider).deleteLand(token, landId);

    final box = Hive.box('landbox');
    final localKeys = box
        .toMap()
        .entries
        .where((entry) {
          final value = entry.value;
          if (value is! Map) return false;
          final raw = Map<String, dynamic>.from(value);
          final localId = raw['id']?.toString().trim() ?? '';
          final cloudId = raw['cloudId']?.toString().trim() ?? '';
          return localId == landId || cloudId == landId;
        })
        .map((entry) => entry.key)
        .toList();

    if (localKeys.isNotEmpty) {
      await box.deleteAll(localKeys);
    }
    await _fetchRemoteData();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Land deleted from cloud and app')),
    );
  }

  Future<void> _copyCoordinates(
    BuildContext context,
    Map<String, dynamic> item,
  ) async {
    final text = _buildLocalShareText(item, includeHeader: false);
    if (text.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
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
    final text = _buildLocalShareText(item);
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

  List<String> _extractRemotePointLabels(
    List<LandPoint> remotePoints,
    int pointsCount,
  ) {
    if (pointsCount <= 0) return const [];
    final labels = <String>[];
    for (int i = 0; i < pointsCount; i++) {
      final raw = i < remotePoints.length
          ? (remotePoints[i].label?.trim() ?? '')
          : '';
      labels.add(raw.isEmpty ? '${i + 1}' : raw);
    }
    return labels;
  }

  Future<String?> _shareBlockForSelection(
    String selectionId,
    Box<dynamic> box,
  ) async {
    if (selectionId.startsWith('remote:')) {
      final landId = selectionId.substring('remote:'.length).trim();
      if (landId.isEmpty) return null;
      try {
        final detail = await ref.read(remoteLandDetailProvider(landId).future);
        return _buildRemoteShareText(detail);
      } catch (_) {
        return null;
      }
    }

    final raw = box.get(selectionId);
    if (raw is! Map) return null;
    return _buildLocalShareText(Map<String, dynamic>.from(raw));
  }

  String _buildLocalShareText(
    Map<String, dynamic> item, {
    bool includeHeader = true,
  }) {
    final pointsRaw = (item['points'] as List?) ?? const [];
    final name = item['name']?.toString() ?? 'Saved location';
    final group = _groupOf(item);
    final createdAt = _formatDate(item['createdAt']?.toString());
    final updatedAt = _formatDate(item['updatedAt']?.toString());
    final hasUpdated = item['updatedAt']?.toString().isNotEmpty ?? false;
    final ellipsoid = _referenceEllipsoidForItem(item);
    final buffer = StringBuffer();

    if (includeHeader) {
      buffer
        ..writeln(name)
        ..writeln('Group: $group')
        ..writeln('Points: ${pointsRaw.length}')
        ..writeln('Created: $createdAt')
        ..writeln(hasUpdated ? 'Updated: $updatedAt' : 'Updated: -')
        ..writeln('');
    }

    for (var i = 0; i < pointsRaw.length; i++) {
      final point = pointsRaw[i];
      if (point is! Map) continue;
      final lat = _toDouble(point['lat']) ?? _toDouble(point['latitude']);
      final lng = _toDouble(point['lng']) ?? _toDouble(point['longitude']);
      if (lat == null || lng == null) continue;
      final computed = UtmConverter.fromLatLng(lat, lng, ellipsoid);
      final easting = _toDouble(point['easting']) ?? computed?.easting;
      final northing = _toDouble(point['northing']) ?? computed?.northing;
      final zone = point['zone']?.toString().trim();
      buffer.writeln(
        _formatPointShareBlock(
          title: 'Point ${i + 1}',
          latitude: lat,
          longitude: lng,
          easting: easting,
          northing: northing,
          zone: zone,
        ),
      );
      if (i < pointsRaw.length - 1) {
        buffer.writeln();
      }
    }

    return buffer.toString().trimRight();
  }

  String _buildRemoteShareText(LandDetail detail) {
    final points = detail.points;
    final pointLabels = _extractRemotePointLabels(points, points.length);
    final ellipsoid = ref.read(referenceEllipsoidProvider);
    final buffer = StringBuffer()
      ..writeln(detail.name.isNotEmpty ? detail.name : 'Saved location')
      ..writeln('Group: Cloud')
      ..writeln('Points: ${points.length}')
      ..writeln('Created: ${_formatDate(detail.createdAt)}')
      ..writeln(
        detail.updatedAt?.toString().isNotEmpty ?? false
            ? 'Updated: ${_formatDate(detail.updatedAt)}'
            : 'Updated: -',
      )
      ..writeln('');

    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final lat =
          point.y ??
          _toDouble(point.raw['lat']) ??
          _toDouble(point.raw['latitude']);
      final lng =
          point.x ??
          _toDouble(point.raw['lng']) ??
          _toDouble(point.raw['longitude']);
      if (lat == null || lng == null) continue;
      final computed = UtmConverter.fromLatLng(lat, lng, ellipsoid);
      final easting = point.easting ?? computed?.easting;
      final northing = point.northing ?? computed?.northing;
      buffer.writeln(
        _formatPointShareBlock(
          title: 'Point ${pointLabels[i]}',
          latitude: lat,
          longitude: lng,
          easting: easting,
          northing: northing,
          zone: point.zone,
        ),
      );
      if (i < points.length - 1) {
        buffer.writeln();
      }
    }

    return buffer.toString().trimRight();
  }

  String _formatPointShareBlock({
    required String title,
    required double latitude,
    required double longitude,
    double? easting,
    double? northing,
    String? zone,
  }) {
    final buffer = StringBuffer()
      ..writeln(title)
      ..writeln('Latitude: ${latitude.toStringAsFixed(6)}')
      ..writeln('Longitude: ${longitude.toStringAsFixed(6)}');

    if (easting != null && northing != null) {
      buffer
        ..writeln('Easting: ${easting.toStringAsFixed(2)}')
        ..writeln('Northing: ${northing.toStringAsFixed(2)}');
      if (zone != null && zone.isNotEmpty) {
        buffer.writeln('Zone: $zone');
      }
    }

    return buffer.toString().trimRight();
  }

  ReferenceEllipsoid _referenceEllipsoidForItem(Map<String, dynamic> item) {
    final raw = item['referenceEllipsoid']?.toString().trim() ?? '';
    for (final ellipsoid in ReferenceEllipsoid.values) {
      if (ellipsoid.name == raw) return ellipsoid;
    }
    return ref.read(referenceEllipsoidProvider);
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
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

class _SectionChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _SectionChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = selected
        ? theme.colorScheme.primary.withValues(alpha: 0.12)
        : Colors.white;
    final borderColor = selected
        ? theme.colorScheme.primary
        : Colors.grey.withValues(alpha: 0.18);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? theme.colorScheme.primary : Colors.black87,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: selected
                    ? theme.colorScheme.primary.withValues(alpha: 0.18)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected ? theme.colorScheme.primary : Colors.black54,
                ),
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
  final bool isCloudSynced;
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
    required this.isCloudSynced,
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
        if (isCloudSynced)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Icon(
              Icons.cloud_done,
              size: 18,
              color: theme.colorScheme.primary,
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
                  fontSize: 15,
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
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
        ),
        if (isCloudSynced)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(
              Icons.cloud_done,
              size: 18,
              color: theme.colorScheme.primary,
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
            if (isCloudSynced)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.cloud_done,
                  size: 18,
                  color: theme.colorScheme.primary,
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
            if (isCloudSynced)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.cloud_done,
                  size: 18,
                  color: theme.colorScheme.primary,
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

class _RemoteLandDetailSheet extends ConsumerStatefulWidget {
  final LandListItem land;
  final Future<void> Function() onRemoteChanged;
  final VoidCallback? onOpenMapRequested;

  const _RemoteLandDetailSheet({
    required this.land,
    required this.onRemoteChanged,
    this.onOpenMapRequested,
  });

  @override
  ConsumerState<_RemoteLandDetailSheet> createState() =>
      _RemoteLandDetailSheetState();
}

class _RemoteLandDetailSheetState
    extends ConsumerState<_RemoteLandDetailSheet> {
  bool _isDeleting = false;

  @override
  Widget build(BuildContext context) {
    final detailState = ref.watch(remoteLandDetailProvider(widget.land.id));

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.94,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
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
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 36,
                    ),
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
      ),
    );
  }

  Widget _buildLoaded(BuildContext context, LandDetail detail) {
    final points = _extractRemoteLatLngPoints(detail.points);
    final pointLabels = _extractRemotePointLabels(detail.points, points.length);
    return Column(
      mainAxisSize: MainAxisSize.min,
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
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            detail.name,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '${points.length} points · ${detail.type}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Place: ${detail.place?.trim().isNotEmpty == true ? detail.place! : '—'}',
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
            'Phone: ${detail.phone?.trim().isNotEmpty == true ? detail.phone! : '—'}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Area: ${detail.area == null ? '—' : detail.area!.toStringAsFixed(2)}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Perimeter: ${detail.perimeter == null ? '—' : detail.perimeter!.toStringAsFixed(2)}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Created: ${_formatStaticDate(detail.createdAt)}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
        ),
        if ((detail.updatedAt ?? '').isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Updated: ${_formatStaticDate(detail.updatedAt)}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.black54),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Type: ${detail.type}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
        ),
        if ((detail.description ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              detail.description!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
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
                  if (detail.type == 'polygon' && points.length >= 3)
                    PolygonLayer(
                      polygons: [
                        Polygon(
                          points: points,
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.16),
                          borderStrokeWidth: 2,
                          borderColor: Theme.of(context).colorScheme.primary,
                        ),
                      ],
                    ),
                  MarkerLayer(
                    markers: [
                      for (int i = 0; i < points.length; i++)
                        Marker(
                          width: 86,
                          height: 42,
                          point: points[i],
                          child: _MapPointLabelMarker(
                            label: pointLabels[i],
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (points.isNotEmpty) const SizedBox(height: 16),
        if (points.isNotEmpty)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                final target = LandNavigationTarget(
                  point: _representativePoint(points),
                  points: points,
                  pointLabels: pointLabels,
                  label: detail.name,
                  kind: _navigationKind(detail.type, points.length),
                );
                ref.read(landMapProvider.notifier).setNavigationTarget(target);
                Navigator.of(context).pop();
                widget.onOpenMapRequested?.call();
              },
              icon: const Icon(Icons.navigation_outlined),
              label: const Text('Go to'),
            ),
          ),
        if (points.isNotEmpty) const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () =>
                ref.invalidate(remoteLandDetailProvider(widget.land.id)),
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
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
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _showEditMetadataSheet(detail),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit metadata'),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                'Markers',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
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
        if (points.isEmpty)
          const Text('No points saved.')
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: detail.points.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final point = detail.points[index];
              final lat = point.y;
              final lng = point.x;
              final label = point.label?.trim().isNotEmpty == true
                  ? point.label!
                  : '${index + 1}';
              final isPolyline = detail.type == 'polyline';
              return ListTile(
                dense: true,
                leading: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isPolyline
                        ? Colors.orange.shade700
                        : Theme.of(context).colorScheme.primary,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Center(
                    child: Text(
                      label.length > 3 ? '${index + 1}' : label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                title: isPolyline && point.label?.trim().isNotEmpty == true
                    ? Text(
                        point.label!,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      )
                    : Text(
                        '${lat?.toStringAsFixed(6) ?? '—'}, ${lng?.toStringAsFixed(6) ?? '—'}',
                        style: const TextStyle(fontSize: 12),
                      ),
                subtitle: isPolyline && point.label?.trim().isNotEmpty == true
                    ? Text(
                        '${lat?.toStringAsFixed(6) ?? '—'}, ${lng?.toStringAsFixed(6) ?? '—'}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      )
                    : point.easting != null && point.northing != null
                    ? Text(
                        'E ${point.easting!.toStringAsFixed(2)} N ${point.northing!.toStringAsFixed(2)} · Zone ${point.zone ?? '—'}${point.band ?? ''}',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade500,
                        ),
                      )
                    : null,
              );
            },
          ),
        const SizedBox(height: 16),
        if (detail.markers.isEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'No cloud markers found for this land.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.black54),
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

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  List<LatLng> _extractRemoteLatLngPoints(List<LandPoint> remotePoints) {
    final points = <LatLng>[];
    for (final point in remotePoints) {
      final lat =
          point.y ??
          _toDouble(point.raw['lat']) ??
          _toDouble(point.raw['latitude']);
      final lng =
          point.x ??
          _toDouble(point.raw['lng']) ??
          _toDouble(point.raw['longitude']);
      if (lat == null || lng == null) continue;
      points.add(LatLng(lat, lng));
    }
    return points;
  }

  List<String> _extractRemotePointLabels(
    List<LandPoint> remotePoints,
    int pointsCount,
  ) {
    if (pointsCount <= 0) return const [];
    final labels = <String>[];
    for (int i = 0; i < pointsCount; i++) {
      final raw = i < remotePoints.length
          ? (remotePoints[i].label?.trim() ?? '')
          : '';
      labels.add(raw.isEmpty ? '${i + 1}' : raw);
    }
    return labels;
  }

  LatLng _representativePoint(List<LatLng> points) {
    if (points.length == 1) return points.first;

    final lat =
        points.fold<double>(0, (sum, point) => sum + point.latitude) /
        points.length;
    final lng =
        points.fold<double>(0, (sum, point) => sum + point.longitude) /
        points.length;
    return LatLng(lat, lng);
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

  Future<void> _showMarkerSheet(LandDetail detail, {LandMarker? marker}) async {
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Marker deleted')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _MapPointLabelMarker extends StatelessWidget {
  final String label;
  final Color color;

  const _MapPointLabelMarker({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.30)),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditRemoteLandSheet extends ConsumerStatefulWidget {
  final LandDetail land;
  final Future<void> Function() onSaved;

  const _EditRemoteLandSheet({required this.land, required this.onSaved});

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
      await ref
          .read(landCloudServiceProvider)
          .updateLand(
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Land metadata updated')));
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
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (value) => value == null || value.trim().isEmpty
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

class _EditRemoteMarkerSheetState
    extends ConsumerState<_EditRemoteMarkerSheet> {
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
        await ref
            .read(landCloudServiceProvider)
            .createMarker(
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
        await ref
            .read(landCloudServiceProvider)
            .updateMarker(
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
                    validator: (value) => value == null || value.trim().isEmpty
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

class _LandDetailSheet extends ConsumerStatefulWidget {
  // Local item data
  final Map<String, dynamic>? localItem;
  // Cloud item data
  final LandListItem? cloudItem;
  final Future<void> Function()? onRemoteChanged;
  final VoidCallback? onOpenMapRequested;

  const _LandDetailSheet({
    this.localItem,
    this.cloudItem,
    this.onRemoteChanged,
    this.onOpenMapRequested,
  }) : assert(
         localItem != null || cloudItem != null,
         'Either localItem or cloudItem must be provided',
       );

  bool get isCloud => cloudItem != null;

  @override
  ConsumerState<_LandDetailSheet> createState() => _LandDetailSheetState();
}

class _LandDetailSheetState extends ConsumerState<_LandDetailSheet> {
  bool _showAllPoints = false;
  bool _isDeleting = false;
  bool _isSaving = false;

  // Local helpers
  List<LatLng> get _localPoints {
    if (widget.localItem == null) return const [];
    final pointsRaw = (widget.localItem!['points'] as List?) ?? const [];
    final points = <LatLng>[];
    for (final e in pointsRaw) {
      if (e is! Map) continue;
      final lat = (e['lat'] as num?)?.toDouble();
      final lng = (e['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      points.add(LatLng(lat, lng));
    }
    if (points.isEmpty) {
      final lat = (widget.localItem!['lat'] as num?)?.toDouble();
      final lng = (widget.localItem!['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) points.add(LatLng(lat, lng));
    }
    return points;
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  List<LatLng> get _cloudPoints {
    final detail = _cloudDetail;
    if (detail == null) return const [];
    final points = <LatLng>[];
    for (final point in detail.points) {
      final lat =
          point.y ??
          _toDouble(point.raw['lat']) ??
          _toDouble(point.raw['latitude']);
      final lng =
          point.x ??
          _toDouble(point.raw['lng']) ??
          _toDouble(point.raw['longitude']);
      if (lat == null || lng == null) continue;
      points.add(LatLng(lat, lng));
    }
    return points;
  }

  LandDetail? get _cloudDetail {
    if (!widget.isCloud) return null;
    return ref
        .watch(remoteLandDetailProvider(widget.cloudItem!.id))
        .asData
        ?.value;
  }

  bool get _cloudLoading {
    if (!widget.isCloud) return false;
    return ref.watch(remoteLandDetailProvider(widget.cloudItem!.id)).isLoading;
  }

  String? get _cloudError {
    if (!widget.isCloud) return null;
    final state = ref.watch(remoteLandDetailProvider(widget.cloudItem!.id));
    return state.hasError ? state.error.toString() : null;
  }

  String _typeBadgeLabel(String type) {
    switch (type.toLowerCase()) {
      case 'polygon':
        return 'Field';
      case 'polyline':
        return 'Distance';
      case 'point':
        return 'Location';
      default:
        return type;
    }
  }

  Color _typeBadgeColor(String type) {
    switch (type.toLowerCase()) {
      case 'polygon':
        return const Color(0xFF0074D9);
      case 'polyline':
        return const Color(0xFFF59E0B);
      case 'point':
        return const Color(0xFF16A34A);
      default:
        return Colors.grey;
    }
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return '—';
    return '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Determine values from either local or cloud
    final name = widget.isCloud
        ? widget.cloudItem!.name
        : widget.localItem!['name']?.toString() ?? 'Saved location';
    final type = widget.isCloud
        ? (_cloudDetail?.type ?? widget.cloudItem!.type)
        : (widget.localItem!['entityType']?.toString() ??
              widget.localItem!['type']?.toString() ??
              'polygon');
    final place = widget.isCloud
        ? widget.cloudItem!.place
        : widget.localItem!['place']?.toString();
    final phone = widget.isCloud
        ? widget.cloudItem!.phone
        : widget.localItem!['phone']?.toString();
    final description = widget.isCloud
        ? widget.cloudItem!.description
        : widget.localItem!['description']?.toString();
    final createdAt = widget.isCloud
        ? widget.cloudItem!.createdAt
        : widget.localItem!['createdAt']?.toString();
    final updatedAt = widget.isCloud
        ? widget.cloudItem!.updatedAt
        : widget.localItem!['updatedAt']?.toString();
    final isCloudSynced =
        widget.isCloud ||
        (widget.localItem!['cloudId']?.toString().trim().isNotEmpty ?? false);

    final badgeColor = _typeBadgeColor(type);
    final points = widget.isCloud ? _cloudPoints : _localPoints;

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: badgeColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: badgeColor.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Text(
                                  _typeBadgeLabel(type),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: badgeColor,
                                  ),
                                ),
                              ),
                              if (isCloudSynced) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.cloud_done,
                                  size: 16,
                                  color: theme.colorScheme.primary,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            name,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: Colors.black87,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Body
              Expanded(
                child: widget.isCloud && _cloudLoading
                    ? const Center(child: CircularProgressIndicator())
                    : widget.isCloud && _cloudError != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.red,
                              size: 36,
                            ),
                            const SizedBox(height: 12),
                            Text(_cloudError!, textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () => ref.invalidate(
                                remoteLandDetailProvider(widget.cloudItem!.id),
                              ),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        children: [
                          // Map card
                          if (points.isNotEmpty)
                            _buildMapCard(context, points, type),
                          const SizedBox(height: 12),
                          // Info card
                          _buildInfoCard(
                            context,
                            place: place,
                            phone: phone,
                            description: description,
                            createdAt: createdAt,
                            updatedAt: updatedAt,
                            type: type,
                          ),
                          const SizedBox(height: 12),
                          // Points card
                          if (points.isNotEmpty)
                            _buildPointsCard(context, points),
                          const SizedBox(height: 12),
                          // Actions card
                          _buildActionsCard(context),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapCard(BuildContext context, List<LatLng> points, String type) {
    final theme = Theme.of(context);
    final color = _typeBadgeColor(type);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 200,
          child: FlutterMap(
            options: MapOptions(
              initialCenter: points.first,
              initialZoom: 15,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.none,
              ),
              cameraConstraint: CameraConstraint.contain(
                bounds: LatLngBounds.fromPoints(points),
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.geo_coordinates',
              ),
              if (type == 'polyline' && points.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(points: points, strokeWidth: 3, color: color),
                  ],
                ),
              if (type == 'polygon' && points.length >= 3)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: points,
                      color: color.withValues(alpha: 0.16),
                      borderStrokeWidth: 2.5,
                      borderColor: color,
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
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
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
    );
  }

  Widget _buildInfoCard(
    BuildContext context, {
    required String? place,
    required String? phone,
    required String? description,
    required String? createdAt,
    required String? updatedAt,
    required String type,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: Colors.grey.shade500),
              const SizedBox(width: 6),
              Text(
                'Details',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InfoRow(label: 'Type', value: _typeBadgeLabel(type)),
          if (place?.trim().isNotEmpty == true)
            _InfoRow(label: 'Place', value: place!),
          if (phone?.trim().isNotEmpty == true)
            _InfoRow(label: 'Phone', value: phone!),
          if (description?.trim().isNotEmpty == true)
            _InfoRow(label: 'Description', value: description!),
          _InfoRow(label: 'Created', value: _formatDate(createdAt)),
          if (updatedAt?.trim().isNotEmpty == true)
            _InfoRow(label: 'Updated', value: _formatDate(updatedAt)),
        ],
      ),
    );
  }

  Widget _buildPointsCard(BuildContext context, List<LatLng> points) {
    final theme = Theme.of(context);
    final cloudDetail = _cloudDetail;
    final visiblePoints = _showAllPoints ? points : points.take(3).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.place_outlined, size: 16, color: Colors.grey.shade500),
              const SizedBox(width: 6),
              Text(
                'Points (${points.length})',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...visiblePoints.asMap().entries.map((entry) {
            final index = entry.key;
            final p = entry.value;

            // Get label
            String label = '${index + 1}';
            if (widget.isCloud &&
                cloudDetail != null &&
                index < cloudDetail.points.length) {
              final raw = cloudDetail.points[index].label?.trim() ?? '';
              if (raw.isNotEmpty) label = raw;
            } else if (!widget.isCloud) {
              final rawPoints =
                  (widget.localItem!['points'] as List?) ?? const [];
              if (index < rawPoints.length && rawPoints[index] is Map) {
                final rawLabel =
                    rawPoints[index]['label']?.toString().trim() ?? '';
                if (rawLabel.isNotEmpty) label = rawLabel;
              }
            }

            final type = widget.isCloud
                ? widget.cloudItem!.type
                : (widget.localItem!['entityType']?.toString() ??
                      widget.localItem!['type']?.toString() ??
                      'polygon');
            final dotColor = _typeBadgeColor(type);

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: dotColor.withValues(alpha: 0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        label.length > 3 ? '${index + 1}' : label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (label != '${index + 1}')
                          Text(
                            label,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        Text(
                          '${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        // Show easting/northing for cloud points
                        if (widget.isCloud &&
                            cloudDetail != null &&
                            index < cloudDetail.points.length)
                          Builder(
                            builder: (context) {
                              final cp = cloudDetail.points[index];
                              if (cp.easting == null || cp.northing == null) {
                                return const SizedBox.shrink();
                              }
                              return Text(
                                'E ${cp.easting!.toStringAsFixed(2)}  N ${cp.northing!.toStringAsFixed(2)}  Zone ${cp.zone ?? '—'}${cp.band ?? ''}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade400,
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          if (points.length > 3)
            TextButton(
              onPressed: () => setState(() => _showAllPoints = !_showAllPoints),
              child: Text(
                _showAllPoints
                    ? 'Show less'
                    : 'Show all ${points.length} points',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionsCard(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Go to map — always shown
          _ActionRow(
            icon: Icons.navigation_outlined,
            label: 'Go to map',
            color: theme.colorScheme.primary,
            onTap: () {
              Navigator.of(context).pop();
              if (widget.isCloud) {
                final detail = _cloudDetail;
                if (detail != null) {
                  final points = _cloudPoints;
                  if (points.isNotEmpty) {
                    final target = LandNavigationTarget(
                      point: _representativePoint(points),
                      points: points,
                      pointLabels: detail.points
                          .map(
                            (p) => p.label?.trim().isNotEmpty == true
                                ? p.label!
                                : '${detail.points.indexOf(p) + 1}',
                          )
                          .toList(),
                      label: detail.name,
                      kind: _navigationKind(detail.type, points.length),
                    );
                    ref
                        .read(landMapProvider.notifier)
                        .setNavigationTarget(target);
                  }
                }
              }
              widget.onOpenMapRequested?.call();
            },
          ),
          const Divider(height: 1, indent: 56),
          if (widget.isCloud) ...[
            _ActionRow(
              icon: Icons.edit_outlined,
              label: 'Edit metadata',
              onTap: () async {
                final detail = _cloudDetail;
                if (detail == null) return;
                await showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => _EditRemoteLandSheet(
                    land: detail,
                    onSaved: () async {
                      ref.invalidate(remoteLandDetailProvider(detail.id));
                      await widget.onRemoteChanged?.call();
                    },
                  ),
                );
              },
            ),
            const Divider(height: 1, indent: 56),
            _ActionRow(
              icon: Icons.refresh,
              label: 'Refresh',
              onTap: () => ref.invalidate(
                remoteLandDetailProvider(widget.cloudItem!.id),
              ),
            ),
            const Divider(height: 1, indent: 56),
            _ActionRow(
              icon: Icons.delete_outline,
              label: _isDeleting ? 'Deleting...' : 'Delete land',
              color: Colors.red,
              onTap: _isDeleting ? null : () => _deleteCloudLand(context),
            ),
          ] else ...[
            _ActionRow(
              icon: Icons.edit_outlined,
              label: 'Rename',
              onTap: () {
                Navigator.of(context).pop();
                // Caller handles rename
              },
            ),
            const Divider(height: 1, indent: 56),
            _ActionRow(
              icon: Icons.copy_outlined,
              label: 'Copy coordinates',
              onTap: () async {
                final pts = (widget.localItem!['points'] as List?) ?? [];
                final coords = pts
                    .map((p) => '${p['lat']},${p['lng']}')
                    .join('\n');
                await Clipboard.setData(ClipboardData(text: coords));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Coordinates copied')),
                );
              },
            ),
            const Divider(height: 1, indent: 56),
            _ActionRow(
              icon: Icons.delete_outline,
              label: 'Delete',
              color: Colors.red,
              onTap: () => _deleteLocalItem(context),
            ),
          ],
        ],
      ),
    );
  }

  LatLng _representativePoint(List<LatLng> points) {
    if (points.length == 1) return points.first;
    final lat =
        points.fold<double>(0, (s, p) => s + p.latitude) / points.length;
    final lng =
        points.fold<double>(0, (s, p) => s + p.longitude) / points.length;
    return LatLng(lat, lng);
  }

  Future<void> _deleteCloudLand(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete cloud land?'),
        content: Text(
          'This will delete "${widget.cloudItem!.name}" from the server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final token = ref.read(authSessionProvider).token.trim();
    if (token.isEmpty) return;
    setState(() => _isDeleting = true);
    try {
      await ref
          .read(landCloudServiceProvider)
          .deleteLand(token, widget.cloudItem!.id);
      await widget.onRemoteChanged?.call();
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Land deleted from cloud')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  void _deleteLocalItem(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete location?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final box = Hive.box('landbox');
              final id = widget.localItem!['id']?.toString() ?? '';
              await box.delete(id);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (!context.mounted) return;
              Navigator.of(context).pop();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback? onTap;

  const _ActionRow({
    required this.icon,
    required this.label,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.black87;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: c),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: c,
              ),
            ),
            const Spacer(),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
