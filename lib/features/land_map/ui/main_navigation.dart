import 'package:flutter/material.dart';
import 'land_map_page.dart';
import 'settings_page.dart';
import 'package:flutter_svg/flutter_svg.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  final List<Widget> _pages = [const LandMapPage(), const SettingsPage()];

  void _navigateToPage(int index) {
    setState(() {
      _currentIndex = index;
    });
    Navigator.of(context).pop(); // Close drawer
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _currentIndex == 0
          ? AppBar(
              title: Text(
                'Home',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
              actions: [
                IconButton(
                  icon: SvgPicture.asset(
                    'lib/assets/icons/search.svg',
                    width: 20,
                    height: 20,
                    colorFilter: const ColorFilter.mode(
                      Colors.black,
                      BlendMode.srcIn,
                    ),
                  ),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Search - Coming soon')),
                    );
                  },
                ),
              ],
              leading: Builder(
                builder: (BuildContext context) {
                  return IconButton(
                    icon: SvgPicture.asset(
                      'lib/assets/icons/bars-sort.svg',
                      width: 20,
                      height: 20,
                      colorFilter: const ColorFilter.mode(
                        Colors.black,
                        BlendMode.srcIn,
                      ),
                    ),
                    onPressed: () {
                      Scaffold.of(context).openDrawer();
                    },
                  );
                },
              ),
              backgroundColor: Colors.white,
            )
          : AppBar(
              title: Text(
                'Settings',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
              leading: Builder(
                builder: (BuildContext context) {
                  return IconButton(
                    icon: SvgPicture.asset(
                      'lib/assets/icons/bars-sort.svg',
                      width: 20,
                      height: 20,
                      colorFilter: const ColorFilter.mode(
                        Colors.black,
                        BlendMode.srcIn,
                      ),
                    ),
                    onPressed: () {
                      Scaffold.of(context).openDrawer();
                    },
                  );
                },
              ),
              backgroundColor: Colors.white,
            ),
      drawer: Drawer(
        child: Container(
          color: Colors.white,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: const BoxDecoration(color: Color(0xFF001F3F)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SvgPicture.asset(
                        'lib/assets/icons/region-pin-alt.svg',
                        width: 32,
                        height: 32,
                        colorFilter: const ColorFilter.mode(
                          Color(0xFF001F3F),
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Land Mapper',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Professional Land Mapping',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: SvgPicture.asset(
                  'lib/assets/icons/region-pin-alt.svg',
                  width: 20,
                  height: 20,
                  colorFilter: ColorFilter.mode(
                    _currentIndex == 0 ? const Color(0xFF001F3F) : Colors.grey,
                    BlendMode.srcIn,
                  ),
                ),
                title: Text(
                  'Map',
                  style: TextStyle(
                    fontWeight: _currentIndex == 0
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: _currentIndex == 0
                        ? const Color(0xFF001F3F)
                        : Colors.black87,
                  ),
                ),
                tileColor: _currentIndex == 0
                    ? const Color(0xFF001F3F).withValues(alpha: 0.1)
                    : null,
                onTap: () => _navigateToPage(0),
              ),
              ListTile(
                leading: SvgPicture.asset(
                  'lib/assets/icons/time-past.svg',
                  width: 18,
                  height: 18,
                  colorFilter: const ColorFilter.mode(
                    Colors.grey,
                    BlendMode.srcIn,
                  ),
                ),
                title: const Text('History'),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('History - Coming soon')),
                  );
                },
              ),
              ListTile(
                leading: SvgPicture.asset(
                  'lib/assets/icons/bookmark-outline.svg',
                  width: 18,
                  height: 18,
                  colorFilter: const ColorFilter.mode(
                    Colors.grey,
                    BlendMode.srcIn,
                  ),
                ),
                title: const Text('Saved Lands'),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Saved Lands - Coming soon')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.camera_alt_outlined,
                  color: Colors.grey,
                ),
                title: const Text('GPS Camera'),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('GPS Camera - Coming soon')),
                  );
                },
              ),
              const Divider(),
              ListTile(
                leading: Icon(
                  Icons.settings,
                  color: _currentIndex == 1
                      ? const Color(0xFF001F3F)
                      : Colors.grey,
                ),
                title: Text(
                  'Settings',
                  style: TextStyle(
                    fontWeight: _currentIndex == 1
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: _currentIndex == 1
                        ? const Color(0xFF001F3F)
                        : Colors.black87,
                  ),
                ),
                tileColor: _currentIndex == 1
                    ? const Color(0xFF001F3F).withValues(alpha: 0.1)
                    : null,
                onTap: () => _navigateToPage(1),
              ),
              ListTile(
                leading: const Icon(Icons.help_outline, color: Colors.grey),
                title: const Text('Help & Support'),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Help & Support - Coming soon'),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      body: Container(
        color: _currentIndex == 1 ? const Color(0xFFF5F5F5) : null,
        child: IndexedStack(index: _currentIndex, children: _pages),
      ),
    );
  }
}
