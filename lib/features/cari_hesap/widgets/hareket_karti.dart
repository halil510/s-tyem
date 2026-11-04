import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/cari_hareket.dart';
import '../../../theme/app_theme.dart';

/// Cari ekstresindeki tek bir hareketi gösteren kart.
///
/// Renk kodu: KREDİ (süt alımı, tahsilat) → cariye yazılan alacak,
/// mavi/bilgi tonunda gösterilir. BORÇ (yem verişi, ödeme) → cariyi
/// borçlandıran hareket, turuncu/uyarı tonunda gösterilir.
class HareketKarti extends StatelessWidget {
  final CariHareket hareket;
  final NumberFormat paraFormat;
  final VoidCallback? onSil;

  const HareketKarti({
    super.key,
    required this.hareket,
    required this.paraFormat,
    this.onSil,
  });

  @override
  Widget build(BuildContext context) {
    final kredi = hareket.kredi;
    final renk = hareket.fiyatEksik ? AppColors.textHint : (kredi ? AppColors.info : AppColors.warning);
    final ikon = switch (hareket.tur) {
      'sut' => Icons.water_drop_rounded,
      'yem' => Icons.grass_rounded,
      'odeme' => Icons.arrow_upward_rounded,
      'tahsilat' => Icons.arrow_downward_rounded,
      _ => Icons.receipt_long_rounded,
    };
    final tarihGoster = DateFormat('d MMMM yyyy', 'tr_TR').format(hareket.tarih);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hareket.fiyatEksik ? AppColors.danger.withOpacity(0.3) : AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: renk.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(ikon, size: 18, color: renk),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(hareket.baslik, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                Text(tarihGoster, style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                if (hareket.aciklama != null && hareket.aciklama!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(hareket.aciklama!, style: TextStyle(fontSize: 11, color: AppColors.textHint)),
                  ),
                if (hareket.fiyatEksik)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Fiyat tanımlı değil', style: TextStyle(fontSize: 10, color: AppColors.danger, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),
          Text(
            '${kredi ? '+' : '-'}${paraFormat.format(hareket.tutar)}',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: renk),
          ),
          if (onSil != null)
            IconButton(
              icon: const Icon(Icons.more_vert, size: 18),
              onPressed: () => _menuGoster(context),
            ),
        ],
      ),
    );
  }

  void _menuGoster(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.danger),
              title: const Text('Sil'),
              onTap: () {
                Navigator.pop(ctx);
                onSil?.call();
              },
            ),
          ],
        ),
      ),
    );
  }
}
