import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:usb_serial/usb_serial.dart';

import '../../data/repositories/sut_repository.dart';
import '../../models/cari_model.dart';
import 'uretici_fisi.dart';

/// Fiş yazıcısına nasıl bağlanılır.
enum YaziciBaglantisi { bluetooth, wifi, usb }

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

  /// USB (OTG kablo): yazıcının üretici/ürün kimliği (VID/PID) ve adı.
  final int? usbVid;
  final int? usbPid;
  final String? usbAd;

  /// Satırdaki karakter sayısı: 32 (58 mm), 40 (80 mm — varsayılan) veya 48 (80 mm geniş).
  final int genislik;
  final String isletmeAdi;
  final String isletmeTelefon;
  final String isletmeAdres;

  /// Fişin en altındaki yazı (boşsa yazılmaz).
  final String altYazi;
  final bool turkceKodSayfasi;

  /// Her fişten kaç kopya basılır (1–5; ör. biri üreticiye, biri işletmeye).
  final int kopya;

  /// Fiş sonunda kâğıt kaç satır ilerletilir (0–10; kesici ya da yırtma hizası için).
  final int besleme;

  /// Yazıcının kesicisi varsa fiş sonunda kâğıdı keser.
  final bool kesici;

  /// Süt kaydedip "Fiş" denince fiş önizlemesiz doğrudan basılır.
  final bool otomatikYazdir;

  const FisAyarlari({
    this.baglanti = YaziciBaglantisi.bluetooth,
    this.yaziciAdres,
    this.yaziciAdi,
    this.wifiAdres,
    this.wifiPort = varsayilanPort,
    this.usbVid,
    this.usbPid,
    this.usbAd,
    this.genislik = 40,
    this.isletmeAdi = '',
    this.isletmeTelefon = '',
    this.isletmeAdres = '',
    this.altYazi = varsayilanAltYazi,
    this.turkceKodSayfasi = false,
    this.kopya = 1,
    this.besleme = varsayilanBesleme,
    this.kesici = true,
    this.otomatikYazdir = false,
  });

  static const gecerliGenislikler = [32, 40, 48];
  static const varsayilanPort = 9100;
  static const varsayilanAltYazi = 'Teşekkür ederiz';
  static const varsayilanBesleme = 4;

  bool get yaziciSecili => switch (baglanti) {
        YaziciBaglantisi.bluetooth => yaziciAdres != null && yaziciAdres!.isNotEmpty,
        YaziciBaglantisi.wifi => gecerliAgAdresi(wifiAdres),
        YaziciBaglantisi.usb => usbVid != null && usbPid != null,
      };

  /// Kullanıcıya gösterilecek kısa ad: "POS-80 (Bluetooth)" / "192.168.1.50:9100 (Wi-Fi)" / "XP-58 (USB)".
  String get yaziciEtiketi => switch (baglanti) {
        YaziciBaglantisi.bluetooth => '${yaziciAdi ?? yaziciAdres ?? '-'} (Bluetooth)',
        YaziciBaglantisi.wifi => '${wifiAdres ?? '-'}:$wifiPort (Wi-Fi)',
        YaziciBaglantisi.usb => '${usbAd ?? 'USB yazıcı'} (USB)',
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
      _usbVid = 'fis_yazici_usb_vid',
      _usbPid = 'fis_yazici_usb_pid',
      _usbAd = 'fis_yazici_usb_ad',
      _genislik = 'fis_genislik',
      _isletme = 'fis_isletme_adi',
      _isletmeTel = 'fis_isletme_telefon',
      _isletmeAdres = 'fis_isletme_adres',
      _altYazi = 'fis_alt_yazi',
      _turkce = 'fis_turkce_kod_sayfasi',
      _kopya = 'fis_kopya',
      _besleme = 'fis_besleme',
      _kesici = 'fis_kesici',
      _otomatik = 'fis_otomatik_yazdir';

  static Future<FisAyarlari> yukle() async {
    final p = await SharedPreferences.getInstance();
    final port = p.getInt(_wifiPort);
    return FisAyarlari(
      baglanti: switch (p.getString(_baglanti)) {
        'wifi' => YaziciBaglantisi.wifi,
        'usb' => YaziciBaglantisi.usb,
        _ => YaziciBaglantisi.bluetooth,
      },
      yaziciAdres: p.getString(_adres),
      yaziciAdi: p.getString(_ad),
      wifiAdres: p.getString(_wifiAdres),
      wifiPort: port != null && port > 0 && port <= 65535 ? port : varsayilanPort,
      usbVid: p.getInt(_usbVid),
      usbPid: p.getInt(_usbPid),
      usbAd: p.getString(_usbAd),
      genislik: gecerliGenislikler.contains(p.getInt(_genislik)) ? p.getInt(_genislik)! : 40,
      isletmeAdi: p.getString(_isletme) ?? '',
      isletmeTelefon: p.getString(_isletmeTel) ?? '',
      isletmeAdres: p.getString(_isletmeAdres) ?? '',
      altYazi: p.getString(_altYazi) ?? varsayilanAltYazi,
      turkceKodSayfasi: p.getBool(_turkce) ?? false,
      kopya: (p.getInt(_kopya) ?? 1).clamp(1, 5),
      besleme: (p.getInt(_besleme) ?? varsayilanBesleme).clamp(0, 10),
      kesici: p.getBool(_kesici) ?? true,
      otomatikYazdir: p.getBool(_otomatik) ?? false,
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
    if (usbVid != null && usbPid != null) {
      await p.setInt(_usbVid, usbVid!);
      await p.setInt(_usbPid, usbPid!);
      await p.setString(_usbAd, usbAd ?? 'USB yazıcı');
    } else {
      await p.remove(_usbVid);
      await p.remove(_usbPid);
      await p.remove(_usbAd);
    }
    await p.setInt(_genislik, genislik);
    await p.setString(_isletme, isletmeAdi.trim());
    await p.setString(_isletmeTel, isletmeTelefon.trim());
    await p.setString(_isletmeAdres, isletmeAdres.trim());
    await p.setString(_altYazi, altYazi.trim());
    await p.setBool(_turkce, turkceKodSayfasi);
    await p.setInt(_kopya, kopya.clamp(1, 5));
    await p.setInt(_besleme, besleme.clamp(0, 10));
    await p.setBool(_kesici, kesici);
    await p.setBool(_otomatik, otomatikYazdir);
  }

  FisAyarlari kopyala({
    YaziciBaglantisi? baglanti,
    String? yaziciAdres,
    String? yaziciAdi,
    String? wifiAdres,
    int? wifiPort,
    int? usbVid,
    int? usbPid,
    String? usbAd,
    int? genislik,
    String? isletmeAdi,
    String? isletmeTelefon,
    String? isletmeAdres,
    String? altYazi,
    bool? turkceKodSayfasi,
    int? kopya,
    int? besleme,
    bool? kesici,
    bool? otomatikYazdir,
  }) =>
      FisAyarlari(
        baglanti: baglanti ?? this.baglanti,
        yaziciAdres: yaziciAdres ?? this.yaziciAdres,
        yaziciAdi: yaziciAdi ?? this.yaziciAdi,
        wifiAdres: wifiAdres ?? this.wifiAdres,
        wifiPort: wifiPort ?? this.wifiPort,
        usbVid: usbVid ?? this.usbVid,
        usbPid: usbPid ?? this.usbPid,
        usbAd: usbAd ?? this.usbAd,
        genislik: genislik ?? this.genislik,
        isletmeAdi: isletmeAdi ?? this.isletmeAdi,
        isletmeTelefon: isletmeTelefon ?? this.isletmeTelefon,
        isletmeAdres: isletmeAdres ?? this.isletmeAdres,
        altYazi: altYazi ?? this.altYazi,
        turkceKodSayfasi: turkceKodSayfasi ?? this.turkceKodSayfasi,
        kopya: kopya ?? this.kopya,
        besleme: besleme ?? this.besleme,
        kesici: kesici ?? this.kesici,
        otomatikYazdir: otomatikYazdir ?? this.otomatikYazdir,
      );
}

class YaziciHatasi implements Exception {
  final String mesaj;
  const YaziciHatasi(this.mesaj);
  @override
  String toString() => mesaj;
}

/// Telefona takılı USB cihaz (yazıcı seçimi için).
class UsbYazici {
  final int vid;
  final int pid;
  final String ad;
  const UsbYazici({required this.vid, required this.pid, required this.ad});
}

/// Termal yazıcıya ESC/POS baytlarını gönderir.
/// - Bluetooth: Android `TermalYazici.kt` (terazinin bağlantısından bağımsız).
/// - Wi-Fi / ağ: yazıcının IP:9100 portuna doğrudan TCP.
/// - USB (OTG): Android USB Host — CDC/FTDI/CH34x/CP210x seri yazıcılar (Fırın ERP'deki usb_serial).
/// Her fiş için bağlanır, yazar, bağlantıyı kapatır; aynı anda tek fiş basılır.
class TermalYaziciServisi {
  static const _kanal = MethodChannel('termal_yazici');
  static const zamanAsimi = Duration(seconds: 6);
  static bool _mesgul = false;

  /// Fişin yazıcıya giden baytları (kopya sayısı, besleme ve kesici ayarlarıyla).
  static List<int> baytlar(FisAyarlari ayar, List<FisSatiri> satirlar) {
    final tek = EscPos.fis(satirlar, turkceKodSayfasi: ayar.turkceKodSayfasi, kes: ayar.kesici, besleme: ayar.besleme);
    return [for (var i = 0; i < ayar.kopya.clamp(1, 5); i++) ...tek];
  }

  static Future<void> yazdir(FisAyarlari ayar, List<FisSatiri> satirlar) async {
    if (!ayar.yaziciSecili) throw const YaziciHatasi('Önce fiş yazıcısını seçin.');
    final b = baytlar(ayar, satirlar);
    if (ayar.baglanti == YaziciBaglantisi.wifi || ayar.baglanti == YaziciBaglantisi.usb) {
      if (_mesgul) throw const YaziciHatasi('Yazıcı önceki fişi yazdırıyor, birazdan tekrar deneyin.');
      _mesgul = true;
      try {
        if (ayar.baglanti == YaziciBaglantisi.wifi) {
          await _agaGonder(ayar.wifiAdres!.trim(), ayar.wifiPort, b);
        } else {
          await _usbGonder(ayar.usbVid!, ayar.usbPid!, ayar.usbAd, b);
        }
      } finally {
        _mesgul = false;
      }
      return;
    }
    try {
      await _kanal.invokeMethod<bool>('yazdir', {
        'address': ayar.yaziciAdres,
        'bytes': Uint8List.fromList(b),
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

  // ── USB ──

  /// Telefona takılı USB cihazlar (OTG kablosuyla). Android dışında boş.
  static Future<List<UsbYazici>> usbCihazlari() async {
    if (!Platform.isAndroid) return const [];
    try {
      final l = await UsbSerial.listDevices();
      return [
        for (final d in l)
          if (d.vid != null && d.pid != null)
            () {
              final ad = [d.manufacturerName, d.productName].whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty).join(' ');
              return UsbYazici(vid: d.vid!, pid: d.pid!, ad: ad.isEmpty ? 'USB cihaz (${_hex(d.vid!)}:${_hex(d.pid!)})' : ad);
            }(),
      ];
    } on MissingPluginException {
      return const [];
    } on PlatformException catch (e) {
      throw YaziciHatasi('USB cihazlar okunamadı: ${e.message}');
    }
  }

  static String _hex(int v) => v.toRadixString(16).padLeft(4, '0').toUpperCase();

  static Future<void> _usbGonder(int vid, int pid, String? ad, List<int> baytlar) async {
    final List<UsbDevice> l;
    try {
      l = await UsbSerial.listDevices();
    } on MissingPluginException {
      throw const YaziciHatasi('USB yazdırma bu cihazda desteklenmiyor.');
    }
    final cihaz = l.where((d) => d.vid == vid && d.pid == pid).firstOrNull;
    if (cihaz == null) {
      throw YaziciHatasi('USB yazıcı (${ad ?? 'kayıtlı yazıcı'}) takılı değil. OTG kablosunu ve yazıcının açık olduğunu kontrol edin.');
    }
    final port = await cihaz.create();
    if (port == null) throw const YaziciHatasi('USB yazıcıyla bağlantı kurulamadı (bu model desteklenmiyor olabilir).');
    try {
      // Android ilk seferde "bu cihaza izin ver" sorar; reddedilirse açılmaz.
      if (!await port.open()) throw const YaziciHatasi('USB yazıcıya izin verilmedi. Çıkan pencerede "İzin ver"e dokunun.');
      await port.setDTR(true);
      await port.setRTS(true);
      await port.setPortParameters(9600, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);
      await port.write(Uint8List.fromList(baytlar)).timeout(const Duration(seconds: 12),
          onTimeout: () => throw const YaziciHatasi('USB yazıcıya veri gönderilemedi (zaman aşımı).'));
    } finally {
      try {
        await port.close();
      } catch (_) {}
    }
  }
}

/// Bir carinin bir günlük süt kaydından fiş üretir; o gün kayıt yoksa null.
Future<UreticiFisi?> sutFisiOlustur(
  SutRepository repo, {
  required Cari cari,
  required String tarih, // yyyy-MM-dd
  required String isletmeAdi,
  FisAyarlari? ayar,
  DateTime? simdi,
}) async {
  final kayit = await repo.getGunluk(cari.id!, tarih);
  if (kayit == null) return null;
  final buAy = await repo.toplamCari(cari.id!, '${tarih.substring(0, 7)}-01', tarih);
  return UreticiFisi(
    isletmeAdi: isletmeAdi,
    isletmeTelefon: ayar?.isletmeTelefon ?? '',
    isletmeAdres: ayar?.isletmeAdres ?? '',
    altYazi: ayar?.altYazi ?? FisAyarlari.varsayilanAltYazi,
    fisNo: kayit.id,
    tarih: DateFormat('yyyy-MM-dd').parse(tarih),
    basimZamani: simdi ?? DateTime.now(),
    ureticiAdi: '${cari.ad} ${cari.soyad}',
    sabah: kayit.sabah,
    aksam: kayit.aksam,
    buAyKg: buAy,
  );
}
