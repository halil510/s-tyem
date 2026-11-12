// AJAN DENETİMİ — Uygulamanın tüm yazma yolları + yedek/geri yükleme ile
// çoklu cihaz senkronunun entegrasyonu. "BUG:" testleri DOĞRU davranışı bekler
// (hata varken başarısız olur); "KONTROL:" testleri doğrulanan doğru davranıştır.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/core/database/app_database.dart' show senkTabanBayragi;
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
import 'package:sutyem_pro/data/repositories/fiyat_repository.dart';
import 'package:sutyem_pro/data/repositories/sut_repository.dart';
import 'package:sutyem_pro/data/repositories/veri_yonetimi_repository.dart';
import 'package:sutyem_pro/data/repositories/yem_repository.dart';
import 'package:sutyem_pro/data/yedek/yedek_servisi.dart';
import 'package:sutyem_pro/features/cari_hesap/providers/cari_hesap_providers.dart';
import 'package:sutyem_pro/features/donem/donem_servisi.dart';
import 'package:sutyem_pro/models/cari_fiyat_model.dart';
import 'package:sutyem_pro/models/cari_model.dart';
import 'package:sutyem_pro/models/cari_odeme_model.dart';
import 'package:sutyem_pro/models/sut_model.dart';
import 'package:sutyem_pro/models/yem_model.dart';
import 'package:sutyem_pro/senkron/senk_cekirdek.dart';
import 'package:sutyem_pro/senkron/senkron_yoneticisi.dart';

import '../helpers/test_db.dart';

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
  CariFiyatRepository get fiyat => CariFiyatRepository(db);
  Future<Map<int, double>> bakiyeler() async {
    c.invalidate(tumKalanBorclarProvider);
    return c.read(tumKalanBorclarProvider.future);
  }

  /// Cari adı → bakiye (yerel id'ler cihazlar arasında farklı).
  Future<Map<String, double>> adliBakiyeler() async {
    final b = await bakiyeler();
    final cariler = await db.query('cariler');
    return {for (final r in cariler) '${r['ad']}': b[r['id']] ?? 0};
  }

  Future<int> cariId(String ad) async => (await db.query('cariler', where: 'ad = ?', whereArgs: [ad])).single['id'] as int;
  Future<Map<String, Object?>> cariSatiri(String ad) async => (await db.query('cariler', where: 'ad = ?', whereArgs: [ad])).single;
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

Future<UygulamaSonucu> aktar(Cihaz kimden, Cihaz kime) async {
  final (kayitlar, sonId) =
      await SenkCekirdek(kimden.db).gonderilecekler(
          sonra: kimden.gonderilen[kime.ad] ?? 0,
          // Gerçek protokol: yedeğe dönen telefon "tam" ister → karşı taraf yankı önlemesiz gönderir.
          haricKaynak: (await kime.db.query('senk_ayarlar', where: "anahtar = 'tam_yeniden'")).isNotEmpty ? null : 'kanal:${kime.ad}',
          limit: 100000);
  kimden.gonderilen[kime.ad] = sonId;
  final s = await kime.db.transaction((txn) => SenkCekirdek(txn).uygula(kayitlar, kanal: 'kanal:${kimden.ad}'));
  expect(s.hatali, 0, reason: (await kime.db.query('senk_hatalar')).toString());
  return s;
}

Future<void> esitle(Cihaz a, Cihaz b) async {
  for (var i = 0; i < 4; i++) {
    await aktar(a, b);
    await aktar(b, a);
  }
}

Future<int> say(Database db, String tablo) async => (await db.rawQuery('SELECT COUNT(*) AS n FROM $tablo')).first['n'] as int;
Future<void> bekle() => Future<void>.delayed(const Duration(milliseconds: 5));

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
    await fiyatTanimla(a.db, ali, '2026-10', sut: 18, sutYemi: 11);
    await esitle(a, b);
  }

  // ═══════════════════════ MIGRATION v12 → v13 ═══════════════════════

  test('BUG: v12→v13 migration, KAPALI dönemde yem/ödeme kaydı olan veritabanında başarısız olmamalı (uuid yazımı dönem kilidine takılır)', () async {
    final db = await testVeritabaniAc(migrationCalistir: false);
    await MigrationRunner(migrations: [
      MigrationV1Initial(), MigrationV2CariOdemeler(), MigrationV3CariFiyatlar(), MigrationV4Indexler(), //
      MigrationV5TeraziCihazlari(), MigrationV6IslemGecmisi(), MigrationV7CariDurumVade(), MigrationV8SutGunlukTekil(),
      MigrationV9Donemler(), MigrationV10TarihIndeksleri(), MigrationV11GunlukFiyat(), MigrationV12CariSira(),
    ]).run(db);
    // Gerçekçi eski veri: çok cari, pasif cari, NULL alanlar, kapalı Ekim ayı.
    final ali = await db.insert('cariler', {'ad': 'Ali', 'soyad': 'Kaya', 'sira': 1});
    final veli = await db.insert('cariler', {'ad': 'Veli', 'soyad': '', 'telefon': null, 'adres': null, 'aktif': 0});
    for (final c in [ali, veli]) {
      await fiyatTanimla(db, c, '2026-10', sut: 18, sutYemi: 11);
    }
    await db.insert('sutler', {'cari_id': ali, 'tarih': '2026-10-05', 'sabah': 30, 'aksam': 20, 'toplam': 50});
    await db.insert('yemler', {'cari_id': ali, 'tarih': '2026-10-06', 'sut_yemi': 4, 'toplam': 4});
    await db.insert('cari_odemeler',
        {'cari_id': veli, 'tarih': '2026-10-07', 'islem_turu': 'odeme', 'miktar': 1, 'birim_fiyat': 100, 'toplam_tutar': 100});
    await db.insert('donemler', {'ay': '2026-10', 'durum': 'kapali'});

    Object? hata;
    try {
      await MigrationRunner().run(db);
    } catch (e) {
      hata = e;
    }
    expect(hata, isNull, reason: 'kapalı dönemi olan her kullanıcının uygulaması güncellemeden sonra AÇILMAZ');
    expect(await say(db, 'yemler WHERE uuid IS NULL'), 0);
    expect(await say(db, 'cari_odemeler WHERE uuid IS NULL'), 0);
  });

  test('KONTROL: v12→v13 migration kapalı dönem YOKKEN çok cari / pasif / NULL alanla sorunsuz; taban günlük her satırı içerir', () async {
    final db = await testVeritabaniAc(migrationCalistir: false);
    await MigrationRunner(migrations: [
      MigrationV1Initial(), MigrationV2CariOdemeler(), MigrationV3CariFiyatlar(), MigrationV4Indexler(), //
      MigrationV5TeraziCihazlari(), MigrationV6IslemGecmisi(), MigrationV7CariDurumVade(), MigrationV8SutGunlukTekil(),
      MigrationV9Donemler(), MigrationV10TarihIndeksleri(), MigrationV11GunlukFiyat(), MigrationV12CariSira(),
    ]).run(db);
    for (var i = 0; i < 30; i++) {
      final id = await db.insert('cariler', {'ad': 'C$i', 'soyad': i.isEven ? '' : 'S', 'telefon': null, 'aktif': i % 5 == 0 ? 0 : 1});
      await fiyatTanimla(db, id, '2026-11', sut: 20, sutYemi: 10);
      await db.insert('sutler', {'cari_id': id, 'tarih': gun, 'sabah': i + 1.0, 'aksam': null, 'toplam': i + 1.0});
      await db.insert('yemler', {'cari_id': id, 'tarih': gun, 'sut_yemi': 1, 'toplam': 1});
    }
    await MigrationRunner().run(db);
    expect(await say(db, 'cariler WHERE uuid IS NULL'), 0);
    expect(await say(db, "senk_gunluk WHERE tablo = 'sutler'"), 30);
    expect(await say(db, "senk_gunluk WHERE tablo = 'cariler'"), 30);
    final x = Cihaz('X', db);
    addTearDown(x.c.dispose);
    await SenkCekirdek.cihazAyarla(db, 'cihaz-X');
    await esitle(x, b);
    expect(await say(b.db, 'sutler'), 30);
    expect(await say(b.db, 'cariler WHERE aktif = 0'), 6);
    expect((await b.adliBakiyeler()), (await x.adliBakiyeler()));
  });

  // ═══════════════════════ FİYAT EKRANLARI ═══════════════════════

  test('BUG: A süt fiyatını, B (internetsiz) yem fiyatlarını aynı ay için kaydeder → A\'nın süt fiyatı KAYBOLMAMALI', () async {
    await aliHazirla();
    final aAli = await a.cariId('Ali'), bAli = await b.cariId('Ali');
    await a.sut.gunlukKaydet(cariId: aAli, tarih: gun, sabah: 100, aksam: 0);
    await esitle(a, b);
    // A: Süt Fiyatı ekranı — Kasım süt fiyatı 20 → 25 (yem fiyatları ekrandaki mevcutlar).
    final aMevcut = (await a.fiyat.getAyFiyatlariHepsi([aAli], '2026-11'))[aAli]!;
    await a.fiyat.topluKaydet([CariFiyat(cariId: aAli, ay: '2026-11', sutFiyat: 25, sutYemiFiyat: aMevcut.sutYemiFiyat)]);
    await bekle();
    // B: Yem Fiyatı ekranı — TÜM cariler yazılır, süt fiyatı B'nin gördüğü (eski) 20.
    final bMevcut = (await b.fiyat.getAyFiyatlariHepsi([bAli], '2026-11'))[bAli]!;
    await b.fiyat.topluKaydet([CariFiyat(cariId: bAli, ay: '2026-11', sutFiyat: bMevcut.sutFiyat, sutYemiFiyat: 13)], yemFiyatiniAyaYay: true);
    await esitle(a, b);
    for (final c in [a, b]) {
      final f = (await c.db.query('cari_fiyatlar', where: "ay = '2026-11'")).single;
      expect([f['sut_fiyat'], f['sut_yemi_fiyat']], [25.0, 13.0], reason: '${c.ad}: iki ekranın değişikliği de korunmalı');
    }
    expect((await a.bakiyeler())[aAli], 100 * 25.0);
  });

  // ═══════════════════════ CARİ / ROTA ═══════════════════════

  test('BUG: B Veli\'yi pasife alır; sonra A rotaya yeni cari ekler (sıra kaydırır) → Veli PASİF kalmalı', () async {
    await aliHazirla();
    await a.cari.insert(Cari(ad: 'Veli', soyad: 'X'), sira: 1);
    await esitle(a, b);
    await b.cari.pasifeAl(await b.cariId('Veli')); // B internetsiz
    await bekle();
    await a.cari.insert(Cari(ad: 'Can', soyad: 'Y'), sira: 1); // A: Veli'nin sırası 1→2 kayar
    await esitle(a, b);
    for (final c in [a, b]) {
      final v = await c.cariSatiri('Veli');
      expect(v['aktif'], 0, reason: '${c.ad}: pasife alınan cari, başka telefonda yapılan sıra kaydırmasıyla geri AKTİF oldu');
    }
  });

  test('BUG: B Ali\'nin telefonunu düzeltir; A Toplama Sırası ekranında rotayı kaydeder → telefon düzeltmesi KAYBOLMAMALI', () async {
    await aliHazirla();
    await a.cari.insert(Cari(ad: 'Veli', soyad: 'X'), sira: 1);
    await esitle(a, b);
    final bAliMap = await b.cariSatiri('Ali');
    await b.cari.update(Cari.fromMap(bAliMap)..telefon = '05551112233');
    await bekle();
    await a.cari.rotaKaydet([await a.cariId('Veli'), await a.cariId('Ali')]);
    await esitle(a, b);
    for (final c in [a, b]) {
      final ali = await c.cariSatiri('Ali');
      expect(ali['telefon'], '05551112233', reason: '${c.ad}: sıra kaydı TÜM carileri yeniden yazıyor, eşzamanlı düzenleme eziliyor');
    }
    expect((await a.db.rawQuery('SELECT ad FROM cariler ORDER BY sira')).map((r) => r['ad']).toList(),
        (await b.db.rawQuery('SELECT ad FROM cariler ORDER BY sira')).map((r) => r['ad']).toList());
  });

  // ═══════════════════════ SÜT ═══════════════════════

  test('BUG: A günün süt kaydını SİLER, B (internetsiz) sonra akşamı ekler → silinen sabah geri DİRİLMEMELİ', () async {
    await aliHazirla();
    final aAli = await a.cariId('Ali'), bAli = await b.cariId('Ali');
    await a.sut.gunlukKaydet(cariId: aAli, tarih: gun, sabah: 40, aksam: 0);
    await esitle(a, b);
    await bekle();
    final aSatir = (await a.sutSatiri('Ali', gun))!;
    await a.sut.delete(aSatir['id'] as int); // Detay → Sil (yanlış girilmiş sabah)
    await bekle();
    await b.sut.gunlukKaydet(cariId: bAli, tarih: gun, sabah: 40, aksam: 35, kayitliOgunuKoru: true); // B akşamı ekler
    await esitle(a, b);
    for (final c in [a, b]) {
      final s = (await c.sutSatiri('Ali', gun))!;
      expect([s['sabah'], s['aksam']], [0.0, 35.0], reason: '${c.ad}: A\'nın sildiği 40 kg sabah geri geldi (+800 TL)');
    }
  });

  test('KONTROL: Detay → Düzenle ile sabahı 0 yapma (silme değil) + B akşam ekleme doğru birleşir', () async {
    await aliHazirla();
    final aAli = await a.cariId('Ali'), bAli = await b.cariId('Ali');
    await a.sut.gunlukKaydet(cariId: aAli, tarih: gun, sabah: 40, aksam: 0);
    await esitle(a, b);
    await bekle();
    final aSatir = (await a.sutSatiri('Ali', gun))!;
    await a.sut.update(Sut(id: aSatir['id'] as int, cariId: aAli, tarih: gun, sabah: 0.5, aksam: 0));
    await bekle();
    await b.sut.gunlukKaydet(cariId: bAli, tarih: gun, sabah: 40, aksam: 35, kayitliOgunuKoru: true);
    await esitle(a, b);
    for (final c in [a, b]) {
      final s = (await c.sutSatiri('Ali', gun))!;
      expect([s['sabah'], s['aksam'], s['toplam']], [0.5, 35.0, 35.5], reason: c.ad);
    }
  });

  test('KONTROL: Hızlı Süt Girişi (topluGunlukKaydet, kayitliOgunuKoru) iki cihazda farklı öğün → birleşme sonrası kilit iki cihazda da çalışır', () async {
    await aliHazirla();
    await a.cari.insert(Cari(ad: 'Veli', soyad: 'X'));
    await esitle(a, b);
    await a.sut.topluGunlukKaydet(gun, [
      GunlukSutGirdisi(cariId: await a.cariId('Ali'), sabah: 40, aksam: 0),
      GunlukSutGirdisi(cariId: await a.cariId('Veli'), sabah: 10, aksam: 0),
    ], kayitliOgunuKoru: true);
    await bekle();
    await b.sut.topluGunlukKaydet(gun, [
      GunlukSutGirdisi(cariId: await b.cariId('Ali'), sabah: 0, aksam: 30),
      GunlukSutGirdisi(cariId: await b.cariId('Veli'), sabah: 0, aksam: 12),
    ], kayitliOgunuKoru: true);
    await esitle(a, b);
    for (final c in [a, b]) {
      expect((await c.sutSatiri('Ali', gun))!['toplam'], 70.0, reason: c.ad);
      expect((await c.sutSatiri('Veli', gun))!['toplam'], 22.0, reason: c.ad);
      // Kayıtlı sabah artık değiştirilemez (öğün kilidi, birleşmiş veride).
      await expectLater(c.sut.gunlukKaydet(cariId: await c.cariId('Ali'), tarih: gun, sabah: 41, aksam: 30, kayitliOgunuKoru: true),
          throwsA(isA<KayitliOgunHatasi>()), reason: c.ad);
      await expectLater(c.sut.gunlukKaydet(cariId: await c.cariId('Ali'), tarih: gun, sabah: 40, aksam: 31, kayitliOgunuKoru: true),
          throwsA(isA<KayitliOgunHatasi>()), reason: c.ad);
    }
    expect(await a.adliBakiyeler(), await b.adliBakiyeler());
  });

  // ═══════════════════════ TÜM YAZMA YOLLARI ═══════════════════════

  test('KONTROL: tüm yazma yolları (cari ekle/Excel/düzenle/sıra, yem/ödeme ekle-düzenle-sil, süt düzenle, fiyat, dönem kapat/aç, cari sil) karşıya geçer; bakiyeler kuruşu kuruşuna aynı', () async {
    await aliHazirla();
    // Excel'den toplu cari.
    await a.cari.topluEkle([Cari(ad: 'Ex1', soyad: 'E'), Cari(ad: 'Ex2', soyad: 'E', telefon: '1')]);
    await b.cari.insert(Cari(ad: 'Bcari', soyad: 'B'), sira: 1);
    await esitle(a, b);
    expect(await say(a.db, 'cariler'), 4);
    expect(await say(b.db, 'cariler'), 4);
    for (final ad in ['Ex1', 'Ex2', 'Bcari']) {
      await a.fiyat.kaydet(CariFiyat(cariId: await a.cariId(ad), ay: '2026-11', sutFiyat: 19.75, sutYemiFiyat: 11.5));
      await a.fiyat.kaydet(CariFiyat(cariId: await a.cariId(ad), ay: '2026-10', sutFiyat: 17.3, sutYemiFiyat: 10));
    }
    final aAli = await a.cariId('Ali');
    // Ay ortası fiyat değişikliği (gün anahtarlı satır) — B'de girilir.
    await b.fiyat.topluKaydet([CariFiyat(cariId: await b.cariId('Ali'), ay: '2026-11-15', sutFiyat: 21.35, sutYemiFiyat: 12)]);
    await a.sut.gunlukKaydet(cariId: aAli, tarih: gun, sabah: 33.3, aksam: 21.7);
    await a.sut.gunlukKaydet(cariId: aAli, tarih: '2026-11-20', sabah: 12.35, aksam: 0);
    await b.sut.gunlukKaydet(cariId: await b.cariId('Ex1'), tarih: '2026-10-03', sabah: 9.9, aksam: 9.9);
    final yemId = await a.yem.insert(Yem(cariId: aAli, tarih: gun, sutYemi: 3.5, besiYemi: 2));
    final odemeId = await b.odeme.insert(CariOdeme(cariId: await b.cariId('Ex2'), tarih: gun, islemTuru: 'odeme', miktar: 1, birimFiyat: 333.33, toplamTutar: 333.33));
    await a.odeme.insert(CariOdeme(cariId: aAli, tarih: '2026-10-20', islemTuru: 'tahsilat', miktar: 1, birimFiyat: 50, toplamTutar: 50));
    await esitle(a, b);
    // Düzenlemeler (karşı cihazda).
    final bYem = (await b.db.query('yemler')).single;
    await b.yem.update(Yem.fromMap(bYem)..sutYemi = 4.25);
    final aOdeme = (await a.db.query('cari_odemeler', where: "islem_turu = 'odeme'")).single;
    await a.odeme.update(CariOdeme.fromMap(aOdeme)
      ..toplamTutar = 444.44
      ..birimFiyat = 444.44);
    final bSut = (await b.sutSatiri('Ali', '2026-11-20'))!;
    await b.sut.update(Sut(id: bSut['id'] as int, cariId: bSut['cari_id'] as int, tarih: '2026-11-20', sabah: 12.35, aksam: 7.65));
    final bEx2 = await b.cariSatiri('Ex2');
    await b.cari.update(Cari.fromMap(bEx2)..adres = 'Köy');
    await a.cari.siraAta(await a.cariId('Ali'), 1);
    await esitle(a, b);
    expect(await a.adliBakiyeler(), await b.adliBakiyeler());

    // Dönem kapat (A) → B'de kilitli, hakediş aynı; yeniden aç (B) → A'da açık.
    await DonemServisi(a.db).kapat('2026-10', simdi: DateTime(2026, 11, 12));
    await esitle(a, b);
    expect((await b.db.query('donemler')).single['durum'], 'kapali');
    expect(await say(b.db, 'donem_hakedisleri'), await say(a.db, 'donem_hakedisleri'));
    await DonemServisi(b.db).yenidenAc('2026-10', 'yanlış fiyat');
    await esitle(a, b);
    expect((await a.db.query('donemler')).single['durum'], 'acik');
    expect(await say(a.db, 'donem_hakedisleri'), 0);

    // Silmeler.
    await b.yem.delete((await b.db.query('yemler')).single['id'] as int);
    await a.odeme.delete((await a.db.query('cari_odemeler', where: "islem_turu = 'tahsilat'")).single['id'] as int);
    await esitle(a, b);
    expect(await say(b.db, 'yemler'), 0);
    expect(await say(b.db, 'cari_odemeler'), 1);
    expect(yemId, isPositive);
    expect(odemeId, isPositive);
    await b.cari.delete(await b.cariId('Ex2'));
    await esitle(a, b);
    for (final c in [a, b]) {
      expect(await say(c.db, 'cariler'), 3, reason: c.ad);
      expect(await say(c.db, 'cari_odemeler'), 0, reason: c.ad);
    }
    final ba = await a.adliBakiyeler(), bb = await b.adliBakiyeler();
    expect(ba, bb);
    for (final t in ['cariler', 'cari_fiyatlar', 'sutler', 'yemler', 'cari_odemeler', 'donemler', 'donem_hakedisleri']) {
      expect(await say(b.db, t), await say(a.db, t), reason: t);
    }
    // Sıra numaraları iki cihazda aynı, 1..N boşluksuz.
    Future<List<Object?>> siralar(Cihaz c) async =>
        (await c.db.rawQuery("SELECT ad || ':' || sira AS s FROM cariler WHERE sira IS NOT NULL ORDER BY sira")).map((r) => r['s']).toList();
    expect(await siralar(a), await siralar(b));
  });

  test('KONTROL: Veri Yönetimi "süt ve yem sil" diğer cihazdan da siler; B\'de SONRADAN girilen kayıt kalır', () async {
    await aliHazirla();
    final aAli = await a.cariId('Ali');
    await a.sut.gunlukKaydet(cariId: aAli, tarih: gun, sabah: 10, aksam: 0);
    await a.yem.insert(Yem(cariId: aAli, tarih: gun, sutYemi: 1));
    await esitle(a, b);
    await VeriYonetimiRepository(a.db).sutVeYemSil();
    await bekle();
    await b.yem.insert(Yem(cariId: await b.cariId('Ali'), tarih: gun, sutYemi: 2));
    await esitle(a, b);
    for (final c in [a, b]) {
      expect(await say(c.db, 'sutler'), 0, reason: c.ad);
      expect(await say(c.db, 'yemler'), 1, reason: c.ad);
    }
  });

  // ═══════════════════════ YEDEK / GERİ YÜKLEME ═══════════════════════

  test('KONTROL: JSON yedek uuid ve öğün zamanlarını taşır; boş telefona tamamen yüklenip eşitlenince ÇOĞALMA olmaz', () async {
    await aliHazirla();
    final aAli = await a.cariId('Ali');
    await a.sut.gunlukKaydet(cariId: aAli, tarih: gun, sabah: 40, aksam: 30);
    await a.yem.insert(Yem(cariId: aAli, tarih: gun, sutYemi: 5));
    final json = YedekServisi.coz(await YedekServisi.disaAktarJson(a.db));
    final yedekSut = (json['sutler'] as List).single as Map;
    expect(yedekSut['sabah_zaman'], isNotNull);
    expect(((json['yemler'] as List).single as Map)['uuid'], isNotNull);
    final c = await cihaz('C');
    addTearDown(c.c.dispose);
    await YedekServisi.iceAktar(c.db, json, tamamenDegistir: true);
    final cSut = (await c.sutSatiri('Ali', gun))!;
    expect(cSut['sabah_zaman'], yedekSut['sabah_zaman']);
    expect(await say(c.db, "senk_gunluk WHERE zaman <> '2000-01-01T00:00:00.000Z'"), 0, reason: 'yükleme günlüğe yerel değişiklik yazmaz');
    await esitle(a, c);
    for (final t in ['cariler', 'cari_fiyatlar', 'sutler', 'yemler']) {
      expect(await say(c.db, t), await say(a.db, t), reason: t);
    }
    expect(await c.adliBakiyeler(), await a.adliBakiyeler());
  });

  test('BUG: A eski JSON yedeğe döner; A\'nın yedekten SONRA yapıp B\'ye gönderdiği düzeltme A\'ya geri gelmeli (iki telefon farklı kalmamalı)', () async {
    await aliHazirla();
    final aAli = await a.cariId('Ali');
    final yemId = await a.yem.insert(Yem(cariId: aAli, tarih: gun, sutYemi: 5));
    await esitle(a, b);
    final json = YedekServisi.coz(await YedekServisi.disaAktarJson(a.db)); // yedek: 5 çuval
    await bekle();
    await a.yem.update(Yem(id: yemId, cariId: aAli, tarih: gun, sutYemi: 10)); // A düzeltir: 10
    await esitle(a, b);
    expect((await b.db.query('yemler')).single['sut_yemi'], 10.0);
    // A, otomatik güvenlik yedeğine / eski yedeğe döner (tamamenDegistir).
    await YedekServisi.iceAktar(a.db, json, tamamenDegistir: true);
    a.gonderilen.clear();
    b.gonderilen.clear();
    await esitle(a, b);
    final aYem = (await a.db.query('yemler')).single['sut_yemi'];
    final bYem = (await b.db.query('yemler')).single['sut_yemi'];
    expect(aYem, bYem, reason: 'A=5, B=10 kalıyor: B, A\'dan aldığı kaydı "yankı" sayıp A\'ya hiç geri göndermiyor');
    expect(await a.adliBakiyeler(), await b.adliBakiyeler());
  });

  test('KONTROL: çoklu cihaz öncesi (uuid\'siz) yedek, LAN rolü "bagli" olan telefona tamamen yüklenmez', () async {
    await aliHazirla();
    final json = YedekServisi.coz(await YedekServisi.disaAktarJson(a.db));
    for (final r in json['cariler'] as List) {
      (r as Map).remove('uuid');
    }
    await a.db.insert('senk_ayarlar', {'anahtar': 'lan_rol', 'deger': 'bagli'});
    await expectLater(YedekServisi.iceAktar(a.db, json, tamamenDegistir: true), throwsA(isA<YedekHatasi>()));
    expect(await say(a.db, 'cariler'), 1);
  });

  test('KONTROL: .db geri yükleme bayrağı → SenkronYoneticisi.baslat günlüğü tabandan kurar, sayaçları sıfırlar, bayrağı siler', () async {
    SharedPreferences.setMockInitialValues({'sutyem_cihaz_id': 'cihaz-A', senkTabanBayragi: true});
    addTearDown(() => SenkronYoneticisi().testSifirla());
    await aliHazirla();
    await a.yem.insert(Yem(cariId: await a.cariId('Ali'), tarih: gun, sutYemi: 1));
    await a.db.insert('senk_kanallar', {'kanal': 'bulut', 'son_gonderilen': 99, 'son_cekilen': 77});
    await SenkronYoneticisi().testSifirla();
    SenkronYoneticisi.testCihaz = null;
    await SenkronYoneticisi().baslat(a.db);
    expect(await say(a.db, "senk_gunluk WHERE zaman <> '2000-01-01T00:00:00.000Z'"), 0);
    expect(await say(a.db, 'senk_kanallar WHERE son_gonderilen = 0 AND son_cekilen = 0'), 1);
    expect((await SharedPreferences.getInstance()).getBool(senkTabanBayragi), isNull);
    await SenkronYoneticisi().testSifirla();
  });
}
