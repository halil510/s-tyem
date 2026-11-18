import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/core/database/app_database.dart';
import 'package:sutyem_pro/core/database/migrations/migration_runner.dart';
import 'package:sutyem_pro/data/repositories/cari_odeme_repository.dart';
import 'package:sutyem_pro/data/repositories/cari_repository.dart';
import 'package:sutyem_pro/data/repositories/sut_repository.dart';
import 'package:sutyem_pro/data/repositories/veri_yonetimi_repository.dart';

/// ESKİ SÜRÜM (.db) yedeğinin yeni sürüme geri yüklenmesi.
///
/// Eski uygulama (paket adı değişmeden önceki, şema sürümü 0) veritabanını
/// kendi DDL'iyle kuruyordu: cari_fiyatlar, islem_gecmisi, aktif/sira vb.
/// yoktu. Kullanıcı eski telefonda yedek alıp yeni sürüme yükleyince bu
/// dosya MigrationRunner ile 0 → güncel sürüme taşınmalı ve hiçbir kayıt,
/// kg ya da ₺ kaybolmamalı.
///
/// Gerçek bir eski yedekle de denemek için: `ESKI_YEDEK=<yol.db> flutter test test/data/eski_yedek_gecis_test.dart`
void main() {
  late Directory klasor;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    klasor = await Directory.systemTemp.createTemp('sutyem_eski_yedek_');
  });

  tearDown(() async {
    try {
      await klasor.delete(recursive: true);
    } catch (_) {}
  });

  /// Eski uygulamanın birebir şeması (Şubat 2026 yedeğinden alındı).
  Future<String> eskiYedekUret() async {
    final yol = p.join(klasor.path, 'sut_yem_backup_eski.db');
    final db = await databaseFactoryFfi.openDatabase(yol);
    await db.execute('''CREATE TABLE cariler (
      id INTEGER PRIMARY KEY AUTOINCREMENT, ad TEXT, soyad TEXT, adres TEXT,
      telefon TEXT, hayvan_turu TEXT)''');
    await db.execute('''CREATE TABLE sutler (
      id INTEGER PRIMARY KEY AUTOINCREMENT, cari_id INTEGER, tarih TEXT,
      sabah REAL, aksam REAL, toplam REAL)''');
    await db.execute('''CREATE TABLE yemler (
      id INTEGER PRIMARY KEY AUTOINCREMENT, cari_id INTEGER, tarih TEXT,
      sut_yemi REAL, besi_yemi REAL, b_baslangic REAL, b_buyutme REAL,
      kuzu_yemi REAL, tavuk_yemi REAL, toplam REAL)''');
    await db.execute('''CREATE TABLE cari_odemeler (
      id INTEGER PRIMARY KEY AUTOINCREMENT, cari_id INTEGER NOT NULL,
      tarih TEXT NOT NULL, islem_turu TEXT NOT NULL, miktar REAL NOT NULL,
      birim_fiyat REAL NOT NULL, toplam_tutar REAL NOT NULL,
      odenen_tutar REAL DEFAULT 0, kalan_tutar REAL DEFAULT 0, aciklama TEXT,
      FOREIGN KEY (cari_id) REFERENCES cariler (id) ON DELETE CASCADE)''');
    await db.execute('CREATE TABLE android_metadata (locale TEXT)');
    await db.insert('android_metadata', {'locale': 'tr_TR'});

    for (var i = 1; i <= 40; i++) {
      await db.insert('cariler', {
        'ad': 'Üretici$i', 'soyad': 'Şahinoğlu', 'adres': 'Köy $i',
        'telefon': '0555000${i.toString().padLeft(4, '0')}', 'hayvan_turu': 'inek',
      });
    }
    // Normal günlük süt
    for (var c = 1; c <= 40; c++) {
      for (var g = 1; g <= 10; g++) {
        final s = 10.0 + c, a = 8.5 + g;
        await db.insert('sutler', {
          'cari_id': c, 'tarih': '2026-10-${g.toString().padLeft(2, '0')}',
          'sabah': s, 'aksam': a, 'toplam': s + a,
        });
      }
    }
    // Eski sürümün hatası: aynı güne ikinci satır ve saatli tarih
    await db.insert('sutler', {'cari_id': 1, 'tarih': '2026-10-01', 'sabah': 0, 'aksam': 5.5, 'toplam': 5.5});
    await db.insert('sutler', {'cari_id': 2, 'tarih': '2026-10-11T08:30:00.000', 'sabah': 12.25, 'aksam': 0, 'toplam': 12.25});
    await db.insert('yemler', {
      'cari_id': 3, 'tarih': '2026-10-05', 'sut_yemi': 50, 'besi_yemi': 0, 'b_baslangic': 0,
      'b_buyutme': 0, 'kuzu_yemi': 0, 'tavuk_yemi': 0, 'toplam': 50,
    });
    await db.insert('cari_odemeler', {
      'cari_id': 1, 'tarih': '2026-10-15', 'islem_turu': 'süt', 'miktar': 100,
      'birim_fiyat': 18.5, 'toplam_tutar': 1850, 'odenen_tutar': 1000, 'kalan_tutar': 850,
      'aciklama': 'avans',
    });
    await db.close();
    return yol;
  }

  Future<Map<String, num>> ozet(Database db) async {
    Future<num> tek(String sql) async => (await db.rawQuery(sql)).first.values.first as num? ?? 0;
    return {
      'cari': await tek('SELECT COUNT(*) FROM cariler'),
      'sut_kg': await tek('SELECT ROUND(SUM(toplam), 4) FROM sutler'),
      'sabah': await tek('SELECT ROUND(SUM(sabah), 4) FROM sutler'),
      'aksam': await tek('SELECT ROUND(SUM(aksam), 4) FROM sutler'),
      'yem_kg': await tek('SELECT ROUND(SUM(toplam), 4) FROM yemler'),
      'odeme_say': await tek('SELECT COUNT(*) FROM cari_odemeler'),
      'odenen': await tek('SELECT ROUND(SUM(odenen_tutar), 4) FROM cari_odemeler'),
      'kalan': await tek('SELECT ROUND(SUM(kalan_tutar), 4) FROM cari_odemeler'),
    };
  }

  /// Geri yükleme ekranının yaptığı: doğrula → dosyayı yerine koy → aç.
  Future<void> geriYukleVeDenetle(String yedek) async {
    await VeriYonetimiRepository.dbDosyasiniDogrula(yedek, factory: databaseFactoryFfi);

    final eski = await databaseFactoryFfi.openDatabase(yedek, options: OpenDatabaseOptions(readOnly: true));
    final once = await ozet(eski);
    final cariAdlari = [for (final r in await eski.query('cariler', orderBy: 'id')) '${r['id']} ${r['ad']} ${r['soyad']}'];
    await eski.close();

    // Yeni kurulum: önce boş veritabanı açılmış olsun (uygulama ilk açılış).
    final app = AppDatabase.test(factory: databaseFactoryFfi, klasor: klasor.path);
    await app.database;
    await app.dosyayiDegistir((yol) async {
      final gecici = File('$yol.geri_yukleme');
      await File(yedek).copy(gecici.path);
      await AppDatabase.dosyayiYerineKoy(gecici, yol);
    });
    final db = await app.database;

    expect(Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version')), MigrationRunner.targetVersion);
    expect(await db.rawQuery('PRAGMA quick_check'), [{'quick_check': 'ok'}]);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    // Hiçbir kg / ₺ değişmedi (mükerrer günler TOPLANARAK birleşir).
    expect(await ozet(db), once);
    expect([for (final r in await db.query('cariler', orderBy: 'id')) '${r['id']} ${r['ad']} ${r['soyad']}'], cariAdlari);

    // Yeni sürüm ekranlarının kullandığı sorgular çalışıyor.
    final cariler = await CariRepository(db).getAll();
    expect(cariler.length, once['cari']);
    expect(cariler.every((c) => c.aktif), isTrue, reason: 'eski cariler aktif sayılmalı');
    await CariOdemeRepository(db).getTumKalanBorclar();
    final sut = SutRepository(db);
    await sut.toplamByCariInRange('2000-01-01', '2100-12-31');

    // Geri yüklenen veritabanına yeni kayıt girilebiliyor.
    final ilk = cariler.first.id!;
    await sut.gunlukKaydet(cariId: ilk, tarih: '2026-11-19', sabah: 21.5, aksam: 0);
    expect((await sut.getGunluk(ilk, '2026-11-19'))!.sabah, 21.5);
    await app.close();
  }

  test('eski sürüm (şema 0) .db yedeği yeni sürüme kayıpsız geri yüklenir', () async {
    final yedek = await eskiYedekUret();
    await geriYukleVeDenetle(yedek);
  });

  test('eski yedekteki mükerrer gün birleşir, saatli tarih gün olur', () async {
    final yedek = await eskiYedekUret();
    await geriYukleVeDenetle(yedek);
    final db = await AppDatabase.test(factory: databaseFactoryFfi, klasor: klasor.path).database;
    final g1 = await db.query('sutler', where: 'cari_id = 1 AND tarih = ?', whereArgs: ['2026-10-01']);
    expect(g1.length, 1);
    expect(g1.first['aksam'], 9.5 + 5.5);
    expect((await db.query('sutler', where: 'cari_id = 2 AND tarih = ?', whereArgs: ['2026-10-11'])).length, 1);
    await db.close();
  });

  final gercek = Platform.environment['ESKI_YEDEK'];
  test('gerçek eski yedek dosyası', () async {
    final kopya = p.join(klasor.path, 'gercek_kopya.db');
    await File(gercek!).copy(kopya); // asıl dosyaya dokunulmaz
    await geriYukleVeDenetle(kopya);
  }, skip: gercek == null ? 'ESKI_YEDEK verilmedi' : false);
}
