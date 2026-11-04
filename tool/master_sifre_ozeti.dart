// Yeni master (aktivasyon) şifresi için kaynak koda yazılacak tuz ve
// özeti üretir. Şifrenin kendisi hiçbir yere kaydedilmez.
//
// Kullanım (proje klasöründe):
//   dart run tool/master_sifre_ozeti.dart
//
// Çıkan iki satırı lib/utils/app_locker.dart içindeki `_masterTuz` ve
// `_masterOzet` sabitlerinin yerine yapıştırın, sonra yeni APK derleyin.
import 'dart:io';
import 'dart:math';

import 'package:sutyem_pro/utils/sifre_ozeti.dart';

void main() {
  final sifre = _gizliOku('Yeni master şifre: ');
  if (sifre.length < 8) {
    stderr.writeln('Şifre en az 8 karakter olmalı.');
    exit(1);
  }
  if (_gizliOku('Tekrar: ') != sifre) {
    stderr.writeln('Şifreler aynı değil.');
    exit(1);
  }

  final rnd = Random.secure();
  final tuz = List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  final ozet = sifreOzeti(sifre, tuz);

  stdout.writeln('\nlib/utils/app_locker.dart içine yapıştırın:\n');
  stdout.writeln("  static const String _masterTuz = '$tuz';");
  stdout.writeln("  static const String _masterOzet = '$ozet';");
}

String _gizliOku(String istem) {
  stdout.write(istem);
  var gizlendi = false;
  try {
    stdin.echoMode = false;
    gizlendi = true;
  } catch (_) {
    // Bazı terminaller (ör. Git Bash) yankıyı kapatmayı desteklemez.
  }
  final satir = stdin.readLineSync() ?? '';
  if (gizlendi) {
    stdin.echoMode = true;
    stdout.writeln();
  }
  return satir.trim();
}
