import 'dart:convert';

import 'package:anatoly/domain/models.dart';
import 'package:anatoly/planner/program_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ExerciseRuntime.state içinde List/LWeight jsonEncode çökmez ve round-trip korur', () {
    final rt = ExerciseRuntime(
      weights: [const LWeight(100, 'lb'), const LWeight(110, 'lb')],
      setVariationIndex: 2,
      state: {
        'increase': const LWeight(5, 'lb'),
        'stage': 3.0,
        'rm1': const LWeight(225, 'lb'),
        // liftoscript binding dizisi (kritik çökme senaryosu)
        'history': [const LWeight(10, 'lb'), 5.0, const LPercentage(80)],
      },
    );
    final program = StoredProgram(
      id: 'p1',
      name: 'Test',
      plannerText: '# Week 1\n## Day 1\nSquat / 3x5 / 100lb',
      runtime: {'k': rt},
    );

    // jsonEncode ÇÖKMEMELİ (eski hata: List<LWeight> -> JsonUnsupportedObjectError)
    final encoded = jsonEncode(program.toJson());
    expect(encoded, isNotEmpty);

    final back = StoredProgram.fromJson(jsonDecode(encoded) as Map<String, dynamic>);
    final rt2 = back.runtime['k']!;
    expect(rt2.setVariationIndex, 2);
    expect(rt2.weights.first, const LWeight(100, 'lb'));
    expect(rt2.state['increase'], const LWeight(5, 'lb'));
    expect(rt2.state['stage'], 3.0);
    final hist = rt2.state['history'] as List;
    expect(hist[0], const LWeight(10, 'lb'));
    expect(hist[1], 5.0);
    expect(hist[2], const LPercentage(80));
  });

  test('WorkoutSet.originalWeight (yüzde) serileşip geri yükleniyor', () {
    final s = WorkoutSet(
      reps: 5,
      weight: const LWeight(100, 'lb'),
      originalWeight: const LPercentage(70),
      completedReps: 5,
      completedWeight: const LWeight(100, 'lb'),
      completed: true,
    );
    final back = WorkoutSet.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
    expect(back.originalWeight, const LPercentage(70));
    expect(back.weight, const LWeight(100, 'lb'));
    expect(back.completedReps, 5);
  });

  test('WorkoutRecord tam round-trip', () {
    final rec = WorkoutRecord(
      id: 1700000000000,
      startTime: 1700000000000,
      endTime: 1700000003600,
      programId: 'p1',
      programName: 'Test',
      day: 2,
      week: 1,
      dayName: 'Day 2',
      entries: [
        WorkoutEntry(
          exercise: const ExerciseType('squat', 'barbell'),
          exerciseName: 'Squat',
          label: 't1',
          sets: [
            WorkoutSet(reps: 5, weight: const LWeight(100, 'lb'), completed: true, completedReps: 5, completedWeight: const LWeight(100, 'lb')),
          ],
        ),
      ],
    );
    final back = WorkoutRecord.fromJson(jsonDecode(jsonEncode(rec.toJson())) as Map<String, dynamic>);
    expect(back.id, 1700000000000);
    expect(back.entries.length, 1);
    expect(back.entries.first.exercise.equipment, 'barbell');
    expect(back.entries.first.sets.first.completed, true);
  });
}
