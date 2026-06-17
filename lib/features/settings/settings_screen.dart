import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_scope.dart';
import '../../ui/i18n.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../legal/legal_screen.dart';

const String kContactEmail = 'ongorunet@gmail.com';
const String kWebsite = 'https://alikaptanoglu.com/anatoly/';
const String kSourceUrl = 'https://github.com/minerd/anatoly';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = app.t;
    final s = app.settings;
    return Scaffold(
      appBar: AppBar(title: Text(t.s('set.title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionTitle(t.s('set.general')),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  title: Text(t.s('set.unit')),
                  trailing: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'kg', label: Text('kg')),
                      ButtonSegment(value: 'lb', label: Text('lb')),
                    ],
                    selected: {s.units},
                    onSelectionChanged: (v) =>
                        app.updateSettings((st) => st.units = v.first),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  title: Text(t.s('set.language')),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(kLocaleNames[s.locale] ?? s.locale,
                          style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
                      const Icon(Icons.chevron_right, color: AppColors.textDim),
                    ],
                  ),
                  onTap: () => _pickLanguage(context, app),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: Text(t.s('set.vibration')),
                  subtitle: Text(t.s('set.vibrationDesc')),
                  value: s.vibration,
                  activeThumbColor: AppColors.accent,
                  onChanged: (v) => app.updateSettings((st) => st.vibration = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionTitle(t.s('set.timers')),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _timerTile(context, app, t.s('set.warmup'), s.warmupTimer,
                    (v) => app.updateSettings((st) => st.warmupTimer = v)),
                const Divider(height: 1),
                _timerTile(context, app, t.s('set.workSet'), s.workoutTimer,
                    (v) => app.updateSettings((st) => st.workoutTimer = v)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionTitle(t.s('set.equipment')),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final entry in s.equipment.entries.where((e) =>
                    e.key == 'barbell' || e.key == 'dumbbell' || e.key == 'ezbar'))
                  ListTile(
                    title: Text(entry.value.name),
                    subtitle: Text(t.f('set.barPlates', {
                      'bar': fmtWeight(entry.value.bar),
                      'n': '${entry.value.plates.length}',
                    })),
                    trailing: const Icon(Icons.chevron_right, color: AppColors.textDim),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionTitle(t.s('set.about')),
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Anatoly', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 4),
                Text(t.s('set.aboutDesc'),
                    style: const TextStyle(color: AppColors.textDim, fontSize: 13)),
                const SizedBox(height: 12),
                Text(
                  t.s('set.aboutAgpl'),
                  style: const TextStyle(color: AppColors.textDim, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionTitle(t.s('set.legal')),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _linkTile(context, Icons.privacy_tip_outlined, t.s('set.privacy'),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                LegalScreen(title: t.s('set.privacy'), kind: 'privacy')))),
                const Divider(height: 1),
                _linkTile(context, Icons.description_outlined, t.s('set.terms'),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                LegalScreen(title: t.s('set.terms'), kind: 'terms')))),
                const Divider(height: 1),
                _linkTile(context, Icons.mail_outline, t.s('set.contact'),
                    trailingText: kContactEmail,
                    onTap: () => _launch('mailto:$kContactEmail'
                        '?subject=${Uri.encodeComponent('Anatoly')}')),
                const Divider(height: 1),
                _linkTile(context, Icons.public, t.s('set.website'),
                    external: true, onTap: () => _launch(kWebsite)),
                const Divider(height: 1),
                _linkTile(context, Icons.code, t.s('set.source'),
                    external: true, onTap: () => _launch(kSourceUrl)),
                const Divider(height: 1),
                _linkTile(context, Icons.article_outlined, t.s('set.licenses'),
                    onTap: () => showLicensePage(
                          context: context,
                          applicationName: 'Anatoly',
                          applicationLegalese: '© 2026 Anatoly · AGPL v3',
                        )),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _linkTile(BuildContext context, IconData icon, String label,
      {VoidCallback? onTap, String? trailingText, bool external = false}) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textDim),
      title: Text(label),
      trailing: trailingText != null
          ? Text(trailingText,
              style: const TextStyle(color: AppColors.accent, fontSize: 13))
          : Icon(external ? Icons.open_in_new : Icons.chevron_right,
              size: external ? 18 : 24, color: AppColors.textDim),
      onTap: onTap,
    );
  }

  Future<void> _launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _pickLanguage(BuildContext context, dynamic app) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(app.t.s('set.language'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ),
            for (final code in kSupportedLocales)
              ListTile(
                title: Text(kLocaleNames[code] ?? code),
                trailing: (app.settings.locale as String) == code
                    ? const Icon(Icons.check, color: AppColors.accent)
                    : null,
                onTap: () {
                  app.setLocale(code);
                  Navigator.pop(ctx);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _timerTile(BuildContext context, dynamic app, String label, int value,
      void Function(int) onChange) {
    final t = app.t;
    return ListTile(
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: value > 15 ? () => onChange(value - 15) : null),
          Text(t.f('set.secN', {'n': '$value'}),
              style: const TextStyle(fontWeight: FontWeight.w600)),
          IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => onChange(value + 15)),
        ],
      ),
    );
  }
}
