import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/core/database/migrations/migration_runner.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v10_tarih_indeksleri.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v11_gunluk_fiyat.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v12_cari_sira.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v1_initial.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v2_cari_odemeler.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v3_cari_fiyatlar.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v4_indexler.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v5_terazi_cihazlari.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v6_islem_gecmisi.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v7_cari_durum_vade.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v8_sut_gunluk_tekil.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v9_donemler.dart';
import 'package:sutyem_pro/data/repositories/cari_odeme_repository.dart';
import 'package:sutyem_pro/data/repositories/cari_repository.dart';
import 'package:sutyem_pro/data/repositories/sut_repository.dart';
import 'package:sutyem_pro/data/repositories/yem_repository.dart';
import 'package:sutyem_pro/data/yedek/yedek_servisi.dart';
import 'package:sutyem_pro/features/cari_hesap/providers/cari_hesap_providers.dart';
import 'package:sutyem_pro/features/donem/donem_servisi.dart';
import 'package:sutyem_pro/models/cari_model.dart';
import 'package:sutyem_pro/models/cari_odeme_model.dart';
import 'package:sutyem_pro/models/sut_model.dart';
import 'package:sutyem_pro/models/yem_model.dart';
import 'package:sutyem_pro/senkron/senk_cekirdek.dart';

import '../helpers/test_db.dart';

/// İki (ya da üç) telefon bellekte; aralarındaki "kanal" doğrudan paket alışverişi.
/// Bulut ve yerel ağ AYNI çekirdeği kullandığından bu testler ikisini de kapsar.
class Cihaz {
  final String ad;
  final Database db;
  final Map<String, int> gonderilen = {};
  late final ProviderContainer c = testContainer(db);
  Cihaz(this.ad, this.db);
  SutRepository get sut => SutRepository(db);
  YemRepository get yem => YemRepository(db);
  CariRepository get cari => CariRepository(db);
  CariOdemeRepository get odeme => CariOdemeRepository(db);
  Future<Map<int, double>> bakiyeler() async {
    c.invalidate(tumKalanBorclarProvider);
    return c.read(tumKalanBorclarProvider.future);
  }

  Future<int> cariId(String ad) async => (await db.query('cariler', where: 'ad = ?', whereArgs: [ad])).single['id'] as int;
  Future<Map<String, Object?>?> sutSatiri(String cariAd, String tarih) async {
    final r = await db.rawQuery('SELECT s.* FROM sutler s JOIN cariler c ON c.id = s.cari_id WHERE c.ad = ? AND s.tarih = ?', [cariAd, tarih]);
    return r.isEmpty ? null : r.single;
  }
}

Future<Cihaz> cihaz(String ad) async {
  final db = await testVeritabaniAc();
  await SenkCekirdek.cihazAyarla(db, 'cihaz-$ad');
  return Cihaz(ad, db);
}

/// [kimden]'in [kime]ye henüz göndermediklerini gönderir (yankısız).
Future<UygulamaSonucu> aktar(Cihaz kimden, Cihaz kime) async {
  final (kayitlar, sonId) =
      await SenkCekirdek(kimden.db).gonderilecekler(sonra: kimden.gonderilen[kime.ad] ?? 0, haricKaynak: 'kanal:${kime.ad}', limit: 100000);
  kimden.gonderilen[kime.ad] = sonId;
  final s = await kime.db.transaction((txn) => SenkCekirdek(txn).uygula(kayitlar, kanal: 'kanal:${kimden.ad}'));
  expect(s.hatali, 0, reason: (await kime.db.query('senk_hatalar')).toString());
  return s;
}

/// Durgunluğa kadar iki yönlü eşitleme.
Future<void> esitle(Cihaz a, Cihaz b) async {
  for (var i = 0; i < 4; i++) {
    await aktar(a, b);
    await aktar(b, a);
  }
}

Future<int> say(Database db, String tablo) async => (await db.rawQuery('SELECT COUNT(*) AS n FROM $tablo')).first['n'] as int;

const gun = '2026-11-10';

void main() {
  late Cihaz a, b;
  setUp(() async {
    a = await cihaz('A');
    b = await cihaz('B');
  });
  tearDown(() {
    a.c.dispose();
    b.c.dispose();
  });

  Future<void> aliHazirla() async {
    final ali = await cariEkle(a.db, ad: 'Ali', soyad: 'Kaya');
    await fiyatTanimla(a.db, ali, '2026-11', sut: 20, sutYemi: 12);
    await esitle(a, b);
  }

  test('A\'daki cari, fiyat, süt, yem, ödeme B\'ye geçer; bakiyeler kuruşu kuruşuna aynı; çoğalma yok', () async {
    final ali = await cariEkle(a.db, ad: 'Ali', soyad: 'Kaya');
    await fiyatTanimla(a.db, ali, '2026-11', sut: 20, sutYemi: 12);
    await a.sut.gunlukKaydet(cariId: ali, tarih: gun, sabah: 40, aksam: 35.5);
    await a.yem.insert(Yem(cariId: ali, tarih: gun, sutYemi: 25));
    await a.odeme.insert(CariOdeme(cariId: ali, tarih: gun, islemTuru: 'odeme', miktar: 1, birimFiyat: 500, toplamTutar: 500));

    await esitle(a, b);
    final bAli = await b.cariId('Ali');
    expect((await b.bakiyeler())[bAli], (await a.bakiyeler())[ali]);
    expect((await b.bakiyeler())[bAli], 75.5 * 20 - 25 * 12 - 500);
    for (final t in ['cariler', 'cari_fiyatlar', 'sutler', 'yemler', 'cari_odemeler']) {
      expect(await say(b.db, t), await say(a.db, t), reason: t);
    }
    // Tekrar eşitleme: hiçbir şey değişmez, yankı yok.
    final s = await aktar(a, b);
    expect(s.uygulanan, 0);
    expect(await say(a.db, 'sutler'), 1);
  });

  test('SÜT: A sabahı, B (internetsiz) akşamı girer → iki telefonda da TEK satır, sabah 40 + akşam 35 (biri diğerini silmez)', () async {
    await aliHazirla();
    final aAli = await a.cariId('Ali'), bAli = await b.cariId('Ali');
    await a.sut.gunlukKaydet(cariId: aAli, tarih: gun, sabah: 40, aksam: 0);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await b.sut.gunlukKaydet(cariId: bAli, tarih: gun, sabah: 0, aksam: 35);

    await esitle(a, b);
    for (final c in [a, b]) {
      final s = (await c.sutSatiri('Ali', gun))!;
      expect([s['sabah'], s['aksam'], s['toplam']], [40.0, 35.0, 75.0], reason: c.ad);
      expect(await say(c.db, 'sutler'), 1, reason: c.ad);
    }
    expect((await a.bakiyeler())[aAli], 75 * 20.0);
    expect((await b.bakiyeler())[bAli], 75 * 20.0);
  });

  test('SÜT: ters sıra da aynı sonuç (önce B gönderir) — üç telefonda da birleşir', () async {
    final c = await cihaz('C');
    addTearDown(c.c.dispose);
    await aliHazirla();
    await esitle(a, c);
    await b.sut.gunlukKaydet(cariId: await b.cariId('Ali'), tarih: gun, sabah: 0, aksam: 35);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await a.sut.gunlukKaydet(cariId: await a.cariId('Ali'), tarih: gun, sabah: 40, aksam: 0);
    // B → C, sonra A → C, sonra herkes birbiriyle.
    await aktar(b, c);
    await aktar(a, c);
    for (var i = 0; i < 3; i++) {
      await esitle(a, b);
      await esitle(b, c);
      await esitle(a, c);
    }
    for (final x in [a, b, c]) {
      final s = (await x.sutSatiri('Ali', gun))!;
      expect([s['sabah'], s['aksam']], [40.0, 35.0], reason: x.ad);
    }
  });

  test('SÜT düzeltmesi (Detay → Düzenle) diğer telefona geçer; 0\'a düzeltme de geçer', () async {
    await aliHazirla();
    final aAli = await a.cariId('Ali');
    await a.sut.gunlukKaydet(cariId: aAli, tarih: gun, sabah: 40, aksam: 35);
    await esitle(a, b);
    final bSatir = (await b.sutSatiri('Ali', gun))!;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await b.sut.update(Sut(id: bSatir['id'] as int, cariId: bSatir['cari_id'] as int, tarih: gun, sabah: 0, aksam: 36));
    await esitle(a, b);
    final s = (await a.sutSatiri('Ali', gun))!;
    expect([s['sabah'], s['aksam'], s['toplam']], [0.0, 36.0, 36.0]);
  });

  test('Silme yayılır: yem silinince ve cari silinince (bağlı kayıtlarıyla) diğer telefondan da gider', () async {
    await aliHazirla();
    final aAli = await a.cariId('Ali');
    final yemId = await a.yem.insert(Yem(cariId: aAli, tarih: gun, besiYemi: 10));
    await a.sut.gunlukKaydet(cariId: aAli, tarih: gun, sabah: 10, aksam: 0);
    await esitle(a, b);
    expect(await say(b.db, 'yemler'), 1);
    await a.yem.delete(yemId);
    await esitle(a, b);
    expect(await say(b.db, 'yemler'), 0);
    await b.cari.delete(await b.cariId('Ali'));
    await esitle(a, b);
    for (final t in ['cariler', 'sutler', 'cari_fiyatlar']) {
      expect(await say(a.db, t), 0, reason: t);
    }
  });

  test('Kapalı dönem: A ayı kapatınca B\'de de kilitli; kapanmadan önce B\'de girilen kayıt kaybolmaz', () async {
    await aliHazirla();
    final bAli = await b.cariId('Ali');
    await b.yem.insert(Yem(cariId: bAli, tarih: '2026-10-15', sutYemi: 5)); // B internetsiz
    await DonemServisi(a.db).kapat('2026-10', simdi: DateTime(2026, 11, 12));
    await esitle(a, b);
    expect((await b.db.query('donemler')).single['durum'], 'kapali');
    expect(await say(a.db, 'yemler'), 1, reason: 'kapalı aya B\'den gelen kayıt A\'da reddedilip kaybolmamalı');
    expect(await say(b.db, 'donem_hakedisleri'), await say(a.db, 'donem_hakedisleri'));
    // B'de artık o aya yerel yazım yapılamaz.
    await expectLater(b.yem.insert(Yem(cariId: bAli, tarih: '2026-10-20', sutYemi: 1)), throwsA(anything));
  });

  test('Rota: iki telefon aynı anda yeni cari eklerse sıra numaraları çakışmaz (1..N boşluksuz, iki telefonda aynı)', () async {
    await aliHazirla(); // Ali sırasız
    await a.cari.insert(Cari(ad: 'Veli', soyad: 'X'), sira: 1);
    await b.cari.insert(Cari(ad: 'Can', soyad: 'Y'), sira: 1);
    await esitle(a, b);
    Future<List<Object?>> siralar(Cihaz c) async =>
        (await c.db.rawQuery("SELECT ad || ':' || sira AS s FROM cariler WHERE sira IS NOT NULL ORDER BY sira")).map((r) => r['s']).toList();
    expect((await siralar(a)).length, 2);
    expect(await siralar(a), await siralar(b));
    expect((await a.db.rawQuery('SELECT sira FROM cariler WHERE sira IS NOT NULL ORDER BY sira')).map((r) => r['sira']), [1, 2]);
  });

  test('JSON yedekten geri yükleme diğer telefondaki kaydı SİLMEZ; o kayıt geri gelir', () async {
    await aliHazirla();
    final json = YedekServisi.coz(await YedekServisi.disaAktarJson(a.db));
    await b.yem.insert(Yem(cariId: await b.cariId('Ali'), tarih: gun, sutYemi: 7));
    await esitle(a, b);
    expect(await say(a.db, 'yemler'), 1);
    await YedekServisi.iceAktar(a.db, json, tamamenDegistir: true); // A eski yedeğe döner (yem yok)
    expect(await say(a.db, 'yemler'), 0);
    expect(await say(a.db, "senk_gunluk WHERE islem = 's'"), 0, reason: 'geri yükleme silme yaymaz');
    a.gonderilen.clear(); // tabanYenile sayaçları sıfırladı
    b.gonderilen.clear();
    await esitle(a, b);
    expect(await say(b.db, 'yemler'), 1);
    expect(await say(a.db, 'yemler'), 1, reason: 'B\'deki yem A\'ya geri geldi');
  });

  test('Çoklu cihaz öncesi (uuid\'siz) yedek, eşitlenen telefona yüklenmez (cariler ikilenirdi)', () async {
    await aliHazirla();
    final json = YedekServisi.coz(await YedekServisi.disaAktarJson(a.db));
    for (final r in json['cariler'] as List) {
      (r as Map).remove('uuid');
    }
    await a.db.insert('senk_ayarlar', {'anahtar': 'bulut_url', 'deger': 'https://x.supabase.co'});
    await expectLater(YedekServisi.iceAktar(a.db, json, tamamenDegistir: true), throwsA(isA<YedekHatasi>()));
    expect(await say(a.db, 'cariler'), 1, reason: 'hiçbir şey silinmedi');
  });

  test('Taban: çoklu cihazdan ÖNCE girilmiş veri (migration) ilk eşitlemede karşıya gider', () async {
    // v12'ye kadar kur (çoklu cihaz yok), veri gir, sonra v13 uygulanır.
    final db = await testVeritabaniAc(migrationCalistir: false);
    await MigrationRunner(migrations: [
      MigrationV1Initial(), MigrationV2CariOdemeler(), MigrationV3CariFiyatlar(), MigrationV4Indexler(), //
      MigrationV5TeraziCihazlari(), MigrationV6IslemGecmisi(), MigrationV7CariDurumVade(), MigrationV8SutGunlukTekil(),
      MigrationV9Donemler(), MigrationV10TarihIndeksleri(), MigrationV11GunlukFiyat(), MigrationV12CariSira(),
    ]).run(db);
    final ali = await cariEkle(db, ad: 'Ali');
    await fiyatTanimla(db, ali, '2026-11', sut: 20);
    await db.insert('sutler', {'cari_id': ali, 'tarih': gun, 'sabah': 50, 'aksam': 0, 'toplam': 50});
    await db.insert('yemler', {'cari_id': ali, 'tarih': gun, 'sut_yemi': 3, 'toplam': 3});
    expect(await MigrationRunner().run(db), 1, reason: 'yalnız v13');
    expect(await say(db, 'cariler WHERE uuid IS NULL'), 0);
    final x = Cihaz('X', db);
    addTearDown(x.c.dispose);
    await SenkCekirdek.cihazAyarla(db, 'cihaz-X');
    await esitle(x, b);
    expect((await b.sutSatiri('Ali', gun))!['sabah'], 50.0);
    expect(await say(b.db, 'yemler'), 1);
  });
}
