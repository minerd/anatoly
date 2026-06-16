import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_scope.dart';
import 'data/app_controller.dart';
import 'data/repository.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/root_shell.dart';
import 'ui/i18n.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  final repo = Repository();
  await repo.init();
  final controller = AppController(repo);
  final existed = await controller.load();

  // İlk açılış: cihaz dili destekleniyorsa onu varsayılan yap.
  if (!existed) {
    final dev = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    if (kSupportedLocales.contains(dev)) {
      controller.settings.locale = dev;
    }
  }
  controller.syncLocaleNotifier();

  runApp(AnatolyApp(controller: controller));
}

class AnatolyApp extends StatelessWidget {
  final AppController controller;
  const AnatolyApp({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
      child: _LocalizedApp(controller: controller),
    );
  }
}

/// AppController dinler; locale değişince MaterialApp'i yeniden kurar.
class _LocalizedApp extends StatelessWidget {
  final AppController controller;
  const _LocalizedApp({required this.controller});

  @override
  Widget build(BuildContext context) {
    // MaterialApp yalnızca dil değişince yeniden kurulur (her state değişiminde değil).
    return ValueListenableBuilder<String>(
      valueListenable: controller.localeNotifier,
      builder: (context, code, _) => MaterialApp(
        title: 'Anatoly',
        debugShowCheckedModeBanner: false,
        theme: buildDarkTheme(),
        locale: Locale(code),
        supportedLocales: kSupportedLocaleObjects,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const _Root(),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.onboarded) return const OnboardingScreen();
    return const RootShell();
  }
}
