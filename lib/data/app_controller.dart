/// Uygulama durumu + iş mantığı (ChangeNotifier).
///
/// Programlar kütüphanesi, antrenman geçmişi, devam eden antrenman, ayarlar,
/// vücut ağırlığı. Her değişiklikte JSON dosyasına kaydeder.
library;

import 'package:flutter/foundation.dart';

import '../domain/models.dart';
import '../planner/program_service.dart';
import '../planner/program_models.dart';
import '../ui/i18n.dart';
import 'repository.dart';

class AppController extends ChangeNotifier {
  final Repository repo;

  Settings settings = Settings();
  List<StoredProgram> programs = [];
  String? currentProgramId;
  List<WorkoutRecord> history = [];
  WorkoutRecord? ongoing; // devam eden antrenman
  List<StatValue> bodyweight = [];
  bool onboarded = false;

  AppController(this.repo);

  /// MaterialApp'in locale'ini yalnızca dil değişince yeniden kurmak için
  /// (her save()'de tüm uygulamayı yeniden kurmamak adına ayrı notifier).
  final ValueNotifier<String> localeNotifier = ValueNotifier<String>('tr');

  /// Geçerli dil için çevrilmiş metinler.
  Strings get t => stringsFor(settings.locale);

  /// localeNotifier'ı mevcut ayarla eşitler (başlangıçta main() çağırır).
  void syncLocaleNotifier() => localeNotifier.value = settings.locale;

  void setLocale(String code) {
    settings.locale = code;
    localeNotifier.value = code;
    save();
  }

  // katalog kısayolları
  List<Exercise> get exercises => repo.exercises;
  List<Map<String, dynamic>> get builtinPrograms => repo.builtinPrograms;

  ProgramService get service => ProgramService(repo.exercises, settings);

  StoredProgram? get currentProgram {
    if (currentProgramId == null) return null;
    for (final p in programs) {
      if (p.id == currentProgramId) return p;
    }
    return null;
  }

  Exercise? exerciseById(String id) {
    for (final e in repo.exercises) {
      if (e.id == id) return e;
    }
    return null;
  }

  // -------------------- yükleme / kaydetme --------------------

  /// Kayıtlı durum varsa true döner (yoksa ilk açılış).
  Future<bool> load() async {
    final json = await repo.loadState();
    if (json == null) return false;
    try {
      if (json['settings'] != null) {
        settings = Settings.fromJson(json['settings'] as Map<String, dynamic>);
      }
      programs = (json['programs'] as List?)
              ?.map((e) => StoredProgram.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
      currentProgramId = json['currentProgramId'] as String?;
      history = (json['history'] as List?)
              ?.map((e) => WorkoutRecord.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
      ongoing = json['ongoing'] != null
          ? WorkoutRecord.fromJson(json['ongoing'] as Map<String, dynamic>)
          : null;
      bodyweight = (json['bodyweight'] as List?)
              ?.map((e) => StatValue.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
      onboarded = json['onboarded'] as bool? ?? false;
    } catch (e) {
      debugPrint('Durum yükleme hatası: $e');
    }
    return true;
  }

  // yazım birleştirme: aynı anda tek yazım çalışır; sırada bekleyen varsa
  // sadece en son durum yazılır (gereksiz ara yazımlar atlanır).
  bool _writing = false;
  bool _writePending = false;

  Future<void> _persist() async {
    if (_writing) {
      _writePending = true;
      return;
    }
    _writing = true;
    try {
      do {
        _writePending = false;
        await repo.saveState({
          'settings': settings.toJson(),
          'programs': programs.map((p) => p.toJson()).toList(),
          'currentProgramId': currentProgramId,
          'history': history.map((h) => h.toJson()).toList(),
          'ongoing': ongoing?.toJson(),
          'bodyweight': bodyweight.map((b) => b.toJson()).toList(),
          'onboarded': onboarded,
        });
      } while (_writePending); // yazım sırasında yeni mutasyon geldiyse tekrar yaz
    } finally {
      _writing = false;
    }
  }

  void save() {
    _persist();
    notifyListeners();
  }

  // -------------------- onboarding & ayarlar --------------------

  void completeOnboarding(String units) {
    settings.units = units;
    onboarded = true;
    save();
  }

  void updateSettings(void Function(Settings) fn) {
    fn(settings);
    save();
  }

  // -------------------- programlar --------------------

  StoredProgram cloneBuiltin(Map<String, dynamic> programJson) {
    final program = service.clone(programJson);
    programs.add(program);
    currentProgramId = program.id;
    save();
    return program;
  }

  StoredProgram createEmptyProgram(String name) {
    final program = service.createEmpty(name);
    programs.add(program);
    currentProgramId = program.id;
    save();
    return program;
  }

  void selectProgram(String id) {
    currentProgramId = id;
    save();
  }

  /// Bir egzersizin 1RM / antrenman maksimumunu ayarlar (yüzde-bazlı programlar).
  /// Ağırlıklar temizlenir ki bir sonraki gün üretiminde yeni rm1'den yeniden
  /// çözülsünler (hem percentageMode hem writesWeights programlarda geçerli).
  void setExerciseRm1(StoredProgram program, String exerciseKey, LWeight rm1) {
    final rt = program.runtime.putIfAbsent(exerciseKey, () => ExerciseRuntime());
    rt.state['rm1'] = rm1;
    rt.weights = [];
    save();
  }

  LWeight? exerciseRm1(StoredProgram program, String exerciseKey) {
    final v = program.runtime[exerciseKey]?.state['rm1'];
    return v is LWeight ? v : null;
  }

  void deleteProgram(String id) {
    programs.removeWhere((p) => p.id == id);
    if (currentProgramId == id) {
      currentProgramId = programs.isNotEmpty ? programs.first.id : null;
    }
    save();
  }

  // -------------------- antrenman akışı --------------------

  WorkoutRecord startWorkout({StoredProgram? program, int? day}) {
    final prog = program ?? currentProgram;
    WorkoutRecord record;
    if (prog != null) {
      record = service.generateDay(prog, day ?? prog.nextDay);
    } else {
      final now = DateTime.now().millisecondsSinceEpoch;
      record = WorkoutRecord(id: now, startTime: now, dayName: 'Serbest Antrenman');
    }
    ongoing = record;
    save();
    return record;
  }

  void updateOngoing() {
    save();
  }

  /// Workout'u bitirir. Geçmişe kaydedildiyse true, hiç set tamamlanmadığı
  /// için atıldıysa false döner (UI kullanıcıya bilgi verebilir).
  bool finishWorkout() {
    final record = ongoing;
    if (record == null) return false;
    record.endTime = DateTime.now().millisecondsSinceEpoch;
    // boş (hiç set tamamlanmamış) entry'leri at
    record.entries.removeWhere((e) => e.sets.every((s) => !s.completed));
    final saved = record.entries.isNotEmpty;
    if (saved) {
      history.insert(0, record);
      // progresyon uygula
      final prog = programs.where((p) => p.id == record.programId).firstOrNull;
      if (prog != null) {
        service.applyProgression(prog, record);
      }
    }
    ongoing = null;
    save();
    return saved;
  }

  void cancelWorkout() {
    ongoing = null;
    save();
  }

  // -------------------- vücut ağırlığı --------------------

  void addBodyweight(double value) {
    bodyweight.insert(0, StatValue(value, DateTime.now().millisecondsSinceEpoch));
    save();
  }

  // -------------------- geçmiş analizi --------------------

  /// Bir egzersizin geçmişteki en iyi tahmini 1RM zaman serisi.
  List<({DateTime date, double e1rm})> exerciseProgress(String exerciseId) {
    final out = <({DateTime date, double e1rm})>[];
    for (final rec in history.reversed) {
      double best = 0;
      for (final entry in rec.entries) {
        if (entry.exercise.id != exerciseId) continue;
        for (final s in entry.sets) {
          if (!s.completed || s.completedWeight == null) continue;
          final reps = s.completedReps ?? 0;
          if (reps <= 0) continue;
          final e1 = s.completedWeight!.value * (1 + reps / 30.0);
          if (e1 > best) best = e1;
        }
      }
      if (best > 0) out.add((date: rec.date, e1rm: best));
    }
    return out;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
