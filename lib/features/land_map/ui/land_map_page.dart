import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_compass/flutter_compass.dart';

import '../models/coordinate_format.dart';
import '../state/land_map_notifier.dart';
import '../state/settings_provider.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum MapType { normal, satellite, terrain, hybrid }

class LandMapPage extends ConsumerStatefulWidget {
  const LandMapPage({super.key});

  @override
  ConsumerState<LandMapPage> createState() => _LandMapPageState();
}

class _LandMapPageState extends ConsumerState<LandMapPage>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  final TextEditingController _nameController = TextEditingController();

  MapType _currentMapType = MapType.normal;
  bool _isFabExpanded = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final err = await ref.read(landMapProvider.notifier).initLocation();
      if (err != null && mounted) _snack(err);

      final st = ref.read(landMapProvider);
      if (st.current != null) {
        _mapController.move(st.current!, 17);
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(landMapProvider);
    final notifier = ref.read(landMapProvider.notifier);
    final coordinateFormat = ref.watch(coordinateFormatProvider);

    final center = st.current ?? const LatLng(-6.7924, 39.2083);

    final markers = <Marker>[
      for (int i = 0; i < st.points.length; i++)
        Marker(
          width: 40,
          height: 40,
          point: st.points[i],
          child: _PointMarker(index: i + 1),
        ),

      if (st.current != null)
        Marker(
          width: 36,
          height: 36,
          point: st.current!,
          child: const _CurrentMarker(),
        ),
    ];

    final polygons = <Polygon>[
      if (st.points.length >= 3)
        Polygon(
          points: st.points,
          borderStrokeWidth: 3,
          color: const Color(0xFF001F3F).withValues(alpha: 0.3),
          borderColor: const Color(0xFF001F3F),
        ),
    ];

    final polylines = <Polyline>[
      if (st.points.length >= 2)
        Polyline(
          points: st.points,
          strokeWidth: 3,
          color: const Color(0xFF001F3F),
        ),
    ];

    return Stack(
      children: [
        // Map
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(initialCenter: center, initialZoom: 16),
          children: [
            TileLayer(
              urlTemplate: _getMapTileUrl(),
              userAgentPackageName: 'com.example.landmapper',
            ),
            if (polygons.isNotEmpty) PolygonLayer(polygons: polygons),
            if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
            MarkerLayer(markers: markers),
          ],
        ),

        // GPS Info Card
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF001F3F).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.gps_fixed,
                    color: Color(0xFF001F3F),
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        st.current == null
                            ? 'Locating...'
                            : CoordinateFormatter.format(
                                st.current!.latitude,
                                st.current!.longitude,
                                coordinateFormat,
                              ),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      if (st.current != null)
                        Text(
                          'Accuracy: ${(st.accuracyMeters ?? 0).toStringAsFixed(1)}m',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                          ),
                        ),
                    ],
                  ),
                ),
                if (st.points.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF001F3F),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${st.points.length} pts',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Compass (Top Right)
        Positioned(right: 16, top: 90, child: const CompassWidget()),

        // Map Controls (Right side)
        Positioned(
          right: 16,
          top: 160,
          child: Column(
            children: [
              _MapControlButton(icon: Icons.fullscreen, onPressed: () {}),
              const SizedBox(height: 8),
              _MapControlButton(
                icon: Icons.my_location_rounded,
                onPressed: () async {
                  final err = await notifier.refreshLocation();
                  if (err != null) _snack(err);
                  final now = ref.read(landMapProvider).current;
                  if (now != null) _mapController.move(now, 17);
                },
              ),
              const SizedBox(height: 8),
              _MapControlButton(
                icon: Icons.layers,
                onPressed: () {
                  _showMapTypeSelector();
                },
              ),
            ],
          ),
        ),

        // Zoom Controls
        Positioned(
          left: 16,
          bottom: 140,
          child: Column(
            children: [
              _MapControlButton(
                icon: Icons.add,
                onPressed: () {
                  _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom + 1,
                  );
                },
              ),
              const SizedBox(height: 8),
              _MapControlButton(
                icon: Icons.remove,
                onPressed: () {
                  _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom - 1,
                  );
                },
              ),
            ],
          ),
        ),

        // Floating Action Button
        Positioned(
          right: 16,
          bottom: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isFabExpanded) ...[
                _FabOption(
                  label: 'Field',
                  icon: SvgPicture.asset(
                    'lib/assets/icons/golf-hole.svg',
                    width: 20,
                    height: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      _isFabExpanded = false;
                    });
                    _showFieldDialog();
                  },
                ),
                const SizedBox(height: 12),
                _FabOption(
                  label: 'Distance',
                  icon: SvgPicture.asset(
                    'lib/assets/icons/map-location-track.svg',
                    width: 20,
                    height: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      _isFabExpanded = false;
                    });
                    _snack('Distance tool activated');
                  },
                ),
                const SizedBox(height: 12),
                _FabOption(
                  label: 'Marker',
                  icon: SvgPicture.asset(
                    'lib/assets/icons/marker.svg',
                    width: 20,
                    height: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      _isFabExpanded = false;
                    });
                    _snack('Marker tool activated');
                  },
                ),
                const SizedBox(height: 12),
              ],
              FloatingActionButton(
                onPressed: () {
                  setState(() {
                    _isFabExpanded = !_isFabExpanded;
                  });
                },
                backgroundColor: Colors.white,
                child: AnimatedRotation(
                  turns: _isFabExpanded ? 0.125 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(_isFabExpanded ? Icons.close : Icons.add),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _getMapTileUrl() {
    switch (_currentMapType) {
      case MapType.normal:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
      case MapType.satellite:
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
      case MapType.terrain:
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}';
      case MapType.hybrid:
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
    }
  }

  void _showMapTypeSelector() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Map Type',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _MapTypeOption(
                  label: 'Normal',
                  icon: Icons.map,
                  isSelected: _currentMapType == MapType.normal,
                  onTap: () {
                    setState(() => _currentMapType = MapType.normal);
                    Navigator.pop(context);
                  },
                ),
                _MapTypeOption(
                  label: 'Satellite',
                  icon: Icons.satellite_alt,
                  isSelected: _currentMapType == MapType.satellite,
                  onTap: () {
                    setState(() => _currentMapType = MapType.satellite);
                    Navigator.pop(context);
                  },
                ),
                _MapTypeOption(
                  label: 'Terrain',
                  icon: Icons.terrain,
                  isSelected: _currentMapType == MapType.terrain,
                  onTap: () {
                    setState(() => _currentMapType = MapType.terrain);
                    Navigator.pop(context);
                  },
                ),
                _MapTypeOption(
                  label: 'Hybrid',
                  icon: Icons.layers,
                  isSelected: _currentMapType == MapType.hybrid,
                  onTap: () {
                    setState(() => _currentMapType = MapType.hybrid);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            const Text(
              'Layers',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _LayerOption(
                  label: 'Field',
                  icon: SvgPicture.asset(
                    'lib/assets/icons/golf-hole.svg',
                    width: 28,
                    height: 28,
                    colorFilter: const ColorFilter.mode(
                      Colors.white,
                      BlendMode.srcIn,
                    ),
                  ),
                  color: Colors.blue,
                ),
                _LayerOption(
                  label: 'Distance',
                  icon: SvgPicture.asset(
                    'lib/assets/icons/map-location-track.svg',
                    width: 28,
                    height: 28,
                    colorFilter: const ColorFilter.mode(
                      Colors.white,
                      BlendMode.srcIn,
                    ),
                  ),
                  color: Colors.orange,
                ),
                _LayerOption(
                  label: 'Marker',
                  icon: SvgPicture.asset(
                    'lib/assets/icons/marker.svg',
                    width: 28,
                    height: 28,
                    colorFilter: const ColorFilter.mode(
                      Colors.white,
                      BlendMode.srcIn,
                    ),
                  ),
                  color: Colors.red,
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showFieldDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => Consumer(
        builder: (context, ref, child) {
          final pointsCount = ref.watch(landMapProvider).points.length;
          final notifier = ref.read(landMapProvider.notifier);

          return AlertDialog(
            title: const Text('Create Field'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Field Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () async {
                    final err = await notifier.addPointFromCurrent();
                    if (err != null && dialogContext.mounted) {
                      ScaffoldMessenger.of(
                        dialogContext,
                      ).showSnackBar(SnackBar(content: Text(err)));
                    } else if (dialogContext.mounted) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(content: Text('Point added')),
                      );
                    }
                  },
                  icon: const Icon(Icons.add_location_alt_rounded),
                  label: const Text('Add Point'),
                ),
                const SizedBox(height: 8),
                Text(
                  '$pointsCount points added',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  notifier.clearPoints();
                  Navigator.pop(dialogContext);
                },
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final err = await notifier.saveOffline(
                    name: _nameController.text.trim(),
                  );
                  if (dialogContext.mounted) {
                    if (err != null) {
                      ScaffoldMessenger.of(
                        dialogContext,
                      ).showSnackBar(SnackBar(content: Text(err)));
                    } else {
                      _nameController.clear();
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text('Field saved successfully'),
                        ),
                      );
                      Navigator.pop(dialogContext);
                    }
                  }
                },
                child: const Text('Save Field'),
              ),
            ],
          );
        },
      ),
    );
  }
}

// Helper Widgets
class _MapControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _MapControlButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon),
        onPressed: onPressed,
        color: const Color(0xFF001F3F),
        iconSize: 22,
      ),
    );
  }
}

class _FabOption extends StatelessWidget {
  final String label;
  final Widget icon;
  final VoidCallback onPressed;

  const _FabOption({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 4,
              ),
            ],
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF001F3F),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FloatingActionButton(
          mini: true,
          onPressed: onPressed,
          backgroundColor: Colors.white,
          child: icon,
        ),
      ],
    );
  }
}

class _MapTypeOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _MapTypeOption({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF001F3F)
                  : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF001F3F)
                    : Colors.grey.shade300,
                width: 2,
              ),
            ),
            child: Icon(
              icon,
              color: isSelected ? Colors.white : Colors.grey,
              size: 28,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected ? const Color(0xFF001F3F) : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}

class _LayerOption extends StatelessWidget {
  final String label;
  final Widget icon;
  final Color color;

  const _LayerOption({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(child: icon),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

class _PointMarker extends StatelessWidget {
  final int index;
  const _PointMarker({required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF001F3F).withValues(alpha: 0.9),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Center(
        child: Text(
          '$index',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _CurrentMarker extends StatelessWidget {
  const _CurrentMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.blue.withValues(alpha: 0.9),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: const Icon(Icons.person_pin_circle, color: Colors.white, size: 20),
    );
  }
}

class CompassWidget extends StatefulWidget {
  const CompassWidget({Key? key}) : super(key: key);

  @override
  State<CompassWidget> createState() => _CompassWidgetState();
}

class _CompassWidgetState extends State<CompassWidget> {
  double _heading = 0.0;

  @override
  void initState() {
    super.initState();
    _initCompass();
  }

  void _initCompass() {
    FlutterCompass.events?.listen((CompassEvent event) {
      if (event.heading != null) {
        setState(() {
          _heading = event.heading!;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Transform.rotate(
        angle: -_heading * (pi / 180), // Convert degrees to radians and rotate
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Compass circle background
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF001F3F).withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
            ),
            // North pointer (red)
            CustomPaint(size: const Size(40, 40), painter: _CompassPainter()),
            // N letter
            const Positioned(
              top: 6,
              child: Text(
                'N',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFE53E3E),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..style = PaintingStyle.fill;

    // North pointer (red)
    paint.color = const Color(0xFFE53E3E);
    final northPath = ui.Path()
      ..moveTo(center.dx, center.dy - 15)
      ..lineTo(center.dx - 4, center.dy)
      ..lineTo(center.dx, center.dy - 3)
      ..close();
    canvas.drawPath(northPath, paint);

    // South pointer (white with dark border)
    paint.color = Colors.white;
    final southPath = ui.Path()
      ..moveTo(center.dx, center.dy + 15)
      ..lineTo(center.dx + 4, center.dy)
      ..lineTo(center.dx, center.dy + 3)
      ..close();
    canvas.drawPath(southPath, paint);

    // Border for south pointer
    paint
      ..color = const Color(0xFF001F3F).withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.drawPath(southPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
