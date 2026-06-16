import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../planner/planner_parser.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../workout/workout_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = app.t;
    final program = app.currentProgram;
    final ongoing = app.ongoing;

    String? nextDayName;
    int nextDayExCount = 0;
    if (program != null) {
      final parsed = PlannerParser.parse(program.plannerText);
      final flat = parsed.flatDays();
      if (flat.isNotEmpty) {
        final info = flat[(program.nextDay - 1) % flat.length];
        nextDayName = info.day.name;
        nextDayExCount = info.day.exercises.where((e) => !e.notUsed).length;
      }
    }

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 8),
            const Text('Anatoly',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
            Text(t.s('home.greeting'),
                style: const TextStyle(color: AppColors.textDim, fontSize: 15)),
            const SizedBox(height: 20),

            // devam eden antrenman
            if (ongoing != null)
              _bigCard(
                context,
                title: t.s('home.ongoing'),
                subtitle: ongoing.dayName,
                buttonText: t.s('home.continue'),
                color: AppColors.warn,
                onTap: () => _openWorkout(context),
              )
            else if (program != null)
              _bigCard(
                context,
                title: program.name,
                subtitle: nextDayName != null
                    ? '${t.s('home.next')}: $nextDayName • ${t.f('home.exercisesN', {'n': '$nextDayExCount'})}'
                    : t.s('home.ready'),
                buttonText: t.s('home.start'),
                onTap: () {
                  app.startWorkout();
                  _openWorkout(context);
                },
              )
            else
              _emptyProgramCard(context, app, t),

            const SizedBox(height: 24),

            // hızlı istatistikler
            Row(
              children: [
                Expanded(child: _statCard(t.s('home.statWorkouts'), '${app.history.length}', Icons.event_available)),
                const SizedBox(width: 12),
                Expanded(child: _statCard(t.s('home.statPrograms'), '${app.programs.length}', Icons.list_alt)),
                const SizedBox(width: 12),
                Expanded(
                    child: _statCard(
                        t.s('home.statWeight'),
                        app.bodyweight.isNotEmpty
                            ? '${app.bodyweight.first.value.toStringAsFixed(0)}${app.settings.units}'
                            : '—',
                        Icons.monitor_weight_outlined)),
              ],
            ),

            const SizedBox(height: 24),

            // son aktivite
            if (app.history.isNotEmpty) ...[
              SectionTitle(t.s('home.recent')),
              for (final rec in app.history.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.check, color: AppColors.accent),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(rec.dayName.isEmpty ? rec.programName : rec.dayName,
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text(fmtDate(rec.date, t),
                                  style: const TextStyle(color: AppColors.textDim, fontSize: 13)),
                            ],
                          ),
                        ),
                        Text(t.f('home.exAbbr', {'n': '${rec.entries.length}'}),
                            style: const TextStyle(color: AppColors.textDim)),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  void _openWorkout(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WorkoutScreen()),
    );
  }

  Widget _bigCard(BuildContext context,
      {required String title,
      required String subtitle,
      required String buttonText,
      required VoidCallback onTap,
      Color color = AppColors.accent}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.22), AppColors.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: AppColors.textDim, fontSize: 14)),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(backgroundColor: color),
              child: Text(buttonText),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyProgramCard(BuildContext context, dynamic app, dynamic t) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.s('home.noProgram'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(t.s('home.noProgramDesc'),
              style: const TextStyle(color: AppColors.textDim)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    app.startWorkout();
                    Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const WorkoutScreen()));
                  },
                  child: Text(t.s('home.freeWorkout')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.accent, size: 20),
          const SizedBox(height: 10),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
        ],
      ),
    );
  }
}
