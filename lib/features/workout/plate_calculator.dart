import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../domain/models.dart';
import '../../domain/plates.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// Plaka hesaplayıcı alt sayfa.
void showPlateCalculator(BuildContext context, LWeight weight, EquipmentData eq, String unit) {
  final t = AppScope.of(context).t;
  final result = calculatePlates(weight, eq, unit);
  final plateColors = <double, Color>{
    45: const Color(0xFFE74C3C),
    25: const Color(0xFF3498DB),
    20: const Color(0xFF2980B9),
    10: const Color(0xFF2ECC71),
    5: const Color(0xFFF39C12),
    2.5: const Color(0xFF9B59B6),
    1.25: const Color(0xFF95A5A6),
  };

  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => SafeArea(
      top: false,
      child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.s('pl.title'),
              style: Theme.of(context).textTheme.titleLarge!
                  .copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
              t.f('pl.barInfo', {
                'w': fmtWeight(result.achieved),
                'eq': eq.name,
                'bar': fmtWeight(eq.bar),
              }),
              style: const TextStyle(color: AppColors.textDim)),
          const SizedBox(height: 24),
          if (result.platesPerSide.isEmpty)
            Text(t.s('pl.none'),
                style: const TextStyle(color: AppColors.textDim))
          else ...[
            Text(t.s('pl.eachSide'), style: const TextStyle(color: AppColors.textDim)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in result.platesPerSide)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: (plateColors[p.value] ?? AppColors.accent2)
                          .withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(fmtWeight(p),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
              ],
            ),
          ],
          if (result.leftover.value > 0.01) ...[
            const SizedBox(height: 16),
            Text(t.f('pl.unreached', {'w': fmtWeight(result.leftover)}),
                style: const TextStyle(color: AppColors.warn, fontSize: 13)),
          ],
          const SizedBox(height: 12),
        ],
      ),
    ),
    ),
  );
}
