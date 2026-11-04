import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/core/providers/repository_providers.dart';
import 'package:sutyem_pro/data/repositories/donem_kilidi.dart';
import 'package:sutyem_pro/data/repositories/fiyat_repository.dart';
import 'package:sutyem_pro/features/cari_hesap/providers/cari_hesap_providers.dart';
import 'package:sutyem_pro/features/donem/donem_servisi.dart';
import 'package:sutyem_pro/models/cari_fiyat_model.dart';

import '../helpers/test_db.dart';

/// "Süt 25 ₺ idi, bugünden (4 Kasım) itibaren 27 ₺": önceki günler 25 ₺,
/// sonrakiler 27 ₺ ile hesaplanmalı. Eskiden fiyat AYLIK tutulduğu için
/// Kasım'ın 1–3'ü de 27 ₺'dan hesaplanıyordu.
void main() {
  late Database db;
  late ProviderContainer container;
  late int ali, veli;

  setUp(() async {
    db = await testVeritabaniAc();
    container = testContainer(db);
    ali = await cariEkle(db, ad: 'Ali');
    veli = await cariEkle(db, ad: 'Veli');
  });

  tearDown(() => container.dispose());

  Future<void> sutGir(int cariId, String tarih, double kg) async {
    final repo = await container.read(sutRepositoryProvider.future);
    await repo.gunlukKaydet(cariId: cariId, tarih: tarih, sabah: kg, aksam: 0);
  }

  Future<void> kasimOrnegi() async {
    await fiyatTanimla(db, ali, '2026-11', sut: 25);
    await fiyatTanimla(db, ali, '2026-11-04', sut: 27); // 4 Kasım'dan itibaren
    await sutGir(ali, '2026-11-02', 10); // 10 × 25 = 250
    await sutGir(ali, '2026-11-03', 20); // 20 × 25 = 500
    await sutGir(ali, '2026-11-04', 10); // 10 × 27 = 270
    await sutGir(ali, '2026-11-05', 10); // 10 × 27 = 270
  }

  test('anahtar: ayın 1\'i aylık anahtar, diğer günler gün anahtarı', () {
    expect(CariFiyat.anahtar(DateTime(2026, 11, 1)), '2026-11');
    expect(CariFiyat.anahtar(DateTime(2026, 11, 4)), '2026-11-04');
    expect(CariFiyat.anahtarGunu('2026-11'), DateTime(2026, 11, 1));
    expect(CariFiyat.anahtarGunu('2026-11-04'), DateTime(2026, 11, 4));
  });

  test('ekstre: değişiklikten önceki günler eski, sonrakiler yeni fiyatla', () async {
    await kasimOrnegi();
    final e = await container.read(cariEkstreProvider(
      (cariId: ali, baslangic: DateTime(2026, 11, 1), bitis: DateTime(2026, 11, 30)),
    ).future);
    expect(e.toplamSut, 1290); // 250 + 500 + 270 + 270
    final aciklamalar = e.hareketler.where((h) => h.tur == 'sut').map((h) => h.aciklama).toSet();
    expect(aciklamalar, containsAll(['10 kg × 25.00 ₺', '20 kg × 25.00 ₺', '10 kg × 27.00 ₺']));

    final bakiyeler = await container.read(tumKalanBorclarProvider.future);
    expect(bakiyeler[ali], 1290, reason: 'Ödemeler sekmesi ekstreyle aynı');
  });

  test('yeni ay fiyat girilmezse son değişiklik (27 ₺) devam eder', () async {
    await kasimOrnegi();
    await sutGir(ali, '2026-12-01', 10);
    final e = await container.read(cariEkstreProvider(
      (cariId: ali, baslangic: DateTime(2026, 12, 1), bitis: DateTime(2026, 12, 31)),
    ).future);
    expect(e.toplamSut, 270);
  });

  test('aylık özet: tutar gün gün; gösterilen fiyat kg ağırlıklı ortalama', () async {
    await kasimOrnegi();
    await fiyatTanimla(db, veli, '2026-11', sut: 20);
    await sutGir(veli, '2026-11-05', 10);

    final o = await container.read(aylikOzetProvider('2026-11').future);
    expect(o[ali]!.sutTutar, 1290);
    expect(o[ali]!.sutKg, 50);
    expect(o[ali]!.sutFiyat, 25.8); // 1290 / 50
    expect(o[ali]!.fiyatDegisti, isTrue);
    expect(o[veli]!.sutFiyat, 20);
    expect(o[veli]!.fiyatDegisti, isFalse);
  });

  test('dönem hakedişi aynı hesabı yapar', () async {
    await kasimOrnegi();
    final s = (await DonemServisi(db).hesapla('2026-11')).single;
    expect(s.sutTutar, 1290);
    expect(s.sutFiyat, 25.8);
  });

  test('önceki ayın ortasındaki değişiklik sonraki aya devreder', () async {
    await fiyatTanimla(db, ali, '2026-10', sut: 20);
    await fiyatTanimla(db, ali, '2026-10-20', sut: 22);
    await sutGir(ali, '2026-10-19', 10); // 200
    await sutGir(ali, '2026-11-10', 10); // 220 (Kasım fiyatı yok → 20 Ekim'den)
    final bakiyeler = await container.read(tumKalanBorclarProvider.future);
    expect(bakiyeler[ali], 420);
  });

  test('kapalı dönemin içine gün bazlı fiyat yazılamaz (v11 tetikleyici)', () async {
    await fiyatTanimla(db, ali, '2026-10', sut: 18);
    await sutGir(ali, '2026-10-05', 10);
    await DonemServisi(db).kapat('2026-10', simdi: DateTime(2026, 11, 4));

    final repo = CariFiyatRepository(db);
    await expectLater(
      repo.topluKaydet([CariFiyat(cariId: ali, ay: '2026-10-15', sutFiyat: 99)]),
      throwsA(isA<DonemKapaliHatasi>()),
    );
    // Açık ayda gün bazlı fiyat serbest.
    await repo.topluKaydet([CariFiyat(cariId: ali, ay: '2026-11-04', sutFiyat: 27)]);
  });

  test('aylık yem fiyatı kaydedilince aynı ayın gün satırlarına da yayılır', () async {
    await fiyatTanimla(db, ali, '2026-11', sut: 25, sutYemi: 10);
    await fiyatTanimla(db, ali, '2026-11-04', sut: 27, sutYemi: 10);
    await fiyatTanimla(db, ali, '2026-12-04', sut: 30, sutYemi: 10); // başka ay: dokunulmaz

    await CariFiyatRepository(db).topluKaydet(
      [CariFiyat(cariId: ali, ay: '2026-11', sutFiyat: 25, sutYemiFiyat: 12)],
      yemFiyatiniAyaYay: true,
    );
    final satirlar = {
      for (final m in await db.query('cari_fiyatlar', where: 'cari_id = ?', whereArgs: [ali]))
        m['ay']: (m['sut_fiyat'], m['sut_yemi_fiyat'])
    };
    expect(satirlar['2026-11'], (25.0, 12.0));
    expect(satirlar['2026-11-04'], (27.0, 12.0), reason: 'süt fiyatı korunur, yem güncellenir');
    expect(satirlar['2026-12-04'], (30.0, 10.0));
  });

  test('seçilen günde geçerli fiyat (Süt Fiyatları ekranının ön dolgusu)', () async {
    await fiyatTanimla(db, ali, '2026-11', sut: 25);
    await fiyatTanimla(db, ali, '2026-11-04', sut: 27);
    final repo = CariFiyatRepository(db);
    expect((await repo.getAyFiyatlariHepsi([ali], '2026-11-03'))[ali]!.sutFiyat, 25);
    expect((await repo.getAyFiyatlariHepsi([ali], '2026-11-04'))[ali]!.sutFiyat, 27);
    expect((await repo.getAyFiyatlariHepsi([ali], '2026-11-20'))[ali]!.sutFiyat, 27);
    expect((await repo.getAyFiyatlariHepsi([ali], '2026-11'))[ali]!.sutFiyat, 25, reason: 'ay başı');
  });
}
