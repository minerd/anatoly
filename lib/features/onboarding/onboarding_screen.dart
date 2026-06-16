import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../ui/theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  String units = 'kg';

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = app.t;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.fitness_center, color: Colors.black, size: 40),
              ),
              const SizedBox(height: 24),
              const Text('Anatoly',
                  style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                t.s('ob.tagline'),
                style: const TextStyle(color: AppColors.textDim, fontSize: 16, height: 1.4),
              ),
              const SizedBox(height: 40),
              Text(t.s('ob.unit'), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Row(
                children: [
                  _unitOption('kg'),
                  const SizedBox(width: 12),
                  _unitOption('lb'),
                ],
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => app.completeOnboarding(units),
                  child: Text(t.s('ob.start')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _unitOption(String u) {
    final sel = units == u;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => units = u),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: sel ? AppColors.accent.withValues(alpha: 0.15) : AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: sel ? AppColors.accent : Colors.transparent, width: 2),
          ),
          child: Center(
            child: Text(u.toUpperCase(),
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: sel ? AppColors.accent : Colors.white)),
          ),
        ),
      ),
    );
  }
}
