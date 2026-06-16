/// Program (planner) modelleri — parse edilmiş statik yapı + çalışma zamanı state.
library;

import '../liftoscript/value.dart';

/// Programlı tek set.
class PSet {
  final int? minReps;
  final int? maxReps; // hedef tekrar
  final Object? weight; // LWeight | LPercentage | null
  final double? rpe;
  final int? timer; // sn
  final bool isAmrap;
  final bool logRpe;
  final bool askWeight;
  final String? label;

  const PSet({
    this.minReps,
    this.maxReps,
    this.weight,
    this.rpe,
    this.timer,
    this.isAmrap = false,
    this.logRpe = false,
    this.askWeight = false,
    this.label,
  });

  Map<String, dynamic> toJson() => {
        'minReps': minReps,
        'maxReps': maxReps,
        'weight': _wJson(weight),
        'rpe': rpe,
        'timer': timer,
        'isAmrap': isAmrap,
        'logRpe': logRpe,
        'askWeight': askWeight,
        'label': label,
      };

  factory PSet.fromJson(Map<String, dynamic> j) => PSet(
        minReps: (j['minReps'] as num?)?.toInt(),
        maxReps: (j['maxReps'] as num?)?.toInt(),
        weight: _wFromJson(j['weight']),
        rpe: (j['rpe'] as num?)?.toDouble(),
        timer: (j['timer'] as num?)?.toInt(),
        isAmrap: j['isAmrap'] as bool? ?? false,
        logRpe: j['logRpe'] as bool? ?? false,
        askWeight: j['askWeight'] as bool? ?? false,
        label: j['label'] as String?,
      );
}

class ProgressDef {
  final String type; // custom | lp | dp | sum | none
  final Map<String, Object?> args; // initial state / parametreler
  final String? script; // custom için liftoscript
  const ProgressDef({required this.type, this.args = const {}, this.script});

  Map<String, dynamic> toJson() => {
        'type': type,
        'args': args.map((k, v) => MapEntry(k, _argJson(v))),
        'script': script,
      };
  factory ProgressDef.fromJson(Map<String, dynamic> j) => ProgressDef(
        type: j['type'] as String,
        args: (j['args'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, _argFromJson(v))) ??
            const {},
        script: j['script'] as String?,
      );
}

/// Programdaki bir egzersiz tanımı (statik).
class ProgramExerciseDef {
  final String key; // benzersiz: week-day-index-name
  final String? label; // t1, t2 ...
  final String name; // egzersiz adı (katalogla eşleşir)
  final String? equipment;
  final List<List<PSet>> setVariations;
  final ProgressDef? progress;
  final String? supersetName;
  final bool notUsed; // "used: none" şablon
  final List<int> repeatWeeks; // [1-12] -> bu haftalarda tekrar eder

  const ProgramExerciseDef({
    required this.key,
    this.label,
    required this.name,
    this.equipment,
    this.setVariations = const [],
    this.progress,
    this.supersetName,
    this.notUsed = false,
    this.repeatWeeks = const [],
  });

  ProgramExerciseDef copyWith({
    String? key,
    List<List<PSet>>? setVariations,
    ProgressDef? progress,
    bool? notUsed,
  }) =>
      ProgramExerciseDef(
        key: key ?? this.key,
        label: label,
        name: name,
        equipment: equipment,
        setVariations: setVariations ?? this.setVariations,
        progress: progress ?? this.progress,
        supersetName: supersetName,
        notUsed: notUsed ?? this.notUsed,
      );
}

class ProgramDayDef {
  final String name;
  final List<ProgramExerciseDef> exercises;
  const ProgramDayDef(this.name, this.exercises);
}

class ProgramWeekDef {
  final String name;
  final List<ProgramDayDef> days;
  const ProgramWeekDef(this.name, this.days);
}

/// Parse edilmiş program (statik yapı).
class ParsedProgram {
  final List<ProgramWeekDef> weeks;
  const ParsedProgram(this.weeks);

  bool get isMultiweek => weeks.length > 1;

  /// Tüm günleri sırayla (hafta sınırları korunarak) düz liste.
  List<({int week, int dayInWeek, ProgramDayDef day})> flatDays() {
    final out = <({int week, int dayInWeek, ProgramDayDef day})>[];
    for (var w = 0; w < weeks.length; w++) {
      for (var d = 0; d < weeks[w].days.length; d++) {
        out.add((week: w + 1, dayInWeek: d + 1, day: weeks[w].days[d]));
      }
    }
    return out;
  }

  int get totalDays => flatDays().length;
}

// ---------------------------------------------------------------------------
// Çalışma zamanı: egzersizin güncel ağırlıkları/varyasyonu/state'i (kalıcı)
// ---------------------------------------------------------------------------

class ExerciseRuntime {
  List<LWeight?> weights; // güncel set ağırlıkları
  int setVariationIndex; // 1-based
  Map<String, Object?> state;

  ExerciseRuntime({
    List<LWeight?>? weights,
    this.setVariationIndex = 1,
    Map<String, Object?>? state,
  })  : weights = weights ?? [],
        state = state ?? {};

  Map<String, dynamic> toJson() => {
        'weights': weights.map(_wJson).toList(),
        'setVariationIndex': setVariationIndex,
        'state': state.map((k, v) => MapEntry(k, _argJson(v))),
      };
  factory ExerciseRuntime.fromJson(Map<String, dynamic> j) => ExerciseRuntime(
        weights: (j['weights'] as List?)?.map((e) {
              final w = _wFromJson(e);
              return w is LWeight ? w : null;
            }).toList() ??
            [],
        setVariationIndex: (j['setVariationIndex'] as num?)?.toInt() ?? 1,
        state: (j['state'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, _argFromJson(v))) ??
            {},
      );
}

/// Kullanıcının kütüphanesindeki program (klonlanmış, state'li).
class StoredProgram {
  final String id;
  String name;
  String author;
  String description;
  String plannerText;
  int nextDay; // 1-based, flatDays üzerinde
  Map<String, ExerciseRuntime> runtime; // exerciseKey -> runtime

  StoredProgram({
    required this.id,
    required this.name,
    this.author = '',
    this.description = '',
    required this.plannerText,
    this.nextDay = 1,
    Map<String, ExerciseRuntime>? runtime,
  }) : runtime = runtime ?? {};

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'author': author,
        'description': description,
        'plannerText': plannerText,
        'nextDay': nextDay,
        'runtime': runtime.map((k, v) => MapEntry(k, v.toJson())),
      };
  factory StoredProgram.fromJson(Map<String, dynamic> j) => StoredProgram(
        id: j['id'] as String,
        name: j['name'] as String,
        author: (j['author'] as String?) ?? '',
        description: (j['description'] as String?) ?? '',
        plannerText: j['plannerText'] as String,
        nextDay: (j['nextDay'] as num?)?.toInt() ?? 1,
        runtime: (j['runtime'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, ExerciseRuntime.fromJson(v as Map<String, dynamic>)),
            ) ??
            {},
      );
}

// ---------------------------------------------------------------------------
// JSON yardımcıları
// ---------------------------------------------------------------------------

Map<String, dynamic>? _wJson(Object? w) {
  if (w == null) return null;
  if (w is LWeight) return {'t': 'w', 'value': w.value, 'unit': w.unit};
  if (w is LPercentage) return {'t': 'p', 'value': w.value};
  return null;
}

Object? _wFromJson(Object? j) {
  if (j == null) return null;
  final m = j as Map<String, dynamic>;
  if (m['t'] == 'p') return LPercentage((m['value'] as num).toDouble());
  return LWeight((m['value'] as num).toDouble(), m['unit'] as String);
}

Object? _argJson(Object? v) {
  if (v is LWeight) return {'t': 'w', 'value': v.value, 'unit': v.unit};
  if (v is LPercentage) return {'t': 'p', 'value': v.value};
  // state'te liftoscript binding dizileri/haritaları olabilir -> recurse et
  // (aksi halde jsonEncode çöker ve TÜM kayıt yazılamaz).
  if (v is List) return v.map(_argJson).toList();
  if (v is Map) return v.map((k, e) => MapEntry(k.toString(), _argJson(e)));
  return v; // num / String / bool / null
}

Object? _argFromJson(Object? v) {
  if (v is List) return v.map(_argFromJson).toList();
  if (v is Map) {
    final m = v.cast<String, dynamic>();
    // etiketli sarmalayıcılar önce
    if (m['t'] == 'w') return LWeight((m['value'] as num).toDouble(), m['unit'] as String);
    if (m['t'] == 'p') return LPercentage((m['value'] as num).toDouble());
    return m.map((k, e) => MapEntry(k, _argFromJson(e)));
  }
  return v;
}
