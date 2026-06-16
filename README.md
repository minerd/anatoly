# Anatoly

Programlanabilir, güçlü bir antrenman takip uygulaması (Flutter • Android + iOS).
**Liftoscript** adlı bir antrenman-programlama dilinin Dart'taki yeniden uygulamasını
içerir; bu sayede 5/3/1, GZCLP, Starting Strength, nSuns gibi metodolojilerin
otomatik progresyon mantığı çalışır.

## Özellikler

- **Liftoscript motoru** (Dart): lexer + parser + evaluator. Özel progresyon
  scriptleri, state değişkenleri, ağırlık/yüzde aritmetiği, `lp`/`dp`/`sum`/`custom`.
- **59 hazır program** + **182 egzersiz** (kas grupları, açıklamalar, video/görsel).
- **Antrenman akışı**: set kaydı, AMRAP, RPE, dinlenme zamanlayıcısı, plaka hesaplayıcı.
- **İlerleme**: otomatik ağırlık artışı/deload, geçmiş, grafikler, vücut ağırlığı.
- **Yerel/offline**: tüm veri cihazda (JSON dosya). Hesap/internet gerekmez
  (egzersiz görselleri ilk açılışta indirilip önbelleğe alınır).
- **Modern koyu, minimalist arayüz** (Material 3).

## Mimari

```
lib/
  liftoscript/   # DSL motoru: lexer, parser, ast, value, runtime (evaluator)
  domain/        # modeller: ağırlık, set, egzersiz, ayarlar, plaka hesabı
  planner/       # planner metin parser'ı + program→workout servisi
  data/          # repository (asset + kalıcılık) + AppController
  features/      # ekranlar: onboarding, home, workout, programs, history,
                 #           exercises, settings
  ui/            # tema + ortak widget'lar
assets/          # exercises.json, programs.json (Liftosaur'dan çıkarılmış)
tools/extract/   # tek seferlik veri çıkarım script'i (Node)
```

## Test

```bash
flutter test            # Liftoscript motoru + planner + program servisi (41 test)
```

## Build

```bash
flutter build apk --release      # Android
flutter build ios --release      # iOS (macOS gerektirir)
```

İkon üretimi (gerekirse): `node tools/icon/gen_icon.js && dart run flutter_launcher_icons`.

### Mağaza dağıtımı için imzalama

Release APK şu an **debug anahtarıyla** imzalanır (geliştirme/test için yeterli, Play Store'a yüklenemez).
Mağaza dağıtımı için kendi keystore'unuzu oluşturup `android/key.properties` ile bağlayın ve
`android/app/build.gradle.kts` içinde release `signingConfig`'i tanımlayın (standart Flutter akışı).
Keystore kullanıcıya özel bir gizli anahtardır; bu repoya dahil edilmez.

## Bilinen Sınırlar

Çok-ajanlı bir denetimle 10 çeşitli program uçtan uca test edildi: **9/10 tam doğru**
(başlangıçta 3/10). Çalışanlar: linear progression, double-progression (ilk-seans
minReps dahil), yüzde-bazlı, **5/3/1 haftalık dalga + deload**, nSuns, Texas Method,
GZCLP stall protokolü, Sheiko undulation, **GZCL The Rippler bi-weekly intensity
dalgası**, Madcow 5x5.

Tam modellenmeyen tek desen:

- **Smolov Jr**: aynı lift'in farklı günlerinde farklı yüzde (70/75/80/85%) +
  `weights +=` ile haftalık ilerleme hibriti. Paylaşılan-runtime modelinde ya gün-içi
  intensity dalgası ya da otomatik haftalık artıştan biri tam çalışır; uygulama
  haftalık +artışı uygular (gün-içi yüzde dalgası kısmi). Program çökmez, makul
  antrenman üretir. (Bu özel peaking şemasını tam modellemek per-instance ağırlık
  takibi gerektirir.)

## Lisans

**AGPL v3** — bkz. [LICENSE](LICENSE).

Bu uygulama [Liftosaur](https://github.com/astashov/liftosaur) (© Anton Astashov,
AGPL v3) projesinin egzersiz ve program verilerini ve Liftoscript dil tasarımını
temel alır. AGPL gereği bu türev çalışma da AGPL v3 altında dağıtılır.
