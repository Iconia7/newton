import 'package:flutter/material.dart';

class ModernLoadingScreen extends StatefulWidget {
  const ModernLoadingScreen({super.key});

  @override
  State<ModernLoadingScreen> createState() => _ModernLoadingScreenState();
}

class _ModernLoadingScreenState extends State<ModernLoadingScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _rotationController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();

    // Pulse animation for the outer circle
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Rotation animation for the inner elements
    _rotationController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    );
    _rotationAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _rotationController, curve: Curves.linear),
    );

    // Start animations
    _pulseController.repeat(reverse: true);
    _rotationController.repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.teal.shade50,
              Colors.cyan.shade50,
              Colors.teal.shade100,
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated logo/loader
              Stack(
                alignment: Alignment.center,
                children: [
                  // Outer pulsing circle
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _pulseAnimation.value,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.teal.withOpacity(0.1),
                            border: Border.all(
                              color: Colors.teal.withOpacity(0.3),
                              width: 2,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  // Middle rotating ring
                  AnimatedBuilder(
                    animation: _rotationAnimation,
                    builder: (context, child) {
                      return Transform.rotate(
                        angle: _rotationAnimation.value * 2 * 3.14159,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.teal, width: 3),
                            gradient: SweepGradient(
                              colors: [
                                Colors.teal,
                                Colors.cyan,
                                Colors.teal.withOpacity(0.1),
                                Colors.teal,
                              ],
                              stops: const [0.0, 0.3, 0.7, 1.0],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  // Inner icon
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.teal.withOpacity(0.3),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.flash_on,
                      color: Colors.teal,
                      size: 24,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 48),

              // App name with modern typography
              Text(
                'Bingwa Sokoni',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.teal.shade700,
                  letterSpacing: 1.2,
                ),
              ),

              const SizedBox(height: 12),

              // Loading text with fade animation
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Opacity(
                    opacity: 0.3 + (0.7 * _pulseAnimation.value / 1.2),
                    child: Text(
                      'Preparing your experience...',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.teal.shade600,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 24),

              // Progress dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (index) {
                  return AnimatedBuilder(
                    animation: _rotationAnimation,
                    builder: (context, child) {
                      double delay = index * 0.3;
                      double animValue = (_rotationAnimation.value + delay) % 1;
                      double opacity =
                          (animValue < 0.5)
                              ? animValue * 2
                              : 2 - (animValue * 2);

                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 100),
                          opacity: 0.3 + (opacity * 0.7),
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.teal,
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
