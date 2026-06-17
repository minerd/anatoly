/// Uygulama-içi yasal metin ekranı (Gizlilik / Şartlar) — çevrimdışı çalışır.
library;

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../ui/markdown.dart';

class LegalScreen extends StatelessWidget {
  final String title;
  final String kind; // 'privacy' | 'terms'
  const LegalScreen({super.key, required this.title, required this.kind});

  @override
  Widget build(BuildContext context) {
    final locale = AppScope.of(context).settings.locale;
    final body = legalText(kind, locale);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [MarkdownText(body)],
      ),
    );
  }
}

/// Yasal metin (markdown). Desteklenmeyen dillerde İngilizce'ye düşer.
String legalText(String kind, String locale) {
  final map = _legal[locale] ?? _legal['en']!;
  return map[kind] ?? _legal['en']![kind] ?? '';
}

const String _contactEmail = 'ongorunet@gmail.com';

final Map<String, Map<String, String>> _legal = {
  'tr': {
    'privacy': '''
# Gizlilik Politikası
*Son güncelleme: 17 Haziran 2026*

**Özet:** Anatoly senden hiçbir kişisel veri toplamaz, hesap istemez, seni takip etmez ve reklam göstermez. Tüm verilerin yalnızca cihazında saklanır.

## Topladığımız veriler
**Hiçbir kişisel veri toplamıyoruz.** Anatoly'nin sunucusu, kullanıcı hesabı veya bulut senkronizasyonu yoktur. Antrenman programların, kayıtların, vücut ağırlığı ve ölçümlerin, ayarların **yalnızca cihazında** bir dosyada tutulur ve bize gönderilmez.

## Analitik, reklam ve takip
Anatoly analitik araç, reklam ağı veya takip teknolojisi kullanmaz. Çerez veya reklam kimliği kullanmaz.

## Ağ bağlantıları
Uygulama yalnızca şu durumlarda internete bağlanır:
- **Egzersiz görselleri** Liftosaur sunucusundan (liftosaur.com) yüklenir ve cihazında önbelleğe alınır. Bu sırada, her web isteğinde olduğu gibi cihazının IP adresi o sunucuya iletilir.
- **Dış bağlantılar** (egzersiz videoları, web sitesi, GitHub, e-posta) cihazının tarayıcısında açılır.

Çekirdek işlevler internet olmadan çevrimdışı çalışır.

## İzinler
Android'de yalnızca **İnternet** izni kullanılır. Konum, kişiler, kamera gibi hassas izinler istenmez.

## Verilerini silme
Tüm verilerin cihazında olduğu için, uygulamayı kaldırırsan veya uygulama verilerini temizlersen her şey kalıcı olarak silinir.

## İletişim
Sorular için: **$_contactEmail**
''',
    'terms': '''
# Kullanım Şartları
*Son güncelleme: 17 Haziran 2026*

Anatoly'yi kullanarak bu şartları kabul etmiş olursun.

**Sağlık uyarısı:** Anatoly tıbbi veya profesyonel antrenörlük hizmeti değildir. Ağırlık antrenmanı yaralanma riski taşır. Yeni bir programa başlamadan önce bir sağlık uzmanına danış. Egzersizleri kendi sorumluluğunda yaparsın.

## Hizmetin niteliği
Anatoly antrenman planlama ve kayıt aracıdır. Programlar, ağırlık önerileri ve progresyon hesaplamaları yalnızca bilgilendirme amaçlıdır.

## "Olduğu gibi" sunum
Uygulama "olduğu gibi", hiçbir garanti olmaksızın sunulur. Hesaplamaların doğruluğu veya kesintisiz çalışma garanti edilmez.

## Sorumluluğun sınırlandırılması
Uygulamanın kullanımından doğan yaralanma, veri kaybı veya başka zararlardan, yasaların izin verdiği azami ölçüde sorumluluk kabul edilmez.

## Veriler
Tüm verilerin cihazında saklanır; yedeklemeden sen sorumlusun.

## Lisans
Anatoly açık kaynaklıdır ve **GNU AGPL v3** altında dağıtılır. Kaynak: github.com/minerd/anatoly. Liftosaur (© Anton Astashov, AGPL v3) projesinin verilerini ve Liftoscript tasarımını temel alır.

## İletişim
**$_contactEmail**
''',
  },
  'en': {
    'privacy': '''
# Privacy Policy
*Last updated: 17 June 2026*

**Summary:** Anatoly collects no personal data, requires no account, does not track you, and shows no ads. All your data stays on your device only.

## Data we collect
**We collect no personal data.** Anatoly has no server, user account, or cloud sync. Your programs, logs, body weight and measurements, and settings are stored **only on your device** in a file and are never sent to us.

## Analytics, ads and tracking
Anatoly uses no analytics tools, ad networks, or tracking technology. No cookies or advertising IDs.

## Network connections
The app connects to the internet only to:
- Load **exercise images** from the Liftosaur server (liftosaur.com), cached on your device. As with any web request, your device's IP address is sent to that server.
- Open **external links** (exercise videos, website, GitHub, email) in your device's browser.

Core features work offline without internet.

## Permissions
On Android only the **Internet** permission is used. No sensitive permissions (location, contacts, camera) are requested.

## Deleting your data
Since all data is on your device, uninstalling the app or clearing app data permanently deletes everything.

## Contact
Questions: **$_contactEmail**
''',
    'terms': '''
# Terms of Use
*Last updated: 17 June 2026*

By using Anatoly you accept these terms.

**Health warning:** Anatoly is not a medical or professional coaching service. Weight training carries injury risk. Consult a health professional before starting a new program. You perform all exercises at your own risk.

## Nature of the service
Anatoly is a workout planning and logging tool. Programs, weight suggestions and progression calculations are for informational purposes only.

## "As is"
The app is provided "as is" without warranties of any kind. Accuracy of calculations or uninterrupted operation is not guaranteed.

## Limitation of liability
To the maximum extent permitted by law, no liability is accepted for injury, data loss or other damages arising from use of the app.

## Data
All your data is stored on your device; you are responsible for backups.

## License
Anatoly is open source under **GNU AGPL v3**. Source: github.com/minerd/anatoly. It is based on data and the Liftoscript design from Liftosaur (© Anton Astashov, AGPL v3).

## Contact
**$_contactEmail**
''',
  },
};
