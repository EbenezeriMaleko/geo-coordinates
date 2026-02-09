import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../models/coordinate_format.dart';
import '../state/land_map_notifier.dart';
import '../state/settings_provider.dart';

class LandMapPage extends ConsumerStatefulWidget {
  const LandMapPage({super.key});

  @override
  ConsumerState<LandMapPage> createState() => _LandMapPageState();
}

class _LandMapPageState extends ConsumerState<LandMapPage> {
  final MapController _mapController = MapController();
  final TextEditingController _nameController = TextEditingController();

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
        Polygon(points: st.points, borderStrokeWidth: 3),
    ];

    final polylines = <Polyline>[
      if (st.points.length >= 2) Polyline(points: st.points, strokeWidth: 3),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Land Map'),
        actions: [
          IconButton(
            onPressed: () async {
              final err = await notifier.refreshLocation();
              if (err != null) _snack(err);
              final now = ref.read(landMapProvider).current;
              if (now != null) _mapController.move(now, 17);
            },
            icon: const Icon(Icons.my_location),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Land name (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final err = await notifier.addPointFromCurrent();
                          if (err != null) _snack(err);
                        },
                        label: const Text('Add Point'),
                        icon: const Icon(Icons.add_location_alt),
                      ),
                    ),

                    const SizedBox(width: 10),

                    ElevatedButton(
                      onPressed: notifier.undoLastPoint,
                      child: const Text('Undo'),
                    ),

                    const SizedBox(width: 10),

                    ElevatedButton(
                      onPressed: notifier.clearPoints,
                      child: const Text('Clear'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    st.current == null
                        ? 'Locating...'
                        : 'GPS: ${CoordinateFormatter.format(st.current!.latitude, st.current!.longitude, coordinateFormat)} | Accuracy: ${(st.accuracyMeters ?? 0).toStringAsFixed(0)}m',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(initialCenter: center, initialZoom: 16),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.landmapper',
                ),
                if (polygons.isNotEmpty) PolygonLayer(polygons: polygons),
                if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
                MarkerLayer(markers: markers),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: st.isSaving
                    ? null
                    : () async {
                        final err = await notifier.saveOffline(
                          name: _nameController.text.trim(),
                        );
                        if (err != null) {
                          _snack(err);
                        } else {
                          _nameController.clear();
                          _snack('Saved offline');
                        }
                      },
                icon: const Icon(Icons.save),
                label: Text(st.isSaving ? 'Saving...' : 'Save Offline'),
              ),
            ),
          ),
        ],
      ),
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
        color: Colors.red.withValues(alpha: 0.85),
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
        color: Colors.blue.withValues(alpha: 0.85),
      ),
      child: const Icon(Icons.person_pin_circle, color: Colors.white, size: 20),
    );
  }
}
