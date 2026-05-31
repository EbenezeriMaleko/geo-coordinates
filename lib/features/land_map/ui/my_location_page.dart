import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../../auth/providers/auth_provider.dart';
import '../../auth/services/auth_service.dart';
import '../models/coordinate_format.dart';
import '../models/location_media_models.dart';
import '../models/reference_ellipsoid.dart';
import '../services/location_media_service.dart';
import '../services/utm_converter.dart';
import '../state/land_map_notifier.dart';
import '../state/settings_provider.dart';
import 'location_media_page.dart';
import 'package:video_player/video_player.dart';
import 'package:permission_handler/permission_handler.dart' hide ServiceStatus;

enum MyLocationAction { savePoint, copyBoth, share }

// ─────────────────────────────────────────────────────────
// Persistent Location-Required Dialog
// ─────────────────────────────────────────────────────────

enum _LocationBlockReason { serviceOff, permissionDenied, permissionForever }

class _LocationRequiredDialog extends StatefulWidget {
  final _LocationBlockReason reason;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;

  const _LocationRequiredDialog({
    required this.reason,
    required this.onRetry,
    required this.onOpenSettings,
  });

  @override
  State<_LocationRequiredDialog> createState() =>
      _LocationRequiredDialogState();
}

class _LocationRequiredDialogState extends State<_LocationRequiredDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _scale = CurvedAnimation(parent: _anim, curve: Curves.easeOutBack);
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeIn);
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    final bool isForever =
        widget.reason == _LocationBlockReason.permissionForever;
    final bool isService = widget.reason == _LocationBlockReason.serviceOff;

    final String headline = isService
        ? 'Location is turned off'
        : isForever
        ? 'Location access blocked'
        : 'Location permission needed';

    final String body = isService
        ? 'TaREF GPS needs your device location to show coordinates, track position and tag media. Please turn on location services to continue.'
        : isForever
        ? 'Location permission has been permanently denied. Open app settings and allow location access so TaREF GPS can function.'
        : 'Location permission is required to track your GPS position. Please grant permission to continue using this page.';

    final String primaryLabel = isService || isForever
        ? 'Open Settings'
        : 'Grant Permission';

    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon badge
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isService
                        ? Icons.location_off_rounded
                        : Icons.location_disabled_rounded,
                    size: 36,
                    color: primary,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  headline,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.black54,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),
                // Primary action
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isService || isForever
                        ? widget.onOpenSettings
                        : widget.onRetry,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      primaryLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                if (!isForever) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        foregroundColor: Colors.black54,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Dismiss',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// MyLocationPage
// ─────────────────────────────────────────────────────────

class MyLocationPage extends ConsumerStatefulWidget {
  final Future<void> Function()? onRefresh;
  final Future<void> Function(MyLocationAction action)? onMenuAction;
  const MyLocationPage({super.key, this.onRefresh, this.onMenuAction});

  @override
  ConsumerState<MyLocationPage> createState() => _MyLocationPageState();
}

class _MyLocationPageState extends ConsumerState<MyLocationPage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  static const String _latestPhotoKey = 'my_location_latest_photo';
  static const String _recentMediaKey = 'my_location_recent_media';
  static const String _photosDirName = 'geo_photos';
  static const String _galleryAlbumName = 'TaREF GPS - Coordinates';

  StreamSubscription<Position>? _locationSubscription;
  StreamSubscription<ServiceStatus>? _serviceStatusSubscription;
  late final LandMapNotifier _landMapNotifier;

  bool _isInitializing = false;
  bool _isStreaming = false;

  // Instead of showing inline states, we drive a persistent dialog
  _LocationBlockReason? _blockReason;
  bool _blockDialogVisible = false;

  String? _errorMessage;
  bool _isCapturingPhoto = false;
  _GeoTaggedPhoto? _latestPhoto;
  List<_GeoTaggedPhoto> _recentMedia = <_GeoTaggedPhoto>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _landMapNotifier = ref.read(landMapProvider.notifier);
    Future.microtask(() async {
      await _restoreRecentMedia();
      await _startServiceStatusListener();
      await _initializeTracking();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationSubscription?.cancel();
    _serviceStatusSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      Future.microtask(_syncLocationAvailability);
    }
  }

  // ── Tracking setup ──────────────────────────────────────

  Future<void> _initializeTracking() async {
    if (!mounted) return;
    setState(() {
      _isInitializing = true;
      _isStreaming = false;
      _errorMessage = null;
    });

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      await _handleLocationServiceDisabled(isInitializing: false);
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (!mounted) return;

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _isInitializing = false;
        _blockReason = _LocationBlockReason.permissionForever;
      });
      _showBlockDialog();
      return;
    }

    if (permission == LocationPermission.denied) {
      setState(() {
        _isInitializing = false;
        _blockReason = _LocationBlockReason.permissionDenied;
      });
      _showBlockDialog();
      return;
    }

    // All clear — clear any previous block and start streaming
    _blockReason = null;
    _dismissBlockDialog();

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
          locationSettings: AndroidSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 1,
            intervalDuration: const Duration(seconds: 2),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'TaREF GPS - Coordinates',
              notificationText: 'Location tracking is active',
              enableWakeLock: true,
              notificationIcon: AndroidResource(
                name: 'ic_launcher',
                defType: 'mipmap',
              ),
            ),
          ),
        ).listen(
          (position) {
            _landMapNotifier.updateCurrentFromPosition(position);
            if (!mounted) return;
            if (_errorMessage != null || _blockReason != null) {
              setState(() {
                _errorMessage = null;
                _blockReason = null;
              });
              _dismissBlockDialog();
            }
          },
          onError: (_) async {
            if (!mounted) return;
            final serviceEnabled = await Geolocator.isLocationServiceEnabled();
            if (!mounted) return;
            if (!serviceEnabled) {
              await _handleLocationServiceDisabled();
            } else {
              setState(() {
                _errorMessage = 'Failed to read live location.';
                _isStreaming = false;
              });
            }
          },
        );
  }

  Future<void> _startServiceStatusListener() async {
    await _serviceStatusSubscription?.cancel();
    _serviceStatusSubscription = Geolocator.getServiceStatusStream().listen(
      (status) async {
        if (!mounted) return;

        if (status == ServiceStatus.disabled) {
          await _handleLocationServiceDisabled();
          return;
        }
        // Service just turned on — re-init quietly
        if (!_isInitializing) {
          _initializeTracking();
        }
      },
      onError: (_) {
        if (!mounted) return;
        Future.microtask(_syncLocationAvailability);
      },
    );
  }

  Future<void> _syncLocationAvailability() async {
    if (!mounted || _isInitializing) return;

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!mounted) return;

    if (!serviceEnabled) {
      await _handleLocationServiceDisabled();
      return;
    }

    if (_blockReason == _LocationBlockReason.serviceOff) {
      await _initializeTracking();
    }
  }

  Future<void> _handleLocationServiceDisabled({
    bool isInitializing = false,
  }) async {
    await _locationSubscription?.cancel();
    _locationSubscription = null;
    if (!mounted) return;

    setState(() {
      _isInitializing = isInitializing;
      _isStreaming = false;
      _errorMessage = null;
      _blockReason = _LocationBlockReason.serviceOff;
    });
    _showBlockDialog();
  }

  // ── Block dialog management ─────────────────────────────

  void _showBlockDialog() {
    if (!mounted || _blockDialogVisible || _blockReason == null) return;
    _blockDialogVisible = true;

    showDialog<void>(
      context: context,
      barrierDismissible:
          _blockReason != _LocationBlockReason.permissionForever,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => _LocationRequiredDialog(
        reason: _blockReason!,
        onRetry: () {
          Navigator.of(ctx).pop();
          Future.microtask(_initializeTracking);
        },
        onOpenSettings: () async {
          Navigator.of(ctx).pop();
          if (_blockReason == _LocationBlockReason.serviceOff) {
            await Geolocator.openLocationSettings();
          } else {
            await Geolocator.openAppSettings();
          }
          // After returning from settings, retry init
          if (mounted) Future.microtask(_initializeTracking);
        },
      ),
    ).then((_) {
      _blockDialogVisible = false;
      // If user dismissed without fixing → re-show after short delay
      if (mounted && _blockReason != null) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && _blockReason != null) {
            _showBlockDialog();
          }
        });
      }
    });
  }

  void _dismissBlockDialog() {
    if (_blockDialogVisible && mounted) {
      // Close the topmost dialog if it's our block dialog
      final nav = Navigator.of(context, rootNavigator: true);
      if (nav.canPop()) nav.pop();
      _blockDialogVisible = false;
    }
  }

  Future<void> _openCompassPage() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const _CompassPage()));
  }

  // ── Camera ──────────────────────────────────────────────

  Future<void> _openGeoCamera() async {
    if (_isCapturingPhoto) return;
    setState(() => _isCapturingPhoto = true);

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
      await _syncCapturedMediaToServer(persistedCapture);
      final saveToGallery = ref.read(saveToGalleryProvider);
      if (saveToGallery) await _saveMediaToGallery(persistedCapture);

      setState(() => _latestPhoto = persistedCapture);
      await _saveRecentMedia(persistedCapture);
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
      if (mounted) setState(() => _isCapturingPhoto = false);
    }
  }

  // ── Persistence helpers ─────────────────────────────────

  Future<void> _restoreRecentMedia() async {
    final box = Hive.box('landbox');
    final rawRecent = box.get(_recentMediaKey);
    final restoredRecent = <_GeoTaggedPhoto>[];

    if (rawRecent is List) {
      for (final item in rawRecent.whereType<Map>()) {
        final restored = _GeoTaggedPhoto.fromMap(
          Map<String, dynamic>.from(item),
        );
        if (restored == null) continue;
        if (!await File(restored.imagePath).exists()) continue;
        restoredRecent.add(restored);
      }
    }

    if (restoredRecent.isEmpty) {
      final rawLatest = box.get(_latestPhotoKey);
      if (rawLatest is Map) {
        final restored = _GeoTaggedPhoto.fromMap(
          Map<String, dynamic>.from(rawLatest),
        );
        if (restored != null && await File(restored.imagePath).exists()) {
          restoredRecent.add(restored);
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _recentMedia = restoredRecent;
      _latestPhoto = restoredRecent.isNotEmpty ? restoredRecent.first : null;
    });
  }

  Future<void> _saveRecentMedia(_GeoTaggedPhoto capture) async {
    final next = <_GeoTaggedPhoto>[
      capture,
      ..._recentMedia.where((item) => item.imagePath != capture.imagePath),
    ].take(8).toList();

    final box = Hive.box('landbox');
    await box.put(_latestPhotoKey, capture.toMap());
    await box.put(_recentMediaKey, next.map((item) => item.toMap()).toList());

    if (!mounted) return;
    setState(() => _recentMedia = next);
  }

  Future<void> _syncCapturedMediaToServer(_GeoTaggedPhoto capture) async {
    final session = ref.read(authSessionProvider);
    if (!session.isLoggedIn || !session.isVerified) return;

    final locationService = LocationMediaService();
    try {
      _debugLog(
        'Uploading media: type=${capture.mediaType}, path=${capture.imagePath}',
      );
      final file = File(capture.imagePath);
      if (await file.exists()) {
        _debugLog('Upload file size: ${await file.length()} bytes');
      } else {
        _debugLog('Upload file missing on disk.');
      }

      final location = await locationService.createLocation(
        session.token,
        CreateLocationRequest(
          name: capture.name.trim().isEmpty
              ? 'GPS Capture'
              : capture.name.trim(),
          description: _formatPlacemark(capture.placemark),
          latitude: capture.position?.latitude,
          longitude: capture.position?.longitude,
        ),
      );

      final mediaTypeName = capture.mediaType == 'video' ? 'Video' : 'Photo';
      await locationService.uploadLocationMedia(
        session.token,
        location.id,
        capture.imagePath,
        capture.mediaType,
      );
      _debugLog('Upload finished. Location id=${location.id}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$mediaTypeName uploaded to cloud')),
      );
    } on AuthException catch (error) {
      _debugLog('Upload auth error: ${error.message}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved locally: ${error.message}')),
      );
    } catch (e) {
      _debugLog('Upload failed: $e');
      if (!mounted) return;
      final mediaTypeName = capture.mediaType == 'video' ? 'Video' : 'Photo';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$mediaTypeName saved locally. Cloud upload failed.'),
        ),
      );
    }
  }

  Future<_GeoTaggedPhoto> _persistCapturedPhoto(_GeoTaggedPhoto capture) async {
    final photosDir = await _getPhotosDirectory();
    final source = File(capture.imagePath);
    var storedPath = capture.imagePath;

    if (await source.exists()) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final keepOriginal = ref.read(saveOriginalPhotoProvider);
      final ext = capture.mediaType == 'video'
          ? _fileExtension(capture.imagePath)
          : '.png';
      final safeName = _safeFileName(capture.name);
      final fileName = safeName.isEmpty
          ? 'gps_$timestamp$ext'
          : '${safeName}_$timestamp$ext';
      final destination = File('${photosDir.path}/$fileName');
      final copied = capture.mediaType == 'video'
          ? await _copyVideoWithLocationOverlay(
              source: source,
              destination: destination,
              capture: capture,
            )
          : keepOriginal
          ? await source.copy(destination.path)
          : await _copyImageWithLocationOverlay(
              source: source,
              destination: destination,
              capture: capture,
            );
      storedPath = copied.path;
      if (source.path != copied.path) {
        try {
          await source.delete();
        } catch (_) {}
      }
    }

    final persisted = capture.copyWith(imagePath: storedPath);
    final box = Hive.box('landbox');
    await box.put(_latestPhotoKey, persisted.toMap());
    return persisted;
  }

  Future<void> _saveMediaToGallery(_GeoTaggedPhoto capture) async {
    try {
      final saved = capture.mediaType == 'video'
          ? await GallerySaver.saveVideo(
              capture.imagePath,
              albumName: _galleryAlbumName,
            )
          : await GallerySaver.saveImage(
              capture.imagePath,
              albumName: _galleryAlbumName,
            );
      if (!mounted) return;
      if (saved == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              capture.mediaType == 'video'
                  ? 'Video saved to gallery'
                  : 'Photo saved to gallery',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not save media to gallery. Check permissions.',
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save media to gallery. Check permissions.'),
        ),
      );
    }
  }

  Future<File> _copyImageWithLocationOverlay({
    required File source,
    required File destination,
    required _GeoTaggedPhoto capture,
  }) async {
    try {
      final bytes = await source.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final size = Size(image.width.toDouble(), image.height.toDouble());
      canvas.drawImage(image, Offset.zero, Paint());
      _paintPersistedLocationOverlay(
        canvas: canvas,
        size: size,
        capture: capture,
      );
      final picture = recorder.endRecording();
      final rendered = await picture.toImage(image.width, image.height);
      final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      rendered.dispose();
      picture.dispose();
      if (data == null) return source.copy(destination.path);
      await destination.writeAsBytes(data.buffer.asUint8List(), flush: true);
      return destination;
    } catch (_) {
      return source.copy(destination.path);
    }
  }

  Future<File> _copyVideoWithLocationOverlay({
    required File source,
    required File destination,
    required _GeoTaggedPhoto capture,
  }) async {
    File? overlayCard;
    final tempOutput = File('${destination.path}.processing.mp4');
    try {
      overlayCard = await _createVideoOverlayCard(capture: capture);
      if (overlayCard == null || !await overlayCard.exists()) {
        _debugLog('Video overlay card missing. Using original video.');
        return source.copy(destination.path);
      }
      final command =
          '-y '
          '-i ${_ffmpegQuotePath(source.path)} '
          '-i ${_ffmpegQuotePath(overlayCard.path)} '
          '-filter_complex '
          '"[1:v]scale=350:-1[overlay];'
          '[0:v][overlay]overlay=x=W-w-34:y=H-h-34" '
          '-map 0:v:0 '
          '-map 0:a? '
          '-c:v mpeg4 '
          '-b:v 2500k '
          '-pix_fmt yuv420p '
          '-c:a aac '
          '${_ffmpegQuotePath(tempOutput.path)}';
      final session = await FFmpegKit.execute(command);
      final rc = await session.getReturnCode();
      _debugLog('FFmpeg return code: ${rc?.getValue()}');
      if (ReturnCode.isSuccess(rc) && await tempOutput.exists()) {
        if (await destination.exists()) await destination.delete();
        return tempOutput.rename(destination.path);
      }
    } catch (_) {
    } finally {
      try {
        if (overlayCard != null && await overlayCard.exists()) {
          await overlayCard.delete();
        }
      } catch (_) {}
      try {
        if (await tempOutput.exists()) await tempOutput.delete();
      } catch (_) {}
    }
    return source.copy(destination.path);
  }

  Future<File?> _createVideoOverlayCard({
    required _GeoTaggedPhoto capture,
  }) async {
    try {
      final format = ref.read(coordinateFormatProvider);
      final ellipsoid = ref.read(referenceEllipsoidProvider);
      final unit = ref.read(distanceUnitProvider);
      final lines = _buildOverlayLines(
        capture: capture,
        coordinateFormat: format,
        referenceEllipsoid: ellipsoid,
        unit: unit,
        includeLocationNote: false,
      );
      final title = capture.name.trim();
      const maxWidth = 620.0;
      const padding = 32.0;
      const spacing = 8.0;
      final painters = <TextPainter>[];
      if (title.isNotEmpty) {
        painters.add(
          _overlayPainter(
            title,
            fontSize: 26,
            weight: FontWeight.w800,
            maxWidth: maxWidth,
          ),
        );
      }
      for (final line in lines) {
        painters.add(
          _overlayPainter(
            line,
            fontSize: 20,
            weight: FontWeight.w700,
            maxWidth: maxWidth,
          ),
        );
      }
      if (painters.isEmpty) return null;
      final textHeight =
          painters.fold<double>(0, (sum, p) => sum + p.height) +
          spacing * (painters.length - 1);
      final textWidth = painters.fold<double>(
        0,
        (maxLine, p) => max(maxLine, p.width),
      );
      final cardWidth = textWidth + padding * 1.8;
      final cardHeight = textHeight + padding * 1.4;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final size = Size(cardWidth, cardHeight);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(22)),
        Paint()..color = Colors.black.withValues(alpha: 0.42),
      );
      var y = padding * 0.7;
      for (final painter in painters) {
        painter.paint(canvas, Offset(cardWidth - padding - painter.width, y));
        y += painter.height + spacing;
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(cardWidth.ceil(), cardHeight.ceil());
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      picture.dispose();
      image.dispose();
      if (data == null) return null;
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/geo_overlay_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      return file;
    } catch (_) {
      return null;
    }
  }

  String _ffmpegQuotePath(String path) =>
      '\'${path.replaceAll('\'', '\'\\\\\'\'')}\'';

  void _debugLog(String message) {
    if (!kDebugMode) return;
    debugPrint('[MyLocationPage] $message');
  }

  void _paintPersistedLocationOverlay({
    required Canvas canvas,
    required Size size,
    required _GeoTaggedPhoto capture,
  }) {
    final format = ref.read(coordinateFormatProvider);
    final ellipsoid = ref.read(referenceEllipsoidProvider);
    final unit = ref.read(distanceUnitProvider);
    final lines = _buildOverlayLines(
      capture: capture,
      coordinateFormat: format,
      referenceEllipsoid: ellipsoid,
      unit: unit,
    );
    final textScale = (size.shortestSide / 900).clamp(1.0, 2.4);
    final padding = 34.0 * textScale;
    final maxWidth = min(size.width * 0.72, 520.0 * textScale);
    final titleSize = 22.0 * textScale;
    final lineSize = 17.0 * textScale;
    final spacing = 8.0 * textScale;
    final painters = <TextPainter>[];
    if (capture.name.trim().isNotEmpty) {
      painters.add(
        _overlayPainter(
          capture.name.trim(),
          fontSize: titleSize,
          weight: FontWeight.w800,
          maxWidth: maxWidth,
        ),
      );
    }
    for (final line in lines) {
      painters.add(
        _overlayPainter(
          line,
          fontSize: lineSize,
          weight: FontWeight.w700,
          maxWidth: maxWidth,
        ),
      );
    }
    if (painters.isEmpty) return;
    final blockHeight =
        painters.fold<double>(0, (sum, p) => sum + p.height) +
        spacing * (painters.length - 1);
    final blockWidth = painters.fold<double>(
      0,
      (maxW, p) => max(maxW, p.width),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width - blockWidth - padding * 1.45,
          size.height - blockHeight - padding * 1.35,
          blockWidth + padding * 0.8,
          blockHeight + padding * 0.7,
        ),
        Radius.circular(18 * textScale),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.34),
    );
    var y = size.height - padding - blockHeight;
    for (final painter in painters) {
      painter.paint(canvas, Offset(size.width - padding - painter.width, y));
      y += painter.height + spacing;
    }
  }

  TextPainter _overlayPainter(
    String text, {
    required double fontSize,
    required FontWeight weight,
    required double maxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: weight,
          height: 1.22,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.86),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
      textAlign: TextAlign.right,
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '...',
    )..layout(maxWidth: maxWidth);
    return painter;
  }

  Future<Directory> _getPhotosDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory('${appDir.path}/$_photosDirName');
    if (!await photosDir.exists()) await photosDir.create(recursive: true);
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

  // ── Build ────────────────────────────────────────────────

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final st = ref.watch(landMapProvider);
    final ellipsoid = ref.watch(referenceEllipsoidProvider);
    final unit = ref.watch(distanceUnitProvider);
    final coordinateFormat = ref.watch(coordinateFormatProvider);

    final lat = st.current?.latitude;
    final lon = st.current?.longitude;
    final coordinateText = lat != null && lon != null
        ? CoordinateFormatter.format(lat, lon, coordinateFormat)
        : '--';

    final utmData = (lat != null && lon != null)
        ? UtmConverter.fromLatLng(lat, lon, ellipsoid)
        : null;
    final eastingText = utmData != null
        ? utmData.easting.toStringAsFixed(1)
        : '—';
    final northingText = utmData != null
        ? utmData.northing.toStringAsFixed(1)
        : '—';
    final utmZoneText = utmData != null
        ? '${utmData.zoneNumber}${utmData.zoneLetter}'
        : '--';

    final altitudeText = _formatDistanceValue(st.altitudeMeters, unit);
    final quality = _qualityFromAccuracy(st.accuracyMeters);
    final qualityColor = _qualityColor(quality);
    final lastUpdateText = _formatLastUpdated(st.locationTimestamp);
    final accuracyText = _formatDistanceValue(st.accuracyMeters, unit);
    final ageText = _formatAge(st.locationTimestamp);

    final bool isLive = _isStreaming && _blockReason == null;
    final Color headerColor = theme.colorScheme.primary;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Container(
        color: const Color(0xFFF5F7FA),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header card ──────────────────────────────
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(
                    24,
                    20 + MediaQuery.of(context).padding.top,
                    24,
                    44,
                  ),
                  decoration: BoxDecoration(
                    color: headerColor,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(32),
                      bottomRight: Radius.circular(32),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Top row: refresh + title + menu
                      Row(
                        children: [
                          _HeaderCompassButton(onTap: _openCompassPage),
                          const Spacer(),
                          Text(
                            'My Location',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const Spacer(),
                          if (widget.onMenuAction != null)
                            PopupMenuButton<MyLocationAction>(
                              icon: const Icon(
                                Icons.more_vert_rounded,
                                color: Colors.white,
                              ),
                              color: Colors.white,
                              onSelected: (action) =>
                                  widget.onMenuAction!(action),
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: MyLocationAction.copyBoth,
                                  child: Text('Copy coordinates'),
                                ),
                                PopupMenuItem(
                                  value: MyLocationAction.share,
                                  child: Text('Share location'),
                                ),
                                PopupMenuItem(
                                  value: MyLocationAction.savePoint,
                                  child: Text('Save location'),
                                ),
                              ],
                            )
                          else
                            const SizedBox(width: 40),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Status pill
                      _LiveStatusPill(
                        isLive: isLive,
                        isLoading: _isInitializing,
                      ),
                      const SizedBox(height: 24),

                      // UTM coordinates — hero numbers
                      _CoordDisplay(
                        label: 'EASTING',
                        value: eastingText,
                        theme: theme,
                      ),
                      const SizedBox(height: 18),
                      _CoordDisplay(
                        label: 'NORTHING',
                        value: northingText,
                        theme: theme,
                      ),
                      const SizedBox(height: 18),

                      // Zone + selected coordinate format
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _SubInfoChip(label: 'Zone', value: utmZoneText),
                                _SubInfoDot(),
                                _SubInfoChip(
                                  label: 'Format',
                                  value: coordinateFormat.shortName,
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: Text(
                                coordinateText,
                                key: ValueKey(coordinateText),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Ellipsoid · ${ellipsoid.displayName}   ·   Updated $lastUpdateText',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white54,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                // FAB camera button
                Positioned(
                  right: 24,
                  bottom: -24,
                  child: _CameraFab(
                    isLoading: _isCapturingPhoto,
                    onTap: _isCapturingPhoto ? null : _openGeoCamera,
                    color: headerColor,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 40),

            // ── Stats grid ───────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _StatsGrid(
                altitude: altitudeText,
                accuracy: accuracyText,
                quality: quality,
                qualityColor: qualityColor,
                age: ageText,
                isStreaming: _isStreaming,
              ),
            ),

            const SizedBox(height: 16),

            // ── Recent media ─────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _RecentMediaStrip(
                media: _recentMedia,
                isLoggedIn: ref.watch(authSessionProvider).isLoggedIn,
                onViewMore: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LocationMediaPage(),
                  ),
                ),
                onOpenItem: _showCaptureDetails,
                onCapture: _openGeoCamera,
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Formatters ──────────────────────────────────────────

  String _formatAge(DateTime? timestamp) {
    if (timestamp == null) return '—';
    final diff = DateTime.now().difference(timestamp);
    if (diff.inSeconds < 0) return '—';
    final h = diff.inHours.toString().padLeft(2, '0');
    final m = diff.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = diff.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatLastUpdated(DateTime? ts) {
    if (ts == null) return '—';
    return '${ts.hour.toString().padLeft(2, '0')}:'
        '${ts.minute.toString().padLeft(2, '0')}:'
        '${ts.second.toString().padLeft(2, '0')}';
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
      return '${(meters * 3.28084).toStringAsFixed(1)} ft';
    }
    return '${meters.toStringAsFixed(1)} m';
  }
}

// ─────────────────────────────────────────────────────────
// Small header UI helpers
// ─────────────────────────────────────────────────────────

class _HeaderCompassButton extends StatelessWidget {
  final Future<void> Function() onTap;

  const _HeaderCompassButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CompassEvent>(
      stream: FlutterCompass.events,
      builder: (context, snapshot) {
        final heading = snapshot.data?.heading;
        final hasHeading = heading != null;

        return GestureDetector(
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: hasHeading ? 0.35 : 0.18),
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.rotate(
                  angle: hasHeading ? -(heading * pi / 180) : 0,
                  child: const Icon(
                    Icons.explore_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: hasHeading
                          ? const Color(0xFF3EE58F)
                          : Colors.white.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CompassPage extends StatefulWidget {
  const _CompassPage();

  @override
  State<_CompassPage> createState() => _CompassPageState();
}

class _CompassPageState extends State<_CompassPage> {
  StreamSubscription<CompassEvent>? _compassSubscription;
  double? _heading;
  double? _accuracy;
  bool _hasPermission = false;
  bool _checkingPermission = true;

  @override
  void initState() {
    super.initState();
    _checkPermissionAndStart();
  }

  Future<void> _checkPermissionAndStart() async {
    debugPrint('[Compass] checking permission...');

    if (Platform.isAndroid) {
      var status = await Permission.locationWhenInUse.status;
      debugPrint('[Compass] initial status: $status');

      if (!status.isGranted) {
        debugPrint('[Compass] requesting permission...');
        status = await Permission.locationWhenInUse.request();
        debugPrint('[Compass] after request status: $status');
        if (!mounted) return;
        if (!status.isGranted) {
          debugPrint('[Compass] permission denied — cannot start compass');
          setState(() {
            _hasPermission = false;
            _checkingPermission = false;
          });
          return;
        }
      }
    }

    debugPrint('[Compass] permission OK — starting listener');
    if (!mounted) return;
    setState(() {
      _hasPermission = true;
      _checkingPermission = false;
    });
    _startListening();
  }

  void _startListening() {
    _compassSubscription?.cancel();
    final stream = FlutterCompass.events;
    // debugPrint('[Compass] stream is null: ${stream == null}');

    _compassSubscription = stream?.listen(
      (event) {
        // debugPrint(
        //   '[Compass] heading: ${event.heading}, accuracy: ${event.accuracy}',
        // );
        if (!mounted) return;
        final h = event.heading;
        if (h == null) return;
        setState(() {
          _heading = h;
          _accuracy = event.accuracy;
        });
      },
      // onError: (error) {
      //   debugPrint('[Compass] stream error: $error');
      // },
      // onDone: () {
      //   debugPrint('[Compass] stream closed/done');
      // },
    );

    if (_compassSubscription == null) {
      debugPrint(
        '[Compass] subscription is null — sensor unavailable on this device',
      );
    } else {
      debugPrint('[Compass] subscription started successfully');
    }
  }

  @override
  void dispose() {
    _compassSubscription?.cancel();
    super.dispose();
  }

  String get _headingText {
    final heading = _heading;
    if (heading == null) return '--';
    return '${heading.toStringAsFixed(0)}°';
  }

  String get _directionText {
    final heading = _heading;
    if (heading == null) return 'Unavailable';
    const labels = [
      'North',
      'North East',
      'East',
      'South East',
      'South',
      'South West',
      'West',
      'North West',
    ];
    final index = ((heading + 22.5) / 45).floor() % labels.length;
    return labels[index];
  }

  String get _shortDirectionText {
    final heading = _heading;
    if (heading == null) return '--';
    const labels = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final index = ((heading + 22.5) / 45).floor() % labels.length;
    return labels[index];
  }

  String get _accuracyText {
    final accuracy = _accuracy;
    if (accuracy == null) return '--';
    return '±${accuracy.toStringAsFixed(0)}°';
  }

  String get _accuracyQualityText {
    final accuracy = _accuracy;
    if (accuracy == null) return 'Not reported';
    if (accuracy <= 10) return 'High';
    if (accuracy <= 25) return 'Moderate';
    return 'Low';
  }

  Color _accuracyColor(Color primary) {
    final accuracy = _accuracy;
    if (accuracy == null) return const Color(0xFF667085);
    if (accuracy <= 10) return const Color(0xFF14804A);
    if (accuracy <= 25) return const Color(0xFFB54708);
    return const Color(0xFFB42318);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final heading = _heading;
    final headingRadians = heading == null ? 0.0 : -(heading * pi / 180);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: const Color(0xFF18212F),
                  ),
                  const Spacer(),
                  Text(
                    'Compass',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF18212F),
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: _checkingPermission
                  ? const Center(child: CircularProgressIndicator())
                  : !_hasPermission
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.location_off_rounded,
                              size: 48,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Location permission is required for the compass sensor on Android.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton(
                              onPressed: () {
                                setState(() => _checkingPermission = true);
                                _checkPermissionAndStart();
                              },
                              child: const Text('Grant Permission'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final dialSize = min(constraints.maxWidth - 48, 360.0);
                        return SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                18,
                                20,
                                24,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: dialSize,
                                    height: dialSize,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.10,
                                          ),
                                          blurRadius: 30,
                                          offset: const Offset(0, 16),
                                        ),
                                      ],
                                    ),
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        CustomPaint(
                                          size: Size.square(dialSize),
                                          painter: _CompassDialPainter(
                                            primaryColor: primary,
                                          ),
                                        ),
                                        Transform.rotate(
                                          angle: headingRadians,
                                          child: CustomPaint(
                                            size: Size(
                                              dialSize * 0.30,
                                              dialSize * 0.68,
                                            ),
                                            painter: _CompassNeedlePainter(
                                              primaryColor: primary,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          width: dialSize * 0.19,
                                          height: dialSize * 0.19,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: primary.withValues(
                                                alpha: 0.16,
                                              ),
                                              width: 8,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(
                                                  alpha: 0.10,
                                                ),
                                                blurRadius: 14,
                                                offset: const Offset(0, 6),
                                              ),
                                            ],
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            _shortDirectionText,
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(
                                                  color: primary,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 26),
                                  Text(
                                    _headingText,
                                    style: theme.textTheme.displayMedium
                                        ?.copyWith(
                                          color: const Color(0xFF18212F),
                                          fontWeight: FontWeight.w900,
                                        ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _directionText,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      color: primary,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 14,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: Colors.black.withValues(
                                            alpha: 0.06,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 38,
                                            height: 38,
                                            decoration: BoxDecoration(
                                              color: _accuracyColor(
                                                primary,
                                              ).withValues(alpha: 0.10),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              Icons.adjust_rounded,
                                              color: _accuracyColor(primary),
                                              size: 21,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                'Compass accuracy',
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                      color: const Color(
                                                        0xFF667085,
                                                      ),
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                              ),
                                              const SizedBox(height: 2),
                                              RichText(
                                                text: TextSpan(
                                                  style: theme
                                                      .textTheme
                                                      .titleMedium
                                                      ?.copyWith(
                                                        color: const Color(
                                                          0xFF18212F,
                                                        ),
                                                        fontWeight:
                                                            FontWeight.w900,
                                                      ),
                                                  children: [
                                                    TextSpan(
                                                      text: _accuracyText,
                                                    ),
                                                    TextSpan(
                                                      text:
                                                          '  $_accuracyQualityText',
                                                      style: theme
                                                          .textTheme
                                                          .bodySmall
                                                          ?.copyWith(
                                                            color:
                                                                _accuracyColor(
                                                                  primary,
                                                                ),
                                                            fontWeight:
                                                                FontWeight.w800,
                                                          ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 22),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 16,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: Colors.black.withValues(
                                          alpha: 0.06,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          heading == null
                                              ? Icons.explore_off_rounded
                                              : Icons.explore_rounded,
                                          color: heading == null
                                              ? Colors.black45
                                              : primary,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            heading == null
                                                ? 'Compass sensor is not available on this device.'
                                                : 'Live compass is active.',
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  color: const Color(
                                                    0xFF344054,
                                                  ),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompassDialPainter extends CustomPainter {
  final Color primaryColor;

  const _CompassDialPainter({required this.primaryColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final tickPaint = Paint()
      ..color = const Color(0xFF18212F).withValues(alpha: 0.34)
      ..strokeCap = StrokeCap.round;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = const Color(0xFF18212F).withValues(alpha: 0.08);

    canvas.drawCircle(center, radius - 13, ringPaint);
    canvas.drawCircle(center, radius - 42, ringPaint);

    for (var i = 0; i < 60; i++) {
      final angle = (i * 6 - 90) * pi / 180;
      final isMajor = i % 5 == 0;
      final isCardinal = i % 15 == 0;
      final outer = radius - 18;
      final inner =
          radius -
          (isCardinal
              ? 40
              : isMajor
              ? 32
              : 25);
      tickPaint
        ..strokeWidth = isCardinal
            ? 3.0
            : isMajor
            ? 2.0
            : 1.0
        ..color = isCardinal
            ? primaryColor.withValues(alpha: 0.74)
            : const Color(0xFF18212F).withValues(alpha: isMajor ? 0.32 : 0.18);

      canvas.drawLine(
        Offset(center.dx + cos(angle) * inner, center.dy + sin(angle) * inner),
        Offset(center.dx + cos(angle) * outer, center.dy + sin(angle) * outer),
        tickPaint,
      );
    }

    _drawCompassLabel(canvas, center, radius, 'N', -90, primaryColor, 30, true);
    _drawCompassLabel(
      canvas,
      center,
      radius,
      'E',
      0,
      const Color(0xFF18212F),
      24,
      false,
    );
    _drawCompassLabel(
      canvas,
      center,
      radius,
      'S',
      90,
      const Color(0xFF18212F),
      24,
      false,
    );
    _drawCompassLabel(
      canvas,
      center,
      radius,
      'W',
      180,
      const Color(0xFF18212F),
      24,
      false,
    );
  }

  void _drawCompassLabel(
    Canvas canvas,
    Offset center,
    double radius,
    String text,
    double degrees,
    Color color,
    double fontSize,
    bool isPrimary,
  ) {
    final angle = degrees * pi / 180;
    final labelRadius = radius - 72;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: isPrimary ? FontWeight.w900 : FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    painter.paint(
      canvas,
      Offset(
        center.dx + cos(angle) * labelRadius - painter.width / 2,
        center.dy + sin(angle) * labelRadius - painter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _CompassDialPainter oldDelegate) {
    return oldDelegate.primaryColor != primaryColor;
  }
}

class _CompassNeedlePainter extends CustomPainter {
  final Color primaryColor;

  const _CompassNeedlePainter({required this.primaryColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final northPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = primaryColor;
    final southPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF98A2B3);

    final northPath = ui.Path()
      ..moveTo(center.dx, 0)
      ..lineTo(center.dx - size.width * 0.22, center.dy)
      ..lineTo(center.dx, center.dy - size.height * 0.08)
      ..lineTo(center.dx + size.width * 0.22, center.dy)
      ..close();
    canvas.drawPath(northPath, northPaint);

    final southPath = ui.Path()
      ..moveTo(center.dx, size.height)
      ..lineTo(center.dx - size.width * 0.18, center.dy)
      ..lineTo(center.dx, center.dy + size.height * 0.08)
      ..lineTo(center.dx + size.width * 0.18, center.dy)
      ..close();
    canvas.drawPath(southPath, southPaint);
  }

  @override
  bool shouldRepaint(covariant _CompassNeedlePainter oldDelegate) {
    return oldDelegate.primaryColor != primaryColor;
  }
}

class _LiveStatusPill extends StatelessWidget {
  final bool isLive;
  final bool isLoading;
  const _LiveStatusPill({required this.isLive, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    final label = isLoading
        ? 'Initializing GPS…'
        : isLive
        ? 'Live tracking'
        : 'Tracking paused';
    final color = isLive
        ? const Color(0xFF1B8F4B)
        : isLoading
        ? const Color(0xFF2A6FB3)
        : const Color(0xFFC65D12);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLive && !isLoading)
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(right: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF4ADE80),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4ADE80).withValues(alpha: 0.7),
                    blurRadius: 6,
                  ),
                ],
              ),
            )
          else if (isLoading)
            const SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: Colors.white,
              ),
            )
          else
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(right: 7),
              decoration: const BoxDecoration(
                color: Color(0xFFF97316),
                shape: BoxShape.circle,
              ),
            ),
          if (isLoading) const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _CoordDisplay extends StatelessWidget {
  final String label;
  final String value;
  final ThemeData theme;
  const _CoordDisplay({
    required this.label,
    required this.value,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: Colors.white54,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 4),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: Text(
            value,
            key: ValueKey(value),
            style: theme.textTheme.headlineLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              fontSize: 38,
            ),
          ),
        ),
      ],
    );
  }
}

class _SubInfoChip extends StatelessWidget {
  final String label;
  final String value;
  const _SubInfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _SubInfoDot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        width: 3,
        height: 3,
        decoration: const BoxDecoration(
          color: Colors.white24,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _CameraFab extends StatelessWidget {
  final bool isLoading;
  final VoidCallback? onTap;
  final Color color;
  const _CameraFab({
    required this.isLoading,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: isLoading
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(
                Icons.camera_alt_rounded,
                color: Colors.white,
                size: 24,
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Stats grid
// ─────────────────────────────────────────────────────────

class _StatsGrid extends StatelessWidget {
  final String altitude;
  final String accuracy;
  final String quality;
  final Color qualityColor;
  final String age;
  final bool isStreaming;

  const _StatsGrid({
    required this.altitude,
    required this.accuracy,
    required this.quality,
    required this.qualityColor,
    required this.age,
    required this.isStreaming,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.landscape_rounded,
                label: 'Altitude',
                value: altitude,
                iconColor: const Color(0xFF0284C7),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                icon: Icons.gps_fixed_rounded,
                label: 'Accuracy',
                value: accuracy,
                valueColor: qualityColor,
                iconColor: qualityColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.signal_cellular_alt_rounded,
                label: 'Signal',
                value: quality,
                valueColor: qualityColor,
                iconColor: qualityColor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                icon: Icons.schedule_rounded,
                label: 'Location age',
                value: age,
                iconColor: const Color(0xFF7C3AED),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _StatCard(
          icon: Icons.wifi_tethering_rounded,
          label: 'Tracking status',
          value: isStreaming ? 'Live' : 'Stopped',
          valueColor: isStreaming
              ? const Color(0xFF1B8F4B)
              : const Color(0xFFC94835),
          iconColor: isStreaming
              ? const Color(0xFF1B8F4B)
              : const Color(0xFFC94835),
          fullWidth: true,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final Color iconColor;
  final bool fullWidth;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.iconColor,
    this.valueColor,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: fullWidth ? double.infinity : null,
      padding: EdgeInsets.symmetric(
        horizontal: fullWidth ? 20 : 16,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.black45,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: valueColor ?? Colors.black87,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Data models (unchanged from original)
// ─────────────────────────────────────────────────────────

class _GeoTaggedPhoto {
  final String imagePath;
  final DateTime capturedAt;
  final Position? position;
  final Placemark? placemark;
  final String? locationError;
  final String name;
  final String mediaType;

  const _GeoTaggedPhoto({
    required this.imagePath,
    required this.capturedAt,
    required this.position,
    required this.placemark,
    required this.locationError,
    required this.name,
    this.mediaType = 'image',
  });

  _GeoTaggedPhoto copyWith({
    String? imagePath,
    DateTime? capturedAt,
    Position? position,
    Placemark? placemark,
    String? locationError,
    String? name,
    String? mediaType,
  }) {
    return _GeoTaggedPhoto(
      imagePath: imagePath ?? this.imagePath,
      capturedAt: capturedAt ?? this.capturedAt,
      position: position ?? this.position,
      placemark: placemark ?? this.placemark,
      locationError: locationError ?? this.locationError,
      name: name ?? this.name,
      mediaType: mediaType ?? this.mediaType,
    );
  }

  Map<String, dynamic> toMap() => {
    'imagePath': imagePath,
    'capturedAt': capturedAt.toIso8601String(),
    'position': _positionToMap(position),
    'placemark': _placemarkToMap(placemark),
    'locationError': locationError,
    'name': name,
    'mediaType': mediaType,
  };

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
      mediaType: raw['mediaType']?.toString().trim().isEmpty == true
          ? 'image'
          : raw['mediaType']?.toString() ?? 'image',
    );
  }
}

// ─────────────────────────────────────────────────────────
// Capture details sheet (unchanged logic, minor style tweaks)
// ─────────────────────────────────────────────────────────

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
    final title = capture.name.isEmpty ? 'GPS media details' : capture.name;
    final when =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
    final utmText = pos == null
        ? '—'
        : _formatUtmCoordinate(pos.latitude, pos.longitude, referenceEllipsoid);
    final accuracyText = pos == null
        ? '—'
        : '${pos.accuracy.toStringAsFixed(1)} m';
    final altitudeText = pos == null
        ? '—'
        : '${pos.altitude.toStringAsFixed(1)} m';
    final speedText = pos == null ? '—' : '${pos.speed.toStringAsFixed(2)} m/s';
    final headingText = pos == null
        ? '—'
        : '${pos.heading.toStringAsFixed(1)}°';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          when,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.black54,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    color: Colors.black54,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetaChip(
                    label: capture.mediaType == 'video' ? 'Video' : 'Photo',
                    icon: capture.mediaType == 'video'
                        ? Icons.videocam
                        : Icons.photo_camera,
                  ),
                  _MetaChip(
                    label: 'Accuracy $accuracyText',
                    icon: Icons.gps_fixed,
                  ),
                  _MetaChip(
                    label: 'Altitude $altitudeText',
                    icon: Icons.landscape,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: SizedBox(
                    height: 360,
                    width: double.infinity,
                    child: _GeoPhotoCanvas(
                      imagePath: capture.imagePath,
                      name: capture.name,
                      mediaType: capture.mediaType,
                      lines: _buildOverlayLines(
                        capture: capture,
                        coordinateFormat: coordinateFormat,
                        referenceEllipsoid: referenceEllipsoid,
                        unit: distanceUnit,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _DetailSection(
                title: 'Coordinates',
                children: [
                  _DetailRow(label: 'Lat/Lon', value: formattedCoordinates),
                  _DetailRow(label: 'UTM', value: utmText),
                ],
              ),
              const SizedBox(height: 12),
              _DetailSection(
                title: 'Motion',
                children: [
                  _DetailRow(label: 'Speed', value: speedText),
                  _DetailRow(label: 'Heading', value: headingText),
                ],
              ),
              const SizedBox(height: 12),
              _DetailSection(
                title: 'Reference',
                children: [
                  _DetailRow(
                    label: 'Ellipsoid',
                    value: referenceEllipsoid.displayName,
                  ),
                  _DetailRow(label: 'Captured at', value: when),
                ],
              ),
              const SizedBox(height: 12),
              _DetailSection(
                title: 'Address',
                children: [
                  _DetailRow(label: 'Location', value: placemarkText),
                  if (capture.locationError != null)
                    _DetailRow(
                      label: 'Location note',
                      value: capture.locationError!,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Reusable sub-widgets (unchanged from original)
// ─────────────────────────────────────────────────────────

class _DetailSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _DetailSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.black54,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final IconData icon;
  const _MetaChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.black54),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
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
  bool _isRecordingVideo = false;
  bool _videoMode = false;
  String? _setupError;
  String? _locationError;
  Position? _livePosition;
  Placemark? _livePlacemark;
  Position? _placemarkPosition;
  XFile? _capturedPhoto;
  DateTime? _capturedAt;
  Position? _capturedPosition;
  Placemark? _capturedPlacemark;
  String _capturedMediaType = 'image';

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
        (c) => c.lensDirection == CameraLensDirection.back,
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
      setState(() => _isInitializing = false);
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
          accuracy: LocationAccuracy.bestForNavigation,
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
          locationSettings: AndroidSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 1,
            intervalDuration: const Duration(seconds: 2),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'TaREF GPS - Coordinates',
              notificationText: 'Location tracking is active',
              enableWakeLock: true,
              notificationIcon: AndroidResource(
                name: 'ic_launcher',
                defType: 'mipmap',
              ),
            ),
          ),
        ).listen(
          (position) async {
            _livePosition = position;
            if (!mounted) return;
            setState(() {});
            final shouldRefresh =
                _placemarkPosition == null ||
                Geolocator.distanceBetween(
                      _placemarkPosition!.latitude,
                      _placemarkPosition!.longitude,
                      position.latitude,
                      position.longitude,
                    ) >
                    20;
            if (!shouldRefresh) return;
            final next = await _reverseGeocode(position);
            if (!mounted) return;
            setState(() {
              _livePlacemark = next;
              _placemarkPosition = position;
            });
          },
          onError: (_) {
            if (!mounted) return;
            setState(() => _locationError = 'Live location updates failed.');
          },
        );
  }

  Future<void> _captureMedia() async {
    final controller = _cameraController;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isTakingPhoto ||
        _isRecordingVideo) {
      return;
    }
    setState(() => _isTakingPhoto = true);
    try {
      if (_videoMode) {
        await controller.startVideoRecording();
        if (!mounted) return;
        setState(() => _isRecordingVideo = true);
      } else {
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
          _capturedMediaType = 'image';
        });
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to capture photo.')));
    } finally {
      if (mounted) setState(() => _isTakingPhoto = false);
    }
  }

  Future<void> _stopVideoRecording() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isRecordingVideo) return;
    try {
      final file = await controller.stopVideoRecording();
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
        _capturedMediaType = 'video';
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to stop video recording.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRecordingVideo = false;
          _isTakingPhoto = false;
        });
      }
    }
  }

  void _retake() => setState(() {
    _capturedPhoto = null;
    _capturedAt = null;
    _capturedPosition = null;
    _capturedPlacemark = null;
    _capturedMediaType = 'image';
  });

  Future<void> _save() async {
    final capturedPhoto = _capturedPhoto;
    if (capturedPhoto == null) return;
    final shouldContinue = await _promptForPlaceName();
    if (!mounted || !shouldContinue) return;
    Navigator.of(context).pop(
      _GeoTaggedPhoto(
        imagePath: capturedPhoto.path,
        capturedAt: _capturedAt ?? DateTime.now(),
        position: _capturedPosition,
        placemark: _capturedPlacemark,
        locationError: _locationError,
        name: _nameController.text.trim(),
        mediaType: _capturedMediaType,
      ),
    );
  }

  Future<bool> _promptForPlaceName() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Place name'),
        content: TextField(
          controller: _nameController,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Enter place name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _nameController.clear();
              Navigator.of(dialogContext).pop(true);
            },
            child: const Text('Skip'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    return result ?? false;
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
        mediaType: _capturedPhoto == null
            ? (_videoMode ? 'video' : 'image')
            : _capturedMediaType,
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
                        : _CapturedMediaPreview(
                            filePath: _capturedPhoto!.path,
                            mediaType: _capturedMediaType,
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
                        Expanded(
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.42),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Text(
                                _capturedPhoto == null
                                    ? 'GPS Camera'
                                    : 'Preview',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 46, height: 46),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 28,
                    child: _CameraBottomControls(
                      capturedPhoto: _capturedPhoto,
                      isTakingPhoto: _isTakingPhoto,
                      isRecordingVideo: _isRecordingVideo,
                      videoMode: _videoMode,
                      locationError: _locationError,
                      onTogglePhoto: _isRecordingVideo
                          ? null
                          : () => setState(() => _videoMode = false),
                      onToggleVideo: _isRecordingVideo
                          ? null
                          : () => setState(() => _videoMode = true),
                      onCapture: _isTakingPhoto
                          ? null
                          : (_videoMode
                                ? (_isRecordingVideo
                                      ? _stopVideoRecording
                                      : _captureMedia)
                                : _captureMedia),
                      onRetake: _retake,
                      onSave: _save,
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 20, 116),
            child: Align(
              alignment: Alignment.bottomRight,
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
                    mediaType: _videoMode ? 'video' : 'image',
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

// Extracted camera bottom controls widget for cleaner build method
class _CameraBottomControls extends StatelessWidget {
  final XFile? capturedPhoto;
  final bool isTakingPhoto;
  final bool isRecordingVideo;
  final bool videoMode;
  final String? locationError;
  final VoidCallback? onTogglePhoto;
  final VoidCallback? onToggleVideo;
  final VoidCallback? onCapture;
  final VoidCallback onRetake;
  final Future<void> Function() onSave;

  const _CameraBottomControls({
    required this.capturedPhoto,
    required this.isTakingPhoto,
    required this.isRecordingVideo,
    required this.videoMode,
    required this.locationError,
    required this.onTogglePhoto,
    required this.onToggleVideo,
    required this.onCapture,
    required this.onRetake,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (locationError != null) ...[
            Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.white70, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    locationError!,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (capturedPhoto == null) ...[
            // Mode toggle
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: onTogglePhoto,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: !videoMode ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Photo',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: !videoMode ? Colors.black87 : Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: onToggleVideo,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: videoMode ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Video',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: videoMode ? Colors.black87 : Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Shutter
            Column(
              children: [
                GestureDetector(
                  onTap: onCapture,
                  child: Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                    ),
                    child: Center(
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: isTakingPhoto
                            ? const Padding(
                                padding: EdgeInsets.all(20),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              )
                            : isRecordingVideo
                            ? Center(
                                child: Container(
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFC94835),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              )
                            : Icon(
                                videoMode ? Icons.videocam : Icons.photo_camera,
                                color: videoMode
                                    ? const Color(0xFFC94835)
                                    : Colors.black87,
                                size: 30,
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  isRecordingVideo
                      ? 'Recording… Tap to stop'
                      : videoMode
                      ? 'Tap to record video'
                      : 'Tap to capture photo',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ] else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onRetake,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white70),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Retake'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0C8A8C),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Remaining helpers (unchanged from original)
// ─────────────────────────────────────────────────────────

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
  final String mediaType;
  final List<String> lines;
  final bool dense;

  const _GeoPhotoCanvas({
    required this.imagePath,
    required this.name,
    required this.mediaType,
    required this.lines,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (mediaType == 'video')
          Container(
            color: Colors.black,
            child: const Center(
              child: Icon(
                Icons.play_circle_fill,
                color: Colors.white,
                size: 74,
              ),
            ),
          )
        else
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
        Padding(
          padding: EdgeInsets.fromLTRB(
            dense ? 18 : 26,
            dense ? 18 : 26,
            dense ? 16 : 20,
            dense ? 22 : 30,
          ),
          child: Align(
            alignment: Alignment.bottomRight,
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
    final fontSize = dense ? 11.0 : 14.0;
    final titleSize = dense ? 14.0 : 18.0;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: dense ? 220 : 300),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (title.isNotEmpty)
            Text(
              title,
              textAlign: TextAlign.right,
              style: _overlayStyle(
                fontSize: titleSize,
                weight: FontWeight.w700,
              ),
            ),
          if (title.isNotEmpty) SizedBox(height: dense ? 8 : 12),
          for (final line in lines) ...[
            Text(
              line,
              textAlign: TextAlign.right,
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

class _CapturedMediaPreview extends StatefulWidget {
  final String filePath;
  final String mediaType;
  final String name;
  final List<String> lines;

  const _CapturedMediaPreview({
    required this.filePath,
    required this.mediaType,
    required this.name,
    required this.lines,
  });

  @override
  State<_CapturedMediaPreview> createState() => _CapturedMediaPreviewState();
}

class _CapturedMediaPreviewState extends State<_CapturedMediaPreview> {
  VideoPlayerController? _videoController;
  bool _videoInitialized = false;

  @override
  void initState() {
    super.initState();
    if (widget.mediaType == 'video') _initVideo();
  }

  Future<void> _initVideo() async {
    final controller = VideoPlayerController.file(File(widget.filePath));
    _videoController = controller;
    await controller.initialize();
    if (!mounted) return;
    setState(() => _videoInitialized = true);
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    final c = _videoController;
    if (c == null) return;
    setState(() => c.value.isPlaying ? c.pause() : c.play());
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mediaType != 'video') {
      return _GeoPhotoCanvas(
        imagePath: widget.filePath,
        name: widget.name,
        mediaType: widget.mediaType,
        lines: widget.lines,
      );
    }
    final controller = _videoController;
    final isPlaying = controller?.value.isPlaying ?? false;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_videoInitialized && controller != null)
          GestureDetector(
            onTap: _togglePlayPause,
            child: Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            ),
          )
        else
          const ColoredBox(
            color: Colors.black,
            child: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
        if (_videoInitialized)
          GestureDetector(
            onTap: _togglePlayPause,
            child: AnimatedOpacity(
              opacity: isPlaying ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: const ColoredBox(
                color: Colors.transparent,
                child: Center(
                  child: Icon(
                    Icons.play_circle_fill,
                    color: Colors.white,
                    size: 74,
                  ),
                ),
              ),
            ),
          ),
        if (_videoInitialized && controller != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 100,
            child: VideoProgressIndicator(
              controller,
              allowScrubbing: true,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              colors: const VideoProgressColors(
                playedColor: Colors.white,
                bufferedColor: Colors.white38,
                backgroundColor: Colors.white12,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 20, 116),
          child: Align(
            alignment: Alignment.bottomRight,
            child: _OverlayTextBlock(title: widget.name, lines: widget.lines),
          ),
        ),
      ],
    );
  }
}

class _RecentMediaStrip extends StatelessWidget {
  final List<_GeoTaggedPhoto> media;
  final bool isLoggedIn;
  final VoidCallback onViewMore;
  final ValueChanged<_GeoTaggedPhoto> onOpenItem;
  final VoidCallback onCapture;

  const _RecentMediaStrip({
    required this.media,
    required this.onViewMore,
    required this.onOpenItem,
    required this.isLoggedIn,
    required this.onCapture,
  });

  @override
  Widget build(BuildContext context) {
    final visibleItems = media.take(3).toList();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Recent media',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            TextButton(onPressed: onViewMore, child: const Text('View more')),
          ],
        ),
        const SizedBox(height: 8),
        if (visibleItems.isEmpty)
          InkWell(
            onTap: isLoggedIn ? onViewMore : onCapture,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isLoggedIn
                        ? Icons.photo_library_outlined
                        : Icons.camera_alt_outlined,
                    color: Colors.grey.shade400,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isLoggedIn
                            ? 'No local media yet'
                            : 'No photos captured yet',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isLoggedIn
                            ? 'Tap to view cloud media'
                            : 'Tap to capture your first photo',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
            ),
          )
        else
          SizedBox(
            height: 118,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: visibleItems.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final capture = visibleItems[index];
                return InkWell(
                  onTap: () => onOpenItem(capture),
                  borderRadius: BorderRadius.circular(14),
                  child: Ink(
                    width: 150,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _GeoPhotoCanvas(
                            imagePath: capture.imagePath,
                            name: capture.name,
                            mediaType: capture.mediaType,
                            lines: const [],
                            dense: true,
                          ),
                          Positioned(
                            left: 8,
                            right: 8,
                            bottom: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.42),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                capture.mediaType == 'video'
                                    ? 'Video'
                                    : 'Photo',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
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
            width: 112,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.black54,
                fontWeight: FontWeight.w700,
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

// ─────────────────────────────────────────────────────────
// Pure utility functions (unchanged)
// ─────────────────────────────────────────────────────────

String _formatUtmCoordinate(
  double latitude,
  double longitude,
  ReferenceEllipsoid ellipsoid,
) {
  final utm = UtmConverter.fromLatLng(latitude, longitude, ellipsoid);
  if (utm == null) return 'UTM unavailable for this latitude';
  return utm.toDisplayString();
}

List<String> _buildOverlayLines({
  required _GeoTaggedPhoto capture,
  required CoordinateFormat coordinateFormat,
  required ReferenceEllipsoid referenceEllipsoid,
  required DistanceUnit unit,
  bool includeLocationNote = true,
}) {
  final placemark = capture.placemark;
  final position = capture.position;
  final street = (placemark?.street ?? '').trim();
  final area = [
    placemark?.subLocality?.trim() ?? '',
    placemark?.locality?.trim() ?? '',
  ].firstWhere((v) => v.isNotEmpty, orElse: () => '');

  final lines = <String>[
    'Date ${_formatCaptureDateTime(capture.capturedAt)}',
    if (street.isNotEmpty) 'Street $street',
    if (area.isNotEmpty) 'Place $area',
    if (position != null)
      'Coordinates ${CoordinateFormatter.format(position.latitude, position.longitude, coordinateFormat)}',
    if (position != null)
      'Accuracy ${_formatOverlayDistance(position.accuracy, unit)}',
  ];

  if (includeLocationNote && capture.locationError != null) {
    lines.add(capture.locationError!);
  }

  return lines.isEmpty ? const ['Waiting for GPS details'] : lines;
}

String _formatOverlayDistance(double meters, DistanceUnit unit) {
  if (unit == DistanceUnit.feet) {
    return '${(meters * 3.28084).toStringAsFixed(1)} ft';
  }
  return '${meters.toStringAsFixed(1)} m';
}

String _formatCaptureDateTime(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  final hh = value.hour.toString().padLeft(2, '0');
  final mm = value.minute.toString().padLeft(2, '0');
  return '$day/$month/${value.year} $hh:$mm';
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
  ].where((v) => v.trim().isNotEmpty).toSet().toList();
  return values.isEmpty ? 'Address unavailable' : values.join(', ');
}
