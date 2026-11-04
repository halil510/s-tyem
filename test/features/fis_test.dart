import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/data/repositories/sut_repository.dart';
import 'package:sutyem_pro/features/fis/fis_servisi.dart';
import 'package:sutyem_pro/features/fis/uretici_fisi.dart';
import 'package:sutyem_pro/models/cari_model.dart';
import 'package:sutyem_pro/utils/tarih_format.dart';

import '../helpers/test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeTurkishLocale);

  final fis = UreticiFisi(
    isletmeAdi: 'Kabatlı Süt Toplama',
    fisNo: 42,
    tarih: DateTime(2026, 11, 4),
    basimZamani: DateTime(2026, 11, 4, 8, 15),
    ureticiAdi: 'Şükrü Çağlar',
    sabah: 20.5,
    aksam: 18,
    buAyKg: 512.25,
  );

  group('fiş düzeni', () {
    for (final g in [32, 40, 48]) {
      test('$g karakter: satırlar kâğıda sığar, bilgiler doğru', () {
        final satirlar = fis.satirlar(g);
        for (final s in satirlar) {
          expect(s.metin.length, lessThanOrEqualTo(s.buyuk ? g ~/ 2 : g), reason: '"${s.metin}"');
        }
        final metin = satirlar.map((s) => s.metin).join('\n');
        expect(metin, contains('Fiş No'));
        expect(metin, contains('42'));
        expect(metin, contains('04.11.2026'));
        expect(metin, contains('Şükrü Çağlar'));
        expect(metin, contains('20,5 kg'));
        expect(metin, contains('18 kg'));
        expect(metin, contains('38,5 kg'));
        expect(metin, contains('512,25 kg'));
      });
    }

    test('sıfır olan vardiya basılmaz', () {
      final f = UreticiFisi(
        isletmeAdi: '', fisNo: 1, tarih: DateTime(2026, 11, 4), basimZamani: DateTime(2026, 11, 4),
        ureticiAdi: 'Ali', sabah: 0, aksam: 15, buAyKg: 15,
      );
      final metin = f.satirlar(32).map((s) => s.metin).join('\n');
      expect(metin, isNot(contains('Sabah')));
      expect(metin, contains('Akşam'));
    });

    test('solSag ve sar', () {
      expect(solSag('Sabah', '20,5 kg', 20), 'Sabah        20,5 kg');
      expect(solSag('Çok uzun bir etiket metni', '1 kg', 12), 'Çok uzu 1 kg');
      expect(sar('Ahmet Mehmet Yılmazoğulları', 12), ['Ahmet Mehmet', 'Yılmazoğulla', 'rı']);
      expect(sar('', 10), ['']);
    });

    test('WhatsApp metni tek aralıklı blok', () {
      final m = fis.whatsappMetni();
      expect(m, startsWith('```\n'));
      expect(m, endsWith('\n```'));
      expect(m, contains('GÜNLÜK TOPLAM'));
    });
  });

  group('ESC/POS', () {
    test('Türkçe harfler varsayılan olarak Latin harfine çevrilir', () {
      expect(String.fromCharCodes(EscPos.kodla('Şükrü Çağlar İĞÖ ı ₺')), 'Sukru Caglar IGO i TL');
      expect(EscPos.kodla('€'), [0x3F]);
    });

    test('CP857 açıkken gerçek Türkçe baytlar', () {
      expect(EscPos.kodla('şŞğĞıİüÜöÖçÇ', turkceKodSayfasi: true),
          [0x9F, 0x9E, 0xA7, 0xA6, 0x8D, 0x98, 0x81, 0x9A, 0x94, 0x99, 0x87, 0x80]);
    });

    test('fiş baytları: başlat, kod sayfası, satırlar, kesim', () {
      final b = EscPos.fis(fis.satirlar(32), turkceKodSayfasi: true);
      expect(b.sublist(0, 5), [0x1B, 0x40, 0x1B, 0x74, 13]);
      expect(b.sublist(b.length - 4), [0x1D, 0x56, 0x42, 0x00]);
      final duz = EscPos.fis(fis.satirlar(32));
      expect(duz.sublist(0, 2), [0x1B, 0x40]);
      expect(duz[2], isNot(0x74), reason: 'kod sayfası komutu gönderilmez');
      expect(duz.every((x) => x >= 0 && x < 256), isTrue);
      expect(String.fromCharCodes(duz), contains('SUT TESLIM FISI'));
    });
  });

  group('fiş ayarları', () {
    test('varsayılan 80 mm (40 karakter); geçersiz değer varsayılana döner', () async {
      SharedPreferences.setMockInitialValues({});
      expect((await FisAyarlari.yukle()).genislik, 40);
      SharedPreferences.setMockInitialValues({'fis_genislik': 48});
      expect((await FisAyarlari.yukle()).genislik, 48);
      SharedPreferences.setMockInitialValues({'fis_genislik': 99});
      expect((await FisAyarlari.yukle()).genislik, 40);
    });

    test('kaydedilen ayar geri okunur', () async {
      SharedPreferences.setMockInitialValues({});
      await const FisAyarlari(yaziciAdres: 'AA', yaziciAdi: 'POS-80', genislik: 32, isletmeAdi: ' Kabatlı ')
          .kaydet();
      final a = await FisAyarlari.yukle();
      expect((a.yaziciAdres, a.yaziciAdi, a.genislik, a.isletmeAdi), ('AA', 'POS-80', 32, 'Kabatlı'));
    });
  });

  group('yazıcı kanalı', () {
    const kanal = MethodChannel('termal_yazici');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(kanal, null));

    test('seçili yazıcıya baytları gönderir', () async {
      MethodCall? gelen;
      messenger.setMockMethodCallHandler(kanal, (c) async {
        gelen = c;
        return true;
      });
      const ayar = FisAyarlari(yaziciAdres: 'AA:BB:CC:DD:EE:FF', yaziciAdi: 'POS-58');
      await TermalYaziciServisi.yazdir(ayar, fis.satirlar(32));
      expect(gelen!.method, 'yazdir');
      expect(gelen!.arguments['address'], 'AA:BB:CC:DD:EE:FF');
      expect(gelen!.arguments['bytes'], isA<Uint8List>());
      expect((gelen!.arguments['bytes'] as Uint8List).first, 0x1B);
    });

    test('yazıcı seçilmemişse ve bağlantı hatasında anlaşılır hata', () async {
      await expectLater(TermalYaziciServisi.yazdir(const FisAyarlari(), fis.satirlar(32)),
          throwsA(isA<YaziciHatasi>()));
      messenger.setMockMethodCallHandler(kanal, (c) async {
        throw PlatformException(code: 'YAZDIRILAMADI', message: 'socket closed');
      });
      await expectLater(
        TermalYaziciServisi.yazdir(const FisAyarlari(yaziciAdres: 'X', yaziciAdi: 'POS-58'), fis.satirlar(32)),
        throwsA(isA<YaziciHatasi>().having((e) => e.mesaj, 'mesaj', contains('POS-58'))),
      );
    });
  });

  group('sutFisiOlustur', () {
    late Database db;
    late Cari ali;
    setUp(() async {
      db = await testVeritabaniAc();
      final id = await cariEkle(db, ad: 'Ali', soyad: 'Kaya');
      ali = Cari(id: id, ad: 'Ali', soyad: 'Kaya', telefon: '05551234567');
      for (final (t, s, a) in [
        ('2026-10-31', 99.0, 0.0), // önceki ay
        ('2026-11-01', 10.0, 12.0),
        ('2026-11-03', 20.0, 18.5),
        ('2026-11-05', 50.0, 0.0), // fiş tarihinden sonra
      ]) {
        await db.insert('sutler', {'cari_id': id, 'tarih': t, 'sabah': s, 'aksam': a, 'toplam': s + a});
      }
    });
    tearDown(() => db.close());

    test('o günün kaydı ve ay başından o güne toplam', () async {
      final f = await sutFisiOlustur(SutRepository(db), cari: ali, tarih: '2026-11-03', isletmeAdi: 'X');
      expect(f!.sabah, 20);
      expect(f.aksam, 18.5);
      expect(f.toplam, 38.5);
      expect(f.buAyKg, 60.5); // 22 + 38,5
      expect(f.ureticiAdi, 'Ali Kaya');
      expect(f.fisNo, isNotNull);
    });

    test('kayıt yoksa null', () async {
      expect(await sutFisiOlustur(SutRepository(db), cari: ali, tarih: '2026-11-02', isletmeAdi: 'X'), isNull);
    });
  });
}
