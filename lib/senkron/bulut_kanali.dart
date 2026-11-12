import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'senk_cekirdek.dart';

/// Bulut ayarları (cihazda `senk_ayarlar` tablosunda durur; eşitlenmez, yedeğe girmez).
class BulutAyari {
  final String url;
  final String anahtar; // anon / publishable (herkese açık) anahtar
  final String isletme;
  final String sifre;
  const BulutAyari({required this.url, required this.anahtar, required this.isletme, required this.sifre});

  bool get tamam => url.isNotEmpty && anahtar.isNotEmpty && isletme.isNotEmpty && sifre.isNotEmpty;

  static String urlTemizle(String u) => u.trim().replaceAll(RegExp(r'/rest/v1/?$'), '').replaceAll(RegExp(r'/+$'), '');

  /// İşletme şifresi her istekte gider: adres https olmalı (http'de şifre ağda açık gider).
  static String? adresSorunu(String u) {
    final a = urlTemizle(u);
    final uri = Uri.tryParse(a);
    if (uri == null || uri.host.isEmpty) return 'Bulut adresi geçersiz (örn. https://xxxx.supabase.co).';
    if (uri.scheme != 'https') return 'Bulut adresi "https://" ile başlamalı; "http://" ile işletme şifresi ağda şifresiz gider.';
    return null;
  }

  /// Uygulamaya GİZLİ anahtar konmamalı (anahtar cihazdan okunabilir).
  static String? anahtarSorunu(String a) {
    final k = a.trim();
    if (k.isEmpty) return 'Anahtar boş.';
    if (k.startsWith('sb_secret_')) return 'Bu GİZLİ (secret) anahtar. Uygulamaya "anon" ya da "publishable" (herkese açık) anahtarı girin.';
    if (k.startsWith('eyJ')) {
      try {
        final govde = utf8.decode(base64Url.decode(base64Url.normalize(k.split('.')[1])));
        if (govde.contains('"service_role"')) return 'Bu service_role (GİZLİ) anahtar. Uygulamaya "anon" anahtarı girin.';
      } catch (_) {}
    }
    return null;
  }
}

class BulutHatasi implements Exception {
  final String mesaj;
  const BulutHatasi(this.mesaj);
  @override
  String toString() => mesaj;
}

/// Cihaz saati ile sunucu saati arasındaki fark (market uygulamasındaki SaatFarki).
/// "Hangi değişiklik daha yeni" kararı cihaz saatiyle verilir; saat yanlışsa eski kayıt
/// yeniyi ezebilir → kullanıcı uyarılır.
class SaatFarki {
  static const esik = Duration(minutes: 5);

  /// Sunucu − cihaz (pozitif: cihaz saati GERİDE). `Date` başlığı yoksa null.
  static Duration? hesapla(String? dateBasligi, DateTime istekBasi, DateTime istekSonu) {
    if (dateBasligi == null || dateBasligi.isEmpty) return null;
    try {
      final sunucu = HttpDate.parse(dateBasligi);
      final orta = istekBasi.add(istekSonu.difference(istekBasi) ~/ 2);
      return sunucu.difference(orta.toUtc());
    } catch (_) {
      return null;
    }
  }

  static bool sapmaVar(Duration? fark) => fark != null && fark.abs() > esik;

  static String metin(Duration fark) {
    final dk = fark.inMinutes.abs();
    final sure = dk >= 120 ? '${(dk / 60).round()} saat' : '$dk dk';
    return 'Telefonun saati sunucudan $sure ${fark.isNegative ? 'ileride' : 'geride'}. Tarih/saati otomatik yapın; '
        'yoksa iki telefon aynı kaydı değiştirdiğinde yanlış olan kalabilir.';
  }
}

/// ─────────────────────────────────────────────────────────────
/// BULUT KANALI — Supabase (PostgREST RPC). Tablolara doğrudan erişim yok;
/// her çağrı işletme kodu + şifresiyle `sutyem_*` fonksiyonlarına gider
/// (bkz. supabase/sutyem_bulut_sema.sql).
/// ─────────────────────────────────────────────────────────────
class BulutKanali {
  final BulutAyari a;
  final http.Client _istemci;
  BulutKanali(this.a, {http.Client? istemci}) : _istemci = istemci ?? testIstemci?.call() ?? http.Client();

  /// Yalnız test: sahte bulut.
  static http.Client Function()? testIstemci;

  /// Son çağrıda ölçülen saat farkı (sunucu − cihaz).
  Duration? saatFarki;

  Map<String, String> get _basliklar => {
        'apikey': a.anahtar,
        if (a.anahtar.startsWith('eyJ')) 'Authorization': 'Bearer ${a.anahtar}',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  Future<Object?> _rpc(String fn, Map<String, Object?> govde) async {
    final uri = Uri.parse('${BulutAyari.urlTemizle(a.url)}/rest/v1/rpc/$fn');
    http.Response r;
    final bas = DateTime.now();
    try {
      r = await _istemci.post(uri, headers: _basliklar, body: jsonEncode(govde)).timeout(const Duration(seconds: 40));
    } on TimeoutException {
      throw const BulutHatasi('Buluta ulaşılamadı (zaman aşımı). İnternet bağlantısını kontrol edin.');
    } on SocketException {
      throw const BulutHatasi('İnternet yok ya da bulut adresi yanlış.');
    } on http.ClientException catch (e) {
      throw BulutHatasi('Bağlantı hatası: ${e.message}');
    }
    saatFarki = SaatFarki.hesapla(r.headers['date'], bas, DateTime.now()) ?? saatFarki;
    if (r.statusCode >= 200 && r.statusCode < 300) {
      if (r.body.isEmpty) return null;
      try {
        return jsonDecode(utf8.decode(r.bodyBytes));
      } on FormatException {
        // Ör. otel/kafe WiFi giriş sayfası 200 + HTML döndürür.
        throw const BulutHatasi('Buluttan anlaşılmayan cevap geldi. WiFi giriş sayfası açık olabilir; internet bağlantısını kontrol edin.');
      }
    }
    var m = utf8.decode(r.bodyBytes);
    try {
      final j = jsonDecode(m) as Map;
      m = (j['message'] ?? j['msg'] ?? j['error'] ?? m).toString();
    } catch (_) {}
    if (m.contains('SUTYEM_YETKISIZ')) throw const BulutHatasi('İşletme kodu veya şifresi hatalı.');
    if (m.contains('SUTYEM_SIFRE_KISA')) throw const BulutHatasi('İşletme şifresi en az 6 karakter olmalı.');
    if (r.statusCode == 404 || m.contains('Could not find the function')) {
      throw const BulutHatasi('Bulutta Süt-Yem tabloları yok. supabase/sutyem_bulut_sema.sql dosyasını SQL Editor\'da çalıştırın.');
    }
    if (r.statusCode == 401 || r.statusCode == 403) throw BulutHatasi('Anahtar geçersiz ya da yetkisiz ($m).');
    throw BulutHatasi('Bulut hatası (${r.statusCode}): $m');
  }

  /// İşletme yoksa kurar, varsa şifreyi doğrular; cihazı kaydeder.
  Future<Map<String, Object?>> baglan({required String cihaz, required String cihazAd, String? isletmeAd}) async => ((await _rpc('sutyem_baglan', {
        'p_isletme': a.isletme,
        'p_sifre': a.sifre,
        'p_cihaz': cihaz,
        'p_cihaz_ad': cihazAd,
        'p_isletme_ad': isletmeAd,
      })) as Map)
          .cast<String, Object?>();

  Future<int> gonder({required String cihaz, required List<SenkKayit> kayitlar}) async {
    final r = (await _rpc('sutyem_gonder', {
      'p_isletme': a.isletme,
      'p_sifre': a.sifre,
      'p_cihaz': cihaz,
      'p_kayitlar': [for (final k in kayitlar) k.toJson()],
    })) as Map;
    return (r['yazilan'] as num?)?.toInt() ?? 0;
  }

  /// [sira]dan sonraki değişiklikler ve her birinin sırası.
  Future<List<(SenkKayit, int)>> cek({required String cihaz, required int sira, int limit = 500}) async {
    final r = (await _rpc('sutyem_cek', {'p_isletme': a.isletme, 'p_sifre': a.sifre, 'p_cihaz': cihaz, 'p_sira': sira, 'p_limit': limit})) as List;
    return [
      for (final m in r.cast<Map>())
        (
          SenkKayit(
            tablo: m['t'] as String,
            anahtar: m['k'] as String,
            zaman: m['z'] as String,
            cihaz: (m['c'] as String?) ?? '',
            silindi: m['s'] == true,
            veri: (m['v'] as Map?)?.cast<String, Object?>(),
          ),
          (m['sira'] as num).toInt(),
        ),
    ];
  }

  Future<List<Map<String, Object?>>> cihazlar() async => ((await _rpc('sutyem_cihaz_listesi', {'p_isletme': a.isletme, 'p_sifre': a.sifre})) as List)
      .cast<Map>()
      .map((m) => m.cast<String, Object?>())
      .toList();

  void kapat() => _istemci.close();
}
