import 'package:intl/intl.dart';

import '../../utils/sayi_format.dart';
import '../cari_hesap/models/cari_hareket.dart';
import 'uretici_fisi.dart';

/// Ödeme (işletme → üretici) ya da tahsilat (üretici → işletme) fişi.
///
/// Fiş üreticiye hitap eder; bakiye işareti uygulamanın iş mantığıyla aynı:
/// bakiye > 0 → işletme üreticiye borçlu ("Alacağınız"),
/// bakiye < 0 → üretici işletmeye borçlu ("Borcunuz").
class OdemeFisi implements Fis {
  final String isletmeAdi;
  final String isletmeTelefon;
  final String isletmeAdres;
  final String altYazi;

  /// `cari_odemeler.id`
  final int? fisNo;

  /// true → tahsilat (cariden alınan), false → ödeme (cariye verilen).
  final bool tahsilatMi;
  final DateTime tarih;
  final DateTime basimZamani;
  final String ureticiAdi;
  final double tutar;
  final String? aciklama;

  /// Bu hareketten hemen önceki bakiye (hareketin gününe kadarki süt/yem dahil).
  final double oncekiBakiye;

  /// Fiş tarihinden SONRA da hareket varsa bugünkü bakiye (geçmiş fiş yeniden basılırken).
  final double? guncelBakiye;

  const OdemeFisi({
    required this.isletmeAdi,
    this.isletmeTelefon = '',
    this.isletmeAdres = '',
    this.altYazi = 'Teşekkür ederiz',
    required this.fisNo,
    required this.tahsilatMi,
    required this.tarih,
    required this.basimZamani,
    required this.ureticiAdi,
    required this.tutar,
    this.aciklama,
    required this.oncekiBakiye,
    this.guncelBakiye,
  });

  /// Ödeme bakiyeyi azaltır, tahsilat artırır.
  double get kalanBakiye => kurusaYuvarla(oncekiBakiye + (tahsilatMi ? tutar : -tutar));

  @override
  String get baslik => tahsilatMi ? 'Tahsilat Fişi' : 'Ödeme Fişi';

  static final _para = NumberFormat('#,##0.00', 'tr_TR');

  /// Yazıcıda ₺ basılamadığı için her yerde "TL".
  static String tl(double v) => '${_para.format(v.abs())} TL';

  static String _bakiyeEtiketi(String on, double b) =>
      b > 0.005 ? '$on Alacağınız' : (b < -0.005 ? '$on Borcunuz' : '$on Bakiye');

  @override
  List<FisSatiri> satirlar(int genislik) {
    final cizgi = FisSatiri('-' * genislik);
    FisSatiri ikili(String sol, String sag, {bool kalin = false}) =>
        FisSatiri(solSag(sol, sag, genislik), kalin: kalin);
    final aciklamaMetni = aciklama?.trim() ?? '';

    return [
      FisSatiri(tahsilatMi ? 'TAHSİLAT FİŞİ' : 'ÖDEME FİŞİ', ortala: true, kalin: true, buyuk: true),
      if (isletmeAdi.trim().isNotEmpty)
        for (final s in sar(isletmeAdi.trim(), genislik)) FisSatiri(s, ortala: true),
      if (isletmeAdres.trim().isNotEmpty)
        for (final s in sar(isletmeAdres.trim(), genislik)) FisSatiri(s, ortala: true),
      if (isletmeTelefon.trim().isNotEmpty) FisSatiri('Tel: ${isletmeTelefon.trim()}', ortala: true),
      cizgi,
      if (fisNo != null) ikili('Fiş No', '$fisNo'),
      ikili('Tarih', DateFormat('dd.MM.yyyy').format(tarih)),
      ikili('Basım', DateFormat('dd.MM.yyyy HH:mm').format(basimZamani)),
      for (final (i, s) in sar(ureticiAdi, genislik - 9).indexed)
        FisSatiri('${i == 0 ? 'Üretici:' : ''.padRight(8)} $s'),
      cizgi,
      ikili(_bakiyeEtiketi('Önceki', oncekiBakiye), tl(oncekiBakiye)),
      ikili(tahsilatMi ? 'Tahsil Edilen' : 'Ödenen', '${tahsilatMi ? '+' : '-'}${tl(tutar)}', kalin: true),
      if (aciklamaMetni.isNotEmpty)
        for (final s in sar(aciklamaMetni, genislik - 2)) FisSatiri('  $s'),
      cizgi,
      kalanBakiye.abs() <= 0.005
          ? ikili('KALAN BAKİYE', 'HESAP KAPANDI', kalin: true)
          : ikili(_bakiyeEtiketi('Kalan', kalanBakiye).toUpperCase(), tl(kalanBakiye), kalin: true),
      if (guncelBakiye != null && (guncelBakiye! - kalanBakiye).abs() > 0.005)
        ikili(_bakiyeEtiketi('Bugünkü', guncelBakiye!), tl(guncelBakiye!)),
      FisSatiri.bos,
      FisSatiri.bos,
      ikili('Teslim Eden', 'Teslim Alan'),
      FisSatiri.bos,
      ikili('.' * (genislik ~/ 2 - 3), '.' * (genislik ~/ 2 - 3)),
      if (altYazi.trim().isNotEmpty) ...[
        FisSatiri.bos,
        for (final s in sar(altYazi.trim(), genislik)) FisSatiri(s, ortala: true),
      ],
    ];
  }

  @override
  String whatsappMetni({int genislik = 32}) => fisWhatsappMetni(this, genislik);
}

/// Hesap ekstresindeki (TÜM ZAMANLAR, filtresiz) hareketlerden ödeme/tahsilat
/// fişi kurar. Önceki bakiye = o hareketten önceki her şey; aynı gün içinde
/// süt ve yem ÖDEMEDEN ÖNCE sayılır (günün sütü/yemi düşüldükten sonra ödenir).
/// Kayıt bulunamazsa null.
OdemeFisi? odemeFisiOlustur({
  required List<CariHareket> tumHareketler,
  required int kayitId,
  required String ureticiAdi,
  required String isletmeAdi,
  String isletmeTelefon = '',
  String isletmeAdres = '',
  String altYazi = 'Teşekkür ederiz',
  DateTime? simdi,
}) {
  final hedef = tumHareketler.where((h) => h.kayitId == kayitId).firstOrNull;
  if (hedef == null || (hedef.tur != 'odeme' && hedef.tur != 'tahsilat')) return null;

  const turSirasi = {'sut': 0, 'yem': 1, 'odeme': 2, 'tahsilat': 3};
  final sirali = [...tumHareketler]..sort((a, b) {
      final t = a.tarih.compareTo(b.tarih);
      if (t != 0) return t;
      final s = (turSirasi[a.tur] ?? 9).compareTo(turSirasi[b.tur] ?? 9);
      return s != 0 ? s : (a.kayitId ?? 0).compareTo(b.kayitId ?? 0);
    });

  double etki(CariHareket h) => h.kredi ? h.tutar : -h.tutar;
  var onceki = 0.0;
  var toplam = 0.0;
  var bulundu = false;
  for (final h in sirali) {
    if (identical(h, hedef)) bulundu = true;
    if (!bulundu) onceki += etki(h);
    toplam += etki(h);
  }

  return OdemeFisi(
    isletmeAdi: isletmeAdi,
    isletmeTelefon: isletmeTelefon,
    isletmeAdres: isletmeAdres,
    altYazi: altYazi,
    fisNo: kayitId,
    tahsilatMi: hedef.tur == 'tahsilat',
    tarih: hedef.tarih,
    basimZamani: simdi ?? DateTime.now(),
    ureticiAdi: ureticiAdi,
    tutar: hedef.tutar,
    aciklama: hedef.aciklama,
    oncekiBakiye: kurusaYuvarla(onceki),
    guncelBakiye: kurusaYuvarla(toplam),
  );
}
