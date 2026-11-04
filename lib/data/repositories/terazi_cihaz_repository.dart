import 'package:sqflite/sqflite.dart';
import '../../models/terazi_cihaz_model.dart';

/// Kayıtlı terazi cihazlarının veri erişim katmanı.
/// Uygulama açılışında "varsayılan" (en son / tercih edilen) cihaza
/// otomatik yeniden bağlanmayı denemek için kullanılır.
class TeraziCihazRepository {
  final Database db;
  const TeraziCihazRepository(this.db);

  static const _tablo = 'terazi_cihazlari';

  Future<List<TeraziCihazi>> getAll() async {
    final maps = await db.query(_tablo, orderBy: 'son_baglanti_tarihi DESC');
    return maps.map(TeraziCihazi.fromMap).toList();
  }

  Future<TeraziCihazi?> getVarsayilan() async {
    final maps = await db.query(_tablo, where: 'varsayilan = 1', limit: 1);
    if (maps.isNotEmpty) return TeraziCihazi.fromMap(maps.first);
    // Varsayılan işaretlenmemişse en son bağlanılanı öner.
    final sonBaglanilanlar = await db.query(
      _tablo,
      orderBy: 'son_baglanti_tarihi DESC',
      limit: 1,
    );
    return sonBaglanilanlar.isNotEmpty ? TeraziCihazi.fromMap(sonBaglanilanlar.first) : null;
  }

  /// Cihazı kaydeder/günceller (adres + tür bazında upsert) ve
  /// bağlantı zamanını şimdiki zamana günceller.
  Future<void> kaydetVeyaGuncelle(TeraziCihazi cihaz) async {
    final mevcut = await db.query(
      _tablo,
      where: 'cihaz_adresi = ? AND baglanti_turu = ?',
      whereArgs: [cihaz.cihazAdresi, cihaz.baglantiTuru.kod],
    );
    cihaz.sonBaglantiTarihi = DateTime.now().toIso8601String();
    if (mevcut.isNotEmpty) {
      // ÖNEMLİ: `id` alanı UPDATE'e dahil edilmemeli — INTEGER PRIMARY
      // KEY (rowid) sütununa NULL yazılması "datatype mismatch" hatası
      // verir (bkz. fiyat_repository.dart'taki aynı düzeltme).
      final guncellemeMap = cihaz.toMap()..remove('id');
      await db.update(_tablo, guncellemeMap,
          where: 'cihaz_adresi = ? AND baglanti_turu = ?',
          whereArgs: [cihaz.cihazAdresi, cihaz.baglantiTuru.kod]);
    } else {
      final eklemeMap = cihaz.toMap()..remove('id');
      await db.insert(_tablo, eklemeMap);
    }
  }

  Future<void> varsayilanYap(int id) async {
    await db.update(_tablo, {'varsayilan': 0});
    await db.update(_tablo, {'varsayilan': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> sil(int id) => db.delete(_tablo, where: 'id = ?', whereArgs: [id]);
}
