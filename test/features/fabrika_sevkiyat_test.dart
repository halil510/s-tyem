// TANK, FABRİKAYA SEVKİYAT ve FABRİKA CARİ HESABI (migration v15) — 2026-11-21.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/core/database/migrations/migration_runner.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v10_tarih_indeksleri.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v11_gunluk_fiyat.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v12_cari_sira.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v13_senkron.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v14_senkron_gruplar.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v1_initial.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v2_cari_odemeler.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v3_cari_fiyatlar.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v4_indexler.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v5_terazi_cihazlari.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v6_islem_gecmisi.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v7_cari_durum_vade.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v8_sut_gunluk_tekil.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v9_donemler.dart';
import 'package:sutyem_pro/data/repositories/fabrika_repository.dart';
import 'package:sutyem_pro/data/repositories/veri_yonetimi_repository.dart';
import 'package:sutyem_pro/data/yedek/yedek_servisi.dart';
import 'package:sutyem_pro/features/fabrika/fabrika_hesap.dart';
import 'package:sutyem_pro/features/fabrika/fabrika_providers.dart';
import 'package:sutyem_pro/models/fabrika_model.dart';
import 'package:sutyem_pro/senkron/senk_cekirdek.dart';

import '../helpers/test_db.dart';

Future<int> say(Database db, String t, [String? where]) async =>
    (await db.rawQuery('SELECT COUNT(*) AS n FROM $t${where == null ? '' : ' WHERE $where'}')).first['n'] as int;

void main() {
  late Database db;
  late FabrikaRepository repo;

  setUp(() async {
    db = await testVeritabaniAc();
    repo = FabrikaRepository(db);
  });
  tearDown(() => db.close());

  Future<int> fabrika([String ad = 'Pınar Süt']) => repo.fabrikaEkle(Fabrika(ad: ad));

  // ───────────────────────────── ŞEMA ─────────────────────────────
  group('migration v15', () {
    test('yeni kurulumda tablolar var; v13 yeni kurulumda yeni tabloları beklemeden çalışır', () async {
      expect(MigrationRunner.targetVersion, greaterThanOrEqualTo(15));
      for (final t in ['fabrikalar', 'sevkiyatlar', 'fabrika_hareketleri', 'tank_sayimlari']) {
        expect(await say(db, 'sqlite_master', "type = 'table' AND name = '$t'"), 1, reason: t);
      }
    });

    test('v14 veritabanı v15\'e yükselir; mevcut veriye dokunulmaz, yeni tablolarda eşitleme tetikleyicisi kurulur', () async {
      sqfliteFfiInit();
      final eski = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
          options: OpenDatabaseOptions(singleInstance: false, onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON')));
      addTearDown(eski.close);
      await MigrationRunner(migrations: [
        MigrationV1Initial(), MigrationV2CariOdemeler(), MigrationV3CariFiyatlar(), MigrationV4Indexler(),
        MigrationV5TeraziCihazlari(), MigrationV6IslemGecmisi(), MigrationV7CariDurumVade(), MigrationV8SutGunlukTekil(),
        MigrationV9Donemler(), MigrationV10TarihIndeksleri(), MigrationV11GunlukFiyat(), MigrationV12CariSira(),
        MigrationV13Senkron(), MigrationV14SenkronGruplar(),
      ]).run(eski);
      final cari = await cariEkle(eski, ad: 'Ali');
      await eski.insert('sutler', {'cari_id': cari, 'tarih': '2026-11-01', 'sabah': 10, 'aksam': 5, 'toplam': 15});
      await eski.insert('senk_kanallar', {'kanal': 'bulut', 'son_gonderilen': 40, 'son_cekilen': 70});
      expect(await MigrationRunner().run(eski), MigrationRunner.targetVersion - 14);
      expect(await say(eski, 'sutler'), 1);
      // Karışık sürüm: eski sürümün attığı fabrika kayıtları yeniden çekilsin; gönderim sayacı korunur.
      final k = (await eski.query('senk_kanallar')).single;
      expect(k['son_cekilen'], 0);
      expect(k['son_gonderilen'], 40);
      expect(await say(eski, 'senk_ayarlar', "anahtar = 'taban_nesil'"), 1, reason: 'ana cihazsa bağlılar yeniden gönderir');

      final r = FabrikaRepository(eski);
      final f = await r.fabrikaEkle(const Fabrika(ad: 'Sütaş'));
      await r.sevkiyatEkle(Sevkiyat(fabrikaId: f, tarih: '2026-11-01', kg: 15));
      await r.tankKaydet('2026-11-01', 3);
      final uuid = (await eski.query('fabrikalar')).single['uuid'];
      expect(uuid, isNotNull, reason: 'uuid tetikleyiciyle verilir');
      expect(await say(eski, 'senk_gunluk', "tablo = 'fabrikalar' AND anahtar = '$uuid'"), greaterThan(0));
      expect(await say(eski, 'senk_gunluk', "tablo = 'sevkiyatlar'"), greaterThan(0));
      expect(await say(eski, 'senk_gunluk', "tablo = 'tank_sayimlari' AND anahtar = '2026-11-01'"), 1);
    });

    test('hareketi olan fabrika veritabanı düzeyinde de silinemez (RESTRICT)', () async {
      final f = await fabrika();
      await repo.sevkiyatEkle(Sevkiyat(fabrikaId: f, tarih: '2026-11-01', kg: 100));
      expect(() => db.delete('fabrikalar', where: 'id = ?', whereArgs: [f]), throwsA(isA<DatabaseException>()));
      expect(await say(db, 'sevkiyatlar'), 1);
    });
  });

  // ───────────────────────────── REPOSITORY ─────────────────────────────
  group('doğrulama', () {
    test('sevkiyat: 0 / negatif / aşırı kg, bozuk tarih ve saat, aşırı fiyat reddedilir; hiçbir şey yazılmaz', () async {
      final f = await fabrika();
      final hatali = [
        Sevkiyat(fabrikaId: f, tarih: '2026-11-01', kg: 0),
        Sevkiyat(fabrikaId: f, tarih: '2026-11-01', kg: -5),
        Sevkiyat(fabrikaId: f, tarih: '2026-11-01', kg: double.nan),
        Sevkiyat(fabrikaId: f, tarih: '2026-11-01', kg: 600000),
        Sevkiyat(fabrikaId: f, tarih: '2026-02-30', kg: 100),
        Sevkiyat(fabrikaId: f, tarih: '1.11.2026', kg: 100),
        Sevkiyat(fabrikaId: f, tarih: '2026-11-01', saat: '25:00', kg: 100),
        Sevkiyat(fabrikaId: f, tarih: '2026-11-01', kg: 100, birimFiyat: 1850),
        Sevkiyat(fabrikaId: f + 99, tarih: '2026-11-01', kg: 100),
      ];
      for (final s in hatali) {
        await expectLater(repo.sevkiyatEkle(s), throwsA(isA<FabrikaKayitHatasi>()), reason: '${s.toMap()}');
      }
      expect(await say(db, 'sevkiyatlar'), 0);
      expect(await say(db, 'islem_gecmisi', "tablo_adi = 'sevkiyatlar'"), 0);
    });

    test('fabrika adı boş olamaz, Türkçe büyük/küçük harf farkıyla aynı ad ikinci kez eklenemez', () async {
      await fabrika('İzmir Süt');
      await expectLater(repo.fabrikaEkle(const Fabrika(ad: '   ')), throwsA(isA<FabrikaKayitHatasi>()));
      await expectLater(repo.fabrikaEkle(const Fabrika(ad: 'izmir  süt')), throwsA(isA<FabrikaKayitHatasi>()));
      expect(await say(db, 'fabrikalar'), 1);
    });

    test('tahsilat tutarı: 0, negatif, yarım kuruşa yuvarlanınca 0 reddedilir; kuruşa yuvarlanır', () async {
      final f = await fabrika();
      for (final t in [0.0, -1.0, 0.004, double.infinity]) {
        await expectLater(
            repo.hareketEkle(FabrikaHareketi(fabrikaId: f, tarih: '2026-11-05', tur: FabrikaHareketTuru.tahsilat, tutar: t)),
            throwsA(isA<FabrikaKayitHatasi>()),
            reason: '$t');
      }
      await repo.hareketEkle(FabrikaHareketi(fabrikaId: f, tarih: '2026-11-05', tur: FabrikaHareketTuru.tahsilat, tutar: 1250.555));
      expect((await db.query('fabrika_hareketleri')).single['tutar'], 1250.56);
    });

    test('hareketi olan fabrika silinmez (pasife alınır); hareketsiz fabrika silinir; denetim kaydı yazılır', () async {
      final f = await fabrika();
      final bos = await fabrika('Boş Fabrika');
      await repo.hareketEkle(FabrikaHareketi(fabrikaId: f, tarih: '2026-11-05', tur: FabrikaHareketTuru.tahsilat, tutar: 10));
      await expectLater(repo.fabrikaSil(f), throwsA(isA<FabrikaKayitHatasi>()));
      await repo.fabrikaSil(bos);
      expect((await repo.fabrikalar()).map((x) => x.id), [f]);
      await repo.fabrikaGuncelle((await repo.fabrikalar()).single.copyWith(aktif: false));
      expect(await repo.fabrikalar(sadeceAktif: true), isEmpty);
      expect(await say(db, 'islem_gecmisi', "tablo_adi = 'fabrikalar' AND islem = 'sil'"), 1);
      expect(await say(db, 'islem_gecmisi', "tablo_adi = 'fabrika_hareketleri' AND islem = 'ekle'"), 1);
    });

    test('düzenleme uuid\'yi korur (eşitleme kimliği değişmez)', () async {
      final f = await fabrika();
      final id = await repo.sevkiyatEkle(Sevkiyat(fabrikaId: f, tarih: '2026-11-01', kg: 100));
      final uuid = (await db.query('sevkiyatlar')).single['uuid'];
      await repo.sevkiyatGuncelle(Sevkiyat(id: id, fabrikaId: f, tarih: '2026-11-02', kg: 120, birimFiyat: 18.5, fisNo: ' 42 '));
      final s = (await db.query('sevkiyatlar')).single;
      expect(s['uuid'], uuid);
      expect(s['kg'], 120);
      expect(s['fis_no'], '42');
    });
  });

  group('fiyat', () {
    test('son birim fiyat formu doldurur; "fiyat uygula" yalnız fiyatsızlara ya da tüm aya', () async {
      final f = await fabrika();
      final f2 = await fabrika('Başka');
      await repo.sevkiyatEkle(Sevkiyat(fabrikaId: f, tarih: '2026-10-30', kg: 100, birimFiyat: 17));
      await repo.sevkiyatEkle(Sevkiyat(fabrikaId: f, tarih: '2026-11-01', kg: 100));
      await repo.sevkiyatEkle(Sevkiyat(fabrikaId: f, tarih: '2026-11-02', kg: 100, birimFiyat: 18));
      await repo.sevkiyatEkle(Sevkiyat(fabrikaId: f2, tarih: '2026-11-02', kg: 100));
      expect(await repo.sonBirimFiyat(f), 18);
      expect(await repo.sonBirimFiyat(f2), isNull);

      expect(await repo.fiyatUygula(fabrikaId: f, start: '2026-11-01', end: '2026-11-30', birimFiyat: 18.75), 1);
      final l = await repo.sevkiyatlar('2026-10-01', '2026-11-30', fabrikaId: f);
      expect(l.map((s) => s.birimFiyat), [17, 18.75, 18], reason: 'ekim ve fiyatlı kasım kaydı değişmez');
      expect((await repo.sevkiyatlar('2026-11-01', '2026-11-30', fabrikaId: f2)).single.birimFiyat, 0, reason: 'başka fabrika');

      expect(await repo.fiyatUygula(fabrikaId: f, start: '2026-11-01', end: '2026-11-30', birimFiyat: 19, sadeceFiyatsiz: false), 2);
      expect((await repo.sevkiyatlar('2026-11-01', '2026-11-30', fabrikaId: f)).map((s) => s.birimFiyat), [19, 19]);
      await expectLater(
          repo.fiyatUygula(fabrikaId: f, start: '2026-11-01', end: '2026-11-30', birimFiyat: 0), throwsA(isA<FabrikaKayitHatasi>()));
    });
  });

  // ───────────────────────────── FABRİKA HESABI ─────────────────────────────
  group('fabrika bakiyesi ve ekstre', () {
    test('bakiye = sevk + ek − tahsilat − kesinti; satır kuruşa yuvarlanır; ekstre ay sonu = güncel bakiye', () async {
      final f = await fabrika();
      // Ekim: devir oluşturur.
      await repo.sevkiyatEkle(Sevkiyat(fabrikaId: f, tarih: '2026-10-31', kg: 1000, birimFiyat: 17.5)); // 17.500
      await repo.hareketEkle(FabrikaHareketi(fabrikaId: f, tarih: '2026-10-31', tur: FabrikaHareketTuru.tahsilat, tutar: 10000));
      // Kasım: 3 × (1,005 kg × 18,5 = 18,5925 → 18,59) = 55,77 (toplu çarpımda 55,78 olurdu).
      for (var i = 0; i < 3; i++) {
        await repo.sevkiyatEkle(Sevkiyat(fabrikaId: f, tarih: '2026-11-0${i + 1}', kg: 1.005, birimFiyat: 18.5));
      }
      await repo.sevkiyatEkle(Sevkiyat(fabrikaId: f, tarih: '2026-11-03', saat: '07:30', kg: 500)); // fiyatsız
      await repo.hareketEkle(FabrikaHareketi(fabrikaId: f, tarih: '2026-11-03', tur: FabrikaHareketTuru.kesinti, tutar: 150));
      await repo.hareketEkle(FabrikaHareketi(fabrikaId: f, tarih: '2026-11-04', tur: FabrikaHareketTuru.ek, tutar: 200));
      await repo.hareketEkle(FabrikaHareketi(fabrikaId: f, tarih: '2026-11-04', tur: FabrikaHareketTuru.tahsilat, tutar: 5000));

      final e = fabrikaEkstresi(
          sevkiyatlar: await repo.fabrikaSevkiyatlari(f), hareketler: await repo.fabrikaHareketleri(f), bas: '2026-11-01', son: '2026-11-30');
      expect(e.devir, 7500);
      expect(e.sevkTutar, 55.77);
      expect(e.sevkKg, 503.015);
      expect(e.fiyatsizSayisi, 1);
      expect(e.kesinti, 150);
      expect(e.ek, 200);
      expect(e.tahsilat, 5000);
      expect(e.sonBakiye, 2605.77); // 7500 + 55,77 + 200 − 150 − 5000
      expect(e.satirlar.last.bakiye, e.sonBakiye, reason: 'yürüyen bakiye ay sonuyla aynı');
      // Aynı gün (3 Kasım): önce sevkiyatlar (saatsiz, sonra 07:30), sonra kesinti.
      final g3 = e.satirlar.where((s) => s.tarih == '2026-11-03').toList();
      expect(g3.map((s) => s.sevkiyat != null), [true, true, false]);
      expect(g3[1].sevkiyat!.saat, '07:30');

      expect((await repo.bakiyeler())[f], e.sonBakiye);
      // Ekim ekstresi Kasım'ı içermez.
      final ekim = fabrikaEkstresi(
          sevkiyatlar: await repo.fabrikaSevkiyatlari(f), hareketler: await repo.fabrikaHareketleri(f), bas: '2026-10-01', son: '2026-10-31');
      expect(ekim.devir, 0);
      expect(ekim.sonBakiye, 7500);
    });

    test('fabrikaEkstresiProvider ve fabrikaBakiyeleriProvider aynı rakamı verir', () async {
      final f = await fabrika();
      await repo.sevkiyatEkle(Sevkiyat(fabrikaId: f, tarih: '2026-11-01', kg: 2000, birimFiyat: 18.4));
      await repo.hareketEkle(FabrikaHareketi(fabrikaId: f, tarih: '2026-11-10', tur: FabrikaHareketTuru.tahsilat, tutar: 30000));
      final c = testContainer(db);
      addTearDown(c.dispose);
      final d1 = c.listen(fabrikaEkstresiProvider((fabrikaId: f, ay: '2026-11')), (_, __) {});
      final d2 = c.listen(fabrikaBakiyeleriProvider, (_, __) {});
      addTearDown(d1.close);
      addTearDown(d2.close);
      final e = await c.read(fabrikaEkstresiProvider((fabrikaId: f, ay: '2026-11')).future);
      expect(e.sonBakiye, 6800);
      expect((await c.read(fabrikaBakiyeleriProvider.future))[f], 6800);
    });
  });

  // ───────────────────────────── TANK / FİRE ─────────────────────────────
  group('tank ve fire', () {
    test('tank sayımı günde tek satır; 0 yazınca silinir; aynı değer yeniden yazılmaz', () async {
      await repo.tankKaydet('2026-11-01', 850.5, aciklama: 'akşam sütü');
      await repo.tankKaydet('2026-11-01', 900);
      expect(await say(db, 'tank_sayimlari'), 1);
      expect((await repo.tankSayimi('2026-11-01'))!.kalanKg, 900);
      final once = await say(db, 'islem_gecmisi', "tablo_adi = 'tank_sayimlari'");
      await repo.tankKaydet('2026-11-01', 900);
      expect(await say(db, 'islem_gecmisi', "tablo_adi = 'tank_sayimlari'"), once, reason: 'değişmeyen değer yazılmaz');
      await repo.tankKaydet('2026-11-01', 0);
      expect(await repo.tankSayimi('2026-11-01'), isNull);
      await expectLater(repo.tankKaydet('2026-11-01', -1), throwsA(isA<FabrikaKayitHatasi>()));
    });

    test('ertesi güne kalan süt tank sayımıyla fire sayılmaz; sayım yoksa günlük fark görünür ama ay toplamı aynıdır', () {
      final toplanan = {'2026-11-01': 1000.0, '2026-11-02': 1000.0};
      final sevk = {'2026-11-01': 600.0, '2026-11-02': 1400.0};
      final tanksiz = fireGunleri(
          bas: DateTime(2026, 11, 1), son: DateTime(2026, 11, 3), toplanan: toplanan, sevk: sevk, tank: const {}, bugun: '2026-11-21');
      expect(tanksiz.map((g) => g.fark), [400, -400]);
      expect(tanksiz.map((g) => g.durum), [FireDurumu.tankGirilmemis, FireDurumu.tankGirilmemis], reason: 'alarm değil, hatırlatma');
      expect(FireOzeti.hesapla(tanksiz).fark, 0);

      final tankli = fireGunleri(
          bas: DateTime(2026, 11, 1),
          son: DateTime(2026, 11, 3),
          toplanan: toplanan,
          sevk: sevk,
          tank: {'2026-11-01': 400},
          bugun: '2026-11-21');
      expect(tankli.map((g) => g.fark), [0, 0]);
      expect(tankli.map((g) => g.durum), [FireDurumu.normal, FireDurumu.normal]);
      expect(tankli.length, 2, reason: 'hareketsiz 3 Kasım listelenmez');
    });

    test('akşam toplanıp ertesi sabah sevk edilen süt (tank girilmemiş) alarm değil "tank girilmemiş?" olur', () {
      final g = fireGunleri(
        bas: DateTime(2026, 11, 1),
        son: DateTime(2026, 11, 4),
        toplanan: {'2026-11-01': 1000, '2026-11-02': 1000, '2026-11-03': 1000, '2026-11-04': 1000},
        sevk: {'2026-11-01': 600, '2026-11-02': 1000, '2026-11-03': 1400, '2026-11-04': 900},
        tank: const {},
        bugun: '2026-11-21',
      );
      expect(g.map((x) => x.fark), [400, 0, -400, 100]);
      expect(g.map((x) => x.durum),
          [FireDurumu.fire, FireDurumu.normal, FireDurumu.fazlaSevk, FireDurumu.fire],
          reason: 'ardışık değil (arada normal gün var) → desen yok');
      final h = fireGunleri(
        bas: DateTime(2026, 11, 1),
        son: DateTime(2026, 11, 3),
        toplanan: {'2026-11-01': 1000, '2026-11-02': 1000, '2026-11-03': 1000},
        sevk: {'2026-11-01': 600, '2026-11-02': 1400, '2026-11-03': 900},
        tank: const {},
        bugun: '2026-11-21',
      );
      expect(h.map((x) => x.durum), [FireDurumu.tankGirilmemis, FireDurumu.tankGirilmemis, FireDurumu.fire]);
      expect(FireOzeti.hesapla(h).fark, 100, reason: 'ay özeti gerçek kaybı gösterir');
      // Gün sonu tank girildiyse desen aranmaz: gerçek fire.
      final k = fireGunleri(
        bas: DateTime(2026, 11, 1),
        son: DateTime(2026, 11, 2),
        toplanan: {'2026-11-01': 1000, '2026-11-02': 1000},
        sevk: {'2026-11-01': 500, '2026-11-02': 1400},
        tank: {'2026-11-01': 100},
        bugun: '2026-11-21',
      );
      expect(k.map((x) => x.durum), [FireDurumu.fire, FireDurumu.fazlaSevk]);
    });

    test('eşikler: %1 altı ve 2 kg\'a kadar fark normal; bugün "sürüyor"; önceki aydan tank devri', () {
      final g = fireGunleri(
        bas: DateTime(2026, 11, 1),
        son: DateTime(2026, 11, 4),
        toplanan: {'2026-11-01': 1000, '2026-11-02': 1000, '2026-11-03': 100, '2026-11-04': 1000},
        sevk: {'2026-11-01': 1295, '2026-11-02': 985, '2026-11-03': 97.5, '2026-11-04': 200},
        tank: {'2026-10-31': 300},
        bugun: '2026-11-04',
      );
      expect(g[0].giren, 1300);
      expect(g[0].fark, 5);
      expect(g[0].durum, FireDurumu.normal, reason: '5 kg = %0,38');
      expect(g[1].durum, FireDurumu.fire, reason: '15 kg = %1,5');
      expect(g[2].fark, 2.5);
      expect(g[2].durum, FireDurumu.fire, reason: '2,5 kg > 2 kg tolerans ve %2,5');
      expect(g[3].durum, FireDurumu.suruyor);
      final oz = FireOzeti.hesapla(g.where((x) => !x.bugun).toList());
      expect(oz.tankBaslangic, 300);
      expect(oz.fark, closeTo(g[0].fark + g[1].fark + g[2].fark, 1e-9));
    });

    test('fireAyiProvider: süt kayıtları + sevkiyat + tank (önceki ayın son günü dahil)', () async {
      final ali = await cariEkle(db, ad: 'Ali');
      final veli = await cariEkle(db, ad: 'Veli');
      await db.insert('sutler', {'cari_id': ali, 'tarih': '2026-10-01', 'sabah': 100, 'aksam': 80, 'toplam': 180});
      await db.insert('sutler', {'cari_id': veli, 'tarih': '2026-10-01', 'sabah': 50, 'aksam': 20, 'toplam': 70});
      await db.insert('sutler', {'cari_id': ali, 'tarih': '2026-10-02', 'sabah': 100, 'aksam': 0, 'toplam': 100});
      final f = await fabrika();
      await repo.tankKaydet('2026-09-30', 40);
      await repo.sevkiyatEkle(Sevkiyat(fabrikaId: f, tarih: '2026-10-01', kg: 200));
      await repo.sevkiyatEkle(Sevkiyat(fabrikaId: f, tarih: '2026-10-01', saat: '19:00', kg: 100));
      await repo.sevkiyatEkle(Sevkiyat(fabrikaId: f, tarih: '2026-10-02', kg: 60));
      await repo.tankKaydet('2026-10-02', 30);
      final c = testContainer(db);
      addTearDown(c.dispose);
      final dinle = c.listen(fireAyiProvider('2026-10'), (_, __) {});
      addTearDown(dinle.close);
      final a = await c.read(fireAyiProvider('2026-10').future);
      // 3 Ekim: önceki gün tankta 30 kg kalmış ama ne sevk ne sayım var → 30 kg kayıp görünür.
      expect(a.gunler.map((g) => g.tarih), ['2026-10-01', '2026-10-02', '2026-10-03']);
      expect(a.gunler[0].toplanan, 250);
      expect(a.gunler[0].sevk, 300);
      expect(a.gunler[0].tankOnceki, 40);
      expect(a.gunler[0].fark, -10);
      expect(a.gunler[0].durum, FireDurumu.fazlaSevk);
      expect(a.gunler[1].fark, 10);
      expect(a.gunler[2].fark, 30);
      expect(a.gunler[2].durum, FireDurumu.fire);
      expect(a.ozet.fark, 30, reason: 'ay farkı = günlük farkların toplamı');
      expect(a.kesinOzet.fark, 30, reason: 'geçmiş ay: bugün yok');
    });
  });

  // ───────────────────────────── YEDEK / TEMİZLİK ─────────────────────────────
  group('yedek ve temizlik', () {
    Future<void> ornek() async {
      final f = await fabrika();
      await repo.sevkiyatEkle(Sevkiyat(fabrikaId: f, tarih: '2026-11-01', kg: 1000, birimFiyat: 18));
      await repo.hareketEkle(FabrikaHareketi(fabrikaId: f, tarih: '2026-11-05', tur: FabrikaHareketTuru.tahsilat, tutar: 5000));
      await repo.tankKaydet('2026-11-01', 120);
    }

    test('JSON yedek yeni tabloları içerir; tamamen değiştir ile birebir geri gelir', () async {
      await ornek();
      final json = await YedekServisi.disaAktarJson(db);
      final veri = YedekServisi.coz(json);
      expect((veri['meta'] as Map)['format_version'], YedekServisi.formatSurumu);
      for (final t in ['fabrikalar', 'sevkiyatlar', 'fabrika_hareketleri', 'tank_sayimlari']) {
        expect(veri[t], hasLength(1), reason: t);
      }
      final once = {for (final t in YedekServisi.tablolar) t: await db.query(t, orderBy: 'id')};
      await VeriYonetimiRepository(db).temizle(TemizlikTuru.hepsi);
      expect(await say(db, 'fabrikalar'), 0);
      await YedekServisi.iceAktar(db, YedekServisi.coz(json), tamamenDegistir: true);
      for (final t in YedekServisi.tablolar) {
        expect(await db.query(t, orderBy: 'id'), once[t], reason: t);
      }
    });

    test('ESKİ (v3, fabrikasız) yedekle "tamamen değiştir": bu cihazın fabrika hesabı SİLİNMEZ', () async {
      await ornek();
      final eskiYedek = jsonDecode(await YedekServisi.disaAktarJson(db)) as Map<String, dynamic>;
      for (final t in ['fabrikalar', 'sevkiyatlar', 'fabrika_hareketleri', 'tank_sayimlari']) {
        eskiYedek.remove(t);
      }
      (eskiYedek['meta'] as Map)['format_version'] = 3;
      await YedekServisi.iceAktar(db, eskiYedek, tamamenDegistir: true);
      expect(await say(db, 'fabrikalar'), 1);
      expect(await say(db, 'sevkiyatlar'), 1);
      expect(await say(db, 'fabrika_hareketleri'), 1);
      expect(await say(db, 'tank_sayimlari'), 1);
    });

    test('birleştirerek geri yükleme: tank sayımı aynı güne İKİNCİ satır açmaz (doğal anahtar)', () async {
      await ornek();
      final veri = YedekServisi.coz(await YedekServisi.disaAktarJson(db));
      (veri['tank_sayimlari'] as List).first['id'] = 999; // başka id, aynı gün
      (veri['tank_sayimlari'] as List).first['kalan_kg'] = 150;
      await YedekServisi.iceAktar(db, veri);
      expect(await say(db, 'tank_sayimlari'), 1);
      expect((await repo.tankSayimi('2026-11-01'))!.kalanKg, 150);
    });

    test('başka telefonun yedeği BİRLEŞTİRİLİRKEN aynı numaralı farklı fabrika ezilmez; hiçbir şey yazılmaz', () async {
      await ornek();
      final veri = YedekServisi.coz(await YedekServisi.disaAktarJson(db));
      (veri['fabrikalar'] as List).first
        ..['uuid'] = 'baska-telefonun-fabrikasi'
        ..['ad'] = 'Başka Fabrika';
      (veri['sevkiyatlar'] as List).first['kg'] = 1;
      await expectLater(YedekServisi.iceAktar(db, veri), throwsA(isA<YedekHatasi>()));
      expect((await repo.fabrikalar()).single.ad, 'Pınar Süt');
      expect((await db.query('sevkiyatlar')).single['kg'], 1000);
    });

    test('"yalnız hareketler" temizliği sevkiyat/ödeme/tankı siler, fabrikayı bırakır', () async {
      await ornek();
      final s = await VeriYonetimiRepository(db).temizle(TemizlikTuru.hareketler);
      expect(s['sevkiyatlar'], 1);
      expect(await say(db, 'sevkiyatlar'), 0);
      expect(await say(db, 'fabrika_hareketleri'), 0);
      expect(await say(db, 'tank_sayimlari'), 0);
      expect(await say(db, 'fabrikalar'), 1);
    });
  });

  // ───────────── ÇOKLU CİHAZ: aynı anda fabrika silme + sevkiyat girme ─────────────
  group('çoklu cihaz yarışı', () {
    // Gerçek kanal gibi: kanal başına gönderim sayacı + yankı önleme (karşıdan gelen geri gitmez).
    final sayac = <String, int>{};
    Future<void> aktar(Database kimden, String kAd, Database kime, String hAd) async {
      final (kayitlar, sonId) = await SenkCekirdek(kimden)
          .gonderilecekler(sonra: sayac['$kAd>$hAd'] ?? 0, haricKaynak: 'kanal:$hAd', limit: 100000);
      sayac['$kAd>$hAd'] = sonId;
      await kime.transaction((txn) => SenkCekirdek(txn).uygula(kayitlar, kanal: 'kanal:$kAd'));
    }

    Future<void> esitle(Database a, Database b, {required bool onceA}) async {
      for (var i = 0; i < 4; i++) {
        if (onceA) {
          await aktar(a, 'A', b, 'B');
          await aktar(b, 'B', a, 'A');
        } else {
          await aktar(b, 'B', a, 'A');
          await aktar(a, 'A', b, 'B');
        }
      }
    }

    for (final onceA in [true, false]) {
      test('A boş fabrikayı silerken B ona sevkiyat girer (${onceA ? 'önce A→B' : 'önce B→A'}): '
          'fabrika ve sevkiyat İKİ telefonda da kalır, hata/bekleyen yok, uyarı verilir', () async {
        sayac.clear();
        final b = await testVeritabaniAc();
        addTearDown(b.close);
        await SenkCekirdek.cihazAyarla(db, 'cihaz-A');
        await SenkCekirdek.cihazAyarla(b, 'cihaz-B');
        final rb = FabrikaRepository(b);

        await fabrika();
        await esitle(db, b, onceA: true);
        final fa = (await repo.fabrikalar()).single.id!;
        final fb = (await rb.fabrikalar()).single.id!;

        // Eşitleme olmadan, aynı anda:
        await repo.fabrikaSil(fa); // A'da kaydı yok → silinir
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await rb.sevkiyatEkle(Sevkiyat(fabrikaId: fb, tarih: '2026-11-01', kg: 1000, birimFiyat: 18));
        await rb.hareketEkle(FabrikaHareketi(fabrikaId: fb, tarih: '2026-11-02', tur: FabrikaHareketTuru.tahsilat, tutar: 500));

        await esitle(db, b, onceA: onceA);

        for (final (ad, d) in [('A', db), ('B', b)]) {
          final r = FabrikaRepository(d);
          final f = await r.fabrikalar();
          expect(f, hasLength(1), reason: '$ad: fabrika korunmalı');
          expect(await say(d, 'sevkiyatlar'), 1, reason: '$ad: sevkiyat kaybolmamalı');
          expect(await say(d, 'fabrika_hareketleri'), 1, reason: '$ad: ödeme kaybolmamalı');
          expect((await r.bakiyeler())[f.single.id], 17500, reason: '$ad: iki telefonda aynı bakiye');
          expect(await say(d, 'senk_bekleyen'), 0, reason: '$ad: bekleyen kayıt kalmamalı');
          expect(await say(d, 'senk_hatalar', "kanal <> 'uyari'"), 0, reason: '$ad: eşitleme hatası olmamalı');
        }
        expect(await say(b, 'senk_hatalar', "kanal = 'uyari' AND tablo = 'fabrikalar'"), 1, reason: 'kullanıcıya not');
        expect((await db.query('fabrikalar')).single['uuid'], (await b.query('fabrikalar')).single['uuid']);
      });
    }

    test('kaydı olmayan fabrikanın silinmesi normal şekilde diğer telefona yansır', () async {
      sayac.clear();
      final b = await testVeritabaniAc();
      addTearDown(b.close);
      await SenkCekirdek.cihazAyarla(db, 'cihaz-A');
      await SenkCekirdek.cihazAyarla(b, 'cihaz-B');
      await fabrika();
      await esitle(db, b, onceA: true);
      await repo.fabrikaSil((await repo.fabrikalar()).single.id!);
      await esitle(db, b, onceA: true);
      expect(await say(b, 'fabrikalar'), 0);
      expect(await say(b, 'senk_hatalar'), 0);
    });
  });

  // ───────────────────────────── ÇOKLU CİHAZ ─────────────────────────────
  group('çoklu cihaz', () {
    Future<void> aktar(Database kimden, Database kime, String kanal) async {
      final (kayitlar, _) = await SenkCekirdek(kimden).gonderilecekler(sonra: 0, haricKaynak: null, limit: 100000);
      await kime.transaction((txn) => SenkCekirdek(txn).uygula(kayitlar, kanal: kanal));
    }

    test('fabrika, sevkiyat, ödeme ve tank sayımı diğer telefona geçer; tank aynı güne iki satır olmaz; silme yansır', () async {
      final b = await testVeritabaniAc();
      addTearDown(b.close);
      await SenkCekirdek.cihazAyarla(db, 'cihaz-A');
      await SenkCekirdek.cihazAyarla(b, 'cihaz-B');
      final rb = FabrikaRepository(b);

      final f = await fabrika();
      final sid = await repo.sevkiyatEkle(Sevkiyat(fabrikaId: f, tarih: '2026-11-01', kg: 1000, birimFiyat: 18));
      await repo.hareketEkle(FabrikaHareketi(fabrikaId: f, tarih: '2026-11-05', tur: FabrikaHareketTuru.tahsilat, tutar: 5000));
      await repo.tankKaydet('2026-11-01', 120);
      await aktar(db, b, 'kanal:A');

      expect(await say(b, 'senk_bekleyen'), 0, reason: 'hiçbir kayıt bekletilmemeli');
      final fb = (await rb.fabrikalar()).single;
      expect(fb.ad, 'Pınar Süt');
      expect((await rb.bakiyeler())[fb.id], 13000);
      expect((await rb.tankSayimi('2026-11-01'))!.kalanKg, 120);

      // B aynı güne tank yazar (A'dan sonra) → A'da da tek satır, B'nin değeri.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await rb.tankKaydet('2026-11-01', 135);
      await aktar(b, db, 'kanal:B');
      expect(await say(db, 'tank_sayimlari'), 1);
      expect((await repo.tankSayimi('2026-11-01'))!.kalanKg, 135);

      // A sevkiyatı siler → B'den de silinir.
      await repo.sevkiyatSil(sid);
      await aktar(db, b, 'kanal:A');
      expect(await say(b, 'sevkiyatlar'), 0);
      expect((await rb.bakiyeler())[fb.id], -5000);
    });
  });
}
