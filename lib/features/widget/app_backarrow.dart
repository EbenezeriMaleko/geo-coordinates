import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

class AppBackButton extends StatelessWidget {
  final VoidCallback? onPressed;
  const AppBackButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Back',
      onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
      icon: const HugeIcon(
        icon: HugeIcons.strokeRoundedArrowLeft01,
        color: Colors.black87,
        size: 24,
      ),
    );
  }
}