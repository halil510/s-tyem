import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'donem_providers.dart';
import 'donem_servisi.dart';

/// Seçilen tarih kapatılmış bir döneme aitse giriş ekranında uyarı
/// gösterir (kayıt veritabanında zaten engellenir; bu, kullanıcının
/// boşuna veri girmesini önler). Dönem açıksa hiçbir şey çizmez.
class DonemKapaliBandi extends ConsumerWidget {
  final DateTime tarih;
  final EdgeInsetsGeometry margin;

  const DonemKapaliBandi({
    super.key,
    required this.tarih,
    this.margin = const EdgeInsets.only(bottom: 14),
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kapali = ref.watch(kapaliAylarProvider).valueOrNull ?? const <String>{};
    if (!kapali.contains(DonemServisi.ayAnahtari(tarih))) return const SizedBox.shrink();

    final ayAdi = DateFormat('MMMM yyyy', 'tr_TR').format(tarih);
    return Container(
      width: double.infinity,
      margin: margin,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Row(children: [
        Icon(Icons.lock_rounded, color: Colors.orange.shade800),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '$ayAdi dönemi kapatıldı; bu tarihe kayıt yapılamaz. '
            'Düzeltme gerekiyorsa Menü → Dönem Kapanışı\'ndan dönemi yeniden açın.',
            style: TextStyle(fontSize: 13, color: Colors.orange.shade900),
          ),
        ),
      ]),
    );
  }
}
