/// Liftoscript çalışma-zamanı değer tipleri ve aritmetiği.
///
/// Değerler: `num` (sayı), [LWeight] (ağırlık), [LPercentage] (yüzde),
/// `bool` (karşılaştırma sonucu), `List<dynamic>` (binding dizileri).
///
/// Semantik Liftosaur'un `weight.ts` + `liftoscriptEvaluator.ts` davranışını
/// birebir taklit eder (AGPL v3 — bkz. LICENSE).
library;

import 'dart:math' as math;

/// Birim: "kg" veya "lb".
class LWeight {
  final double value;
  final String unit; // "kg" | "lb"
  const LWeight(this.value, this.unit);

  @override
  String toString() => '${_n(value)}$unit';

  @override
  bool operator ==(Object other) =>
      other is LWeight && other.value == value && other.unit == unit;
  @override
  int get hashCode => Object.hash(value, unit);

  LWeight copyWith({double? value, String? unit}) =>
      LWeight(value ?? this.value, unit ?? this.unit);
}

/// Yüzde değeri (ör. 80%).
class LPercentage {
  final double value;
  const LPercentage(this.value);
  @override
  String toString() => '${_n(value)}%';
  @override
  bool operator ==(Object other) => other is LPercentage && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

String _n(num v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toString();
}

/// Referans MathUtils_roundTo005: 0.05'e yuvarlar (0.005 değil).
double roundTo005(double v) => (v * 20).round() / 20.0;
double roundFloat(double v, int digits) {
  final f = math.pow(10, digits);
  return (v * f).round() / f;
}

/// kg/lb dönüşümü (Liftosaur: ×2.205 / 0.5'e yuvarla).
LWeight weightConvertTo(LWeight w, String unit) {
  if (w.unit == unit) return w;
  if (w.unit == 'kg' && unit == 'lb') {
    return LWeight((((w.value * 2.205) / 0.5).round() * 0.5), unit);
  } else if (w.unit == 'lb' && unit == 'kg') {
    return LWeight((((w.value / 2.205) / 0.5).round() * 0.5), unit);
  }
  return LWeight(w.value, unit);
}

bool _isNum(Object? v) => v is num;
bool _isWeight(Object? v) => v is LWeight;
bool _isPct(Object? v) => v is LPercentage;

/// İki skaler değer arasında ikili operasyon (Weight_op taklidi).
/// [onerm] 1RM (yüzdeleri ağırlığa çevirmek için, opsiyonel).
Object applyArith(
  Object? a,
  Object? b,
  double Function(double, double) op, {
  LWeight? onerm,
}) {
  a ??= 0;
  b ??= 0;
  if (_isNum(a) && _isNum(b)) return op((a as num).toDouble(), (b as num).toDouble());
  if (_isNum(a) && _isPct(b)) return LPercentage(op((a as num).toDouble(), (b as LPercentage).value));
  if (_isNum(a) && _isWeight(b)) return _weightOp((a as num).toDouble(), b as LWeight, op);

  if (_isPct(a) && _isNum(b)) return LPercentage(op((a as LPercentage).value, (b as num).toDouble()));
  if (_isPct(a) && _isPct(b)) {
    return LPercentage(op((a as LPercentage).value, (b as LPercentage).value));
  }
  if (_isPct(a) && _isWeight(b)) {
    final pct = (a as LPercentage).value;
    final aw = onerm != null
        ? LWeight(roundFloat(onerm.value * pct / 100, 4), onerm.unit)
        : roundFloat(pct / 100, 4);
    return _weightOp(aw, b as LWeight, op);
  }

  if (_isWeight(a) && _isNum(b)) return _weightOp(a as LWeight, (b as num).toDouble(), op);
  if (_isWeight(a) && _isPct(b)) {
    final pct = (b as LPercentage).value;
    final bw = onerm != null
        ? LWeight(roundFloat(onerm.value * pct / 100, 4), onerm.unit)
        : roundFloat(pct / 100, 4);
    return _weightOp(a as LWeight, bw, op);
  }
  if (_isWeight(a) && _isWeight(b)) return _weightOp(a as LWeight, b as LWeight, op);

  throw StateError('Bu değerlere işlem uygulanamaz: $a, $b');
}

/// Weight_operation taklidi — sonuç daima ağırlık (sayısal olmayan operand'ın birimi).
LWeight _weightOp(Object a, Object b, double Function(double, double) op) {
  if (a is num && b is LWeight) return LWeight(op(a.toDouble(), b.value), b.unit);
  if (a is LWeight && b is num) return LWeight(op(a.value, b.toDouble()), a.unit);
  if (a is LWeight && b is LWeight) {
    return LWeight(op(a.value, weightConvertTo(b, a.unit).value), a.unit);
  }
  throw StateError('Weight_operation yalnız sayılarla çalışmaz');
}

double _toComparable(Object? v, String? targetUnit) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  if (v is LPercentage) return v.value;
  if (v is LWeight) {
    if (targetUnit != null) return weightConvertTo(v, targetUnit).value;
    return v.value;
  }
  return 0;
}

/// Skaler karşılaştırma (Weight_gt vb. taklidi).
bool compareScalar(Object? l, Object? r, String op) {
  String? unit;
  if (l is LWeight) {
    unit = l.unit;
  } else if (r is LWeight) {
    unit = r.unit;
  }
  final a = _toComparable(l, unit);
  final b = _toComparable(r, unit);
  switch (op) {
    case '>':
      return a > b;
    case '<':
      return a < b;
    case '>=':
      return a >= b;
    case '<=':
      return a <= b;
    case '==':
      return a == b;
    case '!=':
      return a != b;
  }
  throw StateError('Bilinmeyen karşılaştırma: $op');
}

/// Dizi farkındalıklı karşılaştırma (comparing() taklidi — element-wise `every`).
bool comparing(Object? left, Object? right, String op) {
  final lArr = left is List;
  final rArr = right is List;
  if (lArr && rArr) {
    final l = left;
    final r = right;
    for (var i = 0; i < l.length; i++) {
      if (!compareScalar(l[i] ?? 0, (i < r.length ? r[i] : null) ?? 0, op)) return false;
    }
    return true;
  } else if (lArr && !rArr) {
    for (final l in (left)) {
      if (!compareScalar(l ?? 0, right ?? 0, op)) return false;
    }
    return true;
  } else if (!lArr && rArr) {
    for (final r in (right)) {
      if (!compareScalar(left ?? 0, r ?? 0, op)) return false;
    }
    return true;
  } else {
    return compareScalar(left ?? 0, right ?? 0, op);
  }
}

/// Değeri boolean'a çevir (0/null = false).
bool toBool(Object? v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v == null) return false;
  if (v is LWeight) return v.value != 0;
  if (v is LPercentage) return v.value != 0;
  if (v is List) return v.isNotEmpty;
  return true;
}
