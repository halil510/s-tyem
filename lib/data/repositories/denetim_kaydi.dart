import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// `islem_gecmisi` tablosuna (bkz. migration v6) bir denetim satırı yazar:
/// hangi kayıt, ne zaman eklendi / güncellendi / silindi ve önceki-yeni
/// değerleri neydi. Müşteri "ben o gün 40 kg vermiştim" dediğinde
/// geçmişe bakabilmek için.
///
/// Çağıran transaction içindeyse [db] olarak `txn` geçilmelidir; denetim
/// satırı böylece ana işlemle birlikte yazılır ya da birlikte geri alınır.
Future<void> denetimKaydet(
  DatabaseExecutor db, {
  required String tablo,
  required int kayitId,
  required String islem,
  Map<String, Object?>? oncekiDeger,
  Map<String, Object?>? yeniDeger,
}) async {
  await db.insert('islem_gecmisi', {
    'tablo_adi': tablo,
    'kayit_id': kayitId,
    'islem': islem,
    'onceki_deger': oncekiDeger != null ? jsonEncode(oncekiDeger) : null,
    'yeni_deger': yeniDeger != null ? jsonEncode(yeniDeger) : null,
    'tarih': DateTime.now().toIso8601String(),
  });
}

/// SQLite'ın `datetime('now')` varsayılanıyla aynı biçimde (UTC,
/// `yyyy-MM-dd HH:mm:ss`) zaman damgası — `updated_at` için.
String sqliteSimdi() =>
    DateTime.now().toUtc().toIso8601String().substring(0, 19).replaceFirst('T', ' ');
