import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/core/providers/repository_providers.dart';
import 'package:sutyem_pro/data/yedek/yedek_servisi.dart';
import 'package:sutyem_pro/features/cari_hesap/providers/cari_hesap_providers.dart';
import 'package:sutyem_pro/features/donem/donem_servisi.dart';
import 'package:sutyem_pro/models/cari_fiyat_model.dart';
import 'package:sutyem_pro/models/yem_model.dart';

import '../helpers/test_db.dart';

/// Aylık dönem kapanışı: hakediş hesabı, kilit, yeniden açma, yedek.
void main() {
  late Database db;
  late ProviderContainer container;
  late DonemServisi servis;
  late int ali, veli;
  final kasim = DateTime(2026, 11, 4); // "bugün"

  setUp(() async {
    db = await testVeritabaniAc();
    container = testContainer(db);
    servis = DonemServisi(db);
    ali = await cariEkle(db, ad: 'Ali');
    veli = await cariEkle(db, ad: 'Veli');
  });

  tearDown(() => container.dispose());

  Future<void> sutGir(int cariId, String tarih, double kg) async {
    final repo = await container.read(sutRepositoryProvider.future);
    await repo.gunlukKaydet(cariId: cariId, tarih: tarih, sabah: kg, aksam: 0);
  }

  Future<void> ornekVeri() async {
    await fiyatTanimla(db, ali, '2026-09', sut: 15, sutYemi: 10);
    await sutGir(ali, '2026-09-20', 100); //  Eylül: +1500 → devir
    await fiyatTanimla(db, ali, '2026-10', sut: 18, sutYemi: 12);
    await sutGir(ali, '2026-10-01', 40); //   Ekim: 40 × 18 = 720
    await sutGir(ali, '2026-10-02', 60); //   60 × 18 = 1080
    await db.insert('yemler', {'cari_id': ali, 'tarih': '2026-10-05', 'sut_yemi': 50, 'toplam': 50}); // 600
    final n = container.read(cariHesapNotifierProvider.notifier);
    await n.odemeYap(cariId: ali, tutar: 1000, tarih: DateTime(2026, 10, 15));
    await n.tahsilatAl(cariId: ali, tutar: 20, tarih: DateTime(2026, 10, 16));
  }

  test('hakediş: devir + ay hareketleri = dönem sonu', () async {
    await ornekVeri();
    final s = (await servis.hesapla('2026-10')).single;
    expect(s.cariId, ali);
    expect(s.devir, 1500);
    expect(s.sutKg, 100);
    expect(s.sutFiyat, 18);
    expect(s.sutTutar, 1800);
    expect(s.yemTutar, 600);
    expect(s.odeme, 1000);
    expect(s.tahsilat, 20);
    expect(s.ayNet, 220); // 1800 + 20 − 600 − 1000
    expect(s.donemSonu, 1720);
  });

  test('ay neti Aylık Rapor ile ve genel bakiye ile tutarlı', () async {
    await ornekVeri();
    final s = (await servis.hesapla('2026-10')).single;
    final aylik = (await container.read(aylikOzetProvider('2026-10').future))[ali]!;
    expect(s.ayNet, aylik.ayNet);
    final bakiye = (await container.read(tumKalanBorclarProvider.future))[ali];
    expect(s.donemSonu, bakiye);
  });

  test('kapatma bordroyu dondurur ve o aya her türlü yazmayı kilitler', () async {
    await ornekVeri();
    final bilgi = await servis.kapat('2026-10', simdi: kasim);
    expect(bilgi.kapali, isTrue);
    expect(bilgi.satirlar.single.donemSonu, 1720);

    final sutRepo = await container.read(sutRepositoryProvider.future);
    final yemRepo = await container.read(yemRepositoryProvider.future);
    final fiyatRepo = await container.read(cariFiyatRepositoryProvider.future);
    final n = container.read(cariHesapNotifierProvider.notifier);

    await expectLater(sutGir(ali, '2026-10-03', 5), throwsA(isA<DonemKapaliHatasi>()));
    await expectLater(sutGir(veli, '2026-10-03', 5), throwsA(isA<DonemKapaliHatasi>()));
    final mevcut = await sutRepo.getGunluk(ali, '2026-10-01');
    await expectLater(sutRepo.delete(mevcut!.id!), throwsA(isA<DonemKapaliHatasi>()));
    await expectLater(
        yemRepo.insert(Yem(cariId: ali, tarih: '2026-10-09', sutYemi: 1)),
        throwsA(isA<DonemKapaliHatasi>()));
    await expectLater(n.odemeYap(cariId: ali, tutar: 5, tarih: DateTime(2026, 10, 20)),
        throwsA(isA<DonemKapaliHatasi>()));
    await expectLater(fiyatRepo.kaydet(CariFiyat(cariId: ali, ay: '2026-10', sutFiyat: 99)),
        throwsA(isA<DonemKapaliHatasi>()));

    // Açık aylar etkilenmez.
    await sutGir(ali, '2026-11-01', 10);
    await n.odemeYap(cariId: ali, tutar: 5, tarih: DateTime(2026, 11, 2));

    // Bordro değişmedi.
    expect((await servis.bilgi('2026-10')).satirlar.single.donemSonu, 1720);
  });

  test('devralınan fiyat kapanışta sabitlenir; önceki ay fiyatı değişse de kapalı ay değişmez', () async {
    await fiyatTanimla(db, ali, '2026-09', sut: 15);
    await sutGir(ali, '2026-10-01', 10); // Ekim fiyatı yok → Eylül'den 15
    await servis.kapat('2026-10', simdi: kasim);

    final kendi = await db.query('cari_fiyatlar', where: "cari_id = ? AND ay = '2026-10'", whereArgs: [ali]);
    expect(kendi.single['sut_fiyat'], 15);

    final fiyatRepo = await container.read(cariFiyatRepositoryProvider.future);
    await fiyatRepo.kaydet(CariFiyat(cariId: ali, ay: '2026-09', sutFiyat: 30)); // Eylül açık

    final ekstre = await container.read(cariEkstreProvider(
      (cariId: ali, baslangic: DateTime(2026, 10, 1), bitis: DateTime(2026, 10, 31)),
    ).future);
    expect(ekstre.toplamSut, 150, reason: 'kapalı Ekim hâlâ 15 ₺ ile');
  });

  test('bitmemiş ay ve fiyatı eksik dönem kapatılamaz', () async {
    await expectLater(servis.kapat('2026-11', simdi: kasim), throwsA(isA<DonemIslemHatasi>()));
    await sutGir(veli, '2026-10-05', 30); // Veli'nin hiç fiyatı yok
    await expectLater(servis.kapat('2026-10', simdi: kasim), throwsA(isA<DonemIslemHatasi>()));
    expect(await servis.kapaliMi('2026-10'), isFalse);
  });

  test('yeniden açma gerekçe ister, kaydı denetime yazar ve düzeltmeye izin verir', () async {
    await ornekVeri();
    await servis.kapat('2026-10', simdi: kasim);
    await expectLater(servis.yenidenAc('2026-10', ' '), throwsA(isA<DonemIslemHatasi>()));

    final acik = await servis.yenidenAc('2026-10', 'Ali 2 Ekim yanlış girilmiş');
    expect(acik.kapali, isFalse);
    expect(acik.acilisSayisi, 1);

    await sutGir(ali, '2026-10-02', 50); // düzeltme: 60 → 50
    final yeni = await servis.kapat('2026-10', simdi: kasim);
    expect(yeni.satirlar.single.sutTutar, 1620); // 90 × 18

    final denetim = await db.query('islem_gecmisi', where: "tablo_adi = 'donemler'");
    expect(denetim, hasLength(3)); // kapat, aç, kapat
    expect(denetim[1]['onceki_deger'], contains('bordro'));
    expect(denetim[1]['yeni_deger'], contains('yanlış girilmiş'));
  });

  test('kapalı dönemde kaydı olan cari kalıcı silinemez', () async {
    await ornekVeri();
    await servis.kapat('2026-10', simdi: kasim);
    final cariRepo = await container.read(cariRepositoryProvider.future);
    await expectLater(cariRepo.delete(ali), throwsA(isA<DonemKapaliHatasi>()));
    expect(await db.query('sutler', where: 'cari_id = ?', whereArgs: [ali]), hasLength(3));
  });

  group('yedek', () {
    test('kapalı dönem ve bordro yedeğe girer; tamamen değiştirerek geri yüklenir ve kilit sürer', () async {
      await ornekVeri();
      await servis.kapat('2026-10', simdi: kasim);
      final yedek = await YedekServisi.disaAktar(db);
      expect(yedek['donemler'], hasLength(1));
      expect(yedek['donem_hakedisleri'], hasLength(1));

      final hedef = await testVeritabaniAc();
      final hedefServis = DonemServisi(hedef);
      // Hedefte de kapalı bir dönem olsun: silme kilidi aktarımı engellememeli.
      final h = await cariEkle(hedef, ad: 'Eski');
      await fiyatTanimla(hedef, h, '2026-08', sut: 10);
      await hedef.insert('sutler', {'cari_id': h, 'tarih': '2026-08-01', 'sabah': 1, 'toplam': 1});
      await hedefServis.kapat('2026-08', simdi: kasim);

      await YedekServisi.iceAktar(hedef, yedek, tamamenDegistir: true);
      final b = await hedefServis.bilgi('2026-10');
      expect(b.kapali, isTrue);
      expect(b.satirlar.single.donemSonu, 1720);
      expect(await hedefServis.kapaliMi('2026-08'), isFalse);
      await expectLater(
        hedef.insert('sutler', {'cari_id': ali, 'tarih': '2026-10-20', 'sabah': 1, 'toplam': 1}),
        throwsA(predicate((e) => donemKapaliHatasiMi(e!))),
      );
      await hedef.close();
    });

    test('dönem tablosu olmayan v2 yedeği hâlâ tam yedek sayılır', () async {
      await ornekVeri();
      final yedek = await YedekServisi.disaAktar(db)
        ..remove('donemler')
        ..remove('donem_hakedisleri');
      expect(YedekServisi.tamYedekMi(yedek), isTrue);
    });
  });
}
