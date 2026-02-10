import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/coordinate_format.dart';
import '../state/settings_provider.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedFormat = ref.watch(coordinateFormatProvider);

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        // Coordinate Format Section
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(20),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF001F3F).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.location_on_outlined,
                      color: Color(0xFF001F3F),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Coordinate Format',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...CoordinateFormat.values.map((format) {
                final isSelected = format == selectedFormat;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF001F3F)
                          : Colors.grey.shade300,
                      width: isSelected ? 2 : 1,
                    ),
                    color: isSelected
                        ? const Color(0xFF001F3F).withValues(alpha: 0.05)
                        : Colors.transparent,
                  ),
                  child: RadioListTile<CoordinateFormat>(
                    title: Text(
                      format.displayName,
                      style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: isSelected
                            ? const Color(0xFF001F3F)
                            : Colors.black87,
                      ),
                    ),
                    subtitle: Text(
                      _getFormatExample(format),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    value: format,
                    groupValue: selectedFormat,
                    activeColor: const Color(0xFF001F3F),
                    onChanged: (value) {
                      if (value != null) {
                        ref
                            .read(coordinateFormatProvider.notifier)
                            .setFormat(value);
                      }
                    },
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Unit Formats Section
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(20),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Unit Formats',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              _buildUnitItem(
                context,
                icon: Icons.square_outlined,
                title: 'Area Unit',
                currentValue: 'm²',
              ),
              const Divider(height: 1),
              _buildUnitItem(
                context,
                icon: Icons.straighten,
                title: 'Distance Unit',
                currentValue: 'm',
              ),
              const Divider(height: 1),
              _buildUnitItem(
                context,
                icon: Icons.category_outlined,
                title: 'Perimeter Unit',
                currentValue: 'm',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUnitItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String currentValue,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: Icon(icon, color: Colors.black87, size: 24),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            currentValue,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
        ],
      ),
      onTap: () {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$title - Coming soon')));
      },
    );
  }

  String _getFormatExample(CoordinateFormat format) {
    const lat = -6.7924;
    const lon = 39.2083;
    return 'Example: ${CoordinateFormatter.format(lat, lon, format)}';
  }
}
