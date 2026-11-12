import 'package:flutter/material.dart';

class WorkspaceScaffold extends StatelessWidget {
  const WorkspaceScaffold({
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
    final navy = company ? const Color(0xFF197568) : const Color(0xFF001F3F);
    const border = Color(0xFFE2E7ED);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    );
    final theme = base.copyWith(
      scaffoldBackgroundColor: Colors.white,
      colorScheme: base.colorScheme.copyWith(
        primary: navy,
        onPrimary: Colors.white,
        surface: Colors.white,
        onSurface: const Color(0xFF17212F),
        onSurfaceVariant: const Color(0xFF667085),
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: base.textTheme.titleMedium?.copyWith(
          color: Colors.black87,
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        labelStyle: base.textTheme.bodyMedium?.copyWith(
          color: const Color(0xFF667085),
        ),
        hintStyle: base.textTheme.bodyMedium?.copyWith(
          color: const Color(0xFF98A2B3),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: navy, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: navy,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: shape,
          textStyle: base.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: navy,
          side: const BorderSide(color: border),
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: shape,
        ),
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
      listTileTheme: ListTileThemeData(
        iconColor: navy,
        titleTextStyle: base.textTheme.bodyMedium?.copyWith(
          color: const Color(0xFF17212F),
          fontWeight: FontWeight.w500,
        ),
        subtitleTextStyle: base.textTheme.bodySmall?.copyWith(
          color: const Color(0xFF667085),
          height: 1.5,
        ),
        minLeadingWidth: 24,
        horizontalTitleGap: 12,
      ),
    );
    return Theme(
      data: theme,
      child: Scaffold(appBar: appBar, body: body),
    );
  }
}
