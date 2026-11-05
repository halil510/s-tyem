// Excel dışa aktarmaları: dosya gerçekten üretilir, `excel` paketiyle geri
// okunur ve rakamlar kontrol edilir (2026-11-05 Excel taraması).
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sutyem_pro/features/cari_hesap/providers/cari_hesap_providers.dart';
import 'package:sutyem_pro/features/donem/donem_servisi.dart';
import 'package:sutyem_pro/models/cari_model.dart';
import 'package:sutyem_pro/models/sut_model.dart';
import 'package:sutyem_pro/models/yem_model.dart';
import 'package:sutyem_pro/utils/excel_export.dart';

Excel _oku(File f) => Excel.decodeBytes(f.readAsBytesSync());

Object? _deger(CellValue? v) => switch (v) {
      null => null,
      DoubleCellValue d => d.value,
      IntCellValue i => i.value.toDouble(),
      _ => v.toString(),
    };

List<List<Object?>> _satirlar(Excel x, String sayfa) =>
    x.tables[sayfa]!.rows.map((r) => r.map((c) => _deger(c?.value)).toList()).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    tmp = await Directory.systemTemp.createTemp('excel_rapor');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);
  });
  tearDownAll(() => tmp.delete(recursive: true));

  final ali = Cari(id: 1, ad: 'ALİ', soyad: 'VELİ');
  final cetin = Cari(id: 3, ad: 'ÇETİN', soyad: 'KAYA');
  final zeki = Cari(id: 4, ad: 'ZEKİ', soyad: 'ÖZ');

  group('Süt raporu', () {
    test('boş Sheet1 yok, kuruş yuvarlama, Türkçe sıra, pasif carinin sütü dahil', () async {
      final sutler = [
        Sut(cariId: 1, tarih: '2026-11-01', sabah: 0.1, aksam: 0.2),
        Sut(cariId: 4, tarih: '2026-11-02', sabah: 10, aksam: 5),
        Sut(cariId: 2, tarih: '2026-11-01', sabah: 7), // listede yok (pasif/silinmiş)
        Sut(cariId: 1, tarih: '2026-10-31', sabah: 99), // aralık dışı
      ];
      final f = await ExcelExport.exportSutRaporu(
          cariler: [zeki, cetin, ali],
          sutler: sutler,
          startDate: DateTime(2026, 11, 1),
          endDate: DateTime(2026, 11, 2),
          raporAdi: 'sut');
      final x = _oku(f);
      expect(x.tables.keys.toList(), ['Süt Raporu', 'Süt Toplamları']);
      final r = _satirlar(x, 'Süt Raporu');
      expect(r[0].length, 1 + 2 * 2 + 1);
      expect(r.map((s) => s.first).toList(), [
        'İsim Soyisim / Günler', 'ALİ VELİ', 'ÇETİN KAYA', 'Silinmiş/pasif cari #2', 'ZEKİ ÖZ', 'GENEL TOPLAM',
      ]);
      expect(r[1], ['ALİ VELİ', 0.1, 0.2, 0.0, 0.0, 0.3]);
      expect(r[3].last, 7.0);
      // GENEL TOPLAM = aralıktaki TÜM kayıtlar (0.3 + 15 + 7)
      expect(r[5], ['GENEL TOPLAM', 7.1, 0.2, 10.0, 5.0, 22.3]);

      // 2. sayfa: her cari tek satır, yalnız toplam — 1. sayfayla aynı sıra ve rakam.
      final t = _satirlar(x, 'Süt Toplamları');
      expect(t[0].first, 'Süt Toplamları — 01.11.2026 - 02.11.2026');
      expect(t[2], ['İsim Soyisim', 'Toplam (kg)']);
      expect(t.sublist(3), [
        ['ALİ VELİ', 0.3],
        ['ÇETİN KAYA', 0.0],
        ['Silinmiş/pasif cari #2', 7.0],
        ['ZEKİ ÖZ', 15.0],
        ['GENEL TOPLAM', 22.3],
      ]);
    });

    test('bir yıllık aralık çökmez (702. sütun) ve hızlıdır', () async {
      final cariler = [for (var i = 1; i <= 40; i++) Cari(id: i, ad: 'CARİ$i', soyad: 'X')];
      final sutler = <Sut>[];
      for (var g = DateTime(2026, 1, 1); g.year == 2026; g = DateTime(g.year, g.month, g.day + 1)) {
        final t = '${g.year}-${g.month.toString().padLeft(2, '0')}-${g.day.toString().padLeft(2, '0')}';
        for (final c in cariler) {
          sutler.add(Sut(cariId: c.id!, tarih: t, sabah: 1.5, aksam: 2.25));
        }
      }
      final sw = Stopwatch()..start();
      final f = await ExcelExport.exportSutRaporu(
          cariler: cariler,
          sutler: sutler,
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 12, 31),
          raporAdi: 'yillik');
      sw.stop();
      // ignore: avoid_print
      print('Yıllık süt raporu (40 cari × 365 gün): ${sw.elapsedMilliseconds} ms');
      final r = _satirlar(_oku(f), 'Süt Raporu');
      expect(r[0].length, 1 + 365 * 2 + 1);
      expect(r.last.first, 'GENEL TOPLAM');
      expect(r.last.last, 40 * 365 * 3.75);
      expect(sw.elapsed, lessThan(const Duration(seconds: 20)));
    });
  });

  group('Yem raporu', () {
    test('cariye göre gruplu, tür toplamları, çağıranın listesi değişmez', () async {
      final yemler = [
        Yem(cariId: 4, tarih: '2026-11-03', sutYemi: 50),
        Yem(cariId: 1, tarih: '2026-11-02', besiYemi: 25.5),
        Yem(cariId: 1, tarih: '2026-11-01', sutYemi: 0.1, bBaslangic: 0.2),
        Yem(cariId: 2, tarih: '2026-11-01', tavukYemi: 10),
      ];
      final onceki = yemler.map((y) => y.tarih).toList();
      final f = await ExcelExport.exportYemRaporu(
          cariler: [zeki, ali],
          yemler: yemler,
          startDate: DateTime(2026, 11, 1),
          endDate: DateTime(2026, 11, 30),
          raporAdi: 'yem');
      expect(yemler.map((y) => y.tarih).toList(), onceki, reason: 'ekrandaki liste sıralanmamalı');
      final x = _oku(f);
      expect(x.tables.keys.toList(), ['Yem Raporu']);
      final r = _satirlar(x, 'Yem Raporu');
      expect(r.map((s) => s.first).toList(), [
        'İsim Soyisim', 'ALİ VELİ', 'ALİ VELİ', 'ALİ VELİ — toplam',
        'Silinmiş/pasif cari #2', 'ZEKİ ÖZ', 'GENEL TOPLAM',
      ]);
      expect(r[1][1], '01.11.2026');
      expect(r[3], ['ALİ VELİ — toplam', null, 0.1, 25.5, 0.2, 0.0, 0.0, 0.0, 25.8]);
      expect(r.last, ['GENEL TOPLAM', null, 50.1, 25.5, 0.2, 0.0, 0.0, 10.0, 85.8]);
    });
  });

  test('Süt ve yem (Excel yedeği): süt, süt toplamları, yem sayfaları', () async {
    final f = await ExcelExport.exportSutVeYemRaporu(
        cariler: [ali],
        sutler: [Sut(cariId: 1, tarih: '2026-11-01', sabah: 3)],
        yemler: [Yem(cariId: 1, tarih: '2026-11-01', sutYemi: 2)],
        startDate: DateTime(2026, 11, 1),
        endDate: DateTime(2026, 11, 30),
        raporAdi: 'ikisi');
    final x = _oku(f);
    expect(x.tables.keys.toSet(), {'Süt Raporu', 'Süt Toplamları', 'Yem Raporu'});
    expect(_satirlar(x, 'Süt Raporu').last.last, 3.0);
    expect(_satirlar(x, 'Yem Raporu').last.last, 2.0);
  });

  group('Hesap ekstresi', () {
    // Ekrandaki sıra: yeni → eski; aynı gün süt, yem, ödeme.
    final hareketler = <Map<String, dynamic>>[
      {'tarih': '2026-11-03', 'islemAdi': 'Ödeme', 'kredi': false, 'tutar': 100.0, 'aciklama': ''},
      {'tarih': '2026-11-02', 'islemAdi': 'Süt Alımı', 'kredi': true, 'tutar': 250.10, 'aciklama': '10 kg'},
      {'tarih': '2026-11-02', 'islemAdi': 'Yem Verişi', 'kredi': false, 'tutar': 50.2, 'aciklama': ''},
    ];

    test('eskiden yeniye, yürüyen bakiye, adında "/" olan cari', () async {
      final f = await ExcelExport.exportCariHesapEkstresi(
          cariAdi: 'AHMET / MEHMET',
          hareketler: hareketler,
          toplamSut: 250.1,
          toplamYem: 50.2,
          toplamOdeme: 100,
          toplamTahsilat: 0,
          kalanBakiye: 99.9);
      final x = _oku(f);
      expect(x.tables.keys.toList(), ['Hesap Ekstresi']);
      final r = _satirlar(x, 'Hesap Ekstresi');
      expect(r[1].first, 'Tüm zamanlar');
      expect(r[4], ['02.11.2026', 'Süt Alımı', '10 kg', 250.1, null, 250.1]);
      expect(r[5], ['02.11.2026', 'Yem Verişi', '', null, 50.2, 199.9]);
      expect(r[6], ['03.11.2026', 'Ödeme', '', null, 100.0, 99.9]);
      final son = r.lastWhere((s) => s.isNotEmpty && s.first != null);
      expect(son.first, startsWith('NET BAKİYE (cari ALACAKLI'));
      expect(son.last, 99.9);
    });

    test('tarih filtresi → "DÖNEM NETİ", tüm zamanların bakiyesi gibi görünmez', () async {
      final f = await ExcelExport.exportCariHesapEkstresi(
          cariAdi: 'ALİ VELİ',
          hareketler: hareketler,
          toplamSut: 250.1,
          toplamYem: 50.2,
          toplamOdeme: 100,
          toplamTahsilat: 0,
          kalanBakiye: 99.9,
          baslangic: DateTime(2026, 11, 1),
          bitis: DateTime(2026, 11, 30));
      final r = _satirlar(_oku(f), 'Hesap Ekstresi');
      expect(r[1].first, 'Dönem: 01.11.2026 – 30.11.2026');
      final metin = r.where((s) => s.isNotEmpty).map((s) => s.first).whereType<String>().toList();
      expect(metin.any((m) => m.startsWith('DÖNEM NETİ')), isTrue);
      expect(metin.any((m) => m.startsWith('NET BAKİYE')), isFalse);
    });
  });

  test('Aylık hesaplama: Sheet1 yok, fiyat eksik notu, toplamlar yuvarlı', () async {
    final f = await ExcelExport.exportHesaplamaRaporu(satirlar: [
      (cari: ali, ozet: const AylikCariOzet(cariId: 1, sutKg: 0.1, sutFiyat: 20, sutTutar: 2, genelBakiye: 2)),
      (cari: cetin, ozet: const AylikCariOzet(cariId: 3, sutKg: 0.2, fiyatEksik: true)),
    ], ayAdi: 'Kasım_2026');
    final x = _oku(f);
    expect(x.tables.keys.toList(), ['Aylık Hesaplama']);
    final r = _satirlar(x, 'Aylık Hesaplama');
    expect(r[2].last, startsWith('FİYAT EKSİK'));
    expect(r[3][0], 'GENEL TOPLAM');
    expect(r[3][1], 0.3);
    expect(r[3][2], isNull, reason: 'fiyat toplanmaz');
  });

  test('Hakediş bordrosu: Sheet1 yok, dönem sonu toplamı', () async {
    final f = await ExcelExport.exportHakedisBordrosu(satirlar: [
      (
        cari: ali,
        satir: const HakedisSatiri(cariId: 1, devir: 10, sutKg: 100, sutFiyat: 20, sutTutar: 2000, yemTutar: 500.55)
      ),
      (cari: cetin, satir: const HakedisSatiri(cariId: 3, devir: -0.1, odeme: 0.2)),
    ], ayAdi: 'Ekim 2026', kapali: true);
    final x = _oku(f);
    expect(x.tables.keys.toList(), ['Hakediş Ekim 2026']);
    final r = _satirlar(x, 'Hakediş Ekim 2026');
    expect(r[3][9], 1509.45);
    expect(r[5][0], 'TOPLAM');
    expect(r[5][1], 9.9);
    expect(r[5][9], 1509.15);
  });

  test('dosya adı temizliği', () {
    expect(ExcelExport.dosyaAdi('Hesap_Ekstresi_A/B: "C"?'), 'Hesap_Ekstresi_A_B_C_');
    expect(ExcelExport.dosyaAdi('Hakedis_Ekim 2026'), 'Hakedis_Ekim_2026');
  });
}
