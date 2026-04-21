import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import 'land_map_page.dart';
import 'my_location_page.dart';
import 'saved_locations_page.dart';
import '../services/land_sync_service.dart';
import 'settings_page.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../state/land_map_notifier.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  Timer? _syncTimer;
  bool _syncInProgress = false;

  static const double _bottomNavHeight = 72;
  static const Color _bottomNavBackground = Colors.white;
  static const Color _selectedColor = Color(0xFF001F3F);
  static const Color _unselectedColor = Color(0xFF7C7C7C);
  static const Duration _syncInterval = Duration(seconds: 60);

  late final List<Widget> _pages = [
    const LandMapPage(bottomInset: _bottomNavHeight + 12),
    const MyLocationPage(),
    SavedLocationsPage(onOpenMapRequested: () => _navigateToPage(0)),
    const SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runBackgroundSync();
      _syncTimer = Timer.periodic(_syncInterval, (_) => _runBackgroundSync());
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
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

  Future<void> _handleMyLocationMenu(_MyLocationAction action) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final current = container.read(landMapProvider).current;
    switch (action) {
      case _MyLocationAction.savePoint:
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
      case _MyLocationAction.copyLat:
        if (current == null) return;
        await _copyText(current.latitude.toStringAsFixed(6), 'Latitude');
        return;
      case _MyLocationAction.copyLon:
        if (current == null) return;
        await _copyText(current.longitude.toStringAsFixed(6), 'Longitude');
        return;
      case _MyLocationAction.copyBoth:
        if (current == null) return;
        await _copyText(
          '${current.latitude.toStringAsFixed(6)},${current.longitude.toStringAsFixed(6)}',
          'Coordinates',
        );
        return;
      case _MyLocationAction.share:
        if (current == null) return;
        final accuracy = container.read(landMapProvider).accuracyMeters;
        final payload = StringBuffer()
          ..writeln('My current location')
          ..writeln('Latitude: ${current.latitude.toStringAsFixed(6)}')
          ..writeln('Longitude: ${current.longitude.toStringAsFixed(6)}')
          ..writeln(
            'Accuracy: ${accuracy == null ? '—' : '${accuracy.toStringAsFixed(1)} m'}',
          );
        await _copyText(payload.toString(), 'Share location text');
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['Map', 'My location', 'Saved locations', 'Settings'];
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          titles[_currentIndex],
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        actions: _currentIndex == 0
            ? [
                IconButton(
                  icon: SvgPicture.asset(
                    'lib/assets/icons/search.svg',
                    width: 18,
                    height: 18,
                    colorFilter: const ColorFilter.mode(
                      Colors.black87,
                      BlendMode.srcIn,
                    ),
                  ),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Search - Coming soon')),
                    );
                  },
                ),
              ]
            : _currentIndex == 1
            ? [
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.black87),
                  onPressed: _refreshMyLocation,
                ),
                PopupMenuButton<_MyLocationAction>(
                  icon: const Icon(Icons.more_vert, color: Colors.black87),
                  onSelected: _handleMyLocationMenu,
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: _MyLocationAction.savePoint,
                      child: Text('Save current point'),
                    ),
                    PopupMenuItem(
                      value: _MyLocationAction.copyLat,
                      child: Text('Copy latitude'),
                    ),
                    PopupMenuItem(
                      value: _MyLocationAction.copyLon,
                      child: Text('Copy longitude'),
                    ),
                    PopupMenuItem(
                      value: _MyLocationAction.copyBoth,
                      child: Text('Copy coordinates'),
                    ),
                    PopupMenuItem(
                      value: _MyLocationAction.share,
                      child: Text('Share location'),
                    ),
                  ],
                ),
              ]
            : null,
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

enum _MyLocationAction { savePoint, copyLat, copyLon, copyBoth, share }

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
