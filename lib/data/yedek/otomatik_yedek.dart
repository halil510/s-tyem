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
/// Bu klasör uygulama silinince gider. Bu yüzden her yedeğin bir KOPYASI
/// telefonun ortak İndirilenler klasörüne de ([disKlasorAdi]) yazılır
/// ([disKlasor]); uygulama silinip yeniden yüklense de orada kalır ve
/// "Dosyadan geri yükle" ile seçilip geri alınabilir. Dış kopya en iyi
/// çabadır: yazılamazsa asıl yedek yine alınmış sayılır.
/// Telefon kaybolursa ikisi de gider — telefon dışına "Paylaş" yine gerekli.
class OtomatikYedek {
  final Database db;
  final Directory klasor;

  /// Uygulama silinince de kalan kopya klasörü (yoksa dış kopya yazılmaz).
  final Directory? disKlasor;
  OtomatikYedek(this.db, this.klasor, {this.disKlasor});

  static const klasorAdi = 'otomatik_yedekler';

  /// İndirilenler altındaki klasör adı (Türkçe harf yok: her dosya yöneticisinde okunur).
  static const disKlasorAdi = 'SutYem_Yedekleri';


  /// Son dış kopya denemesinin hatası (null = son kopya başarılı ya da hiç denenmedi).
  static Object? sonDisHata;

  /// İki otomatik yedek arasındaki en kısa süre.
  static const otomatikAralik = Duration(hours: 4);

  /// SAKLAMA KURALI (kullanıcı isteği 2026-11-19: "20 gün tutsun, sonra geriye
  /// doğru otomatik silsin" — telefon şişmesin):
  /// * [saklaGun] günden eski HER yedek silinir (iç ve dış klasör);
  /// * otomatik yedeklerin son 24 saattekilerinin hepsi kalır, daha eskilerden
  ///   her gün için yalnız o günün EN YENİSİ kalır (en çok ~25 dosya);
  /// * işlem öncesi ve elle alınan .db yedekler 20 gün kalır, en çok [islemOncesiSakla].
  static const saklaGun = 20;
  static const islemOncesiSakla = 30;

  /// Dış klasördeki her yedek (.json otomatik/işlem + elle alınan .db).
  static final _disAdKalibi =
      RegExp(r'^sutyem_(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})_([a-z]+)[a-z0-9_]*\.(json|db)$');

  static DateTime _damgaCoz(String g) => DateTime(
        int.parse(g.substring(0, 4)), int.parse(g.substring(5, 7)), int.parse(g.substring(8, 10)),
        int.parse(g.substring(11, 13)), int.parse(g.substring(14, 16)), int.parse(g.substring(17, 19)),
      );

  /// Saklama kuralına göre silinecek yedeklerin anahtarları.
  /// [otomatikMi] true olanlara günlük seyreltme uygulanır.
  static Set<K> silinecekler<K>(Iterable<({K anahtar, DateTime tarih, bool otomatikMi})> yedekler, DateTime simdi) {
    final sil = <K>{};
    final sinir = simdi.subtract(const Duration(days: saklaGun));
    final gunSonu = simdi.subtract(const Duration(hours: 24));
    final sirali = yedekler.toList()..sort((a, b) => b.tarih.compareTo(a.tarih)); // en yeni önce
    final gorulenGun = <String>{};
    var digerSayi = 0;
    for (final y in sirali) {
      if (y.tarih.isBefore(sinir)) {
        sil.add(y.anahtar);
      } else if (y.otomatikMi) {
        if (y.tarih.isAfter(gunSonu)) continue;
        final gun = '${y.tarih.year}-${y.tarih.month}-${y.tarih.day}';
        if (!gorulenGun.add(gun)) sil.add(y.anahtar);
      } else if (++digerSayi > islemOncesiSakla) {
        sil.add(y.anahtar);
      }
    }
    return sil;
  }

  static final _damga = DateFormat('yyyy-MM-dd_HH-mm-ss');
  static final _adKalibi = RegExp(r'^sutyem_(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})_([a-z]+)(?:_([a-z0-9_]+))?\.json$');

  static Future<Directory> varsayilanKlasor() async =>
      Directory(p.join((await getApplicationDocumentsDirectory()).path, klasorAdi));

  /// Android'de ortak İndirilenler/[disKlasorAdi]; başka platformda null.
  /// (Android 11+ izin istemeden kendi oluşturduğu dosyaları yazabilir;
  /// Android 10'da requestLegacyExternalStorage, 9 ve altında depolama izni gerekir.)
  static Directory? varsayilanDisKlasor() =>
      Platform.isAndroid ? Directory('/storage/emulated/0/Download/$disKlasorAdi') : null;

  /// Uygulamanın gerçek veritabanı ve klasörüyle.
  static Future<OtomatikYedek> uygulama() async => OtomatikYedek(
        await AppDatabase.instance.database,
        await varsayilanKlasor(),
        disKlasor: varsayilanDisKlasor(),
      );

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
    final an = simdi ?? DateTime.now();
    await _temizle(an);
    await _disKopyala(hedef, an);
    return hedef;
  }

  /// Yedeğin uygulama silinince de kalan kopyası. ASLA hata fırlatmaz.
  Future<void> _disKopyala(File yedek, DateTime simdi) async {
    final dis = disKlasor;
    if (dis == null) return;
    try {
      await dosyayiKlasoreYaz(yedek, dis);
      sonDisHata = null;
    } catch (e) {
      sonDisHata = e;
      debugPrint('[OtomatikYedek] dış kopya yazılamadı: $e');
      return;
    }
    await disKlasoruTemizle(dis, simdi);
  }

  /// [kaynak]'ı aynı adla [klasor]'e önce .tmp olarak yazıp sonra adlandırır.
  static Future<File> dosyayiKlasoreYaz(File kaynak, Directory klasor) async {
    await klasor.create(recursive: true);
    final hedef = File(p.join(klasor.path, p.basename(kaynak.path)));
    final gecici = File('${hedef.path}.tmp');
    await kaynak.copy(gecici.path);
    await gecici.rename(hedef.path);
    return hedef;
  }

  /// Dış klasöre saklama kuralını uygular (yalnız bu kurulumun yazdıkları
  /// görünür/silinebilir; silinemeyen dosya sessizce geçilir).
  static Future<void> disKlasoruTemizle(Directory dis, DateTime simdi) async {
    try {
      if (!await dis.exists()) return;
      final adaylar = <({File anahtar, DateTime tarih, bool otomatikMi})>[];
      await for (final f in dis.list()) {
        if (f is! File) continue;
        final ad = p.basename(f.path);
        if (ad.endsWith('.tmp')) {
          try {
            await f.delete();
          } catch (_) {}
          continue;
        }
        final m = _disAdKalibi.firstMatch(ad);
        if (m == null) continue;
        adaylar.add((anahtar: f, tarih: _damgaCoz(m.group(1)!), otomatikMi: m.group(2) == YedekSebebi.otomatik.kod));
      }
      for (final f in silinecekler(adaylar, simdi)) {
        try {
          await f.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// "DB Yedekle": veritabanının tutarlı kopyasını telefonda saklar
  /// (Android: İndirilenler/[disKlasorAdi], uygulama silinse de kalır).
  /// Geri yükleme: Yedekleme → İçeri Al → Veritabanı (.db).
  static Future<File> veritabaniYedekAl({
    required Future<void> Function(String hedef) kopyala,
    required Future<void> Function(String yol) dogrula,
    Directory? hedefKlasor,
    DateTime? simdi,
  }) async {
    final an = simdi ?? DateTime.now();
    final klasor = hedefKlasor ?? varsayilanDisKlasor() ?? await varsayilanKlasor();
    final gecici = File(p.join(Directory.systemTemp.path, 'sutyem_${_damga.format(an)}_veritabani.db'));
    if (await gecici.exists()) await gecici.delete();
    await kopyala(gecici.path);
    await dogrula(gecici.path);
    try {
      final hedef = await dosyayiKlasoreYaz(gecici, klasor);
      await disKlasoruTemizle(klasor, an);
      return hedef;
    } finally {
      try {
        await gecici.delete();
      } catch (_) {}
    }
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
      final tarih = _damgaCoz(m.group(1)!);
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

  Future<void> _temizle(DateTime simdi) async {
    final liste = await listele();
    final sil = silinecekler(
      [for (final y in liste) (anahtar: y, tarih: y.tarih, otomatikMi: y.sebep == YedekSebebi.otomatik)],
      simdi,
    );
    for (final y in sil) {
      try {
        await y.dosya.delete();
      } catch (_) {}
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
