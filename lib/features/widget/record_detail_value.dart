import 'package:flutter/material.dart';

/// Keeps record labels readable when a narrow sheet or large text leaves too
/// little space for a two-column detail row.
class RecordDetailValue extends StatelessWidget {
  const RecordDetailValue({
    super.key,
    required this.label,
    required this.value,
  });
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stacked =
          constraints.maxWidth < 300 ||
          MediaQuery.textScalerOf(context).scale(12) > 16;
      final labelWidget = Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF667085),
        ),
      );
      final valueWidget = Text(
        value,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF17212F),
        ),
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [labelWidget, const SizedBox(height: 4), valueWidget],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 104, child: labelWidget),
                  const SizedBox(width: 12),
                  Expanded(child: valueWidget),
                ],
              ),
      );
    },
  );
}
