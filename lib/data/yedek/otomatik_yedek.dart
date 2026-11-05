import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/database/app_database.dart';
import 'yedek_servisi.dart';

/// Otomatik güvenlik yedeği neden alındı.
enum YedekSebebi {
  /// Uygulama açılınca / arka plana geçince, en çok [OtomatikYedek.otomatikAralik]'ta bir.
  otomatik('otomatik', 'Otomatik'),

  /// Toplu silme, geri yükleme, cari silme gibi riskli bir işlemden hemen önce.
  islemOncesi('islem', 'İşlem öncesi');

  final String kod;
  final String etiket;
  const YedekSebebi(this.kod, this.etiket);
}

/// Klasördeki bir güvenlik yedeği.
class GuvenlikYedegi {
  final File dosya;
  final DateTime tarih;
  final YedekSebebi sebep;

  /// İşlem öncesi yedeklerde hangi işlem (ör. "sut_yem_silme").
  final String aciklama;
  final int boyut;
  const GuvenlikYedegi({
    required this.dosya,
    required this.tarih,
    required this.sebep,
    required this.aciklama,
    required this.boyut,
  });
}

/// Güvenlik yedeği alınamadı → riskli işlem YAPILMAMALI.
class GuvenlikYedegiHatasi implements Exception {
  final Object neden;
  const GuvenlikYedegiHatasi(this.neden);
  @override
  String toString() => 'Güvenlik yedeği alınamadı, işlem yapılmadı: $neden';
}

/// ─────────────────────────────────────────────────────────────
/// OTOMATİK GÜVENLİK YEDEĞİ
/// ─────────────────────────────────────────────────────────────
///
/// Telefonda, uygulamanın kendi klasöründe (`otomatik_yedekler/`) tam JSON
/// yedekleri tutar. Kullanıcı hiç yedek almasa bile:
/// * dosya bozulursa / yanlış bir geri yükleme ya da toplu silme yapılırsa
///   en fazla birkaç saatlik veri gider, gerisi buradan geri gelir;
/// * riskli her işlemden ÖNCE yedek alınır; yedek alınamazsa işlem yapılmaz.
///
/// Dosya önce `.tmp` olarak tam yazılıp diske zorlanır, SONRA adı
/// değiştirilir: yazarken şarj biterse yarım dosya "yedek" sayılmaz.
///
/// NOT: Bu klasör uygulama silinince / telefon kaybolunca gider. Telefon
/// dışına yedek (paylaş → Drive/WhatsApp/bilgisayar) yine gereklidir.
class OtomatikYedek {
  final Database db;
  final Directory klasor;
  OtomatikYedek(this.db, this.klasor);

  static const klasorAdi = 'otomatik_yedekler';

  /// İki otomatik yedek arasındaki en kısa süre.
  static const otomatikAralik = Duration(hours: 4);

  /// Saklanacak en çok yedek sayısı (eskiler silinir).
  static const otomatikSakla = 15;
  static const islemOncesiSakla = 10;

  static final _damga = DateFormat('yyyy-MM-dd_HH-mm-ss');
  static final _adKalibi = RegExp(r'^sutyem_(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})_([a-z]+)(?:_([a-z0-9_]+))?\.json$');

  static Future<Directory> varsayilanKlasor() async =>
      Directory(p.join((await getApplicationDocumentsDirectory()).path, klasorAdi));

  /// Uygulamanın gerçek veritabanı ve klasörüyle.
  static Future<OtomatikYedek> uygulama() async =>
      OtomatikYedek(await AppDatabase.instance.database, await varsayilanKlasor());

  /// Riskli bir işlemden ÖNCE çağrılır. Yedek alınamazsa
  /// [GuvenlikYedegiHatasi] fırlatır — çağıran işlemi YAPMAMALI.
  static Future<File> islemOncesiAl(String islem) async {
    try {
      return await (await uygulama()).al(YedekSebebi.islemOncesi, aciklama: islem);
    } catch (e) {
      throw GuvenlikYedegiHatasi(e);
    }
  }

  /// Son otomatik yedek [otomatikAralik]'tan eskiyse yeni yedek alır.
  /// Hata uygulamayı ASLA durdurmaz (null döner).
  static Future<File?> gerekirseOtomatikAl() async {
    try {
      return await (await uygulama()).gerekirseAl();
    } catch (e, st) {
      debugPrint('[OtomatikYedek] alınamadı: $e\n$st');
      return null;
    }
  }

  Future<File?> gerekirseAl({DateTime? simdi}) async {
    final an = simdi ?? DateTime.now();
    final son = (await listele()).where((y) => y.sebep == YedekSebebi.otomatik).firstOrNull;
    if (son != null && an.difference(son.tarih) < otomatikAralik && !son.tarih.isAfter(an)) return null;
    return al(YedekSebebi.otomatik, simdi: an);
  }

  /// Aynı anda iki yedek yazılmasın (ör. arka plana geçiş + işlem öncesi):
  /// biri diğerinin `.tmp` dosyasını temizlemesin.
  static Future<void> _sira = Future.value();

  /// Yedeği yazar ve eski yedekleri temizler.
  Future<File> al(YedekSebebi sebep, {String aciklama = '', DateTime? simdi}) {
    final gorev = _sira.then((_) => _al(sebep, aciklama: aciklama, simdi: simdi));
    _sira = gorev.then((_) {}, onError: (_) {});
    return gorev;
  }

  Future<File> _al(YedekSebebi sebep, {required String aciklama, DateTime? simdi}) async {
    await klasor.create(recursive: true);
    final json = await YedekServisi.disaAktarJson(db);
    final ek = aciklama.isEmpty ? '' : '_${_temizAd(aciklama)}';
    var ad = 'sutyem_${_damga.format(simdi ?? DateTime.now())}_${sebep.kod}$ek';
    var hedef = File(p.join(klasor.path, '$ad.json'));
    // Aynı saniyede ikinci yedek: üzerine yazma, numara ekle.
    for (var i = 2; await hedef.exists(); i++) {
      hedef = File(p.join(klasor.path, '${ad}_$i.json'));
    }
    final gecici = File('${hedef.path}.tmp');
    await gecici.writeAsString(json, flush: true);
    await gecici.rename(hedef.path);
    await _temizle();
    return hedef;
  }

  /// Yedekler, en yeni önce. Yarım kalmış `.tmp` dosyaları listelenmez.
  Future<List<GuvenlikYedegi>> listele() async {
    if (!await klasor.exists()) return const [];
    final liste = <GuvenlikYedegi>[];
    await for (final f in klasor.list()) {
      if (f is! File) continue;
      final m = _adKalibi.firstMatch(p.basename(f.path));
      if (m == null) continue;
      final sebep = YedekSebebi.values.where((s) => s.kod == m.group(2)).firstOrNull;
      if (sebep == null) continue;
      final g = m.group(1)!;
      final tarih = DateTime(
        int.parse(g.substring(0, 4)), int.parse(g.substring(5, 7)), int.parse(g.substring(8, 10)),
        int.parse(g.substring(11, 13)), int.parse(g.substring(14, 16)), int.parse(g.substring(17, 19)),
      );
      liste.add(GuvenlikYedegi(
        dosya: f,
        tarih: tarih,
        sebep: sebep,
        aciklama: (m.group(3) ?? '').replaceAll(RegExp(r'(^|_)\d+$'), ''),
        boyut: await f.length(),
      ));
    }
    liste.sort((a, b) {
      final t = b.tarih.compareTo(a.tarih);
      return t != 0 ? t : b.dosya.path.compareTo(a.dosya.path);
    });
    return liste;
  }

  Future<void> _temizle() async {
    final liste = await listele();
    for (final (sebep, sakla) in [
      (YedekSebebi.otomatik, otomatikSakla),
      (YedekSebebi.islemOncesi, islemOncesiSakla),
    ]) {
      final fazla = liste.where((y) => y.sebep == sebep).skip(sakla);
      for (final y in fazla) {
        try {
          await y.dosya.delete();
        } catch (_) {}
      }
    }
    // Şarj bitip yarım kalmış yazımlar.
    try {
      await for (final f in klasor.list()) {
        if (f is File && f.path.endsWith('.tmp')) await f.delete();
      }
    } catch (_) {}
  }

  static String _temizAd(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');

  /// Kullanıcıya gösterilecek işlem adı.
  static String islemEtiketi(String kod) => switch (kod) {
        'sut_yem_silme' => 'Süt/yem silme öncesi',
        'json_geri_yukleme' => 'JSON geri yükleme öncesi',
        'db_geri_yukleme' => 'Veritabanı geri yükleme öncesi',
        'cihaz_aktarimi' => 'Cihaz aktarımı öncesi',
        'cari_silme' => 'Cari silme öncesi',
        'elle' => 'Elle alınan',
        'guvenlik_yedegi_donusu' => 'Güvenlik yedeğine dönüş öncesi',
        '' => 'İşlem öncesi',
        _ => kod.replaceAll('_', ' '),
      };
}
