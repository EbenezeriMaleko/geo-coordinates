import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

/// Visual treatment shared by the pages opened from a library record.
class LibraryRecordScaffold extends StatelessWidget {
  const LibraryRecordScaffold({
    super.key,
    required this.appBar,
    required this.body,
    this.company = false,
  });

  final PreferredSizeWidget appBar;
  final Widget body;
  final bool company;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final accent = company ? const Color(0xFF197568) : const Color(0xFF001F3F);
    const border = Color(0xFFE8ECF0);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );
    return Theme(
      data: base.copyWith(
        scaffoldBackgroundColor: const Color(0xFFF7F7F8),
        colorScheme: base.colorScheme.copyWith(
          primary: accent,
          onPrimary: Colors.white,
          surface: Colors.white,
        ),
        appBarTheme: base.appBarTheme.copyWith(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          iconTheme: IconThemeData(color: accent, size: 20),
          titleTextStyle: const TextStyle(
            color: Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: IconThemeData(color: accent, size: 20),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 16,
          ),
          border: inputBorder(border),
          enabledBorder: inputBorder(border),
          disabledBorder: inputBorder(border),
          focusedBorder: inputBorder(accent, 1.5),
          labelStyle: const TextStyle(fontSize: 14, color: Colors.black54),
          floatingLabelStyle: TextStyle(
            color: accent,
            fontWeight: FontWeight.w600,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 48),
            shape: shape,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            textStyle: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: accent,
            side: const BorderSide(color: border),
            minimumSize: const Size(0, 46),
            shape: shape,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        listTileTheme: ListTileThemeData(
          iconColor: accent,
          tileColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: border),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 6,
          ),
          titleTextStyle: const TextStyle(
            color: Colors.black87,
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
          ),
          subtitleTextStyle: const TextStyle(
            color: Colors.black54,
            fontSize: 12.5,
            height: 1.4,
          ),
        ),
        dividerTheme: const DividerThemeData(color: border, thickness: 1),
      ),
      child: Scaffold(appBar: appBar, body: body),
    );
  }
}

class LibraryRecordHeader extends StatelessWidget {
  const LibraryRecordHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final dynamic icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8ECF0)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(13),
            ),
            child: HugeIcon(icon: icon, size: 22, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Colors.black54,
                    height: 1.4,
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
