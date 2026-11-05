import 'package:intl/intl.dart';

import 'sayi_format.dart';

/// Hesap ekstresinin Excel ve PDF çıktıları için ORTAK satır hazırlığı:
/// eskiden yeniye sıralama, yürüyen bakiye, dönem ve bakiye etiketleri.
/// (Excel ile PDF aynı ekstrede farklı rakam/etiket göstermesin diye tek yer.)
class EkstreSatiri {
  final String tarih; // 'dd.MM.yyyy'
  final String islemAdi;
  final String aciklama;
  final double? alacak; // süt, tahsilat
  final double? borc; // yem, ödeme
  final double bakiye; // bu satıra kadarki yürüyen bakiye

  const EkstreSatiri({
    required this.tarih,
    required this.islemAdi,
    required this.aciklama,
    this.alacak,
    this.borc,
    required this.bakiye,
  });
}

/// [hareketler]: {tarih ('yyyy-MM-dd'), islemAdi, kredi(bool), tutar, aciklama}.
/// Girdi sırası önemsiz (ekrandaki yeni→eski sıra gelir); çıktı eskiden yeniye,
/// aynı günde verilen sıra korunur (süt, yem, ödeme, tahsilat).
List<EkstreSatiri> ekstreSatirlari(List<Map<String, dynamic>> hareketler) {
  final sirali = [for (var i = 0; i < hareketler.length; i++) (i, hareketler[i])]
    ..sort((a, b) {
      final t = (a.$2['tarih'] as String).compareTo(b.$2['tarih'] as String);
      return t != 0 ? t : a.$1.compareTo(b.$1);
    });
  var bakiye = 0.0;
  return [
    for (final (_, h) in sirali)
      () {
        final kredi = h['kredi'] as bool;
        final tutar = kurusaYuvarla((h['tutar'] as num).toDouble());
        bakiye = kurusaYuvarla(bakiye + (kredi ? tutar : -tutar));
        return EkstreSatiri(
          tarih: ekstreTarihi(h['tarih'] as String),
          islemAdi: h['islemAdi'] as String,
          aciklama: h['aciklama'] as String? ?? '',
          alacak: kredi ? tutar : null,
          borc: kredi ? null : tutar,
          bakiye: bakiye,
        );
      }(),
  ];
}

String ekstreTarihi(String tarih) {
  try {
    return DateFormat('dd.MM.yyyy').format(DateTime.parse(tarih));
  } catch (_) {
    return tarih;
  }
}

/// "Tüm zamanlar" ya da "Dönem: 01.11.2026 – 30.11.2026".
String ekstreDonemYazisi(DateTime? baslangic, DateTime? bitis) {
  if (baslangic == null && bitis == null) return 'Tüm zamanlar';
  final tf = DateFormat('dd.MM.yyyy');
  return 'Dönem: ${baslangic != null ? tf.format(baslangic) : 'başlangıç'} – '
      '${bitis != null ? tf.format(bitis) : 'bugün'}';
}

/// (cari ALACAKLI — işletme ödeyecek) / (cari BORÇLU) / (hesap kapalı)
String ekstreDurumu(double bakiye) => bakiye > 0.005
    ? 'cari ALACAKLI — işletme ödeyecek'
    : bakiye < -0.005
        ? 'cari BORÇLU'
        : 'hesap kapalı';

/// Filtreli ekstrede son rakam DÖNEM NETİ'dir, tüm zamanların bakiyesi değil.
String ekstreBakiyeEtiketi({required bool filtreli}) => filtreli ? 'DÖNEM NETİ' : 'NET BAKİYE';

const ekstreDonemNotu =
    'Not: Yalnız seçilen tarih aralığının hareketleridir; önceki dönemlerin devri dahil değildir.';
