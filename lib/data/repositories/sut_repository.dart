import 'package:sqflite/sqflite.dart';
import '../../models/sut_model.dart';
import 'denetim_kaydi.dart';
import 'donem_kilidi.dart';

/// Kayıt doğrulanamadığında (geçersiz tarih, negatif/aşırı miktar)
/// fırlatılır. Mesaj doğrudan kullanıcıya gösterilebilir.
class SutKayitHatasi implements Exception {
  final String mesaj;
  const SutKayitHatasi(this.mesaj);
  @override
  String toString() => mesaj;
}

enum SutKayitDurumu { eklendi, guncellendi, silindi, degismedi }

/// Toplu girişte (Hızlı Süt Girişi) tek bir carinin o günkü değerleri.
class GunlukSutGirdisi {
  final int cariId;
  final double sabah;
  final double aksam;
  const GunlukSutGirdisi({required this.cariId, required this.sabah, required this.aksam});
}

class TopluSutKayitSonucu {
  int eklenen = 0;
  int guncellenen = 0;
  int silinen = 0;

  void ekle(SutKayitDurumu durum) {
    switch (durum) {
      case SutKayitDurumu.eklendi:
        eklenen++;
      case SutKayitDurumu.guncellendi:
        guncellenen++;
      case SutKayitDurumu.silindi:
        silinen++;
      case SutKayitDurumu.degismedi:
        break;
    }
  }

  int get degisenSayisi => eklenen + guncellenen + silinen;
}

/// Süt kayıtlarının veri erişim katmanı.
///
/// KURAL: Bir cari için bir günde EN FAZLA BİR süt satırı vardır
/// (sabah + akşam aynı satırda). Bu kural hem burada (upsert) hem de
/// veritabanında (`uq_sutler_cari_tarih` UNIQUE index, migration v8)
/// uygulanır. Bu yüzden yeni kayıt için `insert` yoktur — her zaman
/// [gunlukKaydet] / [topluGunlukKaydet] kullanılır.
class SutRepository {
  final Database db;
  const SutRepository(this.db);

  /// Yazma işlemi: transaction + kapalı dönem kilidinin okunur hataya çevrilmesi.
  Future<T> _yaz<T>(Future<T> Function(Transaction txn) islem) =>
      donemKilidiyle(() => db.transaction(islem));

  static const _tablo = 'sutler';

  /// Tek bir sağım için kabul edilen üst sınır (kg). Bunun üstü neredeyse
  /// kesinlikle yazım hatasıdır (ör. 45 yerine 4500).
  static const maksimumSagimKg = 20000.0;

  static final _tarihDeseni = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  // ──────────────────────────────────────────
  // OKUMA
  // ──────────────────────────────────────────

  Future<List<Sut>> getByCari(int cariId, String start, String end) async {
    final maps = await db.query(
      _tablo,
      where: 'cari_id = ? AND tarih BETWEEN ? AND ?',
      whereArgs: [cariId, start, end],
      orderBy: 'tarih ASC',
    );
    return maps.map(Sut.fromMap).toList();
  }

  Future<List<Sut>> getAllInRange(String start, String end) async {
    final maps = await db.query(
      _tablo,
      where: 'tarih BETWEEN ? AND ?',
      whereArgs: [start, end],
      orderBy: 'tarih ASC',
    );
    return maps.map(Sut.fromMap).toList();
  }

  /// Bir carinin belirli bir gündeki kaydı (yoksa null).
  Future<Sut?> getGunluk(int cariId, String tarih) async {
    final maps = await db.query(
      _tablo,
      where: 'cari_id = ? AND tarih = ?',
      whereArgs: [cariId, tarih],
      limit: 1,
    );
    return maps.isEmpty ? null : Sut.fromMap(maps.first);
  }

  /// Bir gündeki TÜM carilerin kayıtları, cari id'sine göre — tek sorgu.
  Future<Map<int, Sut>> getGunlukHepsi(String tarih) async {
    final maps = await db.query(_tablo, where: 'tarih = ?', whereArgs: [tarih]);
    return {for (final m in maps) m['cari_id'] as int: Sut.fromMap(m)};
  }

  /// Belirli bir tarih aralığında, cari başına toplam süt miktarı.
  Future<Map<int, double>> toplamByCariInRange(String start, String end) async {
    final result = await db.rawQuery('''
      SELECT cari_id, SUM(toplam) AS toplam
      FROM sutler
      WHERE tarih BETWEEN ? AND ?
      GROUP BY cari_id
    ''', [start, end]);
    return {
      for (final r in result)
        r['cari_id'] as int: (r['toplam'] as num? ?? 0).toDouble(),
    };
  }

  // ──────────────────────────────────────────
  // YAZMA
  // ──────────────────────────────────────────

  /// Bir carinin bir günlük sütünü kaydeder (yoksa ekler, varsa günceller).
  ///
  /// Sabah ve akşam İKİSİ de 0 ise ve kayıt varsa kayıt silinir.
  Future<SutKayitDurumu> gunlukKaydet({
    required int cariId,
    required String tarih,
    required double sabah,
    required double aksam,
  }) {
    return _yaz(
      (txn) => _gunlukKaydet(txn, cariId: cariId, tarih: tarih, sabah: sabah, aksam: aksam),
    );
  }

  /// Birçok carinin aynı günkü sütünü TEK transaction içinde kaydeder.
  /// Herhangi bir satır geçersizse HİÇBİR değişiklik yazılmaz (ya hep ya
  /// hiç) — yarım kalmış bir toplu giriş müşteri hesaplarını bozamaz.
  Future<TopluSutKayitSonucu> topluGunlukKaydet(
    String tarih,
    List<GunlukSutGirdisi> girdiler,
  ) async {
    _tarihDogrula(tarih);
    for (final g in girdiler) {
      _miktarDogrula(g.sabah, g.aksam);
    }
    final sonuc = TopluSutKayitSonucu();
    await _yaz((txn) async {
      for (final g in girdiler) {
        sonuc.ekle(await _gunlukKaydet(
          txn, cariId: g.cariId, tarih: tarih, sabah: g.sabah, aksam: g.aksam,
        ));
      }
    });
    return sonuc;
  }

  /// Var olan bir kaydın sabah/akşam miktarlarını günceller (Detay ekranı).
  Future<int> update(Sut sut) async {
    if (sut.id == null) throw const SutKayitHatasi('Güncellenecek kaydın kimliği yok.');
    _tarihDogrula(sut.tarih);
    _miktarDogrula(sut.sabah, sut.aksam);
    return _yaz((txn) async {
      final onceki = await txn.query(_tablo, where: 'id = ?', whereArgs: [sut.id]);
      final yeni = {
        'sabah': sut.sabah,
        'aksam': sut.aksam,
        'toplam': sut.sabah + sut.aksam,
        'updated_at': sqliteSimdi(),
      };
      final adet = await txn.update(_tablo, yeni, where: 'id = ?', whereArgs: [sut.id]);
      if (adet > 0) {
        await denetimKaydet(txn,
            tablo: _tablo, kayitId: sut.id!, islem: 'guncelle',
            oncekiDeger: onceki.isEmpty ? null : onceki.first, yeniDeger: yeni);
      }
      return adet;
    });
  }

  Future<int> delete(int id) {
    return _yaz((txn) async {
      final onceki = await txn.query(_tablo, where: 'id = ?', whereArgs: [id]);
      final adet = await txn.delete(_tablo, where: 'id = ?', whereArgs: [id]);
      if (adet > 0) {
        await denetimKaydet(txn,
            tablo: _tablo, kayitId: id, islem: 'sil', oncekiDeger: onceki.first);
      }
      return adet;
    });
  }

  // ──────────────────────────────────────────
  // İÇ YARDIMCILAR
  // ──────────────────────────────────────────

  static Future<SutKayitDurumu> _gunlukKaydet(
    DatabaseExecutor ex, {
    required int cariId,
    required String tarih,
    required double sabah,
    required double aksam,
  }) async {
    _tarihDogrula(tarih);
    _miktarDogrula(sabah, aksam);

    final mevcutlar = await ex.query(
      _tablo,
      where: 'cari_id = ? AND tarih = ?',
      whereArgs: [cariId, tarih],
      limit: 1,
    );
    final mevcut = mevcutlar.isEmpty ? null : mevcutlar.first;
    final bos = sabah == 0 && aksam == 0;

    if (mevcut == null) {
      if (bos) return SutKayitDurumu.degismedi;
      final yeni = {
        'cari_id': cariId,
        'tarih': tarih,
        'sabah': sabah,
        'aksam': aksam,
        'toplam': sabah + aksam,
      };
      final id = await ex.insert(_tablo, yeni);
      await denetimKaydet(ex, tablo: _tablo, kayitId: id, islem: 'ekle', yeniDeger: yeni);
      return SutKayitDurumu.eklendi;
    }

    final id = mevcut['id'] as int;
    if (bos) {
      await ex.delete(_tablo, where: 'id = ?', whereArgs: [id]);
      await denetimKaydet(ex, tablo: _tablo, kayitId: id, islem: 'sil', oncekiDeger: mevcut);
      return SutKayitDurumu.silindi;
    }

    final eskiSabah = (mevcut['sabah'] as num? ?? 0).toDouble();
    final eskiAksam = (mevcut['aksam'] as num? ?? 0).toDouble();
    if (eskiSabah == sabah && eskiAksam == aksam) return SutKayitDurumu.degismedi;

    final yeni = {
      'sabah': sabah,
      'aksam': aksam,
      'toplam': sabah + aksam,
      'updated_at': sqliteSimdi(),
    };
    await ex.update(_tablo, yeni, where: 'id = ?', whereArgs: [id]);
    await denetimKaydet(ex,
        tablo: _tablo, kayitId: id, islem: 'guncelle', oncekiDeger: mevcut, yeniDeger: yeni);
    return SutKayitDurumu.guncellendi;
  }

  static void _tarihDogrula(String tarih) {
    final gun = _tarihDeseni.hasMatch(tarih) ? DateTime.tryParse(tarih) : null;
    // "2026-02-30" gibi takvimde olmayan günler DateTime tarafından bir
    // sonraki aya kaydırılır; geri biçimlendirip karşılaştırarak yakalanır.
    final gecerli = gun != null &&
        '${gun.year.toString().padLeft(4, '0')}-${gun.month.toString().padLeft(2, '0')}-'
                '${gun.day.toString().padLeft(2, '0')}' ==
            tarih;
    if (!gecerli) {
      throw SutKayitHatasi('Geçersiz tarih: "$tarih" (beklenen biçim yyyy-AA-gg).');
    }
  }

  static void _miktarDogrula(double sabah, double aksam) {
    for (final (ad, kg) in [('Sabah', sabah), ('Akşam', aksam)]) {
      if (!kg.isFinite || kg < 0) {
        throw SutKayitHatasi('$ad miktarı geçersiz: $kg');
      }
      if (kg > maksimumSagimKg) {
        throw SutKayitHatasi(
            '$ad miktarı çok yüksek: $kg kg (en fazla ${maksimumSagimKg.toStringAsFixed(0)} kg).');
      }
    }
  }
}
