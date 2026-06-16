/// Liftoscript çalışma zamanı: bindings, built-in fonksiyonlar, evaluator.
///
/// Kullanım: bir progress script'ini bir workout sonrası çalıştırıp `state` ve
/// `weights`/`setVariationIndex` gibi binding'leri mutasyona uğratmak.
library;

import 'dart:math' as math;

import 'ast.dart';
import 'parser.dart';
import 'value.dart';

/// Ağırlık yuvarlayıcı — ekipman/plaka ayarlarına göre (Faz 2'de enjekte edilir).
typedef WeightRounder = LWeight Function(LWeight weight, String unit);

/// Varsayılan yuvarlayıcı: lb için 2.5'e, kg için 1.25'e yuvarla.
LWeight defaultRounder(LWeight w, String unit) {
  final step = unit == 'kg' ? 1.25 : 2.5;
  return LWeight((w.value / step).round() * step, unit);
}

/// Script'e açılan değişkenler.
class ScriptBindings {
  final Map<String, List<Object?>> arrays;
  final Map<String, Object?> scalars;

  ScriptBindings({Map<String, List<Object?>>? arrays, Map<String, Object?>? scalars})
      : arrays = arrays ?? {},
        scalars = scalars ?? {};

  static const Map<String, String> _alias = {
    'w': 'weights',
    'r': 'reps',
    'cr': 'completedReps',
    'cw': 'completedWeights',
    'mr': 'minReps',
    'ns': 'numberOfSets',
  };

  String _canon(String name) => _alias[name] ?? name;

  bool isArray(String name) => arrays.containsKey(_canon(name));
  bool isScalar(String name) => scalars.containsKey(_canon(name));
  bool has(String name) => isArray(name) || isScalar(name);

  List<Object?> array(String name) => arrays[_canon(name)]!;
  Object? scalar(String name) => scalars[_canon(name)];
  void setScalar(String name, Object? v) => scalars[_canon(name)] = v;
}

/// Egzersizin kalıcı state'i: değişken adı -> num | LWeight | LPercentage.
typedef ProgramState = Map<String, Object?>;

class EvalException implements Exception {
  final String message;
  final int pos;
  EvalException(this.message, this.pos);
  @override
  String toString() => 'EvalException@$pos: $message';
}

class Evaluator {
  final ScriptBindings bindings;
  final ProgramState state;
  final WeightRounder rounder;
  final Map<int, ProgramState> otherStates; // state[idx].key için (tag bazlı)
  final List<Object?> prints = [];
  final Map<String, Object?> _locals = {};

  Evaluator({
    required this.bindings,
    required this.state,
    WeightRounder? rounder,
    Map<int, ProgramState>? otherStates,
  })  : rounder = rounder ?? defaultRounder,
        otherStates = otherStates ?? {};

  LWeight? get _onerm {
    final v = bindings.scalar('rm1');
    return v is LWeight ? v : null;
  }

  Object? run(ProgramNode program) {
    Object? last;
    for (final n in program.body) {
      last = _eval(n);
    }
    return last;
  }

  Object? _eval(Node node) {
    switch (node) {
      case NumberNode n:
        return n.value;
      case WeightNode n:
        // Referans Weight_parse 2 ondalığa yuvarlar.
        return LWeight(roundFloat(n.value, 2), n.unit);
      case PercentageNode n:
        return LPercentage(roundFloat(n.value, 2));
      case BlockNode n:
        Object? last;
        for (final e in n.body) {
          last = _eval(e);
        }
        return last;
      case ProgramNode n:
        return run(n);
      case UnaryNode n:
        if (n.op == '!') return !toBool(_eval(n.operand));
        final v = _eval(n.operand);
        if (n.op == '-') return applyArith(0, v, (a, b) => a - b, onerm: _onerm);
        return v; // unary +
      case BinaryNode n:
        return _binary(n);
      case TernaryNode n:
        return toBool(_eval(n.cond)) ? _eval(n.ifTrue) : _eval(n.ifFalse);
      case IfNode n:
        for (final (cond, block) in n.branches) {
          if (toBool(_eval(cond))) return _eval(block);
        }
        if (n.elseBlock != null) return _eval(n.elseBlock!);
        return null;
      case ForNode n:
        return _forLoop(n);
      case LocalVarNode n:
        return _locals[n.name];
      case StateVarNode n:
        return _readState(n);
      case VarNode n:
        return _readVar(n);
      case CallNode n:
        return _call(n);
      case AssignNode n:
        return _assign(n);
    }
  }

  Object? _binary(BinaryNode n) {
    final op = n.op;
    if (op == '&&') return toBool(_eval(n.left)) && toBool(_eval(n.right));
    if (op == '||') return toBool(_eval(n.left)) || toBool(_eval(n.right));
    final l = _eval(n.left);
    final r = _eval(n.right);
    if (op == '==' || op == '!=' || op == '>' || op == '<' || op == '>=' || op == '<=') {
      return comparing(l, r, op);
    }
    if (l is List || r is List) {
      throw EvalException('Dizilere "$op" uygulanamaz', n.pos);
    }
    switch (op) {
      case '+':
        return applyArith(l, r, (a, b) => a + b, onerm: _onerm);
      case '-':
        return applyArith(l, r, (a, b) => a - b, onerm: _onerm);
      case '*':
        // Referans Weight_op binary çarpmada YUVARLAMAZ (yuvarlama yalnız *= atamasında).
        return applyArith(l, r, (a, b) => a * b, onerm: _onerm);
      case '/':
        return applyArith(l, r, (a, b) => a / b, onerm: _onerm);
      case '%':
        return applyArith(l, r, (a, b) => a % b, onerm: _onerm);
    }
    throw EvalException('Bilinmeyen operatör $op', n.pos);
  }

  Object? _forLoop(ForNode n) {
    final iter = _eval(n.iterable);
    if (iter is! List) throw EvalException('for döngüsü dizi bekler', n.pos);
    // Liftosaur: döngü değişkeni 1-based İNDEKS (değer değil).
    for (var i = 1; i <= iter.length; i++) {
      _locals[n.varName] = i;
      _eval(n.block);
    }
    return iter.length.toDouble();
  }

  // ---- okuma ----
  Object? _readVar(VarNode n) {
    if (!bindings.has(n.name)) {
      // bilinmeyen değişken: 0 (Liftosaur toleranslı davranır)
      return 0;
    }
    if (n.indices == null) {
      return bindings.isArray(n.name) ? bindings.array(n.name) : bindings.scalar(n.name);
    }
    // indeksli okuma
    if (bindings.isArray(n.name)) {
      final arr = bindings.array(n.name);
      final idx = _resolveSingleIndex(n.indices!);
      if (idx == null) return arr; // wildcard => tüm dizi
      final i = idx - 1; // 1-based
      return (i >= 0 && i < arr.length) ? arr[i] : null;
    }
    return bindings.scalar(n.name);
  }

  /// Set indeks değerini çöz (wildcard ise null).
  /// Çok-parçalı indekste (`[week:day:variation:set]`) set indeksi SON parçadır
  /// (referans normalizeTarget hedefi sola `*` ile doldurur).
  int? _resolveSingleIndex(List<IndexPart> parts) {
    final p = parts.last;
    if (p.isWildcard) return null;
    final v = _eval(p.expr!);
    if (v is num) return v.toInt();
    if (v is LWeight) return v.value.toInt();
    return null;
  }

  Object? _readState(StateVarNode n) {
    if (n.indexExpr != null) {
      final idx = _eval(n.indexExpr!);
      final tag = idx is num ? idx.toInt() : null;
      if (tag != null && otherStates.containsKey(tag)) {
        return otherStates[tag]![n.key];
      }
      return state[n.key];
    }
    return state[n.key];
  }

  // ---- atama ----
  Object? _assign(AssignNode n) {
    final rhs = _eval(n.value);
    final target = n.target;
    if (target is LocalVarNode) {
      _locals[target.name] = _applyOp(_locals[target.name], rhs, n.op);
      return _locals[target.name];
    }
    if (target is StateVarNode) {
      ProgramState st = state;
      if (target.indexExpr != null) {
        final idx = _eval(target.indexExpr!);
        final tag = idx is num ? idx.toInt() : null;
        if (tag != null) st = otherStates.putIfAbsent(tag, () => {});
      }
      st[target.key] = _applyOp(st[target.key], rhs, n.op);
      return st[target.key];
    }
    if (target is VarNode) {
      return _assignVar(target, rhs, n.op);
    }
    throw EvalException('Geçersiz atama hedefi', n.pos);
  }

  Object? _assignVar(VarNode target, Object? rhs, String op) {
    if (!bindings.has(target.name)) {
      // bilinmeyen binding: yok say
      return rhs;
    }
    if (bindings.isScalar(target.name)) {
      final cur = bindings.scalar(target.name);
      bindings.setScalar(target.name, _applyOp(cur, rhs, op));
      return bindings.scalar(target.name);
    }
    // dizi binding
    final arr = bindings.array(target.name);
    if (target.indices == null) {
      // tüm elemanlara uygula
      for (var i = 0; i < arr.length; i++) {
        arr[i] = _applyOp(arr[i], rhs, op);
      }
      return arr;
    }
    final idx = _resolveSingleIndex(target.indices!);
    if (idx == null) {
      // wildcard => tüm elemanlar
      for (var i = 0; i < arr.length; i++) {
        arr[i] = _applyOp(arr[i], rhs, op);
      }
      return arr;
    }
    final i = idx - 1;
    if (i >= 0 && i < arr.length) {
      arr[i] = _applyOp(arr[i], rhs, op);
    }
    return arr;
  }

  Object? _applyOp(Object? cur, Object? rhs, String op) {
    switch (op) {
      case '=':
        return rhs;
      case '+=':
        return applyArith(cur, rhs, (a, b) => a + b, onerm: _onerm);
      case '-=':
        return applyArith(cur, rhs, (a, b) => a - b, onerm: _onerm);
      case '*=':
        return applyArith(cur, rhs, (a, b) => roundTo005(a * b), onerm: _onerm);
      case '/=':
        return applyArith(cur, rhs, (a, b) => roundTo005(a / b), onerm: _onerm);
    }
    throw StateError('Bilinmeyen atama operatörü $op');
  }

  // ---- built-in fonksiyonlar ----
  Object? _call(CallNode n) {
    final name = n.name;
    List<Object?> args() => n.args.map(_eval).toList();

    switch (name) {
      case 'roundWeight':
      case 'roundConvertWeight':
        {
          final v = _eval(n.args.first);
          return _round(v);
        }
      case 'floor':
        return _mathUnary(_eval(n.args.first), (x) => x.floorToDouble());
      case 'ceil':
        return _mathUnary(_eval(n.args.first), (x) => x.ceilToDouble());
      case 'round':
        return _mathUnary(_eval(n.args.first), (x) => x.roundToDouble());
      case 'sum':
        return _reduce(args(), (a, b) => a + b, 0);
      case 'min':
        return _minmax(args(), true);
      case 'max':
        return _minmax(args(), false);
      case 'increment':
        return _round(applyArith(_eval(n.args.first), _incrementUnit(_eval(n.args.first)),
            (a, b) => a + b, onerm: _onerm));
      case 'decrement':
        return _round(applyArith(_eval(n.args.first), _incrementUnit(_eval(n.args.first)),
            (a, b) => a - b, onerm: _onerm));
      case 'calculate1RM':
        {
          final a = args();
          final w = a[0];
          final reps = (a[1] as num).toInt();
          return _oneRepMax(w, reps);
        }
      case 'calculateTrainingMax':
        {
          final a = args();
          final w = a[0];
          final reps = (a[1] as num).toInt();
          final orm = _oneRepMax(w, reps);
          if (orm is LWeight) return _round(LWeight(orm.value * 0.9, orm.unit));
          return orm;
        }
      case 'rpeMultiplier':
        {
          final a = args();
          final reps = (a[0] as num).toInt();
          final rpe = (a[1] as num).toDouble();
          return _rpeMultiplier(reps, rpe);
        }
      case 'zeroOrGte':
        {
          final a = args();
          final x = a[0];
          final y = a[1];
          if (x is List && y is List) {
            for (var i = 0; i < x.length; i++) {
              final xv = x[i];
              final yv = i < y.length ? y[i] : null;
              if (!(_isZero(xv) || compareScalar(xv ?? 0, yv ?? 0, '>='))) return false;
            }
            return true;
          }
          return _isZero(x) || compareScalar(x ?? 0, y ?? 0, '>=');
        }
      case 'print':
        {
          final a = args();
          prints.addAll(a);
          return a.isNotEmpty ? a.first : null;
        }
      case 'sets':
        return _sets(args());
      default:
        throw EvalException('Bilinmeyen fonksiyon "$name"', n.pos);
    }
  }

  bool _isZero(Object? v) {
    if (v == null) return true;
    if (v is num) return v == 0;
    if (v is LWeight) return v.value == 0;
    if (v is LPercentage) return v.value == 0;
    return false;
  }

  Object _round(Object? v) {
    if (v is LWeight) return rounder(v, v.unit);
    if (v is num) return v;
    if (v is LPercentage) return v;
    return v ?? 0;
  }

  Object _incrementUnit(Object? v) {
    if (v is LWeight) return LWeight(v.unit == 'kg' ? 1.25 : 2.5, v.unit);
    if (v is LPercentage) return const LPercentage(1);
    return 1;
  }

  Object _mathUnary(Object? v, double Function(double) f) {
    if (v is LWeight) return LWeight(f(v.value), v.unit);
    if (v is LPercentage) return LPercentage(f(v.value));
    if (v is num) return f(v.toDouble());
    return 0;
  }

  /// Argümanları (dizi olabilir) düzleştirip indirger.
  Object _reduce(List<Object?> args, double Function(double, double) op, double seed) {
    final flat = <Object?>[];
    for (final a in args) {
      if (a is List) {
        flat.addAll(a);
      } else {
        flat.add(a);
      }
    }
    if (flat.isEmpty) return seed;
    Object? acc = flat.first ?? 0;
    for (var i = 1; i < flat.length; i++) {
      acc = applyArith(acc, flat[i] ?? 0, op, onerm: _onerm);
    }
    return acc ?? seed;
  }

  Object _minmax(List<Object?> args, bool wantMin) {
    final flat = <Object?>[];
    for (final a in args) {
      if (a is List) {
        flat.addAll(a);
      } else {
        flat.add(a);
      }
    }
    flat.removeWhere((e) => e == null);
    if (flat.isEmpty) return 0;
    Object? best = flat.first;
    for (final v in flat.skip(1)) {
      final cmp = compareScalar(v, best, wantMin ? '<' : '>');
      if (cmp) best = v;
    }
    return best ?? 0;
  }

  /// 1RM (referans Weight_getOneRepMax): reps==0 -> 0, reps==1 -> w,
  /// aksi halde w / rpeMultiplier(reps, 10). (Epley DEĞİL — RPE eğrisi.)
  Object _oneRepMax(Object? w, int reps) {
    if (reps == 0) return w is LWeight ? LWeight(0, w.unit) : 0;
    if (reps == 1) return w ?? 0;
    final m = _rpeMultiplier(reps, 10);
    if (w is LWeight) return LWeight(roundTo005(w.value / m), w.unit);
    if (w is num) return roundTo005(w.toDouble() / m);
    return w ?? 0;
  }

  /// RPE çarpanı (openpowerlifting eğrisi) — 1RM'in yüzdesi, daima <= 1.
  double _rpeMultiplier(int reps, double rpe) {
    if (reps == 1 && rpe == 10) return 1.0;
    final r = reps.clamp(1, 24);
    final rp = rpe.clamp(1.0, 10.0);
    final x = 10.0 - rp + (r - 1);
    if (x >= 16) return 0.5;
    const intersection = 2.92;
    if (x <= intersection) {
      return (0.347619 * x * x - 4.60714 * x + 99.9667) / 100.0;
    }
    return (-2.64249 * x + 97.0955) / 100.0;
  }

  /// sets(from, to, minReps, reps, isAmrap, weight, timer, rpe, logRpe)
  /// Referans davranışı: numberOfSets ile sınırlı, ağırlık rm1'e göre çözülüp
  /// yuvarlanır, minReps==reps ise null, amraps/logrpes 1/0'a normalize, rpe/timer 0->null.
  Object _sets(List<Object?> a) {
    int asInt(Object? v) => v is num ? v.toInt() : 0;
    final from = asInt(a[0]);
    final to = asInt(a[1]);
    final minReps = a.length > 2 ? a[2] : null;
    final reps = a.length > 3 ? a[3] : null;
    final isAmrap = a.length > 4 ? a[4] : null;
    final weight = a.length > 5 ? a[5] : null;
    final timer = a.length > 6 ? a[6] : null;
    final rpe = a.length > 7 ? a[7] : null;
    final logRpe = a.length > 8 ? a[8] : null;

    final ns = bindings.isScalar('numberOfSets')
        ? asInt(bindings.scalar('numberOfSets'))
        : (bindings.isArray('reps') ? bindings.array('reps').length : 0);

    void put(String name, int idx, Object? value) {
      if (!bindings.isArray(name)) return;
      final arr = bindings.array(name);
      if (idx >= 0 && idx < arr.length) arr[idx] = value;
    }

    // ağırlığı çöz: LPercentage -> rm1*pct, sonra yuvarla
    Object? convertedWeight;
    if (weight is LPercentage && _onerm != null) {
      convertedWeight = _round(LWeight(_onerm!.value * weight.value / 100, _onerm!.unit));
    } else if (weight is LWeight) {
      convertedWeight = _round(weight);
    } else {
      convertedWeight = weight;
    }

    final repsEqMin = reps != null && minReps != null && reps == minReps;
    for (var i = 0; i < ns; i++) {
      if (i < from - 1 || i >= to) continue;
      put('weights', i, convertedWeight);
      put('originalWeights', i, weight);
      put('reps', i, reps);
      put('minReps', i, repsEqMin ? null : minReps);
      put('RPE', i, (rpe is num && rpe != 0) ? rpe : null);
      put('amraps', i, (isAmrap is num && isAmrap != 0) ? 1 : 0);
      put('logrpes', i, (logRpe is num && logRpe != 0) ? 1 : 0);
      put('timers', i, (timer is num && timer != 0) ? timer : null);
    }
    return (to - from).toDouble();
  }
}

/// Public API: bir script'i parse edip çalıştırır.
class ScriptRunner {
  final ProgramNode program;
  final String source;
  ScriptRunner(this.source) : program = Parser(source).parseProgram();

  /// [bindings] ve [state] yerinde mutasyona uğrar; son ifade değeri döner.
  Object? run(
    ScriptBindings bindings,
    ProgramState state, {
    WeightRounder? rounder,
    Map<int, ProgramState>? otherStates,
    List<Object?>? prints,
  }) {
    final ev = Evaluator(
      bindings: bindings,
      state: state,
      rounder: rounder,
      otherStates: otherStates,
    );
    final result = ev.run(program);
    if (prints != null) prints.addAll(ev.prints);
    return result;
  }

  /// Tek bir ifade olarak değerlendir (parse hatalarını yüzeye çıkarır).
  static Object? evalExpression(
    String src,
    ScriptBindings bindings,
    ProgramState state, {
    WeightRounder? rounder,
  }) {
    final runner = ScriptRunner(src);
    return runner.run(bindings, state, rounder: rounder);
  }
}

/// math importu kullanılıyor (gelecekte trig/log için); şimdilik referans.
// ignore: unused_element
final _ensureMath = math.e;
