import 'package:flutter_test/flutter_test.dart';
import 'package:sutyem_pro/utils/sayi_format.dart';

void main() {
  group('sayiCoz', () {
    test('boş giriş 0 kabul edilir', () {
      expect(sayiCoz(''), 0);
      expect(sayiCoz('   '), 0);
    });

    test('virgül ve nokta ondalık ayırıcıdır', () {
      expect(sayiCoz('12,5'), 12.5);
      expect(sayiCoz('12.5'), 12.5);
      expect(sayiCoz(' 40 '), 40);
      expect(sayiCoz(',5'), 0.5);
      expect(sayiCoz('12.'), 12);
    });

    test('Türk usulü binlik ayırıcı', () {
      expect(sayiCoz('1.250,5'), 1250.5);
      expect(sayiCoz('12.345.678,25'), 12345678.25);
    });

    test('geçersiz girişler 0 DEĞİL null döner (sessiz veri kaybı yok)', () {
      for (final hatali in ['12,5x', 'abc', '1.2.3', '1,2,3', '-5', '1e5', '1,250.5', '--', '.']) {
        expect(sayiCoz(hatali), isNull, reason: '"$hatali" reddedilmeli');
      }
    });
  });

  group('kurusaYuvarla', () {
    test('kayan nokta artıklarını temizler', () {
      expect(kurusaYuvarla(0.1 + 0.2), 0.3);
      expect(kurusaYuvarla(12.345), 12.35);
      expect(kurusaYuvarla(-12.345), -12.35);
      expect(kurusaYuvarla(37.5 * 18.75), 703.13);
    });
  });

  group('sayiGoster', () {
    test('gereksiz sıfır göstermez', () {
      expect(sayiGoster(12), '12');
      expect(sayiGoster(12.5), '12.5');
      expect(sayiGoster(12.25), '12.25');
      expect(sayiGoster(12.340000000000001), '12.34');
      expect(sayiGoster(0), '0');
    });

    test('REGRESYON: toplam tek haneye yuvarlanmaz (47.8 + 30.54 = 78.34)', () {
      expect(sayiGoster(47.8 + 30.54), '78.34');
      expect(sayiGoster(12.0001), '12', reason: 'eskiden "12.0" çıkıyordu; kayan nokta artığı gizlenir');
      expect(sayiGoster(25.0), '25');
      expect(sayiGoster(-0.0001), '0');
      // 2026-11-13: gerçek 3 haneli kg (terazi 12,345) artık 2 haneye yuvarlanmaz.
      expect(sayiGoster(12.345), '12.345');
      expect(sayiGirdi(12.345), '12,345');
      expect(sayiCoz(sayiGirdi(12.345)), 12.345, reason: 'kutuya geri yazılan değer birebir aynı okunur');
      expect(sayiCoz(sayiGirdi(1500)), 1500);
    });
  });
}
