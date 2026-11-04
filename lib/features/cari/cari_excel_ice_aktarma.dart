import 'package:excel/excel.dart';

import '../../models/cari_model.dart';
import '../../utils/turkce.dart';

export '../../utils/turkce.dart' show turkceKucuk;

/// Excel'den okunan bir cari adayı (henüz kaydedilmedi).
class CariAdayi {
  final String ad;
  final String soyad;
  final String? telefon;
  final String? adres;

  /// Excel'deki satır numarası (1'den başlar) — kullanıcıya göstermek için.
  final int satir;

  const CariAdayi({required this.ad, required this.soyad, this.telefon, this.adres, required this.satir});

  String get tamAd => '$ad $soyad'.trim();
}

/// Excel dosyasının okunma sonucu.
class CariExcelSonucu {
  final String sayfa;
  final List<CariAdayi> adaylar;

  /// Okunup alınmayan satırlar ve nedeni (ör. "12. satır: toplam satırı").
  final List<String> atlananlar;

  const CariExcelSonucu({required this.sayfa, required this.adaylar, required this.atlananlar});
}

class CariExcelHatasi implements Exception {
  final String mesaj;
  const CariExcelHatasi(this.mesaj);
  @override
  String toString() => mesaj;
}

/// Karşılaştırma anahtarı: Türkçe küçük harf + tek boşluk.
String adAnahtari(String tamAd) => turkceKucuk(tamAd.trim().replaceAll(RegExp(r'\s+'), ' '));

/// "MEHMET ALİ YILMAZ" → ad "MEHMET ALİ", soyad "YILMAZ".
/// Tek kelimeyse soyad boş kalır.
({String ad, String soyad}) adSoyadAyir(String tamAd) {
  final kelimeler = tamAd.trim().split(RegExp(r'\s+')).where((k) => k.isNotEmpty).toList();
  if (kelimeler.isEmpty) return (ad: '', soyad: '');
  if (kelimeler.length == 1) return (ad: kelimeler.first, soyad: '');
  return (ad: kelimeler.sublist(0, kelimeler.length - 1).join(' '), soyad: kelimeler.last);
}

/// Excel'den cari listesi okur.
///
/// Desteklenen düzenler:
/// - Tek sütunda ad soyad ("İsim Soyisim", "Ad Soyad", "Cari", "Üretici"…) —
///   uygulamanın kendi Süt/Yem raporu Excel'i dahil.
/// - Ayrı "Ad" ve "Soyad" sütunları.
/// - İsteğe bağlı "Telefon" ve "Adres" sütunları.
/// - Başlık yoksa: ilk sütunu metin olan sütun ad soyad kabul edilir.
/// "Toplam" satırları, boş satırlar ve dosya içindeki tekrarlar atlanır.
/// Birden çok sayfa varsa en çok cari bulunan sayfa seçilir.
class CariExcelOkuyucu {
  static CariExcelSonucu oku(List<int> baytlar) {
    final Excel excel;
    try {
      excel = Excel.decodeBytes(baytlar);
    } catch (_) {
      throw const CariExcelHatasi(
          'Dosya okunamadı. Yalnızca .xlsx biçimindeki Excel dosyaları desteklenir '
          '(eski .xls dosyasını Excel\'de "Farklı Kaydet → .xlsx" ile dönüştürün).');
    }

    CariExcelSonucu? enIyi;
    for (final e in excel.tables.entries) {
      final sonuc = _sayfaOku(e.key, e.value);
      if (sonuc != null && (enIyi == null || sonuc.adaylar.length > enIyi.adaylar.length)) {
        enIyi = sonuc;
      }
    }
    if (enIyi == null || enIyi.adaylar.isEmpty) {
      throw const CariExcelHatasi(
          'Dosyada cari ismi bulunamadı. İlk satırda "Ad Soyad" (ya da "Ad" ve "Soyad") '
          'başlığı olan bir sütun bekleniyor.');
    }
    return enIyi;
  }

  static String _metin(Data? h) {
    final v = h?.value;
    if (v == null) return '';
    // Telefon gibi sayılar Excel'de 5551234567.0 olarak gelir.
    if (v is double && v == v.roundToDouble()) return v.toInt().toString();
    return v.toString().trim();
  }

  /// İsim sütunu sanılmaması gereken başlık kelimeleri ("Cari Kodu", "Müşteri No"…).
  static const _isimDegil = {'kod', 'kodu', 'no', 'numara', 'numarası', 'id', 'bakiye', 'tutar', 'borç', 'alacak'};

  static bool _eslesir(String baslik, List<String> kaliplar) {
    final b = turkceKucuk(baslik).replaceAll(RegExp(r'[^a-zçğıöşü ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (b.split(' ').any(_isimDegil.contains)) return false;
    return kaliplar.any((k) => b == k || b.startsWith('$k ') || b.endsWith(' $k') || b.contains(' $k '));
  }

  static const _tamAdKaliplari = [
    'isim soyisim', 'ad soyad', 'adı soyadı', 'adi soyadi', 'ad soyadı', 'isim', 'cari', 'cari adı',
    'üretici', 'müşteri', 'ünvan', 'unvan',
  ];
  static const _adKaliplari = ['ad', 'adı', 'adi'];
  static const _soyadKaliplari = ['soyad', 'soyadı', 'soyadi'];
  static const _telKaliplari = ['telefon', 'tel', 'gsm', 'cep', 'cep telefonu'];
  static const _adresKaliplari = ['adres', 'köy', 'mahalle'];

  static CariExcelSonucu? _sayfaOku(String sayfaAdi, Sheet sayfa) {
    final satirlar = sayfa.rows;
    if (satirlar.isEmpty) return null;

    // Başlık satırını ilk 5 satırda ara.
    int? baslikSatiri, tamAdSut, adSut, soyadSut, telSut, adresSut;
    for (var r = 0; r < satirlar.length && r < 5 && baslikSatiri == null; r++) {
      final hucreler = [for (final h in satirlar[r]) _metin(h)];
      int? bul(List<String> k) {
        for (var c = 0; c < hucreler.length; c++) {
          if (hucreler[c].isNotEmpty && _eslesir(hucreler[c], k)) return c;
        }
        return null;
      }

      final soyad = bul(_soyadKaliplari);
      final tamAd = bul(_tamAdKaliplari);
      // "Ad Soyad" tek başlıksa soyad kalıbı da ona uyar; ayrı sütun sayılmaz.
      final ad = soyad != null && soyad != tamAd ? bul(_adKaliplari) : null;
      if (tamAd != null || (ad != null && soyad != null)) {
        baslikSatiri = r;
        if (ad != null && soyad != null && ad != soyad && tamAd != ad) {
          adSut = ad;
          soyadSut = soyad;
        } else {
          tamAdSut = tamAd ?? ad;
        }
        telSut = bul(_telKaliplari);
        adresSut = bul(_adresKaliplari);
      }
    }

    // Başlık yoksa: ilk satırlarda metin içeren ilk sütun.
    if (baslikSatiri == null) {
      for (var c = 0; c < (satirlar.first.length); c++) {
        final metinli = satirlar.take(10).where((s) {
          final m = c < s.length ? _metin(s[c]) : '';
          return m.isNotEmpty && double.tryParse(m.replaceAll(',', '.')) == null;
        }).length;
        if (metinli >= 1) {
          tamAdSut = c;
          break;
        }
      }
      if (tamAdSut == null) return null;
    }

    String hucre(List<Data?> s, int? c) => c == null || c >= s.length ? '' : _metin(s[c]);

    final adaylar = <CariAdayi>[];
    final atlananlar = <String>[];
    final gorulen = <String>{};
    for (var r = (baslikSatiri ?? -1) + 1; r < satirlar.length; r++) {
      final s = satirlar[r];
      final no = r + 1;
      String ad, soyad;
      if (adSut != null) {
        ad = hucre(s, adSut);
        soyad = hucre(s, soyadSut);
      } else {
        final p = adSoyadAyir(hucre(s, tamAdSut));
        ad = p.ad;
        soyad = p.soyad;
      }
      ad = ad.replaceAll(RegExp(r'\s+'), ' ').trim();
      soyad = soyad.replaceAll(RegExp(r'\s+'), ' ').trim();
      final tam = '$ad $soyad'.trim();

      if (tam.isEmpty) continue; // boş satır: sessizce geç
      if (turkceKucuk(tam).contains('toplam')) {
        atlananlar.add('$no. satır: toplam satırı ("$tam")');
        continue;
      }
      if (double.tryParse(tam.replaceAll(',', '.')) != null) {
        atlananlar.add('$no. satır: isim değil ("$tam")');
        continue;
      }
      if (!gorulen.add(adAnahtari(tam))) {
        atlananlar.add('$no. satır: dosyada tekrar ("$tam")');
        continue;
      }
      final tel = hucre(s, telSut);
      final adres = hucre(s, adresSut);
      adaylar.add(CariAdayi(
        ad: ad,
        soyad: soyad,
        telefon: tel.isEmpty ? null : tel,
        adres: adres.isEmpty ? null : adres,
        satir: no,
      ));
    }
    return CariExcelSonucu(sayfa: sayfaAdi, adaylar: adaylar, atlananlar: atlananlar);
  }
}

/// Adayları mevcut carilerle karşılaştırır: aynı ad soyad (büyük/küçük harf
/// ve boşluk farkı gözetmeden, pasif cariler dahil) zaten kayıtlıysa yeni
/// sayılmaz.
({List<CariAdayi> yeni, List<CariAdayi> kayitli}) iceAktarmaPlani(
  List<CariAdayi> adaylar,
  List<Cari> mevcut,
) {
  final kayitliAdlar = {for (final c in mevcut) adAnahtari(c.tamAd)};
  final yeni = <CariAdayi>[], kayitli = <CariAdayi>[];
  for (final a in adaylar) {
    (kayitliAdlar.contains(adAnahtari(a.tamAd)) ? kayitli : yeni).add(a);
  }
  return (yeni: yeni, kayitli: kayitli);
}
