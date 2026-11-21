import 'package:flutter/material.dart';
import '../constants/omni_constants.dart';
import 'home_screen.dart';

class OmniSplashScreen extends StatefulWidget {
  const OmniSplashScreen({super.key});

  @override
  State<OmniSplashScreen> createState() => _OmniSplashScreenState();
}

class _OmniSplashScreenState extends State<OmniSplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 8.0, end: 28.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    // Navega automaticamente para a Home inteligente após 2 segundos
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const OmniHomeScreen(),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OmniConstants.darkBackground,
      body: Center(
        child: AnimatedBuilder(
          animation: _glowAnimation,
          builder: (context, child) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: OmniConstants.darkSurface,
                    shape: BoxShape.circle,
                    border: Border.all(color: OmniConstants.neonCyan, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: OmniConstants.neonCyan.withOpacity(0.35),
                        blurRadius: _glowAnimation.value,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.navigation_rounded,
                      size: 48,
                      color: OmniConstants.neonCyan,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'OMNI',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4.0,
                    color: OmniConstants.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'MOBILIDADE URBANA INTELIGENTE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.5,
                    color: OmniConstants.neonCyan,
                  ),
                ),
                const SizedBox(height: 48),
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(OmniConstants.neonCyan),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
