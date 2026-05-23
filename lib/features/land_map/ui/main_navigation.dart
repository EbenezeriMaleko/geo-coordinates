import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
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

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  Timer? _syncTimer;
  bool _syncInProgress = false;
  final SavedLocationsToolbarController _savedLocationsToolbarController =
      SavedLocationsToolbarController();

  static const double _bottomNavHeight = 72;
  static const Color _bottomNavBackground = Colors.white;
  static const Color _selectedColor = Color(0xFF001F3F);
  static const Color _unselectedColor = Color(0xFF7C7C7C);
  static const Duration _syncInterval = Duration(seconds: 60);

  late final List<Widget> _pages = [
    LandMapPage(bottomInset: _bottomNavHeight + 12 + MediaQuery.of(context).padding.bottom),
    MyLocationPage(
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

  @override
  void initState() {
    super.initState();
    _savedLocationsToolbarController.addListener(_onSavedToolbarChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runBackgroundSync();
      _syncTimer = Timer.periodic(_syncInterval, (_) => _runBackgroundSync());
    });
  }

  @override
  void dispose() {
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
        final id = const Uuid().v4();
        final box = Hive.box('landbox');
        await box.put(id, {
          'id': id,
          'entityType': 'marker',
          'name': 'Marker ${DateTime.now().toIso8601String()}',
          'lat': current.latitude,
          'lng': current.longitude,
          'createdAt': DateTime.now().toIso8601String(),
        });
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Current point saved')));
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
      ..writeln('Latitude: ${current.latitude.toStringAsFixed(6)}')
      ..writeln('Longitude: ${current.longitude.toStringAsFixed(6)}')
      ..writeln(
        'Easting: ${utm?.easting.toStringAsFixed(2) ?? '—'}',
      )
      ..writeln(
        'Northing: ${utm?.northing.toStringAsFixed(2) ?? '—'}',
      )
      ..writeln('UTM Zone: ${utm?.zone ?? '—'}')
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _currentIndex == 0 || _currentIndex == 1 ? null : AppBar(
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
      body: IndexedStack(index: _currentIndex, children: _pages),
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
