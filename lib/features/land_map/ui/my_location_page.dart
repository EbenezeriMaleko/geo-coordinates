import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../models/coordinate_format.dart';
import '../models/reference_ellipsoid.dart';
import '../services/utm_converter.dart';
import '../state/land_map_notifier.dart';
import '../state/settings_provider.dart';

class MyLocationPage extends ConsumerStatefulWidget {
  const MyLocationPage({super.key});

  @override
  ConsumerState<MyLocationPage> createState() => _MyLocationPageState();
}

class _MyLocationPageState extends ConsumerState<MyLocationPage>
    with AutomaticKeepAliveClientMixin {
  static const String _latestPhotoKey = 'my_location_latest_photo';
  static const String _photosDirName = 'geo_photos';

  StreamSubscription<Position>? _locationSubscription;
  late final LandMapNotifier _landMapNotifier;
  bool _isInitializing = false;
  bool _isStreaming = false;
  bool _serviceDisabled = false;
  bool _permissionDenied = false;
  bool _permissionDeniedForever = false;
  String? _errorMessage;
  bool _isCapturingPhoto = false;
  _GeoTaggedPhoto? _latestPhoto;

  @override
  void initState() {
    super.initState();
    _landMapNotifier = ref.read(landMapProvider.notifier);
    Future.microtask(() async {
      await _restoreLatestPhoto();
      await _initializeTracking();
    });
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

  Future<void> _openGeoCamera() async {
    if (_isCapturingPhoto) return;

    setState(() {
      _isCapturingPhoto = true;
    });

    try {
      final format = ref.read(coordinateFormatProvider);
      final unit = ref.read(distanceUnitProvider);
      final quality = ref.read(photoQualityProvider);
      final captureMode = ref.read(photoCaptureModeProvider);
      final ellipsoid = ref.read(referenceEllipsoidProvider);

      if (captureMode == PhotoCaptureMode.systemCamera && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'System camera mode is not available yet, using in-app camera.',
            ),
          ),
        );
      }

      final capture = await Navigator.of(context).push<_GeoTaggedPhoto>(
        MaterialPageRoute(
          builder: (_) => _GeoCameraCapturePage(
            coordinateFormat: format,
            referenceEllipsoid: ellipsoid,
            distanceUnit: unit,
            quality: quality,
            initialName: _latestPhoto?.name ?? '',
          ),
          fullscreenDialog: true,
        ),
      );

      if (!mounted || capture == null) return;

      final persistedCapture = await _persistCapturedPhoto(capture);
      final saveToGallery = ref.read(saveToGalleryProvider);
      if (saveToGallery) {
        await _saveImageToGallery(persistedCapture.imagePath);
      }

      setState(() {
        _latestPhoto = persistedCapture;
      });
      _showCaptureDetails(persistedCapture);
    } on PlatformException catch (e) {
      if (!mounted) return;
      final code = e.code.toLowerCase();
      final message = code.contains('camera_access_denied')
          ? 'Camera permission is denied. Allow camera permission in app settings.'
          : 'Failed to open camera. Please try again.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to capture GPS photo. Try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCapturingPhoto = false;
        });
      }
    }
  }

  Future<void> _restoreLatestPhoto() async {
    final box = Hive.box('landbox');
    final raw = box.get(_latestPhotoKey);
    if (raw is! Map) return;

    final data = Map<String, dynamic>.from(raw);
    final imagePath = data['imagePath']?.toString() ?? '';
    if (imagePath.isEmpty) return;
    if (!await File(imagePath).exists()) return;

    final restored = _GeoTaggedPhoto.fromMap(data);
    if (restored == null || !mounted) return;

    setState(() {
      _latestPhoto = restored;
    });
  }

  Future<_GeoTaggedPhoto> _persistCapturedPhoto(_GeoTaggedPhoto capture) async {
    final photosDir = await _getPhotosDirectory();
    final source = File(capture.imagePath);
    var storedPath = capture.imagePath;

    if (await source.exists()) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ext = _fileExtension(capture.imagePath);
      final safeName = _safeFileName(capture.name);
      final fileName = safeName.isEmpty
          ? 'gps_$timestamp$ext'
          : '${safeName}_$timestamp$ext';
      final destination = File('${photosDir.path}/$fileName');
      final copied = await source.copy(destination.path);
      storedPath = copied.path;

      final keepOriginal = ref.read(saveOriginalPhotoProvider);
      if (!keepOriginal && source.path != copied.path) {
        try {
          await source.delete();
        } catch (_) {
          // Keep working even if source cleanup fails.
        }
      }
    }

    final persisted = capture.copyWith(imagePath: storedPath);
    final box = Hive.box('landbox');
    await box.put(_latestPhotoKey, persisted.toMap());
    return persisted;
  }

  Future<void> _saveImageToGallery(String imagePath) async {
    try {
      final saved = await GallerySaver.saveImage(
        imagePath,
        albumName: 'GeoCoordinates',
      );
      if (!mounted) return;
      if (saved == true) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Photo saved to gallery')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not save photo to gallery. Check permissions.',
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save photo to gallery. Check permissions.'),
        ),
      );
    }
  }

  Future<Directory> _getPhotosDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory('${appDir.path}/$_photosDirName');
    if (!await photosDir.exists()) {
      await photosDir.create(recursive: true);
    }
    return photosDir;
  }

  String _fileExtension(String path) {
    final index = path.lastIndexOf('.');
    if (index == -1) return '.jpg';
    final ext = path.substring(index);
    return ext.isEmpty ? '.jpg' : ext;
  }

  String _safeFileName(String name) {
    final trimmed = name.trim().toLowerCase();
    if (trimmed.isEmpty) return '';
    final cleaned = trimmed.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return cleaned.replaceAll(RegExp(r'^_+|_+$'), '');
  }

  void _showCaptureDetails(_GeoTaggedPhoto capture) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        final format = ref.read(coordinateFormatProvider);
        return _CapturedPhotoDetailsSheet(
          capture: capture,
          formattedCoordinates: capture.position == null
              ? 'Coordinates unavailable'
              : CoordinateFormatter.format(
                  capture.position!.latitude,
                  capture.position!.longitude,
                  format,
                ),
          coordinateFormat: format,
          referenceEllipsoid: ref.read(referenceEllipsoidProvider),
          distanceUnit: ref.read(distanceUnitProvider),
        );
      },
    );
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
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final st = ref.watch(landMapProvider);
    final format = ref.watch(coordinateFormatProvider);
    final ellipsoid = ref.watch(referenceEllipsoidProvider);
    final unit = ref.watch(distanceUnitProvider);
    final viewState = _viewState();

    final lat = st.current?.latitude;
    final lon = st.current?.longitude;

    final latText = lat != null ? lat.toStringAsFixed(6) : '--';
    final lonText = lon != null ? lon.toStringAsFixed(6) : '--';
    final formatted = (lat != null && lon != null)
        ? CoordinateFormatter.format(lat, lon, format)
        : 'Waiting for GPS...';
    final utmText = (lat != null && lon != null)
        ? _formatUtmCoordinate(lat, lon, ellipsoid)
        : 'Waiting for UTM...';

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
                      const SizedBox(height: 4),
                      Text(
                        'Reference ellipsoid: ${ellipsoid.displayName}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        utmText,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
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
                    heroTag: 'my_location_camera_fab',
                    onPressed: _isCapturingPhoto ? null : _openGeoCamera,
                    backgroundColor: theme.colorScheme.primary,
                    child: _isCapturingPhoto
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.camera_alt, color: Colors.white),
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
            if (_latestPhoto != null) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _LatestCaptureCard(
                  capture: _latestPhoto!,
                  unit: unit,
                  coordinateFormat: format,
                  referenceEllipsoid: ellipsoid,
                  onViewDetails: () => _showCaptureDetails(_latestPhoto!),
                ),
              ),
            ],
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

class _GeoTaggedPhoto {
  final String imagePath;
  final DateTime capturedAt;
  final Position? position;
  final Placemark? placemark;
  final String? locationError;
  final String name;

  const _GeoTaggedPhoto({
    required this.imagePath,
    required this.capturedAt,
    required this.position,
    required this.placemark,
    required this.locationError,
    required this.name,
  });

  _GeoTaggedPhoto copyWith({
    String? imagePath,
    DateTime? capturedAt,
    Position? position,
    Placemark? placemark,
    String? locationError,
    String? name,
  }) {
    return _GeoTaggedPhoto(
      imagePath: imagePath ?? this.imagePath,
      capturedAt: capturedAt ?? this.capturedAt,
      position: position ?? this.position,
      placemark: placemark ?? this.placemark,
      locationError: locationError ?? this.locationError,
      name: name ?? this.name,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'imagePath': imagePath,
      'capturedAt': capturedAt.toIso8601String(),
      'position': _positionToMap(position),
      'placemark': _placemarkToMap(placemark),
      'locationError': locationError,
      'name': name,
    };
  }

  static _GeoTaggedPhoto? fromMap(Map<String, dynamic> raw) {
    final imagePath = raw['imagePath']?.toString();
    final capturedAtRaw = raw['capturedAt']?.toString();
    final capturedAt = capturedAtRaw == null
        ? null
        : DateTime.tryParse(capturedAtRaw);
    if (imagePath == null || imagePath.isEmpty || capturedAt == null) {
      return null;
    }

    return _GeoTaggedPhoto(
      imagePath: imagePath,
      capturedAt: capturedAt,
      position: _positionFromMap(raw['position']),
      placemark: _placemarkFromMap(raw['placemark']),
      locationError: raw['locationError']?.toString(),
      name: raw['name']?.toString() ?? '',
    );
  }
}

class _LatestCaptureCard extends StatelessWidget {
  final _GeoTaggedPhoto capture;
  final DistanceUnit unit;
  final CoordinateFormat coordinateFormat;
  final ReferenceEllipsoid referenceEllipsoid;
  final VoidCallback onViewDetails;

  const _LatestCaptureCard({
    required this.capture,
    required this.unit,
    required this.coordinateFormat,
    required this.referenceEllipsoid,
    required this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pos = capture.position;

    final coordinateText = pos == null
        ? 'Coordinates unavailable'
        : CoordinateFormatter.format(
            pos.latitude,
            pos.longitude,
            coordinateFormat,
          );
    final utmText = pos == null
        ? 'UTM unavailable'
        : _formatUtmCoordinate(
            pos.latitude,
            pos.longitude,
            referenceEllipsoid,
          );
    final accuracyText = pos == null
        ? '—'
        : _formatDistance(pos.accuracy, unit);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  capture.name.isEmpty ? 'Latest GPS Photo' : capture.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: onViewDetails,
                  child: const Text('View details'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 200,
                width: double.infinity,
                child: _GeoPhotoCanvas(
                  imagePath: capture.imagePath,
                  name: capture.name,
                  lines: _buildOverlayLines(
                    capture: capture,
                    coordinateFormat: coordinateFormat,
                    referenceEllipsoid: referenceEllipsoid,
                    unit: unit,
                  ),
                  dense: true,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              coordinateText,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Ellipsoid: ${referenceEllipsoid.displayName}',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: 4),
            Text(
              utmText,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: 4),
            Text(
              'Accuracy: $accuracyText',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
            ),
            if (capture.locationError != null) ...[
              const SizedBox(height: 4),
              Text(
                capture.locationError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFC65D12),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CapturedPhotoDetailsSheet extends StatelessWidget {
  final _GeoTaggedPhoto capture;
  final String formattedCoordinates;
  final CoordinateFormat coordinateFormat;
  final ReferenceEllipsoid referenceEllipsoid;
  final DistanceUnit distanceUnit;

  const _CapturedPhotoDetailsSheet({
    required this.capture,
    required this.formattedCoordinates,
    required this.coordinateFormat,
    required this.referenceEllipsoid,
    required this.distanceUnit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pos = capture.position;
    final placemarkText = _formatPlacemark(capture.placemark);
    final date = capture.capturedAt;
    final when =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
    final utmText = pos == null
        ? '—'
        : _formatUtmCoordinate(
            pos.latitude,
            pos.longitude,
            referenceEllipsoid,
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: ListView(
        shrinkWrap: true,
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
          const SizedBox(height: 12),
          Text(
            capture.name.isEmpty ? 'GPS Photo Details' : capture.name,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 420,
              width: double.infinity,
              child: _GeoPhotoCanvas(
                imagePath: capture.imagePath,
                name: capture.name,
                lines: _buildOverlayLines(
                  capture: capture,
                  coordinateFormat: coordinateFormat,
                  referenceEllipsoid: referenceEllipsoid,
                  unit: distanceUnit,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _DetailRow(label: 'Captured at', value: when),
          _DetailRow(
            label: 'Reference ellipsoid',
            value: referenceEllipsoid.displayName,
          ),
          _DetailRow(label: 'Coordinates', value: formattedCoordinates),
          _DetailRow(label: 'UTM', value: utmText),
          _DetailRow(label: 'Latitude', value: _formatNumber(pos?.latitude)),
          _DetailRow(label: 'Longitude', value: _formatNumber(pos?.longitude)),
          _DetailRow(
            label: 'Accuracy',
            value: pos == null ? '—' : '${pos.accuracy.toStringAsFixed(1)} m',
          ),
          _DetailRow(
            label: 'Altitude',
            value: pos == null ? '—' : '${pos.altitude.toStringAsFixed(1)} m',
          ),
          _DetailRow(
            label: 'Speed',
            value: pos == null ? '—' : '${pos.speed.toStringAsFixed(2)} m/s',
          ),
          _DetailRow(
            label: 'Heading',
            value: pos == null ? '—' : '${pos.heading.toStringAsFixed(1)}°',
          ),
          _DetailRow(label: 'Address', value: placemarkText),
          if (capture.locationError != null)
            _DetailRow(label: 'Location note', value: capture.locationError!),
        ],
      ),
    );
  }
}

class _GeoCameraCapturePage extends StatefulWidget {
  final CoordinateFormat coordinateFormat;
  final ReferenceEllipsoid referenceEllipsoid;
  final DistanceUnit distanceUnit;
  final PhotoCaptureQuality quality;
  final String initialName;

  const _GeoCameraCapturePage({
    required this.coordinateFormat,
    required this.referenceEllipsoid,
    required this.distanceUnit,
    required this.quality,
    required this.initialName,
  });

  @override
  State<_GeoCameraCapturePage> createState() => _GeoCameraCapturePageState();
}

class _GeoCameraCapturePageState extends State<_GeoCameraCapturePage> {
  CameraController? _cameraController;
  StreamSubscription<Position>? _positionSubscription;
  final TextEditingController _nameController = TextEditingController();
  bool _isInitializing = true;
  bool _isTakingPhoto = false;
  String? _setupError;
  String? _locationError;
  Position? _livePosition;
  Placemark? _livePlacemark;
  Position? _placemarkPosition;
  XFile? _capturedPhoto;
  DateTime? _capturedAt;
  Position? _capturedPosition;
  Placemark? _capturedPlacemark;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.initialName;
    Future.microtask(_initialize);
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _cameraController?.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      final cameras = await availableCameras();
      final rearCamera = cameras.where(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );
      final description = rearCamera.isNotEmpty
          ? rearCamera.first
          : cameras.first;

      final controller = CameraController(
        description,
        _resolutionForQuality(widget.quality),
        enableAudio: false,
      );
      await controller.initialize();

      _cameraController = controller;
      await _startLocationTracking();

      if (!mounted) return;
      setState(() {
        _isInitializing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _setupError = 'Failed to initialize the in-app camera.';
      });
    }
  }

  Future<void> _startLocationTracking() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _locationError = 'Location service is disabled.';
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      _locationError = 'Location permission denied.';
      return;
    }
    if (permission == LocationPermission.deniedForever) {
      _locationError = 'Location permission blocked in settings.';
      return;
    }

    try {
      final current = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );
      _livePosition = current;
      _livePlacemark = await _reverseGeocode(current);
      _placemarkPosition = current;
    } catch (_) {
      _locationError = 'Unable to resolve current location.';
    }

    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 1,
          ),
        ).listen(
          (position) async {
            _livePosition = position;
            if (!mounted) return;
            setState(() {});

            final shouldRefreshPlacemark =
                _placemarkPosition == null ||
                Geolocator.distanceBetween(
                      _placemarkPosition!.latitude,
                      _placemarkPosition!.longitude,
                      position.latitude,
                      position.longitude,
                    ) >
                    20;
            if (!shouldRefreshPlacemark) return;

            final nextPlacemark = await _reverseGeocode(position);
            if (!mounted) return;
            setState(() {
              _livePlacemark = nextPlacemark;
              _placemarkPosition = position;
            });
          },
          onError: (_) {
            if (!mounted) return;
            setState(() {
              _locationError = 'Live location updates failed.';
            });
          },
        );
  }

  Future<void> _takePhoto() async {
    final controller = _cameraController;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isTakingPhoto) {
      return;
    }

    setState(() {
      _isTakingPhoto = true;
    });

    try {
      final file = await controller.takePicture();
      if (!mounted) return;

      final captureTime = DateTime.now();
      final position = _livePosition;
      Placemark? placemark = _livePlacemark;
      if (position != null && placemark == null) {
        placemark = await _reverseGeocode(position);
      }

      if (!mounted) return;
      setState(() {
        _capturedPhoto = file;
        _capturedAt = captureTime;
        _capturedPosition = position;
        _capturedPlacemark = placemark;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to capture photo.')));
    } finally {
      if (mounted) {
        setState(() {
          _isTakingPhoto = false;
        });
      }
    }
  }

  void _retake() {
    setState(() {
      _capturedPhoto = null;
      _capturedAt = null;
      _capturedPosition = null;
      _capturedPlacemark = null;
    });
  }

  void _save() {
    final capturedPhoto = _capturedPhoto;
    if (capturedPhoto == null) return;

    Navigator.of(context).pop(
      _GeoTaggedPhoto(
        imagePath: capturedPhoto.path,
        capturedAt: _capturedAt ?? DateTime.now(),
        position: _capturedPosition,
        placemark: _capturedPlacemark,
        locationError: _locationError,
        name: _nameController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewLines = _buildOverlayLines(
      capture: _GeoTaggedPhoto(
        imagePath: _capturedPhoto?.path ?? '',
        capturedAt: _capturedAt ?? DateTime.now(),
        position: _capturedPhoto == null ? _livePosition : _capturedPosition,
        placemark: _capturedPhoto == null ? _livePlacemark : _capturedPlacemark,
        locationError: _locationError,
        name: _nameController.text.trim(),
      ),
      coordinateFormat: widget.coordinateFormat,
      referenceEllipsoid: widget.referenceEllipsoid,
      unit: widget.distanceUnit,
      includeLocationNote: false,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _isInitializing
            ? const Center(child: CircularProgressIndicator())
            : _setupError != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _setupError!,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: _capturedPhoto == null
                        ? _buildCameraPreview()
                        : _GeoPhotoCanvas(
                            imagePath: _capturedPhoto!.path,
                            name: _nameController.text.trim(),
                            lines: previewLines,
                          ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.55),
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.72),
                            ],
                            stops: const [0, 0.36, 1],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    left: 16,
                    right: 16,
                    child: Row(
                      children: [
                        _TopIconButton(
                          icon: Icons.close,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _capturedPhoto == null ? 'GPS Camera' : 'Preview',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 28,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18),
                            ),
                          ),
                          child: TextField(
                            controller: _nameController,
                            style: const TextStyle(color: Colors.black54),
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              hintText: 'Enter place name',
                              hintStyle: TextStyle(color: Colors.black54),
                              prefixIcon: Icon(
                                Icons.edit_location_alt_outlined,
                                color: Colors.black54,
                              ),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                            ),
                          ),
                        ),
                        if (_locationError != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            _locationError!,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 18),
                        if (_capturedPhoto == null)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              GestureDetector(
                                onTap: _isTakingPhoto ? null : _takePhoto,
                                child: Container(
                                  width: 86,
                                  height: 86,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 5,
                                    ),
                                  ),
                                  child: Center(
                                    child: Container(
                                      width: 68,
                                      height: 68,
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                      child: _isTakingPhoto
                                          ? const Padding(
                                              padding: EdgeInsets.all(20),
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                              ),
                                            )
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        else
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _retake,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(
                                      color: Colors.white70,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                  ),
                                  child: const Text('Retake'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _save,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0C8A8C),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                  ),
                                  child: const Text('Save'),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(controller),
        IgnorePointer(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: _OverlayTextBlock(
                title: _nameController.text.trim(),
                lines: _buildOverlayLines(
                  capture: _GeoTaggedPhoto(
                    imagePath: '',
                    capturedAt: DateTime.now(),
                    position: _livePosition,
                    placemark: _livePlacemark,
                    locationError: _locationError,
                    name: _nameController.text.trim(),
                  ),
                  coordinateFormat: widget.coordinateFormat,
                  referenceEllipsoid: widget.referenceEllipsoid,
                  unit: widget.distanceUnit,
                  includeLocationNote: false,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<Placemark?> _reverseGeocode(Position position) async {
    try {
      final marks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (marks.isEmpty) return null;
      return marks.first;
    } catch (_) {
      return null;
    }
  }

  ResolutionPreset _resolutionForQuality(PhotoCaptureQuality quality) {
    switch (quality) {
      case PhotoCaptureQuality.low:
        return ResolutionPreset.medium;
      case PhotoCaptureQuality.medium:
        return ResolutionPreset.high;
      case PhotoCaptureQuality.high:
        return ResolutionPreset.veryHigh;
    }
  }
}

Map<String, dynamic>? _positionToMap(Position? position) {
  if (position == null) return null;
  return {
    'latitude': position.latitude,
    'longitude': position.longitude,
    'timestamp': position.timestamp.toIso8601String(),
    'accuracy': position.accuracy,
    'altitude': position.altitude,
    'altitudeAccuracy': position.altitudeAccuracy,
    'heading': position.heading,
    'headingAccuracy': position.headingAccuracy,
    'speed': position.speed,
    'speedAccuracy': position.speedAccuracy,
    'floor': position.floor,
    'isMocked': position.isMocked,
  };
}

Position? _positionFromMap(dynamic raw) {
  if (raw is! Map) return null;
  try {
    final data = Map<String, dynamic>.from(raw);
    return Position(
      latitude: (data['latitude'] as num).toDouble(),
      longitude: (data['longitude'] as num).toDouble(),
      timestamp: DateTime.parse(data['timestamp'].toString()),
      accuracy: (data['accuracy'] as num).toDouble(),
      altitude: (data['altitude'] as num).toDouble(),
      altitudeAccuracy: (data['altitudeAccuracy'] as num).toDouble(),
      heading: (data['heading'] as num).toDouble(),
      headingAccuracy: (data['headingAccuracy'] as num).toDouble(),
      speed: (data['speed'] as num).toDouble(),
      speedAccuracy: (data['speedAccuracy'] as num).toDouble(),
      floor: (data['floor'] as num?)?.toInt(),
      isMocked: data['isMocked'] == true,
    );
  } catch (_) {
    return null;
  }
}

Map<String, dynamic>? _placemarkToMap(Placemark? placemark) {
  if (placemark == null) return null;
  return {
    'name': placemark.name,
    'street': placemark.street,
    'isoCountryCode': placemark.isoCountryCode,
    'country': placemark.country,
    'postalCode': placemark.postalCode,
    'administrativeArea': placemark.administrativeArea,
    'subAdministrativeArea': placemark.subAdministrativeArea,
    'locality': placemark.locality,
    'subLocality': placemark.subLocality,
    'thoroughfare': placemark.thoroughfare,
    'subThoroughfare': placemark.subThoroughfare,
  };
}

Placemark? _placemarkFromMap(dynamic raw) {
  if (raw is! Map) return null;
  final data = Map<String, dynamic>.from(raw);
  return Placemark(
    name: data['name']?.toString(),
    street: data['street']?.toString(),
    isoCountryCode: data['isoCountryCode']?.toString(),
    country: data['country']?.toString(),
    postalCode: data['postalCode']?.toString(),
    administrativeArea: data['administrativeArea']?.toString(),
    subAdministrativeArea: data['subAdministrativeArea']?.toString(),
    locality: data['locality']?.toString(),
    subLocality: data['subLocality']?.toString(),
    thoroughfare: data['thoroughfare']?.toString(),
    subThoroughfare: data['subThoroughfare']?.toString(),
  );
}

class _GeoPhotoCanvas extends StatelessWidget {
  final String imagePath;
  final String name;
  final List<String> lines;
  final bool dense;

  const _GeoPhotoCanvas({
    required this.imagePath,
    required this.name,
    required this.lines,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(File(imagePath), fit: BoxFit.cover),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.08),
                Colors.black.withValues(alpha: 0.28),
              ],
            ),
          ),
        ),
        Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: dense ? 18 : 26),
            child: _OverlayTextBlock(title: name, lines: lines, dense: dense),
          ),
        ),
      ],
    );
  }
}

class _OverlayTextBlock extends StatelessWidget {
  final String title;
  final List<String> lines;
  final bool dense;

  const _OverlayTextBlock({
    required this.title,
    required this.lines,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final fontSize = dense ? 16.0 : 22.0;
    final titleSize = dense ? 20.0 : 28.0;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title.isNotEmpty)
            Text(
              title,
              textAlign: TextAlign.center,
              style: _overlayStyle(
                fontSize: titleSize,
                weight: FontWeight.w700,
              ),
            ),
          if (title.isNotEmpty) SizedBox(height: dense ? 8 : 12),
          for (final line in lines) ...[
            Text(
              line,
              textAlign: TextAlign.center,
              style: _overlayStyle(fontSize: fontSize),
            ),
            SizedBox(height: dense ? 4 : 8),
          ],
        ],
      ),
    );
  }
}

class _TopIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _TopIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Ink(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.42),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatNumber(double? value) {
  if (value == null) return '—';
  return value.toStringAsFixed(6);
}

String _formatUtmCoordinate(
  double latitude,
  double longitude,
  ReferenceEllipsoid ellipsoid,
) {
  final utm = UtmConverter.fromLatLng(latitude, longitude, ellipsoid);
  if (utm == null) {
    return 'UTM unavailable for this latitude';
  }
  return utm.toDisplayString();
}

List<String> _buildOverlayLines({
  required _GeoTaggedPhoto capture,
  required CoordinateFormat coordinateFormat,
  required ReferenceEllipsoid referenceEllipsoid,
  required DistanceUnit unit,
  bool includeLocationNote = true,
}) {
  final position = capture.position;
  final placemark = capture.placemark;
  final utmText = position == null
      ? null
      : _formatUtmCoordinate(
          position.latitude,
          position.longitude,
          referenceEllipsoid,
        );

  final lines = <String>[
    if (position != null)
      '${_formatLatitudeLabel(position.latitude, coordinateFormat)} LAT',
    if (position != null)
      '${_formatLongitudeLabel(position.longitude, coordinateFormat)} LON',
    if (utmText != null) ...[utmText],
    'Ellipsoid ${referenceEllipsoid.displayName}',
    if (position != null)
      'Altitude ${_formatDistance(position.altitude, unit)} a.s.l',
    _formatCaptureDateTime(capture.capturedAt),
    'Location provider ${_providerLabel()}',
    if ((placemark?.street ?? '').trim().isNotEmpty) placemark!.street!.trim(),
    if ((placemark?.subLocality ?? '').trim().isNotEmpty)
      placemark!.subLocality!.trim(),
    if ((placemark?.locality ?? '').trim().isNotEmpty)
      placemark!.locality!.trim(),
    if ((placemark?.administrativeArea ?? '').trim().isNotEmpty)
      placemark!.administrativeArea!.trim(),
    if ((placemark?.country ?? '').trim().isNotEmpty)
      placemark!.country!.trim(),
  ];

  if (includeLocationNote && capture.locationError != null) {
    lines.add(capture.locationError!);
  }

  if (lines.isEmpty) {
    return const ['Waiting for GPS details'];
  }
  return lines;
}

String _formatLatitudeLabel(double value, CoordinateFormat format) {
  switch (format) {
    case CoordinateFormat.decimalDegrees:
      return value.toStringAsFixed(6);
    case CoordinateFormat.degreesMinutesSeconds:
      return _toDms(value, value >= 0 ? 'N' : 'S');
    case CoordinateFormat.degreesDecimalMinutes:
      return _toDdm(value, value >= 0 ? 'N' : 'S');
  }
}

String _formatLongitudeLabel(double value, CoordinateFormat format) {
  switch (format) {
    case CoordinateFormat.decimalDegrees:
      return value.toStringAsFixed(6);
    case CoordinateFormat.degreesMinutesSeconds:
      return _toDms(value, value >= 0 ? 'E' : 'W');
    case CoordinateFormat.degreesDecimalMinutes:
      return _toDdm(value, value >= 0 ? 'E' : 'W');
  }
}

String _toDms(double decimal, String direction) {
  final absolute = decimal.abs();
  final degrees = absolute.floor();
  final minutesDecimal = (absolute - degrees) * 60;
  final minutes = minutesDecimal.floor();
  final seconds = (minutesDecimal - minutes) * 60;
  return '$degrees°$minutes\'${seconds.toStringAsFixed(2)}"$direction';
}

String _toDdm(double decimal, String direction) {
  final absolute = decimal.abs();
  final degrees = absolute.floor();
  final minutes = (absolute - degrees) * 60;
  return '$degrees°${minutes.toStringAsFixed(4)}\'$direction';
}

String _formatDistance(double meters, DistanceUnit unit) {
  if (unit == DistanceUnit.feet) {
    final feet = meters * 3.28084;
    return '${feet.toStringAsFixed(1)} ft';
  }
  return '${meters.toStringAsFixed(1)} m';
}

String _formatCaptureDateTime(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  final year = value.year.toString();
  final hh = value.hour.toString().padLeft(2, '0');
  final mm = value.minute.toString().padLeft(2, '0');
  return '$day/$month/$year $hh:$mm';
}

String _providerLabel() {
  if (Platform.isAndroid) return 'Fused';
  if (Platform.isIOS) return 'Core Location';
  return 'Device GPS';
}

TextStyle _overlayStyle({
  required double fontSize,
  FontWeight weight = FontWeight.w600,
}) {
  return TextStyle(
    color: Colors.white,
    fontSize: fontSize,
    fontWeight: weight,
    height: 1.22,
    shadows: const [
      Shadow(color: Colors.black87, blurRadius: 8, offset: Offset(0, 2)),
    ],
  );
}

String _formatPlacemark(Placemark? placemark) {
  if (placemark == null) return 'Address unavailable';

  final values = <String>[
    placemark.street ?? '',
    placemark.subLocality ?? '',
    placemark.locality ?? '',
    placemark.administrativeArea ?? '',
    placemark.postalCode ?? '',
    placemark.country ?? '',
  ].where((value) => value.trim().isNotEmpty).toSet().toList();

  if (values.isEmpty) return 'Address unavailable';
  return values.join(', ');
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
