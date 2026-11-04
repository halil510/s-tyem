import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/core/providers/repository_providers.dart';
import 'package:sutyem_pro/features/cari_hesap/providers/cari_hesap_providers.dart';
import 'package:sutyem_pro/services/whatsapp_service.dart';

import '../helpers/test_db.dart';

/// Aylık Hesaplama & Rapor ekranının (ve WhatsApp/Excel çıktısının)
/// veri kaynağı: tutarlar carinin o ayki gerçek fiyatıyla, ekstreyle
/// aynı fonksiyonlardan hesaplanmalı.
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

  Future<void> sutGir(int cariId, String tarih, double sabah, [double aksam = 0]) async {
    final repo = await container.read(sutRepositoryProvider.future);
    await repo.gunlukKaydet(cariId: cariId, tarih: tarih, sabah: sabah, aksam: aksam);
  }

  Future<Map<int, AylikCariOzet>> ozet(String ay) =>
      container.read(aylikOzetProvider(ay).future);

  test('her cari kendi o ayki fiyatıyla hesaplanır (sabit fiyat yok)', () async {
    await fiyatTanimla(db, ali, '2026-05', sut: 18.5, sutYemi: 12);
    await fiyatTanimla(db, veli, '2026-05', sut: 20);
    await sutGir(ali, '2026-05-01', 20, 18); // 38 kg × 18,5 = 703
    await sutGir(veli, '2026-05-01', 10); //     10 kg × 20   = 200
    await db.insert('yemler', {'cari_id': ali, 'tarih': '2026-05-03', 'sut_yemi': 25, 'toplam': 25}); // 300
    final n = container.read(cariHesapNotifierProvider.notifier);
    await n.odemeYap(cariId: ali, tutar: 100, tarih: DateTime(2026, 5, 10));
    await n.tahsilatAl(cariId: ali, tutar: 40, tarih: DateTime(2026, 5, 11));

    final o = await ozet('2026-05');
    final a = o[ali]!;
    expect(a.sutKg, 38);
    expect(a.sutFiyat, 18.5);
    expect(a.sutTutar, 703);
    expect(a.yemKg, 25);
    expect(a.yemTutar, 300);
    expect(a.odeme, 100);
    expect(a.tahsilat, 40);
    expect(a.ayNet, 343); // 703 + 40 − 300 − 100
    expect(a.fiyatEksik, isFalse);
    expect(o[veli]!.sutTutar, 200);
  });

  test('ay toplamları ekstrenin aynı ay filtresiyle kuruşu kuruşuna aynı', () async {
    await fiyatTanimla(db, ali, '2026-04', sut: 17.333);
    await sutGir(ali, '2026-05-01', 12.345);
    await sutGir(ali, '2026-05-02', 7.77, 1.01);
    await sutGir(ali, '2026-04-30', 99); // başka ay, dahil değil

    final a = (await ozet('2026-05'))[ali]!;
    final e = await container.read(cariEkstreProvider(
      (cariId: ali, baslangic: DateTime(2026, 5, 1), bitis: DateTime(2026, 5, 31)),
    ).future);
    expect(a.sutTutar, e.toplamSut);
    expect(a.ayNet, e.bakiye);
    expect(a.sutFiyat, 17.333, reason: 'Nisan fiyatı Mayıs\'a devralınır');
  });

  test('genel bakiye tüm zamanları kapsar; hareketsiz ama bakiyeli cari listede', () async {
    await fiyatTanimla(db, ali, '2026-04', sut: 10);
    await sutGir(ali, '2026-04-15', 50); // Nisan: 500 alacak

    final o = await ozet('2026-05');
    expect(o[ali], isNotNull);
    expect(o[ali]!.hareketVar, isFalse);
    expect(o[ali]!.genelBakiye, 500);
    expect(o[veli], isNull, reason: 'hareketi ve bakiyesi olmayan cari gösterilmez');
  });

  test('fiyat tanımlı değilse uyarı bayrağı', () async {
    await sutGir(veli, '2026-05-03', 30);
    final v = (await ozet('2026-05'))[veli]!;
    expect(v.sutTutar, 0);
    expect(v.fiyatEksik, isTrue);
  });

  test('WhatsApp mesajı: yem için uydurma birim fiyat yok, net doğru', () {
    final m = WhatsAppService.createHesapOzetiMessage(
      cariAd: 'Ali Yılmaz',
      ayAdi: 'Mayıs 2026',
      sutKg: 38,
      sutFiyat: 18.5,
      sutTutar: 703,
      yemKg: 25,
      yemTutar: 300,
      odeme: 100,
      tahsilat: 40,
      kalanBorc: 343,
    );
    expect(m, contains('38.00 kg × 18.50 ₺ = 703.00 ₺'));
    expect(m, contains('*Yem (Borç):* 25.00 kg = 300.00 ₺'));
    expect(m, contains('*Size Ödenen:* 100.00 ₺'));
    expect(m, contains('*Sizden Alınan:* 40.00 ₺'));
    expect(m, contains('*Bu Ay Net:* 343.00 ₺'));
    expect(m, contains('Alacaklısınız:* 343.00 ₺'));
  });
}
