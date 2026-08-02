import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import 'land_map_page.dart';
import 'my_location_page.dart';
import 'saved_locations_page.dart';
import '../services/land_sync_service.dart';
import '../services/utm_converter.dart';
import '../models/reference_ellipsoid.dart';
import 'settings_page.dart';
import '../state/land_map_notifier.dart';
import '../state/settings_provider.dart';
import 'package:share_plus/share_plus.dart';

// ─── Startup location-check helpers ─────────────────────────────────────────

enum _StartupLocationState { serviceOff, permissionDenied, permissionForever }

/// A dialog shown once on cold-start / resume that walks the user through
/// turning on GPS and granting location permission — without ever forcing
/// them to leave the app through a deep settings link.
class _LocationStartupDialog extends StatefulWidget {
  final _StartupLocationState state;
  final VoidCallback onDismiss;

  /// Called when the user enables service / grants permission so the parent
  /// can refresh the location immediately.
  final Future<void> Function() onAccessGranted;

  const _LocationStartupDialog({
    required this.state,
    required this.onDismiss,
    required this.onAccessGranted,
  });

  @override
  State<_LocationStartupDialog> createState() => _LocationStartupDialogState();
}

class _LocationStartupDialogState extends State<_LocationStartupDialog> {
  bool _busy = false;

  String get _title {
    switch (widget.state) {
      case _StartupLocationState.serviceOff:
        return 'Location is off';
      case _StartupLocationState.permissionDenied:
        return 'Allow location access?';
      case _StartupLocationState.permissionForever:
        return 'Location access blocked';
    }
  }

  String get _body {
    switch (widget.state) {
      case _StartupLocationState.serviceOff:
        return 'TaREF GPS needs location services for live coordinates, '
            'land-point tracking, navigation, and photo geotagging. '
            'You can continue without location — GPS features will be '
            'unavailable until location is turned on.';
      case _StartupLocationState.permissionDenied:
        return 'TaREF GPS uses your location only for live coordinates, '
            'land-point tracking, and navigation. You can continue '
            'without sharing your location — GPS features will stay '
            'off until access is granted.';
      case _StartupLocationState.permissionForever:
        return 'Location access was permanently denied. To use GPS features, '
            'enable location for TaREF GPS in your device settings. '
            'You can continue using the app without GPS.';
    }
  }

  String get _primaryLabel {
    switch (widget.state) {
      case _StartupLocationState.serviceOff:
        return 'Turn On Location';
      case _StartupLocationState.permissionDenied:
        return 'Continue';
      case _StartupLocationState.permissionForever:
        return 'Open Settings';
    }
  }

  IconData get _icon {
    switch (widget.state) {
      case _StartupLocationState.serviceOff:
        return Icons.location_off_rounded;
      case _StartupLocationState.permissionDenied:
        return Icons.location_on_outlined;
      case _StartupLocationState.permissionForever:
        return Icons.location_disabled_rounded;
    }
  }

  Future<void> _onPrimary() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      switch (widget.state) {
        case _StartupLocationState.serviceOff:
          // Open location settings then pop — the service-status stream
          // (already running in LandMapPage) will resume location automatically
          // when the user toggles GPS on.
          if (mounted) Navigator.of(context).pop();
          await Geolocator.openLocationSettings();
          // After returning, trigger a fresh check via lifecycle (no polling).
          return;

        case _StartupLocationState.permissionDenied:
          // Trigger the OS permission prompt.
          final perm = await Geolocator.requestPermission();
          if (!mounted) return;
          if (perm == LocationPermission.whileInUse ||
              perm == LocationPermission.always) {
            Navigator.of(context).pop();
            await widget.onAccessGranted();
          } else if (perm == LocationPermission.deniedForever) {
            // Silently dismiss — user can still use the app; in-map
            // dialogs will guide them if they tap a GPS action.
            Navigator.of(context).pop();
          } else {
            // Still denied — just dismiss and let them proceed.
            Navigator.of(context).pop();
          }
          return;

        case _StartupLocationState.permissionForever:
          // Only case where we go to app settings.
          Navigator.of(context).pop();
          await Geolocator.openAppSettings();
          return;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = const Color(0xFF001F3F);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      icon: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.08),
          shape: BoxShape.circle,
        ),
        child: Icon(_icon, size: 32, color: primary),
      ),
      title: Text(
        _title,
        textAlign: TextAlign.center,
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 19,
        ),
      ),
      content: Text(
        _body,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: Colors.black54,
          height: 1.5,
        ),
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _busy ? null : _onPrimary,
            style: ElevatedButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    _primaryLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: _busy ? null : widget.onDismiss,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              foregroundColor: Colors.black54,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Not Now',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Main navigation ──────────────────────────────────────────────────────────

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  Timer? _syncTimer;
  bool _syncInProgress = false;
  bool _isCheckingInitialLocationChoice = false;
  final SavedLocationsToolbarController _savedLocationsToolbarController =
      SavedLocationsToolbarController();

  static const double _bottomNavHeight = 72;
  static const Color _bottomNavBackground = Colors.white;
  static const Color _selectedColor = Color(0xFF001F3F);
  static const Color _unselectedColor = Color(0xFF7C7C7C);
  static const Duration _syncInterval = Duration(seconds: 60);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _savedLocationsToolbarController.addListener(_onSavedToolbarChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_showInitialLocationChoice());
      _runBackgroundSync();
      _syncTimer = Timer.periodic(_syncInterval, (_) => _runBackgroundSync());
    });
  }

  Future<void> _showInitialLocationChoice() async {
    if (_isCheckingInitialLocationChoice) return;
    _isCheckingInitialLocationChoice = true;
    try {
      // ── 1. Check service first ────────────────────────────────────────────
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!mounted) return;

      if (!serviceEnabled) {
        await _showLocationStartupDialog(_StartupLocationState.serviceOff);
        return; // dialog + stream handle the rest on resume
      }

      // ── 2. Check permission ───────────────────────────────────────────────
      final permission = await Geolocator.checkPermission();
      if (!mounted) return;

      if (permission == LocationPermission.denied) {
        await _showLocationStartupDialog(
          _StartupLocationState.permissionDenied,
        );
      }
      // permissionForever → silent; in-map dialogs guide the user if needed.
      // whileInUse / always → already have access, no dialog needed.
    } finally {
      _isCheckingInitialLocationChoice = false;
    }
  }

  /// Shows the startup location dialog for [state] and waits for it to close.
  Future<void> _showLocationStartupDialog(_StartupLocationState state) async {
    if (!mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    await showDialog<void>(
      context: context,
      barrierDismissible: false, // user must tap Not Now or primary action
      builder: (dialogContext) => _LocationStartupDialog(
        state: state,
        onDismiss: () => Navigator.of(dialogContext).pop(),
        onAccessGranted: () async {
          // Permission was just granted — start location.
          final err = await container
              .read(landMapProvider.notifier)
              .requestLocationAccess();
          if (err != null) return;
          await container.read(landMapProvider.notifier).refreshLocation();
        },
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(_showInitialLocationChoice());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _savedLocationsToolbarController.removeListener(_onSavedToolbarChanged);
    _savedLocationsToolbarController.dispose();
    _syncTimer?.cancel();
    super.dispose();
  }

  void _onSavedToolbarChanged() {
    if (!mounted || _currentIndex != 2) return;
    setState(() {});
  }

  Future<void> _runBackgroundSync() async {
    if (_syncInProgress || !mounted) return;

    _syncInProgress = true;
    try {
      final service = LandSyncService(Hive.box('landbox'));
      await service.syncPendingLands(limit: 10);
    } finally {
      _syncInProgress = false;
    }
  }

  void _navigateToPage(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  Future<void> _refreshMyLocation() async {
    final container = ProviderScope.containerOf(context, listen: false);
    final err = await container
        .read(landMapProvider.notifier)
        .refreshLocation();
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Location refreshed')));
  }

  Future<void> _copyText(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label copied')));
  }

  Future<void> _handleMyLocationMenu(MyLocationAction action) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final current = container.read(landMapProvider).current;
    switch (action) {
      case MyLocationAction.savePoint:
        if (current == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location not available yet')),
          );
          return;
        }
        final customName = await _promptForLocationName();
        if (!mounted) return;
        if (customName == null) return;
        final id = const Uuid().v4();
        final box = Hive.box('landbox');
        final now = DateTime.now().toIso8601String();
        final ellipsoid = container.read(referenceEllipsoidProvider);
        final name = customName.trim().isEmpty
            ? 'My location $now'
            : customName.trim();
        await box.put(id, {
          'id': id,
          'entityType': 'point',
          'type': 'point',
          'name': name,
          'referenceEllipsoid': ellipsoid.name,
          'labels': ['1'],
          'points': [
            {
              'order': 0,
              'lat': current.latitude,
              'lng': current.longitude,
              'label': '1',
            },
          ],
          'syncStatus': 'pending',
          'createdAt': now,
          'updatedAt': now,
        });
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Location saved')));
        await _runBackgroundSync();
        return;

      case MyLocationAction.copyBoth:
        if (current == null) return;
        final ellipsoid = container.read(referenceEllipsoidProvider);
        await _copyText(
          _buildMyLocationPayload(
            current: current,
            accuracy: container.read(landMapProvider).accuracyMeters,
            referenceEllipsoid: ellipsoid,
          ),
          'Coordinates',
        );
        return;
      case MyLocationAction.share:
        if (current == null) return;
        final ellipsoid = container.read(referenceEllipsoidProvider);
        final accuracy = container.read(landMapProvider).accuracyMeters;
        await SharePlus.instance.share(
          ShareParams(
            text: _buildMyLocationPayload(
              current: current,
              accuracy: accuracy,
              referenceEllipsoid: ellipsoid,
            ),
          ),
        );
        return;
    }
  }

  Future<String?> _promptForLocationName() async {
    final controller = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Save location'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Enter location name (optional)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    return result;
  }

  String _buildMyLocationPayload({
    required LatLng current,
    required double? accuracy,
    required ReferenceEllipsoid referenceEllipsoid,
  }) {
    final utm = UtmConverter.fromLatLng(
      current.latitude,
      current.longitude,
      referenceEllipsoid,
    );
    final buffer = StringBuffer()
      ..writeln('My current location')
      ..writeln(
        'Lat/Long: ${current.latitude.toStringAsFixed(6)}, ${current.longitude.toStringAsFixed(6)}',
      )
      ..writeln(
        'E/N: ${utm?.easting.toStringAsFixed(2) ?? '—'}, ${utm?.northing.toStringAsFixed(2) ?? '—'}',
      )
      ..writeln(
        'UTM Zone: ${utm?.zone ?? '—'} ${referenceEllipsoid.displayName}',
      )
      ..writeln(
        'Accuracy: ${accuracy == null ? '—' : '${accuracy.toStringAsFixed(1)} m'}',
      );
    return buffer.toString();
  }

  String _appBarTitleText() {
    if (_currentIndex != 2) {
      const titles = ['Map', 'My location', 'Saved locations', 'Settings'];
      return titles[_currentIndex];
    }

    if (_savedLocationsToolbarController.isSelectionMode) {
      return '${_savedLocationsToolbarController.selectedCount} selected';
    }
    return 'Saved locations';
  }

  List<Widget>? _buildAppBarActions() {
    if (_currentIndex == 0) {
      return null;
    }

    if (_currentIndex == 2) {
      final canActOnSelection = _savedLocationsToolbarController.hasSelection;
      final isSelectionMode = _savedLocationsToolbarController.isSelectionMode;

      if (isSelectionMode) {
        return [
          IconButton(
            icon: const Icon(Icons.folder_outlined, color: Colors.black87),
            tooltip: 'Set group',
            onPressed: canActOnSelection
                ? () => _savedLocationsToolbarController.dispatch(
                    SavedLocationsToolbarAction.setGroup,
                  )
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined, color: Colors.black87),
            tooltip: 'Share selected',
            onPressed: canActOnSelection
                ? () => _savedLocationsToolbarController.dispatch(
                    SavedLocationsToolbarAction.share,
                  )
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.black87),
            tooltip: 'Delete selected',
            onPressed: canActOnSelection
                ? () => _savedLocationsToolbarController.dispatch(
                    SavedLocationsToolbarAction.delete,
                  )
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.black87),
            tooltip: 'Exit selection',
            onPressed: () => _savedLocationsToolbarController.dispatch(
              SavedLocationsToolbarAction.exitSelection,
            ),
          ),
        ];
      }

      return [
        // IconButton(
        //   icon: const Icon(Icons.tune, color: Colors.black87),
        //   tooltip: 'Filter',
        //   onPressed: () => _savedLocationsToolbarController.dispatch(
        //     SavedLocationsToolbarAction.filter,
        //   ),
        // ),
        IconButton(
          icon: const Icon(Icons.sort, color: Colors.black87),
          tooltip: 'Sort',
          onPressed: () => _savedLocationsToolbarController.dispatch(
            SavedLocationsToolbarAction.sort,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.more_vert, color: Colors.black87),
          tooltip: 'More',
          onPressed: () => _savedLocationsToolbarController.dispatch(
            SavedLocationsToolbarAction.menu,
          ),
        ),
      ];
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset =
        _bottomNavHeight + 12 + MediaQuery.of(context).padding.bottom;
    final pages = [
      LandMapPage(bottomInset: bottomInset),
      MyLocationPage(
        isTabActive: _currentIndex == 1,
        onRefresh: _refreshMyLocation,
        onMenuAction: _handleMyLocationMenu,
      ),
      SavedLocationsPage(
        toolbarController: _savedLocationsToolbarController,
        onOpenMapRequested: () => _navigateToPage(0),
        onToolbarStateChanged: () {
          if (mounted && _currentIndex == 2) {
            setState(() {});
          }
        },
        showEmbeddedToolbar: false,
      ),
      const SettingsPage(),
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _currentIndex == 0 || _currentIndex == 1
          ? null
          : AppBar(
              title: Text(
                _appBarTitleText(),
                style: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              actions: _buildAppBarActions(),
              backgroundColor: Colors.white,
              elevation: 0,
            ),
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: Container(
        height: _bottomNavHeight + MediaQuery.of(context).padding.bottom,
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 10,
          bottom: 10 + MediaQuery.of(context).padding.bottom,
        ),
        color: _bottomNavBackground,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _BottomNavItem(
              label: 'Map',
              icon: Icons.public,
              isSelected: _currentIndex == 0,
              selectedColor: _selectedColor,
              unselectedColor: _unselectedColor,
              onTap: () => _navigateToPage(0),
            ),
            _BottomNavItem(
              label: 'My location',
              icon: Icons.navigation,
              isSelected: _currentIndex == 1,
              selectedColor: _selectedColor,
              unselectedColor: _unselectedColor,
              onTap: () => _navigateToPage(1),
            ),
            _BottomNavItem(
              label: 'Saved locations',
              icon: Icons.list_alt,
              isSelected: _currentIndex == 2,
              selectedColor: _selectedColor,
              unselectedColor: _unselectedColor,
              onTap: () => _navigateToPage(2),
            ),
            _BottomNavItem(
              label: 'Settings',
              icon: Icons.settings,
              isSelected: _currentIndex == 3,
              selectedColor: _selectedColor,
              unselectedColor: _unselectedColor,
              onTap: () => _navigateToPage(3),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final Color selectedColor;
  final Color unselectedColor;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.selectedColor,
    required this.unselectedColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? selectedColor : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? Colors.white : unselectedColor,
              ),
              if (isSelected) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
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
