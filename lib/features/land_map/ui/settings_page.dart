import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/coordinate_format.dart';
import '../state/settings_provider.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _keepScreenOn = false;
  bool _oneClickCopy = false;
  bool _saveOriginalPhoto = true;

  @override
  Widget build(BuildContext context) {
    final selectedFormat = ref.watch(coordinateFormatProvider);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _sectionHeader('Premium', theme),
        _item(
          title: 'Subscriptions',
          onTap: _comingSoon('Subscriptions'),
        ),
        _item(
          title: 'Remove ads',
          subtitle: 'Watch 3 ads to go ad-free for 24 hours',
          onTap: _comingSoon('Remove ads'),
        ),
        _sectionDivider(),

        _sectionHeader('Cloud synchronization', theme),
        _item(
          title: 'Account',
          onTap: _comingSoon('Account'),
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
          title: 'Location provider',
          subtitle: 'Fused',
          onTap: _comingSoon('Location provider'),
        ),
        _switchItem(
          title: 'One-click copy',
          subtitle:
              'After long press on latitude or longitude, copy both as CSV.',
          value: _oneClickCopy,
          onChanged: (value) => setState(() => _oneClickCopy = value),
        ),
        _item(
          title: 'Elevation cache',
          subtitle: 'Size 0 MB. Tap to clear cache',
          onTap: _comingSoon('Elevation cache'),
        ),
        _item(
          title: 'Device settings',
          onTap: _comingSoon('Device settings'),
        ),
        _item(
          title: 'Location data is based on WGS84',
          onTap: _comingSoon('Location data'),
        ),
        _sectionDivider(),

        _sectionHeader('Units', theme),
        _item(
          title: 'Altitude units',
          subtitle: 'Feet',
          onTap: _comingSoon('Altitude units'),
        ),
        _item(
          title: 'Accuracy units',
          subtitle: 'Feet',
          onTap: _comingSoon('Accuracy units'),
        ),
        _item(
          title: 'Distance units',
          subtitle: 'Feet',
          onTap: _comingSoon('Distance units'),
        ),
        _sectionDivider(),

        _sectionHeader('SOS', theme),
        _item(
          title: 'Rescue phone number',
          subtitle: 'Not set',
          onTap: _comingSoon('Rescue phone number'),
        ),
        _item(
          title: 'Rescue message',
          subtitle: 'Not set',
          onTap: _comingSoon('Rescue message'),
        ),
        _sectionDivider(),

        _sectionHeader('Photo', theme),
        _switchItem(
          title: 'Save original photo',
          subtitle:
              'Save with no data on it. Useful for editing before sharing.',
          value: _saveOriginalPhoto,
          onChanged: (value) => setState(() => _saveOriginalPhoto = value),
        ),
        _item(
          title: 'Save to gallery',
          subtitle: 'Save image with data',
          onTap: _comingSoon('Save to gallery'),
        ),
        _item(
          title: 'Image quality',
          subtitle: 'High',
          onTap: _comingSoon('Image quality'),
        ),
        _item(
          title: 'Capture mode',
          subtitle: 'Inside the app',
          onTap: _comingSoon('Capture mode'),
        ),
        _sectionDivider(),

        _sectionHeader('Maps', theme),
        _item(
          title: 'Default map zoom level',
          subtitle: '14.0',
          onTap: _comingSoon('Default map zoom level'),
        ),
        _item(
          title: 'Navigate with',
          subtitle: 'Google Maps',
          onTap: _comingSoon('Navigate with'),
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
        _item(
          title: 'Privacy policy',
          onTap: _comingSoon('Privacy policy'),
        ),
        _item(
          title: 'Install app on a watch',
          onTap: _comingSoon('Install app on a watch'),
        ),
        _item(
          title: 'More applications',
          onTap: _comingSoon('More applications'),
        ),
        _item(
          title: 'Share this app',
          onTap: _comingSoon('Share this app'),
        ),
        _item(
          title: 'Rate us',
          onTap: _comingSoon('Rate us'),
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
          subtitle: '1.0.0+1',
          onTap: _comingSoon('Version'),
        ),
      ],
    );
  }

  Widget _sectionHeader(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 6),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          color: const Color(0xFF0C8A8C),
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
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 15,
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
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 15,
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
              return RadioListTile<CoordinateFormat>(
                title: Text(format.displayName),
                subtitle: Text(_getFormatExample(format)),
                value: format,
                groupValue: current,
                activeColor: const Color(0xFF0C8A8C),
                onChanged: (value) {
                  if (value != null) {
                    ref.read(coordinateFormatProvider.notifier).setFormat(value);
                    Navigator.pop(context);
                  }
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _getFormatExample(CoordinateFormat format) {
    const lat = -6.7924;
    const lon = 39.2083;
    return 'Example: ${CoordinateFormatter.format(lat, lon, format)}';
  }
}
