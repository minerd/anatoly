import 'dart:convert';
import 'dart:io';

import 'package:anatoly/domain/models.dart';
import 'package:anatoly/planner/program_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final exercises = (jsonDecode(File('assets/exercises.json').readAsStringSync()) as List)
      .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
      .toList();
  final programs = (jsonDecode(File('assets/programs.json').readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();

  Map<String, dynamic> prog(String id) => programs.firstWhere((e) => e['id'] == id);

  test('basicBeginner klonla → gün üret → tamamla → ağırlık artar', () {
    final settings = Settings(units: 'lb');
    final svc = ProgramService(exercises, settings);
    final program = svc.clone(prog('basicBeginner'));

    final day1 = svc.generateDay(program, 1);
    expect(day1.entries.isNotEmpty, true);
    final squat = day1.entries.firstWhere((e) => e.exerciseName == 'Squat');
    expect(squat.sets.length, 3);
    final startWeight = squat.sets.first.weight!.value;

    // tüm setleri başarıyla tamamla
    for (final s in squat.sets) {
      s.completed = true;
      s.completedReps = (s.reps ?? 5) + (s.isAmrap ? 3 : 0);
      s.completedWeight = s.weight;
    }
    // diğer egzersizler de tamamlanmış sayılsın
    for (final e in day1.entries) {
      for (final s in e.sets) {
        s.completed = true;
        s.completedReps = s.reps;
        s.completedWeight = s.weight;
      }
    }

    svc.applyProgression(program, day1);
    // Squat custom progress: increase 5lb -> sonraki ağırlık artmalı
    final rt = program.runtime[squat.programExerciseKey];
    expect(rt, isNotNull);
    expect(rt!.weights.first!.value, greaterThan(startWeight));
    // gün ilerledi
    expect(program.nextDay, 2);
  });

  test('GZCLP stall protokolü: başarısız set → varyasyon ilerler → set şeması değişir', () {
    final settings = Settings(units: 'lb');
    final svc = ProgramService(exercises, settings);
    final program = svc.clone(prog('gzclp'));

    // Day 1 t1 (Squat): varyasyon 1 = 4x3,1x3+ = 5 set
    final day1 = svc.generateDay(program, 1);
    final t1 = day1.entries.firstWhere((e) => e.label == 't1');
    expect(t1.sets.length, 5, reason: 'varyasyon 1: 5 set');
    final key = t1.programExerciseKey!;
    expect(program.runtime[key]!.setVariationIndex, 1);

    // setleri BAŞARISIZ tamamla (hedefin altında)
    for (final s in t1.sets) {
      s.completed = true;
      s.completedReps = 1; // hedef 3, başarısız
      s.completedWeight = s.weight;
    }
    svc.applyProgression(program, day1);
    // stall: setVariationIndex 1 -> 2
    expect(program.runtime[key]!.setVariationIndex, 2,
        reason: 'başarısızlıkta sonraki stage');

    // aynı günü yeniden üret: artık varyasyon 2 = 5x2,1x2+ = 6 set
    final day1b = svc.generateDay(program, 1);
    final t1b = day1b.entries.firstWhere((e) => e.label == 't1');
    expect(t1b.sets.length, 6, reason: 'varyasyon 2: 6 set');
  });

  test('yüzde-bazlı program (531) boş bar değil, anlamlı ağırlık üretir', () {
    final settings = Settings(units: 'lb');
    final svc = ProgramService(exercises, settings);
    final program = svc.clone(prog('the531bbb'));
    final day = svc.generateDay(program, 1);
    expect(day.entries.isNotEmpty, true);
    // ana barbell egzersizlerinden en az biri bardan ağır olmalı (45lb)
    final hasRealWeight = day.entries.any((e) =>
        e.sets.any((s) => (s.weight?.value ?? 0) > 45));
    expect(hasRealWeight, true,
        reason: 'yüzde-bazlı program boş bar üretmemeli');
  });

  test('", Ekipman" sözdizimi: phul ekipman ekini ad+ekipmana ayırır', () {
    final settings = Settings(units: 'lb');
    final svc = ProgramService(exercises, settings);
    final program = svc.clone(prog('phul'));
    // Day 1 (Upper Power): Incline Bench Press, Dumbbell / Bicep Curl, Barbell
    final rec = svc.generateDay(program, 1);
    // hiçbir egzersiz adı virgül içermemeli (ekipman ayrılmış olmalı)
    for (final e in rec.entries) {
      expect(e.exerciseName.contains(', '), false,
          reason: 'ekipman eki addan ayrılmalı: ${e.exerciseName}');
    }
    final incline = rec.entries.firstWhere((e) => e.exerciseName == 'Incline Bench Press');
    expect(incline.exercise.equipment, 'dumbbell');
    expect(incline.sets.first.weight!.value, closeTo(35, 2.5)); // 35lb dumbbell, bara yükselmedi
  });

  test('ss1 lp deload: 2 ardışık başarısızlıkta ağırlık düşer (Deadlift 95lb)', () {
    final settings = Settings(units: 'lb');
    final svc = ProgramService(exercises, settings);
    final program = svc.clone(prog('ss1'));
    final d1 = svc.generateDay(program, 1);
    // Deadlift 95lb (bardan ağır, deload edilebilir)
    final dl = d1.entries.firstWhere((e) => e.exerciseName == 'Deadlift');
    final key = dl.programExerciseKey!;
    final startW = dl.sets.first.weight!.value;
    expect(startW, greaterThan(45));

    void failOnce(WorkoutRecord rec) {
      final e = rec.entries.firstWhere((x) => x.programExerciseKey == key);
      for (final s in e.sets) {
        s.completed = true;
        s.completedReps = 1; // hedef 5, başarısız
        s.completedWeight = s.weight;
      }
      svc.applyProgression(program, rec);
    }

    failOnce(d1);
    expect(program.runtime[key]!.weights.first!.value, startW, reason: '1 başarısızlıkta düşmez');
    failOnce(svc.generateDay(program, 1));
    expect(program.runtime[key]!.weights.first!.value, lessThan(startW),
        reason: '2 ardışık başarısızlıkta %10 deload');
  });

  test('yüzde-bazlı: rm1 artınca set ağırlığı yeniden çözülür (artar)', () {
    final settings = Settings(units: 'lb');
    final svc = ProgramService(exercises, settings);
    final program = svc.clone(prog('the531bbb'));
    final d1 = svc.generateDay(program, 1);
    // yüzde-bazlı bir egzersiz bul
    final entry = d1.entries.firstWhere(
        (e) => e.programExerciseKey != null && e.sets.any((s) => (s.weight?.value ?? 0) > 45),
        orElse: () => d1.entries.first);
    final key = entry.programExerciseKey!;
    final before = entry.sets.first.weight!.value;
    // rm1'i elle yükselt (script ilerlemesini simüle et)
    final rt = program.runtime[key]!;
    final rm1 = rt.state['rm1'];
    if (rm1 is LWeight) {
      rt.state['rm1'] = LWeight(rm1.value + 50, rm1.unit);
      final d1b = svc.generateDay(program, 1);
      final entry2 = d1b.entries.firstWhere((e) => e.programExerciseKey == key);
      expect(entry2.sets.first.weight!.value, greaterThan(before),
          reason: 'rm1 artınca yüzde ağırlığı artmalı');
    }
  });

  test('dp double-progression: ilk seans minReps, tavanda ağırlık artar', () {
    final settings = Settings(units: 'lb');
    final svc = ProgramService(exercises, settings);
    final program = svc.clone(prog('phul'));
    // Leg Press / 4x10 / dp(5lb, 10, 15) — minReps 10, maxReps 15
    WorkoutEntry? findLegPress() {
      for (var d = 1; d <= 4; d++) {
        final rec = svc.generateDay(program, d);
        final e = rec.entries.where((x) => x.exerciseName == 'Leg Press').firstOrNull;
        if (e != null) return e;
      }
      return null;
    }

    final lp = findLegPress();
    expect(lp, isNotNull);
    // ilk seans hedefi minReps (10) olmalı, maxReps (15) değil
    expect(lp!.sets.first.reps, 10, reason: 'dp ilk seans minReps göstermeli');
    final key = lp.programExerciseKey!;
    final startW = lp.sets.first.weight!.value;

    // minReps'ten maxReps'e: her seansta tekrar artar, ağırlık sabit
    var guard = 0;
    while (guard++ < 10) {
      // bu egzersizi içeren günü üret
      WorkoutRecord? rec;
      for (var d = 1; d <= 4; d++) {
        final r = svc.generateDay(program, d);
        if (r.entries.any((e) => e.programExerciseKey == key)) {
          rec = r;
          break;
        }
      }
      final e = rec!.entries.firstWhere((x) => x.programExerciseKey == key);
      final target = e.sets.first.reps!;
      for (final s in e.sets) {
        s.completed = true;
        s.completedReps = target; // hedefi tam yap
        s.completedWeight = s.weight;
      }
      svc.applyProgression(program, rec);
      if (target >= 15) break; // tavana ulaşıldı
    }
    // tavandan sonra ağırlık artmış, tekrar minReps'e dönmüş olmalı
    final rt = program.runtime[key]!;
    expect(rt.weights.first!.value, greaterThan(startW),
        reason: 'maxReps tavanında ağırlık artmalı');
    expect((rt.state['dpReps'] as num).toInt(), 10, reason: 'tavandan sonra minReps reset');
  });

  test('1RM ayarla: rm1 set + ağırlık temizle -> her modda yeniden çözülür', () {
    final settings = Settings(units: 'lb');
    final svc = ProgramService(exercises, settings);
    final program = svc.clone(prog('the531bbb'));
    final d1 = svc.generateDay(program, 1);
    // yüzde-bazlı bir egzersiz (bardan ağır) bul
    final entry = d1.entries.firstWhere(
        (e) => e.programExerciseKey != null && e.sets.any((s) => (s.weight?.value ?? 0) > 45),
        orElse: () => d1.entries.first);
    final key = entry.programExerciseKey!;
    final before = entry.sets.last.weight!.value;

    // setExerciseRm1'in yaptığını uygula: rm1 = 200, _wRm1 temizle, weights temizle
    final rt = program.runtime[key]!;
    rt.state['rm1'] = const LWeight(200, 'lb');
    rt.state.remove('_wRm1');
    rt.weights = [];

    final d1b = svc.generateDay(program, 1);
    final entry2 = d1b.entries.firstWhere((e) => e.programExerciseKey == key);
    final after = entry2.sets.last.weight!.value;
    expect(after, greaterThan(before),
        reason: '1RM 200 ayarlanınca yüzde ağırlığı yeniden çözülüp artmalı (before=$before after=$after)');
  });

  test('531 haftalık dalga: hafta 1 ve hafta 2 ana lift şeması/ağırlığı farklı', () {
    final settings = Settings(units: 'lb');
    final svc = ProgramService(exercises, settings);
    final program = svc.clone(prog('the531bbb'));
    // 4 gün/hafta varsayımıyla: gün 1 (hafta 1) vs gün 5 (hafta 2) aynı lift
    final w1d1 = svc.generateDay(program, 1);
    final w2d1 = svc.generateDay(program, 5);
    // aynı programExerciseKey'e sahip ana lifti bul
    for (final e1 in w1d1.entries) {
      final e2 = w2d1.entries
          .where((x) => x.programExerciseKey == e1.programExerciseKey)
          .firstOrNull;
      if (e2 == null) continue;
      // ana set ağırlığı (yüzde-bazlı) hafta 2'de farklı olmalı VEYA rep şeması farklı
      final w1 = e1.sets.isNotEmpty ? e1.sets.last.weight?.value : null;
      final w2 = e2.sets.isNotEmpty ? e2.sets.last.weight?.value : null;
      final repsDiffer = e1.sets.map((s) => s.reps).join(',') !=
          e2.sets.map((s) => s.reps).join(',');
      if ((w1 != null && w2 != null && w1 != w2) || repsDiffer) {
        // dalga uygulanıyor
        return;
      }
    }
    fail('531 hafta 1 ve hafta 2 özdeş — haftalık dalga uygulanmıyor');
  });

  test('sheiko undulation: aynı egzersiz farklı günlerde farklı yüzde ağırlığı', () {
    final settings = Settings(units: 'lb');
    final svc = ProgramService(exercises, settings);
    final program = svc.clone(prog('sheiko-29-32'));
    // birkaç günü üret, en sık görülen egzersizin ağırlıklarını topla
    final weightsByName = <String, Set<double>>{};
    for (var d = 1; d <= 8; d++) {
      final rec = svc.generateDay(program, d);
      for (final e in rec.entries) {
        for (final s in e.sets) {
          if (s.weight != null) {
            (weightsByName[e.exerciseName] ??= {}).add(s.weight!.value);
          }
        }
      }
    }
    // en az bir egzersiz birden fazla farklı ağırlık görmeli (undulation)
    final hasUndulation = weightsByName.values.any((set) => set.length > 1);
    expect(hasUndulation, true,
        reason: 'yüzde-bazlı sheiko günlere göre farklı ağırlık üretmeli: $weightsByName');
  });

  test('çapraz-instance: texas/smolov tam döngüde ana lift ilerler', () {
    for (final id in ['texasmethod', 'smolov-jr']) {
      final settings = Settings(units: 'lb');
      final svc = ProgramService(exercises, settings);
      final program = svc.clone(prog(id));
      final parsed0 = svc.generateDay(program, 1);
      final total = parsed0.entries.isEmpty ? 0 : null; // sadece kontrol
      expect(total, null);

      // başlangıç: en ağır barbell egzersizinin ağırlığı (paylaşılan key)
      String? trackKey;
      double startW = 0;
      for (final e in parsed0.entries) {
        final double w = e.sets.isNotEmpty ? (e.sets.first.weight?.value ?? 0).toDouble() : 0.0;
        if (w > startW) {
          startW = w;
          trackKey = e.programExerciseKey;
        }
      }
      expect(trackKey, isNotNull, reason: '$id izlenecek lift bulunamadı');

      // bir tam döngü: tüm günleri başarıyla tamamla
      final dayCount = 12; // güvenli üst sınır; nextDay döngüsel
      for (var i = 0; i < dayCount; i++) {
        final rec = svc.generateDay(program, program.nextDay);
        for (final e in rec.entries) {
          for (final s in e.sets) {
            s.completed = true;
            s.completedReps = (s.reps ?? 5) + (s.isAmrap ? 2 : 0);
            s.completedWeight = s.weight;
          }
        }
        svc.applyProgression(program, rec);
      }

      // döngü sonunda izlenen liftin ağırlığı artmış olmalı (rm1 veya weights)
      final rt = program.runtime[trackKey];
      final endW = rt != null && rt.weights.isNotEmpty
          ? (rt.weights.firstWhere((w) => w != null, orElse: () => null)?.value ?? 0)
          : 0;
      final rm1 = rt?.state['rm1'];
      final rm1Val = rm1 is LWeight ? rm1.value : 0;
      expect(endW > startW || rm1Val > startW, true,
          reason: '$id: tam döngüde ana lift ilerlemeli (start=$startW end=$endW rm1=$rm1Val)');
    }
  });

  test('5 popüler program gün üretebiliyor', () {
    final settings = Settings(units: 'lb');
    final svc = ProgramService(exercises, settings);
    for (final id in ['gzclp', 'ss1', 'phul', 'nsuns', 'the531bbb']) {
      final program = svc.clone(prog(id));
      final day = svc.generateDay(program, 1);
      expect(day.entries.isNotEmpty, true, reason: '$id boş gün üretti');
    }
  });
}
