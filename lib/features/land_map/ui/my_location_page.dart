import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/coordinate_format.dart';
import '../state/land_map_notifier.dart';
import '../state/settings_provider.dart';

class MyLocationPage extends ConsumerStatefulWidget {
  const MyLocationPage({super.key});

  @override
  ConsumerState<MyLocationPage> createState() => _MyLocationPageState();
}

class _MyLocationPageState extends ConsumerState<MyLocationPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final err = await ref.read(landMapProvider.notifier).initLocation();
      if (err != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err)),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final st = ref.watch(landMapProvider);
    final format = ref.watch(coordinateFormatProvider);

    final lat = st.current?.latitude;
    final lon = st.current?.longitude;

    final latText = lat != null ? lat.toStringAsFixed(6) : '--';
    final lonText = lon != null ? lon.toStringAsFixed(6) : '--';
    final formatted = (lat != null && lon != null)
        ? CoordinateFormatter.format(lat, lon, format)
        : 'Waiting for GPS...';

    final ageText = _formatAge(st.locationTimestamp);
    final altitudeText = st.altitudeMeters == null
        ? '—'
        : '${st.altitudeMeters!.toStringAsFixed(1)} m';

    return SingleChildScrollView(
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(28),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.explore,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Latitude',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      latText,
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Longitude',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      lonText,
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      formatted,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 20,
                bottom: -24,
                child: FloatingActionButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Camera - Coming soon')),
                    );
                  },
                  backgroundColor: theme.colorScheme.primary,
                  child: const Icon(Icons.camera_alt, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _InfoRow(
                    label: 'Altitude',
                    value: altitudeText,
                  ),
                  _InfoDivider(),
                  _InfoRow(
                    label: 'Coordinates accuracy',
                    value: st.accuracyMeters == null
                        ? '—'
                        : '${st.accuracyMeters!.toStringAsFixed(1)} m',
                  ),
                  _InfoDivider(),
                  _InfoRow(label: 'Location age', value: ageText),
                  _InfoDivider(),
                  const _InfoRow(
                    label: 'Number of satellites',
                    value: 'Unavailable',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _formatAge(DateTime? timestamp) {
    if (timestamp == null) return '—';
    final diff = DateTime.now().difference(timestamp);
    if (diff.inSeconds < 0) return '—';
    final minutes = diff.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = diff.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = diff.inHours.toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, color: Colors.grey.shade200);
  }
}
