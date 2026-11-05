// PDF hesap ekstresi + Excel/PDF ortak satır hesabı (2026-11-05).
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sutyem_pro/utils/ekstre_satirlari.dart';
import 'package:sutyem_pro/utils/pdf_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    tmp = await Directory.systemTemp.createTemp('pdf_ekstre');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);
  });
  tearDownAll(() => tmp.delete(recursive: true));

  // Ekrandaki sıra: yeni → eski; aynı gün süt, yem.
  final hareketler = <Map<String, dynamic>>[
    {'tarih': '2026-11-03', 'islemAdi': 'Ödeme', 'kredi': false, 'tutar': 100.0, 'aciklama': ''},
    {'tarih': '2026-11-02', 'islemAdi': 'Süt Alımı', 'kredi': true, 'tutar': 250.10, 'aciklama': '10 kg'},
    {'tarih': '2026-11-02', 'islemAdi': 'Yem Verişi', 'kredi': false, 'tutar': 50.2, 'aciklama': null},
  ];

  test('ortak satırlar: eskiden yeniye, aynı gün sırası korunur, yürüyen bakiye kuruşlu', () {
    final s = ekstreSatirlari(hareketler);
    expect(s.map((e) => e.islemAdi), ['Süt Alımı', 'Yem Verişi', 'Ödeme']);
    expect(s.map((e) => e.tarih), ['02.11.2026', '02.11.2026', '03.11.2026']);
    expect(s.map((e) => e.bakiye), [250.1, 199.9, 99.9]);
    expect(s[0].alacak, 250.1);
    expect(s[0].borc, isNull);
    expect(s[1].aciklama, '');
    expect(s[2].borc, 100.0);
  });

  test('etiketler: filtreli ekstre DÖNEM NETİ, tüm zamanlar NET BAKİYE', () {
    expect(ekstreDonemYazisi(null, null), 'Tüm zamanlar');
    expect(ekstreDonemYazisi(DateTime(2026, 11, 1), DateTime(2026, 11, 30)), 'Dönem: 01.11.2026 – 30.11.2026');
    expect(ekstreBakiyeEtiketi(filtreli: true), 'DÖNEM NETİ');
    expect(ekstreBakiyeEtiketi(filtreli: false), 'NET BAKİYE');
    expect(ekstreDurumu(10), startsWith('cari ALACAKLI'));
    expect(ekstreDurumu(-10), 'cari BORÇLU');
    expect(ekstreDurumu(0.004), 'hesap kapalı');
  });

  test('PDF internetsiz oluşur (uygulama içi yazı tipi), adında "/" olan cari', () async {
    for (final filtre in [false, true]) {
      final f = await PdfExport.exportCariHesapEkstresi(
        cariAdi: 'ŞÜKRÜ / ÇİĞDEM',
        cariTelefon: '0555 111 22 33',
        hareketler: hareketler,
        toplamSut: 250.1,
        toplamYem: 50.2,
        toplamOdeme: 100,
        toplamTahsilat: 0,
        kalanBakiye: 99.9,
        baslangic: filtre ? DateTime(2026, 11, 1) : null,
        bitis: filtre ? DateTime(2026, 11, 30) : null,
      );
      expect(f.existsSync(), isTrue);
      expect(f.path, endsWith('Hesap_Ekstresi_ŞÜKRÜ_ÇİĞDEM.pdf'));
      final bas = String.fromCharCodes(f.readAsBytesSync().take(5));
      expect(bas, '%PDF-');
    }
  });

  test('çok sayfalı ekstre (400 hareket) oluşur', () async {
    final cok = [
      for (var i = 0; i < 400; i++)
        {'tarih': '2026-${(i % 12 + 1).toString().padLeft(2, '0')}-01', 'islemAdi': 'Süt Alımı',
         'kredi': true, 'tutar': 10.0, 'aciklama': ''},
    ];
    final b = await PdfExport.ekstreBelgesi(
        cariAdi: 'ALİ', hareketler: cok, toplamSut: 4000, toplamYem: 0,
        toplamOdeme: 0, toplamTahsilat: 0, kalanBakiye: 4000);
    expect(b.length, greaterThan(1000));
  });
}
