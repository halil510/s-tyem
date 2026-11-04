import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import '../table_builder.dart';
import 'migration.dart';

/// v8 — Bir cari için bir günde TEK süt kaydı garantisi.
///
/// Sorun: Süt Ekle ekranı her kaydette yeni satır ekliyordu. Sabah ve
/// akşam ayrı ayrı girilince (veya kaydet'e iki kez basılınca) aynı
/// cari + gün için birden çok satır oluşuyordu. Ekstre hepsini topluyor,
/// ama Hızlı Süt Girişi yalnızca İLKİNİ gösterip güncelliyordu — diğer
/// satırlar görünmez kalıp bakiyeyi şişiriyordu.
///
/// Bu migration:
/// 1. Saat bilgisi taşıyan tarihleri (`2026-01-05T08:30:00`) gün
///    biçimine (`2026-01-05`) normalize eder — aksi halde `BETWEEN`
///    sorguları aralığın son gününü kaçırıyordu.
/// 2. Aynı cari + gün için birden çok süt satırını, miktarları TOPLAYARAK
///    tek satırda birleştirir. Toplama, ekstrenin bugüne kadar gösterdiği
///    bakiyeyi birebir korur (hiçbir carinin alacağı değişmez).
///    Silinen her satır `islem_gecmisi`'ne yazılır (denetim izi).
/// 3. `sutler(cari_id, tarih)` üzerine UNIQUE index koyar; bundan sonra
///    mükerrer kayıt veritabanı seviyesinde imkânsızdır.
class MigrationV8SutGunlukTekil extends Migration {
  @override
  int get version => 8;

  @override
  String get description =>
      'Tarih normalizasyonu + mükerrer süt kayıtlarını birleştir + UNIQUE(cari_id, tarih)';

  @override
  Future<void> up(DatabaseExecutor db) async {
    for (final tablo in ['sutler', 'yemler', 'cari_odemeler']) {
      await db.rawUpdate(
        'UPDATE $tablo SET tarih = substr(tarih, 1, 10) WHERE length(tarih) > 10',
      );
    }

    final gruplar = await db.rawQuery('''
      SELECT cari_id, tarih FROM sutler
      GROUP BY cari_id, tarih HAVING COUNT(*) > 1
    ''');

    final simdi = DateTime.now().toIso8601String();
    for (final g in gruplar) {
      final satirlar = await db.query(
        'sutler',
        where: 'cari_id = ? AND tarih = ?',
        whereArgs: [g['cari_id'], g['tarih']],
        orderBy: 'id ASC',
      );
      final kalan = satirlar.first;
      double topla(String alan) =>
          satirlar.fold(0.0, (t, s) => t + ((s[alan] as num?) ?? 0).toDouble());

      final birlesik = {
        'sabah': topla('sabah'),
        'aksam': topla('aksam'),
        'toplam': topla('toplam'),
      };
      await db.update('sutler', birlesik, where: 'id = ?', whereArgs: [kalan['id']]);

      for (final silinen in satirlar.skip(1)) {
        await db.delete('sutler', where: 'id = ?', whereArgs: [silinen['id']]);
        await db.insert('islem_gecmisi', {
          'tablo_adi': 'sutler',
          'kayit_id': silinen['id'],
          'islem': 'birlestir',
          'onceki_deger': jsonEncode(silinen),
          'yeni_deger': jsonEncode({'birlestirildigi_id': kalan['id'], ...birlesik}),
          'tarih': simdi,
        });
      }
    }

    await SchemaInspector.createIndexIfMissing(
      db, 'uq_sutler_cari_tarih', 'sutler', ['cari_id', 'tarih'], unique: true,
    );
  }
}
