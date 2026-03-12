import 'dart:async';

import 'package:flutter/material.dart';

import '../../auth/ui/login_page.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  static const Duration _splashDuration = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    Timer(_splashDuration, () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const LoginPage(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 450),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF4F8FF), Color(0xFFE8F0FF), Color(0xFFDDE8FF)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 120,
                height: 120,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22001F3F),
                      blurRadius: 22,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Image.asset('lib/assets/databenki_latest_logo.png'),
              ),
              const SizedBox(height: 18),
              Text(
                'Land Mapper',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: const Color(0xFF001F3F),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Loading your map experience',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF2F4F78),
                ),
              ),
              const SizedBox(height: 28),
              const SizedBox(
                width: 180,
                child: LinearProgressIndicator(
                  minHeight: 4,
                  borderRadius: BorderRadius.all(Radius.circular(99)),
                  color: Color(0xFF001F3F),
                  backgroundColor: Color(0x334A6FA5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
