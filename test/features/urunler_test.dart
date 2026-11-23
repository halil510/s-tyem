// ÜRÜNLER (yem, gübre… eklenebilir) — migration v16, 2026-11-23.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/core/database/migrations/migration_runner.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v10_tarih_indeksleri.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v11_gunluk_fiyat.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v12_cari_sira.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v13_senkron.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v14_senkron_gruplar.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v15_fabrika_sevkiyat.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v16_urunler.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v1_initial.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v2_cari_odemeler.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v3_cari_fiyatlar.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v4_indexler.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v5_terazi_cihazlari.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v6_islem_gecmisi.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v7_cari_durum_vade.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v8_sut_gunluk_tekil.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v9_donemler.dart';
import 'package:sutyem_pro/core/providers/repository_providers.dart';
import 'package:sutyem_pro/data/repositories/urun_repository.dart';
import 'package:sutyem_pro/data/repositories/yem_repository.dart';
import 'package:sutyem_pro/data/yedek/yedek_servisi.dart';
import 'package:sutyem_pro/features/cari_hesap/providers/cari_hesap_providers.dart';
import 'package:sutyem_pro/features/donem/donem_servisi.dart';
import 'package:sutyem_pro/features/raporlar/rapor_modeli.dart';
import 'package:sutyem_pro/features/raporlar/rapor_servisi.dart';
import 'package:sutyem_pro/models/urun_model.dart';
import 'package:sutyem_pro/models/yem_model.dart';
import 'package:sutyem_pro/senkron/senk_cekirdek.dart';
import 'package:sutyem_pro/utils/sayi_format.dart';

import '../helpers/test_db.dart';

Future<int> say(Database db, String t, [String? where]) async =>
    (await db.rawQuery('SELECT COUNT(*) AS n FROM $t${where == null ? '' : ' WHERE $where'}')).first['n'] as int;

/// v15 (ürünler öncesi) bir veritabanı.
Future<Database> v15Veritabani() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false, onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON')));
  await MigrationRunner(migrations: [
    MigrationV1Initial(), MigrationV2CariOdemeler(), MigrationV3CariFiyatlar(), MigrationV4Indexler(),
    MigrationV5TeraziCihazlari(), MigrationV6IslemGecmisi(), MigrationV7CariDurumVade(), MigrationV8SutGunlukTekil(),
    MigrationV9Donemler(), MigrationV10TarihIndeksleri(), MigrationV11GunlukFiyat(), MigrationV12CariSira(),
    MigrationV13Senkron(), MigrationV14SenkronGruplar(), MigrationV15FabrikaSevkiyat(),
  ]).run(db);
  return db;
}

/// ESKİ (v15) KURAL — bağımsız referans: kaydın gününe kadar başlamış en son cari_fiyatlar
/// satırının ilgili yem sütunu. Dönüşümden ÖNCE hesaplanır, sonra yeni yapıyla karşılaştırılır.
double eskiBirimFiyat(List<Map<String, Object?>> fiyatlar, int cariId, String tarih, String fiyatSutunu) {
  final l = fiyatlar.where((f) => f['cari_id'] == cariId && (f['ay'] as String).compareTo(tarih) <= 0).toList()
    ..sort((a, b) => (a['ay'] as String).compareTo(b['ay'] as String));
  return l.isEmpty ? 0 : ((l.last[fiyatSutunu] as num?)?.toDouble() ?? 0);
}

void main() {
  // ───────────────────────────── ŞEMA / AKTARIM ─────────────────────────────
  group('migration v16', () {
    test('yeni kurulumda eski 6 yem türü SABİT kimlikle ürün (id 1..6, kg), hepsi aktif', () async {
      final db = await testVeritabaniAc();
      addTearDown(db.close);
      expect(MigrationRunner.targetVersion, 16);
      final u = await UrunRepository(db).getAll();
      expect(u.map((x) => (x.id, x.ad, x.birim, x.aktif, x.uuid)), [
        for (var i = 0; i < sistemUrunleri.length; i++) (i + 1, sistemUrunleri[i].ad, 'kg', true, sistemUrunleri[i].uuid),
      ]);
      expect([urunSutYemi, urunBesiYemi, urunBBaslangic, urunBBuyutme, urunKuzuYemi, urunTavukYemi], [1, 2, 3, 4, 5, 6]);
      expect(await say(db, 'senk_gunluk', "tablo = 'urunler'"), 6, reason: 'ürünler eşitleme günlüğüne yazılır');
    });

    test('v15 → v16: her yem kaleminin birim fiyatı BİREBİR korunur; kapalı ay dahil; kilit sonra yine çalışır', () async {
      final db = await v15Veritabani();
      addTearDown(db.close);
      final a = await cariEkle(db, ad: 'Ali'), b = await cariEkle(db, ad: 'Veli');
      // Eski fiyatlar: ay ortası satır yem fiyatı taşır; Kasım'da süt yemi bilerek 0 (fiyat kaldırıldı).
      final fiyatlar = <Map<String, Object?>>[
        {'cari_id': a, 'ay': '2026-09', 'sut_fiyat': 20, 'sut_yemi_fiyat': 10, 'besi_yemi_fiyat': 0},
        {'cari_id': a, 'ay': '2026-10', 'sut_fiyat': 21, 'sut_yemi_fiyat': 10, 'besi_yemi_fiyat': 12.35},
        {'cari_id': a, 'ay': '2026-10-15', 'sut_fiyat': 22, 'sut_yemi_fiyat': 11.5, 'besi_yemi_fiyat': 12.35},
        {'cari_id': a, 'ay': '2026-11', 'sut_fiyat': 22, 'sut_yemi_fiyat': 0, 'besi_yemi_fiyat': 13},
        {'cari_id': b, 'ay': '2026-10', 'sut_fiyat': 19, 'sut_yemi_fiyat': 9.99, 'kuzu_yemi_fiyat': 7},
      ];
      for (final f in fiyatlar) {
        await db.insert('cari_fiyatlar', f);
      }
      final yemler = <Map<String, Object?>>[
        {'cari_id': a, 'tarih': '2026-09-05', 'sut_yemi': 5},
        {'cari_id': a, 'tarih': '2026-10-10', 'sut_yemi': 3, 'besi_yemi': 2.5},
        {'cari_id': a, 'tarih': '2026-10-20', 'sut_yemi': 4.25, 'tavuk_yemi': 1},
        {'cari_id': a, 'tarih': '2026-11-03', 'sut_yemi': 7, 'besi_yemi': 1},
        {'cari_id': b, 'tarih': '2026-10-01'}, // tamamen boş satır
        {'cari_id': b, 'tarih': '2026-10-02', 'kuzu_yemi': 2, 'b_buyutme': 3, 'b_baslangic': 0.5},
      ];
      for (final y in yemler) {
        final m = {...y, 'toplam': sistemUrunleri.fold<double>(0, (t, s) => t + ((y[s.yemSutunu] as num?) ?? 0))};
        await db.insert('yemler', m);
      }
      await db.insert('sutler', {'cari_id': a, 'tarih': '2026-09-05', 'sabah': 10, 'aksam': 0, 'toplam': 10});
      // Eylül kapalı (kilit tetikleyicisi dönüşümü durdurmamalı).
      await db.insert('donemler', {'ay': '2026-09', 'durum': 'kapali'});
      await db.insert('senk_kanallar', {'kanal': 'bulut', 'son_gonderilen': 40, 'son_cekilen': 70});

      // Beklenen (eski kural): her (cari, gün, tür) → (miktar, birim fiyat).
      final eskiUuid = {for (final r in await db.query('yemler')) r['id']: r['uuid']};
      final beklenen = <String, (double, double)>{};
      for (final y in await db.query('yemler')) {
        for (final t in sistemUrunleri) {
          final m = (y[t.yemSutunu] as num?)?.toDouble() ?? 0;
          if (m <= 0) continue;
          beklenen['${y['cari_id']}|${y['tarih']}|${t.uuid}'] =
              (m, eskiBirimFiyat(fiyatlar, y['cari_id'] as int, y['tarih'] as String, t.fiyatSutunu));
        }
      }

      expect(await MigrationRunner().run(db), 1);

      final urunUuid = {for (final r in await db.query('urunler')) r['id']: r['uuid']};
      final l = await UrunFiyatRepository(db).lookup();
      final yeni = await YemRepository(db).getAllInRange('1970-01-01', '2999-12-31');
      expect(yeni.length, beklenen.length, reason: 'boş satır silinir, çok türlü satır bölünür');
      for (final y in yeni) {
        final k = '${y.cariId}|${y.tarih}|${urunUuid[y.urunId]}';
        expect(beklenen.containsKey(k), isTrue, reason: k);
        expect(y.miktar, beklenen[k]!.$1, reason: '$k miktar');
        expect(l.fiyat(y.cariId, y.urunId, y.tarih), beklenen[k]!.$2, reason: '$k birim fiyat');
      }
      // Eski sütunlar sıfırlandı; ilk tür satırın kendisinde (aynı uuid), diğerleri "uuid~ürün".
      expect(await say(db, 'yemler', 'sut_yemi + besi_yemi + b_baslangic + b_buyutme + kuzu_yemi + tavuk_yemi <> 0'), 0);
      final ekim10 = await db.query('yemler', where: "tarih = '2026-10-10'", orderBy: 'id');
      final anaUuid = eskiUuid[ekim10.first['id']] as String;
      expect(ekim10.map((r) => r['uuid']), [anaUuid, '$anaUuid~urun-besi-yemi']);
      // Kasım süt yemi 0 olarak açıkça yazılmıştı: devralınan 11,5 KULLANILMAZ.
      expect(l.fiyat(a, urunSutYemi, '2026-11-03'), 0);
      // Değişim noktaları dışında satır yazılmaz (Eylül besi 0 → yazılmaz).
      expect(await say(db, 'cari_urun_fiyatlari', 'cari_id = $a AND urun_id = $urunBesiYemi'), 2); // Ekim 12,35 · Kasım 13
      // Eşitleme: bölünen satır, ürünler ve fiyatlar günlükte; okuma sayaçları sıfırlandı.
      expect(await say(db, 'senk_gunluk', "tablo = 'yemler' AND anahtar = '$anaUuid~urun-besi-yemi'"), 1);
      expect(await say(db, 'senk_gunluk', "tablo = 'cari_urun_fiyatlari'"), greaterThan(0));
      expect((await db.query('senk_kanallar')).single['son_cekilen'], 0);
      // Kapalı Eylül kilidi yeniden kuruldu (yem ve ürün fiyatı için).
      await expectLater(YemRepository(db).insert(Yem(cariId: a, tarih: '2026-09-20', urunId: urunSutYemi, miktar: 1)),
          throwsA(isA<DonemKapaliHatasi>()));
      await expectLater(UrunFiyatRepository(db).kaydet(cariId: a, urunId: urunSutYemi, ay: '2026-09', fiyat: 99),
          throwsA(isA<DonemKapaliHatasi>()));

      // Dönüşüm iki kez çalışsa da (yarıda kalıp yeniden açılma) hiçbir şey değişmez.
      final once = jsonEncode(await db.query('yemler', orderBy: 'id'));
      await db.transaction((t) async {
        for (final s in ['ekle', 'guncelle', 'sil']) {
          await t.execute('DROP TRIGGER IF EXISTS trg_yemler_donem_$s');
        }
        await eskiYemleriDonustur(t);
        await donemKilitleriniKur(t);
      });
      expect(jsonEncode(await db.query('yemler', orderBy: 'id')), once);
    });

    test('v15 → v16: tek türlü eski satırlarda bakiye KURUŞU KURUŞUNA aynı (ekstre = toplu bakiye = hakediş)', () async {
      final db = await v15Veritabani();
      addTearDown(db.close);
      final a = await cariEkle(db, ad: 'Ali');
      await db.insert('cari_fiyatlar', {'cari_id': a, 'ay': '2026-10', 'sut_fiyat': 18.37, 'sut_yemi_fiyat': 11.11, 'besi_yemi_fiyat': 12.345});
      await db.insert('cari_fiyatlar', {'cari_id': a, 'ay': '2026-10-20', 'sut_fiyat': 18.9, 'sut_yemi_fiyat': 11.11, 'besi_yemi_fiyat': 12.6});
      await db.insert('sutler', {'cari_id': a, 'tarih': '2026-10-05', 'sabah': 33.3, 'aksam': 0, 'toplam': 33.3});
      final eskiTutarlar = <double>[];
      for (final (t, sut, besi) in [('2026-10-03', 33.3, 0.0), ('2026-10-21', 0.0, 7.77), ('2026-10-25', 12.5, 0.0)]) {
        await db.insert('yemler', {'cari_id': a, 'tarih': t, 'sut_yemi': sut, 'besi_yemi': besi, 'toplam': sut + besi});
        final f = t.compareTo('2026-10-20') >= 0 ? (11.11, 12.6) : (11.11, 12.345);
        eskiTutarlar.add(kurusaYuvarla(sut * f.$1 + besi * f.$2)); // eski yemTutari
      }
      await db.insert('cari_odemeler', {'cari_id': a, 'tarih': '2026-10-28', 'islem_turu': 'odeme', 'miktar': 1, 'birim_fiyat': 100, 'toplam_tutar': 100});
      final eskiBakiye = kurusaYuvarla(kurusaYuvarla(33.3 * 18.37) - eskiTutarlar.fold(0.0, (x, y) => x + y) - 100);

      await MigrationRunner().run(db);
      final c = testContainer(db);
      addTearDown(c.dispose);
      expect((await c.read(tumKalanBorclarProvider.future))[a], eskiBakiye);
      expect((await c.read(cariEkstreProvider((cariId: a, baslangic: null, bitis: null)).future)).bakiye, eskiBakiye);
      final h = (await DonemServisi(db).hesapla('2026-10')).single;
      expect(h.donemSonu, eskiBakiye);
      expect(h.yemKg, 33.3 + 7.77 + 12.5);
    });
  });

  // ───────────────────────────── ÜRÜN KURALLARI ─────────────────────────────
  group('ürünler', () {
    late Database db;
    late UrunRepository repo;
    late int ali;
    setUp(() async {
      db = await testVeritabaniAc();
      repo = UrunRepository(db);
      ali = await cariEkle(db);
    });
    tearDown(() => db.close());

    test('ekle: sona eklenir; boş ad, aynı ad (Türkçe İ/ı dahil), uzun ad/birim reddedilir', () async {
      final g = await repo.ekle(ad: '  Gübre  ', birim: 'çuval');
      final u = (await repo.getAll()).last;
      expect((u.id, u.ad, u.birim, u.sira, u.aktif), (g, 'Gübre', 'çuval', 7, true));
      expect(u.uuid, isNotNull, reason: 'eşitleme kimliği tetikleyiciyle verilir');
      for (final (ad, birim) in [('', 'kg'), ('GÜBRE', 'kg'), ('süt yemi', 'kg'), ('SÜT YEMİ', 'kg'), ('x' * 41, 'kg'), ('Saman', ''), ('Saman', 'x' * 13)]) {
        await expectLater(repo.ekle(ad: ad, birim: birim), throwsA(isA<UrunHatasi>()), reason: '"$ad" / "$birim"');
      }
      expect(await say(db, 'urunler'), 7);
    });

    test('kaydı olan ürün: birimi değişmez, silinemez (veritabanı da RESTRICT); pasife alınır, kayıt kalır', () async {
      final g = await repo.ekle(ad: 'Gübre', birim: 'çuval');
      await YemRepository(db).insert(Yem(cariId: ali, tarih: '2026-11-02', urunId: g, miktar: 3));
      await expectLater(repo.guncelle(g, ad: 'Gübre', birim: 'kg'), throwsA(isA<UrunHatasi>()));
      await repo.guncelle(g, ad: 'Amonyum Gübre', birim: 'çuval'); // ad değişebilir
      await expectLater(repo.sil(g), throwsA(isA<UrunHatasi>()));
      expect(() => db.delete('urunler', where: 'id = ?', whereArgs: [g]), throwsA(isA<DatabaseException>()));
      await repo.aktiflikDegistir(g, false);
      expect((await repo.getAll(sadeceAktif: true)).map((u) => u.id), isNot(contains(g)));
      expect(await say(db, 'yemler'), 1);
      expect(await repo.kayitSayilari(), {g: 1});
    });

    test('kaydı olmayan ürün silinir, fiyatları da gider; sıralama kaydedilir', () async {
      final g = await repo.ekle(ad: 'Saman', birim: 'balya');
      await UrunFiyatRepository(db).kaydet(cariId: ali, urunId: g, ay: '2026-11', fiyat: 150);
      await repo.sil(g);
      expect(await say(db, 'urunler'), 6);
      expect(await say(db, 'cari_urun_fiyatlari'), 0);
      await repo.siraKaydet([6, 5, 4, 3, 2, 1]);
      expect((await repo.getAll()).map((u) => u.id), [6, 5, 4, 3, 2, 1]);
    });

    test('yem: 0 / negatif / aşırı miktar ya da ürünsüz satır yazılmaz; toplu ekleme ya hep ya hiç', () async {
      final r = YemRepository(db);
      for (final m in [0.0, -1.0, double.nan, 100001.0]) {
        await expectLater(r.insert(Yem(cariId: ali, tarih: '2026-11-02', urunId: 1, miktar: m)), throwsA(isA<ArgumentError>()));
      }
      await expectLater(r.insert(Yem(cariId: ali, tarih: '2026-11-02', urunId: 0, miktar: 1)), throwsA(isA<ArgumentError>()));
      // İkinci kalemin ürünü yok (FK) → ilk kalem de yazılmaz.
      await expectLater(
          r.topluEkle([
            Yem(cariId: ali, tarih: '2026-11-02', urunId: 1, miktar: 5),
            Yem(cariId: ali, tarih: '2026-11-02', urunId: 999, miktar: 5),
          ]),
          throwsA(anything));
      expect(await say(db, 'yemler'), 0);
      final idler = await r.topluEkle([
        Yem(cariId: ali, tarih: '2026-11-02', urunId: 1, miktar: 5),
        Yem(cariId: ali, tarih: '2026-11-02', urunId: 2, miktar: 2.5),
      ]);
      expect(idler.length, 2);
    });
  });

  // ───────────────────────────── FİYAT ─────────────────────────────
  group('ürün fiyatları', () {
    late Database db;
    late UrunFiyatRepository repo;
    late int ali, veli;
    setUp(() async {
      db = await testVeritabaniAc();
      repo = UrunFiyatRepository(db);
      ali = await cariEkle(db);
      veli = await cariEkle(db, ad: 'Veli');
    });
    tearDown(() => db.close());

    test('devralınan fiyat değişmeden kaydedilirse satır yazılmaz; değişen yazılır; ayın satırı güncellenir', () async {
      await repo.kaydet(cariId: ali, urunId: 1, ay: '2026-10', fiyat: 10);
      await repo.ayFiyatlariniKaydet('2026-11', [
        (cariId: ali, urunId: 1, fiyat: 10), // devralınan = aynı → satır yok
        (cariId: veli, urunId: 1, fiyat: 0), // hiç fiyat yok, 0 → satır yok
        (cariId: ali, urunId: 2, fiyat: 12.5),
      ]);
      expect(await say(db, 'cari_urun_fiyatlari'), 2);
      await repo.kaydet(cariId: ali, urunId: 2, ay: '2026-11', fiyat: 13);
      expect(await say(db, 'cari_urun_fiyatlari'), 2);
      final l = await repo.lookup();
      expect(l.fiyat(ali, 1, '2026-12-31'), 10, reason: 'sonraki aylara devreder');
      expect(l.fiyat(ali, 2, '2026-11-01'), 13);
      expect(l.fiyat(ali, 2, '2026-10-31'), 0);
      expect(await repo.ayBasiFiyatlari([ali, veli], '2026-12'), {ali: {1: 10.0, 2: 13.0}, veli: {}});
    });

    test('negatif / aşırı fiyat ve bozuk ay reddedilir; kapalı ay kilitli', () async {
      await expectLater(repo.kaydet(cariId: ali, urunId: 1, ay: '2026-11', fiyat: -1), throwsA(isA<UrunHatasi>()));
      await expectLater(repo.kaydet(cariId: ali, urunId: 1, ay: '2026-11', fiyat: 2e6), throwsA(isA<UrunHatasi>()));
      await expectLater(repo.kaydet(cariId: ali, urunId: 1, ay: '2026-13', fiyat: 1), throwsA(isA<UrunHatasi>()));
      await db.insert('sutler', {'cari_id': ali, 'tarih': '2026-10-05', 'sabah': 1, 'aksam': 0, 'toplam': 1});
      await fiyatTanimla(db, ali, '2026-10', sut: 20);
      await DonemServisi(db).kapat('2026-10', simdi: DateTime(2026, 11, 4));
      await expectLater(repo.kaydet(cariId: ali, urunId: 1, ay: '2026-10', fiyat: 5), throwsA(isA<DonemKapaliHatasi>()));
      expect(await say(db, 'cari_urun_fiyatlari'), 0);
    });

    test('dönem kapanışı devralınan ürün fiyatını o aya sabitler', () async {
      await fiyatTanimla(db, ali, '2026-09', sut: 20);
      await repo.kaydet(cariId: ali, urunId: 1, ay: '2026-09', fiyat: 10);
      await yemSatiriEkle(db, ali, '2026-10-05', 5);
      await DonemServisi(db).kapat('2026-10', simdi: DateTime(2026, 11, 4));
      final ekim = await db.query('cari_urun_fiyatlari', where: "ay = '2026-10'");
      expect(ekim.map((r) => (r['urun_id'], r['fiyat'])), [(1, 10.0)]);
    });
  });

  // ───────────────────────────── HESAP (gübre çuvalla) ─────────────────────────────
  group('hesap: kg olmayan ürün', () {
    late Database db;
    late ProviderContainer c;
    late int ali, gubre;
    setUp(() async {
      db = await testVeritabaniAc();
      c = testContainer(db);
      ali = await cariEkle(db);
      gubre = await UrunRepository(db).ekle(ad: 'Gübre', birim: 'çuval');
      await fiyatTanimla(db, ali, '2026-11', sut: 20, sutYemi: 12);
      await urunFiyatiTanimla(db, ali, gubre, '2026-11', 450.5);
      await db.insert('sutler', {'cari_id': ali, 'tarih': '2026-11-02', 'sabah': 100, 'aksam': 0, 'toplam': 100});
      await YemRepository(db).topluEkle([
        Yem(cariId: ali, tarih: '2026-11-03', urunId: urunSutYemi, miktar: 25),
        Yem(cariId: ali, tarih: '2026-11-03', urunId: gubre, miktar: 3),
      ]);
    });
    tearDown(() async {
      c.dispose();
      await db.close();
    });

    test('tutar her yerde aynı; çuval kg toplamına girmez', () async {
      const yemTutar = 25 * 12 + 3 * 450.5; // 1651,5
      const bakiye = 2000 - yemTutar;
      expect((await c.read(tumKalanBorclarProvider.future))[ali], bakiye);
      final e = await c.read(cariEkstreProvider((cariId: ali, baslangic: null, bitis: null)).future);
      expect((e.bakiye, e.toplamYem, e.toplamYemKg), (bakiye, yemTutar, 25.0));
      expect(e.hareketler.where((h) => h.tur == 'yem').map((h) => h.aciklama),
          containsAll(['Süt Yemi 25 kg × 12.00 ₺', 'Gübre 3 çuval × 450.50 ₺']));
      final o = (await c.read(aylikOzetProvider('2026-11').future))[ali]!;
      expect((o.yemKg, o.yemTutar, o.genelBakiye), (25.0, yemTutar, bakiye));
      final h = (await DonemServisi(db).hesapla('2026-11')).single;
      expect((h.yemKg, h.yemTutar, h.donemSonu), (25.0, yemTutar, bakiye));

      final rapor = RaporServisi(
        cariRepo: await c.read(cariRepositoryProvider.future),
        sutRepo: await c.read(sutRepositoryProvider.future),
        yemRepo: await c.read(yemRepositoryProvider.future),
        fiyatRepo: await c.read(cariFiyatRepositoryProvider.future),
        odemeRepo: await c.read(cariOdemeRepositoryProvider.future),
        urunRepo: await c.read(urunRepositoryProvider.future),
        urunFiyatRepo: await c.read(urunFiyatRepositoryProvider.future),
      );
      const f = RaporFiltresi(bas: '2026-11-01', bit: '2026-11-30');
      final t = await rapor.olustur(RaporTuru.yemTuruBazli, f);
      expect(t.satirlar, [
        ['Süt Yemi', 'kg', 25.0, 12.0, 300.0],
        ['Gübre', 'çuval', 3.0, 450.5, 1351.5],
      ]);
      final teslim = await rapor.olustur(RaporTuru.yemTeslimleri, f);
      expect(teslim.toplamlar[teslim.sutunlar.indexWhere((s) => s.ad == 'Tutar')], yemTutar);
      final cy = await rapor.olustur(RaporTuru.cariYemToplami, f);
      expect(cy.satirlar.single.sublist(1), [2, 25.0, yemTutar]);
    });

    test('fiyatı girilmemiş ürün "fiyat eksik" sayılır', () async {
      final saman = await UrunRepository(db).ekle(ad: 'Saman', birim: 'balya');
      await YemRepository(db).insert(Yem(cariId: ali, tarih: '2026-11-04', urunId: saman, miktar: 2));
      final e = await c.read(cariEkstreProvider((cariId: ali, baslangic: null, bitis: null)).future);
      expect(e.herhangiFiyatEksikMi, isTrue);
      expect((await DonemServisi(db).hesapla('2026-11')).single.fiyatEksik, isTrue);
    });
  });

  // ───────────────────────────── YEDEK ─────────────────────────────
  group('yedek', () {
    test('yeni biçim (v5): ürünler, ürün fiyatları, yem satırları aynen geri gelir', () async {
      final a = await testVeritabaniAc();
      addTearDown(a.close);
      final ali = await cariEkle(a);
      final g = await UrunRepository(a).ekle(ad: 'Gübre', birim: 'çuval');
      await urunFiyatiTanimla(a, ali, g, '2026-11', 450);
      await yemSatiriEkle(a, ali, '2026-11-03', 3, urunId: g);
      final json = YedekServisi.coz(await YedekServisi.disaAktarJson(a));
      expect(json['meta']['format_version'], 5);

      final b = await testVeritabaniAc();
      addTearDown(b.close);
      await YedekServisi.iceAktar(b, json, tamamenDegistir: true);
      expect((await UrunRepository(b).getAll()).last.ad, 'Gübre');
      final cb = testContainer(b);
      addTearDown(cb.dispose);
      expect((await cb.read(tumKalanBorclarProvider.future))[ali], -1350.0);
    });

    test('ESKİ biçim (v4) yedek: 6 sütunlu yem ve cari_fiyatlar yem fiyatları çevrilir; iki kez birleştirmek çift yapmaz', () async {
      final db = await testVeritabaniAc();
      addTearDown(db.close);
      final eski = {
        'meta': {'app': 'sut_yem', 'format_version': 4},
        'cariler': [
          {'id': 1, 'ad': 'Ali', 'soyad': 'Kaya', 'uuid': 'cari-ali'},
        ],
        'cari_fiyatlar': [
          {'id': 1, 'cari_id': 1, 'ay': '2026-10', 'sut_fiyat': 20, 'sut_yemi_fiyat': 10, 'besi_yemi_fiyat': 12, 'kuzu_yemi_fiyat': 0},
          {'id': 2, 'cari_id': 1, 'ay': '2026-11', 'sut_fiyat': 21, 'sut_yemi_fiyat': 11, 'besi_yemi_fiyat': 12},
        ],
        'fiyatlar': [],
        'sutler': [
          {'id': 1, 'cari_id': 1, 'tarih': '2026-10-05', 'sabah': 100, 'aksam': 0, 'toplam': 100},
        ],
        'yemler': [
          {'id': 1, 'cari_id': 1, 'tarih': '2026-10-06', 'sut_yemi': 5, 'besi_yemi': 2, 'toplam': 7, 'uuid': 'yem-1'},
          {'id': 2, 'cari_id': 1, 'tarih': '2026-11-06', 'sut_yemi': 1, 'toplam': 1, 'uuid': 'yem-2'},
          {'id': 3, 'cari_id': 1, 'tarih': '2026-11-07', 'toplam': 0, 'uuid': 'yem-3'},
        ],
        'cari_odemeler': [],
      };
      // Eski kuralla: 5×10 + 2×12 + 1×11 = 85 → bakiye 2000 − 85.
      const beklenen = 2000.0 - 85;
      await YedekServisi.iceAktar(db, eski, tamamenDegistir: true);
      final c = testContainer(db);
      addTearDown(c.dispose);
      expect((await c.read(tumKalanBorclarProvider.future))[1], beklenen);
      expect(await say(db, 'yemler'), 3, reason: 'boş satır atlanır, iki türlü satır bölünür');
      expect((await db.query('yemler', columns: ['uuid'], orderBy: 'id')).map((r) => r['uuid']),
          ['yem-1', 'yem-2', 'yem-1~urun-besi-yemi']);

      // Aynı eski yedek "birleştir" ile iki kez daha yüklenir: çift satır, çift fiyat yok.
      await YedekServisi.iceAktar(db, eski);
      await YedekServisi.iceAktar(db, eski);
      expect(await say(db, 'yemler'), 3);
      expect(await say(db, 'cari_urun_fiyatlari'), 3); // süt yemi 10→11, besi 12
      c.invalidate(tumKalanBorclarProvider);
      expect((await c.read(tumKalanBorclarProvider.future))[1], beklenen);
    });

    test('başka telefonun yedeği: aynı numaralı farklı ürün birleştirilmez', () async {
      final db = await testVeritabaniAc();
      addTearDown(db.close);
      await UrunRepository(db).ekle(ad: 'Saman', birim: 'balya'); // id 7
      final yedek = YedekServisi.coz(await YedekServisi.disaAktarJson(db));
      (yedek['urunler'] as List).last['uuid'] = 'baska-telefon';
      (yedek['urunler'] as List).last['ad'] = 'Gübre';
      await expectLater(YedekServisi.iceAktar(db, yedek), throwsA(isA<YedekHatasi>()));
      expect((await UrunRepository(db).getAll()).last.ad, 'Saman');
    });
  });

  // ───────────────────────────── ÇOKLU CİHAZ ─────────────────────────────
  group('iki telefon', () {
    Future<Database> tel(String ad) async {
      final db = await testVeritabaniAc();
      await SenkCekirdek.cihazAyarla(db, 'cihaz-$ad');
      return db;
    }

    final gonderilen = <String, int>{};
    Future<void> aktar(Database kimden, String kimdenAd, Database kime, String kimeAd) async {
      final (k, son) = await SenkCekirdek(kimden).gonderilecekler(
          sonra: gonderilen['$kimdenAd>$kimeAd'] ?? 0, haricKaynak: 'kanal:$kimeAd', limit: 100000);
      gonderilen['$kimdenAd>$kimeAd'] = son;
      final s = await kime.transaction((t) => SenkCekirdek(t).uygula(k, kanal: 'kanal:$kimdenAd'));
      expect(s.hatali, 0, reason: (await kime.query('senk_hatalar')).toString());
    }

    test('A ürün + fiyat + yem girer → B aynı ürünü (bir kez), aynı bakiyeyi görür; ilk 6 ürün çift olmaz', () async {
      gonderilen.clear();
      final a = await tel('A'), b = await tel('B');
      addTearDown(a.close);
      addTearDown(b.close);
      final aAli = await cariEkle(a);
      final g = await UrunRepository(a).ekle(ad: 'Gübre', birim: 'çuval');
      await fiyatTanimla(a, aAli, '2026-11', sut: 20, sutYemi: 12);
      await urunFiyatiTanimla(a, aAli, g, '2026-11', 450);
      await YemRepository(a).topluEkle([
        Yem(cariId: aAli, tarih: '2026-11-03', urunId: urunSutYemi, miktar: 10),
        Yem(cariId: aAli, tarih: '2026-11-03', urunId: g, miktar: 2),
      ]);
      for (var i = 0; i < 3; i++) {
        await aktar(a, 'A', b, 'B');
        await aktar(b, 'B', a, 'A');
      }
      expect(await say(b, 'urunler'), 7, reason: 'sabit kimlikli 6 ürün birleşir, Gübre eklenir');
      expect(await say(a, 'urunler'), 7);
      final bAli = (await b.query('cariler')).single['id'] as int;
      final cb = testContainer(b);
      addTearDown(cb.dispose);
      expect((await cb.read(tumKalanBorclarProvider.future))[bAli], -(10 * 12 + 2 * 450.0));
      final bGubre = (await b.query('urunler', where: "ad = 'Gübre'")).single;
      expect(bGubre['birim'], 'çuval');
      expect(await say(b, 'yemler', 'urun_id = ${bGubre['id']}'), 1);

      // B ürünün adını değiştirir → A'ya gelir.
      await UrunRepository(b).guncelle(bGubre['id'] as int, ad: 'Gübre (21)', birim: 'çuval');
      await aktar(b, 'B', a, 'A');
      expect((await a.query('urunler', where: 'id = ?', whereArgs: [g])).single['ad'], 'Gübre (21)');
    });
  });
}
