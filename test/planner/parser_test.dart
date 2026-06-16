import 'dart:convert';
import 'dart:io';

import 'package:anatoly/planner/planner_parser.dart';
import 'package:anatoly/planner/program_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final programs = (jsonDecode(File('assets/programs.json').readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();

  test('tüm built-in programlar hatasız parse olur', () {
    final failures = <String>[];
    var totalDays = 0;
    var totalExercises = 0;
    for (final p in programs) {
      try {
        final parsed = PlannerParser.parse(p['script'] as String);
        totalDays += parsed.totalDays;
        for (final w in parsed.weeks) {
          for (final d in w.days) {
            totalExercises += d.exercises.length;
          }
        }
      } catch (e) {
        failures.add('${p['id']}: $e');
      }
    }
    // ignore: avoid_print
    print('Parse edildi: ${programs.length} program, $totalDays gün, $totalExercises egzersiz');
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('basicBeginner doğru yapıda', () {
    final p = programs.firstWhere((e) => e['id'] == 'basicBeginner');
    final parsed = PlannerParser.parse(p['script'] as String);
    expect(parsed.weeks.length, 1);
    final days = parsed.weeks.first.days;
    expect(days.length, 2); // Workout A, Workout B
    expect(days[0].name, 'Workout A');
    // Workout A: Bent Over Row, Bench Press, Squat (main 'used:none' hariç)
    final names = days[0].exercises.map((e) => e.name).toList();
    expect(names, containsAll(['Bent Over Row', 'Bench Press', 'Squat']));
    expect(names, isNot(contains('main'))); // şablon dahil değil
    // Squat reuse main'den 2x5,1x5+ = 3 set almalı
    final squat = days[0].exercises.firstWhere((e) => e.name == 'Squat');
    expect(squat.setVariations.isNotEmpty, true);
    expect(squat.setVariations.first.length, 3);
    expect(squat.setVariations.first.last.isAmrap, true);
    expect(squat.progress?.type, 'custom');
  });

  test('gzclp çok haftalı ve etiketli', () {
    final p = programs.firstWhere((e) => e['id'] == 'gzclp');
    final parsed = PlannerParser.parse(p['script'] as String);
    expect(parsed.weeks.isNotEmpty, true);
    final firstDay = parsed.weeks.first.days.first;
    expect(firstDay.exercises.any((e) => e.label == 't1'), true);
  });

  test('gzclp t1 ÇOKLU set varyasyonuna sahip (stall protokolü)', () {
    final p = programs.firstWhere((e) => e['id'] == 'gzclp');
    final parsed = PlannerParser.parse(p['script'] as String);
    final t1 = parsed.weeks.first.days.first.exercises.firstWhere((e) => e.label == 't1');
    // t1 şablonu: 4x3,1x3+ / 5x2,1x2+ / 9x1,1x1+ / 1x5 (5RM Test) = 4 varyasyon
    expect(t1.setVariations.length, 4, reason: 'reuse ile 4 varyasyon gelmeli');
    expect(t1.setVariations[0].length, 5); // 4x3 + 1x3+
    expect(t1.setVariations[1].length, 6); // 5x2 + 1x2+
    expect(t1.setVariations[2].length, 10); // 9x1 + 1x1+
    expect(t1.setVariations[0].last.isAmrap, true);
    expect(t1.progress?.type, 'custom');
    expect(t1.progress?.script, isNotNull);
  });

  test('madcow: sahte egzersiz yok, gerçek egzersizler set alıyor', () {
    final p = programs.firstWhere((e) => e['id'] == 'madcow');
    final parsed = PlannerParser.parse(p['script'] as String);
    final wa = parsed.weeks.first.days.first; // Workout A
    final names = wa.exercises.map((e) => e.name).toList();
    // script gövdesinden sızan sahte isimler olmamalı
    expect(names.any((n) => n.contains('if ') || n.contains('}') || n.contains('weights')),
        false,
        reason: 'script satırları egzersiz olmamalı: $names');
    // ...main[1] reuse ile Squat/Bench/Row set almalı
    final squat = wa.exercises.firstWhere((e) => e.name == 'Squat');
    expect(squat.setVariations.isNotEmpty, true, reason: 'Squat reuse ile set almalı');
    expect(squat.setVariations.first.length, 5); // main[1]: 5 set (40-85%)
  });

  test('smolov-jr: ad köşeli-parantezsiz, çok-haftalı doldurulmuş', () {
    final p = programs.firstWhere((e) => e['id'] == 'smolov-jr');
    final parsed = PlannerParser.parse(p['script'] as String);
    // hiçbir egzersiz adında [1-N] kalıntısı olmamalı
    for (final w in parsed.weeks) {
      for (final d in w.days) {
        for (final e in d.exercises) {
          expect(e.name.contains('['), false, reason: 'ad temiz olmalı: ${e.name}');
        }
      }
    }
    // çok haftalıysa 2. hafta boş olmamalı (fillRepeats)
    if (parsed.weeks.length >= 2) {
      final week2HasEx = parsed.weeks[1].days.any((d) => d.exercises.isNotEmpty);
      expect(week2HasEx, true, reason: '2. hafta fillRepeats ile dolu olmalı');
    }
  });

  test('sheiko: halting/block etiketleri çözülüyor, ad temiz', () {
    final p = programs.firstWhere((e) => e['id'] == 'sheiko-29-32');
    final parsed = PlannerParser.parse(p['script'] as String);
    final allEx = [for (final w in parsed.weeks) for (final d in w.days) ...d.exercises];
    // 'halting:' veya 'block:' adın içinde kalmamalı
    final polluted = allEx.where((e) => e.name.contains(':')).toList();
    expect(polluted, isEmpty, reason: 'etiketler addan ayrılmalı: ${polluted.map((e) => e.name)}');
  });

  test('gzclp t2 3 varyasyon (3x10/3x8/3x6)', () {
    final p = programs.firstWhere((e) => e['id'] == 'gzclp');
    final parsed = PlannerParser.parse(p['script'] as String);
    // t2 ilk Day1'de Bench Press
    ProgramExerciseDef? t2;
    for (final w in parsed.weeks) {
      for (final d in w.days) {
        for (final e in d.exercises) {
          if (e.label == 't2') { t2 = e; break; }
        }
      }
    }
    expect(t2, isNotNull);
    expect(t2!.setVariations.length, 3);
  });
}
