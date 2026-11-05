import 'package:flutter/material.dart';

/// Uzun süren işlem (ör. yıllık Excel raporu) sürerken kapatılamayan
/// "hazırlanıyor" penceresi gösterir. Kullanıcı uygulama dondu sanmaz,
/// düğmeye ikinci kez basıp iki rapor / iki paylaşım başlatamaz.
/// Pencere, [islem] bitince (hata olsa da) kapanır.
Future<T> beklemeyleCalistir<T>(BuildContext context, String mesaj, Future<T> Function() islem) async {
  final nav = Navigator.of(context, rootNavigator: true);
  var acik = true;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(width: 18),
            Expanded(child: Text(mesaj)),
          ],
        ),
      ),
    ),
  ).whenComplete(() => acik = false);
  try {
    return await islem();
  } finally {
    if (acik && nav.mounted) nav.pop();
  }
}
