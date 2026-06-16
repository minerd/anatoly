import 'package:anatoly/liftoscript/runtime.dart';
import 'package:anatoly/liftoscript/value.dart';
import 'package:flutter_test/flutter_test.dart';

ScriptBindings emptyBindings() => ScriptBindings(scalars: {'rm1': const LWeight(100, 'lb')});

Object? run(String src, {ScriptBindings? b, ProgramState? state, WeightRounder? rounder}) {
  final bindings = b ?? emptyBindings();
  final st = state ?? <String, Object?>{};
  return ScriptRunner(src).run(bindings, st, rounder: rounder);
}

void main() {
  group('aritmetik', () {
    test('sayı toplama', () => expect(run('2 + 3'), 5.0));
    test('öncelik', () => expect(run('2 + 3 * 4'), 14.0));
    test('parantez', () => expect(run('(2 + 3) * 4'), 20.0));
    test('modulo', () => expect(run('7 % 3'), 1.0));
    test('unary minus', () => expect(run('-5 + 2'), -3.0));
  });

  group('ağırlık', () {
    test('weight + number', () {
      final r = run('100lb + 5');
      expect(r, const LWeight(105, 'lb'));
    });
    test('weight + weight', () {
      final r = run('100lb + 20lb');
      expect(r, const LWeight(120, 'lb'));
    });
    test('weight * number', () {
      final r = run('100lb * 0.85');
      expect(r, const LWeight(85, 'lb'));
    });
    test('kg lb karışık çevrim', () {
      // 10kg -> ~22lb; 100lb + 22 ~ 122
      final r = run('100lb + 10kg') as LWeight;
      expect(r.unit, 'lb');
      expect(r.value, closeTo(122, 1));
    });
  });

  group('yüzde', () {
    test('yüzde literal', () {
      final r = run('80%');
      expect(r, const LPercentage(80));
    });
    test('yüzde + weight (rm1 ile)', () {
      // 80% of 100lb 1RM = 80lb; + 0
      final r = run('80% + 0lb') as LWeight;
      expect(r.value, closeTo(80, 0.01));
    });
  });

  group('karşılaştırma & mantık', () {
    test('büyük', () => expect(run('5 > 3'), true));
    test('eşit weight', () => expect(run('100lb == 100lb'), true));
    test('ve', () => expect(run('5 > 3 && 2 < 1'), false));
    test('veya', () => expect(run('5 > 3 || 2 < 1'), true));
    test('not', () => expect(run('!(5 > 3)'), false));
    test('ternary', () => expect(run('5 > 3 ? 10 : 20'), 10.0));
  });

  group('if/else', () {
    test('if doğru dal', () {
      final st = <String, Object?>{};
      run('if (5 > 3) { state.x = 1 } else { state.x = 2 }', state: st);
      expect(st['x'], 1.0);
    });
    test('else if', () {
      final st = <String, Object?>{};
      run('if (1 > 3) { state.x = 1 } else if (2 > 1) { state.x = 2 } else { state.x = 3 }',
          state: st);
      expect(st['x'], 2.0);
    });
  });

  group('state', () {
    test('artırma', () {
      final st = <String, Object?>{'count': 5.0};
      run('state.count += 2', state: st);
      expect(st['count'], 7.0);
    });
    test('weight state', () {
      final st = <String, Object?>{'w': const LWeight(100, 'lb')};
      run('state.w += 5lb', state: st);
      expect(st['w'], const LWeight(105, 'lb'));
    });
  });

  group('for döngüsü', () {
    test('toplam', () {
      final b = ScriptBindings(arrays: {
        'completedReps': [5.0, 5.0, 3.0]
      }, scalars: {
        'rm1': const LWeight(100, 'lb')
      });
      final st = <String, Object?>{'total': 0.0};
      // var.i 1-based indeks: completedReps[var.i] = 5+5+3 = 13
      run('for (var.i in completedReps) { state.total += completedReps[var.i] }', b: b, state: st);
      expect(st['total'], 13.0);
    });
  });

  group('binding dizileri', () {
    test('weights[1] okuma (1-based)', () {
      final b = ScriptBindings(arrays: {
        'weights': [const LWeight(100, 'lb'), const LWeight(110, 'lb')]
      });
      expect(run('weights[1]', b: b), const LWeight(100, 'lb'));
      expect(run('weights[2]', b: b), const LWeight(110, 'lb'));
    });
    test('weights = X tüm elemanlara', () {
      final b = ScriptBindings(arrays: {
        'weights': [const LWeight(100, 'lb'), const LWeight(110, 'lb')]
      });
      run('weights = 50lb', b: b);
      expect(b.array('weights'), [const LWeight(50, 'lb'), const LWeight(50, 'lb')]);
    });
    test('weights += 5lb broadcast', () {
      final b = ScriptBindings(arrays: {
        'weights': [const LWeight(100, 'lb'), const LWeight(110, 'lb')]
      });
      run('weights += 5lb', b: b);
      expect(b.array('weights'), [const LWeight(105, 'lb'), const LWeight(115, 'lb')]);
    });
    test('karşılaştırma element-wise (completedReps >= reps)', () {
      final b = ScriptBindings(arrays: {
        'completedReps': [5.0, 5.0, 6.0],
        'reps': [5.0, 5.0, 5.0],
      });
      expect(run('completedReps >= reps', b: b), true);
      final b2 = ScriptBindings(arrays: {
        'completedReps': [5.0, 4.0, 6.0],
        'reps': [5.0, 5.0, 5.0],
      });
      expect(run('completedReps >= reps', b: b2), false);
    });
  });

  group('fonksiyonlar', () {
    test('sum dizi', () {
      final b = ScriptBindings(arrays: {
        'completedReps': [5.0, 5.0, 3.0]
      });
      expect(run('sum(completedReps)', b: b), 13.0);
    });
    test('floor/ceil/round', () {
      expect(run('floor(5.7)'), 5.0);
      expect(run('ceil(5.2)'), 6.0);
      expect(run('round(5.5)'), 6.0);
    });
    test('min/max', () {
      expect(run('min(5, 3, 8)'), 3.0);
      expect(run('max(5, 3, 8)'), 8.0);
    });
    test('calculate1RM (RPE eğrisi, referans)', () {
      // referans: 100lb x 5 = 100 / rpeMultiplier(5,10) ≈ 115.55
      final r = run('calculate1RM(100lb, 5)') as LWeight;
      expect(r.value, closeTo(115.55, 0.5));
      final r2 = run('calculate1RM(150lb, 5)') as LWeight;
      expect(r2.value, closeTo(173.35, 0.6));
    });
    test('calculateTrainingMax = 1RM * 0.9', () {
      final r = run('calculateTrainingMax(150lb, 5)') as LWeight;
      expect(r.value, closeTo(156, 1.5));
    });
    test('binary * YUVARLAMAZ (referans Weight_op)', () {
      final r = run('100 * 0.333') as double;
      expect(r, closeTo(33.3, 0.0001));
      // ham çarpım: roundTo005 olsaydı tam 33.3 olurdu; ham 33.3000...4
      expect(r, isNot(equals(33.3)));
    });
    test('roundWeight (default 2.5 lb)', () {
      final r = run('roundWeight(103lb)') as LWeight;
      expect(r.value, 102.5);
    });
    test('increment weight', () {
      final r = run('increment(100lb)') as LWeight;
      expect(r.value, 102.5);
    });
  });

  group('GZCLP benzeri progress', () {
    test('başarılı seansta ağırlık artar', () {
      final b = ScriptBindings(arrays: {
        'completedReps': [3.0, 3.0, 5.0],
        'reps': [3.0, 3.0, 3.0],
        'completedWeights': [const LWeight(100, 'lb'), const LWeight(100, 'lb'), const LWeight(100, 'lb')],
        'weights': [const LWeight(100, 'lb'), const LWeight(100, 'lb'), const LWeight(100, 'lb')],
      }, scalars: {
        'numberOfSets': 3,
        'setVariationIndex': 1,
        'rm1': const LWeight(100, 'lb'),
      });
      final st = <String, Object?>{'increase': const LWeight(10, 'lb')};
      const script = '''
if (completedReps >= reps) {
  weights = completedWeights[ns] + state.increase
} else if (setVariationIndex == 1) {
  setVariationIndex = 2
} else if (setVariationIndex == 2) {
  setVariationIndex = 3
} else {
  weights = completedWeights[ns] * 0.85
  setVariationIndex = 1
}
''';
      run(script, b: b, state: st);
      expect(b.array('weights').first, const LWeight(110, 'lb'));
      expect(b.scalar('setVariationIndex'), 1); // değişmedi
    });

    test('başarısız 5x3 -> varyasyon 2', () {
      final b = ScriptBindings(arrays: {
        'completedReps': [3.0, 3.0, 2.0],
        'reps': [3.0, 3.0, 3.0],
        'completedWeights': [const LWeight(100, 'lb'), const LWeight(100, 'lb'), const LWeight(100, 'lb')],
        'weights': [const LWeight(100, 'lb'), const LWeight(100, 'lb'), const LWeight(100, 'lb')],
      }, scalars: {
        'numberOfSets': 3,
        'setVariationIndex': 1,
        'rm1': const LWeight(100, 'lb'),
      });
      final st = <String, Object?>{'increase': const LWeight(10, 'lb')};
      const script = '''
if (completedReps >= reps) {
  weights = completedWeights[ns] + state.increase
} else if (setVariationIndex == 1) {
  setVariationIndex = 2
}
''';
      run(script, b: b, state: st);
      expect(b.scalar('setVariationIndex'), 2);
    });
  });

  group('yorumlar ve blok işaretleri', () {
    test('// yorum atlanır', () => expect(run('5 + 3 // yorum'), 8.0));
    test('{~ ~} işaretleri atlanır', () {
      final st = <String, Object?>{};
      run('{~ state.x = 1 ~}', state: st);
      expect(st['x'], 1.0);
    });
  });
}
