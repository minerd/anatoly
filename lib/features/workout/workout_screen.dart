import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_scope.dart';
import '../../domain/models.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'plate_calculator.dart';

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key});
  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  Timer? _ticker;
  int _restRemaining = 0;
  int _restTotal = 0;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startRest(int seconds) {
    _ticker?.cancel();
    setState(() {
      _restTotal = seconds;
      _restRemaining = seconds;
    });
    final app = AppScope.read(context);
    if (app.settings.vibration) HapticFeedback.lightImpact();
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _restRemaining--);
      if (_restRemaining <= 0) {
        t.cancel();
        if (app.settings.vibration) HapticFeedback.mediumImpact();
      }
    });
  }

  void _stopRest() {
    _ticker?.cancel();
    setState(() => _restRemaining = 0);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = app.t;
    final record = app.ongoing;
    if (record == null) {
      return Scaffold(body: Center(child: Text(t.s('wo.noActive'))));
    }

    final totalSets = record.entries.fold<int>(0, (s, e) => s + e.sets.length);
    final doneSets = record.entries
        .fold<int>(0, (s, e) => s + e.sets.where((x) => x.completed).length);

    return Scaffold(
      appBar: AppBar(
        title: Text(record.dayName.isEmpty ? t.s('wo.title') : record.dayName),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _confirmExit(context, app),
        ),
        actions: [
          TextButton(
            onPressed: () => _finish(context, app),
            child: Text(t.s('wo.finish'),
                style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: totalSets == 0 ? 0 : doneSets / totalSets,
            backgroundColor: AppColors.surfaceHigh,
            color: AppColors.accent,
            minHeight: 4,
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16, 16, 16, _restRemaining > 0 ? 180 : 120),
              children: [
                for (var ei = 0; ei < record.entries.length; ei++)
                  _ExerciseCard(
                    entry: record.entries[ei],
                    onChanged: () => app.updateOngoing(),
                    onCompleteSet: (s) {
                      if (s.timer != null && s.timer! > 0) _startRest(s.timer!);
                    },
                  ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _addExercise(context, app),
                  icon: const Icon(Icons.add),
                  label: Text(t.s('wo.addExercise')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    side: const BorderSide(color: AppColors.surfaceHigh),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomSheet: _restRemaining > 0 ? _restBanner() : null,
    );
  }

  Widget _restBanner() {
    final t = AppScope.of(context).t;
    final mins = (_restRemaining ~/ 60).toString().padLeft(2, '0');
    final secs = (_restRemaining % 60).toString().padLeft(2, '0');
    return Container(
      color: AppColors.surfaceHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
          child: Row(
            children: [
              const Icon(Icons.timer_outlined, color: AppColors.accent),
              const SizedBox(width: 12),
              Text('${t.s('wo.rest')}: $mins:$secs',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const Spacer(),
              TextButton(
                  onPressed: () => _startRest(_restTotal + 30), child: const Text('+30s')),
              TextButton(onPressed: _stopRest, child: Text(t.s('wo.skip'))),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _finish(BuildContext context, dynamic app) async {
    final t = app.t;
    final saved = app.finishWorkout() as bool;
    if (!context.mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(saved ? t.s('wo.saved') : t.s('wo.notSaved'))),
    );
  }

  Future<void> _confirmExit(BuildContext context, dynamic app) async {
    final t = app.t;
    final r = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(t.s('wo.exitTitle')),
        content: Text(t.s('wo.exitDesc')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'cancel'), child: Text(t.s('wo.cancelWorkout'), style: const TextStyle(color: AppColors.danger))),
          TextButton(onPressed: () => Navigator.pop(context, 'keep'), child: Text(t.s('wo.continue'))),
          TextButton(onPressed: () => Navigator.pop(context, 'finish'), child: Text(t.s('wo.finish'))),
        ],
      ),
    );
    if (r == 'finish') {
      app.finishWorkout();
      if (context.mounted) Navigator.pop(context);
    } else if (r == 'cancel') {
      app.cancelWorkout();
      if (context.mounted) Navigator.pop(context);
    }
  }

  Future<void> _addExercise(BuildContext context, dynamic app) async {
    final ex = await showModalBottomSheet<Exercise>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _ExercisePicker(exercises: app.exercises),
    );
    if (ex == null) return;
    final entry = WorkoutEntry(
      exercise: ExerciseType(ex.id, ex.defaultEquipment),
      exerciseName: ex.name,
    );
    final unit = app.settings.units;
    entry.sets.add(WorkoutSet(reps: 5, weight: LWeight(ex.startingWeight(unit), unit), timer: app.settings.workoutTimer));
    app.ongoing!.entries.add(entry);
    app.updateOngoing();
  }
}

class _ExerciseCard extends StatelessWidget {
  final WorkoutEntry entry;
  final VoidCallback onChanged;
  final void Function(WorkoutSet) onCompleteSet;
  const _ExerciseCard({required this.entry, required this.onChanged, required this.onCompleteSet});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final eqKey = entry.exercise.equipment ?? 'barbell';
    final eq = app.settings.equipment[eqKey];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ExerciseImage(type: entry.exercise, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (entry.label != null)
                        Text(entry.label!.toUpperCase(),
                            style: const TextStyle(
                                color: AppColors.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      Text(entry.exerciseName,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                if (eq != null && !eq.isFixed && eq.plates.isNotEmpty && entry.sets.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.calculate_outlined, color: AppColors.textDim),
                    onPressed: () {
                      final w = entry.sets.first.weight;
                      if (w != null) {
                        showPlateCalculator(context, w, eq, app.settings.units);
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (entry.warmupSets.isNotEmpty) ...[
              const _SetHeader(warmup: true),
              for (var i = 0; i < entry.warmupSets.length; i++)
                _SetRow(
                  index: i + 1,
                  set: entry.warmupSets[i],
                  unit: app.settings.units,
                  onChanged: onChanged,
                  onComplete: onCompleteSet,
                ),
              const SizedBox(height: 6),
            ],
            const _SetHeader(),
            for (var i = 0; i < entry.sets.length; i++)
              _SetRow(
                index: i + 1,
                set: entry.sets[i],
                unit: app.settings.units,
                onChanged: onChanged,
                onComplete: onCompleteSet,
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  final last = entry.sets.isNotEmpty ? entry.sets.last : null;
                  entry.sets.add(WorkoutSet(
                    reps: last?.reps ?? 5,
                    weight: last?.weight,
                    timer: last?.timer,
                  ));
                  onChanged();
                },
                icon: const Icon(Icons.add, size: 18),
                label: Text(AppScope.of(context).t.s('wo.addSet')),
                style: TextButton.styleFrom(foregroundColor: AppColors.textDim),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetHeader extends StatelessWidget {
  final bool warmup;
  const _SetHeader({this.warmup = false});
  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).t;
    const style = TextStyle(color: AppColors.textDim, fontSize: 11, fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 28, child: Text(warmup ? 'W' : '#', style: style)),
          Expanded(child: Text(t.s('wo.weightCol'), style: style)),
          Expanded(child: Text(t.s('wo.repsCol'), style: style)),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

class _SetRow extends StatelessWidget {
  final int index;
  final WorkoutSet set;
  final String unit;
  final VoidCallback onChanged;
  final void Function(WorkoutSet) onComplete;
  const _SetRow({
    required this.index,
    required this.set,
    required this.unit,
    required this.onChanged,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final target = set.isAmrap
        ? '${set.reps ?? '-'}+'
        : (set.minReps != null ? '${set.minReps}-${set.reps}' : '${set.reps ?? '-'}');
    return InkWell(
      onTap: () => _edit(context),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: set.completed
              ? AppColors.accent.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text('$index',
                  style: TextStyle(
                      color: set.isWarmup ? AppColors.warn : AppColors.textDim,
                      fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: Text(fmtWeight(set.completedWeight ?? set.weight),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: Row(
                children: [
                  Text('${set.completedReps ?? target}',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  if (set.completedReps == null)
                    Text('  / $target',
                        style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
                  if (set.isAmrap)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Text('AMRAP',
                          style: TextStyle(color: AppColors.warn, fontSize: 9, fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            ),
            SizedBox(
              width: 44,
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: Icon(
                  set.completed ? Icons.check_circle : Icons.circle_outlined,
                  color: set.completed ? AppColors.accent : AppColors.textDim,
                ),
                onPressed: () {
                  set.completed = !set.completed;
                  if (set.completed) {
                    set.completedReps ??= set.reps;
                    set.completedWeight ??= set.weight;
                    onComplete(set);
                  }
                  onChanged();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context) async {
    final t = AppScope.of(context).t;
    final repsCtrl = TextEditingController(
        text: (set.completedReps ?? set.reps)?.toString() ?? '');
    final weightCtrl = TextEditingController(
        text: (set.completedWeight ?? set.weight)?.value
                .toString()
                .replaceAll('.0', '') ??
            '');
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        // klavye yüksekliği (viewInsets) içeriği yukarı iter
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          top: false, // alt sistem gezinme çubuğunun üstünde kal
          child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.f('wo.setN', {'n': '$index'}), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: weightCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: '${t.s('home.statWeight')} ($unit)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: repsCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: t.s('wo.repsField')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(t.s('common.save')),
              ),
            ),
          ],
        ),
      ),
      ),
      ),
    );
    if (ok == true) {
      final reps = int.tryParse(repsCtrl.text);
      final wv = double.tryParse(weightCtrl.text.replaceAll(',', '.'));
      if (reps != null) set.completedReps = reps;
      if (wv != null) set.completedWeight = LWeight(wv, unit);
      set.completed = true;
      onChanged();
    }
    repsCtrl.dispose();
    weightCtrl.dispose();
  }
}

class _ExercisePicker extends StatefulWidget {
  final List<Exercise> exercises;
  const _ExercisePicker({required this.exercises});
  @override
  State<_ExercisePicker> createState() => _ExercisePickerState();
}

class _ExercisePickerState extends State<_ExercisePicker> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final list = widget.exercises
        .where((e) => e.name.toLowerCase().contains(_q.toLowerCase()))
        .toList();
    return Padding(
      padding: EdgeInsets.only(
          left: 16, right: 16, top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                  hintText: AppScope.of(context).t.s('ex.search'),
                  prefixIcon: const Icon(Icons.search)),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                // son öğeler alt sistem gezinme çubuğunun üstünde kalsın
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewPadding.bottom + 8),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final e = list[i];
                  return ListTile(
                    leading: ExerciseImage(
                        type: ExerciseType(e.id, e.defaultEquipment), size: 40),
                    title: Text(e.name),
                    subtitle: Text(e.targetMuscles.join(', '),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
                    onTap: () => Navigator.pop(context, e),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
