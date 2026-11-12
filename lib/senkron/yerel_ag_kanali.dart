import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import 'senk_cekirdek.dart';

/// Yerel ağ (internetsiz) senkronunun portu.
const yerelAgPortu = 8767; // Fırın ERP 8766 kullanır; aynı WiFi'da karışmasın
const _uygulamaKodu = 'sutyem';

/// ─────────────────────────────────────────────────────────────
/// ANA CİHAZ (sunucu) — aynı WiFi'daki cihazlar buna bağlanır.
/// Market uygulamasındaki WiFi aktarımının dersiyle: eşleşme KODU olmadan
/// hiçbir veri verilmez/alınmaz (misafir WiFi'daki biri veriye erişemez).
/// ─────────────────────────────────────────────────────────────
class YerelAgSunucusu {
  HttpServer? _sunucu;
  String? ip;
  final _hataliDeneme = <String, int>{};
  final _engelliBitis = <String, DateTime>{};
  void Function(UygulamaSonucu)? degisti; // istemciden veri gelince (ekran yenilensin)

  bool get acik => _sunucu != null;

  Future<void> baslat({required Database db, required String cihaz, required String cihazAd, required String kod}) async {
    await durdur();
    _sunucu = await HttpServer.bind(InternetAddress.anyIPv4, yerelAgPortu, shared: true);
    ip = await yerelIp();
    _sunucu!.listen((istek) => _isle(istek, db, cihaz, cihazAd, kod), onError: (_) {});
  }

  Future<void> durdur() async {
    await _sunucu?.close(force: true);
    _sunucu = null;
  }

  Future<void> _isle(HttpRequest istek, Database db, String cihaz, String cihazAd, String kod) async {
    final cevap = istek.response..headers.contentType = ContentType.json;
    try {
      if (istek.method == 'GET' && istek.uri.path == '/bilgi') {
        // Keşif: veri içermez, yalnız "burada süt-yem ana cihazı var".
        cevap.write(jsonEncode({'uygulama': _uygulamaKodu, 'ad': cihazAd, 'cihaz': cihaz}));
        return;
      }
      if (istek.method != 'POST' || istek.uri.path != '/senk') {
        cevap.statusCode = HttpStatus.notFound;
        return;
      }
      // Deneme sınırı: bir adres 5 kez yanlış kod girerse 5 dakika engellenir
      // (6 haneli kod aksi halde dakikalar içinde denenerek bulunabilirdi).
      final ip = istek.connectionInfo?.remoteAddress.address ?? '?';
      final engel = _engelliBitis[ip];
      if (engel != null && DateTime.now().isBefore(engel)) {
        cevap.statusCode = HttpStatus.tooManyRequests;
        cevap.write(jsonEncode({'hata': 'Çok fazla hatalı deneme. 5 dakika sonra tekrar deneyin.'}));
        return;
      }
      if (istek.headers.value('x-sutyem-kod') != kod) {
        final n = (_hataliDeneme[ip] ?? 0) + 1;
        _hataliDeneme[ip] = n;
        if (n >= 5) {
          _engelliBitis[ip] = DateTime.now().add(const Duration(minutes: 5));
          _hataliDeneme.remove(ip);
        }
        cevap.statusCode = HttpStatus.forbidden;
        cevap.write(jsonEncode({'hata': 'Eşleşme kodu hatalı.'}));
        return;
      }
      _hataliDeneme.remove(ip);
      final govde = jsonDecode(await utf8.decoder.bind(istek).join()) as Map<String, dynamic>;
      final istemci = govde['cihaz'] as String;
      final kanal = 'lan:$istemci';
      final gelen = [for (final m in (govde['kayitlar'] as List)) SenkKayit.fromJson((m as Map).cast<String, Object?>())];
      final sonuc = await db.transaction((txn) => SenkCekirdek(txn).uygula(gelen, kanal: kanal));
      if (sonuc.uygulanan > 0) degisti?.call(sonuc);
      final c = SenkCekirdek(db);
      var sonra = (govde['son_cekilen'] as num?)?.toInt() ?? 0;
      final sunucuSon = await c.sonGunlukId();
      if (sonra > sunucuSon) sonra = 0; // ana cihazın veritabanı yenilenmiş: baştan
      final (giden, sonId) = await c.gonderilecekler(sonra: sonra, haricKaynak: kanal);
      cevap.write(jsonEncode({
        'kayitlar': [for (final k in giden) k.toJson()],
        'son_id': sonId,
        'sunucu_son': sunucuSon,
        'sunucu_cihaz': cihaz,
        'sunucu_ad': cihazAd,
        'uygulama': sonuc.toString(),
      }));
    } catch (e) {
      cevap.statusCode = HttpStatus.internalServerError;
      cevap.write(jsonEncode({'hata': e.toString()}));
    } finally {
      await cevap.close();
    }
  }
}

/// Bu cihazın yerel ağ IPv4 adresi (192.168.x / 10.x / 172.16-31.x).
Future<String?> yerelIp() async {
  try {
    for (final iface in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      for (final a in iface.addresses) {
        if (!a.isLoopback && _yerelMi(a.address)) return a.address;
      }
    }
  } catch (_) {}
  return null;
}

bool _yerelMi(String ip) {
  final p = ip.split('.').map(int.tryParse).toList();
  if (p.length != 4 || p.contains(null)) return false;
  return p[0] == 10 || (p[0] == 172 && p[1]! >= 16 && p[1]! <= 31) || (p[0] == 192 && p[1] == 168);
}

class AnaCihaz {
  final String adres;
  final String ad;
  final String cihaz;
  const AnaCihaz(this.adres, this.ad, this.cihaz);
}

/// ─────────────────────────────────────────────────────────────
/// İSTEMCİ — ana cihazı bulur ve onunla eşitler.
/// ─────────────────────────────────────────────────────────────
class YerelAgIstemcisi {
  /// Aynı ağdaki ana cihazları bulur (port 8766'da /bilgi cevaplayanlar).
  static Future<List<AnaCihaz>> tara() async {
    final ip = await yerelIp();
    if (ip == null) return [];
    final taban = ip.split('.').take(3).join('.');
    final bulunan = <AnaCihaz>[];
    final istemci = HttpClient()..connectionTimeout = const Duration(milliseconds: 700);
    await Future.wait([
      for (var i = 1; i <= 254; i++)
        () async {
          final adres = '$taban.$i';
          if (adres == ip) return;
          try {
            final r = await (await istemci.get(adres, yerelAgPortu, '/bilgi')).close().timeout(const Duration(milliseconds: 1500));
            final j = jsonDecode(await utf8.decoder.bind(r).join()) as Map;
            if (j['uygulama'] == _uygulamaKodu) bulunan.add(AnaCihaz(adres, (j['ad'] as String?) ?? adres, (j['cihaz'] as String?) ?? ''));
          } catch (_) {}
        }(),
    ]);
    istemci.close(force: true);
    return bulunan;
  }

  /// Bir tur: gönder + al (tek istek). Dönen: (alınan kayıtlar, yeni son_cekilen, sunucu cihaz kimliği).
  static Future<(List<SenkKayit>, int, int, String)> tur({
    required String adres,
    required String kod,
    required String cihaz,
    required int sonCekilen,
    required List<SenkKayit> giden,
  }) async {
    final istemci = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final rq = await istemci.post(adres, yerelAgPortu, '/senk');
      rq.headers.contentType = ContentType.json;
      rq.headers.set('x-sutyem-kod', kod);
      rq.add(utf8.encode(jsonEncode({
        'cihaz': cihaz,
        'son_cekilen': sonCekilen,
        'kayitlar': [for (final k in giden) k.toJson()]
      })));
      final r = await rq.close().timeout(const Duration(seconds: 60));
      final metin = await utf8.decoder.bind(r).join();
      final j = jsonDecode(metin) as Map<String, dynamic>;
      if (r.statusCode == HttpStatus.forbidden) throw const YerelAgHatasi('Eşleşme kodu hatalı. Ana cihazdaki kodu girin.');
      if (r.statusCode == HttpStatus.tooManyRequests) throw YerelAgHatasi('${j['hata']}');
      if (r.statusCode != HttpStatus.ok) throw YerelAgHatasi('Ana cihaz hatası: ${j['hata']}');
      return (
        [for (final m in (j['kayitlar'] as List)) SenkKayit.fromJson((m as Map).cast<String, Object?>())],
        (j['son_id'] as num).toInt(),
        (j['sunucu_son'] as num).toInt(),
        j['sunucu_cihaz'] as String,
      );
    } on SocketException {
      throw YerelAgHatasi('Ana cihaza ($adres) ulaşılamadı. Aynı WiFi\'da mı, ana cihazda uygulama açık mı?');
    } on TimeoutException {
      throw const YerelAgHatasi('Ana cihaz cevap vermedi (zaman aşımı).');
    } finally {
      istemci.close(force: true);
    }
  }
}

class YerelAgHatasi implements Exception {
  final String mesaj;
  const YerelAgHatasi(this.mesaj);
  @override
  String toString() => mesaj;
}
