/// Liftosaur planner metin formatı parser'ı.
///
/// Desteklenen:
/// - `# Week ...` hafta, `## ...` gün başlıkları
/// - `[label:] İsim / [used: none] / set-şeması [ağırlık] [@rpe] [timer] / progress: ...`
/// - `...label` ile set/progress yeniden kullanımı (reuse)
/// - set şeması: virgülle ayrılmış `NxR`, `NxR+` (amrap), `NxRmin-Rmax`
/// - `progress: custom(args){script}` / `lp(...)` / `dp(...)` / `sum(...)`
/// - `\` ile satır devamı
///
/// Tanınmayan sözdizimine karşı toleranslı (en iyi çaba).
library;

import '../liftoscript/value.dart';
import 'program_models.dart';

class PlannerParser {
  /// Ham planner metnini [ParsedProgram]'a dönüştürür.
  ///
  /// İki faz: (1) tüm haftaları/günleri/egzersizleri ham olarak topla,
  /// (2) GLOBAL şablon haritası kur (ör. dosya sonundaki `t1 / used: none / ...`)
  /// ve reuse'ları çöz. Şablonlar genelde dosyanın sonunda tanımlandığı için
  /// gün-bazlı çözüm yetersizdir — global olmalı.
  static ParsedProgram parse(String text) {
    final lines = _joinContinuations(text.split('\n'));

    // --- Faz 1: ham toplama ---
    final rawWeeks = <_RawWeek>[];
    String? curWeekName;
    List<_RawDay> curDays = [];
    String? curDayName;
    List<_RawExercise> curRaws = [];

    void flushDay() {
      if (curDayName != null) {
        curDays.add(_RawDay(curDayName!, curRaws));
      }
      curRaws = [];
      curDayName = null;
    }

    void flushWeek() {
      flushDay();
      if (curWeekName != null || curDays.isNotEmpty) {
        rawWeeks.add(_RawWeek(curWeekName ?? 'Week ${rawWeeks.length + 1}', curDays));
      }
      curDays = [];
      curWeekName = null;
    }

    for (var raw in lines) {
      final line = raw.trimRight();
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('## ')) {
        flushDay();
        curDayName = trimmed.substring(3).trim();
        continue;
      }
      if (trimmed.startsWith('# ')) {
        flushWeek();
        curWeekName = trimmed.substring(2).trim();
        continue;
      }
      if (trimmed.startsWith('//')) continue;
      curDayName ??= 'Day ${curDays.length + 1}';
      final rawEx = _parseExerciseLine(trimmed);
      if (rawEx != null) curRaws.add(rawEx);
    }
    flushWeek();

    // --- Faz 1.5: RAW seviyesinde tekrar-doldurma (hafta-duyarlı) ---
    // `Bench Press[1-12]` gibi tekrar etiketli egzersizler hedef haftaların aynı
    // gün-konumuna KOPYALANIR. Reuse alanları korunduğu için her hafta KENDİ
    // şablonuna göre çözülür (531 dalga-yüklemesi, rippler intensity dalgası).
    for (var wi = 0; wi < rawWeeks.length; wi++) {
      for (var di = 0; di < rawWeeks[wi].days.length; di++) {
        for (final r in List.of(rawWeeks[wi].days[di].raws)) {
          if (r.repeatWeeks.isEmpty) continue;
          for (final tw in r.repeatWeeks) {
            final twi = tw - 1;
            if (twi == wi || twi < 0 || twi >= rawWeeks.length) continue;
            if (di >= rawWeeks[twi].days.length) continue;
            final targetRaws = rawWeeks[twi].days[di].raws;
            if (targetRaws.any((x) => x.name == r.name && x.label == r.label)) continue;
            targetRaws.add(r.cloneForRepeat());
          }
        }
      }
    }

    // --- Faz 2: GLOBAL şablon haritası ---
    // Bir raw "reuse kaynağı" sayılır: set şeması VEYA progress içeriyorsa.
    // Şablonlar (set şemalı) öncelikli; aynı etikete sahip şablonsuz gün
    // egzersizleri kaynağı ezmez.
    final globalLabelMap = <String, _RawExercise>{};
    final allRaws = [for (final w in rawWeeks) for (final d in w.days) ...d.raws];

    void register(_RawExercise r) {
      final hasContent = r.setSchemes.isNotEmpty || r.progressRaw != null;
      if (!hasContent) return;
      void put(String k) {
        final existing = globalLabelMap[k];
        // set şemalı olan (asıl şablon) önceliklidir
        if (existing == null || (r.setSchemes.isNotEmpty && existing.setSchemes.isEmpty)) {
          globalLabelMap[k] = r;
        }
      }
      if (r.label != null) put(r.label!);
      put(r.name);
    }

    for (final r in allRaws) {
      register(r);
    }

    // Şablon adlarını global yay: bir İSİM programda bir kez `used: none` ile
    // tanımlandıysa, o ismin TÜM yeniden-tanımları da şablondur (notUsed).
    // (531/madcow/rippler: `main`/`t1` hafta 1'de used:none ama 2-4'te değil ->
    //  aksi halde katalogda olmayan sahte "main"/"t1" egzersizi sızıyor.)
    // YALNIZ isim üzerinden: GZCLP'de `t1` hem şablon adı hem de gerçek egzersiz
    // etiketidir (`t1: Squat`); etiketle yaymak gerçek egzersizleri silerdi.
    final templateNames = <String>{
      for (final r in allRaws)
        if (r.notUsed) r.name,
    };
    for (final r in allRaws) {
      if (templateNames.contains(r.name)) r.notUsed = true;
    }

    // progress'leri parse et (önce şablonlar, sonra hepsi — `{ ...t1 }` reuse için)
    for (final r in globalLabelMap.values) {
      r.progress ??= r.progressRaw != null
          ? _parseProgress(r.progressRaw!, labelMap: globalLabelMap)
          : null;
    }
    for (final r in allRaws) {
      if (r.progressRaw != null) {
        r.progress ??= _parseProgress(r.progressRaw!, labelMap: globalLabelMap);
      }
    }

    // Per-week şablon haritaları: her haftanın set-şemalı tanımları (531/rippler
    // haftaya-özel `main`/`t1` yeniden-tanımları). Reuse önce gün-yerel, sonra
    // O HAFTANIN şablonu, sonra global'e bakar.
    final weekTemplates = <Map<String, _RawExercise>>[];
    for (final w in rawWeeks) {
      final m = <String, _RawExercise>{};
      for (final d in w.days) {
        for (final r in d.raws) {
          if (r.setSchemes.isEmpty) continue;
          if (r.label != null) m.putIfAbsent(r.label!, () => r);
          m.putIfAbsent(r.name, () => r);
        }
      }
      weekTemplates.add(m);
    }

    // --- Faz 3: çöz + ProgramExerciseDef üret ---
    final weeks = <ProgramWeekDef>[];
    for (var wi = 0; wi < rawWeeks.length; wi++) {
      final days = <ProgramDayDef>[];
      for (var di = 0; di < rawWeeks[wi].days.length; di++) {
        final rawDay = rawWeeks[wi].days[di];
        final exercises = _buildExercises(rawDay.raws, weekTemplates[wi], globalLabelMap);
        days.add(ProgramDayDef(rawDay.name, exercises));
      }
      weeks.add(ProgramWeekDef(rawWeeks[wi].name, days));
    }

    _shareProgress(weeks);
    return ParsedProgram(weeks);
  }

  /// Progress'i aynı stabil kimlikteki TÜM instance'lara paylaştır.
  /// Liftosaur'da progress egzersizin özelliğidir; aynı lift farklı günlerde
  /// (texas Volume/Intensity, smolov Day1/Day4) tek paylaşılan progresyon kullanır
  /// ve GERÇEK dayInWeek/week ile değerlendirilir. Böylece `dayInWeek==3` koşullu
  /// progress, o egzersizin dayInWeek==3 olan gününde de tetiklenir.
  static void _shareProgress(List<ProgramWeekDef> weeks) {
    final byKey = <String, ProgressDef>{};
    for (final w in weeks) {
      for (final d in w.days) {
        for (final e in d.exercises) {
          if (e.progress != null) byKey.putIfAbsent(e.key, () => e.progress!);
        }
      }
    }
    for (final w in weeks) {
      for (final d in w.days) {
        for (var i = 0; i < d.exercises.length; i++) {
          final e = d.exercises[i];
          if (e.progress == null && byKey.containsKey(e.key)) {
            d.exercises[i] = e.copyWith(progress: byKey[e.key]);
          }
        }
      }
    }
  }


  // --- satır devamı (`\`) ve çok satırlı `{~ ... ~}` bloklarını birleştir ---
  // Sürekli derinlik takibi: bir satırda hem `~}` (kapanış) hem yeni `{~`
  // (açılış) olabilir (madcow: `~} / update: custom() {~`). Yalnız `{~`/`~}`
  // sayılır; script içindeki düz `{`/`}` derinliği etkilemez.
  static List<String> _joinContinuations(List<String> lines) {
    final out = <String>[];
    var buffer = '';
    var depth = 0;
    for (var line in lines) {
      final t = line.trimRight();
      final opens = '{~'.allMatches(line).length;
      final closes = '~}'.allMatches(line).length;
      final newDepth = depth + opens - closes;

      if (depth > 0) {
        // blok içindeyiz: satırı birleştir
        buffer += ' ${line.trim()}';
        depth = newDepth < 0 ? 0 : newDepth;
        if (depth == 0) {
          out.add(buffer);
          buffer = '';
        }
        continue;
      }
      if (newDepth > 0) {
        // blok bu satırda başlıyor ve kapanmıyor
        buffer += t.endsWith('\\') ? '${t.substring(0, t.length - 1)} ' : line;
        depth = newDepth;
        continue;
      }
      // normal satır (blok yok ya da tek satırda açılıp kapanan)
      if (t.endsWith('\\')) {
        buffer += '${t.substring(0, t.length - 1)} ';
      } else {
        out.add(buffer + line);
        buffer = '';
      }
    }
    if (buffer.isNotEmpty) out.add(buffer);
    return out;
  }

  // --- tek egzersiz satırı ---
  static _RawExercise? _parseExerciseLine(String line) {
    // progress: bloğunu önce ayır (içinde ' / ' olabilir)
    String? progressRaw;
    var work = line;
    final progIdx = _findProgress(work);
    if (progIdx >= 0) {
      progressRaw = work.substring(progIdx).trim();
      work = work.substring(0, progIdx).trim();
      if (work.endsWith('/')) work = work.substring(0, work.length - 1).trim();
    }

    final segments = work.split(' / ').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;

    // ilk segment: [label:] isim [hafta-aralığı]
    var nameSeg = segments.first;
    String? label;
    final colon = nameSeg.indexOf(':');
    if (colon > 0) {
      // Liftosaur etiketi: en fazla 8 karakter, boşluk içermez (t1, aux, halting, block)
      final maybeLabel = nameSeg.substring(0, colon).trim();
      if (maybeLabel.length <= 8 && !maybeLabel.contains(' ')) {
        label = maybeLabel;
        nameSeg = nameSeg.substring(colon + 1).trim();
      }
    }

    // hafta-aralığı son-eki: "Bench Press[1-12]" -> name="Bench Press", repeat 1..12
    List<int> repeatWeeks = const [];
    final repMatch = RegExp(r'\s*\[\s*(\d+)\s*-\s*(\d+)\s*\]\s*$').firstMatch(nameSeg);
    if (repMatch != null) {
      final from = int.parse(repMatch.group(1)!);
      final to = int.parse(repMatch.group(2)!);
      repeatWeeks = [for (var w = from; w <= to; w++) w];
      nameSeg = nameSeg.substring(0, repMatch.start).trim();
    }

    // "Bench Press, Dumbbell" -> name="Bench Press", equipment="dumbbell"
    String? equipment;
    final commaIdx = nameSeg.lastIndexOf(', ');
    if (commaIdx > 0) {
      final eq = _equipmentKey(nameSeg.substring(commaIdx + 2).trim());
      if (eq != null) {
        equipment = eq;
        nameSeg = nameSeg.substring(0, commaIdx).trim();
      }
    }

    final raw = _RawExercise(name: nameSeg, label: label, progressRaw: progressRaw)
      ..repeatWeeks = repeatWeeks
      ..equipment = equipment;

    for (var i = 1; i < segments.length; i++) {
      final seg = segments[i];
      if (seg.startsWith('...')) {
        // indeksli reuse olabilir: ...main[1] -> label=main, index=1
        final m = RegExp(r'^(.*?)(?:\[(\d+)\])?$').firstMatch(seg.substring(3).trim());
        raw.reuseLabel = m?.group(1)?.trim();
        raw.reuseIndex = m?.group(2) != null ? int.parse(m!.group(2)!) : null;
      } else if (seg.startsWith('reuse:')) {
        raw.reuseLabel = seg.substring(6).trim();
      } else if (seg.startsWith('used:')) {
        if (seg.substring(5).trim() == 'none') raw.notUsed = true;
      } else if (seg.startsWith('superset:')) {
        raw.supersetName = seg.substring(9).trim();
      } else if (seg.startsWith('update:')) {
        // update bloğu workout sırasında set günceller; egzersiz olarak yaratma, atla
      } else if (seg.startsWith('warmup:')) {
        // şimdilik atla
      } else if (seg.startsWith('id:')) {
        // atla
      } else if (_looksLikeSetScheme(seg)) {
        raw.setSchemes.add(seg);
      } else if (_looksLikeWeight(seg) || _looksLikeParenWeight(seg)) {
        raw.globalWeight = _parseWeightOrPct(_stripParens(seg));
      } else if (seg.startsWith('@')) {
        raw.globalRpe = double.tryParse(seg.substring(1));
      } else if (RegExp(r'^\d+s$').hasMatch(seg)) {
        raw.globalTimer = int.tryParse(seg.substring(0, seg.length - 1));
      }
    }
    return raw;
  }

  /// Görünen ekipman adını ("Dumbbell", "Leverage Machine", "EZ Bar") iç anahtara çevirir.
  static String? _equipmentKey(String display) {
    final n = display.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    const map = {
      'barbell': 'barbell',
      'dumbbell': 'dumbbell',
      'cable': 'cable',
      'smith': 'smith',
      'smithmachine': 'smith',
      'band': 'band',
      'kettlebell': 'kettlebell',
      'bodyweight': 'bodyweight',
      'leveragemachine': 'leverageMachine',
      'machine': 'leverageMachine',
      'medicineball': 'medicineball',
      'ezbar': 'ezbar',
      'trapbar': 'trapbar',
    };
    return map[n];
  }

  static bool _looksLikeParenWeight(String s) =>
      RegExp(r'^\([+\-]?\d+(\.\d+)?\s*(lb|kg|%)\)$').hasMatch(s.trim());
  static String _stripParens(String s) {
    s = s.trim();
    if (s.startsWith('(') && s.endsWith(')')) return s.substring(1, s.length - 1).trim();
    return s;
  }

  static int _findProgress(String line) {
    final m = RegExp(r'(^|/)\s*progress\s*:').firstMatch(line);
    if (m == null) return -1;
    // 'progress' kelimesinin başlangıcı
    return line.indexOf('progress', m.start);
  }

  static bool _looksLikeSetScheme(String s) => RegExp(r'\d+\s*x\s*\d+').hasMatch(s);
  static bool _looksLikeWeight(String s) =>
      RegExp(r'^[+\-]?\d+(\.\d+)?\s*(lb|kg|%)$').hasMatch(s.trim());

  static Object? _parseWeightOrPct(String s) {
    s = s.trim();
    final pct = RegExp(r'^([+\-]?\d+(\.\d+)?)\s*%$').firstMatch(s);
    if (pct != null) return LPercentage(double.parse(pct.group(1)!));
    final w = RegExp(r'^([+\-]?\d+(\.\d+)?)\s*(lb|kg)$').firstMatch(s);
    if (w != null) return LWeight(double.parse(w.group(1)!), w.group(3)!);
    return null;
  }

  // --- set şeması parse: "2x5, 1x5+ 100lb @8 90s" ---
  static List<PSet> _parseSetScheme(String scheme, {Object? globalWeight, double? globalRpe, int? globalTimer}) {
    final sets = <PSet>[];
    for (var group in scheme.split(',')) {
      group = group.trim();
      if (group.isEmpty) continue;
      // set etiketi: "1x5 (5RM Test)" -> label "5RM Test"
      String? label;
      final labelMatch = RegExp(r'\(([^)]*)\)').firstMatch(group);
      if (labelMatch != null) {
        label = labelMatch.group(1)!.trim();
        group = group.replaceRange(labelMatch.start, labelMatch.end, '').trim();
      }
      // grup içi tokenlar: NxR[+], ağırlık, @rpe, timer
      Object? weight = globalWeight;
      double? rpe = globalRpe;
      int? timer = globalTimer;
      int count = 1;
      int? minRep;
      int? maxRep;
      bool amrap = false;

      // ana NxR kısmı
      final nxr = RegExp(r'(\d+)\s*x\s*(\d+)(?:\s*-\s*(\d+))?\s*(\+)?').firstMatch(group);
      if (nxr != null) {
        count = int.parse(nxr.group(1)!);
        final r1 = int.parse(nxr.group(2)!);
        if (nxr.group(3) != null) {
          minRep = r1;
          maxRep = int.parse(nxr.group(3)!);
        } else {
          maxRep = r1;
        }
        amrap = nxr.group(4) == '+';
      } else {
        // sadece sayı? tek set
        final only = RegExp(r'^(\d+)(\+)?$').firstMatch(group);
        if (only != null) {
          maxRep = int.parse(only.group(1)!);
          amrap = only.group(2) == '+';
        }
      }

      // ek tokenlar (ağırlık/rpe/timer)
      for (final tok in group.split(RegExp(r'\s+'))) {
        if (_looksLikeWeight(tok)) {
          weight = _parseWeightOrPct(tok);
        } else if (tok.startsWith('@')) {
          rpe = double.tryParse(tok.substring(1)) ?? rpe;
        } else if (RegExp(r'^\d+s$').hasMatch(tok)) {
          timer = int.tryParse(tok.substring(0, tok.length - 1));
        }
      }

      for (var i = 0; i < count; i++) {
        sets.add(PSet(
          minReps: minRep,
          maxReps: maxRep,
          weight: weight,
          rpe: rpe,
          timer: timer,
          isAmrap: amrap,
          label: label,
        ));
      }
    }
    return sets;
  }

  // --- progress parse ---
  static ProgressDef? _parseProgress(String raw, {Map<String, _RawExercise>? labelMap}) {
    // "progress: custom(increase: 2.5lb) {~ ... ~}" veya "lp(5lb)" vb.
    final afterColon = raw.replaceFirst(RegExp(r'^progress\s*:\s*'), '');
    final typeMatch = RegExp(r'^(\w+)\s*\(').firstMatch(afterColon);
    if (typeMatch == null) return null;
    final type = typeMatch.group(1)!;
    // argümanlar: ilk '(' ... eşleşen ')'
    final argStart = afterColon.indexOf('(');
    final argEnd = _matchParen(afterColon, argStart);
    if (argEnd < 0) return null;
    final argStr = afterColon.substring(argStart + 1, argEnd);

    // script bloğu {..} veya {~..~}
    String? script;
    final braceStart = afterColon.indexOf('{', argEnd);
    if (braceStart >= 0) {
      final braceEnd = _matchBrace(afterColon, braceStart);
      if (braceEnd >= 0) {
        var body = afterColon.substring(braceStart + 1, braceEnd);
        body = body.replaceAll('~', '').trim();
        // reuse: { ...label }
        final reuseRef = RegExp(r'^\.\.\.(\w+)$').firstMatch(body);
        if (reuseRef != null && labelMap != null) {
          final ref = labelMap[reuseRef.group(1)];
          script = ref?.progress?.script;
        } else {
          script = body;
        }
      }
    }

    if (type == 'custom') {
      return ProgressDef(type: 'custom', args: _parseArgs(argStr), script: script);
    } else if (type == 'lp' || type == 'dp' || type == 'sum') {
      return ProgressDef(type: type, args: _parsePositionalArgs(argStr));
    }
    return ProgressDef(type: type, args: _parseArgs(argStr), script: script);
  }

  /// "increase: 2.5lb, stage: 1" -> {increase: LWeight, stage: 1}
  static Map<String, Object?> _parseArgs(String s) {
    final out = <String, Object?>{};
    for (final part in _splitTopLevel(s, ',')) {
      final kv = part.split(':');
      if (kv.length < 2) continue;
      final key = kv[0].trim();
      final valStr = kv.sublist(1).join(':').trim();
      out[key] = _parseValue(valStr);
    }
    return out;
  }

  /// "5lb, 3" -> {arg0: ..., arg1: ...}
  static Map<String, Object?> _parsePositionalArgs(String s) {
    final out = <String, Object?>{};
    var i = 0;
    for (final part in _splitTopLevel(s, ',')) {
      final t = part.trim();
      if (t.isEmpty) continue;
      // adlı argüman da olabilir
      if (t.contains(':')) {
        final kv = t.split(':');
        out[kv[0].trim()] = _parseValue(kv.sublist(1).join(':').trim());
      } else {
        out['arg$i'] = _parseValue(t);
        i++;
      }
    }
    return out;
  }

  static Object? _parseValue(String s) {
    s = s.trim();
    final wp = _parseWeightOrPct(s);
    if (wp != null) return wp;
    final n = double.tryParse(s);
    if (n != null) return n;
    if (s == 'true') return true;
    if (s == 'false') return false;
    return s;
  }

  // --- reuse çözümü + ProgramExerciseDef üretimi (global şablon haritasıyla) ---
  static List<ProgramExerciseDef> _buildExercises(
    List<_RawExercise> raws,
    Map<String, _RawExercise> weekMap,
    Map<String, _RawExercise> globalMap,
  ) {
    // Gün-yerel şablon haritası: aynı günde SET-ŞEMALI tanımlar (madcow `main`).
    // Reuse hedefi YALNIZ set-şemalı şablonlardır (Liftosaur). Progress-only bir
    // raw (ör. GZCLP'de `...t1` + inline progress taşıyan gün egzersizi) reuse
    // kaynağı OLMAMALI — aksi halde kendini gölgeleyip global şablonu gizler.
    final localMap = <String, _RawExercise>{};
    for (final r in raws) {
      if (r.setSchemes.isEmpty) continue;
      void put(String k) {
        localMap.putIfAbsent(k, () => r);
      }
      if (r.label != null) put(r.label!);
      put(r.name);
    }

    final out = <ProgramExerciseDef>[];
    for (final r in raws) {
      // notUsed şablonları (used: none) workout'a dahil edilmez ama reuse hedefi olabilir
      if (r.notUsed) continue;

      // reuse: set şemaları yoksa referanstan al (önce yerel, sonra global)
      var schemes = r.setSchemes;
      var progress = r.progress;
      Object? gWeight = r.globalWeight;
      double? gRpe = r.globalRpe;
      int? gTimer = r.globalTimer;
      // reuse çözüm sırası: gün-yerel -> O HAFTANIN şablonu -> global
      final ref = r.reuseLabel != null
          ? (localMap[r.reuseLabel] ?? weekMap[r.reuseLabel] ?? globalMap[r.reuseLabel])
          : null;
      if (ref != null) {
        if (schemes.isEmpty) {
          // indeksli reuse (...main[1]): yalnız o varyasyonu al
          if (r.reuseIndex != null &&
              r.reuseIndex! >= 1 &&
              r.reuseIndex! <= ref.setSchemes.length) {
            schemes = [ref.setSchemes[r.reuseIndex! - 1]];
          } else {
            schemes = ref.setSchemes;
          }
        }
        progress ??= ref.progress;
        gWeight ??= ref.globalWeight;
        gRpe ??= ref.globalRpe;
        gTimer ??= ref.globalTimer;
      }

      // her şema -> bir varyasyon
      final variations = <List<PSet>>[];
      for (final scheme in schemes) {
        final sets = _parseSetScheme(scheme,
            globalWeight: gWeight, globalRpe: gRpe, globalTimer: gTimer);
        if (sets.isNotEmpty) variations.add(sets);
      }

      // STABİL key: aynı egzersiz kimliği (etiket+ad+ekipman) tüm gün/haftalarda
      // aynı runtime'ı paylaşır (rm1/ağırlık/sayaç progresyonu birlikte ilerler).
      // GZCLP'de t1=Squat / t2=Squat farklı etiketle ayrılır.
      final key = _stableKey(r.label, r.name, r.equipment);
      out.add(ProgramExerciseDef(
        key: key,
        label: r.label,
        name: r.name,
        equipment: r.equipment,
        setVariations: variations,
        progress: progress,
        supersetName: r.supersetName,
        repeatWeeks: r.repeatWeeks,
      ));
    }
    return out;
  }

  static String _slug(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Stabil egzersiz kimliği: etiket + ad + ekipman (gün/hafta bağımsız).
  static String _stableKey(String? label, String name, String? equipment) =>
      '${label ?? ''}|${_slug(name)}|${equipment ?? ''}';

  // --- yardımcılar ---
  static int _matchParen(String s, int open) => _matchPair(s, open, '(', ')');
  static int _matchBrace(String s, int open) => _matchPair(s, open, '{', '}');
  static int _matchPair(String s, int open, String oc, String cc) {
    var depth = 0;
    for (var i = open; i < s.length; i++) {
      if (s[i] == oc) {
        depth++;
      } else if (s[i] == cc) {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  static List<String> _splitTopLevel(String s, String sep) {
    final out = <String>[];
    var depth = 0;
    var buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == '(' || c == '{' || c == '[') depth++;
      if (c == ')' || c == '}' || c == ']') depth--;
      if (c == sep && depth == 0) {
        out.add(buf.toString());
        buf = StringBuffer();
      } else {
        buf.write(c);
      }
    }
    if (buf.isNotEmpty) out.add(buf.toString());
    return out;
  }
}

class _RawExercise {
  final String name;
  final String? label;
  String? equipment; // "Name, Equipment" sözdiziminden
  String? reuseLabel;
  int? reuseIndex; // ...main[1] -> yalnız o varyasyonu kullan
  final List<String> setSchemes = []; // her biri bir set varyasyonu
  Object? globalWeight;
  double? globalRpe;
  int? globalTimer;
  bool notUsed = false;
  String? supersetName;
  List<int> repeatWeeks = const []; // [1-12] -> bu egzersiz şu haftalarda tekrar eder
  final String? progressRaw;
  ProgressDef? progress;

  _RawExercise({
    required this.name,
    this.label,
    this.progressRaw,
  });

  /// Tekrar-doldurma için kopya (repeatWeeks sıfırlanır; reuse alanları korunur ki
  /// hedef hafta kendi şablonuna göre yeniden çözülsün).
  _RawExercise cloneForRepeat() {
    final c = _RawExercise(name: name, label: label, progressRaw: progressRaw)
      ..equipment = equipment
      ..reuseLabel = reuseLabel
      ..reuseIndex = reuseIndex
      ..globalWeight = globalWeight
      ..globalRpe = globalRpe
      ..globalTimer = globalTimer
      ..notUsed = notUsed
      ..supersetName = supersetName
      ..progress = progress;
    c.setSchemes.addAll(setSchemes);
    return c;
  }
}

class _RawDay {
  final String name;
  final List<_RawExercise> raws;
  _RawDay(this.name, this.raws);
}

class _RawWeek {
  final String name;
  final List<_RawDay> days;
  _RawWeek(this.name, this.days);
}
