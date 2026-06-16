/// Hafif Markdown render widget'ı (Liftosaur açıklama/talimat formatı için).
///
/// Destekler: `# / ## / ###` başlıklar, `**kalın**`, `*italik*`, `[metin](url)`
/// linkler (tıklanabilir), `- `/`* ` ve `1.` listeler, ` ``` ` kod blokları,
/// `<!-- yorum -->` (atlanır), boş satır = paragraf.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';

class MarkdownText extends StatelessWidget {
  final String data;
  const MarkdownText(this.data, {super.key});

  @override
  Widget build(BuildContext context) {
    // HTML yorumlarını (tek/çok satır) temizle
    var text = data.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
    text = text.replaceAll('\r\n', '\n');
    final lines = text.split('\n');

    final widgets = <Widget>[];
    var inCode = false;
    final codeBuf = <String>[];

    void flushCode() {
      if (codeBuf.isEmpty) return;
      widgets.add(Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          codeBuf.join('\n'),
          style: const TextStyle(
              fontFamily: 'monospace', fontSize: 12, color: Colors.white, height: 1.4),
        ),
      ));
      codeBuf.clear();
    }

    for (final raw in lines) {
      final line = raw.trimRight();
      final trimmed = line.trim();

      // kod bloğu çiti
      if (trimmed.startsWith('```')) {
        if (inCode) {
          inCode = false;
          flushCode();
        } else {
          inCode = true;
        }
        continue;
      }
      if (inCode) {
        codeBuf.add(line);
        continue;
      }

      if (trimmed.isEmpty) {
        widgets.add(const SizedBox(height: 8));
        continue;
      }

      // başlıklar
      if (trimmed.startsWith('### ')) {
        widgets.add(_block(context, trimmed.substring(4), 15, FontWeight.w700, top: 10));
        continue;
      }
      if (trimmed.startsWith('## ')) {
        widgets.add(_block(context, trimmed.substring(3), 18, FontWeight.w800, top: 14));
        continue;
      }
      if (trimmed.startsWith('# ')) {
        widgets.add(_block(context, trimmed.substring(2), 22, FontWeight.w800, top: 16));
        continue;
      }

      // listeler
      final bullet = RegExp(r'^[-*]\s+(.*)$').firstMatch(trimmed);
      if (bullet != null) {
        widgets.add(_listItem(context, '•  ', bullet.group(1)!));
        continue;
      }
      final numbered = RegExp(r'^(\d+)\.\s+(.*)$').firstMatch(trimmed);
      if (numbered != null) {
        widgets.add(_listItem(context, '${numbered.group(1)}.  ', numbered.group(2)!));
        continue;
      }

      // paragraf
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: RichText(
          text: TextSpan(
            style: const TextStyle(color: AppColors.textDim, fontSize: 15, height: 1.5),
            children: _inline(trimmed),
          ),
        ),
      ));
    }
    flushCode();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
  }

  Widget _block(BuildContext context, String text, double size, FontWeight weight,
      {double top = 0}) {
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: 4),
      child: RichText(
        text: TextSpan(
          style: TextStyle(color: Colors.white, fontSize: size, fontWeight: weight, height: 1.3),
          children: _inline(text),
        ),
      ),
    );
  }

  Widget _listItem(BuildContext context, String marker, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, left: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(marker, style: const TextStyle(color: AppColors.accent, fontSize: 15, height: 1.5)),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: AppColors.textDim, fontSize: 15, height: 1.5),
                children: _inline(content),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Satır-içi: **kalın**, *italik*, [metin](url).
  List<InlineSpan> _inline(String text) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*|\[([^\]]+)\]\(([^)]+)\)');
    var i = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > i) spans.add(TextSpan(text: text.substring(i, m.start)));
      if (m.group(1) != null) {
        spans.add(TextSpan(
            text: m.group(1),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)));
      } else if (m.group(2) != null) {
        spans.add(TextSpan(
            text: m.group(2), style: const TextStyle(fontStyle: FontStyle.italic)));
      } else if (m.group(3) != null) {
        final label = m.group(3)!;
        final url = m.group(4)!;
        spans.add(TextSpan(
          text: label,
          style: const TextStyle(
              color: AppColors.accent, decoration: TextDecoration.underline),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              final uri = Uri.tryParse(url);
              if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
            },
        ));
      }
      i = m.end;
    }
    if (i < text.length) spans.add(TextSpan(text: text.substring(i)));
    return spans;
  }
}
