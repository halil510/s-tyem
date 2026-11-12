// AJAN DENETİMİ — Süt veri katmanı ve hesap doğruluğu.
// "DÜZELTİLDİ: ..." testleri DOĞRU davranışı bekler (hata varken başarısız olur).
// "KONTROL: ..." testleri doğrulanmış doğru davranışlardır (geçmeli).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/core/providers/repository_providers.dart';
import 'package:sutyem_pro/data/repositories/sut_repository.dart';
import 'package:sutyem_pro/features/cari_hesap/models/cari_fiyat_lookup.dart';
import 'package:sutyem_pro/features/cari_hesap/models/cari_hareket.dart';
import 'package:sutyem_pro/features/cari_hesap/providers/cari_hesap_providers.dart';
import 'package:sutyem_pro/models/cari_fiyat_model.dart';
import 'package:sutyem_pro/models/sut_model.dart';
import 'package:sutyem_pro/utils/sayi_format.dart';

import '../helpers/test_db.dart';

void main() {
  late Database db;
  late ProviderContainer c;
  late SutRepository repo;
  late int ali, veli;

  setUp(() async {
    db = await testVeritabaniAc();
    c = testContainer(db);
    repo = await c.read(sutRepositoryProvider.future);
    ali = await cariEkle(db, ad: 'Ali');
    veli = await cariEkle(db, ad: 'Veli');
  });

  tearDown(() => c.dispose());

  Future<CariEkstreSonucu> ekstre(int id, [DateTime? bas, DateTime? bit]) =>
      c.read(cariEkstreProvider((cariId: id, baslangic: bas, bitis: bit)).future);

  Future<void> sut(int id, String tarih, double sabah, [double aksam = 0]) =>
      repo.gunlukKaydet(cariId: id, tarih: tarih, sabah: sabah, aksam: aksam);

  // ───────────────────────── Fiyat bulma ─────────────────────────

  test('KONTROL: ay ortası fiyat değişimi — 1-3 Kasım 25, 4 Kasım+ 27, Aralık 27, 31 Ekim eski fiyat', () async {
    await fiyatTanimla(db, ali, '2026-10', sut: 20);
    await fiyatTanimla(db, ali, '2026-11', sut: 25);
    await fiyatTanimla(db, ali, '2026-11-04', sut: 27);
    await sut(ali, '2026-10-31', 10);
    await sut(ali, '2026-11-01', 10);
    await sut(ali, '2026-11-03', 10);
    await sut(ali, '2026-11-04', 10);
    await sut(ali, '2026-11-30', 10);
    await sut(ali, '2026-12-01', 10);
    final e = await ekstre(ali);
    final tutarlar = {for (final h in e.hareketler) h.tarih: h.tutar};
    expect(tutarlar[DateTime(2026, 10, 31)], 200);
    expect(tutarlar[DateTime(2026, 11, 1)], 250);
    expect(tutarlar[DateTime(2026, 11, 3)], 250);
    expect(tutarlar[DateTime(2026, 11, 4)], 270);
    expect(tutarlar[DateTime(2026, 11, 30)], 270);
    expect(tutarlar[DateTime(2026, 12, 1)], 270);
    expect(e.toplamSut, 200 + 250 + 250 + 270 + 270 + 270);
    final ozet = await c.read(aylikOzetProvider('2026-11').future);
    expect(ozet[ali]!.sutTutar, 1040);
    expect(ozet[ali]!.fiyatDegisti, isTrue);
    expect(ozet[ali]!.sutFiyat, 26); // 1040 / 40
  });

  test('KONTROL: lookup karışık anahtarlar — yyyy-MM ve yyyy-MM-dd, ay ile sorgu ay başını verir', () {
    final l = CariFiyatLookup([
      CariFiyat(cariId: 1, ay: '2026-10-20', sutFiyat: 22),
      CariFiyat(cariId: 1, ay: '2026-11', sutFiyat: 25),
      CariFiyat(cariId: 1, ay: '2026-11-04', sutFiyat: 27),
      CariFiyat(cariId: 1, ay: '2026-12-31', sutFiyat: 30),
      CariFiyat(cariId: 1, ay: '2027-01', sutFiyat: 31),
    ]);
    expect(l.fiyatIcin(1, '2026-10-19').sutFiyat, 0);
    expect(l.fiyatIcin(1, '2026-10-20').sutFiyat, 22);
    expect(l.fiyatIcin(1, '2026-10-31').sutFiyat, 22);
    expect(l.fiyatIcin(1, '2026-11').sutFiyat, 25);
    expect(l.fiyatIcin(1, '2026-11-03').sutFiyat, 25);
    expect(l.fiyatIcin(1, '2026-11-04').sutFiyat, 27);
    expect(l.fiyatIcin(1, '2026-12').sutFiyat, 27);
    expect(l.fiyatIcin(1, '2026-12-30').sutFiyat, 27);
    expect(l.fiyatIcin(1, '2026-12-31').sutFiyat, 30);
    expect(l.fiyatIcin(1, '2027-01-01').sutFiyat, 31);
    expect(l.fiyatIcin(2, '2026-11-04').sutFiyat, 0, reason: 'başka carinin fiyatı karışmaz');
    // anahtar(): ayın 1'i her zaman 'yyyy-MM' (aynı aya iki satır oluşmaz)
    expect(CariFiyat.anahtar(DateTime(2026, 11, 1)), '2026-11');
    expect(CariFiyat.anahtar(DateTime(2028, 2, 29)), '2028-02-29');
  });

  test('KONTROL: getAyFiyatlariHepsi (fiyat ekranı) = lookup (ekstre) — gün anahtarlı geçmiş', () async {
    await fiyatTanimla(db, ali, '2026-10-20', sut: 22);
    await fiyatTanimla(db, ali, '2026-11', sut: 25);
    await fiyatTanimla(db, ali, '2026-11-04', sut: 27);
    final fr = await c.read(cariFiyatRepositoryProvider.future);
    final l = CariFiyatLookup(await fr.getTumFiyatlar());
    for (final g in ['2026-10-25', '2026-11', '2026-11-03', '2026-11-04', '2026-11-20', '2026-12']) {
      final ekran = (await fr.getAyFiyatlariHepsi([ali], g))[ali]!;
      expect(ekran.sutFiyat, l.fiyatIcin(ali, g).sutFiyat, reason: g);
    }
  });

  // ───────────────────────── Tarih doğrulama ─────────────────────────

  test('KONTROL: 29 Şubat artık yılda kabul, değil yılda ret; 30 Şubat / 31 Nisan / saatli tarih ret', () async {
    await sut(ali, '2028-02-29', 5);
    expect(await repo.getGunluk(ali, '2028-02-29'), isNotNull);
    for (final t in ['2026-02-29', '2026-02-30', '2026-04-31', '2026-11-04 10:00', '2026-11-04T00:00:00',
        '2026-1-04', '04.11.2026', '']) {
      await expectLater(sut(ali, t, 5), throwsA(isA<SutKayitHatasi>()), reason: t);
    }
    expect((await db.query('sutler')).length, 1);
  });

  test("KONTROL: Şubat ayı özeti ('\$ay-31' aralığı) Mart 1'i almaz, 28/29 Şubat'ı alır; ekstre ay filtresiyle aynı", () async {
    await fiyatTanimla(db, ali, '2028-02', sut: 10);
    await fiyatTanimla(db, ali, '2028-03', sut: 50);
    await sut(ali, '2028-01-31', 1);
    await sut(ali, '2028-02-01', 2);
    await sut(ali, '2028-02-29', 3);
    await sut(ali, '2028-03-01', 4);
    final o = (await c.read(aylikOzetProvider('2028-02').future))[ali]!;
    expect(o.sutKg, 5);
    expect(o.sutTutar, 50);
    final e = await ekstre(ali, DateTime(2028, 2, 1), DateTime(2028, 2, 29));
    expect(e.toplamSutKg, o.sutKg);
    expect(e.toplamSut, o.sutTutar);
    expect(await repo.toplamCari(ali, '2028-02-01', '2028-02-31'), 5);
  });

  // ───────────────────────── Miktar doğrulama ─────────────────────────

  test('KONTROL: negatif / NaN / sonsuz / aşırı kg reddedilir — gunlukKaydet, update ve toplu (ya hep ya hiç)', () async {
    for (final kg in [-1.0, double.nan, double.infinity, double.negativeInfinity, 20000.01]) {
      await expectLater(sut(ali, '2026-11-10', kg), throwsA(isA<SutKayitHatasi>()), reason: '$kg');
      await expectLater(sut(ali, '2026-11-10', 1, kg), throwsA(isA<SutKayitHatasi>()), reason: '$kg');
    }
    await sut(ali, '2026-11-10', 20000); // sınır kabul
    final k = (await repo.getGunluk(ali, '2026-11-10'))!;
    await expectLater(repo.update(Sut(id: k.id, cariId: ali, tarih: k.tarih, sabah: double.nan)),
        throwsA(isA<SutKayitHatasi>()));
    await expectLater(repo.update(Sut(id: k.id, cariId: ali, tarih: k.tarih, sabah: -5)),
        throwsA(isA<SutKayitHatasi>()));
    await expectLater(
      repo.topluGunlukKaydet('2026-11-11', [
        GunlukSutGirdisi(cariId: ali, sabah: 10, aksam: 0),
        GunlukSutGirdisi(cariId: veli, sabah: double.nan, aksam: 0),
      ]),
      throwsA(isA<SutKayitHatasi>()),
    );
    expect(await repo.getGunluk(ali, '2026-11-11'), isNull, reason: 'toplu kayıt yarım yazılmamalı');
    expect((await repo.getGunluk(ali, '2026-11-10'))!.sabah, 20000);
  });

  test('KONTROL: bir cari bir günde tek satır — sabah sonra akşam aynı satıra, toplam güncel', () async {
    await sut(ali, '2026-11-12', 12.345);
    await repo.gunlukKaydet(cariId: ali, tarih: '2026-11-12', sabah: 12.345, aksam: 8.5, kayitliOgunuKoru: true);
    final satirlar = await db.query('sutler', where: 'cari_id = ?', whereArgs: [ali]);
    expect(satirlar.length, 1);
    expect(satirlar.first['toplam'], closeTo(20.845, 1e-9));
    await expectLater(
      repo.gunlukKaydet(cariId: ali, tarih: '2026-11-12', sabah: 12, aksam: 8.5, kayitliOgunuKoru: true),
      throwsA(isA<KayitliOgunHatasi>()),
    );
    // Veli'nin kaydı Ali'ye yazılmaz
    await sut(veli, '2026-11-12', 3);
    expect((await repo.getGunluk(ali, '2026-11-12'))!.toplam, closeTo(20.845, 1e-9));
    expect((await repo.getGunluk(veli, '2026-11-12'))!.toplam, 3);
  });

  // ───────────────────────── Para / ekranlar arası tutarlılık ─────────────────────────

  test('KONTROL: çok satırda kuruş birikimi — ekstre = tumKalanBorclar = aylık özet = satır toplamı', () async {
    await fiyatTanimla(db, ali, '2026-01', sut: 13.37);
    await fiyatTanimla(db, ali, '2026-01-16', sut: 13.41);
    var beklenen = 0.0;
    var kg = 0.0;
    for (var g = 1; g <= 31; g++) {
      final t = '2026-01-${g.toString().padLeft(2, '0')}';
      final s = 12.345 + g / 1000, a = 7.005;
      await sut(ali, t, s, a);
      final f = g < 16 ? 13.37 : 13.41;
      beklenen += kurusaYuvarla((s + a) * f);
      kg += s + a;
    }
    await db.insert('yemler', {'cari_id': ali, 'tarih': '2026-01-05', 'sut_yemi': 0.333, 'toplam': 0.333});
    final n = c.read(cariHesapNotifierProvider.notifier);
    await n.odemeYap(cariId: ali, tutar: 1000.005, tarih: DateTime(2026, 1, 20));
    final e = await ekstre(ali);
    expect(e.toplamSut, kurusaYuvarla(beklenen));
    final satirToplami = e.hareketler.where((h) => h.tur == 'sut').fold(0.0, (t, h) => t + h.tutar);
    expect(kurusaYuvarla(satirToplami), e.toplamSut);
    final bakiyeler = await c.read(tumKalanBorclarProvider.future);
    expect(bakiyeler[ali], e.bakiye);
    final o = (await c.read(aylikOzetProvider('2026-01').future))[ali]!;
    expect(o.sutTutar, e.toplamSut);
    expect(o.genelBakiye, e.bakiye);
    expect(o.ayNet, e.bakiye);
    // kg: SQL SUM ile Dart toplamı ekranda aynı görünür
    final sqlKg = await repo.toplamCari(ali, '2026-01-01', '2026-01-31');
    expect(sayiGoster(sqlKg), sayiGoster(e.toplamSutKg));
    expect(sayiGoster(sqlKg), sayiGoster(kg));
    expect((await repo.toplamByCariInRange('2026-01-01', '2026-01-31'))[ali], closeTo(e.toplamSutKg, 1e-9));
    // ödeme 1000.005 → 1000.01 kuruşa yuvarlanıp yazıldı
    expect(e.toplamOdeme, 1000.01);
  });

  test('KONTROL: bakiye işareti — süt > yem+ödeme → pozitif (cari alacaklı)', () async {
    await fiyatTanimla(db, ali, '2026-11', sut: 20, sutYemi: 10);
    await sut(ali, '2026-11-02', 50); // 1000
    await db.insert('yemler', {'cari_id': ali, 'tarih': '2026-11-03', 'sut_yemi': 30, 'toplam': 30}); // 300
    final n = c.read(cariHesapNotifierProvider.notifier);
    await n.odemeYap(cariId: ali, tutar: 200, tarih: DateTime(2026, 11, 4));
    await n.tahsilatAl(cariId: ali, tutar: 50, tarih: DateTime(2026, 11, 5));
    final e = await ekstre(ali);
    expect(e.bakiye, 550); // (1000 + 50) − (300 + 200)
    expect((await c.read(tumKalanBorclarProvider.future))[ali], 550);
  });

  // ───────────────────────── Sayı girişi ─────────────────────────

  test('KONTROL: sayiCoz — "1.234,5" = 1234,5; "1,234.5" (İngiliz) reddedilir; aşırı uzun sayı null', () {
    expect(sayiCoz('1.234,5'), 1234.5);
    expect(sayiCoz('12,345'), 12.345);
    expect(sayiCoz('1,234.5'), isNull);
    expect(sayiCoz('9' * 400), isNull);
    expect(sayiCoz('1.234.567'), isNull);
    expect(sayiCoz('NaN'), isNull);
    expect(sayiCoz('Infinity'), isNull);
  });

  test('DÜZELTİLDİ: Türkçe binlik "1.500" (ödeme tutarı 1.500 TL) sessizce 1,5 olarak çözülmemeli', () {
    // "1.500.000" belirsiz sayılıp reddediliyor ama "1.500" 1,5 kabul ediliyor:
    // Ödeme Al / Ödeme Yap ekranında 1.500 TL yazan kullanıcıya 1,50 TL kaydedilir.
    expect(sayiCoz('1.500'), anyOf(isNull, 1500.0));
    expect(sayiCoz('12.500'), anyOf(isNull, 12500.0));
  });

  test('DÜZELTİLDİ: ekstre satırındaki "kg × fiyat" açıklaması satır tutarıyla tutmalı (3 ondalıklı kg)', () async {
    await fiyatTanimla(db, ali, '2026-11', sut: 30);
    await sut(ali, '2026-11-02', 12.345); // tutar 370,35
    final e = await ekstre(ali);
    final h = e.hareketler.single;
    expect(h.tutar, 370.35);
    // Açıklamada gösterilen kg × fiyat, gösterilen tutarla aynı olmalı.
    final m = RegExp(r'^([\d.]+) kg × ([\d.]+)').firstMatch(h.aciklama!)!;
    final gosterilenKg = double.parse(m.group(1)!);
    final gosterilenFiyat = double.parse(m.group(2)!);
    expect(kurusaYuvarla(gosterilenKg * gosterilenFiyat), h.tutar,
        reason: 'Ekranda "${h.aciklama}" yazıyor ama tutar ${h.tutar}');
  });
}
