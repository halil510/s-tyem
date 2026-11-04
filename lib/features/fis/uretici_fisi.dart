import 'package:intl/intl.dart';

/// Fişteki bir satır. Ekrandaki önizleme, WhatsApp metni ve yazıcı
/// çıktısı AYNI satırlardan üretilir — görülen neyse basılan odur.
class FisSatiri {
  final String metin;
  final bool ortala;
  final bool kalin;

  /// Çift genişlik + çift yükseklik (yalnızca başlık için).
  final bool buyuk;

  const FisSatiri(this.metin, {this.ortala = false, this.kalin = false, this.buyuk = false});

  static const bos = FisSatiri('');
}

/// Üreticiye verilen günlük süt teslim fişi.
class UreticiFisi {
  final String isletmeAdi;
  final int? fisNo;
  final DateTime tarih;
  final DateTime basimZamani;
  final String ureticiAdi;
  final double sabah;
  final double aksam;

  /// Ayın 1'inden fiş tarihine kadar (dahil) toplam süt.
  final double buAyKg;

  const UreticiFisi({
    required this.isletmeAdi,
    required this.fisNo,
    required this.tarih,
    required this.basimZamani,
    required this.ureticiAdi,
    required this.sabah,
    required this.aksam,
    required this.buAyKg,
  });

  double get toplam => sabah + aksam;

  static final _kg = NumberFormat('#,##0.##', 'tr_TR');
  static String kg(double v) => '${_kg.format(v)} kg';

  /// [genislik]: satırdaki karakter sayısı (58 mm ≈ 32, 80 mm ≈ 48).
  List<FisSatiri> satirlar(int genislik) {
    final cizgi = FisSatiri('-' * genislik);
    FisSatiri ikili(String sol, String sag, {bool kalin = false}) =>
        FisSatiri(solSag(sol, sag, genislik), kalin: kalin);

    return [
      const FisSatiri('SÜT TESLİM FİŞİ', ortala: true, kalin: true, buyuk: true),
      if (isletmeAdi.trim().isNotEmpty)
        for (final s in sar(isletmeAdi.trim(), genislik)) FisSatiri(s, ortala: true),
      cizgi,
      if (fisNo != null) ikili('Fiş No', '$fisNo'),
      ikili('Tarih', DateFormat('dd.MM.yyyy').format(tarih)),
      ikili('Basım', DateFormat('dd.MM.yyyy HH:mm').format(basimZamani)),
      for (final (i, s) in sar(ureticiAdi, genislik - 9).indexed)
        FisSatiri('${i == 0 ? 'Üretici:' : ''.padRight(8)} $s'),
      cizgi,
      if (sabah > 0) ikili('Sabah', kg(sabah)),
      if (aksam > 0) ikili('Akşam', kg(aksam)),
      ikili('GÜNLÜK TOPLAM', kg(toplam), kalin: true),
      cizgi,
      ikili('Bu ay toplam', kg(buAyKg)),
      FisSatiri.bos,
      const FisSatiri('Teşekkür ederiz', ortala: true),
    ];
  }

  /// WhatsApp için: tek aralıklı (```) blok, yazıcıyla aynı düzen.
  String whatsappMetni({int genislik = 32}) =>
      '```\n${satirlar(genislik).map((s) => s.ortala ? ortalaMetin(s.metin, genislik) : s.metin).join('\n')}\n```';
}

/// Sol metni sola, sağ metni sağa yaslar; sığmazsa sol kısaltılır.
String solSag(String sol, String sag, int genislik) {
  final bosluk = genislik - sag.length - 1;
  if (bosluk <= 0) return sag.length > genislik ? sag.substring(0, genislik) : sag;
  final s = sol.length > bosluk ? sol.substring(0, bosluk) : sol;
  return '${s.padRight(bosluk)} $sag';
}

String ortalaMetin(String metin, int genislik) {
  if (metin.length >= genislik) return metin;
  return '${' ' * ((genislik - metin.length) ~/ 2)}$metin';
}

/// Uzun metni kelime sınırından satırlara böler.
List<String> sar(String metin, int genislik) {
  if (genislik <= 0) return [metin];
  final satirlar = <String>[];
  var satir = '';
  for (final kelime in metin.split(RegExp(r'\s+')).where((k) => k.isNotEmpty)) {
    var k = kelime;
    while (k.length > genislik) {
      if (satir.isNotEmpty) {
        satirlar.add(satir);
        satir = '';
      }
      satirlar.add(k.substring(0, genislik));
      k = k.substring(genislik);
    }
    if (satir.isEmpty) {
      satir = k;
    } else if (satir.length + 1 + k.length <= genislik) {
      satir = '$satir $k';
    } else {
      satirlar.add(satir);
      satir = k;
    }
  }
  if (satir.isNotEmpty) satirlar.add(satir);
  return satirlar.isEmpty ? [''] : satirlar;
}

/// ESC/POS komutları (Epson uyumlu termal yazıcılar).
///
/// Türkçe karakterler: çoğu ucuz yazıcı Türkçe kod sayfasını desteklemez;
/// varsayılan olarak harfler en yakın Latin harfine çevrilir (ş→s, İ→I).
/// Yazıcı CP857'yi destekliyorsa [turkceKodSayfasi] ile gerçek harfler basılır.
class EscPos {
  static const _esc = 0x1B, _gs = 0x1D, _lf = 0x0A;

  static const _ascii = {
    'ç': 'c', 'Ç': 'C', 'ğ': 'g', 'Ğ': 'G', 'ı': 'i', 'İ': 'I',
    'ö': 'o', 'Ö': 'O', 'ş': 's', 'Ş': 'S', 'ü': 'u', 'Ü': 'U',
    'â': 'a', 'Â': 'A', 'î': 'i', 'Î': 'I', 'û': 'u', 'Û': 'U', '₺': 'TL',
  };

  static const _cp857 = {
    'ç': 0x87, 'Ç': 0x80, 'ğ': 0xA7, 'Ğ': 0xA6, 'ı': 0x8D, 'İ': 0x98,
    'ö': 0x94, 'Ö': 0x99, 'ş': 0x9F, 'Ş': 0x9E, 'ü': 0x81, 'Ü': 0x9A,
    'â': 0x83, 'Â': 0xB6, 'î': 0x8C, 'û': 0x96,
  };

  /// Metni yazıcı baytlarına çevirir; bilinmeyen karakter '?' olur.
  static List<int> kodla(String metin, {bool turkceKodSayfasi = false}) {
    final b = <int>[];
    for (final r in metin.runes) {
      final c = String.fromCharCode(r);
      if (r < 0x80) {
        b.add(r);
      } else if (turkceKodSayfasi && _cp857.containsKey(c)) {
        b.add(_cp857[c]!);
      } else if (_ascii.containsKey(c)) {
        b.addAll(_ascii[c]!.codeUnits);
      } else {
        b.add(0x3F);
      }
    }
    return b;
  }

  static List<int> fis(List<FisSatiri> satirlar, {bool turkceKodSayfasi = false, bool kes = true}) {
    final b = <int>[
      _esc, 0x40, // başlat
      if (turkceKodSayfasi) ...[_esc, 0x74, 13], // kod sayfası PC857
    ];
    for (final s in satirlar) {
      b
        ..addAll([_esc, 0x61, s.ortala ? 1 : 0])
        ..addAll([_esc, 0x45, s.kalin ? 1 : 0])
        ..addAll([_gs, 0x21, s.buyuk ? 0x11 : 0x00])
        ..addAll(kodla(s.metin, turkceKodSayfasi: turkceKodSayfasi))
        ..add(_lf);
    }
    b.addAll([_esc, 0x61, 0, _esc, 0x45, 0, _gs, 0x21, 0]); // varsayılana dön
    b.addAll([_esc, 0x64, 4]); // kâğıdı kesme hizasına ilerlet
    if (kes) b.addAll([_gs, 0x56, 0x42, 0x00]); // kesici varsa kısmi kesim
    return b;
  }
}
