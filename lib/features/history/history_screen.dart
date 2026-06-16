import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../domain/models.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = app.t;
    final history = app.history;
    return Scaffold(
      appBar: AppBar(title: Text(t.s('hist.title'))),
      body: history.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Text(t.s('hist.empty'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textDim, fontSize: 15)),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _BodyweightCard(),
                const SizedBox(height: 8),
                SectionTitle(t.s('hist.workouts')),
                for (final rec in history)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => WorkoutDetailScreen(record: rec))),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(rec.dayName.isEmpty ? rec.programName : rec.dayName,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                                const SizedBox(height: 4),
                                Text(
                                    '${fmtDate(rec.date, t)} • ${t.f('hist.exercisesN', {'n': '${rec.entries.length}'})}'
                                    '${rec.endTime != null ? ' • ${fmtDuration(rec.endTime! - rec.startTime, t)}' : ''}',
                                    style: const TextStyle(color: AppColors.textDim, fontSize: 13)),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: AppColors.textDim),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _BodyweightCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = app.t;
    final bw = app.bodyweight;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.monitor_weight_outlined, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(t.s('hist.bodyweight'),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const Spacer(),
              if (bw.isNotEmpty)
                Text('${bw.first.value.toStringAsFixed(1)} ${app.settings.units}',
                    style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
            ],
          ),
          if (bw.length >= 2) ...[
            const SizedBox(height: 16),
            SizedBox(height: 120, child: _miniChart(bw.reversed.toList())),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _add(context, app),
              icon: const Icon(Icons.add, size: 18),
              label: Text(t.s('hist.addMeasure')),
              style: TextButton.styleFrom(foregroundColor: AppColors.textDim),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniChart(List<StatValue> values) {
    final spots = [
      for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i].value)
    ];
    return LineChart(LineChartData(
      gridData: const FlGridData(show: false),
      titlesData: const FlTitlesData(show: false),
      borderData: FlBorderData(show: false),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: AppColors.accent,
          barWidth: 3,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
              show: true, color: AppColors.accent.withValues(alpha: 0.12)),
        ),
      ],
    ));
  }

  void _add(BuildContext context, dynamic app) async {
    final t = app.t;
    final ctrl = TextEditingController();
    final v = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(t.f('hist.weightPrompt', {'unit': app.settings.units as String})),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t.s('common.cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(context, double.tryParse(ctrl.text.replaceAll(',', '.'))),
            child: Text(t.s('common.add')),
          ),
        ],
      ),
    );
    if (v != null) app.addBodyweight(v);
  }
}

class WorkoutDetailScreen extends StatelessWidget {
  final WorkoutRecord record;
  const WorkoutDetailScreen({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).t;
    return Scaffold(
      appBar: AppBar(title: Text(record.dayName.isEmpty ? t.s('wo.title') : record.dayName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(fmtDate(record.date, t),
              style: const TextStyle(color: AppColors.textDim)),
          const SizedBox(height: 16),
          for (final entry in record.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ExerciseImage(type: entry.exercise, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(entry.exerciseName,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    for (final s in entry.sets.where((s) => s.completed))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                            '${fmtWeight(s.completedWeight ?? s.weight)} × ${s.completedReps ?? s.reps}',
                            style: const TextStyle(color: AppColors.textDim)),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
