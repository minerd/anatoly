# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Proje

Anatoly — programlanabilir antrenman takip uygulaması (Flutter, Android + iOS). Çekirdeği, **Liftoscript** adlı antrenman-programlama DSL'inin Dart'ta sıfırdan yeniden uygulanmasıdır; 5/3/1, GZCLP, nSuns, Madcow gibi programların otomatik progresyon mantığını çalıştırır. Tamamen offline (cihazda JSON), hesap/internet gerektirmez. Lisans: **AGPL v3** (Liftosaur verisi ve dil tasarımından türetilmiştir).

## Komutlar

```bash
flutter pub get                         # bağımlılıklar
flutter test                            # tüm testler (motor + planner + servis + persistence)
flutter test test/liftoscript/engine_test.dart   # tek dosya
flutter test --name "GZCLP"             # ada göre tek test
flutter analyze                         # statik analiz (flutter_lints)
flutter run                             # cihazda/emülatörde çalıştır
flutter build apk --release             # Android (şu an DEBUG anahtarıyla imzalı — aşağı bak)
flutter build ios --release             # iOS (macOS gerekir)
```

İkon üretimi: `node tools/icon/gen_icon.js && dart run flutter_launcher_icons`.
Egzersiz/program verisi yeniden çıkarımı (tek seferlik, Node): `tools/extract/extract.js` → `assets/exercises.json` + `assets/programs.json`.

## Mimari — katmanlar ve veri akışı

Bağımlılık yönü tek yönlü: `features/ui` → `data` → `planner` → `liftoscript` + `domain`.

- **`lib/liftoscript/`** — DSL motoru, Flutter'dan bağımsız saf Dart. `lexer` → `parser` → `ast` → `runtime` (`Evaluator`). `value.dart` aritmetik tipleri tutar: `LWeight` (değer+birim), `LPercentage`, ve `applyArith`/`roundTo005`/RPE eğrisi gibi yardımcılar. Motor, Liftosaur referans davranışını birebir taklit eder (yorumlardaki "Referans ..." notları bunu işaretler) — değiştirirken referans semantiğini koru. `ScriptBindings` set dizilerini (`weights`/`w`, `reps`/`r`, `completedReps`/`cr` …) takma adlarıyla script'e açar; `state` egzersizin kalıcı değişkenleridir (`rm1`, `lpSuccess` vb.).

- **`lib/planner/`** — `planner_parser.dart` Liftosaur'un metin program formatını (`# Week`, `## Day`, `İsim / şema [ağırlık] / progress: ...`, `...label` reuse) `ParsedProgram`'a çevirir; şablon reuse'ları **global** çözülür (şablonlar genelde dosya sonunda tanımlı). `program_service.dart` üç işi yapar ve burası işin kalbidir:
  - `generateDay()` — belirli günü `WorkoutRecord`'a açar, runtime'ı başlatır, ağırlıkları çözer.
  - `applyProgression()` — workout bitince progress tipini çalıştırıp `nextDay`'i ilerletir.
  - **Kritik ayrım: "percentage mode" vs "absolute mode".** Egzersiz yüzde-bazlı set kullanıyor VE progress `weights` dizisine yazmıyorsa, ağırlık her seans güncel `rm1`'den taze çözülür (531/Sheiko/nSuns böyle ilerler). Aksi halde (`lp`/`dp`/`sum` veya `weights +=` yapan `custom`, ör. GZCLP/Madcow) progresyonun mutasyona uğrattığı `rt.weights` korunur. `_scriptWritesWeights()` regex'i bu kararı verir — bozarsan programların yarısı yanlış ağırlık üretir.
  - `lp`/`dp`/`sum` native Dart'ta; `custom` ise Liftoscript motorunda `_runCustomScript()` ile çalışır.

- **`lib/domain/`** — `models.dart` (Exercise, Settings, WorkoutRecord/Entry/Set, StoredProgram, ExerciseRuntime — JSON serileştirme dahil), `plates.dart` (ekipman/plaka yuvarlama `roundToEquipment`, plaka hesabı).

- **`lib/data/`** — `repository.dart` asset kataloğunu yükler + state'i **atomik** olarak `anatoly_state.json`'a yazar (tmp→rename). `app_controller.dart` (`ChangeNotifier`) tüm uygulama durumudur: her mutasyon `save()` çağırır, `_persist()` eşzamanlı yazımları birleştirir. UI buna `AppScope` (InheritedNotifier) üzerinden erişir — `AppScope.of(context)` dinleyerek, `AppScope.read(context)` dinlemeden.

- **`lib/features/`** — ekranlar; `root_shell.dart` alt navigasyon. **`lib/ui/`** — `theme.dart` (koyu Material 3), `i18n.dart` (5 dil: tr/en/es/de/fr — `stringsFor(locale)`), ortak `widgets.dart`.

State yönetimi sade tutulmuştur: harici state kütüphanesi yok, sadece `ChangeNotifier` + `InheritedNotifier`. Dil değişimi `MaterialApp`'i `localeNotifier` ile yeniden kurar; sıradan state değişimleri kurmaz.

## Testler

`flutter test` dört alanı kapsar: `liftoscript/engine_test.dart` (motor semantiği), `planner/parser_test.dart` + `service_test.dart` (programların uçtan uca doğru workout + progresyon üretmesi), `data/persistence_test.dart`. Program davranışını değiştiren bir iş yaparken `service_test.dart`'taki gerçek-program senaryolarını çalıştır — README'de belgelenen 9/10 doğruluk burada doğrulanır.

## Android imzalama (yayın için kritik)

`android/app/build.gradle.kts` içinde release build **debug anahtarıyla** imzalanır (`signingConfig = signingConfigs.getByName("debug")`). Bu APK Play Store'a **yüklenemez**. Mağaza dağıtımı için kullanıcının kendi keystore'unu oluşturup `android/key.properties` ile bağlaması ve release `signingConfig`'i tanımlaması gerekir. `key.properties` ve keystore repoya dahil edilmez — gizli kullanıcı anahtarıdır.

## Dağıtım

`site/` — uygulamanın tanıtım/gizlilik/şartlar statik sitesi (5 dilli, `i18n.js`). FTP ile `alikaptanoglu.com/anatoly/` altına yüklenir (global CLAUDE.md'deki hosting kuralına bak).
