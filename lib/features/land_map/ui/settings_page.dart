import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/models/auth_models.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/ui/account_page.dart';
import '../models/coordinate_format.dart';
import '../models/reference_ellipsoid.dart';
import '../state/settings_provider.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _keepScreenOn = false;

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
      color:Colors.white,
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

          _sectionHeader('General', theme),
          _switchItem(
            title: 'Keep screen on',
            value: _keepScreenOn,
            onChanged: (value) => setState(() => _keepScreenOn = value),
          ),
          _item(
            title: 'App language',
            subtitle: 'English',
            onTap: _comingSoon('App language'),
          ),
          _sectionDivider(),

          _sectionHeader('Location Settings', theme),
          _item(
            title: 'Coordinates format',
            subtitle: selectedFormat.displayName,
            onTap: _showCoordinateFormatSelector,
          ),
          _item(
            title: 'Location accuracy',
            subtitle: 'High accuracy',
            onTap: _comingSoon('Location accuracy'),
          ),
          _item(
            title: 'Reference ellipsoid',
            subtitle: selectedEllipsoid.displayName,
            onTap: _showReferenceEllipsoidSelector,
          ),
          _item(
            title: 'Location provider',
            subtitle: 'Fused',
            onTap: _comingSoon('Location provider'),
          ),
          _sectionDivider(),

          _sectionHeader('Units', theme),
          _item(
            title: 'Altitude units',
            subtitle: unitLabel,
            onTap: _showDistanceUnitSelector,
          ),
          _item(
            title: 'Accuracy units',
            subtitle: unitLabel,
            onTap: _showDistanceUnitSelector,
          ),
          _item(
            title: 'Distance units',
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

          _sectionHeader('Compass', theme),
          _item(
            title: 'Compass mode',
            subtitle: 'True north',
            onTap: _comingSoon('Compass mode'),
          ),
          _sectionDivider(),

          _sectionHeader('Other', theme),
          _item(title: 'Privacy policy', onTap: _comingSoon('Privacy policy')),
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
            subtitle: '1.0.0+1',
            onTap: _comingSoon('Version'),
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
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const AccountPage(),
      ),
    );
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
                        onTap: () {
                          ref
                              .read(referenceEllipsoidProvider.notifier)
                              .setEllipsoid(ellipsoid);
                          Navigator.pop(context);
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
