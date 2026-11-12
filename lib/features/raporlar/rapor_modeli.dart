import 'package:intl/intl.dart';

import '../../utils/sayi_format.dart';

final _kg = NumberFormat('#,##0.##', 'tr_TR');
final _tl = NumberFormat('#,##0.00', 'tr_TR');

/// Türkçe biçim: 1.234,5
String kgYaz(num v) => _kg.format(v);

/// Türkçe biçim: 1.234,50 TL
String tlYaz(num v) => '${_tl.format(v)} TL';

/// Hücre metni (ekran ve PDF aynı).
String hucreMetni(RaporSutun s, Object? v) {
  if (v == null) return '';
  return switch (s.tip) {
    SutunTipi.para => tlYaz(v as num),
    SutunTipi.miktar => kgYaz(v as num),
    SutunTipi.sayi => '$v',
    SutunTipi.tarih => v is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v) ? '${v.substring(8, 10)}.${v.substring(5, 7)}.${v.substring(0, 4)}' : '$v',
    SutunTipi.metin => '$v',
  };
}

/// Rapor sütununun türü: gösterim, Excel hücresi ve toplam buna göre.
enum SutunTipi {
  metin,
  tarih, // 'yyyy-MM-dd' → 12.11.2026
  miktar, // kg
  para, // TL (kuruşa yuvarlı double)
  sayi, // adet (gün, cari sayısı)
}

class RaporSutun {
  final String ad;
  final SutunTipi tip;

  /// Toplam satırında toplanır mı (fiyat, yürüyen bakiye, adet gibi sütunlarda toplanmaz).
  final bool toplanir;
  const RaporSutun(this.ad, [this.tip = SutunTipi.metin, bool? toplanir])
      : toplanir = toplanir ?? (tip == SutunTipi.miktar || tip == SutunTipi.para);

  bool get sayisal => tip == SutunTipi.miktar || tip == SutunTipi.para || tip == SutunTipi.sayi;
}

/// Ekranda tablo, Excel ve PDF'in TEK veri kaynağı.
class RaporTablosu {
  final String baslik;
  final String altBaslik;
  final List<RaporSutun> sutunlar;
  final List<List<Object?>> satirlar;
  final bool toplamSatiri;

  /// Tablonun altında gösterilen not (ör. "3 kayıtta fiyat eksik").
  final String? not;

  const RaporTablosu({
    required this.baslik,
    required this.altBaslik,
    required this.sutunlar,
    required this.satirlar,
    this.toplamSatiri = true,
    this.not,
  });

  /// Toplam satırı: ilk sütun "TOPLAM", toplanan sütunlar kuruşa yuvarlı toplam, diğerleri boş.
  List<Object?> get toplamlar => [
        for (var i = 0; i < sutunlar.length; i++)
          if (i == 0)
            'TOPLAM'
          else if (sutunlar[i].toplanir)
            kurusaYuvarla(satirlar.fold<double>(0, (a, s) => a + ((s[i] as num?)?.toDouble() ?? 0)))
          else
            null,
      ];
}

class RaporFiltresi {
  final String bas; // 'yyyy-MM-dd'
  final String bit;
  final int? cariId;
  const RaporFiltresi({required this.bas, required this.bit, this.cariId});
}

/// Raporlar ekranındaki gruplar.
const raporGruplari = {
  'sut': 'Süt',
  'yem': 'Yem',
  'hesap': 'Cari Hesap ve Ödemeler',
  'kontrol': 'Kontrol',
};

enum RaporTuru {
  gunlukSut('Süt Girişleri (gün gün)', 'sut', 'Her carinin her günkü sabah/akşam sütü, fiyatı ve tutarı', cariFiltresi: true),
  gunlukSutToplami('Günlük Toplam Süt', 'sut', 'Her gün toplanan toplam süt ve gelen üretici sayısı'),
  cariSutToplami('Cari Bazlı Süt Toplamı', 'sut', 'Seçilen dönemde her carinin süt toplamı ve tutarı'),
  aylikSut('Aylık Süt Karşılaştırması', 'sut', 'Ay ay toplam süt, tutar ve ortalama fiyat', yillikVarsayilan: true),
  yemTeslimleri('Yem Teslimleri', 'yem', 'Verilen her yem, türleriyle birlikte', cariFiltresi: true),
  yemTuruBazli('Yem Türü Bazlı', 'yem', 'Her yem türünden toplam kg ve tutar'),
  cariYemToplami('Cari Bazlı Yem Toplamı', 'yem', 'Seçilen dönemde her carinin aldığı yem'),
  cariHesapOzeti('Cari Hesap Özeti', 'hesap', 'Her cari için dönemin süt, yem, ödeme, tahsilatı ve genel bakiye'),
  bakiyeListesi('Bakiye Listesi', 'hesap', 'Bitiş tarihi itibarıyla her carinin bakiyesi (alacaklı/borçlu)'),
  odemeTahsilat('Ödeme ve Tahsilatlar', 'hesap', 'Carilere yapılan ödemeler ve alınan tahsilatlar', cariFiltresi: true),
  cariEkstre('Cari Ekstre', 'hesap', 'Bir carinin devirli, yürüyen bakiyeli hesap dökümü', cariFiltresi: true, cariZorunlu: true),
  fiyatEksik('Fiyatı Eksik Kayıtlar', 'kontrol', 'Miktarı olup fiyatı tanımlı olmadığı için 0 TL hesaplanan kayıtlar');

  final String baslik;
  final String grup;
  final String aciklama;
  final bool cariFiltresi;
  final bool cariZorunlu;
  final bool yillikVarsayilan;
  const RaporTuru(this.baslik, this.grup, this.aciklama, {this.cariFiltresi = false, this.cariZorunlu = false, this.yillikVarsayilan = false});
}
