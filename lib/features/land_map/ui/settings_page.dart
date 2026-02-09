import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/coordinate_format.dart';
import '../state/settings_provider.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedFormat = ref.watch(coordinateFormatProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Coordinate Format',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ...CoordinateFormat.values.map((format) {
            return RadioListTile<CoordinateFormat>(
              title: Text(format.displayName),
              subtitle: Text(_getFormatExample(format)),
              value: format,
              groupValue: selectedFormat,
              onChanged: (value) {
                if (value != null) {
                  ref.read(coordinateFormatProvider.notifier).setFormat(value);
                }
              },
            );
          }),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'About Coordinate Formats',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  '• DD (Decimal Degrees): Most common format, easy to use with digital maps',
                  style: TextStyle(fontSize: 12),
                ),
                SizedBox(height: 4),
                Text(
                  '• DMS (Degrees Minutes Seconds): Traditional format used in navigation',
                  style: TextStyle(fontSize: 12),
                ),
                SizedBox(height: 4),
                Text(
                  '• DDM (Degrees Decimal Minutes): Hybrid format, common in marine navigation',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getFormatExample(CoordinateFormat format) {
    const lat = -6.7924;
    const lon = 39.2083;
    return 'Example: ${CoordinateFormatter.format(lat, lon, format)}';
  }
}
