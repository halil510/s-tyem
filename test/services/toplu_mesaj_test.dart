import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sutyem_pro/ekranlar/cari/cari_dialoglari.dart';
import 'package:sutyem_pro/models/cari_model.dart';
import 'package:sutyem_pro/models/sut_model.dart';
import 'package:sutyem_pro/models/yem_model.dart';
import 'package:sutyem_pro/services/toplu_mesaj_servisi.dart';
import 'package:sutyem_pro/services/whatsapp_service.dart';
import 'package:sutyem_pro/utils/tarih_format.dart';

void main() {
  setUpAll(initializeTurkishLocale);

  group('telefonNormalize', () {
    test('Türkiye cep numarası biçimleri', () {
      expect(WhatsAppService.telefonNormalize('0555 002 00 05'), '905550020005');
      expect(WhatsAppService.telefonNormalize('5550020005'), '905550020005');
      expect(WhatsAppService.telefonNormalize('+90 (555) 002-00-05'), '905550020005');
      expect(WhatsAppService.telefonNormalize('905550020005'), '905550020005');
    });
    test('geçersiz numara boş döner', () {
      expect(WhatsAppService.telefonNormalize(''), '');
      expect(WhatsAppService.telefonNormalize('12345'), '');
      expect(WhatsAppService.telefonNormalize('abc'), '');
    });
  });

  group('TopluMesajServisi', () {
    Cari cari(String ad, String? tel) => Cari(id: ad.hashCode, ad: ad, soyad: 'X', telefon: tel);

    test('gerçek sonuç sayılır; hata ve telefonsuz cari diğerlerini durdurmaz', () async {
      final gonderilenler = <String>[];
      final servis = TopluMesajServisi(
        bekleme: Duration.zero,
        gonderici: (tel, mesaj) async {
          if (tel == '905550000002') return false; // WhatsApp açılamadı
          if (tel == '905550000003') throw StateError('kısa'); // kısa hata metni
          gonderilenler.add('$tel|$mesaj');
          return true;
        },
      );
      final sonuc = await servis.gonder([
        cari('Ali', '05550000001'),
        cari('Veli', '05550000002'),
        cari('Can', '05550000003'),
        cari('Ece', null),
        cari('Naz', '123'),
        cari('Efe', '0555 000 00 04'),
      ], (c) async => 'Merhaba ${c.ad}');

      expect(sonuc.gonderilen, 2);
      expect(sonuc.basarisiz, ['Veli X', 'Can X']);
      expect(sonuc.telefonsuz, ['Ece X', 'Naz X']);
      expect(sonuc.toplam, 6);
      expect(gonderilenler, ['905550000001|Merhaba Ali', '905550000004|Merhaba Efe']);
      expect(sonuc.ozet('mesaj'), contains('2 cariye mesaj gönderildi'));
    });
  });

  group('sutRaporuToplamlari', () {
    Sut s(String tarih, double kg) => Sut(cariId: 1, tarih: tarih, sabah: kg);

    test('ayın 2\'sinde haftalık toplam önceki ayın günlerini de kapsar', () {
      final bugun = DateTime(2026, 11, 2);
      expect(sutRaporuBaslangici(bugun), DateTime(2026, 10, 27));
      final t = sutRaporuToplamlari([
        s('2026-10-26', 100), // 7 günün dışında
        s('2026-10-27', 10),
        s('2026-10-31', 20),
        s('2026-11-01', 30),
        s('2026-11-02', 40),
        s('2026-11-03', 999), // gelecek, sayılmaz
      ], bugun);
      expect(t.gunluk, 40);
      expect(t.haftalik, 100); // 10 + 20 + 30 + 40
      expect(t.aylik, 70); // 30 + 40
    });
  });

  test('yem raporu tüm yem türlerini listeler', () {
    final r = yemRaporuDetayi([
      Yem(cariId: 1, tarih: '2026-11-01', sutYemi: 25, bBaslangic: 5, bBuyutme: 2.5),
      Yem(cariId: 1, tarih: '2026-11-02', tavukYemi: 10),
    ]);
    expect(r.toplam, 42.5);
    expect(r.detay, contains('01.11.2026: Süt Yemi: 25 kg, B. Başlangıç: 5 kg, B. Büyütme: 2.5 kg'));
    expect(r.detay, contains('02.11.2026: Tavuk Yemi: 10 kg'));
  });

  testWidgets('rapor tarih diyaloğu aralığı döndürür, alttaki sayfayı kapatmaz', (tester) async {
    DateTimeRange? sonuc;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Column(children: [
            const Text('ALT SAYFA'),
            ElevatedButton(
              onPressed: () async => sonuc = await raporTarihAraligiSor(context, 'Süt Raporu'),
              child: const Text('aç'),
            ),
          ]),
        ),
      ),
    ));
    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Son 7 Gün'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oluştur'));
    await tester.pumpAndSettle();

    final b = DateTime.now();
    final bugun = DateTime(b.year, b.month, b.day);
    expect(sonuc, DateTimeRange(start: DateTime(b.year, b.month, b.day - 6), end: bugun));
    expect(find.text('ALT SAYFA'), findsOneWidget);
    expect(find.text('Süt Raporu'), findsNothing);
  });
}
