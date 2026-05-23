import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../auth/models/auth_models.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/ui/account_page.dart';
import '../models/coordinate_format.dart';
import '../models/reference_ellipsoid.dart';
import '../state/settings_provider.dart';
import '../state/land_map_notifier.dart';
import '../services/coordinate_converter.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final Future<PackageInfo> _packageInfoFuture;

  @override
  void initState() {
    super.initState();
    _packageInfoFuture = PackageInfo.fromPlatform();
  }

  @override
  Widget build(BuildContext context) {
    final selectedFormat = ref.watch(coordinateFormatProvider);
    final selectedUnit = ref.watch(distanceUnitProvider);
    final saveOriginalPhoto = ref.watch(saveOriginalPhotoProvider);
    final saveToGallery = ref.watch(saveToGalleryProvider);
    final photoQuality = ref.watch(photoQualityProvider);
    final captureMode = ref.watch(photoCaptureModeProvider);
    final selectedEllipsoid = ref.watch(referenceEllipsoidProvider);
    final session = ref.watch(authSessionProvider);
    final theme = Theme.of(context);
    final unitLabel = selectedUnit == DistanceUnit.feet ? 'Feet' : 'Meters';
    final accountSubtitle = _accountSubtitle(session);

    return ColoredBox(
      color: Colors.white,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _sectionHeader('Cloud synchronization', theme),
          _item(
            title: 'Account',
            subtitle: accountSubtitle,
            onTap: _openAccountPage,
          ),
          _sectionDivider(),

          _sectionHeader('Location Settings', theme),
          _item(
            title: 'Coordinates format',
            subtitle: selectedFormat.displayName,
            onTap: _showCoordinateFormatSelector,
          ),

          _item(
            title: 'Reference ellipsoid',
            subtitle: selectedEllipsoid.displayName,
            onTap: _showReferenceEllipsoidSelector,
          ),

          _sectionDivider(),

          _sectionHeader('Units', theme),
          _item(
            title: 'Units',
            subtitle: unitLabel,
            onTap: _showDistanceUnitSelector,
          ),
          _sectionDivider(),
          _sectionHeader('Photo', theme),
          _switchItem(
            title: 'Save original photo',
            subtitle:
                'Save with no data on it. Useful for editing before sharing.',
            value: saveOriginalPhoto,
            onChanged: (value) =>
                ref.read(saveOriginalPhotoProvider.notifier).setValue(value),
          ),
          _switchItem(
            title: 'Save to gallery',
            subtitle: 'Save image with data',
            value: saveToGallery,
            onChanged: (value) =>
                ref.read(saveToGalleryProvider.notifier).setValue(value),
          ),
          _item(
            title: 'Image quality',
            subtitle: _photoQualityLabel(photoQuality),
            onTap: _showPhotoQualitySelector,
          ),
          _item(
            title: 'Capture mode',
            subtitle: _captureModeLabel(captureMode),
            onTap: _showCaptureModeSelector,
          ),
          _sectionDivider(),
          _sectionHeader('Saved locations', theme),
          _item(
            title: 'View modes',
            subtitle: '[Combined, Basic, Text, Photo]',
            onTap: _comingSoon('View modes'),
          ),

          _sectionDivider(),

          _sectionHeader('Other', theme),
          _item(title: 'Privacy policy', onTap: _comingSoon('Privacy policy')),
          _sectionDivider(),

          _sectionHeader('Cache', theme),
          _item(
            title: 'Clear cache',
            subtitle: 'Remove cached data and temporary files',
            onTap: _clearCache,
          ),
          _sectionDivider(),

          _sectionHeader('Information', theme),
          _item(
            title: 'Contact us',
            subtitle:
                'Send suggestions or report a bug. We appreciate your feedback.',
            onTap: _comingSoon('Contact us'),
          ),
          _item(
            title: 'Version',
            subtitleWidget: FutureBuilder<PackageInfo>(
              future: _packageInfoFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Text(
                    'Loading version...',
                    style: TextStyle(fontSize: 14, color: Colors.black54),
                  );
                }

                final info = snapshot.data;
                if (info == null) {
                  return const Text(
                    'Version unavailable',
                    style: TextStyle(fontSize: 14, color: Colors.black54),
                  );
                }

                return Text(
                  '${info.version}+${info.buildNumber}',
                  style: const TextStyle(fontSize: 14, color: Colors.black54),
                );
              },
            ),
            onTap: _showVersionDetails,
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 6),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _item({
    required String title,
    String? subtitle,
    Widget? subtitleWidget,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            if (subtitleWidget != null) ...[
              const SizedBox(height: 3),
              subtitleWidget,
            ] else if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black54,
                  height: 1.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _switchItem({
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Checkbox(
            value: value,
            onChanged: (newValue) => onChanged(newValue ?? false),
            side: const BorderSide(color: Colors.black45, width: 2),
            activeColor: const Color(0xFF0C8A8C),
          ),
        ],
      ),
    );
  }

  Widget _sectionDivider() {
    return Divider(height: 1, color: Colors.grey.shade300);
  }

  VoidCallback _comingSoon(String feature) {
    return () {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$feature - Coming soon')));
    };
  }

  void _showVersionDetails() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: FutureBuilder<PackageInfo>(
              future: _packageInfoFuture,
              builder: (context, snapshot) {
                final info = snapshot.data;
                final versionText = info == null
                    ? 'Loading version...'
                    : '${info.version}+${info.buildNumber}';

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Version',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      versionText,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.connectionState == ConnectionState.waiting
                          ? 'Reading build metadata from the app package...'
                          : 'This comes from the installed app metadata.',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _clearCache() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear cache?'),
        content: const Text(
          'This will clear all cached data including images, '
          'temporary files, and app cache storage. '
          'Your saved locations will not be affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);

              final messenger = ScaffoldMessenger.of(context);

              try {
                // Clear Flutter image cache
                imageCache.clear();
                imageCache.clearLiveImages();

                // Calculate freed space
                int freedBytes = 0;

                final tempDir = await getTemporaryDirectory();
                if (tempDir.existsSync()) {
                  freedBytes += _getTotalSize(tempDir);
                  await tempDir.delete(recursive: true);
                  await tempDir.create(recursive: true);
                }

                try {
                  final cacheDir = await getApplicationCacheDirectory();
                  if (cacheDir.existsSync()) {
                    freedBytes += _getTotalSize(cacheDir);
                    await cacheDir.delete(recursive: true);
                    await cacheDir.create(recursive: true);
                  }
                } catch (_) {}

                if (!mounted) return;

                final freedMB = (freedBytes / (1024 * 1024)).toStringAsFixed(2);
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      freedBytes > 0
                          ? 'Cache cleared successfully (~$freedMB MB freed)'
                          : 'Cache cleared successfully',
                    ),
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(content: Text('Error clearing cache: $e')),
                );
              }
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // Helper method to calculate total size of directory
  int _getTotalSize(Directory dir) {
    int totalSize = 0;
    try {
      if (dir.existsSync()) {
        dir.listSync(recursive: true).forEach((file) {
          if (file is File) {
            totalSize += file.lengthSync();
          }
        });
      }
    } catch (_) {}
    return totalSize;
  }

  String _accountSubtitle(AuthSession session) {
    final user = session.user;
    final fullName = user?.name.trim() ?? '';
    final email = user?.email.trim() ?? '';

    if (fullName.isNotEmpty && email.isNotEmpty) {
      return '$fullName\n$email';
    }
    if (fullName.isNotEmpty) {
      return '$fullName\nSigned in';
    }
    if (email.isNotEmpty) {
      return '$email\nSigned in';
    }
    return 'Sign in only when you want to sync data to the server.';
  }

  Future<void> _openAccountPage() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: (_) => const AccountPage()));
  }

  void _showCoordinateFormatSelector() {
    final current = ref.read(coordinateFormatProvider);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            const Text(
              'Coordinates format',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            ...CoordinateFormat.values.map((format) {
              final isSelected = format == current;
              return ListTile(
                title: Text(format.displayName),
                subtitle: Text(_getFormatExample(format)),
                trailing: isSelected
                    ? const Icon(Icons.check_circle, color: Color(0xFF0C8A8C))
                    : const Icon(Icons.circle_outlined),
                onTap: () {
                  ref.read(coordinateFormatProvider.notifier).setFormat(format);
                  Navigator.pop(context);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showDistanceUnitSelector() {
    final current = ref.read(distanceUnitProvider);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            const Text(
              'Units',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            ListTile(
              title: const Text('Meters'),
              subtitle: const Text('Use meters (m)'),
              trailing: current == DistanceUnit.meters
                  ? const Icon(Icons.check_circle, color: Color(0xFF0C8A8C))
                  : const Icon(Icons.circle_outlined),
              onTap: () {
                ref
                    .read(distanceUnitProvider.notifier)
                    .setUnit(DistanceUnit.meters);
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Feet'),
              subtitle: const Text('Use feet (ft)'),
              trailing: current == DistanceUnit.feet
                  ? const Icon(Icons.check_circle, color: Color(0xFF0C8A8C))
                  : const Icon(Icons.circle_outlined),
              onTap: () {
                ref
                    .read(distanceUnitProvider.notifier)
                    .setUnit(DistanceUnit.feet);
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showReferenceEllipsoidSelector() {
    final current = ref.read(referenceEllipsoidProvider);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.75,
          child: Column(
            children: [
              const SizedBox(height: 10),
              const Text(
                'Reference ellipsoid',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView(
                  children: [
                    ...ReferenceEllipsoid.values.map((ellipsoid) {
                      final isSelected = ellipsoid == current;
                      return ListTile(
                        title: Text(ellipsoid.displayName),
                        subtitle: Text(
                          ellipsoid.isDefault
                              ? 'Default GPS reference for this app.'
                              : 'Use for display or export workflows that follow this model.',
                        ),
                        trailing: isSelected
                            ? const Icon(
                                Icons.check_circle,
                                color: Color(0xFF0C8A8C),
                              )
                            : const Icon(Icons.circle_outlined),
                        onTap: () async {
                          final popContext = Navigator.of(context);
                          // Handle ellipsoid change with coordinate transformation
                          if (ellipsoid != current) {
                            await _handleEllipsoidChange(ellipsoid);
                          }
                          popContext.pop();
                        },
                      );
                    }),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Handle ellipsoid change and transform all coordinates
  Future<void> _handleEllipsoidChange(ReferenceEllipsoid newEllipsoid) async {
    try {
      final ellipsoidNotifier = ref.read(referenceEllipsoidProvider.notifier);
      final currentEllipsoid = ref.read(referenceEllipsoidProvider);

      // If no change, return early
      if (newEllipsoid == currentEllipsoid) {
        return;
      }

      // Get the land map notifier
      final landMapNotifier = ref.read(landMapProvider.notifier);

      // Create a conversion function using the coordinate converter
      LatLng conversionFunction(LatLng coord) {
        return CoordinateConverter.convertCoordinates(
          coord,
          currentEllipsoid,
          newEllipsoid,
        );
      }

      // Debug: report ellipsoid change and point count
      try {
        final pointCount = ref.read(landMapProvider).points.length;
        debugPrint(
          'SettingsPage: changing ellipsoid from '
          '${currentEllipsoid.name} to ${newEllipsoid.name}; points=$pointCount',
        );
      } catch (_) {}

      // Transform all coordinates in the land map
      landMapNotifier.transformAllCoordinates(conversionFunction);

      // Update the ellipsoid setting
      await ellipsoidNotifier.setEllipsoid(newEllipsoid);

      // Show confirmation
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Coordinates transformed to ${newEllipsoid.displayName}',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error transforming coordinates: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _getFormatExample(CoordinateFormat format) {
    const lat = -6.7924;
    const lon = 39.2083;
    return 'Example: ${CoordinateFormatter.format(lat, lon, format)}';
  }

  String _photoQualityLabel(PhotoCaptureQuality quality) {
    switch (quality) {
      case PhotoCaptureQuality.low:
        return 'Low';
      case PhotoCaptureQuality.medium:
        return 'Medium';
      case PhotoCaptureQuality.high:
        return 'High';
    }
  }

  String _captureModeLabel(PhotoCaptureMode mode) {
    switch (mode) {
      case PhotoCaptureMode.inApp:
        return 'Inside the app';
      case PhotoCaptureMode.systemCamera:
        return 'System camera';
    }
  }

  void _showPhotoQualitySelector() {
    final current = ref.read(photoQualityProvider);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            const Text(
              'Image quality',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            ...PhotoCaptureQuality.values.map((quality) {
              final selected = quality == current;
              return ListTile(
                title: Text(_photoQualityLabel(quality)),
                trailing: selected
                    ? const Icon(Icons.check_circle, color: Color(0xFF0C8A8C))
                    : const Icon(Icons.circle_outlined),
                onTap: () {
                  ref.read(photoQualityProvider.notifier).setQuality(quality);
                  Navigator.pop(context);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showCaptureModeSelector() {
    final current = ref.read(photoCaptureModeProvider);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            const Text(
              'Capture mode',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            ...PhotoCaptureMode.values.map((mode) {
              final selected = mode == current;
              return ListTile(
                title: Text(_captureModeLabel(mode)),
                subtitle: Text(
                  mode == PhotoCaptureMode.inApp
                      ? 'Built-in camera with live GPS overlay.'
                      : 'Use the device camera app (falls back to in-app if unavailable).',
                ),
                trailing: selected
                    ? const Icon(Icons.check_circle, color: Color(0xFF0C8A8C))
                    : const Icon(Icons.circle_outlined),
                onTap: () {
                  ref.read(photoCaptureModeProvider.notifier).setMode(mode);
                  Navigator.pop(context);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
