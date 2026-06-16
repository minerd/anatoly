/// Anatoly domain modelleri (plain Dart, JSON serileştirmeli).
///
/// Ağırlık tipi için Liftoscript [LWeight]/[LPercentage] yeniden kullanılır.
library;

import '../liftoscript/value.dart';

export '../liftoscript/value.dart' show LWeight, LPercentage;

// ---------------------------------------------------------------------------
// Egzersiz kataloğu
// ---------------------------------------------------------------------------

class Exercise {
  final String id;
  final String name;
  final String? defaultEquipment;
  final int defaultWarmup;
  final List<String> types;
  final double startingWeightLb;
  final double startingWeightKg;
  final List<String> targetMuscles;
  final List<String> synergistMuscles;
  final List<String> bodyParts;
  final List<String> equipment;
  final String? video;
  final String description;
  final String instructions;

  const Exercise({
    required this.id,
    required this.name,
    this.defaultEquipment,
    this.defaultWarmup = 0,
    this.types = const [],
    this.startingWeightLb = 0,
    this.startingWeightKg = 0,
    this.targetMuscles = const [],
    this.synergistMuscles = const [],
    this.bodyParts = const [],
    this.equipment = const [],
    this.video,
    this.description = '',
    this.instructions = '',
  });

  factory Exercise.fromJson(Map<String, dynamic> j) => Exercise(
        id: j['id'] as String,
        name: j['name'] as String,
        defaultEquipment: j['defaultEquipment'] as String?,
        defaultWarmup: (j['defaultWarmup'] as num?)?.toInt() ?? 0,
        types: (j['types'] as List?)?.cast<String>() ?? const [],
        startingWeightLb: (j['startingWeightLb'] as num?)?.toDouble() ?? 0,
        startingWeightKg: (j['startingWeightKg'] as num?)?.toDouble() ?? 0,
        targetMuscles: (j['targetMuscles'] as List?)?.cast<String>() ?? const [],
        synergistMuscles: (j['synergistMuscles'] as List?)?.cast<String>() ?? const [],
        bodyParts: (j['bodyParts'] as List?)?.cast<String>() ?? const [],
        equipment: (j['equipment'] as List?)?.cast<String>() ?? const [],
        video: j['video'] as String?,
        description: (j['description'] as String?) ?? '',
        instructions: (j['instructions'] as String?) ?? '',
      );

  double startingWeight(String unit) => unit == 'kg' ? startingWeightKg : startingWeightLb;
}

/// Programda/geçmişte egzersiz referansı: id + opsiyonel ekipman.
class ExerciseType {
  final String id;
  final String? equipment;
  const ExerciseType(this.id, [this.equipment]);

  String get key => equipment == null ? id : '$id:$equipment';

  Map<String, dynamic> toJson() => {'id': id, if (equipment != null) 'equipment': equipment};
  factory ExerciseType.fromJson(Map<String, dynamic> j) =>
      ExerciseType(j['id'] as String, j['equipment'] as String?);

  @override
  bool operator ==(Object other) =>
      other is ExerciseType && other.id == id && other.equipment == equipment;
  @override
  int get hashCode => Object.hash(id, equipment);
}

// ---------------------------------------------------------------------------
// Set & workout (geçmiş kaydı)
// ---------------------------------------------------------------------------

class WorkoutSet {
  // hedef (programdan)
  int? reps;
  int? minReps;
  LWeight? weight;
  Object? originalWeight; // LWeight | LPercentage (yuvarlama öncesi)
  double? rpe;
  int? timer; // saniye
  bool isAmrap;
  bool logRpe;
  bool askWeight;
  String? label;
  bool isWarmup;
  // tamamlanan
  bool completed;
  int? completedReps;
  LWeight? completedWeight;
  double? completedRpe;

  WorkoutSet({
    this.reps,
    this.minReps,
    this.weight,
    this.originalWeight,
    this.rpe,
    this.timer,
    this.isAmrap = false,
    this.logRpe = false,
    this.askWeight = false,
    this.label,
    this.isWarmup = false,
    this.completed = false,
    this.completedReps,
    this.completedWeight,
    this.completedRpe,
  });

  Map<String, dynamic> toJson() => {
        'reps': reps,
        'minReps': minReps,
        'weight': _wJson(weight),
        'originalWeight': _owJson(originalWeight),
        'rpe': rpe,
        'timer': timer,
        'isAmrap': isAmrap,
        'logRpe': logRpe,
        'askWeight': askWeight,
        'label': label,
        'isWarmup': isWarmup,
        'completed': completed,
        'completedReps': completedReps,
        'completedWeight': _wJson(completedWeight),
        'completedRpe': completedRpe,
      };

  factory WorkoutSet.fromJson(Map<String, dynamic> j) => WorkoutSet(
        reps: (j['reps'] as num?)?.toInt(),
        minReps: (j['minReps'] as num?)?.toInt(),
        weight: _wFromJson(j['weight']),
        originalWeight: _owFromJson(j['originalWeight']),
        rpe: (j['rpe'] as num?)?.toDouble(),
        timer: (j['timer'] as num?)?.toInt(),
        isAmrap: j['isAmrap'] as bool? ?? false,
        logRpe: j['logRpe'] as bool? ?? false,
        askWeight: j['askWeight'] as bool? ?? false,
        label: j['label'] as String?,
        isWarmup: j['isWarmup'] as bool? ?? false,
        completed: j['completed'] as bool? ?? false,
        completedReps: (j['completedReps'] as num?)?.toInt(),
        completedWeight: _wFromJson(j['completedWeight']),
        completedRpe: (j['completedRpe'] as num?)?.toDouble(),
      );
}

class WorkoutEntry {
  final ExerciseType exercise;
  final String exerciseName;
  final String? label;
  final String? programExerciseKey;
  final String? supersetName;
  List<WorkoutSet> warmupSets;
  List<WorkoutSet> sets;
  String? notes;

  WorkoutEntry({
    required this.exercise,
    required this.exerciseName,
    this.label,
    this.programExerciseKey,
    this.supersetName,
    List<WorkoutSet>? warmupSets,
    List<WorkoutSet>? sets,
    this.notes,
  })  : warmupSets = warmupSets ?? [],
        sets = sets ?? [];

  Map<String, dynamic> toJson() => {
        'exercise': exercise.toJson(),
        'exerciseName': exerciseName,
        'label': label,
        'programExerciseKey': programExerciseKey,
        'supersetName': supersetName,
        'warmupSets': warmupSets.map((s) => s.toJson()).toList(),
        'sets': sets.map((s) => s.toJson()).toList(),
        'notes': notes,
      };

  factory WorkoutEntry.fromJson(Map<String, dynamic> j) => WorkoutEntry(
        exercise: ExerciseType.fromJson(j['exercise'] as Map<String, dynamic>),
        exerciseName: j['exerciseName'] as String,
        label: j['label'] as String?,
        programExerciseKey: j['programExerciseKey'] as String?,
        supersetName: j['supersetName'] as String?,
        warmupSets: (j['warmupSets'] as List?)
                ?.map((e) => WorkoutSet.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        sets: (j['sets'] as List?)
                ?.map((e) => WorkoutSet.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        notes: j['notes'] as String?,
      );
}

class WorkoutRecord {
  final int id; // ms timestamp
  String? programId;
  String programName;
  int day;
  int? week;
  String dayName;
  int startTime; // ms
  int? endTime;
  List<WorkoutEntry> entries;
  String? notes;

  WorkoutRecord({
    required this.id,
    this.programId,
    this.programName = '',
    this.day = 1,
    this.week,
    this.dayName = '',
    required this.startTime,
    this.endTime,
    List<WorkoutEntry>? entries,
    this.notes,
  }) : entries = entries ?? [];

  bool get isFinished => endTime != null;
  DateTime get date => DateTime.fromMillisecondsSinceEpoch(id);

  Map<String, dynamic> toJson() => {
        'id': id,
        'programId': programId,
        'programName': programName,
        'day': day,
        'week': week,
        'dayName': dayName,
        'startTime': startTime,
        'endTime': endTime,
        'entries': entries.map((e) => e.toJson()).toList(),
        'notes': notes,
      };

  factory WorkoutRecord.fromJson(Map<String, dynamic> j) => WorkoutRecord(
        id: (j['id'] as num).toInt(),
        programId: j['programId'] as String?,
        programName: (j['programName'] as String?) ?? '',
        day: (j['day'] as num?)?.toInt() ?? 1,
        week: (j['week'] as num?)?.toInt(),
        dayName: (j['dayName'] as String?) ?? '',
        startTime: (j['startTime'] as num?)?.toInt() ?? 0,
        endTime: (j['endTime'] as num?)?.toInt(),
        entries: (j['entries'] as List?)
                ?.map((e) => WorkoutEntry.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        notes: j['notes'] as String?,
      );
}

// ---------------------------------------------------------------------------
// Ekipman & ayarlar
// ---------------------------------------------------------------------------

class PlateSet {
  final LWeight weight;
  final int count;
  const PlateSet(this.weight, this.count);
  Map<String, dynamic> toJson() => {'weight': _wJson(weight), 'count': count};
  factory PlateSet.fromJson(Map<String, dynamic> j) =>
      PlateSet(_wFromJson(j['weight'])!, ((j['count'] ?? j['num']) as num).toInt());
}

class EquipmentData {
  final String name;
  final int multiplier; // barbell=2
  final LWeight bar;
  final List<PlateSet> plates;
  final List<LWeight> fixed; // dumbbell vb. sabit ağırlıklar
  final bool isFixed;

  const EquipmentData({
    required this.name,
    this.multiplier = 2,
    required this.bar,
    this.plates = const [],
    this.fixed = const [],
    this.isFixed = false,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'multiplier': multiplier,
        'bar': _wJson(bar),
        'plates': plates.map((p) => p.toJson()).toList(),
        'fixed': fixed.map(_wJson).toList(),
        'isFixed': isFixed,
      };

  factory EquipmentData.fromJson(Map<String, dynamic> j) => EquipmentData(
        name: j['name'] as String,
        multiplier: (j['multiplier'] as num?)?.toInt() ?? 2,
        bar: _wFromJson(j['bar'])!,
        plates: (j['plates'] as List?)
                ?.map((e) => PlateSet.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        fixed: (j['fixed'] as List?)?.map((e) => _wFromJson(e)!).toList() ?? const [],
        isFixed: j['isFixed'] as bool? ?? false,
      );
}

class Settings {
  String units; // kg | lb
  String locale; // tr | en | es | de | fr
  int warmupTimer; // sn
  int workoutTimer; // sn
  bool vibration;
  Map<String, EquipmentData> equipment;

  Settings({
    this.units = 'lb',
    this.locale = 'tr',
    this.warmupTimer = 90,
    this.workoutTimer = 180,
    this.vibration = true,
    Map<String, EquipmentData>? equipment,
  }) : equipment = equipment ?? defaultEquipment();

  Map<String, dynamic> toJson() => {
        'units': units,
        'locale': locale,
        'warmupTimer': warmupTimer,
        'workoutTimer': workoutTimer,
        'vibration': vibration,
        'equipment': equipment.map((k, v) => MapEntry(k, v.toJson())),
      };

  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
        units: (j['units'] as String?) ?? 'lb',
        locale: (j['locale'] as String?) ?? 'tr',
        warmupTimer: (j['warmupTimer'] as num?)?.toInt() ?? 90,
        workoutTimer: (j['workoutTimer'] as num?)?.toInt() ?? 180,
        vibration: j['vibration'] as bool? ?? true,
        equipment: (j['equipment'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, EquipmentData.fromJson(v as Map<String, dynamic>)),
            ) ??
            defaultEquipment(),
      );

  static Map<String, EquipmentData> defaultEquipment() {
    final barbellPlatesLb = [
      const PlateSet(LWeight(45, 'lb'), 8),
      const PlateSet(LWeight(25, 'lb'), 4),
      const PlateSet(LWeight(10, 'lb'), 4),
      const PlateSet(LWeight(5, 'lb'), 4),
      const PlateSet(LWeight(2.5, 'lb'), 4),
    ];
    final barbellPlatesKg = [
      const PlateSet(LWeight(20, 'kg'), 8),
      const PlateSet(LWeight(10, 'kg'), 4),
      const PlateSet(LWeight(5, 'kg'), 4),
      const PlateSet(LWeight(2.5, 'kg'), 4),
      const PlateSet(LWeight(1.25, 'kg'), 4),
    ];
    return {
      'barbell': EquipmentData(
        name: 'Barbell',
        multiplier: 2,
        bar: const LWeight(45, 'lb'),
        plates: [...barbellPlatesLb, ...barbellPlatesKg],
      ),
      'smith': EquipmentData(
        name: 'Smith Machine',
        multiplier: 2,
        bar: const LWeight(45, 'lb'),
        plates: [...barbellPlatesLb, ...barbellPlatesKg],
      ),
      'dumbbell': EquipmentData(
        name: 'Dumbbell',
        multiplier: 1,
        bar: const LWeight(0, 'lb'),
        plates: [...barbellPlatesLb, ...barbellPlatesKg],
      ),
      'cable': EquipmentData(
        name: 'Cable',
        multiplier: 1,
        bar: const LWeight(0, 'lb'),
        plates: [
          const PlateSet(LWeight(10, 'lb'), 20),
          const PlateSet(LWeight(5, 'kg'), 20),
        ],
      ),
      'leverageMachine': EquipmentData(
        name: 'Machine',
        multiplier: 1,
        bar: const LWeight(0, 'lb'),
        plates: [
          const PlateSet(LWeight(10, 'lb'), 20),
          const PlateSet(LWeight(5, 'kg'), 20),
        ],
      ),
      'kettlebell': EquipmentData(
        name: 'Kettlebell',
        multiplier: 1,
        bar: const LWeight(0, 'lb'),
        isFixed: true,
        fixed: [
          for (final v in [10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 70, 80])
            LWeight(v.toDouble(), 'lb'),
        ],
      ),
      'bodyweight': EquipmentData(
        name: 'Bodyweight',
        multiplier: 1,
        bar: const LWeight(0, 'lb'),
      ),
      'band': EquipmentData(
        name: 'Band',
        multiplier: 1,
        bar: const LWeight(0, 'lb'),
      ),
      'ezbar': EquipmentData(
        name: 'EZ Bar',
        multiplier: 2,
        bar: const LWeight(15, 'lb'),
        plates: [...barbellPlatesLb, ...barbellPlatesKg],
      ),
      'trapbar': EquipmentData(
        name: 'Trap Bar',
        multiplier: 2,
        bar: const LWeight(45, 'lb'),
        plates: [...barbellPlatesLb, ...barbellPlatesKg],
      ),
      'medicineball': EquipmentData(
        name: 'Medicine Ball',
        multiplier: 1,
        bar: const LWeight(0, 'lb'),
        isFixed: true,
        fixed: [for (final v in [4, 6, 8, 10, 12, 14, 20]) LWeight(v.toDouble(), 'lb')],
      ),
    };
  }
}

// ---------------------------------------------------------------------------
// Vücut istatistikleri
// ---------------------------------------------------------------------------

class StatValue {
  final double value;
  final int timestamp;
  const StatValue(this.value, this.timestamp);
  Map<String, dynamic> toJson() => {'value': value, 'timestamp': timestamp};
  factory StatValue.fromJson(Map<String, dynamic> j) =>
      StatValue((j['value'] as num).toDouble(), (j['timestamp'] as num).toInt());
}

// ---------------------------------------------------------------------------
// JSON yardımcıları (ağırlık)
// ---------------------------------------------------------------------------

Map<String, dynamic>? _wJson(LWeight? w) => w == null ? null : {'value': w.value, 'unit': w.unit};
LWeight? _wFromJson(Object? j) {
  if (j == null) return null;
  final m = j as Map<String, dynamic>;
  return LWeight((m['value'] as num).toDouble(), m['unit'] as String);
}

/// originalWeight: LWeight | LPercentage | null (etiketli).
Map<String, dynamic>? _owJson(Object? v) {
  if (v is LWeight) return {'t': 'w', 'value': v.value, 'unit': v.unit};
  if (v is LPercentage) return {'t': 'p', 'value': v.value};
  return null;
}

Object? _owFromJson(Object? j) {
  if (j == null) return null;
  final m = j as Map<String, dynamic>;
  if (m['t'] == 'p') return LPercentage((m['value'] as num).toDouble());
  return LWeight((m['value'] as num).toDouble(), m['unit'] as String);
}
