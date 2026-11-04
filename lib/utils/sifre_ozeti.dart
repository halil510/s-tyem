import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Şifreyi geri çevrilemez, yavaş bir özete dönüştürür
/// (PBKDF2-HMAC-SHA256, RFC 8018). Kaynak kodda yalnızca bu özet ve tuz
/// durur; şifrenin kendisi asla yazılmaz.
///
/// [tur] yüksek tutulur ki özet ele geçse bile tahmin denemesi pahalı olsun.
String sifreOzeti(String sifre, String tuz, {int tur = 120000, int uzunluk = 32}) {
  final hmac = Hmac(sha256, utf8.encode(sifre));
  final tuzBaytlari = utf8.encode(tuz);
  final cikti = BytesBuilder();
  var blok = 1;
  while (cikti.length < uzunluk) {
    final ilk = Uint8List(tuzBaytlari.length + 4)
      ..setAll(0, tuzBaytlari)
      ..buffer.asByteData().setUint32(tuzBaytlari.length, blok);
    var u = hmac.convert(ilk).bytes;
    final t = Uint8List.fromList(u);
    for (var i = 1; i < tur; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    cikti.add(t);
    blok++;
  }
  return _hex(cikti.toBytes().sublist(0, uzunluk));
}

/// Sabit zamanlı karşılaştırma: eşleşmeyen karakterin konumu, cevap
/// süresinden anlaşılamaz.
bool sifreOzetiEsitMi(String sifre, String tuz, String beklenenOzet, {int tur = 120000}) {
  final ozet = sifreOzeti(sifre, tuz, tur: tur, uzunluk: beklenenOzet.length ~/ 2);
  if (ozet.length != beklenenOzet.length) return false;
  var fark = 0;
  for (var i = 0; i < ozet.length; i++) {
    fark |= ozet.codeUnitAt(i) ^ beklenenOzet.toLowerCase().codeUnitAt(i);
  }
  return fark == 0;
}

String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
