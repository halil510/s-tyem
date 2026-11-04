import 'package:sqflite/sqflite.dart';
import '../../models/cari_model.dart';

/// Cari (müşteri/tedarikçi) kayıtları için veri erişim katmanı.
///
/// UI kodu asla doğrudan SQL yazmaz; her zaman bu repository
/// üzerinden çalışır. Bu, hem test edilebilirliği artırır hem de
/// veritabanı şeması değiştiğinde tek bir dosyayı güncellemeyi yeterli
/// kılar.
class CariRepository {
  final Database db;
  const CariRepository(this.db);

  Future<int> insert(Cari cari) => db.insert('cariler', cari.toMap());

  /// [sadeceAktif] true ise pasife alınmış (aktif=0) cariler listeye dahil edilmez.
  Future<List<Cari>> getAll({bool sadeceAktif = false}) async {
    final maps = await db.query(
      'cariler',
      where: sadeceAktif ? 'aktif = 1 OR aktif IS NULL' : null,
      orderBy: 'ad ASC, soyad ASC',
    );
    return maps.map(Cari.fromMap).toList();
  }

  Future<Cari?> getById(int id) async {
    final maps = await db.query('cariler', where: 'id = ?', whereArgs: [id]);
    return maps.isNotEmpty ? Cari.fromMap(maps.first) : null;
  }

  Future<int> update(Cari cari) =>
      db.update('cariler', cari.toMap(), where: 'id = ?', whereArgs: [cari.id]);

  /// Cariyi KALICI olarak siler. DİKKAT: yabancı anahtarlar `ON DELETE
  /// CASCADE` olduğundan carinin tüm süt, yem, ödeme ve fiyat kayıtları da
  /// silinir. Hareketi olan bir cari için önce [hareketSayilari] ile
  /// kullanıcı uyarılmalı ve [pasifeAl] önerilmelidir.
  Future<int> delete(int id) =>
      db.delete('cariler', where: 'id = ?', whereArgs: [id]);

  /// Carinin kaç süt / yem / ödeme-tahsilat kaydı olduğunu döner.
  Future<({int sut, int yem, int odeme})> hareketSayilari(int id) async {
    Future<int> say(String tablo) async =>
        Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM $tablo WHERE cari_id = ?', [id])) ??
        0;
    return (sut: await say('sutler'), yem: await say('yemler'), odeme: await say('cari_odemeler'));
  }

  /// Cariyi silmek yerine pasife alır — geçmiş kayıtlar (süt, yem,
  /// ödeme) korunur, sadece aktif listelerden gizlenir.
  Future<int> pasifeAl(int id) =>
      db.update('cariler', {'aktif': 0}, where: 'id = ?', whereArgs: [id]);

  Future<int> aktifYap(int id) =>
      db.update('cariler', {'aktif': 1}, where: 'id = ?', whereArgs: [id]);

  Future<List<Cari>> ara(String sorgu) async {
    final maps = await db.query(
      'cariler',
      where: 'ad LIKE ? OR soyad LIKE ? OR telefon LIKE ?',
      whereArgs: ['%$sorgu%', '%$sorgu%', '%$sorgu%'],
      orderBy: 'ad ASC, soyad ASC',
    );
    return maps.map(Cari.fromMap).toList();
  }
}
