import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../domain/models.dart';
import '../../liftoscript/value.dart' show weightConvertTo;
import '../../ui/i18n.dart';
import '../../planner/planner_parser.dart';
import '../../planner/program_models.dart';
import '../../ui/markdown.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../workout/workout_screen.dart';

class ProgramsScreen extends StatefulWidget {
  const ProgramsScreen({super.key});
  @override
  State<ProgramsScreen> createState() => _ProgramsScreenState();
}

class _ProgramsScreenState extends State<ProgramsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  String _goalFilter = 'all';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = app.t;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.s('pr.title')),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.textDim,
          tabs: [Tab(text: t.s('pr.library')), Tab(text: t.s('pr.discover'))],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_library(app), _discover(app)],
      ),
    );
  }

  Widget _library(dynamic app) {
    final t = app.t;
    final programs = app.programs as List<StoredProgram>;
    if (programs.isEmpty) {
      return _empty(t.s('pr.empty'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final p in programs)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _LibraryCard(
              program: p,
              isCurrent: app.currentProgramId == p.id,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => ProgramDetailScreen(program: p))),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _createEmpty(app),
          icon: const Icon(Icons.add),
          label: Text(t.s('pr.createEmpty')),
          style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: const BorderSide(color: AppColors.surfaceHigh),
              padding: const EdgeInsets.symmetric(vertical: 16)),
        ),
      ],
    );
  }

  Widget _discover(dynamic app) {
    final t = app.t;
    final all = app.builtinPrograms as List<Map<String, dynamic>>;
    final goals = <String>{'all', ...all.map((p) => (p['goal'] ?? '').toString()).where((g) => g.isNotEmpty)};
    final filtered = _goalFilter == 'all'
        ? all
        : all.where((p) => p['goal'] == _goalFilter).toList();
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final g in goals)
                Padding(
                  padding: const EdgeInsets.only(right: 8, top: 8),
                  child: ChoiceChip(
                    label: Text(g == 'all' ? t.s('common.all') : goalLabel(t, g)),
                    selected: _goalFilter == g,
                    onSelected: (_) => setState(() => _goalFilter = g),
                    selectedColor: AppColors.accent.withValues(alpha: 0.2),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: filtered.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _BuiltinCard(
                data: filtered[i],
                onTap: () => _previewBuiltin(app, filtered[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _createEmpty(dynamic app) async {
    final t = app.t;
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(t.s('pr.new')),
        content: TextField(controller: ctrl, decoration: InputDecoration(hintText: t.s('pr.name'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t.s('common.cancel'))),
          TextButton(onPressed: () => Navigator.pop(context, ctrl.text), child: Text(t.s('common.create'))),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      app.createEmptyProgram(name.trim());
    }
  }

  void _previewBuiltin(dynamic app, Map<String, dynamic> data) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => BuiltinPreviewScreen(data: data)));
  }

  Widget _empty(String msg) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text(msg,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textDim, fontSize: 15)),
        ),
      );

}

/// Hedef adını çevirir (strength/hypertrophy/endurance); bilinmeyenleri olduğu gibi döner.
String goalLabel(Strings t, String g) {
  switch (g) {
    case 'strength':
      return t.s('goal.strength');
    case 'hypertrophy':
      return t.s('goal.hypertrophy');
    case 'endurance':
      return t.s('goal.endurance');
    default:
      return g;
  }
}

class _LibraryCard extends StatelessWidget {
  final StoredProgram program;
  final bool isCurrent;
  final VoidCallback onTap;
  const _LibraryCard({required this.program, required this.isCurrent, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).t;
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(program.name,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    ),
                    if (isCurrent) ...[
                      const SizedBox(width: 8),
                      TagChip(t.s('pr.active')),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(program.author.isEmpty ? t.s('pr.custom') : program.author,
                    style: const TextStyle(color: AppColors.textDim, fontSize: 13)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textDim),
        ],
      ),
    );
  }
}

class _BuiltinCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  const _BuiltinCard({required this.data, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).t;
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(data['name'] as String,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          if ((data['author'] as String?)?.isNotEmpty ?? false)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(data['author'] as String,
                  style: const TextStyle(color: AppColors.textDim, fontSize: 13)),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if ((data['goal'] as String?)?.isNotEmpty ?? false)
                TagChip(goalLabel(t, data['goal'] as String)),
              if (data['frequency'] != null)
                TagChip(t.f('pr.freqN', {'n': '${data['frequency']}'}), color: AppColors.accent2),
              if ((data['duration'] as String?)?.isNotEmpty ?? false)
                TagChip(t.f('pr.durN', {'n': '${data['duration']}'}), color: AppColors.warn),
            ],
          ),
        ],
      ),
    );
  }
}

/// Hazır program önizleme + klonla.
class BuiltinPreviewScreen extends StatelessWidget {
  final Map<String, dynamic> data;
  const BuiltinPreviewScreen({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = app.t;
    final parsed = PlannerParser.parse(data['script'] as String);
    return Scaffold(
      appBar: AppBar(title: Text(data['name'] as String)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if ((data['description'] as String?)?.isNotEmpty ?? false)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: MarkdownText(data['description'] as String),
            ),
          for (var wi = 0; wi < parsed.weeks.length; wi++) ...[
            if (parsed.weeks.length > 1) SectionTitle(parsed.weeks[wi].name),
            for (final day in parsed.weeks[wi].days)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(day.name,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      for (final ex in day.exercises.where((e) => !e.notUsed))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              if (ex.label != null)
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Text(ex.label!.toUpperCase(),
                                      style: const TextStyle(
                                          color: AppColors.accent,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700)),
                                ),
                              Expanded(child: Text(ex.name)),
                              Text(_setSummary(ex),
                                  style: const TextStyle(color: AppColors.textDim, fontSize: 13)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                app.cloneBuiltin(data);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(t.f('pr.addedN', {'name': '${data['name']}'}))),
                );
              },
              child: Text(t.s('pr.use')),
            ),
          ),
        ),
      ),
    );
  }

  static String _setSummary(ProgramExerciseDef ex) {
    if (ex.setVariations.isEmpty) return '';
    final sets = ex.setVariations.first;
    if (sets.isEmpty) return '';
    final reps = sets.first.maxReps;
    return '${sets.length}×${reps ?? '-'}';
  }
}

/// Kütüphane programı detayı.
class ProgramDetailScreen extends StatelessWidget {
  final StoredProgram program;
  const ProgramDetailScreen({super.key, required this.program});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = app.t;
    final parsed = PlannerParser.parse(program.plannerText);
    final isCurrent = app.currentProgramId == program.id;
    return Scaffold(
      appBar: AppBar(
        title: Text(program.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: AppColors.surface,
                  title: Text(t.s('pr.deleteConfirm')),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.s('common.cancel'))),
                    TextButton(onPressed: () => Navigator.pop(context, true), child: Text(t.s('common.delete'), style: const TextStyle(color: AppColors.danger))),
                  ],
                ),
              );
              if (ok == true) {
                app.deleteProgram(program.id);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!isCurrent)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FilledButton.icon(
                onPressed: () => app.selectProgram(program.id),
                icon: const Icon(Icons.check),
                label: Text(t.s('pr.makeActive')),
              ),
            ),
          _rm1Section(context, app, parsed),
          for (var wi = 0; wi < parsed.weeks.length; wi++) ...[
            if (parsed.weeks.length > 1) SectionTitle(parsed.weeks[wi].name),
            for (final day in parsed.weeks[wi].days)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(day.name,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      for (final ex in day.exercises.where((e) => !e.notUsed))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Text('• ${ex.name}',
                              style: const TextStyle(color: AppColors.textDim)),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                app.selectProgram(program.id);
                app.startWorkout(program: program);
                Navigator.pushReplacement(
                    context, MaterialPageRoute(builder: (_) => const WorkoutScreen()));
              },
              child: Text(t.s('pr.start')),
            ),
          ),
        ),
      ),
    );
  }

  /// Yüzde-bazlı egzersizler için 1RM / antrenman maksimumu ayar bölümü.
  Widget _rm1Section(BuildContext context, dynamic app, ParsedProgram parsed) {
    // benzersiz yüzde-bazlı egzersizler (stabil key'e göre)
    final seen = <String>{};
    final pct = <ProgramExerciseDef>[];
    for (final w in parsed.weeks) {
      for (final d in w.days) {
        for (final ex in d.exercises) {
          if (ex.notUsed || seen.contains(ex.key)) continue;
          final isPct = ex.setVariations
              .any((v) => v.any((s) => s.weight is LPercentage));
          if (isPct) {
            seen.add(ex.key);
            pct.add(ex);
          }
        }
      }
    }
    if (pct.isEmpty) return const SizedBox.shrink();

    final t = app.t;
    final unit = app.settings.units as String;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(t.s('pr.rm1Title')),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              t.s('pr.rm1Desc'),
              style: const TextStyle(color: AppColors.textDim, fontSize: 13),
            ),
          ),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < pct.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    title: Text(pct[i].name),
                    subtitle: pct[i].label != null
                        ? Text(pct[i].label!.toUpperCase(),
                            style: const TextStyle(color: AppColors.accent, fontSize: 11))
                        : null,
                    trailing: Builder(builder: (_) {
                      final rm1 = app.exerciseRm1(program, pct[i].key) as LWeight?;
                      return Text(
                        rm1 != null ? fmtWeight(rm1) : t.s('common.set'),
                        style: TextStyle(
                          color: rm1 != null ? AppColors.accent : AppColors.textDim,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      );
                    }),
                    onTap: () => _editRm1(context, app, pct[i], unit),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _editRm1(
      BuildContext context, dynamic app, ProgramExerciseDef ex, String unit) async {
    final t = app.t;
    final current = app.exerciseRm1(program, ex.key) as LWeight?;
    // mevcut değeri görüntü birimine çevir (birim değişmiş olabilir)
    final shown = current != null ? weightConvertTo(current, unit) : null;
    final ctrl = TextEditingController(
        text: shown != null ? _trimNum(shown.value) : '');
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(t.f('pr.rm1DialogTitle', {'name': ex.name, 'unit': unit})),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(hintText: t.s('pr.rm1Hint')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.s('common.cancel'))),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(ctrl.text.replaceAll(',', '.'))),
            child: Text(t.s('common.save')),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (value != null && value > 0) {
      app.setExerciseRm1(program, ex.key, LWeight(value, unit));
    }
  }

  static String _trimNum(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}
