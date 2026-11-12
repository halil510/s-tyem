import 'package:sqflite/sqflite.dart';
import '../../models/cari_model.dart';
import '../../utils/turkce.dart';
import 'donem_kilidi.dart';

/// Cari (müşteri/tedarikçi) kayıtları için veri erişim katmanı.
///
/// UI kodu asla doğrudan SQL yazmaz; her zaman bu repository
/// üzerinden çalışır. Bu, hem test edilebilirliği artırır hem de
/// veritabanı şeması değiştiğinde tek bir dosyayı güncellemeyi yeterli
/// kılar.
class CariRepository {
  final Database db;
  const CariRepository(this.db);

  /// Yeni cari. [sira] verilirse (aktif cari) toplama rotasında o sıraya
  /// yerleşir, o sıradaki ve sonrakiler birer kayar. Yeni kimliği döner.
  Future<int> insert(Cari cari, {int? sira}) => db.transaction((txn) async {
        final id = await txn.insert('cariler', cari.toMap()..['sira'] = null);
        if (cari.aktif && sira != null) await _siraAta(txn, id, sira);
        return id;
      });

  /// Birçok cariyi TEK transaction'da ekler (Excel'den içeri alma): biri
  /// hata verirse hiçbiri eklenmez. Eklenen kayıt sayısını döner.
  Future<int> topluEkle(List<Cari> cariler) => db.transaction((txn) async {
        final b = txn.batch();
        for (final c in cariler) {
          b.insert('cariler', c.toMap()..remove('id'));
        }
        await b.commit(noResult: true);
        return cariler.length;
      });

  /// [sadeceAktif] true ise pasife alınmış (aktif=0) cariler listeye dahil edilmez.
  Future<List<Cari>> getAll({bool sadeceAktif = false}) async {
    final maps = await db.query(
      'cariler',
      where: sadeceAktif ? 'aktif = 1 OR aktif IS NULL' : null,
    );
    // Süt toplama rotası: önce sırası olanlar (1, 2, 3…), sonra sırasızlar
    // Türk alfabesiyle (SQL'in ORDER BY'ı Ç/Ş/Ö/Ü/İ'yi Z'den sonraya atıyordu).
    // Raporlar (Excel, bordro) kendi içinde alfabetik [cariSirala] kullanır.
    return maps.map(Cari.fromMap).toList()..sort(rotaSirala);
  }

  Future<Cari?> getById(int id) async {
    final maps = await db.query('cariler', where: 'id = ?', whereArgs: [id]);
    return maps.isNotEmpty ? Cari.fromMap(maps.first) : null;
  }

  /// Cari bilgilerini günceller (tek transaction). `cari.sira` YOK SAYILIR:
  /// sıra yalnız [siraGuncelle] true ise [sira] ile değişir (o sıradakiler
  /// kayar). Cari pasif yapıldıysa rotadan çıkar, kalanlar yeniden numaralanır.
  Future<int> update(Cari cari, {bool siraGuncelle = false, int? sira}) => db.transaction((txn) async {
        final map = cari.toMap()
          ..remove('id')
          ..remove('sira');
        final adet = await txn.update('cariler', map, where: 'id = ?', whereArgs: [cari.id]);
        if (!cari.aktif) {
          await _siraAta(txn, cari.id!, null);
        } else if (siraGuncelle) {
          await _siraAta(txn, cari.id!, sira);
        }
        return adet;
      });

  // ─── Süt toplama rotası ─────────────────────────────────────────────

  /// Cariyi rotada [sira]'ya yerleştirir (1 = ilk). O sıradaki ve sonraki
  /// cariler birer kayar; numaralar 1..N boşluksuz kalır. [sira] null →
  /// cari rotadan çıkar (sırasız, listede en sonda). Rotadaki sayıdan büyük
  /// bir sıra en sona yerleştirir.
  Future<void> siraAta(int cariId, int? sira) => db.transaction((txn) => _siraAta(txn, cariId, sira));

  /// Rotayı verilen sırayla baştan yazar (Toplama Sırası ekranı, sürükle-bırak):
  /// [cariIdleri][0] → 1, [1] → 2 … Listede olmayan cariler sırasız kalır.
  Future<void> rotaKaydet(List<int> cariIdleri) => db.transaction((txn) async {
        await txn.update('cariler', {'sira': null});
        await _numarala(txn, cariIdleri);
      });

  /// Rotadaki (aktif, sıralı) cari sayısı.
  Future<int> rotadakiSayi() async =>
      Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM cariler WHERE sira IS NOT NULL AND (aktif = 1 OR aktif IS NULL)')) ??
      0;

  static Future<void> _siraAta(Transaction txn, int cariId, int? sira) async {
    final satirlar = await txn.query('cariler',
        columns: ['id'],
        where: 'sira IS NOT NULL AND (aktif = 1 OR aktif IS NULL) AND id != ?',
        whereArgs: [cariId],
        orderBy: 'sira, id');
    final idler = [for (final s in satirlar) s['id'] as int];
    await txn.update('cariler', {'sira': null}, where: 'id = ?', whereArgs: [cariId]);
    if (sira != null) idler.insert((sira - 1).clamp(0, idler.length), cariId);
    await _numarala(txn, idler);
  }

  /// Yalnız sırası DEĞİŞEN cariler güncellenir: çoklu cihazda sırası aynı kalan carinin
  /// "değişti" sayılıp başka telefondaki eşzamanlı düzenlemesiyle yarışmasın.
  static Future<void> _numarala(Transaction txn, List<int> idler) async {
    if (idler.isEmpty) return;
    final mevcut = {
      for (final r in await txn.query('cariler', columns: ['id', 'sira'], where: 'id IN (${List.filled(idler.length, '?').join(',')})', whereArgs: idler))
        r['id'] as int: r['sira'] as int?,
    };
    final b = txn.batch();
    for (var i = 0; i < idler.length; i++) {
      if (mevcut[idler[i]] != i + 1) b.update('cariler', {'sira': i + 1}, where: 'id = ?', whereArgs: [idler[i]]);
    }
    await b.commit(noResult: true);
  }

  /// Cariyi KALICI olarak siler. DİKKAT: yabancı anahtarlar `ON DELETE
  /// CASCADE` olduğundan carinin tüm süt, yem, ödeme ve fiyat kayıtları da
  /// silinir. Hareketi olan bir cari için önce [hareketSayilari] ile
  /// kullanıcı uyarılmalı ve [pasifeAl] önerilmelidir.
  /// Kapalı bir dönemde kaydı olan cari silinemez ([DonemKapaliHatasi]).
  /// Rotadaki cari silinince kalanlar 1..N boşluksuz yeniden numaralanır (kural 16).
  Future<int> delete(int id) => donemKilidiyle(() => db.transaction((txn) async {
        await _siraAta(txn, id, null);
        return txn.delete('cariler', where: 'id = ?', whereArgs: [id]);
      }));

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
  /// Pasif cari rotadan çıkar; kalanlar yeniden numaralanır.
  Future<int> pasifeAl(int id) => db.transaction((txn) async {
        final adet = await txn.update('cariler', {'aktif': 0}, where: 'id = ?', whereArgs: [id]);
        await _siraAta(txn, id, null);
        return adet;
      });

  /// Pasif cariyi geri getirir. [sira] verilirse rotada o sıraya girer,
  /// verilmezse sırasız (listede en sonda) kalır.
  Future<int> aktifYap(int id, {int? sira}) => db.transaction((txn) async {
        final adet = await txn.update('cariler', {'aktif': 1}, where: 'id = ?', whereArgs: [id]);
        if (sira != null) await _siraAta(txn, id, sira);
        return adet;
      });

  Future<List<Cari>> ara(String sorgu) async {
    final maps = await db.query(
      'cariler',
      where: 'ad LIKE ? OR soyad LIKE ? OR telefon LIKE ?',
      whereArgs: ['%$sorgu%', '%$sorgu%', '%$sorgu%'],
    );
    return maps.map(Cari.fromMap).toList()..sort(cariSirala);
  }
}

/// Süt toplama rotası: sırası olanlar (1, 2, 3…) önce, sırasızlar sonra
/// alfabetik. Pasiflerin sırası yoktur. Süt, Yem, Hızlı Giriş, Cariler listeleri.
int rotaSirala(Cari a, Cari b) {
  final sa = a.aktif ? a.sira : null, sb = b.aktif ? b.sira : null;
  if (sa != null && sb != null && sa != sb) return sa.compareTo(sb);
  if (sa != null && sb == null) return -1;
  if (sa == null && sb != null) return 1;
  return cariSirala(a, b);
}

/// Carileri ad, sonra soyad sırasıyla Türk alfabesine göre dizer (raporlar).
int cariSirala(Cari a, Cari b) {
  final ad = turkceKarsilastir(a.ad, b.ad);
  return ad != 0 ? ad : turkceKarsilastir(a.soyad, b.soyad);
}
