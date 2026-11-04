import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/core/providers/repository_providers.dart';
import 'package:sutyem_pro/core/providers/veri_surumu_provider.dart';
import 'package:sutyem_pro/features/cari_hesap/models/cari_hareket.dart';
import 'package:sutyem_pro/features/cari_hesap/providers/cari_hesap_providers.dart';
import 'package:sutyem_pro/features/dashboard/providers/dashboard_providers.dart';

import 'package:sutyem_pro/utils/tarih_format.dart';

import '../helpers/test_db.dart';

/// Cari hesap (bakiye) hesabının uçtan uca testleri: gerçek SQLite +
/// gerçek Riverpod provider'ları.
///
/// İş kuralı: bakiye = (süt + tahsilat) − (yem + ödeme).
/// Pozitif → işletme cariye BORÇLU (cari alacaklı).
void main() {
  late Database db;
  late ProviderContainer container;
  late int ali;

  setUpAll(initializeTurkishLocale);

  setUp(() async {
    db = await testVeritabaniAc();
    container = testContainer(db);
    ali = await cariEkle(db, ad: 'Ali');
  });

  tearDown(() => container.dispose());

  Future<void> sutGir(int cariId, String tarih, double sabah, [double aksam = 0]) async {
    final repo = await container.read(sutRepositoryProvider.future);
    await repo.gunlukKaydet(cariId: cariId, tarih: tarih, sabah: sabah, aksam: aksam);
  }

  Future<CariEkstreSonucu> ekstre(int cariId, {DateTime? bas, DateTime? bit}) =>
      container.read(cariEkstreProvider((cariId: cariId, baslangic: bas, bitis: bit)).future);

  test('süt × o ayın fiyatı alacak yazar; yem ve ödeme düşer; tahsilat ekler', () async {
    await fiyatTanimla(db, ali, '2026-05', sut: 18.5, sutYemi: 12);
    await sutGir(ali, '2026-05-01', 20, 18); // 38 kg × 18,5 = 703,00
    await sutGir(ali, '2026-05-02', 21.5); // 21,5 × 18,5 = 397,75
    await db.insert('yemler', {'cari_id': ali, 'tarih': '2026-05-03', 'sut_yemi': 25, 'toplam': 25}); // 300
    final notifier = container.read(cariHesapNotifierProvider.notifier);
    await notifier.odemeYap(cariId: ali, tutar: 500, tarih: DateTime(2026, 5, 10));
    await notifier.tahsilatAl(cariId: ali, tutar: 50, tarih: DateTime(2026, 5, 11));

    final e = await ekstre(ali);
    expect(e.toplamSut, 1100.75);
    expect(e.toplamYem, 300);
    expect(e.toplamOdeme, 500);
    expect(e.toplamTahsilat, 50);
    expect(e.bakiye, 350.75); // 1100,75 + 50 − 300 − 500
    expect(e.alacakliMi, isTrue);
    expect(e.toplamSutKg, 59.5);
    expect(e.hareketler, hasLength(5));
    expect(e.herhangiFiyatEksikMi, isFalse);
  });

  test('fiyat girilmeyen ay, önceki ayın fiyatını devralır', () async {
    await fiyatTanimla(db, ali, '2026-03', sut: 15);
    await fiyatTanimla(db, ali, '2026-05', sut: 20);
    await sutGir(ali, '2026-04-15', 10); // Nisan fiyatı yok → Mart: 150
    await sutGir(ali, '2026-05-15', 10); // 200

    expect((await ekstre(ali)).toplamSut, 350);
  });

  test('fiyatı hiç tanımlı olmayan süt "fiyat eksik" uyarısı verir', () async {
    await sutGir(ali, '2026-05-01', 10);
    final e = await ekstre(ali);
    expect(e.toplamSut, 0);
    expect(e.herhangiFiyatEksikMi, isTrue);
    expect(e.hareketler.single.fiyatEksik, isTrue);
  });

  test('tarih filtresi yalnızca o dönemin hareketini verir, ay sonu dahil', () async {
    await fiyatTanimla(db, ali, '2026-04', sut: 10);
    await sutGir(ali, '2026-04-30', 10);
    await sutGir(ali, '2026-05-01', 5);
    await sutGir(ali, '2026-05-31', 7);

    final mayis = await ekstre(ali, bas: DateTime(2026, 5, 1), bit: DateTime(2026, 5, 31));
    expect(mayis.filtreliMi, isTrue);
    expect(mayis.toplamSut, 120);
    expect(mayis.hareketler, hasLength(2));
  });

  test('Ödemeler sekmesi bakiyesi ile ekstre bakiyesi AYNIDIR', () async {
    final veli = await cariEkle(db, ad: 'Veli');
    await fiyatTanimla(db, ali, '2026-05', sut: 18.37, sutYemi: 11.11);
    await fiyatTanimla(db, veli, '2026-05', sut: 19.99);
    for (var gun = 1; gun <= 28; gun++) {
      final t = '2026-05-${gun.toString().padLeft(2, '0')}';
      await sutGir(ali, t, 17.3, 15.9);
      await sutGir(veli, t, 33.33);
    }
    await db.insert('yemler', {'cari_id': ali, 'tarih': '2026-05-20', 'sut_yemi': 33.3, 'toplam': 33.3});
    await container.read(cariHesapNotifierProvider.notifier).odemeYap(cariId: veli, tutar: 1234.56);

    final toplu = await container.read(tumKalanBorclarProvider.future);
    expect(toplu[ali], (await ekstre(ali)).bakiye);
    expect(toplu[veli], (await ekstre(veli)).bakiye);
  });

  test('ekstrede satırların toplamı genel toplamla kuruşu kuruşuna tutar', () async {
    await fiyatTanimla(db, ali, '2026-05', sut: 18.37);
    for (var gun = 1; gun <= 31; gun++) {
      await sutGir(ali, '2026-05-${gun.toString().padLeft(2, '0')}', 17.33, 13.07);
    }
    final e = await ekstre(ali);
    final satirToplami = e.hareketler.fold<int>(0, (t, h) => t + (h.tutar * 100).round());
    expect((e.toplamSut * 100).round(), satirToplami);
  });

  test('REGRESYON: süt girildikten sonra bakiyeler ve dashboard güncellenir', () async {
    await fiyatTanimla(db, ali, '2026-05', sut: 20);
    await sutGir(ali, '2026-05-01', 10);

    // Ödemeler sekmesi ve dashboard bir kez okundu (önbelleğe alındı).
    final sub = container.listen(tumKalanBorclarProvider, (_, __) {});
    final dashSub = container.listen(dashboardDataProvider, (_, __) {});
    expect((await container.read(tumKalanBorclarProvider.future))[ali], 200);
    final onceOdenecek = (await container.read(dashboardDataProvider.future)).odenecekTutar;
    expect(onceOdenecek, 200);

    // Yeni süt girişi + ekranların yaptığı bildirim.
    await sutGir(ali, '2026-05-02', 5);
    container.read(veriSurumuProvider.notifier).state++;

    expect((await container.read(tumKalanBorclarProvider.future))[ali], 300);
    expect((await container.read(dashboardDataProvider.future)).odenecekTutar, 300);
    sub.close();
    dashSub.close();
  });

  test('ödeme/tahsilat silinince bakiye geri döner ve silme denetime yazılır', () async {
    await fiyatTanimla(db, ali, '2026-05', sut: 20);
    await sutGir(ali, '2026-05-01', 10);
    final notifier = container.read(cariHesapNotifierProvider.notifier);
    await notifier.odemeYap(cariId: ali, tutar: 150);

    var e = await ekstre(ali);
    expect(e.bakiye, 50);
    final odeme = e.hareketler.firstWhere((h) => h.tur == 'odeme');
    expect(odeme.silinebilir, isTrue);

    await notifier.sil(odeme.kayitId!);
    e = await ekstre(ali);
    expect(e.bakiye, 200);
    final denetim = await db.query('islem_gecmisi', where: "tablo_adi = 'cari_odemeler'", orderBy: 'id');
    expect(denetim.map((d) => d['islem']), ['ekle', 'sil']);
  });

  test('fazla ödeme bakiyeyi negatife çevirir (cari borçlu olur)', () async {
    await fiyatTanimla(db, ali, '2026-05', sut: 20);
    await sutGir(ali, '2026-05-01', 10);
    await container.read(cariHesapNotifierProvider.notifier).odemeYap(cariId: ali, tutar: 250);
    final e = await ekstre(ali);
    expect(e.bakiye, -50);
    expect(e.borcluMu, isTrue);
  });

  test('0, negatif veya geçersiz tutarla ödeme yapılamaz', () async {
    final notifier = container.read(cariHesapNotifierProvider.notifier);
    for (final tutar in [0.0, -10.0, double.nan, double.infinity]) {
      await expectLater(notifier.odemeYap(cariId: ali, tutar: tutar), throwsArgumentError);
    }
    expect(await db.query('cari_odemeler'), isEmpty);
  });

  test('ödeme tutarı kuruşa yuvarlanarak kaydedilir', () async {
    await container.read(cariHesapNotifierProvider.notifier).odemeYap(cariId: ali, tutar: 100.005);
    expect((await db.query('cari_odemeler')).single['toplam_tutar'], 100.01);
  });

  test('eski "alim" kayıtları (kapatma özelliğinden) bakiyeye ÇİFT sayılmaz', () async {
    await fiyatTanimla(db, ali, '2026-05', sut: 20);
    await sutGir(ali, '2026-05-01', 10);
    await db.insert('cari_odemeler', {
      'cari_id': ali, 'tarih': '2026-05-31', 'islem_turu': 'alim',
      'miktar': 10, 'birim_fiyat': 20, 'toplam_tutar': 200,
    });
    expect((await ekstre(ali)).bakiye, 200);
    expect((await container.read(tumKalanBorclarProvider.future))[ali], 200);
  });
}
