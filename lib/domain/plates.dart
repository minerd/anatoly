/// Plaka hesaplama ve ekipmana göre ağırlık yuvarlama.
library;

import '../liftoscript/value.dart';
import 'models.dart';

class PlateResult {
  final List<LWeight> platesPerSide; // bir taraftaki plakalar (büyükten küçüğe)
  final LWeight achieved; // ulaşılan toplam ağırlık
  final LWeight leftover; // ulaşılamayan kalan
  const PlateResult(this.platesPerSide, this.achieved, this.leftover);
}

/// Hedef ağırlığı ekipmanla ulaşılabilir en yakın değere yuvarlar.
LWeight roundToEquipment(LWeight target, EquipmentData eq, String unit) {
  final t = weightConvertTo(target, unit);
  if (eq.isFixed) {
    if (eq.fixed.isEmpty) return t;
    LWeight best = weightConvertTo(eq.fixed.first, unit);
    var bestDiff = (best.value - t.value).abs();
    for (final f in eq.fixed) {
      final fc = weightConvertTo(f, unit);
      final d = (fc.value - t.value).abs();
      if (d < bestDiff) {
        bestDiff = d;
        best = fc;
      }
    }
    return best;
  }
  final bar = weightConvertTo(eq.bar, unit);
  final platesInUnit = eq.plates
      .map((p) => weightConvertTo(p.weight, unit))
      .where((w) => w.value > 0)
      .toList();
  if (platesInUnit.isEmpty) {
    return LWeight((t.value).roundToDouble(), unit);
  }
  final smallest = platesInUnit.map((p) => p.value).reduce((a, b) => a < b ? a : b);
  final inc = smallest * eq.multiplier;
  final overBar = t.value - bar.value;
  if (overBar <= 0) return bar;
  final rounded = (overBar / inc).round() * inc;
  return LWeight(_round2(bar.value + rounded), unit);
}

/// Greedy plaka hesabı (bir taraf için).
PlateResult calculatePlates(LWeight target, EquipmentData eq, String unit) {
  final t = weightConvertTo(target, unit);
  final bar = weightConvertTo(eq.bar, unit);
  if (eq.isFixed || eq.multiplier == 0) {
    return PlateResult(const [], t, const LWeight(0, '') == t ? t : LWeight(0, unit));
  }
  var perSide = (t.value - bar.value) / eq.multiplier;
  if (perSide < 0) perSide = 0;

  // mevcut plakalar (adet sınırlı), büyükten küçüğe
  final avail = <LWeight>[];
  for (final p in eq.plates) {
    final w = weightConvertTo(p.weight, unit);
    if (w.value <= 0) continue;
    // num adet = toplam çift sayısı; bir tarafta num/2 (multiplier=2 ise)
    final perSideCount = eq.multiplier == 2 ? (p.count ~/ 2) : p.count;
    for (var i = 0; i < perSideCount; i++) {
      avail.add(w);
    }
  }
  avail.sort((a, b) => b.value.compareTo(a.value));

  final used = <LWeight>[];
  var remaining = perSide;
  const eps = 0.001;
  for (final p in avail) {
    if (p.value <= remaining + eps) {
      used.add(p);
      remaining = _round2(remaining - p.value);
      if (remaining <= eps) break;
    }
  }
  final achievedPerSide = used.fold<double>(0, (s, p) => s + p.value);
  final achieved = LWeight(_round2(bar.value + achievedPerSide * eq.multiplier), unit);
  return PlateResult(used, achieved, LWeight(_round2(remaining), unit));
}

double _round2(double v) => (v * 100).round() / 100;

/// 1RM tahmini (Epley) — geçmiş analizinde kullanılır.
double epley1RM(double weight, int reps) {
  if (reps <= 1) return weight;
  return weight * (1 + reps / 30.0);
}
