import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../models/coordinate_format.dart';
import '../state/land_map_notifier.dart';
import '../state/settings_provider.dart';

class MyLocationPage extends ConsumerStatefulWidget {
  const MyLocationPage({super.key});

  @override
  ConsumerState<MyLocationPage> createState() => _MyLocationPageState();
}

class _MyLocationPageState extends ConsumerState<MyLocationPage> {
  StreamSubscription<Position>? _locationSubscription;
  late final LandMapNotifier _landMapNotifier;
  bool _isInitializing = false;
  bool _isStreaming = false;
  bool _serviceDisabled = false;
  bool _permissionDenied = false;
  bool _permissionDeniedForever = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _landMapNotifier = ref.read(landMapProvider.notifier);
    Future.microtask(_initializeTracking);
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeTracking() async {
    if (!mounted) return;

    setState(() {
      _isInitializing = true;
      _isStreaming = false;
      _serviceDisabled = false;
      _permissionDenied = false;
      _permissionDeniedForever = false;
      _errorMessage = null;
    });

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _serviceDisabled = true;
      });
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (!mounted) return;

    if (permission == LocationPermission.denied) {
      setState(() {
        _isInitializing = false;
        _permissionDenied = true;
      });
      return;
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _isInitializing = false;
        _permissionDeniedForever = true;
      });
      return;
    }

    await _landMapNotifier.refreshLocation();
    if (!mounted) return;
    await _startTracking();

    if (!mounted) return;
    setState(() {
      _isInitializing = false;
      _isStreaming = true;
    });
  }

  Future<void> _startTracking() async {
    await _locationSubscription?.cancel();
    if (!mounted) return;

    _locationSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 1,
          ),
        ).listen(
          (position) {
            _landMapNotifier.updateCurrentFromPosition(position);
            if (!mounted) return;

            if (_errorMessage != null ||
                _permissionDenied ||
                _permissionDeniedForever ||
                _serviceDisabled) {
              setState(() {
                _errorMessage = null;
                _permissionDenied = false;
                _permissionDeniedForever = false;
                _serviceDisabled = false;
              });
            }
          },
          onError: (_) {
            if (!mounted) return;
            setState(() {
              _errorMessage = 'Failed to read live location.';
              _isStreaming = false;
            });
          },
        );
  }

  Future<void> _retry() async {
    await _locationSubscription?.cancel();
    if (!mounted) return;
    await _initializeTracking();
  }

  Future<void> _openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  Future<void> _openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  _LocationViewState _viewState() {
    if (_isInitializing) return _LocationViewState.loading;
    if (_serviceDisabled) return _LocationViewState.serviceDisabled;
    if (_permissionDeniedForever) {
      return _LocationViewState.permissionDeniedForever;
    }
    if (_permissionDenied) return _LocationViewState.permissionDenied;
    if (_errorMessage != null) return _LocationViewState.error;
    return _LocationViewState.ready;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final st = ref.watch(landMapProvider);
    final format = ref.watch(coordinateFormatProvider);
    final unit = ref.watch(distanceUnitProvider);
    final viewState = _viewState();

    final lat = st.current?.latitude;
    final lon = st.current?.longitude;

    final latText = lat != null ? lat.toStringAsFixed(6) : '--';
    final lonText = lon != null ? lon.toStringAsFixed(6) : '--';
    final formatted = (lat != null && lon != null)
        ? CoordinateFormatter.format(lat, lon, format)
        : 'Waiting for GPS...';

    final ageText = _formatAge(st.locationTimestamp);
    final altitudeText = _formatDistanceValue(st.altitudeMeters, unit);
    final quality = _qualityFromAccuracy(st.accuracyMeters);
    final qualityColor = _qualityColor(quality);
    final lastUpdateText = _formatLastUpdated(st.locationTimestamp);
    final accuracyText = _formatDistanceValue(st.accuracyMeters, unit);

    return SingleChildScrollView(
      child: Container(
        color: Colors.white,
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
                    // borderRadius: const BorderRadius.vertical(
                    //   bottom: Radius.circular(28),
                    // ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            Container(
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
                            const Spacer(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      _StatusChip(
                        label: _statusLabel(viewState),
                        color: _statusColor(viewState),
                      ),
                      const SizedBox(height: 12),
                      if (viewState != _LocationViewState.ready)
                        _LocationStatePanel(
                          state: viewState,
                          errorMessage: _errorMessage,
                          onRetry: _retry,
                          onOpenLocationSettings: _openLocationSettings,
                          onOpenAppSettings: _openAppSettings,
                        ),
                      if (viewState != _LocationViewState.ready)
                        const SizedBox(height: 12),
                      Text(
                        'Latitude',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        transitionBuilder: (child, animation) =>
                            FadeTransition(opacity: animation, child: child),
                        child: Text(
                          latText,
                          key: ValueKey(latText),
                          style: theme.textTheme.displaySmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
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
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        transitionBuilder: (child, animation) =>
                            FadeTransition(opacity: animation, child: child),
                        child: Text(
                          lonText,
                          key: ValueKey(lonText),
                          style: theme.textTheme.displaySmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
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
                      const SizedBox(height: 8),
                      Text(
                        'Last update: $lastUpdateText',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
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
                    _InfoRow(label: 'Altitude', value: altitudeText),
                    _InfoDivider(),
                    _InfoRow(
                      label: 'Coordinates accuracy',
                      value: accuracyText,
                      valueColor: qualityColor,
                    ),
                    _InfoDivider(),
                    _InfoRow(
                      label: 'Signal quality',
                      value: quality,
                      valueColor: qualityColor,
                    ),
                    _InfoDivider(),
                    _InfoRow(label: 'Location age', value: ageText),
                    _InfoDivider(),
                    _InfoRow(
                      label: 'Tracking',
                      value: _isStreaming ? 'Live' : 'Stopped',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  String _statusLabel(_LocationViewState state) {
    switch (state) {
      case _LocationViewState.loading:
        return 'Initializing GPS...';
      case _LocationViewState.serviceDisabled:
        return 'Location service is OFF';
      case _LocationViewState.permissionDenied:
        return 'Location permission required';
      case _LocationViewState.permissionDeniedForever:
        return 'Permission blocked';
      case _LocationViewState.error:
        return 'Location error';
      case _LocationViewState.ready:
        return 'Live tracking';
    }
  }

  Color _statusColor(_LocationViewState state) {
    switch (state) {
      case _LocationViewState.ready:
        return const Color(0xFF1B8F4B);
      case _LocationViewState.loading:
        return const Color(0xFF2A6FB3);
      case _LocationViewState.serviceDisabled:
      case _LocationViewState.permissionDenied:
      case _LocationViewState.permissionDeniedForever:
      case _LocationViewState.error:
        return const Color(0xFFC65D12);
    }
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

  String _formatLastUpdated(DateTime? timestamp) {
    if (timestamp == null) return '—';
    final hh = timestamp.hour.toString().padLeft(2, '0');
    final mm = timestamp.minute.toString().padLeft(2, '0');
    final ss = timestamp.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  String _qualityFromAccuracy(double? accuracy) {
    if (accuracy == null) return 'Unknown';
    if (accuracy <= 8) return 'Good';
    if (accuracy <= 20) return 'Fair';
    return 'Poor';
  }

  Color _qualityColor(String quality) {
    switch (quality) {
      case 'Good':
        return const Color(0xFF1B8F4B);
      case 'Fair':
        return const Color(0xFFC67B12);
      case 'Poor':
        return const Color(0xFFC94835);
      default:
        return const Color(0xFF6E7781);
    }
  }

  String _formatDistanceValue(double? meters, DistanceUnit unit) {
    if (meters == null) return '—';
    if (unit == DistanceUnit.feet) {
      final feet = meters * 3.28084;
      return '${feet.toStringAsFixed(1)} ft';
    }
    return '${meters.toStringAsFixed(1)} m';
  }
}

enum _LocationViewState {
  loading,
  ready,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  error,
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _LocationStatePanel extends StatelessWidget {
  final _LocationViewState state;
  final String? errorMessage;
  final Future<void> Function() onRetry;
  final Future<void> Function() onOpenLocationSettings;
  final Future<void> Function() onOpenAppSettings;

  const _LocationStatePanel({
    required this.state,
    required this.errorMessage,
    required this.onRetry,
    required this.onOpenLocationSettings,
    required this.onOpenAppSettings,
  });

  @override
  Widget build(BuildContext context) {
    final message = switch (state) {
      _LocationViewState.loading => 'Preparing GPS...',
      _LocationViewState.serviceDisabled =>
        'Location service is disabled. Turn it on to continue.',
      _LocationViewState.permissionDenied =>
        'Location permission was denied. Allow permission to continue.',
      _LocationViewState.permissionDeniedForever =>
        'Location permission is permanently denied. Open app settings to enable it.',
      _LocationViewState.error => errorMessage ?? 'Unexpected location error.',
      _LocationViewState.ready => '',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (state == _LocationViewState.serviceDisabled)
                OutlinedButton(
                  onPressed: onOpenLocationSettings,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                  ),
                  child: const Text('Open location settings'),
                ),
              if (state == _LocationViewState.permissionDeniedForever)
                OutlinedButton(
                  onPressed: onOpenAppSettings,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                  ),
                  child: const Text('Open app settings'),
                ),
              if (state != _LocationViewState.loading)
                ElevatedButton(
                  onPressed: onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                  ),
                  child: const Text('Retry'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({required this.label, required this.value, this.valueColor});

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
              color: valueColor ?? Colors.black87,
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
