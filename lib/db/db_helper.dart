import 'package:sqflite/sqflite.dart';

import '../models/cari_model.dart';
import '../models/sut_model.dart';
import '../models/yem_model.dart';
import '../models/cari_odeme_model.dart';
import '../models/fiyat_model.dart';
import '../models/cari_fiyat_model.dart';
import '../core/database/app_database.dart';
import '../data/repositories/sut_repository.dart';

/// ─────────────────────────────────────────────────────────────
/// DBHelper — GERİYE DÖNÜK UYUMLULUK KATMANI
/// ─────────────────────────────────────────────────────────────
///
/// ÖNEMLİ: Bu sınıfın kendi şema/versiyon yönetimi ARTIK YOK.
/// Aşağıdaki `db` getter'ı, gerçek veritabanı bağlantısını ve tüm
/// migration mantığını [AppDatabase] içindeki `MigrationRunner`'a
/// devreder. Bu tasarım kasıtlıdır:
///
/// Eskiden bu sınıf kendi `openDatabase(version: 3, onCreate: ...,
/// onUpgrade: ...)` çağrısını yapıyordu. Yeni mimaride [AppDatabase]
/// da AYNI veritabanı dosyasını PRAGMA user_version üzerinden kendi
/// migration sistemiyle yönetiyor. İki ayrı yerde iki ayrı versiyon
/// mantığı çalıştırmak (biri sqflite'ın version:3 mekanizması, diğeri
/// bizim migration'larımız v1-v7) veritabanının "downgrade" algılayıp
/// bozuk sanması ve GERİ DÖNÜLEMEZ VERİ KAYBINA yol açması riskini
/// taşır. Bu yüzden `db` getter'ı artık doğrudan `AppDatabase.instance`
/// döner — tek bağlantı, tek versiyon otoritesi.
///
/// Henüz yeni repository katmanına taşınmamış eski ekranlar (ör.
/// `cari_listesi.dart`, `sut_ekrani.dart`) bu sınıfı kullanmaya devam
/// edebilir; CRUD metodlarının tamamı korunmuştur. Yeni yazılan kod
/// ise doğrudan `lib/data/repositories/` altındaki repository'leri
/// (Riverpod provider'ları üzerinden) kullanmalıdır.
class DBHelper {
  static final DBHelper _instance = DBHelper._internal();
  factory DBHelper() => _instance;
  DBHelper._internal();

  Future<Database> get db async => AppDatabase.instance.database;

  Future<void> closeDatabase() => AppDatabase.instance.close();

  // ──────────────────────────────────────────
  // CARİ
  // ──────────────────────────────────────────
  Future<int> insertCari(Cari c) async =>
      (await db).insert('cariler', c.toMap());

  Future<List<Cari>> getCariler() async {
    final maps = await (await db).query('cariler', orderBy: 'ad ASC, soyad ASC');
    return maps.map((m) => Cari.fromMap(m)).toList();
  }

  Future<Cari?> getCariById(int id) async {
    final maps = await (await db).query('cariler', where: 'id = ?', whereArgs: [id]);
    return maps.isNotEmpty ? Cari.fromMap(maps.first) : null;
  }

  Future<int> updateCari(Cari c) async =>
      (await db).update('cariler', c.toMap(), where: 'id = ?', whereArgs: [c.id]);

  Future<int> deleteCari(int id) async =>
      (await db).delete('cariler', where: 'id = ?', whereArgs: [id]);

  // ──────────────────────────────────────────
  // SÜT
  // ──────────────────────────────────────────
  /// Günde tek kayıt kuralına uyar (bkz. [SutRepository.gunlukKaydet]).
  /// Eskiden `REPLACE` kullanıyordu; UNIQUE index ile bu, aynı günün
  /// mevcut kaydını sessizce silip yenisini yazardı.
  Future<void> insertSut(Sut s) async => SutRepository(await db)
      .gunlukKaydet(cariId: s.cariId, tarih: s.tarih, sabah: s.sabah, aksam: s.aksam);

  Future<List<Sut>> getSutlarByCari(int cariId, String start, String end) async {
    final maps = await (await db).query('sutler',
        where: 'cari_id = ? AND tarih BETWEEN ? AND ?',
        whereArgs: [cariId, start, end],
        orderBy: 'tarih ASC');
    return maps.map((m) => Sut.fromMap(m)).toList();
  }

  Future<List<Sut>> getTumSutler(String start, String end) async {
    final maps = await (await db).query('sutler',
        where: 'tarih BETWEEN ? AND ?', whereArgs: [start, end], orderBy: 'tarih ASC');
    return maps.map((m) => Sut.fromMap(m)).toList();
  }

  Future<int> updateSut(Sut s) async =>
      (await db).update('sutler', s.toMap(), where: 'id = ?', whereArgs: [s.id]);

  Future<int> deleteSut(int id) async =>
      (await db).delete('sutler', where: 'id = ?', whereArgs: [id]);

  // ──────────────────────────────────────────
  // YEM
  // ──────────────────────────────────────────
  Future<int> insertYem(Yem y) async =>
      (await db).insert('yemler', y.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<Yem>> getYemlerByCari(int cariId, String start, String end) async {
    final maps = await (await db).query('yemler',
        where: 'cari_id = ? AND tarih BETWEEN ? AND ?',
        whereArgs: [cariId, start, end],
        orderBy: 'tarih ASC');
    return maps.map((m) => Yem.fromMap(m)).toList();
  }

  Future<List<Yem>> getTumYemler(String start, String end) async {
    final maps = await (await db).query('yemler',
        where: 'tarih BETWEEN ? AND ?', whereArgs: [start, end], orderBy: 'tarih ASC');
    return maps.map((m) => Yem.fromMap(m)).toList();
  }

  Future<int> updateYem(Yem y) async =>
      (await db).update('yemler', y.toMap(), where: 'id = ?', whereArgs: [y.id]);

  Future<int> deleteYem(int id) async =>
      (await db).delete('yemler', where: 'id = ?', whereArgs: [id]);

  // ──────────────────────────────────────────
  // CARİ ÖDEME
  // ──────────────────────────────────────────
  Future<int> insertCariOdeme(CariOdeme o) async =>
      (await db).insert('cari_odemeler', o.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<CariOdeme>> getCariOdemeler(int cariId) async {
    final maps = await (await db).query('cari_odemeler',
        where: 'cari_id = ?', whereArgs: [cariId], orderBy: 'tarih DESC, id DESC');
    return maps.map((m) => CariOdeme.fromMap(m)).toList();
  }

  Future<int> updateCariOdeme(CariOdeme o) async =>
      (await db).update('cari_odemeler', o.toMap(), where: 'id = ?', whereArgs: [o.id]);

  Future<int> deleteCariOdeme(int id) async =>
      (await db).delete('cari_odemeler', where: 'id = ?', whereArgs: [id]);

  Future<Map<int, double>> getTumCariKalanBorclar() async {
    final result = await (await db).rawQuery('''
      SELECT cari_id,
        SUM(CASE WHEN islem_turu='alim' THEN toplam_tutar ELSE 0 END) -
        SUM(CASE WHEN islem_turu='odeme' THEN toplam_tutar ELSE 0 END) AS kalan
      FROM cari_odemeler
      GROUP BY cari_id
    ''');
    return {
      for (var r in result)
        r['cari_id'] as int: (r['kalan'] as num? ?? 0).toDouble()
    };
  }

  // ──────────────────────────────────────────
  // CARİ FİYATLAR
  // ──────────────────────────────────────────
  Future<CariFiyat?> getCariFiyat(int cariId, String ay) async {
    final maps = await (await db).query('cari_fiyatlar',
        where: 'cari_id = ? AND ay = ?', whereArgs: [cariId, ay]);
    return maps.isNotEmpty ? CariFiyat.fromMap(maps.first) : null;
  }

  Future<CariFiyat?> getSonCariFiyat(int cariId, String ay) async {
    final maps = await (await db).query('cari_fiyatlar',
        where: 'cari_id = ? AND ay <= ?',
        whereArgs: [cariId, ay],
        orderBy: 'ay DESC',
        limit: 1);
    return maps.isNotEmpty ? CariFiyat.fromMap(maps.first) : null;
  }

  Future<void> upsertCariFiyat(CariFiyat f) async {
    final dbClient = await db;
    final mevcut = await getCariFiyat(f.cariId, f.ay);
    if (mevcut != null) {
      await dbClient.update('cari_fiyatlar', f.toMap(),
          where: 'cari_id = ? AND ay = ?', whereArgs: [f.cariId, f.ay]);
    } else {
      await dbClient.insert('cari_fiyatlar', f.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<CariFiyat> oncekiAydanKopyala(int cariId, String ay) async {
    final parts = ay.split('-');
    final yil = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final oncekiAy = month == 1
        ? '${yil - 1}-12'
        : '$yil-${(month - 1).toString().padLeft(2, '0')}';

    final onceki = await getSonCariFiyat(cariId, oncekiAy);
    if (onceki != null) {
      return CariFiyat(
        cariId: cariId, ay: ay,
        sutFiyat: onceki.sutFiyat,
        sutYemiFiyat: onceki.sutYemiFiyat,
        besiYemiFiyat: onceki.besiYemiFiyat,
        bBaslangicFiyat: onceki.bBaslangicFiyat,
        bBuyutmeFiyat: onceki.bBuyutmeFiyat,
        kuzuYemiFiyat: onceki.kuzuYemiFiyat,
        tavukYemiFiyat: onceki.tavukYemiFiyat,
      );
    }
    return CariFiyat(cariId: cariId, ay: ay);
  }

  Future<Map<int, CariFiyat>> getAyFiyatlariHepsi(
      List<Cari> cariler, String ay) async {
    final Map<int, CariFiyat> sonuc = {};
    for (final cari in cariler) {
      var fiyat = await getCariFiyat(cari.id!, ay);
      fiyat ??= await oncekiAydanKopyala(cari.id!, ay);
      sonuc[cari.id!] = fiyat;
    }
    return sonuc;
  }

  // ──────────────────────────────────────────
  // GLOBAL FİYATLAR (eski, uyumluluk)
  // ──────────────────────────────────────────
  Future<int> insertFiyat(Fiyat f) async =>
      (await db).insert('fiyatlar', f.toMap());

  Future<List<Fiyat>> getFiyatlar(String urunTuru) async {
    final maps = await (await db).query('fiyatlar',
        where: 'urun_turu = ?', whereArgs: [urunTuru],
        orderBy: 'tarih DESC, id DESC');
    return maps.map((m) => Fiyat.fromMap(m)).toList();
  }

  Future<Fiyat?> getGuncelFiyat(String urunTuru) async {
    final maps = await (await db).query('fiyatlar',
        where: 'urun_turu = ?', whereArgs: [urunTuru],
        orderBy: 'tarih DESC, id DESC', limit: 1);
    return maps.isNotEmpty ? Fiyat.fromMap(maps.first) : null;
  }

  Future<int> deleteFiyat(int id) async =>
      (await db).delete('fiyatlar', where: 'id = ?', whereArgs: [id]);
}
