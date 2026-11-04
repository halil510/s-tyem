import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sutyem_pro/utils/app_locker.dart';
import 'package:sutyem_pro/utils/sifre_ozeti.dart';

void main() {
  group('sifreOzeti (PBKDF2-HMAC-SHA256)', () {
    // Yaygın kullanılan PBKDF2-HMAC-SHA256 test vektörleri.
    test('bilinen vektörler', () {
      expect(sifreOzeti('password', 'salt', tur: 1),
          '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b');
      expect(sifreOzeti('password', 'salt', tur: 2),
          'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43');
      expect(sifreOzeti('password', 'salt', tur: 4096),
          'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a');
      expect(
        sifreOzeti('passwordPASSWORDpassword', 'saltSALTsaltSALTsaltSALTsaltSALTsalt',
            tur: 4096, uzunluk: 40),
        '348c89dbcbd32b2f32d814b8116e84cf2b17347ebc1800181c4e2a1fb8dd53e1c635518c7dac47e9',
      );
    });

    test('doğru şifre eşleşir, en küçük fark eşleşmez', () {
      final ozet = sifreOzeti('Süt-2026!', 'tuz', tur: 1000);
      expect(sifreOzetiEsitMi('Süt-2026!', 'tuz', ozet, tur: 1000), isTrue);
      expect(sifreOzetiEsitMi('süt-2026!', 'tuz', ozet, tur: 1000), isFalse);
      expect(sifreOzetiEsitMi('Süt-2026! ', 'tuz', ozet, tur: 1000), isFalse);
      expect(sifreOzetiEsitMi('Süt-2026!', 'tuz2', ozet, tur: 1000), isFalse);
      expect(sifreOzetiEsitMi('', 'tuz', ozet, tur: 1000), isFalse);
    });
  });

  group('AppLocker', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('yanlış aktivasyon şifresi reddedilir, uygulama aktifleşmez', () async {
      final locker = AppLocker();
      final sonuc = await locker.activateApp('yanlis-sifre', 'Test');
      expect(sonuc['success'], isFalse);
      expect(await locker.isAppActivated(), isFalse);
    });

    test('5 hatalı denemede kilitlenir', () async {
      final locker = AppLocker();
      Map<String, dynamic> son = {};
      for (var i = 0; i < 5; i++) {
        son = await locker.verifyPassword('yanlis-$i');
      }
      expect(son['locked'], isTrue);
      expect(await locker.isAppLocked(), isTrue);
      await locker.unlockApp();
    });

    test('kullanılan şifre bilgisi şifrenin hiçbir parçasını göstermez', () async {
      expect(await AppLocker().getUsedPassword(), 'Master şifre');
    });

    test('kaynak kodda açık şifre yok, yalnızca özet', () {
      final kaynak = File('lib/utils/app_locker.dart').readAsStringSync();
      expect(kaynak, isNot(contains('_defaultMasterPassword')));
      expect(kaynak, isNot(contains('_userPasswords')));
      expect(RegExp(r"_masterOzet = '[0-9a-f]{64}'").hasMatch(kaynak), isTrue);
    });
  });
}
