/// Program servisi: klonlama, gün → workout üretimi, progresyon uygulama.
library;

import '../domain/models.dart';
import '../domain/plates.dart';
import '../liftoscript/runtime.dart';
import '../liftoscript/value.dart';
import 'planner_parser.dart';
import 'program_models.dart';

class ProgramService {
  final Map<String, Exercise> catalog; // isim/normalize -> egzersiz
  final Settings settings;

  ProgramService(List<Exercise> exercises, this.settings)
      : catalog = {for (final e in exercises) _norm(e.name): e};

  static String _norm(String s) => s.toLowerCase().trim();

  Exercise? findExercise(String name) {
    final e = catalog[_norm(name)];
    if (e != null) return e;
    // gevşek eşleşme
    for (final entry in catalog.entries) {
      if (entry.key.replaceAll(' ', '') == _norm(name).replaceAll(' ', '')) {
        return entry.value;
      }
    }
    return null;
  }

  /// Built-in program JSON'undan kullanıcı kütüphanesine kopya üretir.
  StoredProgram clone(Map<String, dynamic> programJson) {
    final id = '${programJson['id']}-${DateTime.now().millisecondsSinceEpoch}';
    return StoredProgram(
      id: id,
      name: programJson['name'] as String,
      author: (programJson['author'] as String?) ?? '',
      description: (programJson['description'] as String?) ?? '',
      plannerText: programJson['script'] as String,
      nextDay: 1,
    );
  }

  /// Boş program oluştur.
  StoredProgram createEmpty(String name) {
    return StoredProgram(
      id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      plannerText: '# Week 1\n## Day 1\n',
      nextDay: 1,
    );
  }

  EquipmentData _equipmentFor(Exercise? ex, String? overrideEquip) {
    final key = overrideEquip ?? ex?.defaultEquipment ?? 'barbell';
    return settings.equipment[key] ?? settings.equipment['barbell']!;
  }

  WeightRounder _rounderFor(Exercise? ex, String? equip) {
    final eq = _equipmentFor(ex, equip);
    return (LWeight w, String unit) => roundToEquipment(w, eq, unit);
  }

  /// Belirli (1-based) gün için workout kaydı üret. Runtime'ı ilk kez başlatır.
  WorkoutRecord generateDay(StoredProgram program, int dayNumber) {
    final parsed = PlannerParser.parse(program.plannerText);
    final flat = parsed.flatDays();
    if (flat.isEmpty) {
      return WorkoutRecord(
        id: DateTime.now().millisecondsSinceEpoch,
        startTime: DateTime.now().millisecondsSinceEpoch,
        programId: program.id,
        programName: program.name,
        dayName: 'Boş',
      );
    }
    final idx = ((dayNumber - 1) % flat.length);
    final dayInfo = flat[idx];
    final now = DateTime.now().millisecondsSinceEpoch;
    final record = WorkoutRecord(
      id: now,
      startTime: now,
      programId: program.id,
      programName: program.name,
      day: dayNumber,
      week: dayInfo.week,
      dayName: dayInfo.day.name,
    );

    for (final exDef in dayInfo.day.exercises) {
      if (exDef.notUsed) continue;
      final ex = findExercise(exDef.name);
      final exType = ExerciseType(ex?.id ?? exDef.name, exDef.equipment ?? ex?.defaultEquipment);
      final unit = settings.units;
      final eq = _equipmentFor(ex, exDef.equipment);

      // runtime başlat
      final rt = program.runtime.putIfAbsent(exDef.key, () => ExerciseRuntime());
      final variation = _currentVariation(exDef, rt);

      // Ağırlık çözümü.
      // - "Yüzde modu" (yüzde setleri VE progress `weights` yazmıyor): her gün/hafta
      //   kendi yüzdesinden GÜNCEL rm1 ile taze çözülür. Böylece sheiko undulation,
      //   nsuns/531 rm1 ilerlemesi her seans doğru ağırlık verir.
      // - Aksi halde (lp/dp/sum veya `weights +=` yapan custom, ör. GZCLP/madcow):
      //   progresyonun mutasyona uğrattığı rt.weights kullanılır.
      final hasPct = variation.any((p) => p.weight is LPercentage);
      final writesWeights = exDef.progress != null &&
          (exDef.progress!.type == 'lp' ||
              exDef.progress!.type == 'dp' ||
              exDef.progress!.type == 'sum' ||
              (exDef.progress!.type == 'custom' &&
                  _scriptWritesWeights(exDef.progress!.script)));
      final percentageMode = hasPct && !writesWeights;

      if (percentageMode) {
        rt.weights = List<LWeight?>.generate(
          variation.length,
          (i) => _resolveWeight(variation[i], ex, rt, unit, eq),
        );
      } else if (rt.weights.isEmpty) {
        rt.weights = List<LWeight?>.generate(
          variation.length,
          (i) => _resolveWeight(variation[i], ex, rt, unit, eq),
        );
      } else if (rt.weights.length != variation.length) {
        // varyasyon değişti (ör. GZCLP 5x3 -> 6x2). Bu dal yalnız MUTLAK mod
        // (writesWeights / yüzdesiz) için çalışır; progresyonun mutasyona uğrattığı
        // ağırlığı KORU (yeniden çözüm artışı silerdi), yeni setlere son ağırlığı taşı.
        final carry = rt.weights.lastWhere((w) => w != null,
            orElse: () => rt.weights.isNotEmpty ? rt.weights.first : null);
        rt.weights = List<LWeight?>.generate(variation.length, (i) {
          if (i < rt.weights.length && rt.weights[i] != null) return rt.weights[i];
          return carry ?? _resolveWeight(variation[i], ex, rt, unit, eq);
        });
      }

      final entry = WorkoutEntry(
        exercise: exType,
        exerciseName: ex?.name ?? exDef.name,
        label: exDef.label,
        programExerciseKey: exDef.key,
        supersetName: exDef.supersetName,
      );

      // double-progression hedefi: runtime'da tutulan güncel tekrar. İlk seansta
      // dpReps yoksa minReps'e seed et (8-12 şemasında ilk hedef 8 olmalı, 12 değil) —
      // böylece generateDay ile _runProgress'in başlangıcı tutarlı.
      int? dpTarget;
      if (exDef.progress?.type == 'dp') {
        if (rt.state['dpReps'] == null) {
          final args = exDef.progress!.args;
          final argMin = (args['arg1'] as num?)?.toInt();
          final schemeMin = variation.isNotEmpty
              ? (variation.first.minReps ?? variation.first.maxReps)
              : null;
          rt.state['dpReps'] = argMin ?? schemeMin ?? 1;
        }
        dpTarget = (rt.state['dpReps'] as num?)?.toInt();
      }

      for (var i = 0; i < variation.length; i++) {
        final ps = variation[i];
        final LWeight? w = (rt.weights.length > i ? rt.weights[i] : null) ??
            _resolveWeight(ps, ex, rt, unit, eq);
        entry.sets.add(WorkoutSet(
          reps: dpTarget ?? ps.minReps ?? ps.maxReps,
          minReps: ps.minReps,
          weight: w,
          originalWeight: ps.weight,
          rpe: ps.rpe,
          timer: ps.timer ?? settings.workoutTimer,
          isAmrap: ps.isAmrap,
          logRpe: ps.logRpe,
          askWeight: ps.askWeight,
        ));
      }

      // warmup setleri: EN AĞIR çalışma setine göre (rampalı şemada ilk set en hafif).
      // Sabit ekipmanda (dumbbell/kettlebell) ya da plakasız ekipmanda warmup üretme.
      LWeight? topWeight;
      for (final s in entry.sets) {
        final sw = s.weight;
        if (sw != null && (topWeight == null || sw.value > topWeight.value)) topWeight = sw;
      }
      if (topWeight != null && !eq.isFixed && eq.plates.isNotEmpty && topWeight.value > eq.bar.value) {
        entry.warmupSets.addAll(_warmups(topWeight, eq, unit));
      }

      record.entries.add(entry);
    }
    return record;
  }

  List<PSet> _currentVariation(ProgramExerciseDef exDef, ExerciseRuntime rt) {
    if (exDef.setVariations.isEmpty) return const [];
    final i = (rt.setVariationIndex - 1).clamp(0, exDef.setVariations.length - 1);
    return exDef.setVariations[i];
  }

  LWeight? _resolveWeight(PSet ps, Exercise? ex, ExerciseRuntime rt, String unit, EquipmentData eq) {
    final w = ps.weight;
    if (w is LWeight) return roundToEquipment(w, eq, unit);
    if (w is LPercentage) {
      // rm1/training max state'ten; yoksa başlangıç ağırlığını taban al ve
      // kalıcı yap (ilk seans ile sonraki seanslar tutarlı olsun, script rm1'i ilerletsin).
      var rm1 = rt.state['rm1'];
      if (rm1 is! LWeight) {
        rm1 = LWeight(ex?.startingWeight(unit) ?? 0, unit);
        if ((rm1).value > 0) rt.state['rm1'] = rm1;
      }
      final base = weightConvertTo(rm1, unit);
      return roundToEquipment(LWeight(base.value * w.value / 100, unit), eq, unit);
    }
    // ağırlık yok: başlangıç ağırlığı
    if (ex != null) {
      return roundToEquipment(LWeight(ex.startingWeight(unit), unit), eq, unit);
    }
    return LWeight(0, unit);
  }

  List<WorkoutSet> _warmups(LWeight top, EquipmentData eq, String unit) {
    final bar = weightConvertTo(eq.bar, unit);
    final sets = <WorkoutSet>[];
    void add(double frac, int reps) {
      var w = LWeight(top.value * frac, unit);
      w = roundToEquipment(w, eq, unit);
      if (w.value <= bar.value) w = bar;
      if (sets.any((s) => s.weight?.value == w.value)) return;
      sets.add(WorkoutSet(reps: reps, weight: w, isWarmup: true, timer: settings.warmupTimer));
    }

    if (top.value > bar.value * 1.5) {
      add(0.0, 8); // boş bar (frac 0 -> bar)
      add(0.5, 5);
      add(0.7, 3);
      add(0.85, 2);
    }
    return sets;
  }

  /// Workout bitince progresyonu uygular ve nextDay'i ilerletir.
  void applyProgression(StoredProgram program, WorkoutRecord record) {
    final parsed = PlannerParser.parse(program.plannerText);
    final flat = parsed.flatDays();
    final week = record.week ?? 1;
    final day = record.day;
    int dayInWeek = 1;
    if (flat.isNotEmpty) {
      final idx = ((record.day - 1) % flat.length);
      dayInWeek = flat[idx].dayInWeek;
    }
    for (final entry in record.entries) {
      final key = entry.programExerciseKey;
      if (key == null) continue;
      final exDef = _findDef(parsed, key);
      if (exDef == null || exDef.progress == null) continue;
      final rt = program.runtime[key];
      if (rt == null) continue;
      _runProgress(exDef, rt, entry, week: week, day: day, dayInWeek: dayInWeek);
    }
    // gün ilerlet
    final total = parsed.totalDays;
    if (total > 0) {
      program.nextDay = (program.nextDay % total) + 1;
    }
  }

  ProgramExerciseDef? _findDef(ParsedProgram parsed, String key) {
    for (final w in parsed.weeks) {
      for (final d in w.days) {
        for (final e in d.exercises) {
          if (e.key == key) return e;
        }
      }
    }
    return null;
  }

  void _runProgress(ProgramExerciseDef exDef, ExerciseRuntime rt, WorkoutEntry entry,
      {required int week, required int day, required int dayInWeek}) {
    final prog = exDef.progress!;
    final completedSets = entry.sets.where((s) => !s.isWarmup).toList();
    final unit = settings.units;
    final ex = findExercise(exDef.name);
    final rounder = _rounderFor(ex, exDef.equipment);

    final allCompleted = completedSets.every((s) => (s.completedReps ?? 0) >= (s.reps ?? 0));

    if (prog.type == 'lp') {
      // lp(increment, successesReq, currentSuccesses, decrement, failuresReq, currentFailures)
      // ss1: lp(5lb, 1, 0, 10%, 2, 0) — 2 ardışık başarısızlıkta %10 deload.
      final inc = _asWeight(prog.args['arg0'] ?? prog.args['increment'], unit);
      final successReq = (prog.args['arg1'] as num?)?.toInt() ?? 1;
      final decrement = prog.args['arg3']; // LWeight | LPercentage | null
      final failReq = (prog.args['arg4'] as num?)?.toInt() ?? 0;
      if (allCompleted) {
        rt.state['lpFail'] = 0;
        final s = ((rt.state['lpSuccess'] as num?)?.toInt() ?? 0) + 1;
        if (s >= successReq && inc != null) {
          rt.weights = _addWeight(rt.weights, inc, rounder);
          rt.state['lpSuccess'] = 0;
        } else {
          rt.state['lpSuccess'] = s;
        }
      } else {
        rt.state['lpSuccess'] = 0;
        final f = ((rt.state['lpFail'] as num?)?.toInt() ?? 0) + 1;
        if (failReq > 0 && f >= failReq && decrement != null) {
          rt.weights = _applyDecrement(rt.weights, decrement, rounder);
          rt.state['lpFail'] = 0;
        } else {
          rt.state['lpFail'] = f;
        }
      }
      return;
    }
    if (prog.type == 'dp') {
      // dp(increment, minReps, maxReps): gerçek double-progression.
      // Tüm setler güncel hedefe ulaştıysa: hedef < maxReps ise tekrarı artır
      // (ağırlık sabit); hedef == maxReps ise ağırlığı artır + tekrarı minReps'e sıfırla.
      final inc = _asWeight(prog.args['arg0'] ?? prog.args['increment'], unit);
      final minReps = (prog.args['arg1'] as num?)?.toInt() ??
          completedSets.map((s) => s.minReps ?? s.reps ?? 0).fold<int>(99, (a, b) => b < a ? b : a);
      final maxReps = (prog.args['arg2'] as num?)?.toInt() ??
          completedSets.map((s) => s.reps ?? 0).fold<int>(0, (a, b) => b > a ? b : a);
      final cur = (rt.state['dpReps'] as num?)?.toInt() ?? minReps;
      final allHit = completedSets.every((s) => (s.completedReps ?? 0) >= cur);
      if (allHit) {
        if (cur >= maxReps) {
          if (inc != null) rt.weights = _addWeight(rt.weights, inc, rounder);
          rt.state['dpReps'] = minReps;
        } else {
          rt.state['dpReps'] = cur + 1;
        }
      }
      return;
    }
    if (prog.type == 'sum') {
      final inc = _asWeight(prog.args['arg0'] ?? prog.args['increment'], unit);
      final target = (prog.args['arg1'] ?? prog.args['reps']);
      final totalReps = completedSets.fold<int>(0, (s, x) => s + (x.completedReps ?? 0));
      final t = target is num ? target.toInt() : 0;
      if (totalReps >= t && inc != null) {
        rt.weights = _addWeight(rt.weights, inc, rounder);
      }
      return;
    }
    if (prog.type == 'custom' && prog.script != null && prog.script!.trim().isNotEmpty) {
      _runCustomScript(prog, rt, completedSets, rounder, unit,
          week: week, day: day, dayInWeek: dayInWeek);
    }
  }

  void _runCustomScript(
    ProgressDef prog,
    ExerciseRuntime rt,
    List<WorkoutSet> sets,
    WeightRounder rounder,
    String unit, {
    required int week,
    required int day,
    required int dayInWeek,
  }) {
    // state'i başlat (ilk kez): progress args -> state
    for (final e in prog.args.entries) {
      rt.state.putIfAbsent(e.key, () => e.value);
    }

    final prevWeights = <LWeight?>[for (final s in sets) s.weight];
    final weights = <Object?>[for (final s in sets) s.weight];
    final reps = <Object?>[for (final s in sets) (s.reps ?? 0).toDouble()];
    final minReps = <Object?>[for (final s in sets) (s.minReps ?? s.reps ?? 0).toDouble()];
    final completedReps = <Object?>[for (final s in sets) (s.completedReps ?? 0).toDouble()];
    final completedWeights = <Object?>[for (final s in sets) (s.completedWeight ?? s.weight)];
    final rpe = <Object?>[for (final s in sets) s.rpe];
    final completedRpe = <Object?>[for (final s in sets) s.completedRpe];

    // rm1: state'te kalıcı (5/3/1 `rm1 += ...`, GZCLP retest `rm1 = ...`).
    // Yoksa en ağır tamamlanan setten tahmin et.
    LWeight? rm1 = rt.state['rm1'] is LWeight ? rt.state['rm1'] as LWeight : null;
    if (rm1 == null) {
      for (final s in sets) {
        final cw = s.completedWeight ?? s.weight;
        final cr = s.completedReps ?? s.reps ?? 0;
        if (cw != null && cr > 0) {
          final est = epley1RM(cw.value, cr);
          if (rm1 == null || est > rm1.value) rm1 = LWeight(est, cw.unit);
        }
      }
    }

    final descriptionIndex =
        rt.state['descriptionIndex'] is num ? (rt.state['descriptionIndex'] as num).toInt() : 1;

    final bindings = ScriptBindings(
      arrays: {
        'weights': weights,
        'reps': reps,
        'minReps': minReps,
        'completedReps': completedReps,
        'completedWeights': completedWeights,
        'RPE': rpe,
        'completedRPE': completedRpe,
      },
      scalars: {
        'numberOfSets': sets.length,
        'completedNumberOfSets': sets.where((s) => s.completed).length,
        'setVariationIndex': rt.setVariationIndex,
        'descriptionIndex': descriptionIndex,
        'rm1': rm1 ?? LWeight(0, unit),
        'day': day,
        'week': week,
        'dayInWeek': dayInWeek,
        'bodyweight': LWeight(0, unit),
      },
    );

    try {
      ScriptRunner(prog.script!).run(bindings, rt.state, rounder: rounder);

      // güncellenmiş rm1'i state'e kalıcı yaz
      final newRm1 = bindings.scalar('rm1');
      if (newRm1 is LWeight && newRm1.value > 0) rt.state['rm1'] = newRm1;

      // sonuçları geri yaz: LWeight->yuvarla, LPercentage->rm1'e göre çöz,
      // null->önceki ağırlığı koru (veri kaybı yok).
      final newWeights = bindings.array('weights');
      rt.weights = [
        for (var i = 0; i < newWeights.length; i++)
          _writeBackWeight(newWeights[i], i < prevWeights.length ? prevWeights[i] : null,
              rt.state['rm1'] is LWeight ? rt.state['rm1'] as LWeight : rm1, rounder, unit),
      ];

      final svi = bindings.scalar('setVariationIndex');
      if (svi is num) rt.setVariationIndex = svi.toInt().clamp(1, 1 << 20);
      final di = bindings.scalar('descriptionIndex');
      if (di is num) rt.state['descriptionIndex'] = di.toInt();
    } catch (_) {
      // script hatası: progresyon atlanır (app çökmemeli)
    }
  }

  LWeight? _writeBackWeight(
      Object? w, LWeight? prev, LWeight? rm1, WeightRounder rounder, String unit) {
    if (w is LWeight) return rounder(w, w.unit);
    if (w is LPercentage) {
      final base = rm1 ?? prev;
      if (base != null) {
        return rounder(LWeight(base.value * w.value / 100, base.unit), base.unit);
      }
      return prev;
    }
    if (w is num) return rounder(LWeight(w.toDouble(), unit), unit);
    return prev; // null veya bilinmeyen: önceki ağırlığı koru
  }

  LWeight? _asWeight(Object? v, String unit) {
    if (v is LWeight) return v;
    if (v is num) return LWeight(v.toDouble(), unit);
    return null;
  }

  /// Custom progress script `weights`/`w` dizisine yazıyor mu (mutlak mod)?
  /// `==` karşılaştırması hariç tutulur.
  static final _weightsWriteRe =
      RegExp(r'\b(weights|w)\b\s*(\[[^\]]*\])?\s*(\+=|-=|\*=|/=|=(?!=))');
  bool _scriptWritesWeights(String? script) {
    if (script == null) return false;
    return _weightsWriteRe.hasMatch(script);
  }

  /// Tüm ağırlıklara sabit artış (yuvarlanmış).
  List<LWeight?> _addWeight(List<LWeight?> weights, LWeight inc, WeightRounder rounder) {
    return weights
        .map((w) => w == null
            ? null
            : rounder(LWeight(w.value + weightConvertTo(inc, w.unit).value, w.unit), w.unit))
        .toList();
  }

  /// Deload uygula: yüzde (10% -> ×0.9) veya sabit ağırlık (-decrement).
  List<LWeight?> _applyDecrement(List<LWeight?> weights, Object decrement, WeightRounder rounder) {
    return weights.map((w) {
      if (w == null) return null;
      if (decrement is LPercentage) {
        return rounder(LWeight(w.value * (1 - decrement.value / 100), w.unit), w.unit);
      }
      if (decrement is LWeight) {
        return rounder(LWeight(w.value - weightConvertTo(decrement, w.unit).value, w.unit), w.unit);
      }
      return w;
    }).toList();
  }
}
