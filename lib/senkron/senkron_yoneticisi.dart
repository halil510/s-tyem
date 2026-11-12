import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../core/database/app_database.dart' show senkTabanBayragi;
import 'bulut_kanali.dart';
import 'senk_cekirdek.dart';
import 'yerel_ag_kanali.dart';

/// Senkron ayar anahtarları (`senk_ayarlar` tablosu — cihaza özel; eşitlenmez, yedeğe girmez).
class SenkAyar {
  static const bulutUrl = 'bulut_url';
  static const bulutAnahtar = 'bulut_anahtar';
  static const isletme = 'isletme';
  static const isletmeSifre = 'isletme_sifre';
  static const bulutOtomatik = 'bulut_otomatik';
  static const bulutKimlik = 'bulut_kimlik'; // url+işletme: değişirse sayaçlar sıfırlanır
  static const lanRol = 'lan_rol'; // kapali | ana | bagli
  static const lanKod = 'lan_kod'; // ana cihazın eşleşme kodu
  static const lanAdres = 'lan_adres'; // bağlı cihaz: ana cihazın IP'si
  static const lanIstemciKod = 'lan_istemci_kod';
  static const lanSunucuCihaz = 'lan_sunucu_cihaz';
  static const cihazAd = 'cihaz_ad';
  static const tamYeniden = 'tam_yeniden'; // bu telefon yedeğe döndü: yerel ağda tam eşitleme
  static const lanSunucuNesil = 'lan_sunucu_nesil'; // ana cihazın son görülen taban nesli
}

enum SenkDurum { kapali, esitleniyor, tamam, hata }

class SenkOzet {
  final SenkDurum durum;
  final String mesaj;
  final DateTime? zaman;
  const SenkOzet(this.durum, this.mesaj, [this.zaman]);
}

/// ─────────────────────────────────────────────────────────────
/// SENKRON YÖNETİCİSİ — bulut + yerel ağ, otomatik eşitleme.
/// ─────────────────────────────────────────────────────────────
class SenkronYoneticisi {
  static final SenkronYoneticisi _i = SenkronYoneticisi._();
  factory SenkronYoneticisi() => _i;
  SenkronYoneticisi._();

  Database? _db;
  String? _cihaz;
  Timer? _zamanlayici;
  bool _calisiyor = false;

  /// Bulut (adres/işletme) değişince artar: sürmekte olan eski eşitleme sayaç yazmadan durur.
  int _bulutNesil = 0;
  final sunucu = YerelAgSunucusu();

  /// Uzak değişiklik uygulanınca çağrılır (ekranlar yenilensin).
  VoidCallback? veriGeldi;

  final bulutDurum = ValueNotifier(const SenkOzet(SenkDurum.kapali, 'Bulut kapalı'));
  final lanDurum = ValueNotifier(const SenkOzet(SenkDurum.kapali, 'Yerel ağ kapalı'));

  /// Son bulut eşitlemesinde ölçülen saat farkı (sunucu − cihaz); 5 dk'yı aşarsa ekranda uyarı.
  final saatFarki = ValueNotifier<Duration?>(null);

  @visibleForTesting
  static String? testCihaz;

  String get cihaz => _cihaz ?? '';

  /// Cihaz kimliği SharedPreferences'ta: veritabanı yedeğiyle başka telefona KOPYALANMAZ.
  static Future<String> cihazKimligi() async {
    if (testCihaz != null) return testCihaz!;
    final p = await SharedPreferences.getInstance();
    var k = p.getString('sutyem_cihaz_id');
    if (k == null || k.isEmpty) {
      final r = Random.secure();
      k = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await p.setString('sutyem_cihaz_id', k);
    }
    return k;
  }

  /// Uygulama açılışında (veritabanı hazır olunca) çağrılır. Veritabanı dosyası başka bir
  /// cihazdan geldiyse (.db aktarımı) senkron günlüğü tabandan kurulur.
  Future<void> baslat(Database db) async {
    if (_db == db && _cihaz != null) return;
    _db = db;
    _cihaz = await cihazKimligi();
    final onceki = (await db.rawQuery('SELECT yerel_cihaz FROM senk_durum WHERE tek = 1')).firstOrNull?['yerel_cihaz'] as String?;
    var dosyaDegisti = false;
    SharedPreferences? p;
    if (testCihaz == null) {
      try {
        p = await SharedPreferences.getInstance();
        dosyaDegisti = p.getBool(senkTabanBayragi) ?? false;
      } catch (_) {}
    }
    if (dosyaDegisti || (onceki != null && onceki.isNotEmpty && onceki != _cihaz)) {
      await db.transaction((txn) async {
        await SenkCekirdek.cihazAyarla(txn, _cihaz!);
        await SenkCekirdek.tabanYenile(txn);
      });
      await p?.remove(senkTabanBayragi);
    } else {
      await SenkCekirdek.cihazAyarla(db, _cihaz!);
    }
    await _yerelAgiKur();
    _zamanlayici?.cancel();
    if (testCihaz != null) return; // testlerde zamanlayıcı ve otomatik eşitleme yok
    _zamanlayici = Timer.periodic(const Duration(seconds: 60), (_) => otomatikEsitle());
    unawaited(otomatikEsitle());
  }

  /// Veritabanı dosyası değiştirilince (.db geri yükleme) eski bağlantı bırakılır.
  void veritabaniDegisti() {
    _db = null;
    _cihaz = null;
  }

  Future<String?> ayar(String k) async {
    final db = _db;
    if (db == null) return null;
    return (await db.query('senk_ayarlar', where: 'anahtar = ?', whereArgs: [k])).firstOrNull?['deger'] as String?;
  }

  Future<void> ayarYaz(String k, String? v) async {
    if (v == null) {
      await _db!.delete('senk_ayarlar', where: 'anahtar = ?', whereArgs: [k]);
    } else {
      await _db!.rawInsert('INSERT OR REPLACE INTO senk_ayarlar (anahtar, deger) VALUES (?, ?)', [k, v]);
    }
  }

  Future<String> cihazAdi() async => (await ayar(SenkAyar.cihazAd)) ?? (defaultTargetPlatform == TargetPlatform.windows ? 'Bilgisayar' : 'Telefon');

  Future<BulutAyari?> bulutAyari() async {
    final a = BulutAyari(
      url: (await ayar(SenkAyar.bulutUrl)) ?? '',
      anahtar: (await ayar(SenkAyar.bulutAnahtar)) ?? '',
      isletme: (await ayar(SenkAyar.isletme)) ?? '',
      sifre: (await ayar(SenkAyar.isletmeSifre)) ?? '',
    );
    return a.tamam ? a : null;
  }

  Future<Map<String, Object?>> _kanal(String k) async {
    await _db!.rawInsert('INSERT OR IGNORE INTO senk_kanallar (kanal) VALUES (?)', [k]);
    return (await _db!.query('senk_kanallar', where: 'kanal = ?', whereArgs: [k])).first;
  }

  Future<void> _kanalYaz(String k, Map<String, Object?> v) => _db!.update('senk_kanallar', v, where: 'kanal = ?', whereArgs: [k]);

  Future<int> bekleyen(String kanal, String haric) async {
    if (_db == null) return 0;
    final k = await _kanal(kanal);
    return SenkCekirdek(_db!).bekleyenSayisi(sonra: k['son_gonderilen'] as int, haricKaynak: haric);
  }

  Future<List<Map<String, Object?>>> hatalar() async {
    final db = _db;
    if (db == null) return const [];
    return db.query('senk_hatalar', orderBy: 'id DESC', limit: 200);
  }

  Future<int> bekletilenSayisi() async => _db == null ? 0 : (Sqflite.firstIntValue(await _db!.rawQuery('SELECT COUNT(*) FROM senk_bekleyen')) ?? 0);
  Future<void> hatalariTemizle() async => _db?.delete('senk_hatalar');

  /// Ebeveyni sonradan gelen ya da hata veren bekletilmiş kayıtlar, o kanaldan yeni veri
  /// gelmese de yeniden denenir (ör. cari başka kanaldan geldi).
  Future<void> _bekleyenleriDene(String kanal, UygulamaSonucu alinan) async {
    final db = _db!;
    final n = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM senk_bekleyen WHERE kanal = ?', [kanal])) ?? 0;
    if (n == 0) return;
    final s = await db.transaction((txn) => SenkCekirdek(txn).uygula(const [], kanal: kanal));
    alinan
      ..uygulanan += s.uygulanan
      ..bekletilen = s.bekletilen
      ..hatali += s.hatali;
  }

  Future<void> otomatikEsitle() async {
    if (_db == null || _calisiyor) return;
    try {
      if ((await ayar(SenkAyar.lanRol)) == 'bagli' && (await ayar(SenkAyar.lanAdres)) != null) await yerelAgdaEsitle(sessiz: true);
      if ((await bulutAyari()) != null && (await ayar(SenkAyar.bulutOtomatik)) != '0') await buluttaEsitle(sessiz: true);
    } catch (_) {
      // Otomatik eşitleme sessizdir; durum kartlarında hata görünür.
    }
  }

  // ═════════════════════════════ BULUT ═════════════════════════════

  /// Ayarları kaydeder ve bağlantıyı dener (işletme yoksa kurar).
  Future<Map<String, Object?>> bulutBaglan(BulutAyari a, {String? isletmeAd}) async {
    final sorun = BulutAyari.adresSorunu(a.url) ?? BulutAyari.anahtarSorunu(a.anahtar);
    if (sorun != null) throw BulutHatasi(sorun);
    // Sürmekte olan eşitleme bitince eski bulutun sayaçlarını yeni bulutun üstüne yazardı.
    // Sürmekte olan eşitleme varsa: bulut değiştiği için o eşitleme sayaçları YAZMADAN durur (bkz. _bulutNesil).
    final kanal = BulutKanali(a);
    try {
      final r = await kanal.baglan(cihaz: cihaz, cihazAd: await cihazAdi(), isletmeAd: isletmeAd);
      saatFarki.value = kanal.saatFarki;
      final kimlik = '${BulutAyari.urlTemizle(a.url)}#${a.isletme}';
      if ((await ayar(SenkAyar.bulutKimlik)) != kimlik) {
        await _bulutSayaclariniSifirla();
      } else {
        await _bulutSifirlandiysa(r);
      }
      await ayarYaz(SenkAyar.bulutUrl, BulutAyari.urlTemizle(a.url));
      await ayarYaz(SenkAyar.bulutAnahtar, a.anahtar.trim());
      await ayarYaz(SenkAyar.isletme, a.isletme.trim());
      await ayarYaz(SenkAyar.isletmeSifre, a.sifre);
      await ayarYaz(SenkAyar.bulutKimlik, kimlik);
      return r;
    } finally {
      kanal.kapat();
    }
  }

  Future<void> _bulutSayaclariniSifirla() async {
    await _kanal('bulut');
    _bulutNesil++;
    await _kanalYaz('bulut', {'son_gonderilen': 0, 'son_cekilen': 0});
    await _db!.delete('senk_bekleyen', where: 'kanal = ?', whereArgs: ['bulut']);
  }

  /// Buluttaki işletme silinip aynı kodla yeniden kurulduysa (ya da bulut veritabanı
  /// sıfırlandıysa) bu telefon her şeyini yeniden göndermeli, baştan almalı.
  Future<void> _bulutSifirlandiysa(Map<String, Object?> baglanti) async {
    final k = await _kanal('bulut');
    final sonSira = (baglanti['son_sira'] as num?)?.toInt() ?? 0;
    final sifirlandi = baglanti['yeni'] == true || sonSira < (k['son_cekilen'] as int);
    if (sifirlandi && ((k['son_gonderilen'] as int) > 0 || (k['son_cekilen'] as int) > 0)) await _bulutSayaclariniSifirla();
  }

  Future<void> bulutuKapat() async {
    for (final k in [SenkAyar.bulutUrl, SenkAyar.bulutAnahtar, SenkAyar.isletmeSifre]) {
      await ayarYaz(k, null);
    }
    bulutDurum.value = const SenkOzet(SenkDurum.kapali, 'Bulut kapalı');
  }

  /// Önce gönder, sonra al. Hata olursa sayaçlar ilerlemez (tekrar denenir).
  Future<String> buluttaEsitle({bool sessiz = false}) async {
    final a = await bulutAyari();
    if (a == null) throw const BulutHatasi('Bulut ayarlanmamış.');
    if (_calisiyor) return 'Eşitleme zaten sürüyor';
    _calisiyor = true;
    bulutDurum.value = const SenkOzet(SenkDurum.esitleniyor, 'Bulutla eşitleniyor…');
    final kanal = BulutKanali(a);
    var gonderilen = 0;
    final alinan = UygulamaSonucu();
    try {
      final db = _db!;
      await _bulutSifirlandiysa(await kanal.baglan(cihaz: cihaz, cihazAd: await cihazAdi()));
      final nesil = _bulutNesil;
      var k = await _kanal('bulut');
      // ÖNCE AL, SONRA GÖNDER: buluttaki değişiklikler önce bu telefondakilerle birleşir
      // (ör. aynı günün sütünde öğünler), sonra birleşmiş hali gider. Önce gönderilseydi bu
      // telefonun satırı buluttaki diğer öğünün üzerine yazar, birleşme bir tur gecikirdi.
      var sonCekilen = k['son_cekilen'] as int;
      while (true) {
        final gelen = await kanal.cek(cihaz: cihaz, sira: sonCekilen);
        if (gelen.isEmpty) break;
        final s = await db.transaction((txn) => SenkCekirdek(txn).uygula([for (final g in gelen) g.$1], kanal: 'bulut'));
        alinan
          ..uygulanan += s.uygulanan
          ..bekletilen = s.bekletilen
          ..hatali += s.hatali;
        sonCekilen = gelen.last.$2;
        if (nesil != _bulutNesil) return 'Bulut değişti; eşitleme yeniden başlayacak';
        await _kanalYaz('bulut', {'son_cekilen': sonCekilen});
        if (gelen.length < 500) break;
      }
      await _bekleyenleriDene('bulut', alinan);
      var sonGonderilen = (k = await _kanal('bulut'))['son_gonderilen'] as int;
      while (true) {
        final (giden, sonId) = await SenkCekirdek(db).gonderilecekler(sonra: sonGonderilen, haricKaynak: 'bulut');
        if (sonId == sonGonderilen) break;
        if (giden.isNotEmpty) gonderilen += await kanal.gonder(cihaz: cihaz, kayitlar: giden);
        sonGonderilen = sonId;
        if (nesil != _bulutNesil) return 'Bulut değişti; eşitleme yeniden başlayacak';
        await _kanalYaz('bulut', {'son_gonderilen': sonGonderilen});
      }
      await SenkCekirdek(db).budama();
      saatFarki.value = kanal.saatFarki;
      final mesaj = '${gonderilen > 0 ? '$gonderilen gönderildi, ' : ''}${alinan.uygulanan} alındı'
          '${alinan.bekletilen > 0 ? ', ${alinan.bekletilen} bekliyor' : ''}${alinan.hatali > 0 ? ', ${alinan.hatali} sorun' : ''}';
      await _kanalYaz('bulut', {'son_basari': DateTime.now().toIso8601String(), 'son_hata': null});
      bulutDurum.value = SenkOzet(alinan.hatali > 0 ? SenkDurum.hata : SenkDurum.tamam, 'Eşitlendi: $mesaj', DateTime.now());
      if (alinan.uygulanan > 0) veriGeldi?.call();
      return mesaj;
    } catch (e) {
      await _kanalYaz('bulut', {'son_hata': e.toString()});
      bulutDurum.value = SenkOzet(SenkDurum.hata, e.toString(), DateTime.now());
      if (sessiz) return e.toString();
      rethrow;
    } finally {
      kanal.kapat();
      _calisiyor = false;
    }
  }

  Future<List<Map<String, Object?>>> bulutCihazlari() async {
    final a = await bulutAyari();
    if (a == null) return [];
    final k = BulutKanali(a);
    try {
      return await k.cihazlar();
    } finally {
      k.kapat();
    }
  }

  // ═════════════════════════════ YEREL AĞ ═════════════════════════════

  Future<void> _yerelAgiKur() async {
    if ((await ayar(SenkAyar.lanRol)) == 'ana') {
      try {
        await anaCihazOl();
      } catch (e) {
        lanDurum.value = SenkOzet(SenkDurum.hata, 'Ana cihaz açılamadı: $e');
      }
    } else {
      await sunucu.durdur();
    }
  }

  /// Bu cihazı ana cihaz yapar (sunucuyu açar). Eşleşme kodu yoksa üretir.
  Future<String> anaCihazOl() async {
    var kod = await ayar(SenkAyar.lanKod);
    if (kod == null || kod.length != 6) {
      kod = (100000 + Random.secure().nextInt(900000)).toString();
      await ayarYaz(SenkAyar.lanKod, kod);
    }
    await ayarYaz(SenkAyar.lanRol, 'ana');
    sunucu.degisti = (_) => veriGeldi?.call();
    await sunucu.baslat(db: _db!, cihaz: cihaz, cihazAd: await cihazAdi(), kod: kod);
    lanDurum.value = SenkOzet(SenkDurum.tamam, 'Ana cihaz açık: ${sunucu.ip ?? '?'} · kod $kod');
    return kod;
  }

  Future<void> yerelAgiKapat() async {
    await sunucu.durdur();
    await ayarYaz(SenkAyar.lanRol, 'kapali');
    lanDurum.value = const SenkOzet(SenkDurum.kapali, 'Yerel ağ kapalı');
  }

  Future<String> anaCihazaBaglan(String adres, String kod) async {
    await ayarYaz(SenkAyar.lanAdres, adres.trim());
    await ayarYaz(SenkAyar.lanIstemciKod, kod.trim());
    await ayarYaz(SenkAyar.lanRol, 'bagli');
    await sunucu.durdur();
    return yerelAgdaEsitle();
  }

  Future<String> yerelAgdaEsitle({bool sessiz = false}) async {
    final adres = await ayar(SenkAyar.lanAdres);
    final kod = await ayar(SenkAyar.lanIstemciKod);
    if (adres == null || kod == null) throw const YerelAgHatasi('Ana cihaz seçilmemiş.');
    if (_calisiyor) return 'Eşitleme zaten sürüyor';
    _calisiyor = true;
    lanDurum.value = const SenkOzet(SenkDurum.esitleniyor, 'Ana cihazla eşitleniyor…');
    var gonderilen = 0;
    final alinan = UygulamaSonucu();
    try {
      final db = _db!;
      final k = await _kanal('lan');
      var sonGonderilen = k['son_gonderilen'] as int;
      var sonCekilen = k['son_cekilen'] as int;
      // Tam eşitleme (yankı önlemesiz): bu telefon yedeğe döndüyse ya da ana cihaz yedeğe döndüyse.
      var tam = (await ayar(SenkAyar.tamYeniden)) == '1';
      for (var tur = 0; tur < 200; tur++) {
        final (giden, sonId) = await SenkCekirdek(db).gonderilecekler(sonra: sonGonderilen, haricKaynak: tam ? null : 'lan');
        final (gelen, yeniCekilen, sunucuSon, sunucuCihaz) =
            await YerelAgIstemcisi.tur(adres: adres, kod: kod, cihaz: cihaz, sonCekilen: sonCekilen, giden: giden, tam: tam);
        final nesil = YerelAgIstemcisi.sonSunucuNesil ?? '';
        final eskiNesil = await ayar(SenkAyar.lanSunucuNesil);
        if (eskiNesil != nesil) {
          await ayarYaz(SenkAyar.lanSunucuNesil, nesil);
          if (eskiNesil != null && !tam) {
            // Ana cihaz yedeğe döndü: ondan baştan al, elindekileri yankısız yeniden gönder.
            tam = true;
            sonCekilen = 0;
            sonGonderilen = 0;
            await _kanalYaz('lan', {'son_cekilen': 0, 'son_gonderilen': 0});
            continue;
          }
        }
        final eski = await ayar(SenkAyar.lanSunucuCihaz);
        if (eski != sunucuCihaz) {
          await ayarYaz(SenkAyar.lanSunucuCihaz, sunucuCihaz);
          if (eski != null) {
            // Yeni ana cihaz: ondan baştan alınır VE bu telefonun eski ana cihaza gönderdiği her şey
            // yenisine de gönderilir (yoksa yeni ana cihaz bu telefonun geçmiş kayıtlarını hiç görmezdi).
            sonCekilen = 0;
            sonGonderilen = 0;
            await _kanalYaz('lan', {'son_cekilen': 0, 'son_gonderilen': 0});
            continue;
          }
        }
        gonderilen += giden.length;
        sonGonderilen = sonId;
        if (gelen.isNotEmpty) {
          final s = await db.transaction((txn) => SenkCekirdek(txn).uygula(gelen, kanal: 'lan'));
          alinan
            ..uygulanan += s.uygulanan
            ..bekletilen = s.bekletilen
            ..hatali += s.hatali;
        }
        final ilerledi = yeniCekilen != sonCekilen || giden.isNotEmpty;
        sonCekilen = yeniCekilen > sunucuSon ? sunucuSon : yeniCekilen;
        await _kanalYaz('lan', {'son_gonderilen': sonGonderilen, 'son_cekilen': sonCekilen});
        if (!ilerledi) break;
      }
      await _bekleyenleriDene('lan', alinan);
      if (tam) await ayarYaz(SenkAyar.tamYeniden, null);
      await SenkCekirdek(db).budama();
      final mesaj = '${gonderilen > 0 ? '$gonderilen gönderildi, ' : ''}${alinan.uygulanan} alındı'
          '${alinan.hatali > 0 ? ', ${alinan.hatali} sorun' : ''}';
      await _kanalYaz('lan', {'son_basari': DateTime.now().toIso8601String(), 'son_hata': null});
      lanDurum.value = SenkOzet(alinan.hatali > 0 ? SenkDurum.hata : SenkDurum.tamam, 'Eşitlendi: $mesaj', DateTime.now());
      if (alinan.uygulanan > 0) veriGeldi?.call();
      return mesaj;
    } catch (e) {
      await _kanalYaz('lan', {'son_hata': e.toString()});
      lanDurum.value = SenkOzet(SenkDurum.hata, e.toString(), DateTime.now());
      if (sessiz) return e.toString();
      rethrow;
    } finally {
      _calisiyor = false;
    }
  }

  @visibleForTesting
  Future<void> testSifirla() async {
    _zamanlayici?.cancel();
    await sunucu.durdur();
    _db = null;
    _cihaz = null;
    _calisiyor = false;
    saatFarki.value = null;
  }
}
