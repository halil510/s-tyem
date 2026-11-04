import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// ─── KPI Kart ────────────────────────────────────────────────────
class KpiKarti extends StatelessWidget {
  final String baslik;
  final String deger;
  final String? altyazi;
  final IconData ikon;
  final Color renk;
  final VoidCallback? onTap;

  const KpiKarti({
    super.key,
    required this.baslik,
    required this.deger,
    this.altyazi,
    required this.ikon,
    required this.renk,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: renk.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(ikon, color: renk, size: 18),
                ),
                const Spacer(),
                if (onTap != null)
                  Icon(Icons.chevron_right_rounded,
                      size: 16, color: AppColors.textHint),
              ],
            ),
            const SizedBox(height: 12),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                deger,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).textTheme.titleLarge?.color,
                  fontFamily: 'Poppins',
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              baslik,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontFamily: 'Poppins',
              ),
            ),
            if (altyazi != null) ...[
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  altyazi!,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 11,
                    color: renk,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Bölüm Başlığı ───────────────────────────────────────────────
class BolumBasligi extends StatelessWidget {
  final String baslik;
  final String? eylem;
  final VoidCallback? onEylem;

  const BolumBasligi({
    super.key,
    required this.baslik,
    this.eylem,
    this.onEylem,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              baslik,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                fontFamily: 'Poppins',
                letterSpacing: 0.5,
              ),
            ),
          ),
          if (eylem != null)
            GestureDetector(
              onTap: onEylem,
              child: Text(
                eylem!,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.primary,
                  fontFamily: 'Poppins',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Boş Durum Ekranı ────────────────────────────────────────────
class BosEkran extends StatelessWidget {
  final IconData ikon;
  final String baslik;
  final String aciklama;
  final String? butonMetin;
  final VoidCallback? onButon;

  const BosEkran({
    super.key,
    required this.ikon,
    required this.baslik,
    required this.aciklama,
    this.butonMetin,
    this.onButon,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(ikon,
                  size: 48, color: AppColors.primary.withOpacity(0.5)),
            ),
            const SizedBox(height: 20),
            Text(
              baslik,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                fontFamily: 'Poppins',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              aciklama,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontFamily: 'Poppins',
                height: 1.5,
              ),
            ),
            if (butonMetin != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onButon,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(butonMetin!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Yükleme göstergesi ──────────────────────────────────────────
class YukleniyorEkrani extends StatelessWidget {
  final String? mesaj;
  const YukleniyorEkrani({super.key, this.mesaj});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 3,
          ),
          if (mesaj != null) ...[
            const SizedBox(height: 16),
            Text(
              mesaj!,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontFamily: 'Poppins',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Durum Etiketi ───────────────────────────────────────────────
class DurumEtiketi extends StatelessWidget {
  final String metin;
  final Color renk;
  final Color? arkaplan;

  const DurumEtiketi({
    super.key,
    required this.metin,
    required this.renk,
    this.arkaplan,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: arkaplan ?? renk.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        metin,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: renk,
          fontFamily: 'Poppins',
        ),
      ),
    );
  }
}

// ─── Gelişmiş Arama Çubuğu ───────────────────────────────────────
class AramaCubugu extends StatelessWidget {
  final TextEditingController controller;
  final String ipucu;
  final ValueChanged<String> onDegisti;
  final VoidCallback? onTemizle;

  const AramaCubugu({
    super.key,
    required this.controller,
    required this.ipucu,
    required this.onDegisti,
    this.onTemizle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceVar,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: TextField(
        controller: controller,
        onChanged: onDegisti,
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
        decoration: InputDecoration(
          hintText: ipucu,
          hintStyle: const TextStyle(
            fontFamily: 'Poppins',
            color: AppColors.textHint,
            fontSize: 14,
          ),
          prefixIcon: const Icon(Icons.search_rounded,
              color: AppColors.textSecondary, size: 20),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    controller.clear();
                    onTemizle?.call();
                    onDegisti('');
                  },
                )
              : null,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }
}

// ─── Bilgi Satırı ─────────────────────────────────────────────────
class BilgiSatiri extends StatelessWidget {
  final String etiket;
  final String deger;
  final bool sonSatir;

  const BilgiSatiri({
    super.key,
    required this.etiket,
    required this.deger,
    this.sonSatir = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Text(
                etiket,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontFamily: 'Poppins',
                ),
              ),
              const Spacer(),
              Text(
                deger,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                  fontFamily: 'Poppins',
                ),
              ),
            ],
          ),
        ),
        if (!sonSatir) const Divider(height: 1),
      ],
    );
  }
}
