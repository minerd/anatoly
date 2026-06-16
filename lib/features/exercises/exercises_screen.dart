import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_scope.dart';
import '../../domain/models.dart';
import '../../ui/markdown.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

class ExercisesScreen extends StatefulWidget {
  const ExercisesScreen({super.key});
  @override
  State<ExercisesScreen> createState() => _ExercisesScreenState();
}

class _ExercisesScreenState extends State<ExercisesScreen> {
  String _q = '';
  String _muscle = 'all';

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = app.t;
    final all = app.exercises;
    final muscles = <String>{'all', ...all.expand((e) => e.bodyParts)};
    var list = all.where((e) => e.name.toLowerCase().contains(_q.toLowerCase())).toList();
    if (_muscle != 'all') {
      list = list.where((e) => e.bodyParts.contains(_muscle)).toList();
    }
    list.sort((a, b) => a.name.compareTo(b.name));

    return Scaffold(
      appBar: AppBar(title: Text(t.s('ex.title'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                  hintText: t.s('ex.search'), prefixIcon: const Icon(Icons.search)),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final m in muscles)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(m == 'all' ? t.s('common.all') : m),
                      selected: _muscle == m,
                      onSelected: (_) => setState(() => _muscle = m),
                      selectedColor: AppColors.accent.withValues(alpha: 0.2),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final e = list[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    padding: const EdgeInsets.all(10),
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => ExerciseDetailScreen(exercise: e))),
                    child: Row(
                      children: [
                        ExerciseImage(type: ExerciseType(e.id, e.defaultEquipment), size: 52),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.name,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                              const SizedBox(height: 2),
                              Text(e.targetMuscles.join(', '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: AppColors.textDim),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ExerciseDetailScreen extends StatelessWidget {
  final Exercise exercise;
  const ExerciseDetailScreen({super.key, required this.exercise});

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).t;
    final type = ExerciseType(exercise.id, exercise.defaultEquipment);
    return Scaffold(
      appBar: AppBar(title: Text(exercise.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(child: ExerciseImage(type: type, size: 220, large: true)),
          const SizedBox(height: 20),
          if (exercise.description.isNotEmpty)
            Text(exercise.description, style: const TextStyle(fontSize: 15, height: 1.4)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in exercise.targetMuscles) TagChip(m),
              for (final m in exercise.synergistMuscles) TagChip(m, color: AppColors.textDim),
            ],
          ),
          if (exercise.equipment.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(t.s('common.equipment'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [for (final eq in exercise.equipment) TagChip(eq, color: AppColors.accent2)],
            ),
          ],
          if (exercise.video != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => launchUrl(
                  Uri.parse('https://www.youtube.com/watch?v=${exercise.video}'),
                  mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.play_circle_outline),
              label: Text(t.s('ex.video')),
              style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: const BorderSide(color: AppColors.surfaceHigh)),
            ),
          ],
          if (exercise.instructions.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(t.s('ex.howto'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            MarkdownText(exercise.instructions),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
