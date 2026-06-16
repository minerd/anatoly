/// Ortak UI yardımcıları ve widget'lar.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../domain/models.dart';
import 'i18n.dart';
import 'theme.dart';

/// Egzersiz görseli (Liftosaur CDN'inden, önbellekli). Offline'da yer tutucu.
class ExerciseImage extends StatelessWidget {
  final ExerciseType type;
  final double size;
  final bool large;
  const ExerciseImage({super.key, required this.type, this.size = 56, this.large = false});

  String get _id {
    final equip = (type.equipment ?? 'bodyweight').toLowerCase();
    return '${type.id.toLowerCase()}_$equip';
  }

  String get _url {
    final path = large
        ? 'full/large/${_id}_full_large.png'
        : 'single/small/${_id}_single_small.png';
    return 'https://www.liftosaur.com/externalimages/exercises/$path';
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CachedNetworkImage(
        imageUrl: _url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, _) => _ph(),
        errorWidget: (_, _, _) => _ph(icon: Icons.fitness_center),
      ),
    );
  }

  Widget _ph({IconData icon = Icons.image_outlined}) => Container(
        width: size,
        height: size,
        color: AppColors.surfaceHigh,
        child: Icon(icon, color: AppColors.textDim, size: size * 0.4),
      );
}

/// Bölüm başlığı.
class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        children: [
          Text(text,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// Yuvarlatılmış kart.
class AppCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final Color? color;
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.color,
  });
  @override
  Widget build(BuildContext context) {
    return Material(
      color: color ?? AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Etiket çipi.
class TagChip extends StatelessWidget {
  final String text;
  final Color? color;
  const TagChip(this.text, {super.key, this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: (color ?? AppColors.accent).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: TextStyle(
              color: color ?? AppColors.accent,
              fontSize: 11,
              fontWeight: FontWeight.w600)),
    );
  }
}

String fmtWeight(LWeight? w) {
  if (w == null) return '—';
  final v = w.value;
  final s = v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
  return '$s${w.unit}';
}

String fmtDate(DateTime d, Strings t) => '${d.day} ${t.month(d.month)} ${d.year}';

String fmtDuration(int ms, Strings t) {
  final m = ms ~/ 60000;
  final min = t.f('pr.durN', {'n': ''}).trim(); // "dk" / "min" / "Min"
  if (m < 60) return '$m $min';
  return '${m ~/ 60}h ${m % 60} $min';
}
