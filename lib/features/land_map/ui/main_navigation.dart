import 'package:flutter/material.dart';
import 'land_map_page.dart';
import 'my_location_page.dart';
import 'saved_locations_page.dart';
import 'settings_page.dart';
import 'package:flutter_svg/flutter_svg.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  static const double _bottomNavHeight = 72;
  static const Color _bottomNavBackground = Color(0xFFF5EFF7);
  static const Color _selectedColor = Color(0xFF0B8A8D);
  static const Color _unselectedColor = Color(0xFF7C7C7C);

  late final List<Widget> _pages = [
    const LandMapPage(bottomInset: _bottomNavHeight + 12),
    const MyLocationPage(),
    SavedLocationsPage(onOpenMapRequested: () => _navigateToPage(0)),
    const SettingsPage(),
  ];

  void _navigateToPage(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['Map', 'My location', 'Saved locations', 'Settings'];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          titles[_currentIndex],
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w700,
            fontSize: 22,
          ),
        ),
        actions: _currentIndex == 0
            ? [
                IconButton(
                  icon: SvgPicture.asset(
                    'lib/assets/icons/search.svg',
                    width: 20,
                    height: 20,
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
            : null,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        color: _currentIndex == 3 ? const Color(0xFFF5F5F5) : null,
        child: IndexedStack(index: _currentIndex, children: _pages),
      ),
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
