import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/repositories/sut_repository.dart';
import '../../models/cari_model.dart';
import 'uretici_fisi.dart';

/// Fiş yazıcısına nasıl bağlanılır.
enum YaziciBaglantisi { bluetooth, wifi }

/// Fiş yazıcısı ayarları (cihazda saklanır). Kaydedilen yazıcı, kullanıcı
/// ayarlardan bilerek "Değiştir" demedikçe değişmez.
class FisAyarlari {
  final YaziciBaglantisi baglanti;

  /// Bluetooth: eşleşmiş yazıcının MAC adresi ve adı.
  final String? yaziciAdres;
  final String? yaziciAdi;

  /// Wi-Fi / ağ: yazıcının IP adresi (ya da ağ adı) ve portu (termal yazıcılarda 9100).
  final String? wifiAdres;
  final int wifiPort;

  /// Satırdaki karakter sayısı: 32 (58 mm), 40 (80 mm — varsayılan) veya 48 (80 mm geniş).
  final int genislik;
  final String isletmeAdi;
  final bool turkceKodSayfasi;

  const FisAyarlari({
    this.baglanti = YaziciBaglantisi.bluetooth,
    this.yaziciAdres,
    this.yaziciAdi,
    this.wifiAdres,
    this.wifiPort = varsayilanPort,
    this.genislik = 40,
    this.isletmeAdi = '',
    this.turkceKodSayfasi = false,
  });

  static const gecerliGenislikler = [32, 40, 48];
  static const varsayilanPort = 9100;

  bool get yaziciSecili => switch (baglanti) {
        YaziciBaglantisi.bluetooth => yaziciAdres != null && yaziciAdres!.isNotEmpty,
        YaziciBaglantisi.wifi => gecerliAgAdresi(wifiAdres),
      };

  /// Kullanıcıya gösterilecek kısa ad: "POS-80 (Bluetooth)" / "192.168.1.50:9100 (Wi-Fi)".
  String get yaziciEtiketi => switch (baglanti) {
        YaziciBaglantisi.bluetooth => '${yaziciAdi ?? yaziciAdres ?? '-'} (Bluetooth)',
        YaziciBaglantisi.wifi => '${wifiAdres ?? '-'}:$wifiPort (Wi-Fi)',
      };

  /// IPv4 adresi ya da boşluksuz ağ adı.
  static bool gecerliAgAdresi(String? s) {
    final a = s?.trim() ?? '';
    if (a.isEmpty || a.contains(' ')) return false;
    final ip = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(a);
    if (ip != null) return [1, 2, 3, 4].every((i) => int.parse(ip.group(i)!) <= 255);
    if (RegExp(r'^[\d.]+$').hasMatch(a)) return false; // eksik/bozuk IP (ör. 192.168.1)
    return RegExp(r'^[A-Za-z0-9][A-Za-z0-9.-]*$').hasMatch(a);
  }

  static const _adres = 'fis_yazici_adres',
      _ad = 'fis_yazici_adi',
      _baglanti = 'fis_yazici_baglanti',
      _wifiAdres = 'fis_yazici_wifi_adres',
      _wifiPort = 'fis_yazici_wifi_port',
      _genislik = 'fis_genislik',
      _isletme = 'fis_isletme_adi',
      _turkce = 'fis_turkce_kod_sayfasi';

  static Future<FisAyarlari> yukle() async {
    final p = await SharedPreferences.getInstance();
    final port = p.getInt(_wifiPort);
    return FisAyarlari(
      baglanti: p.getString(_baglanti) == 'wifi' ? YaziciBaglantisi.wifi : YaziciBaglantisi.bluetooth,
      yaziciAdres: p.getString(_adres),
      yaziciAdi: p.getString(_ad),
      wifiAdres: p.getString(_wifiAdres),
      wifiPort: port != null && port > 0 && port <= 65535 ? port : varsayilanPort,
      genislik: gecerliGenislikler.contains(p.getInt(_genislik)) ? p.getInt(_genislik)! : 40,
      isletmeAdi: p.getString(_isletme) ?? '',
      turkceKodSayfasi: p.getBool(_turkce) ?? false,
    );
  }

  Future<void> kaydet() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_baglanti, baglanti.name);
    if (yaziciAdres != null && yaziciAdres!.isNotEmpty) {
      await p.setString(_adres, yaziciAdres!);
      await p.setString(_ad, yaziciAdi ?? yaziciAdres!);
    } else {
      await p.remove(_adres);
      await p.remove(_ad);
    }
    if (gecerliAgAdresi(wifiAdres)) {
      await p.setString(_wifiAdres, wifiAdres!.trim());
    } else {
      await p.remove(_wifiAdres);
    }
    await p.setInt(_wifiPort, wifiPort);
    await p.setInt(_genislik, genislik);
    await p.setString(_isletme, isletmeAdi.trim());
    await p.setBool(_turkce, turkceKodSayfasi);
  }

  FisAyarlari kopyala({
    YaziciBaglantisi? baglanti,
    String? yaziciAdres,
    String? yaziciAdi,
    String? wifiAdres,
    int? wifiPort,
    int? genislik,
    String? isletmeAdi,
    bool? turkceKodSayfasi,
  }) =>
      FisAyarlari(
        baglanti: baglanti ?? this.baglanti,
        yaziciAdres: yaziciAdres ?? this.yaziciAdres,
        yaziciAdi: yaziciAdi ?? this.yaziciAdi,
        wifiAdres: wifiAdres ?? this.wifiAdres,
        wifiPort: wifiPort ?? this.wifiPort,
        genislik: genislik ?? this.genislik,
        isletmeAdi: isletmeAdi ?? this.isletmeAdi,
        turkceKodSayfasi: turkceKodSayfasi ?? this.turkceKodSayfasi,
      );
}

class YaziciHatasi implements Exception {
  final String mesaj;
  const YaziciHatasi(this.mesaj);
  @override
  String toString() => mesaj;
}

/// Termal yazıcıya ESC/POS baytlarını gönderir.
/// - Bluetooth: Android `TermalYazici.kt` (terazinin bağlantısından bağımsız).
/// - Wi-Fi / ağ: yazıcının IP:9100 portuna doğrudan TCP (ek paket gerekmez).
/// Her fiş için bağlanır, yazar, bağlantıyı kapatır; aynı anda tek fiş basılır.
class TermalYaziciServisi {
  static const _kanal = MethodChannel('termal_yazici');
  static const zamanAsimi = Duration(seconds: 6);
  static bool _mesgul = false;

  static Future<void> yazdir(FisAyarlari ayar, List<FisSatiri> satirlar) async {
    if (!ayar.yaziciSecili) throw const YaziciHatasi('Önce fiş yazıcısını seçin.');
    final baytlar = EscPos.fis(satirlar, turkceKodSayfasi: ayar.turkceKodSayfasi);
    if (ayar.baglanti == YaziciBaglantisi.wifi) {
      if (_mesgul) throw const YaziciHatasi('Yazıcı önceki fişi yazdırıyor, birazdan tekrar deneyin.');
      _mesgul = true;
      try {
        await _agaGonder(ayar.wifiAdres!.trim(), ayar.wifiPort, baytlar);
      } finally {
        _mesgul = false;
      }
      return;
    }
    try {
      await _kanal.invokeMethod<bool>('yazdir', {
        'address': ayar.yaziciAdres,
        'bytes': Uint8List.fromList(baytlar),
      });
    } on PlatformException catch (e) {
      throw YaziciHatasi(switch (e.code) {
        'MESGUL' => 'Yazıcı önceki fişi yazdırıyor, birazdan tekrar deneyin.',
        'IZIN' => 'Bluetooth izni verilmemiş.',
        _ => 'Yazıcıya bağlanılamadı (${ayar.yaziciAdi ?? ayar.yaziciAdres}). '
            'Yazıcı açık ve eşleştirilmiş mi?',
      });
    } on MissingPluginException {
      throw const YaziciHatasi('Fiş yazdırma bu cihazda desteklenmiyor.');
    }
  }

  /// Wi-Fi yazıcıya yalnız bağlanıp kapatır (kâğıt harcamadan "ulaşılıyor mu?").
  static Future<void> wifiTest(String adres, int port) async {
    final s = await _baglan(adres, port);
    s.destroy();
  }

  static Future<Socket> _baglan(String adres, int port) async {
    try {
      return await Socket.connect(adres, port, timeout: zamanAsimi);
    } on SocketException {
      throw YaziciHatasi('Yazıcıya ağdan ulaşılamadı ($adres:$port). Yazıcı açık mı, '
          'telefon ve yazıcı AYNI Wi-Fi ağında mı, IP adresi doğru mu?');
    } on TimeoutException {
      throw YaziciHatasi('Yazıcı yanıt vermedi ($adres:$port).');
    }
  }

  static Future<void> _agaGonder(String adres, int port, List<int> baytlar) async {
    final s = await _baglan(adres, port);
    try {
      s.add(baytlar);
      await s.flush().timeout(zamanAsimi);
    } catch (_) {
      throw YaziciHatasi('Fiş gönderilirken bağlantı koptu ($adres:$port).');
    } finally {
      try {
        await s.close().timeout(const Duration(seconds: 2));
      } catch (_) {}
      s.destroy();
    }
  }
}

/// Bir carinin bir günlük süt kaydından fiş üretir; o gün kayıt yoksa null.
Future<UreticiFisi?> sutFisiOlustur(
  SutRepository repo, {
  required Cari cari,
  required String tarih, // yyyy-MM-dd
  required String isletmeAdi,
  DateTime? simdi,
}) async {
  final kayit = await repo.getGunluk(cari.id!, tarih);
  if (kayit == null) return null;
  final buAy = await repo.toplamCari(cari.id!, '${tarih.substring(0, 7)}-01', tarih);
  return UreticiFisi(
    isletmeAdi: isletmeAdi,
    fisNo: kayit.id,
    tarih: DateFormat('yyyy-MM-dd').parse(tarih),
    basimZamani: simdi ?? DateTime.now(),
    ureticiAdi: '${cari.ad} ${cari.soyad}',
    sabah: kayit.sabah,
    aksam: kayit.aksam,
    buAyKg: buAy,
  );
}
