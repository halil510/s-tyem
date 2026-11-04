import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sutyem_pro/data/repositories/terazi_cihaz_repository.dart';
import 'package:sutyem_pro/features/terazi/services/terazi_veri_cozucu.dart';
import 'package:sutyem_pro/models/terazi_cihaz_model.dart';

import '../helpers/test_db.dart';

void main() {
  group('agirlikCoz (tek satır)', () {
    final ornekler = <String, double?>{
      'ST,GS,+0025.40kg': 25.40,
      'US,NT,-0001.20kg': -1.20,
      '  42.5 kg': 42.5,
      'W: 7,25 kg': 7.25,
      '001 0033.60': 33.60, // eskiden 10033 okunuyordu
      'NET 0015.20 kg': 15.20,
      '12500 g': 12.5,
      '25.40 gross': 25.40, // "gross" gram değil
      'ww000.000kg': 0,
      '0025': 25,
      'OL': null, // aşırı yük
      'ST': null,
      '': null,
    };
    ornekler.forEach((satir, beklenen) {
      test('"$satir" → $beklenen', () {
        final kg = TeraziVeriCozucu.agirlikCoz(satir);
        if (beklenen == null) {
          expect(kg, isNull);
        } else {
          expect(kg, closeTo(beklenen, 1e-9));
        }
      });
    });
  });

  group('parça parça akış', () {
    test('bölünen satır birleşir, ara değer üretilmez', () {
      final gelen = <double>[];
      final c = TeraziVeriCozucu(gelen.add);
      c.ekle('ST,GS,+0012');
      c.ekle('.80kg\r');
      c.ekle('\n');
      expect(gelen, [12.80]);
      c.sifirla();
    });

    test('bir pakette birden çok satır → yalnız sonuncusu', () {
      final gelen = <double>[];
      final c = TeraziVeriCozucu(gelen.add);
      c.ekle('+0020.10kg\r\n+0020.20kg\r\n+0020.30kg\r\n+00');
      expect(gelen, [20.30]);
      c.sifirla();
    });

    test('satır sonu göndermeyen terazi: kısa sessizlikten sonra okunur', () {
      fakeAsync((zaman) {
        final gelen = <double>[];
        final c = TeraziVeriCozucu(gelen.add);
        c.ekle('+0031');
        zaman.elapse(const Duration(milliseconds: 50));
        c.ekle('.05kg'); // devamı geldi, süre yeniden başlar
        zaman.elapse(const Duration(milliseconds: 150));
        expect(gelen, isEmpty, reason: 'henüz sessizlik süresi dolmadı');
        zaman.elapse(const Duration(milliseconds: 100));
        expect(gelen, [31.05]);
      });
    });

    test('anlamsız satır son tartıyı silmez (0.00 basılmaz)', () {
      final gelen = <double>[];
      final c = TeraziVeriCozucu(gelen.add);
      c.ekle('+0025.40kg\r\nOL\r\nST\r\n');
      expect(gelen, [25.40], reason: 'en son ÇÖZÜLEBİLEN satır');
      c.ekle('OL\r\n');
      expect(gelen, [25.40]);
      c.sifirla();
    });
  });

  test('REGRESYON: yeni teraziye ilk bağlanışta aynı anda iki kayıt → UNIQUE hatası yok', () async {
    final db = await testVeritabaniAc();
    final repo = TeraziCihazRepository(db);
    TeraziCihazi cihaz() => TeraziCihazi(
        cihazAdi: 'Sanal', cihazAdresi: '192.168.1.50', baglantiTuru: TeraziBaglantiTuru.wifi, port: 9100);
    await Future.wait([repo.kaydetVeyaGuncelle(cihaz()), repo.kaydetVeyaGuncelle(cihaz())]);
    expect(await repo.getAll(), hasLength(1));
    await db.close();
  });
}
