import '../../widget/plan_access_lock.dart';
import 'dart:async';
import '../../subscriptions/plans_access_page.dart';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
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
import '../services/coordinate_converter.dart';
import '../services/land_sync_service.dart';
import '../services/measurement_formatter.dart';
import '../services/survey_invitation.dart';
import 'user_survey_page.dart';
import 'package:uuid/uuid.dart';
import '../../../core/localization/app_localizations.dart';
import '../../workspaces/workspace_context.dart';
import '../../workspaces/workspace_provider.dart';
import '../../workspaces/library_organization_filter.dart';
import '../../workspaces/record_organization_section.dart';
import 'record_recovery_page.dart';
import 'record_export_page.dart';
import 'parcel_pdf_page.dart';
import 'record_sharing_page.dart';
import 'record_custom_fields_page.dart';
import '../../widget/record_detail_value.dart';
import '../../widget/saved_location_widgets.dart';
import '../../widget/settings_sheet.dart';

enum _ViewMode { combined, basic, text, photo }

enum _SavedSort { newest, oldest, nameAsc, nameDesc, pointsDesc }

enum _SavedFilter { all, threePlusPoints, updatedOnly, cloudOnly }

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
  final bool isActive;
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
    this.isActive = false,
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
  final ScrollController _savedListScrollController = ScrollController();
  String _searchQuery = '';
  bool _selectionMode = false;
  final Set<String> _selectedIds = <String>{};
  String _groupFilter = 'All groups';
  bool _compactMode = false;
  bool _isLoadingMoreRemote = false;
  bool _isManuallySyncing = false;
  bool _showSurveyInvitation = false;
  bool _previewSurveyInvitation = false;
  bool _checkingSurveyInvitation = false;
  ProviderSubscription<AuthSession>? _authSubscription;
  ProviderSubscription<WorkspaceState>? _workspaceSubscription;

  Color get _accent => ref.read(workspaceProvider).activeCompanyId != null
      ? const Color(0xFF001F3F)
      : const Color(0xFF001F3F);

  @override
  void initState() {
    super.initState();
    widget.toolbarController?.attach(this);
    _savedListScrollController.addListener(_onSavedListScroll);
    _restoreDisplayPreferences();
    _authSubscription = ref.listenManual(authSessionProvider, (previous, next) {
      if (next.isLoggedIn && next.isVerified) {
        _fetchRemoteData();
        return;
      }
    });
    _workspaceSubscription = ref.listenManual(workspaceProvider, (
      previous,
      next,
    ) {
      if (previous?.activeCompanyId == next.activeCompanyId) return;
      _selectedIds.clear();
      _selectionMode = false;
      if (mounted) setState(() {});
      _fetchRemoteData();
    });

    Future.microtask(_fetchRemoteData);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.isActive) _considerSurveyInvitation();
    });
  }

  @override
  void didUpdateWidget(covariant SavedLocationsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _considerSurveyInvitation();
      });
    }
  }

  @override
  void dispose() {
    widget.toolbarController?.detach(this);
    _savedListScrollController.removeListener(_onSavedListScroll);
    _savedListScrollController.dispose();
    _authSubscription?.close();
    _workspaceSubscription?.close();
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
    if (mounted && widget.isActive) _considerSurveyInvitation();
  }

  Future<void> _syncPendingRecords() async {
    if (_isManuallySyncing) return;
    final session = ref.read(authSessionProvider);
    if (!session.isLoggedIn || !session.isVerified) return;
    final companyId = ref.read(workspaceProvider).activeCompanyId;
    final token = Hive.box('landbox').get('auth_token');
    setState(() => _isManuallySyncing = true);
    try {
      final box = Hive.box('landbox');
      final result = await LandSyncService(
        box,
      ).syncPendingLands(limit: max(1, box.length));
      if (!mounted ||
          companyId != ref.read(workspaceProvider).activeCompanyId ||
          token != box.get('auth_token')) {
        return;
      }
      await _fetchRemoteData();
      if (!mounted ||
          companyId != ref.read(workspaceProvider).activeCompanyId ||
          token != box.get('auth_token')) {
        return;
      }
      final message = result.attempted == 0
          ? context.l10n.t('No pending records to sync.')
          : context.l10n.t(
              '{synced} records synced. {failed} records remain pending.',
              params: {
                'synced': '${result.synced}',
                'failed': '${result.failed}',
              },
            );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.t(
                'Unable to complete cloud sync. Your local records are kept. Please try again.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isManuallySyncing = false);
    }
  }

  Future<void> _considerSurveyInvitation() async {
    if (!mounted || !widget.isActive || _checkingSurveyInvitation) return;
    _checkingSurveyInvitation = true;
    try {
      final box = Hive.box('landbox');
      final localCount = box.values.whereType<Map>().where((record) {
        final type = record['entityType']?.toString() ?? '';
        return type == 'land' ||
            type == 'polygon' ||
            type == 'polyline' ||
            type == 'point';
      }).length;
      final remoteCount =
          ref.read(remoteLandsProvider).asData?.value?.total ?? 0;
      final invitation = SurveyInvitation(box);
      final preview =
          _previewSurveyInvitation || await invitation.consumeDebugPreview();
      final show =
          preview ||
          await invitation.shouldShow(
            savedRecordCount: max(localCount, remoteCount),
          );
      if (mounted &&
          widget.isActive &&
          (_showSurveyInvitation != show ||
              _previewSurveyInvitation != preview)) {
        setState(() {
          _previewSurveyInvitation = preview;
          _showSurveyInvitation = show;
        });
      }
    } finally {
      _checkingSurveyInvitation = false;
    }
  }

  Future<void> _dismissSurveyInvitation() async {
    if (!_previewSurveyInvitation) {
      await SurveyInvitation(Hive.box('landbox')).dismiss();
    }
    if (mounted) {
      setState(() {
        _previewSurveyInvitation = false;
        _showSurveyInvitation = false;
      });
    }
  }

  Future<void> _openSurveyFromInvitation() async {
    final saved = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const UserSurveyPage()));
    if (!mounted) return;
    if (saved == true) {
      setState(() => _showSurveyInvitation = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.t('Response saved. It will sync automatically.'),
          ),
        ),
      );
    }
  }

  Future<void> _loadMoreRemoteData() async {
    final session = ref.read(authSessionProvider);
    if (!session.isLoggedIn || !session.isVerified || _isLoadingMoreRemote) {
      return;
    }
    setState(() => _isLoadingMoreRemote = true);
    try {
      await ref
          .read(remoteLandsProvider.notifier)
          .fetchNextPage(search: _searchQuery.isEmpty ? null : _searchQuery);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.t('Could not load more cloud records.')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoadingMoreRemote = false);
      }
    }
  }

  void _onSavedListScroll() {
    if (!_savedListScrollController.hasClients || _isLoadingMoreRemote) return;
    final position = _savedListScrollController.position;
    if (position.extentAfter > 420) return;

    final session = ref.read(authSessionProvider);
    final remotePage = ref.read(remoteLandsProvider).asData?.value;
    if (!_canLoadMoreRemote(remotePage, session)) return;

    _loadMoreRemoteData();
  }

  bool _canLoadMoreRemote(PaginatedLands? remotePage, AuthSession session) {
    final remoteLoadedCount = remotePage?.items.length ?? 0;
    return session.isLoggedIn &&
        session.isVerified &&
        remotePage != null &&
        remoteLoadedCount < latestRemoteLandsLimit &&
        remotePage.currentPage < remotePage.lastPage;
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
    final l10n = context.l10n;
    final box = Hive.box('landbox');
    final authSession = ref.watch(authSessionProvider);
    final workspace = ref.watch(workspaceProvider);
    final organizationFilter = ref.watch(libraryOrganizationFilterProvider);
    ref.listen(libraryOrganizationFilterProvider, (previous, next) {
      _selectedIds.clear();
      _selectionMode = false;
      _notifyToolbarStateChanged();
      _fetchRemoteData();
    });
    final remoteLandsState = ref.watch(remoteLandsProvider);
    final distanceUnit = ref.watch(distanceUnitProvider);
    final canUseCloud = authSession.isLoggedIn && authSession.isVerified;

    final baseTheme = Theme.of(context);
    return Theme(
      data: baseTheme.copyWith(
        colorScheme: baseTheme.colorScheme.copyWith(primary: _accent),
      ),
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: const Color(0xFFF7F7F8),
          body: Column(
            children: [
              if (widget.showEmbeddedToolbar && _selectionMode)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      if (_selectionMode)
                        Text(
                          l10n.t(
                            '{count} selected',
                            params: {'count': '${_selectedIds.length}'},
                          ),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      const Spacer(),
                      if (_selectionMode)
                        IconButton(
                          onPressed: _selectedIds.isEmpty
                              ? null
                              : _setGroupForSelectedItems,
                          icon: const HugeIcon(
                            icon: HugeIcons.strokeRoundedFolder01,
                            size: 20,
                          ),
                          tooltip: l10n.t('Set group'),
                        ),
                      if (_selectionMode)
                        IconButton(
                          onPressed: _selectedIds.isEmpty
                              ? null
                              : _shareSelectedItems,
                          icon: const HugeIcon(
                            icon: HugeIcons.strokeRoundedShare01,
                            size: 20,
                          ),
                          tooltip: l10n.t('Share selected'),
                        ),
                      if (_selectionMode)
                        IconButton(
                          onPressed: _selectedIds.isEmpty
                              ? null
                              : _deleteSelectedItems,
                          icon: const HugeIcon(
                            icon: HugeIcons.strokeRoundedDelete02,
                            size: 20,
                          ),
                          tooltip: l10n.t('Delete selected'),
                        ),
                      if (_selectionMode)
                        IconButton(
                          onPressed: _exitSelectionMode,
                          icon: const HugeIcon(
                            icon: HugeIcons.strokeRoundedCancel01,
                            size: 20,
                          ),
                          tooltip: l10n.t('Exit selection'),
                        ),
                      if (!_selectionMode) ...[
                        IconButton(
                          onPressed: _showPageMenu,
                          icon: const HugeIcon(
                            icon: HugeIcons.strokeRoundedMoreVertical,
                            size: 20,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              if (_showSurveyInvitation && widget.isActive && !_selectionMode)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF1F7),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFCFDDEB)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const HugeIcon(
                              icon: HugeIcons.strokeRoundedMessage01,
                              color: Color(0xFF001F3F),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l10n.t('Help us improve TaREF'),
                                style: TextStyle(
                                  color: Color(0xFF001F3F),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: l10n.t('Not now'),
                              icon: const HugeIcon(
                                icon: HugeIcons.strokeRoundedCancel01,
                                size: 18,
                              ),
                              onPressed: _dismissSurveyInvitation,
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                        Text(
                          l10n.t(
                            'Tell us what is working and what is difficult. It takes about a minute.',
                          ),
                          style: TextStyle(
                            color: Color(0xFF374151),
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: _openSurveyFromInvitation,
                            child: Text(l10n.t('Share feedback')),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: SavedSearchHeader(
                  controller: _searchController,
                  hintText: l10n.t('Search saved locations'),
                  clearTooltip: l10n.t('Clear'),
                  menuTooltip: l10n.t('More'),
                  onMenu: _showPageMenu,
                  onChanged: (value) {
                    setState(() => _searchQuery = value.trim());
                    if (canUseCloud) _fetchRemoteData();
                  },
                  onClear: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                    if (canUseCloud) _fetchRemoteData();
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.t(
                          workspace.activeCompanyId != null
                              ? 'Company library'
                              : 'My library',
                        ),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: const Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (canUseCloud)
                      FeatureAccessLock(
                        features: ['land.sync'],
                        child: IconButton(
                          tooltip: l10n.t('Sync pending records'),
                          onPressed: _isManuallySyncing
                              ? null
                              : _syncPendingRecords,
                          icon: _isManuallySyncing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const HugeIcon(
                                  icon: HugeIcons.strokeRoundedCloud,
                                  size: 21,
                                ),
                        ),
                      ),
                    IconButton(
                      tooltip: l10n.t('Filter'),
                      color: _filter != _SavedFilter.all
                          ? Theme.of(context).colorScheme.primary
                          : null,
                      onPressed: _showFilterSheet,
                      icon: const HugeIcon(
                        icon: HugeIcons.strokeRoundedFilterHorizontal,
                        size: 21,
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.t('Sort'),
                      color: _sort != _SavedSort.newest
                          ? Theme.of(context).colorScheme.primary
                          : null,
                      onPressed: _showSortSheet,
                      icon: const HugeIcon(
                        icon: HugeIcons.strokeRoundedSorting05,
                        size: 21,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (_filter != _SavedFilter.all ||
                  _sort != _SavedSort.newest ||
                  _groupFilter != 'All groups')
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (_filter != _SavedFilter.all)
                        _ActiveTag(
                          label:
                              '${l10n.t('Filter')}: ${l10n.t(_filterLabel(_filter))}',
                          onClear: () =>
                              setState(() => _filter = _SavedFilter.all),
                        ),
                      if (_sort != _SavedSort.newest)
                        _ActiveTag(
                          label:
                              '${l10n.t('Sort')}: ${l10n.t(_sortLabel(_sort))}',
                          onClear: () =>
                              setState(() => _sort = _SavedSort.newest),
                        ),
                      if (_groupFilter != 'All groups')
                        _ActiveTag(
                          label:
                              '${l10n.t('Group')}: ${_groupFilter == 'General' ? l10n.t('General') : _groupFilter}',
                          onClear: () =>
                              setState(() => _groupFilter = 'All groups'),
                        ),
                    ],
                  ),
                ),
              if (canUseCloud && workspace.activeCompanyId != null)
                const LibraryOrganizationFilters(),
              const SizedBox(height: 8),
              Expanded(
                child: ValueListenableBuilder(
                  valueListenable: box.listenable(),
                  builder: (context, Box box, _) {
                    final localItems = box.values
                        .whereType<Map>()
                        .map((e) => Map<String, dynamic>.from(e))
                        .where(WorkspaceContext.belongsToActiveWorkspace)
                        .toList();

                    final remoteItems =
                        remoteLandsState.asData?.value?.items ??
                        const <LandListItem>[];
                    final remotePage = remoteLandsState.asData?.value;
                    final allDisplayItems = _buildDisplayItems(
                      localItems: organizationFilter.active
                          ? const []
                          : localItems,
                      remoteItems: remoteItems,
                      canUseCloud: canUseCloud,
                    ).where((item) => _pointsCount(item) > 0).toList();
                    final items = _latestSavedItems(
                      allDisplayItems,
                      limit: latestRemoteLandsLimit,
                    );
                    final remoteTotal =
                        remoteLandsState.asData?.value?.total ?? 0;
                    final remoteLoadedCount = remotePage?.items.length ?? 0;
                    final hasReachedMobileLimit =
                        remoteLoadedCount >= latestRemoteLandsLimit &&
                        remoteTotal > latestRemoteLandsLimit;
                    final showLoadingMoreFooter = _isLoadingMoreRemote;

                    final counts = _contentCounts(items);
                    final sectioned = _applyContentSection(items);
                    final filteredSorted = _applyFilterAndSort(sectioned);
                    final searched = _applySearch(filteredSorted);
                    final groups = _groupOptions(items);

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                SavedPill(
                                  accent: _accent,
                                  label: l10n.t('All'),
                                  count: items.length,
                                  selected:
                                      _contentSection ==
                                      _SavedContentSection.all,
                                  onTap: () => setState(
                                    () => _contentSection =
                                        _SavedContentSection.all,
                                  ),
                                ),
                                const SizedBox(width: 0),
                                SavedPill(
                                  accent: _accent,
                                  label: l10n.t('Points'),
                                  count: counts.markers,
                                  selected:
                                      _contentSection ==
                                      _SavedContentSection.markers,
                                  onTap: () => setState(
                                    () => _contentSection =
                                        _SavedContentSection.markers,
                                  ),
                                ),
                                const SizedBox(width: 0),
                                SavedPill(
                                  accent: _accent,
                                  label: l10n.t('Area'),
                                  count: counts.fields,
                                  selected:
                                      _contentSection ==
                                      _SavedContentSection.fields,
                                  onTap: () => setState(
                                    () => _contentSection =
                                        _SavedContentSection.fields,
                                  ),
                                ),
                                const SizedBox(width: 0),
                                SavedPill(
                                  accent: _accent,
                                  label: l10n.t('Route'),
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
                        if (groups.any(
                          (group) =>
                              group != 'All groups' && group != 'General',
                        )) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 40,
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              scrollDirection: Axis.horizontal,
                              itemCount: groups.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (context, index) {
                                final group = groups[index];
                                return ChoiceChip(
                                  label: Text(
                                    group == 'General' || group == 'All groups'
                                        ? l10n.t(group)
                                        : group,
                                  ),
                                  selected: _groupFilter == group,
                                  onSelected: (_) =>
                                      setState(() => _groupFilter = group),
                                );
                              },
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        if (canUseCloud && remoteLandsState.isLoading) ...[
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: _CloudRecordsLoadingBanner(),
                          ),
                        ],
                        if (searched.isEmpty)
                          Expanded(
                            child: Column(
                              children: [
                                Expanded(
                                  child:
                                      _searchQuery.isNotEmpty ||
                                          _filter != _SavedFilter.all ||
                                          _sort != _SavedSort.newest ||
                                          _groupFilter != 'All groups' ||
                                          _contentSection !=
                                              _SavedContentSection.all
                                      ? const _EmptyState(
                                          title: 'No matching saved locations',
                                          subtitle:
                                              'Try changing search text, filter, sort, or group.',
                                        )
                                      : const _EmptyState(),
                                ),
                                if (showLoadingMoreFooter)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      16,
                                    ),
                                    child: _CloudRecordsLoadMoreFooter(
                                      isLoading: _isLoadingMoreRemote,
                                    ),
                                  ),
                              ],
                            ),
                          )
                        else ...[
                          if (hasReachedMobileLimit)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                              child: Text(
                                l10n.t(
                                  'Showing latest {count} records. Use the web app to view older records.',
                                  params: {'count': '$latestRemoteLandsLimit'},
                                ),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: Colors.black45),
                              ),
                            ),
                          Expanded(
                            child: ListView.separated(
                              controller: _savedListScrollController,
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                              itemCount:
                                  searched.length +
                                  (showLoadingMoreFooter ? 1 : 0),
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                if (index >= searched.length) {
                                  return _CloudRecordsLoadMoreFooter(
                                    isLoading: _isLoadingMoreRemote,
                                  );
                                }
                                final item = searched[index];
                                final id = _selectionKey(item);
                                final isSelected = _selectedIds.contains(id);
                                final isRemote = _isRemoteItem(item);
                                return _SavedLocationCard(
                                  id: id,
                                  name:
                                      item['name']?.toString() ??
                                      item['place']?.toString() ??
                                      l10n.t('Saved location'),
                                  group: _groupOf(item),
                                  createdAt: item['createdAt']?.toString(),
                                  updatedAt: item['updatedAt']?.toString(),
                                  points: _pointsCount(item),
                                  section: _sectionOf(item),
                                  areaSquareMeters: _areaSquareMeters(item),
                                  distanceUnit: distanceUnit,
                                  isCloudSynced: _isCloudSynced(item),
                                  waitingForSpace:
                                      !isRemote &&
                                      item['syncStatus'] == 'pending' &&
                                      item['syncBlockedReason'] ==
                                          'waiting_for_space',
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
                                      final remoteLand = _remoteLandFromItem(
                                        item,
                                      );
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
                                            l10n.t('Cloud land'),
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
          floatingActionButton: FeatureAccessLock(
            features: ['land.create_and_save'],
            child: FloatingActionButton.extended(
              heroTag: 'manual_coords_fab',
              onPressed: _showManualCoordinateEntry,
              backgroundColor: _accent,
              icon: const HugeIcon(
                icon: HugeIcons.strokeRoundedLocationAdd01,
                color: Colors.white,
              ),
              label: Text(
                l10n.t('Add manually'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showManualCoordinateEntry() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => _ManualCoordinateEntrySheet(
        onSaved: () {
          _fetchRemoteData();
        },
      ),
    );
  }

  List<Map<String, dynamic>> _latestSavedItems(
    List<Map<String, dynamic>> src, {
    required int limit,
  }) {
    if (src.length <= limit) return src;
    final sorted = List<Map<String, dynamic>>.of(src);
    sorted.sort((a, b) => _recordTimestamp(b).compareTo(_recordTimestamp(a)));
    return sorted.take(limit).toList();
  }

  int _recordTimestamp(Map<String, dynamic> item) {
    final updated = DateTime.tryParse(item['updatedAt']?.toString() ?? '');
    if (updated != null) return updated.millisecondsSinceEpoch;
    final created = DateTime.tryParse(item['createdAt']?.toString() ?? '');
    return created?.millisecondsSinceEpoch ?? 0;
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
        case _SavedFilter.cloudOnly:
          return _isCloudSynced(item);
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
    final local = _localItemForCloudId(remote.id);
    return {
      'id': remote.id,
      'entityType': remote.type,
      'type': remote.type,
      'name': local?['name'] ?? remote.name,
      'place': local?['place'] ?? remote.place,
      'phone': local?['phone'] ?? remote.phone,
      'description': local?['description'] ?? remote.description,
      'group': local?['group'],
      'createdAt': remote.createdAt,
      'updatedAt': remote.updatedAt,
      'area': remote.area,
      'perimeter': remote.perimeter,
      'pointsCount': remote.pointsCount,
      'canManage': remote.canManage,
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

  double? _areaSquareMeters(Map<String, dynamic> item) {
    if (_sectionOf(item) != _SavedContentSection.fields) return null;
    final stored = item['area'];
    if (stored is num && stored > 0) return stored.toDouble();

    final rawPoints = item['points'];
    if (rawPoints is! List || rawPoints.length < 3) return null;
    final coordinates = <(double, double)>[];
    for (final raw in rawPoints) {
      if (raw is! Map) return null;
      final lat = double.tryParse((raw['lat'] ?? raw['y']).toString());
      final lon = double.tryParse((raw['lng'] ?? raw['x']).toString());
      if (lat == null || lon == null) return null;
      coordinates.add((lat, lon));
    }

    // Match the local, small-field approximation used on the map page.
    const radius = 6378137.0;
    final lat0 =
        coordinates.map((p) => p.$1).reduce((a, b) => a + b) /
        coordinates.length;
    final lon0 =
        coordinates.map((p) => p.$2).reduce((a, b) => a + b) /
        coordinates.length;
    final lat0Radians = lat0 * pi / 180;
    final xScale = radius * cos(lat0Radians) * pi / 180;
    final yScale = radius * pi / 180;
    var sum = 0.0;
    for (var index = 0; index < coordinates.length; index++) {
      final next = (index + 1) % coordinates.length;
      final x1 = (coordinates[index].$2 - lon0) * xScale;
      final y1 = (coordinates[index].$1 - lat0) * yScale;
      final x2 = (coordinates[next].$2 - lon0) * xScale;
      final y2 = (coordinates[next].$1 - lat0) * yScale;
      sum += x1 * y2 - x2 * y1;
    }
    return sum.abs() / 2;
  }

  LandListItem? _remoteLandFromItem(Map<String, dynamic> item) {
    if (!_isRemoteItem(item)) return null;
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty) return null;

    return LandListItem(
      canManage: item['canManage'] != false,
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
      case _SavedFilter.cloudOnly:
        return 'Cloud only';
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
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(primary: _accent),
        ),
        child: SheetFrame(
          accent: _accent,
          icon: HugeIcons.strokeRoundedFilterHorizontal,
          title: context.l10n.t('Filter'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _FilterTile(
                title: sheetContext.l10n.t('All saved lands'),
                selected: _filter == _SavedFilter.all,
                onTap: () {
                  setState(() => _filter = _SavedFilter.all);
                  Navigator.pop(sheetContext);
                },
              ),
              _FilterTile(
                title: sheetContext.l10n.t('3+ points only'),
                selected: _filter == _SavedFilter.threePlusPoints,
                onTap: () {
                  setState(() => _filter = _SavedFilter.threePlusPoints);
                  Navigator.pop(sheetContext);
                },
              ),
              _FilterTile(
                title: sheetContext.l10n.t('Updated only'),
                selected: _filter == _SavedFilter.updatedOnly,
                onTap: () {
                  setState(() => _filter = _SavedFilter.updatedOnly);
                  Navigator.pop(sheetContext);
                },
              ),
              _FilterTile(
                title: sheetContext.l10n.t('Cloud records only'),
                selected: _filter == _SavedFilter.cloudOnly,
                onTap: () {
                  setState(() => _filter = _SavedFilter.cloudOnly);
                  Navigator.pop(sheetContext);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(primary: _accent),
        ),
        child: SheetFrame(
          accent: _accent,
          icon: HugeIcons.strokeRoundedSorting05,
          title: context.l10n.t('Sort'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _FilterTile(
                title: sheetContext.l10n.t('Newest first'),
                selected: _sort == _SavedSort.newest,
                onTap: () {
                  setState(() => _sort = _SavedSort.newest);
                  Navigator.pop(sheetContext);
                },
              ),
              _FilterTile(
                title: sheetContext.l10n.t('Oldest first'),
                selected: _sort == _SavedSort.oldest,
                onTap: () {
                  setState(() => _sort = _SavedSort.oldest);
                  Navigator.pop(sheetContext);
                },
              ),
              _FilterTile(
                title: sheetContext.l10n.t('Name A-Z'),
                selected: _sort == _SavedSort.nameAsc,
                onTap: () {
                  setState(() => _sort = _SavedSort.nameAsc);
                  Navigator.pop(sheetContext);
                },
              ),
              _FilterTile(
                title: sheetContext.l10n.t('Name Z-A'),
                selected: _sort == _SavedSort.nameDesc,
                onTap: () {
                  setState(() => _sort = _SavedSort.nameDesc);
                  Navigator.pop(sheetContext);
                },
              ),
              _FilterTile(
                title: sheetContext.l10n.t('Most points'),
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
      ),
    );
  }

  void _showPageMenu() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(primary: _accent),
        ),
        child: SheetFrame(
          accent: _accent,
          icon: HugeIcons.strokeRoundedMoreVertical,
          title: context.l10n.t('More'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (ref.read(authSessionProvider).isLoggedIn &&
                  ref.read(authSessionProvider).isVerified)
                SavedActionRow(
                  accent: _accent,
                  icon: HugeIcons.strokeRoundedRestoreBin,
                  label: context.l10n.t('Recycle bin'),
                  onTap: () {
                    final company = ref.read(workspaceProvider).activeCompanyId;
                    Navigator.pop(sheetContext);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => RecordRecoveryPage(
                          company: company,
                          onRestored: _fetchRemoteData,
                        ),
                      ),
                    );
                  },
                ),
              SavedActionRow(
                accent: _accent,
                icon: HugeIcons.strokeRoundedTask01,
                label: sheetContext.l10n.t('Select multiple'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  setState(() => _selectionMode = true);
                },
              ),
              SavedActionRow(
                accent: _accent,
                icon: HugeIcons.strokeRoundedFilterHorizontal,
                label: sheetContext.l10n.t('Reset filters/sort/group'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  setState(() {
                    _filter = _SavedFilter.all;
                    _sort = _SavedSort.newest;
                    _groupFilter = 'All groups';
                  });
                },
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Divider(height: 1, color: Color(0xFFE8ECF0)),
              ),
              SavedActionRow(
                accent: _accent,
                icon: HugeIcons.strokeRoundedDelete02,
                label: sheetContext.l10n.t('Delete all saved lands'),
                destructive: true,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmDeleteAll();
                },
              ),
              TextButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: Text(sheetContext.l10n.t('Cancel')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteAll() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.t('Delete all saved lands?')),
        content: Text(
          dialogContext.l10n.t(
            'Markers will be kept. This action cannot be undone.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogContext.l10n.t('Cancel')),
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
            child: Text(dialogContext.l10n.t('Delete all')),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.t('Nothing to share'))),
        );
      }
      return;
    }

    await SharePlus.instance.share(
      ShareParams(text: blocks.join('\n\n---\n\n')),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.t('Selected items shared'))),
    );
  }

  Future<void> _deleteSelectedItems() async {
    if (_selectedIds.isEmpty) return;
    for (final selectionId in _selectedIds.toList()) {
      final raw = Hive.box('landbox').get(selectionId);
      final item = selectionId.startsWith('remote:')
          ? <String, dynamic>{'cloudId': selectionId.substring(7)}
          : raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};
      if (!await _canManageLocal(item)) return;
    }
    if (!mounted) return;
    final selectedCount = _selectedIds.length;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.t('Delete selected locations?')),
        content: Text(
          dialogContext.l10n.t(
            'This will delete {count} selected items. This action cannot be undone.',
            params: {'count': '${_selectedIds.length}'},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogContext.l10n.t('Cancel')),
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
                    SnackBar(
                      content: Text(
                        context.l10n.t(
                          'Sign in again to delete cloud records.',
                        ),
                      ),
                    ),
                  );
                }
                return;
              }

              for (final landId in cloudIdsToDelete) {
                if (!await _canManageLocal({'cloudId': landId})) return;
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
                    context.l10n.t(
                      selectedCount == 1
                          ? 'Deleted {count} selected item'
                          : 'Deleted {count} selected items',
                      params: {'count': '$selectedCount'},
                    ),
                  ),
                ),
              );
            },
            child: Text(dialogContext.l10n.t('Delete')),
          ),
        ],
      ),
    );
  }

  Future<void> _setGroupForSelectedItems() async {
    if (_selectedIds.isEmpty) return;
    if (!await _canManageSelection()) return;
    if (!mounted) return;
    final controller = TextEditingController(text: context.l10n.t('General'));
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          dialogContext.l10n.t('Set group for selected'),
          style: TextStyle(fontSize: 18, color: Color(0xFF111827)),
        ),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: dialogContext.l10n.t('Group name'),
            labelStyle: TextStyle(color: Colors.grey.shade600),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogContext.l10n.t('Cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              final input = controller.text.trim();
              if (!await _canManageSelection()) return;
              if (!context.mounted) return;
              final group = input.isEmpty || input == context.l10n.t('General')
                  ? 'General'
                  : input;
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
                SnackBar(
                  content: Text(
                    context.l10n.t('Group updated for selected items'),
                  ),
                ),
              );
            },
            child: Text(dialogContext.l10n.t('Save')),
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
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: _accent),
          ),
          child: SheetFrame(
            accent: _accent,
            icon: HugeIcons.strokeRoundedLocation01,
            title:
                item['name']?.toString() ??
                item['place']?.toString() ??
                context.l10n.t('Saved location'),
            subtitle: context.l10n.t('Saved location'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SavedActionRow(
                  accent: _accent,
                  icon: HugeIcons.strokeRoundedNavigation01,
                  label: sheetContext.l10n.t('Go to'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    if (isRemote) {
                      // Prefer the local Hive copy (already has coordinates).
                      // For cloud-only records, fetch full detail from the API.
                      final cloudId = item['id']?.toString() ?? '';
                      final local = _localItemForCloudId(cloudId);
                      if (local != null) {
                        _goToSavedItem(context, local);
                      } else {
                        _fetchDetailAndAction(
                          context,
                          cloudId: cloudId,
                          item: item,
                          action: _ActionKind_goTo,
                        );
                      }
                    } else {
                      _goToSavedItem(context, item);
                    }
                  },
                ),
                SavedActionRow(
                  accent: _accent,
                  icon: HugeIcons.strokeRoundedView,
                  label: sheetContext.l10n.t('View on map'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    if (isRemote) {
                      final cloudId = item['id']?.toString() ?? '';
                      final local = _localItemForCloudId(cloudId);
                      if (local != null) {
                        _viewOnMap(context, local);
                      } else {
                        _fetchDetailAndAction(
                          context,
                          cloudId: cloudId,
                          item: item,
                          action: _ActionKind_viewOnMap,
                        );
                      }
                    } else {
                      _viewOnMap(context, item);
                    }
                  },
                ),
                if (item['canManage'] == false)
                  const ListTile(
                    leading: HugeIcon(
                      icon: HugeIcons.strokeRoundedLockKey,
                      size: 20,
                    ),
                    title: Text('Read-only record'),
                  ),
                if (item['canManage'] != false)
                  SavedActionRow(
                    accent: _accent,
                    icon: HugeIcons.strokeRoundedEdit02,
                    label: sheetContext.l10n.t('Rename'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      if (isRemote) {
                        unawaited(_editRemoteItem(context, item));
                      } else {
                        _renameItem(
                          context,
                          id,
                          item['name']?.toString() ?? '',
                        );
                      }
                    },
                  ),
                SavedActionRow(
                  accent: _accent,
                  icon: HugeIcons.strokeRoundedCopy01,
                  label: sheetContext.l10n.t('Copy coordinates'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    unawaited(
                      _withActionItem(context, item, isRemote, (data) {
                        return _copyCoordinates(context, data);
                      }),
                    );
                  },
                ),
                SavedActionRow(
                  accent: _accent,
                  icon: HugeIcons.strokeRoundedShare01,
                  label: sheetContext.l10n.t('Share'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    unawaited(
                      _withActionItem(context, item, isRemote, (data) {
                        return _shareItem(context, data);
                      }),
                    );
                  },
                ),
                SavedActionRow(
                  accent: _accent,
                  icon: HugeIcons.strokeRoundedFolder01,
                  label: sheetContext.l10n.t('Set group'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    unawaited(
                      _withActionItem(context, item, isRemote, (data) {
                        _setGroupForItem(
                          context,
                          data['id']?.toString() ?? '',
                          data,
                        );
                      }),
                    );
                  },
                ),
                if (item['canManage'] != false)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Divider(height: 1, color: Color(0xFFE8ECF0)),
                  ),
                if (item['canManage'] != false)
                  SavedActionRow(
                    accent: _accent,
                    icon: HugeIcons.strokeRoundedDelete02,
                    label: sheetContext.l10n.t('Delete'),
                    destructive: true,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _deleteItem(context, id, item: item, isRemote: isRemote);
                    },
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: Text(sheetContext.l10n.t('Cancel')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // The three-dot menu is identical for local and cloud records. Cloud-only
  // records need their full coordinates before local-style actions can run.
  Future<void> _withActionItem(
    BuildContext context,
    Map<String, dynamic> item,
    bool isRemote,
    FutureOr<void> Function(Map<String, dynamic>) action,
  ) async {
    try {
      var data = item;
      if (isRemote) {
        final cloudId = item['id']?.toString() ?? '';
        final local = _localItemForCloudId(cloudId);
        if (local != null) {
          data = local;
        } else {
          final detail = await ref.read(
            remoteLandDetailProvider(cloudId).future,
          );
          await LandSyncService(Hive.box('landbox')).cacheCloudLand(detail);
          data = _localItemForCloudId(cloudId)!;
        }
      }
      if (!context.mounted) return;
      await action(data);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.t('Something went wrong. Please try again.'),
          ),
        ),
      );
    }
  }

  Future<void> _editRemoteItem(
    BuildContext context,
    Map<String, dynamic> item,
  ) async {
    try {
      final cloudId = item['id']?.toString() ?? '';
      final detail =
          _cachedDetailForRemote(item) ??
          await ref.read(remoteLandDetailProvider(cloudId).future);
      if (detail == null) throw StateError('Cloud record not found');
      if (!detail.canManage) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This record is read-only after a plan change.'),
            ),
          );
        }
        return;
      }
      if (!context.mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _EditRemoteLandSheet(
          land: detail,
          onSaved: () async {
            ref.invalidate(remoteLandDetailProvider(detail.id));
            await _fetchRemoteData();
          },
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.t('Something went wrong. Please try again.'),
          ),
        ),
      );
    }
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
        SnackBar(content: Text(context.l10n.t('No points found for guidance'))),
      );
      return;
    }

    ref.read(landMapProvider.notifier).setNavigationTarget(target);
    widget.onOpenMapRequested?.call();
  }

  void _viewOnMap(BuildContext context, Map<String, dynamic> item) {
    final points = _extractLatLngPoints(item);
    if (points.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('No points to display on map'))),
      );
      return;
    }

    final id = item['id']?.toString();
    final name = item['name']?.toString().trim().isNotEmpty == true
        ? item['name'].toString().trim()
        : context.l10n.t('Saved location');

    ref
        .read(landMapProvider.notifier)
        .loadSavedFieldPoints(points, fieldId: id, fieldName: name);
    widget.onOpenMapRequested?.call();
  }

  // ── Cloud-only action fetch ──────────────────────────────────────────────

  /// Which action to execute once cloud coordinates are fetched.
  // ignore: constant_identifier_names
  static const _ActionKind_goTo = 0;
  // ignore: constant_identifier_names
  static const _ActionKind_viewOnMap = 1;

  /// Fetches the full [LandDetail] from the cloud API for a record that has
  /// no local Hive copy, then executes the intended [action] (go-to or
  /// view-on-map) using the fetched coordinates.
  ///
  /// Shows a loading indicator while fetching and a clear error snackbar if
  /// the fetch fails — instead of silently opening a detail sheet.
  Future<void> _fetchDetailAndAction(
    BuildContext context, {
    required String cloudId,
    required Map<String, dynamic> item,
    required int action,
  }) async {
    // Capture context-dependent objects before any async gap.
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;

    if (cloudId.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.t('No cloud ID found for this record.'))),
      );
      return;
    }

    final session = ref.read(authSessionProvider);
    if (!session.isLoggedIn || !session.isVerified) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.t('Sign in required to load cloud coordinates.'),
          ),
        ),
      );
      return;
    }

    // Show a brief loading indicator so the user knows something is happening.
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 12),
            Text(context.l10n.t('Loading coordinates…')),
          ],
        ),
        duration: Duration(seconds: 10),
      ),
    );

    try {
      final detail = await ref
          .read(landCloudServiceProvider)
          .getLand(session.token, cloudId);

      if (!mounted) return;
      messenger.hideCurrentSnackBar();

      if (detail.points.isEmpty) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.t('This record has no coordinates available.')),
          ),
        );
        return;
      }

      final localId = await LandSyncService(
        Hive.box('landbox'),
      ).cacheCloudLand(detail);

      // Convert LandPoint list → the {lat, lng} map format that
      // _goToSavedItem / _viewOnMap read via _extractLatLngPoints.
      final pointsList = detail.points
          .map(
            (p) => <String, dynamic>{
              'lat': p.y,
              'lng': p.x,
              if (p.label != null) 'label': p.label,
            },
          )
          .toList();

      final enriched = <String, dynamic>{
        ...item,
        'id': localId,
        'cloudId': detail.id,
        'points': pointsList,
      };

      if (!context.mounted) return;
      if (action == _ActionKind_goTo) {
        _goToSavedItem(context, enriched);
      } else {
        _viewOnMap(context, enriched);
      }
    } catch (e) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.t(
              'Failed to load coordinates. Check your connection and try again.',
            ),
          ),
        ),
      );
    }
  }

  // ignore: non_constant_identifier_names
  // (intentionally removed — using plain int constants above)

  /// Finds the local Hive copy for a cloud record using its cloud ID.
  /// Synced records keep a local copy with `cloudId` pointing back to the cloud.
  /// Cloud-only records (created on another device) won't have a local copy.
  Map<String, dynamic>? _localItemForCloudId(String cloudId) {
    if (cloudId.isEmpty) return null;
    final box = Hive.box('landbox');
    for (final raw in box.values) {
      if (raw is! Map) continue;
      final local = Map<String, dynamic>.from(raw);
      final localId = local['id']?.toString().trim() ?? '';
      final localCloudId = local['cloudId']?.toString().trim() ?? '';
      if (localId == cloudId || localCloudId == cloudId) return local;
    }
    return null;
  }

  LandDetail? _cachedDetailForRemote(Map<String, dynamic> remoteItem) {
    final remote = _remoteLandFromItem(remoteItem);
    if (remote == null) return null;
    final local = _localItemForCloudId(remote.id);
    if (local == null) return null;
    final rawPoints = (local['points'] as List?) ?? const [];
    final points = <LandPoint>[];
    for (var index = 0; index < rawPoints.length; index++) {
      final raw = rawPoints[index];
      if (raw is! Map) continue;
      final point = Map<String, dynamic>.from(raw);
      final lat = _toDouble(point['lat']) ?? _toDouble(point['latitude']);
      final lng = _toDouble(point['lng']) ?? _toDouble(point['longitude']);
      if (lat == null || lng == null) continue;
      points.add(
        LandPoint({
          ...point,
          'point_order': (point['order'] as num?)?.toInt() ?? index,
          'x': lng,
          'y': lat,
        }),
      );
    }
    return LandDetail(
      id: remote.id,
      userId: remote.userId,
      type: remote.type,
      name: local['name']?.toString() ?? remote.name,
      place: local['place']?.toString() ?? remote.place,
      phone: local['phone']?.toString() ?? remote.phone,
      claimantName: local['claimant_name']?.toString() ?? remote.claimantName,
      claimantPhone:
          local['claimant_phone']?.toString() ?? remote.claimantPhone,
      claimantIdMasked:
          local['claimant_id_masked']?.toString() ?? remote.claimantIdMasked,
      plotNumber: local['plot_number']?.toString() ?? remote.plotNumber,
      landUse: local['land_use']?.toString() ?? remote.landUse,
      area: remote.area,
      perimeter: remote.perimeter,
      description: local['description']?.toString() ?? remote.description,
      pointsCount: points.length,
      markersCount: remote.markersCount,
      mediaCount: remote.mediaCount,
      createdAt: local['createdAt']?.toString() ?? remote.createdAt,
      updatedAt: local['updatedAt']?.toString() ?? remote.updatedAt,
      points: points,
      markers: const [],
      media: const [],
    );
  }

  LandNavigationTarget? _buildNavigationTarget(Map<String, dynamic> item) {
    final points = _extractLatLngPoints(item);
    if (points.isEmpty) return null;
    final pointLabels = _extractPointLabels(item, points.length);

    final representative = _representativePoint(points);
    final label = item['name']?.toString().trim().isNotEmpty == true
        ? item['name'].toString().trim()
        : context.l10n.t('Saved location');
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

  Future<void> _setGroupForItem(
    BuildContext context,
    String id,
    Map<String, dynamic> item,
  ) async {
    if (!await _canManageLocal(item)) return;
    if (!context.mounted) return;
    final currentGroup = _groupOf(item);
    final controller = TextEditingController(
      text: currentGroup == 'General'
          ? context.l10n.t('General')
          : currentGroup,
    );
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.t('Set group')),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: dialogContext.l10n.t('Group name'),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogContext.l10n.t('Cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              final input = controller.text.trim();
              final group = input.isEmpty || input == context.l10n.t('General')
                  ? 'General'
                  : input;
              final box = Hive.box('landbox');
              final raw = box.get(id);
              if (raw is! Map) return;
              final data = Map<String, dynamic>.from(raw);
              data['group'] = group;
              data['updatedAt'] = DateTime.now().toIso8601String();
              await box.put(id, data);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: Text(dialogContext.l10n.t('Save')),
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

  Future<bool> _canManageSelection() async {
    for (final id in _selectedIds.toList()) {
      final raw = Hive.box('landbox').get(id);
      final item = id.startsWith('remote:')
          ? <String, dynamic>{'cloudId': id.substring(7)}
          : raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};
      if (!await _canManageLocal(item)) return false;
    }
    return mounted;
  }

  Future<void> _canManageNotice() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'This record is read-only or access could not be verified. No local changes were made.',
        ),
      ),
    );
  }

  Future<bool> _canManageLocal(Map<String, dynamic> item) async {
    final cloudId = item['cloudId']?.toString().trim() ?? '';
    if (cloudId.isEmpty) return true;
    try {
      final token = ref.read(authSessionProvider).token;
      final detail = await ref
          .read(landCloudServiceProvider)
          .getLand(token, cloudId);
      if (detail.canManage) return true;
    } catch (_) {}
    await _canManageNotice();
    return false;
  }

  Future<void> _renameItem(
    BuildContext context,
    String id,
    String currentName,
  ) async {
    final raw = Hive.box('landbox').get(id);
    if (raw is Map && !await _canManageLocal(Map<String, dynamic>.from(raw))) {
      return;
    }
    if (!context.mounted) return;
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.t('Rename location')),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: dialogContext.l10n.t('Name'),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogContext.l10n.t('Cancel')),
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
              item['updatedAt'] = DateTime.now().toIso8601String();
              if ((item['cloudId']?.toString().trim() ?? '').isNotEmpty) {
                item['syncStatus'] = 'pending';
                item['syncError'] = null;
              }
              await box.put(id, item);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: Text(dialogContext.l10n.t('Save')),
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

  Future<void> _deleteItem(
    BuildContext context,
    String id, {
    required Map<String, dynamic> item,
    required bool isRemote,
  }) async {
    final accessItem = isRemote ? {...item, 'cloudId': item['id']} : item;
    if (!await _canManageLocal(accessItem)) return;
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.t('Delete location?')),
        content: Text(dialogContext.l10n.t('This action cannot be undone.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogContext.l10n.t('Cancel')),
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
            child: Text(dialogContext.l10n.t('Delete')),
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
      throw Exception(
        context.l10n.t('Cloud deletion requires a valid session and land id.'),
      );
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
      SnackBar(
        content: Text(context.l10n.t('Land deleted from cloud and app')),
      ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('Coordinates copied'))),
      );
    }
  }

  Future<void> _shareItem(
    BuildContext context,
    Map<String, dynamic> item,
  ) async {
    final text = _buildLocalShareText(item);
    await SharePlus.instance.share(ShareParams(text: text));
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return context.l10n.t('Unknown');
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return context.l10n.t('Unknown');
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
    final l10n = context.l10n;
    final pointsRaw = (item['points'] as List?) ?? const [];
    final name = item['name']?.toString() ?? l10n.t('Saved location');
    final group = _groupOf(item);
    final createdAt = _formatDate(item['createdAt']?.toString());
    final updatedAt = _formatDate(item['updatedAt']?.toString());
    final hasUpdated = item['updatedAt']?.toString().isNotEmpty ?? false;
    final ellipsoid = ref.read(referenceEllipsoidProvider);
    final buffer = StringBuffer();

    if (includeHeader) {
      buffer
        ..writeln(name)
        ..writeln(
          '${l10n.t('Group')}: ${group == 'General' ? l10n.t('General') : group}',
        )
        ..writeln('${l10n.t('Points')}: ${pointsRaw.length}')
        ..writeln('${l10n.t('Created')}: $createdAt')
        ..writeln('${l10n.t('Updated')}: ${hasUpdated ? updatedAt : '—'}')
        ..writeln('');
    }

    for (var i = 0; i < pointsRaw.length; i++) {
      final point = pointsRaw[i];
      if (point is! Map) continue;
      final lat = _toDouble(point['lat']) ?? _toDouble(point['latitude']);
      final lng = _toDouble(point['lng']) ?? _toDouble(point['longitude']);
      if (lat == null || lng == null) continue;
      final computed = CoordinateConverter.deriveDisplayCoordinate(
        LatLng(lat, lng),
        ellipsoid,
        ref.read(selectedDatumProvider),
      ).utm;
      final easting = computed?.easting;
      final northing = computed?.northing;
      final zone = computed?.zone;
      buffer.writeln(
        _formatPointShareBlock(
          title: l10n.t('Point {count}', params: {'count': '${i + 1}'}),
          latitude: lat,
          longitude: lng,
          easting: easting,
          northing: northing,
          zone: zone,
          ellipsoid: ellipsoid,
        ),
      );
      if (i < pointsRaw.length - 1) {
        buffer.writeln();
      }
    }

    return buffer.toString().trimRight();
  }

  String _buildRemoteShareText(LandDetail detail) {
    final l10n = context.l10n;
    final points = detail.points;
    final pointLabels = _extractRemotePointLabels(points, points.length);
    final ellipsoid = ref.read(referenceEllipsoidProvider);
    final buffer = StringBuffer()
      ..writeln(detail.name.isNotEmpty ? detail.name : l10n.t('Saved location'))
      ..writeln('${l10n.t('Source')}: ${l10n.t('Cloud')}')
      ..writeln('${l10n.t('Points')}: ${points.length}')
      ..writeln('${l10n.t('Created')}: ${_formatDate(detail.createdAt)}')
      ..writeln(
        '${l10n.t('Updated')}: ${detail.updatedAt?.toString().isNotEmpty ?? false ? _formatDate(detail.updatedAt) : '—'}',
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
      final computed = CoordinateConverter.deriveDisplayCoordinate(
        LatLng(lat, lng),
        ellipsoid,
        ref.read(selectedDatumProvider),
      ).utm;
      final easting = computed?.easting;
      final northing = computed?.northing;
      buffer.writeln(
        _formatPointShareBlock(
          title: l10n.t('Point {count}', params: {'count': pointLabels[i]}),
          latitude: lat,
          longitude: lng,
          easting: easting,
          northing: northing,
          zone: computed?.zone,
          ellipsoid: ellipsoid,
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
    ReferenceEllipsoid? ellipsoid,
  }) {
    final l10n = context.l10n;
    final buffer = StringBuffer()
      ..writeln(title)
      ..writeln(
        '${l10n.t('Lat/Long')}: ${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
      );

    if (easting != null && northing != null) {
      buffer.writeln(
        '${l10n.t('E/N')}: ${easting.toStringAsFixed(2)}, ${northing.toStringAsFixed(2)}',
      );
      if (zone != null && zone.isNotEmpty) {
        final ellipsoidSuffix = ellipsoid != null
            ? ' ${l10n.t(ref.read(selectedReferenceNameProvider))}'
            : '';
        buffer.writeln('${l10n.t('Zone')}: $zone$ellipsoidSuffix');
      }
    }

    return buffer.toString().trimRight();
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

class _CloudRecordsLoadingBanner extends StatelessWidget {
  const _CloudRecordsLoadingBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primary.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.l10n.t('Updating cloud records...'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CloudRecordsLoadMoreFooter extends StatelessWidget {
  final bool isLoading;

  const _CloudRecordsLoadMoreFooter({required this.isLoading});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 10),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading) ...[
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: primary,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Text(
              context.l10n.t('Loading more records...'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
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
  final _SavedContentSection section;
  final double? areaSquareMeters;
  final DistanceUnit distanceUnit;
  final bool isCloudSynced;
  final bool waitingForSpace;
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
    required this.section,
    required this.areaSquareMeters,
    required this.distanceUnit,
    required this.isCloudSynced,
    this.waitingForSpace = false,
    required this.viewMode,
    required this.compactMode,
    required this.selectionMode,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    required this.onMore,
  });

  String get _kindLabel => switch (section) {
    _SavedContentSection.markers => 'Point',
    _SavedContentSection.fields => 'Area',
    _SavedContentSection.distances => 'Route',
    _SavedContentSection.all => 'Location',
  };

  dynamic get _kindIcon => switch (section) {
    _SavedContentSection.markers => HugeIcons.strokeRoundedLocation01,
    _SavedContentSection.fields => HugeIcons.strokeRoundedSquare,
    _SavedContentSection.distances => HugeIcons.strokeRoundedRoute01,
    _SavedContentSection.all => HugeIcons.strokeRoundedLocation01,
  };

  String _measurementLabel(AppLocalizations l10n) =>
      section == _SavedContentSection.fields &&
          areaSquareMeters != null &&
          areaSquareMeters! > 0
      ? MeasurementFormatter.area(areaSquareMeters!, distanceUnit)
      : l10n.t(
          points == 1 ? '{count} point' : '{count} points',
          params: {'count': '$points'},
        );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final dateText = _formatDate(createdAt, l10n);
    final updatedText = _formatDate(updatedAt, l10n);
    final createdTime = DateTime.tryParse(createdAt ?? '');
    final updatedTime = DateTime.tryParse(updatedAt ?? '');
    final hasUpdated =
        updatedTime != null &&
        (createdTime == null || updatedTime.isAfter(createdTime));

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: compactMode ? 10 : 16,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : const Color(0xFFE8ECF0),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildContent(context, theme, dateText, hasUpdated, updatedText),
            if (waitingForSpace)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.tertiaryContainer.withValues(
                      alpha: 0.4,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.cloud_queue_outlined, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Waiting for space',
                              style: theme.textTheme.labelLarge,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Saved on this device. Cloud sync will retry when space is available.',
                        style: theme.textTheme.bodySmall,
                      ),
                      TextButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const PlansAccessPage(),
                          ),
                        ),
                        icon: const Icon(
                          Icons.manage_accounts_outlined,
                          size: 16,
                        ),
                        label: const Text('View plan access'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    ThemeData theme,
    String dateText,
    bool hasUpdated,
    String updatedText,
  ) {
    switch (viewMode) {
      case _ViewMode.basic:
        return _buildBasic(context, theme, dateText);
      case _ViewMode.text:
        return _buildText(context, theme, dateText);
      case _ViewMode.photo:
        return _buildPhoto(context, theme, dateText);
      case _ViewMode.combined:
        return _buildCombined(
          context,
          theme,
          dateText,
          hasUpdated,
          updatedText,
        );
    }
  }

  Widget _buildCombined(
    BuildContext context,
    ThemeData theme,
    String dateText,
    bool hasUpdated,
    String updatedText,
  ) {
    final l10n = context.l10n;
    final subtitle = '${l10n.t(_kindLabel)} · ${_measurementLabel(l10n)}';
    final dateLabel = hasUpdated
        ? l10n.t('Updated {date}', params: {'date': updatedText})
        : l10n.t('Saved {date}', params: {'date': dateText});
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
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: HugeIcon(
            icon: _kindIcon,
            color: theme.colorScheme.primary,
            size: 20,
          ),
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
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
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
                group == 'General' ? dateLabel : '$group · $dateLabel',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.black54,
                ),
              ),
            ],
          ),
        ),
        if (isCloudSynced)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Tooltip(
              message: l10n.t('Saved to cloud'),
              child: HugeIcon(
                icon: HugeIcons.strokeRoundedCloud,
                size: 18,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        if (!selectionMode)
          IconButton(
            onPressed: onMore,
            tooltip: l10n.t('Actions for {name}', params: {'name': name}),
            icon: const HugeIcon(icon: HugeIcons.strokeRoundedMoreVertical),
          ),
      ],
    );
  }

  Widget _buildBasic(BuildContext context, ThemeData theme, String dateText) {
    final l10n = context.l10n;
    return Row(
      children: [
        if (selectionMode) ...[
          Icon(
            isSelected ? Icons.check_circle : Icons.circle_outlined,
            color: isSelected ? theme.colorScheme.primary : Colors.black45,
          ),
          SizedBox(width: compactMode ? 8 : 10),
        ],
        HugeIcon(icon: _kindIcon, color: theme.colorScheme.primary, size: 20),
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
                '${l10n.t(_kindLabel)} · ${_measurementLabel(l10n)}',
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
            child: HugeIcon(
              icon: HugeIcons.strokeRoundedCloud,
              size: 18,
              color: theme.colorScheme.primary,
            ),
          ),
        if (!selectionMode) ...[
          SizedBox(width: compactMode ? 2 : 6),
          IconButton(
            onPressed: onMore,
            tooltip: l10n.t('Actions for {name}', params: {'name': name}),
            icon: const HugeIcon(icon: HugeIcons.strokeRoundedMoreVertical),
          ),
        ],
      ],
    );
  }

  Widget _buildText(BuildContext context, ThemeData theme, String dateText) {
    final l10n = context.l10n;
    final updatedText = _formatDate(updatedAt, l10n);
    final createdTime = DateTime.tryParse(createdAt ?? '');
    final updatedTime = DateTime.tryParse(updatedAt ?? '');
    final hasUpdated =
        updatedTime != null &&
        (createdTime == null || updatedTime.isAfter(createdTime));
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
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (isCloudSynced)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedCloud,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
              ),
            if (!selectionMode)
              IconButton(
                onPressed: onMore,
                tooltip: l10n.t('Actions for {name}', params: {'name': name}),
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedMoreVertical),
              ),
          ],
        ),
        SizedBox(height: compactMode ? 4 : 6),
        Text(
          '${l10n.t(_kindLabel)} · ${_measurementLabel(l10n)}',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
        ),
        if (group != 'General') ...[
          const SizedBox(height: 2),
          Text(
            '${l10n.t('Group')}: $group',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 2),
        Text(
          '${l10n.t('Created')}: $dateText',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
        ),
        const SizedBox(height: 2),
        Text(
          '${l10n.t('Updated')}: ${hasUpdated ? updatedText : '—'}',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
        ),
      ],
    );
  }

  Widget _buildPhoto(BuildContext context, ThemeData theme, String dateText) {
    final l10n = context.l10n;
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
                child: HugeIcon(
                  icon: _kindIcon,
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
                    '${l10n.t(_kindLabel)} · ${_measurementLabel(l10n)}',
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
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (isCloudSynced)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedCloud,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
              ),
            if (!selectionMode)
              IconButton(
                onPressed: onMore,
                tooltip: l10n.t('Actions for {name}', params: {'name': name}),
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedMoreVertical),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          group == 'General' ? dateText : '$group · $dateText',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
        ),
      ],
    );
  }

  String _formatDate(String? iso, AppLocalizations l10n) {
    if (iso == null || iso.isEmpty) return l10n.t('Unknown');
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return l10n.t('Unknown');
    final yyyy = parsed.year.toString().padLeft(4, '0');
    final mm = parsed.month.toString().padLeft(2, '0');
    final dd = parsed.day.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy';
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
  late final TextEditingController _claimantNameController;
  late final TextEditingController _claimantPhoneController;
  late final TextEditingController _plotNumberController;
  late final TextEditingController _landUseController;
  late final int? _companyAtOpen;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _companyAtOpen = WorkspaceContext.activeCompanyId;
    _nameController = TextEditingController(text: widget.land.name);
    _placeController = TextEditingController(text: widget.land.place ?? '');
    _phoneController = TextEditingController(text: widget.land.phone ?? '');
    _descriptionController = TextEditingController(
      text: widget.land.description ?? '',
    );
    _claimantNameController = TextEditingController(
      text: widget.land.claimantName ?? '',
    );
    _claimantPhoneController = TextEditingController(
      text: widget.land.claimantPhone ?? '',
    );
    _plotNumberController = TextEditingController(
      text: widget.land.plotNumber ?? '',
    );
    _landUseController = TextEditingController(text: widget.land.landUse ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _placeController.dispose();
    _phoneController.dispose();
    _descriptionController.dispose();
    _claimantNameController.dispose();
    _claimantPhoneController.dispose();
    _plotNumberController.dispose();
    _landUseController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_companyAtOpen != WorkspaceContext.activeCompanyId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Workspace changed. Reopen this record.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final syncService = LandSyncService(Hive.box('landbox'));
      await syncService.queueMetadataEdit(
        detail: widget.land,
        name: _nameController.text,
        place: _placeController.text,
        phone: _phoneController.text,
        description: _descriptionController.text,
        claimantName: _companyAtOpen == null
            ? null
            : _claimantNameController.text,
        claimantPhone: _companyAtOpen == null
            ? null
            : _claimantPhoneController.text,
        plotNumber: _companyAtOpen == null ? null : _plotNumberController.text,
        landUse: _companyAtOpen == null ? null : _landUseController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.t('Changes saved. They will sync when connected.'),
          ),
        ),
      );
      unawaited(_syncAndRefresh(syncService));
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

  Future<void> _syncAndRefresh(LandSyncService syncService) async {
    try {
      final result = await syncService.syncPendingLands(limit: 10);
      if (result.synced > 0) {
        await widget.onSaved();
      }
    } catch (_) {
      // The edit is already safe in Hive and remains pending for the periodic
      // background sync. A failed opportunistic refresh must not undo it.
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
                    context.l10n.t('Edit cloud land'),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: context.l10n.t('Name'),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? context.l10n.t('Name is required')
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _placeController,
                    decoration: InputDecoration(
                      labelText: context.l10n.t('Place'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _phoneController,
                    decoration: InputDecoration(
                      labelText: context.l10n.t('Phone'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _descriptionController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: context.l10n.t('Description'),
                    ),
                  ),
                  if (_companyAtOpen != null) ...[
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _claimantNameController,
                      decoration: const InputDecoration(
                        labelText: 'Owner / claimant',
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _claimantPhoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Owner phone',
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _plotNumberController,
                      decoration: const InputDecoration(
                        labelText: 'Plot number',
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _landUseController,
                      decoration: const InputDecoration(labelText: 'Land use'),
                    ),
                    if (widget.land.claimantIdMasked?.isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Text(
                          'Owner ID: ${widget.land.claimantIdMasked}',
                        ),
                      ),
                  ],
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
                          : Text(context.l10n.t('Save changes')),
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
    final accent = Theme.of(context).colorScheme.primary;
    return SheetOptionTile(
      accent: accent,
      leading: SheetLeadingIcon(
        icon: HugeIcons.strokeRoundedFilterHorizontal,
        accent: accent,
        selected: selected,
      ),
      title: title,
      selected: selected,
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
            context.l10n.t(title),
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.t(subtitle),
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
            child: const HugeIcon(
              icon: HugeIcons.strokeRoundedCancel01,
              size: 14,
              color: Color(0xFF0B8A8D),
            ),
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
  late final int? _companyAtOpen;

  @override
  void initState() {
    super.initState();
    _companyAtOpen = ref.read(workspaceProvider).activeCompanyId;
  }

  bool _showAllPoints = false;
  bool _isDeleting = false;

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
        return const Color(0xFF001F3F);
      case 'polyline':
        return const Color(0xFFF59E0B);
      case 'point':
        return const Color(0xFF001F3F);
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
        : widget.localItem!['name']?.toString() ??
              context.l10n.t('Saved location');
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
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: HugeIcon(
                        icon: switch (type.toLowerCase()) {
                          'polygon' => HugeIcons.strokeRoundedSquare,
                          'polyline' => HugeIcons.strokeRoundedRoute01,
                          _ => HugeIcons.strokeRoundedLocation01,
                        },
                        size: 22,
                        color: badgeColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
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
                                  context.l10n.t(_typeBadgeLabel(type)),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: badgeColor,
                                  ),
                                ),
                              ),
                              if (isCloudSynced) ...[
                                const SizedBox(width: 8),
                                HugeIcon(
                                  icon: HugeIcons.strokeRoundedCloud,
                                  size: 16,
                                  color: theme.colorScheme.primary,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
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
                      tooltip: context.l10n.t('Cancel'),
                      icon: const HugeIcon(
                        icon: HugeIcons.strokeRoundedCancel01,
                        size: 20,
                        color: Colors.black45,
                      ),
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
                            const HugeIcon(
                              icon: HugeIcons.strokeRoundedAlertCircle,
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
                              child: Text(context.l10n.t('Retry')),
                            ),
                          ],
                        ),
                      )
                    : ColoredBox(
                        color: const Color(0xFFF7F7F8),
                        child: ListView(
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
                              claimantName: _companyAtOpen == null
                                  ? null
                                  : (widget.isCloud
                                        ? (_cloudDetail?.claimantName ??
                                              widget.cloudItem!.claimantName)
                                        : widget.localItem!['claimant_name']
                                              ?.toString()),
                              claimantPhone: _companyAtOpen == null
                                  ? null
                                  : (widget.isCloud
                                        ? (_cloudDetail?.claimantPhone ??
                                              widget.cloudItem!.claimantPhone)
                                        : widget.localItem!['claimant_phone']
                                              ?.toString()),
                              claimantIdMasked: _companyAtOpen == null
                                  ? null
                                  : (widget.isCloud
                                        ? (_cloudDetail?.claimantIdMasked ??
                                              widget
                                                  .cloudItem!
                                                  .claimantIdMasked)
                                        : widget
                                              .localItem!['claimant_id_masked']
                                              ?.toString()),
                              plotNumber: _companyAtOpen == null
                                  ? null
                                  : (widget.isCloud
                                        ? (_cloudDetail?.plotNumber ??
                                              widget.cloudItem!.plotNumber)
                                        : widget.localItem!['plot_number']
                                              ?.toString()),
                              landUse: _companyAtOpen == null
                                  ? null
                                  : (widget.isCloud
                                        ? (_cloudDetail?.landUse ??
                                              widget.cloudItem!.landUse)
                                        : widget.localItem!['land_use']
                                              ?.toString()),
                              createdAt: createdAt,
                              updatedAt: updatedAt,
                              type: type,
                              points: points,
                            ),
                            const SizedBox(height: 12),
                            // Points card
                            if (_companyAtOpen != null && isCloudSynced)
                              RecordOrganizationSection(
                                company: _companyAtOpen,
                                record: widget.isCloud
                                    ? widget.cloudItem!.id
                                    : widget.localItem!['cloudId'].toString(),
                                canManage: widget.isCloud
                                    ? (_cloudDetail?.canManage ?? false)
                                    : widget.localItem!['canManage'] != false,
                                onChanged: widget.onRemoteChanged,
                              ),
                            if (points.isNotEmpty)
                              _buildPointsCard(context, points),
                            const SizedBox(height: 12),
                            // Actions card
                            _buildActionsCard(context),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapCard(BuildContext context, List<LatLng> points, String type) {
    final color = _typeBadgeColor(type);
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 200,
          child: FlutterMap(
            options: MapOptions(
              initialCenter: points.first,
              initialZoom: 15,
              initialCameraFit: points.any((p) => p != points.first)
                  ? CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(points),
                      padding: const EdgeInsets.all(28),
                      maxZoom: 18,
                    )
                  : null,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.none,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.databenki.taref_gps',
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
    String? claimantName,
    String? claimantPhone,
    String? claimantIdMasked,
    String? plotNumber,
    String? landUse,
    required String? createdAt,
    required String? updatedAt,
    required String type,
    List<LatLng> points = const [],
  }) {
    // Compute perimeter and area from points
    final distanceCalc = const Distance();
    final normalizedType = type.toLowerCase();
    String? perimeterText;
    String? areaText;

    if (points.length >= 2) {
      double perimeter = 0;
      for (int i = 0; i < points.length - 1; i++) {
        perimeter += distanceCalc.as(
          LengthUnit.Meter,
          points[i],
          points[i + 1],
        );
      }
      // Close loop for polygons
      if (normalizedType == 'polygon' && points.length >= 3) {
        perimeter += distanceCalc.as(
          LengthUnit.Meter,
          points.last,
          points.first,
        );
      }
      perimeterText = _formatMeasurement(perimeter);
    }

    if ((normalizedType == 'polygon') && points.length >= 3) {
      final area = _computeAreaSqm(points);
      areaText = _formatArea(area);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8ECF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedInformationCircle,
                size: 16,
                color: Colors.grey.shade500,
              ),
              const SizedBox(width: 6),
              Text(
                context.l10n.t('Details'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InfoRow(
            label: context.l10n.t('Type'),
            value: context.l10n.t(_typeBadgeLabel(type)),
          ),
          if (place?.trim().isNotEmpty == true)
            _InfoRow(label: context.l10n.t('Place'), value: place!),
          if (phone?.trim().isNotEmpty == true)
            _InfoRow(label: context.l10n.t('Phone'), value: phone!),
          if (description?.trim().isNotEmpty == true)
            _InfoRow(label: context.l10n.t('Description'), value: description!),
          if ([
            claimantName,
            claimantPhone,
            claimantIdMasked,
            plotNumber,
            landUse,
          ].any((value) => value?.trim().isNotEmpty == true)) ...[
            const Divider(height: 28),
            Text(
              'Customer & parcel',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
          ],
          if (claimantName?.trim().isNotEmpty == true)
            _InfoRow(label: 'Owner / claimant', value: claimantName!),
          if (claimantPhone?.trim().isNotEmpty == true)
            _InfoRow(label: 'Owner phone', value: claimantPhone!),
          if (claimantIdMasked?.trim().isNotEmpty == true)
            _InfoRow(label: 'Owner ID (masked)', value: claimantIdMasked!),
          if (plotNumber?.trim().isNotEmpty == true)
            _InfoRow(label: 'Plot number', value: plotNumber!),
          if (landUse?.trim().isNotEmpty == true)
            _InfoRow(label: 'Land use', value: landUse!),
          const Divider(height: 28),
          Text(
            'Measurements & dates',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          if (perimeterText != null)
            _InfoRow(label: context.l10n.t('Perimeter'), value: perimeterText),
          if (areaText != null)
            _InfoRow(label: context.l10n.t('Area'), value: areaText),
          _InfoRow(
            label: context.l10n.t('Created'),
            value: _formatDate(createdAt),
          ),
          if (updatedAt?.trim().isNotEmpty == true)
            _InfoRow(
              label: context.l10n.t('Updated'),
              value: _formatDate(updatedAt),
            ),
        ],
      ),
    );
  }

  String _formatMeasurement(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(2)} km';
    }
    return '${meters.toStringAsFixed(1)} m';
  }

  String _formatArea(double sqm) {
    if (sqm >= 10000) {
      return '${(sqm / 10000).toStringAsFixed(4)} ha (${sqm.toStringAsFixed(1)} m²)';
    }
    return '${sqm.toStringAsFixed(1)} m²';
  }

  double _computeAreaSqm(List<LatLng> points) {
    if (points.length < 3) return 0;
    const radius = 6378137.0;
    final lat0 =
        points.map((e) => e.latitude).reduce((a, b) => a + b) / points.length;
    final lon0 =
        points.map((e) => e.longitude).reduce((a, b) => a + b) / points.length;
    final lat0Rad = lat0 * pi / 180.0;
    final lon0Rad = lon0 * pi / 180.0;
    final projected = points.map((p) {
      final latRad = p.latitude * pi / 180.0;
      final lonRad = p.longitude * pi / 180.0;
      final x = radius * (lonRad - lon0Rad) * cos(lat0Rad);
      final y = radius * (latRad - lat0Rad);
      return Offset(x, y);
    }).toList();
    double sum = 0;
    for (int i = 0; i < projected.length; i++) {
      final j = (i + 1) % projected.length;
      sum += projected[i].dx * projected[j].dy;
      sum -= projected[j].dx * projected[i].dy;
    }
    return sum.abs() / 2.0;
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
        border: Border.all(color: const Color(0xFFE8ECF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedLocation01,
                size: 16,
                color: Colors.grey.shade500,
              ),
              const SizedBox(width: 6),
              Text(
                context.l10n.t(
                  'Points ({count})',
                  params: {'count': '${points.length}'},
                ),
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
                        // Always show easting/northing computed from lat/lng
                        Builder(
                          builder: (context) {
                            final ellipsoid = ref.read(
                              referenceEllipsoidProvider,
                            );
                            final utm = UtmConverter.fromLatLng(
                              p.latitude,
                              p.longitude,
                              ellipsoid,
                            );
                            if (utm == null) {
                              return const SizedBox.shrink();
                            }
                            return Text(
                              '${context.l10n.t('E')} ${utm.easting.toStringAsFixed(2)}  ${context.l10n.t('N')} ${utm.northing.toStringAsFixed(2)}  ${context.l10n.t('Zone')} ${utm.zoneNumber}${utm.zoneLetter}',
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
                    ? context.l10n.t('Show less')
                    : context.l10n.t(
                        'Show all {count} points',
                        params: {'count': '${points.length}'},
                      ),
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
        border: Border.all(color: const Color(0xFFE8ECF0)),
      ),
      child: Column(
        children: [
          SheetSectionLabel(context.l10n.t('Actions')),
          // Go to map — always shown
          if (widget.isCloud ||
              (widget.localItem?['cloudId']?.toString().isNotEmpty ?? false))
            _ActionRow(
              icon: HugeIcons.strokeRoundedNote01,
              label: 'Custom fields',
              color: theme.colorScheme.primary,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RecordCustomFieldsPage(
                    company: _companyAtOpen,
                    record: widget.isCloud
                        ? widget.cloudItem!.id
                        : widget.localItem!['cloudId'].toString(),
                  ),
                ),
              ),
            ),
          if (widget.isCloud ||
              (widget.localItem?['cloudId']?.toString().isNotEmpty ?? false))
            _ActionRow(
              icon: HugeIcons.strokeRoundedPdf01,
              label: context.l10n.t('Parcel PDF'),
              color: theme.colorScheme.primary,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ParcelPdfPage(
                    company: _companyAtOpen,
                    record: widget.isCloud
                        ? widget.cloudItem!.id
                        : widget.localItem!['cloudId'].toString(),
                    name: widget.isCloud
                        ? (_cloudDetail?.name ?? widget.cloudItem!.name)
                        : widget.localItem!['name']?.toString() ??
                              'Saved record',
                  ),
                ),
              ),
            ),
          if (widget.isCloud ||
              (widget.localItem?['cloudId']?.toString().isNotEmpty ?? false))
            _ActionRow(
              icon: HugeIcons.strokeRoundedLink01,
              label: 'Share link',
              color: theme.colorScheme.primary,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RecordSharingPage(
                    company: _companyAtOpen,
                    record: widget.isCloud
                        ? widget.cloudItem!.id
                        : widget.localItem!['cloudId'].toString(),
                  ),
                ),
              ),
            ),
          if (widget.isCloud ||
              (widget.localItem?['cloudId']?.toString().isNotEmpty ?? false))
            _ActionRow(
              icon: HugeIcons.strokeRoundedFileExport,
              label: context.l10n.t('Export file'),
              color: theme.colorScheme.primary,
              onTap: () {
                final record = widget.isCloud
                    ? widget.cloudItem!.id
                    : widget.localItem!['cloudId'].toString();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RecordExportPage(
                      company: _companyAtOpen,
                      record: record,
                      name: widget.isCloud
                          ? (_cloudDetail?.name ?? widget.cloudItem!.name)
                          : widget.localItem!['name']?.toString() ??
                                'Saved record',
                    ),
                  ),
                );
              },
            ),
          if (widget.isCloud ||
              (widget.localItem?['cloudId']?.toString().isNotEmpty ?? false))
            _ActionRow(
              icon: HugeIcons.strokeRoundedClock01,
              label: context.l10n.t('Record history'),
              color: theme.colorScheme.primary,
              onTap: () async {
                var restored = false;
                final record = widget.isCloud
                    ? widget.cloudItem!.id
                    : widget.localItem!['cloudId'].toString();
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RecordRecoveryPage(
                      company: _companyAtOpen,
                      record: record,
                      canManage: widget.isCloud
                          ? (_cloudDetail?.canManage ?? false)
                          : widget.localItem!['canManage'] != false,
                      onRestored: () async {
                        restored = true;
                        await widget.onRemoteChanged?.call();
                      },
                    ),
                  ),
                );
                if (mounted && restored) Navigator.of(this.context).pop();
              },
            ),
          _ActionRow(
            icon: HugeIcons.strokeRoundedNavigation01,
            label: context.l10n.t('Go to map'),
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
              } else {
                final points = _localPoints;
                if (points.isNotEmpty) {
                  final item = widget.localItem!;
                  final name =
                      item['name']?.toString().trim().isNotEmpty == true
                      ? item['name'].toString().trim()
                      : context.l10n.t('Saved location');
                  final type =
                      item['entityType']?.toString().trim().isNotEmpty == true
                      ? item['entityType'].toString().trim()
                      : item['type']?.toString().trim() ?? 'polygon';
                  final rawPts = (item['points'] as List?) ?? const [];
                  final topLabels = (item['labels'] as List?) ?? const [];
                  final pointLabels = List<String>.generate(points.length, (i) {
                    if (i < rawPts.length && rawPts[i] is Map) {
                      final label = rawPts[i]['label']?.toString().trim() ?? '';
                      if (label.isNotEmpty) return label;
                    }
                    if (i < topLabels.length) {
                      final label = topLabels[i]?.toString().trim() ?? '';
                      if (label.isNotEmpty) return label;
                    }
                    return '${i + 1}';
                  });
                  final target = LandNavigationTarget(
                    point: _representativePoint(points),
                    points: points,
                    pointLabels: pointLabels,
                    label: name,
                    kind: _navigationKind(type, points.length),
                  );
                  ref
                      .read(landMapProvider.notifier)
                      .setNavigationTarget(target);
                }
              }
              widget.onOpenMapRequested?.call();
            },
          ),
          const Divider(height: 1, indent: 56),
          // View on map — loads points without navigation
          _ActionRow(
            icon: HugeIcons.strokeRoundedView,
            label: context.l10n.t('View on map'),
            onTap: () async {
              final points = widget.isCloud ? _cloudPoints : _localPoints;
              if (points.isEmpty) return;
              final name = widget.isCloud
                  ? widget.cloudItem!.name
                  : widget.localItem!['name']?.toString() ??
                        context.l10n.t('Saved location');
              String? id;
              if (widget.isCloud) {
                final detail = _cloudDetail;
                if (detail == null) return;
                id = await LandSyncService(
                  Hive.box('landbox'),
                ).cacheCloudLand(detail);
              } else {
                id = widget.localItem!['id']?.toString();
              }
              if (!context.mounted) return;
              Navigator.of(context).pop();
              ref
                  .read(landMapProvider.notifier)
                  .loadSavedFieldPoints(points, fieldId: id, fieldName: name);
              widget.onOpenMapRequested?.call();
            },
          ),
          const Divider(height: 1, indent: 56),
          if (widget.isCloud && _cloudDetail?.canManage == false)
            const ListTile(
              leading: HugeIcon(icon: HugeIcons.strokeRoundedLockKey),
              title: Text('Read-only record'),
              subtitle: Text(
                'Viewing, navigation and coordinate sharing remain available.',
              ),
            ),
          if (widget.isCloud && _cloudDetail?.canManage != false) ...[
            _ActionRow(
              icon: HugeIcons.strokeRoundedEdit02,
              label: context.l10n.t('Edit metadata'),
              onTap: () async {
                final detail = _cloudDetail;
                if (detail == null) return;
                await showModalBottomSheet<void>(
                  // Recheck permission in the cloud service before any queued edit is uploaded.
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
              icon: HugeIcons.strokeRoundedRefresh,
              label: context.l10n.t('Refresh'),
              onTap: () => ref.invalidate(
                remoteLandDetailProvider(widget.cloudItem!.id),
              ),
            ),
            const Divider(height: 1, indent: 56),
            _ActionRow(
              icon: HugeIcons.strokeRoundedDelete02,
              label: _isDeleting
                  ? context.l10n.t('Deleting...')
                  : context.l10n.t('Delete land'),
              color: Colors.red,
              onTap: _isDeleting ? null : () => _deleteCloudLand(context),
            ),
          ] else ...[
            _ActionRow(
              icon: HugeIcons.strokeRoundedEdit02,
              label: context.l10n.t('Rename'),
              onTap: () {
                Navigator.of(context).pop();
                // Caller handles rename.
              },
            ),
            const Divider(height: 1, indent: 56),
            _ActionRow(
              icon: HugeIcons.strokeRoundedCopy01,
              label: context.l10n.t('Copy coordinates'),
              onTap: () async {
                final pts = (widget.localItem!['points'] as List?) ?? [];
                final coords = pts
                    .map((p) => '${p['lat']},${p['lng']}')
                    .join('\n');
                await Clipboard.setData(ClipboardData(text: coords));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.l10n.t('Coordinates copied'))),
                );
              },
            ),
            const Divider(height: 1, indent: 56),
            _ActionRow(
              icon: HugeIcons.strokeRoundedDelete02,
              label: context.l10n.t('Delete'),
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
        title: Text(ctx.l10n.t('Delete cloud land?')),
        content: Text(
          ctx.l10n.t(
            'This will delete "{name}" from the server.',
            params: {'name': widget.cloudItem!.name},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.t('Cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.t('Delete')),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('Land deleted from cloud'))),
      );
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
        title: Text(ctx.l10n.t('Delete location?')),
        content: Text(ctx.l10n.t('This action cannot be undone.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.l10n.t('Cancel')),
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
            child: Text(ctx.l10n.t('Delete')),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final dynamic icon;
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
    final c = color ?? Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: HugeIcon(icon: icon, size: 20, color: c),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: c,
                ),
              ),
            ),
            const SizedBox(width: 8),
            HugeIcon(
              icon: HugeIcons.strokeRoundedArrowRight01,
              size: 18,
              color: Colors.grey.shade400,
            ),
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
    return RecordDetailValue(label: label, value: value);
  }
}

class _ManualCoordinateEntrySheet extends ConsumerStatefulWidget {
  final VoidCallback onSaved;

  const _ManualCoordinateEntrySheet({required this.onSaved});

  @override
  ConsumerState<_ManualCoordinateEntrySheet> createState() =>
      _ManualCoordinateEntrySheetState();
}

enum _CoordInputMode { latLng, utm }

class _ManualCoordinateEntrySheetState
    extends ConsumerState<_ManualCoordinateEntrySheet> {
  final _nameController = TextEditingController();
  final _placeController = TextEditingController();
  final _phoneController = TextEditingController();
  final _descriptionController = TextEditingController();

  _CoordInputMode _inputMode = _CoordInputMode.latLng;
  String _recordType = 'auto'; // auto, point, polyline, polygon
  final List<_ManualPoint> _points = [];
  bool _isSaving = false;
  String? _feedbackMessage;
  bool _feedbackIsError = false;

  // LatLng input controllers
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  final _latLngLabelController = TextEditingController();

  // UTM input controllers
  final _eastingController = TextEditingController();
  final _northingController = TextEditingController();
  final _zoneController = TextEditingController();
  final _bandController = TextEditingController();
  String _hemisphere = 'S';
  final _utmLabelController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _placeController.dispose();
    _phoneController.dispose();
    _descriptionController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _latLngLabelController.dispose();
    _eastingController.dispose();
    _northingController.dispose();
    _zoneController.dispose();
    _bandController.dispose();
    _utmLabelController.dispose();
    super.dispose();
  }

  void _addPoint() {
    if (_inputMode == _CoordInputMode.latLng) {
      final lat = double.tryParse(_latController.text.trim());
      final lng = double.tryParse(_lngController.text.trim());
      if (lat == null || lng == null) {
        _setFeedback('Enter valid latitude and longitude.', isError: true);
        return;
      }
      if (lat < -90 || lat > 90) {
        _setFeedback('Latitude must be between -90 and 90.', isError: true);
        return;
      }
      if (lng < -180 || lng > 180) {
        _setFeedback('Longitude must be between -180 and 180.', isError: true);
        return;
      }
      if (lat == 0 && lng == 0) {
        _setFeedback(
          'Coordinates 0, 0 point to the Gulf of Guinea. Please enter real coordinates.',
          isError: true,
        );
        return;
      }
      if (lat.abs() < 0.001 && lng.abs() < 0.001) {
        _setFeedback(
          'These coordinates are near 0,0 which is unlikely to be a real location.',
          isError: true,
        );
        return;
      }

      // Convert to UTM
      final ellipsoid = ref.read(referenceEllipsoidProvider);
      final utm = UtmConverter.fromLatLng(lat, lng, ellipsoid);

      setState(() {
        _points.add(
          _ManualPoint(
            label: _latLngLabelController.text.trim().isEmpty
                ? '${_points.length + 1}'
                : _latLngLabelController.text.trim(),
            lat: lat,
            lng: lng,
            easting: utm?.easting,
            northing: utm?.northing,
            zone: utm?.zoneNumber.toString(),
            band: utm?.zoneLetter,
            hemisphere: lat >= 0 ? 'N' : 'S',
          ),
        );
        _latController.clear();
        _lngController.clear();
        _latLngLabelController.clear();
      });
      _setFeedback(
        'Point {count} added.',
        params: {'count': '${_points.length}'},
        isError: false,
      );
    } else {
      final easting = double.tryParse(_eastingController.text.trim());
      final northing = double.tryParse(_northingController.text.trim());
      final zone = _zoneController.text.trim();
      final band = _bandController.text.trim();

      if (easting == null || northing == null) {
        _setFeedback('Enter valid easting and northing.', isError: true);
        return;
      }
      if (zone.isEmpty) {
        _setFeedback('Zone number is required.', isError: true);
        return;
      }

      final zoneNumber = int.tryParse(zone);
      if (zoneNumber == null || zoneNumber < 1 || zoneNumber > 60) {
        _setFeedback('Zone must be between 1 and 60.', isError: true);
        return;
      }

      if (easting < 100000 || easting > 900000) {
        _setFeedback(
          'Easting must be between 100,000 and 900,000 meters.',
          isError: true,
        );
        return;
      }

      if (northing < 0 || northing > 10000000) {
        _setFeedback(
          'Northing must be between 0 and 10,000,000 meters.',
          isError: true,
        );
        return;
      }

      if (band.isNotEmpty) {
        final upper = band.toUpperCase();
        if (upper.length != 1 ||
            !RegExp(r'[C-X]').hasMatch(upper) ||
            upper == 'I' ||
            upper == 'O') {
          _setFeedback(
            'Band letter must be C-X (excluding I and O).',
            isError: true,
          );
          return;
        }
      }

      // Convert UTM back to lat/lng
      final ellipsoid = ref.read(referenceEllipsoidProvider);
      final latLng = UtmConverter.toLatLng(
        easting: easting,
        northing: northing,
        zoneNumber: zoneNumber,
        zoneLetter: band.isEmpty ? 'M' : band.toUpperCase(),
        ellipsoid: ellipsoid,
        hemisphere: _hemisphere,
      );

      if (latLng == null) {
        _setFeedback(
          'Could not convert these UTM values to coordinates. Check your input.',
          isError: true,
        );
        return;
      }

      // Sanity check the resulting lat/lng
      if (latLng.latitude < -90 ||
          latLng.latitude > 90 ||
          latLng.longitude < -180 ||
          latLng.longitude > 180) {
        _setFeedback(
          'UTM values produce invalid coordinates. Please verify easting, northing, and zone.',
          isError: true,
        );
        return;
      }

      setState(() {
        _points.add(
          _ManualPoint(
            label: _utmLabelController.text.trim().isEmpty
                ? '${_points.length + 1}'
                : _utmLabelController.text.trim(),
            lat: latLng.latitude,
            lng: latLng.longitude,
            easting: easting,
            northing: northing,
            zone: zone,
            band: band.isEmpty ? null : band.toUpperCase(),
            hemisphere: _hemisphere,
          ),
        );
        _eastingController.clear();
        _northingController.clear();
        _zoneController.clear();
        _bandController.clear();
        _utmLabelController.clear();
      });
      _setFeedback(
        'Point {count} added.',
        params: {'count': '${_points.length}'},
        isError: false,
      );
    }
  }

  void _removePoint(int index) {
    setState(() => _points.removeAt(index));
  }

  void _setFeedback(
    String message, {
    required bool isError,
    Map<String, String> params = const {},
  }) {
    setState(() {
      _feedbackMessage = context.l10n.t(message, params: params);
      _feedbackIsError = isError;
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _setFeedback('Name is required.', isError: true);
      return;
    }
    if (_points.isEmpty) {
      _setFeedback('Add at least one point.', isError: true);
      return;
    }

    setState(() => _isSaving = true);

    try {
      final box = Hive.box('landbox');
      final id = const Uuid().v4();
      final now = DateTime.now().toIso8601String();
      final ellipsoid = ref.read(referenceEllipsoidProvider);

      final type = _recordType == 'auto'
          ? (_points.length == 1
                ? 'point'
                : _points.length == 2
                ? 'polyline'
                : 'polygon')
          : _recordType;

      // Save locally first
      await box.put(
        id,
        WorkspaceContext.stampRecord({
          'id': id,
          'entityType': type,
          'type': type,
          'name': name,
          if (_placeController.text.trim().isNotEmpty)
            'place': _placeController.text.trim(),
          if (_phoneController.text.trim().isNotEmpty)
            'phone': _phoneController.text.trim(),
          if (_descriptionController.text.trim().isNotEmpty)
            'description': _descriptionController.text.trim(),
          'referenceEllipsoid': ellipsoid.name,
          'labels': _points.map((p) => p.label).toList(),
          'points': _points
              .asMap()
              .entries
              .map(
                (e) => {
                  'order': e.key,
                  'lat': e.value.lat,
                  'lng': e.value.lng,
                  if (e.value.easting != null) 'easting': e.value.easting,
                  if (e.value.northing != null) 'northing': e.value.northing,
                  if (e.value.zone != null) 'zone': e.value.zone,
                  if (e.value.band != null) 'band': e.value.band,
                  'hemisphere': e.value.hemisphere,
                  'label': e.value.label,
                },
              )
              .toList(),
          'syncStatus': 'pending',
          'createdAt': now,
          'updatedAt': now,
        }),
      );

      // Attempt cloud sync
      final session = ref.read(authSessionProvider);
      if (session.isLoggedIn && session.isVerified) {
        try {
          final service = ref.read(landCloudServiceProvider);
          final coordinates = _points
              .asMap()
              .entries
              .map(
                (e) => LandCoordinateRequest(
                  x: e.value.lng,
                  y: e.value.lat,
                  easting: e.value.easting,
                  northing: e.value.northing,
                  zone: e.value.zone,
                  band: e.value.band,
                  hemisphere: e.value.hemisphere,
                  label: e.value.label,
                ),
              )
              .toList();

          final result = await service.createLand(
            session.token,
            CreateLandRequest(
              type: type,
              name: name,
              place: _placeController.text.trim().isEmpty
                  ? null
                  : _placeController.text.trim(),
              phone: _phoneController.text.trim().isEmpty
                  ? null
                  : _phoneController.text.trim(),
              description: _descriptionController.text.trim().isEmpty
                  ? null
                  : _descriptionController.text.trim(),
              referenceEllipsoid: ellipsoid.displayName,
              coordinates: coordinates,
            ),
          );

          // Update local record with cloud id
          final saved = Map<String, dynamic>.from(box.get(id) as Map);
          saved['cloudId'] = result.id;
          saved['syncStatus'] = 'synced';
          await box.put(id, saved);

          if (!mounted) return;
          _setFeedback('Saved and synced to cloud!', isError: false);
        } catch (e) {
          if (!mounted) return;
          _setFeedback(
            'Saved locally. Cloud sync failed: {error}',
            params: {'error': e.toString()},
            isError: false,
          );
        }
      } else {
        _setFeedback(
          'Saved locally. Will sync when logged in.',
          isError: false,
        );
      }

      widget.onSaved();
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      _setFeedback(
        'Failed to save: {error}',
        params: {'error': e.toString()},
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final accent = ref.watch(workspaceProvider).activeCompanyId != null
        ? const Color(0xFF001F3F)
        : const Color(0xFF001F3F);
    final theme = baseTheme.copyWith(
      colorScheme: baseTheme.colorScheme.copyWith(primary: accent),
    );
    final l10n = context.l10n;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Theme(
      data: theme,
      child: Builder(
        builder: (context) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD5DCE5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: HugeIcon(
                        icon: HugeIcons.strokeRoundedLocationAdd01,
                        color: Theme.of(context).colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.t('Add location manually'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF111827),
                            ),
                          ),
                          Text(
                            l10n.t(
                              'Enter coordinates in your preferred format',
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.t('Cancel'),
                      icon: const HugeIcon(
                        icon: HugeIcons.strokeRoundedCancel01,
                        color: Colors.black45,
                        size: 20,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Scrollable body
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Location metadata ──────────────────
                      _SectionHeader(title: l10n.t('Location details')),
                      const SizedBox(height: 10),
                      _Field(
                        controller: _nameController,
                        label: l10n.t('Name *'),
                        hint: l10n.t('e.g. Farm boundary, Warehouse'),
                        icon: HugeIcons.strokeRoundedTag01,
                      ),
                      const SizedBox(height: 10),
                      _Field(
                        controller: _placeController,
                        label: l10n.t('Place'),
                        hint: l10n.t('e.g. Dodoma, Tanzania'),
                        icon: HugeIcons.strokeRoundedLocation01,
                      ),
                      const SizedBox(height: 10),
                      _Field(
                        controller: _phoneController,
                        label: l10n.t('Phone'),
                        hint: l10n.t('Contact number'),
                        icon: HugeIcons.strokeRoundedCall,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 10),
                      _Field(
                        controller: _descriptionController,
                        label: l10n.t('Description'),
                        hint: l10n.t('Notes about this location'),
                        icon: HugeIcons.strokeRoundedNote01,
                        minLines: 2,
                        maxLines: 3,
                      ),

                      const SizedBox(height: 20),

                      // ── Record type selector ─────────────
                      _SectionHeader(title: l10n.t('Record type')),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            _RecordTypeChip(
                              label: l10n.t('Auto'),
                              icon: HugeIcons.strokeRoundedMagicWand01,
                              selected: _recordType == 'auto',
                              onTap: () => setState(() => _recordType = 'auto'),
                            ),
                            _RecordTypeChip(
                              label: l10n.t('Point'),
                              icon: HugeIcons.strokeRoundedLocation01,
                              selected: _recordType == 'point',
                              onTap: () =>
                                  setState(() => _recordType = 'point'),
                            ),
                            _RecordTypeChip(
                              label: l10n.t('Distance'),
                              icon: HugeIcons.strokeRoundedRuler,
                              selected: _recordType == 'polyline',
                              onTap: () =>
                                  setState(() => _recordType = 'polyline'),
                            ),
                            _RecordTypeChip(
                              label: l10n.t('Area'),
                              icon: HugeIcons.strokeRoundedSquare,
                              selected: _recordType == 'polygon',
                              onTap: () =>
                                  setState(() => _recordType = 'polygon'),
                            ),
                          ],
                        ),
                      ),
                      if (_recordType == 'auto')
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            l10n.t(
                              'Type is determined by point count: 1 = Point, 2 = Distance, 3+ = Area',
                            ),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),

                      const SizedBox(height: 20),

                      // ── Coordinate input mode ──────────────
                      _SectionHeader(title: l10n.t('Add coordinate points')),
                      const SizedBox(height: 8),
                      Text(
                        l10n.t(
                          'Choose your preferred coordinate format to add points one by one.',
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Mode toggle
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(
                                  () => _inputMode = _CoordInputMode.latLng,
                                ),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _inputMode == _CoordInputMode.latLng
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      HugeIcon(
                                        icon: HugeIcons.strokeRoundedGlobe02,
                                        size: 16,
                                        color:
                                            _inputMode == _CoordInputMode.latLng
                                            ? Colors.white
                                            : Colors.grey.shade600,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        l10n.t('Lat / Lng'),
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color:
                                              _inputMode ==
                                                  _CoordInputMode.latLng
                                              ? Colors.white
                                              : Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(
                                  () => _inputMode = _CoordInputMode.utm,
                                ),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _inputMode == _CoordInputMode.utm
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      HugeIcon(
                                        icon: HugeIcons.strokeRoundedGrid,
                                        size: 16,
                                        color: _inputMode == _CoordInputMode.utm
                                            ? Colors.white
                                            : Colors.grey.shade600,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        l10n.t('UTM'),
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color:
                                              _inputMode == _CoordInputMode.utm
                                              ? Colors.white
                                              : Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      // ── Coordinate input fields ────────────
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _inputMode == _CoordInputMode.latLng
                            ? _LatLngInputSection(
                                key: const ValueKey('latlng'),
                                latController: _latController,
                                lngController: _lngController,
                                labelController: _latLngLabelController,
                                onAdd: _addPoint,
                              )
                            : _UtmInputSection(
                                key: const ValueKey('utm'),
                                eastingController: _eastingController,
                                northingController: _northingController,
                                zoneController: _zoneController,
                                bandController: _bandController,
                                hemisphere: _hemisphere,
                                labelController: _utmLabelController,
                                onHemisphereChanged: (v) =>
                                    setState(() => _hemisphere = v),
                                onAdd: _addPoint,
                              ),
                      ),

                      // ── Feedback banner ────────────────────
                      if (_feedbackMessage != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: _feedbackIsError
                                ? Colors.red.shade50
                                : Colors.green.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _feedbackIsError
                                  ? Colors.red.shade200
                                  : Colors.green.shade200,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _feedbackIsError
                                    ? Icons.error_outline
                                    : Icons.check_circle_outline,
                                size: 16,
                                color: _feedbackIsError
                                    ? Colors.red.shade700
                                    : Colors.green.shade700,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _feedbackMessage!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _feedbackIsError
                                        ? Colors.red.shade800
                                        : Colors.green.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // ── Points list ────────────────────────
                      if (_points.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _SectionHeader(
                          title:
                              '${l10n.t('Added points')} (${_points.length})',
                        ),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            children: _points.asMap().entries.map((entry) {
                              final index = entry.key;
                              final point = entry.value;
                              final isLast = index == _points.length - 1;
                              return Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 28,
                                          height: 28,
                                          decoration: BoxDecoration(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 1.5,
                                            ),
                                          ),
                                          child: Center(
                                            child: Text(
                                              point.label.length > 3
                                                  ? '${index + 1}'
                                                  : point.label,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if (point.label != '${index + 1}')
                                                Text(
                                                  point.label,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                    color: Color(0xFF111827),
                                                  ),
                                                ),
                                              Text(
                                                '${point.lat.toStringAsFixed(6)}, ${point.lng.toStringAsFixed(6)}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                              if (point.easting != null &&
                                                  point.northing != null)
                                                Text(
                                                  '${l10n.t('E')} ${point.easting!.toStringAsFixed(2)}  ${l10n.t('N')} ${point.northing!.toStringAsFixed(2)}  ${l10n.t('Zone')} ${point.zone ?? '—'}${point.band ?? ''}',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.grey.shade400,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          icon: const HugeIcon(
                                            icon:
                                                HugeIcons.strokeRoundedDelete02,
                                            color: Colors.red,
                                            size: 18,
                                          ),
                                          onPressed: () => _removePoint(index),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 32,
                                            minHeight: 32,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (!isLast)
                                    Divider(
                                      height: 1,
                                      color: Colors.grey.shade200,
                                    ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // ── Save button ────────────────────────
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FeatureAccessLock(
                          features: const ['land.create_and_save'],
                          child: ElevatedButton(
                            onPressed: _isSaving ? null : _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
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
                                    l10n.t('Save location'),
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: Colors.black45,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _RecordTypeChip extends StatelessWidget {
  final String label;
  final dynamic icon;
  final bool selected;
  final VoidCallback onTap;

  const _RecordTypeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              HugeIcon(
                icon: icon,
                size: 16,
                color: selected ? Colors.white : Colors.grey.shade600,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final dynamic icon;
  final TextInputType keyboardType;
  final int minLines;
  final int maxLines;

  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.minLines = 1,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          minLines: minLines,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            prefixIcon: Padding(
              padding: const EdgeInsets.all(10),
              child: SheetLeadingIcon(
                icon: icon,
                accent: Theme.of(context).colorScheme.primary,
              ),
            ),
            filled: true,
            fillColor: const Color(0xFFF7F7F8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE8ECF0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE8ECF0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 1.8,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 13,
            ),
          ),
        ),
      ],
    );
  }
}

class _LatLngInputSection extends StatelessWidget {
  final TextEditingController latController;
  final TextEditingController lngController;
  final TextEditingController labelController;
  final VoidCallback onAdd;

  const _LatLngInputSection({
    super.key,
    required this.latController,
    required this.lngController,
    required this.labelController,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _CompactField(
                  controller: latController,
                  label: context.l10n.t('Latitude'),
                  hint: '-6.792453',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CompactField(
                  controller: lngController,
                  label: context.l10n.t('Longitude'),
                  hint: '39.208328',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _CompactField(
            controller: labelController,
            label: context.l10n.t('Point label (optional)'),
            hint: context.l10n.t('e.g. A1, Corner 1'),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onAdd,
              icon: const HugeIcon(
                icon: HugeIcons.strokeRoundedAdd01,
                size: 18,
              ),
              label: Text(context.l10n.t('Add point')),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UtmInputSection extends StatelessWidget {
  final TextEditingController eastingController;
  final TextEditingController northingController;
  final TextEditingController zoneController;
  final TextEditingController bandController;
  final String hemisphere;
  final TextEditingController labelController;
  final ValueChanged<String> onHemisphereChanged;
  final VoidCallback onAdd;

  const _UtmInputSection({
    super.key,
    required this.eastingController,
    required this.northingController,
    required this.zoneController,
    required this.bandController,
    required this.hemisphere,
    required this.labelController,
    required this.onHemisphereChanged,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _CompactField(
                  controller: eastingController,
                  label: context.l10n.t('Easting'),
                  hint: '525893.68',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CompactField(
                  controller: northingController,
                  label: context.l10n.t('Northing'),
                  hint: '9252392.60',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _CompactField(
                  controller: zoneController,
                  label: context.l10n.t('Zone number'),
                  hint: '37',
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CompactField(
                  controller: bandController,
                  label: context.l10n.t('Band letter'),
                  hint: 'M',
                  textCapitalization: TextCapitalization.characters,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.t('Hemisphere'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF374151),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: ['N', 'S'].map((h) {
                          final selected = hemisphere == h;
                          return Expanded(
                            child: GestureDetector(
                              onTap: () => onHemisphereChanged(h),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  h,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: selected
                                        ? Colors.white
                                        : Colors.grey.shade600,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _CompactField(
            controller: labelController,
            label: context.l10n.t('Point label (optional)'),
            hint: context.l10n.t('e.g. A1, Corner 1'),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onAdd,
              icon: const HugeIcon(
                icon: HugeIcons.strokeRoundedAdd01,
                size: 18,
              ),
              label: Text(context.l10n.t('Add point')),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType keyboardType;
  final TextCapitalization textCapitalization;

  const _CompactField({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType = TextInputType.text,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            filled: true,
            fillColor: Colors.white,
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE8ECF0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE8ECF0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 1.5,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 10,
            ),
          ),
        ),
      ],
    );
  }
}

class _ManualPoint {
  final String label;
  final double lat;
  final double lng;
  final double? easting;
  final double? northing;
  final String? zone;
  final String? band;
  final String hemisphere;

  const _ManualPoint({
    required this.label,
    required this.lat,
    required this.lng,
    this.easting,
    this.northing,
    this.zone,
    this.band,
    required this.hemisphere,
  });
}
