import 'package:intl/intl.dart';

import '../models/cari_model.dart';
import '../models/sut_model.dart';
import '../models/urun_model.dart';
import '../models/yem_model.dart';
import '../utils/sayi_format.dart';
import 'whatsapp_service.dart';

/// Birden çok cariye WhatsApp mesajı göndermenin sonucu.
class TopluGonderimSonucu {
  int gonderilen = 0;
  final List<String> telefonsuz = [];
  final List<String> basarisiz = [];

  int get toplam => gonderilen + telefonsuz.length + basarisiz.length;

  /// Kullanıcıya gösterilecek özet. [ne]: "süt raporu", "mesaj" vb.
  String ozet(String ne) {
    final b = StringBuffer('✅ $gonderilen cariye $ne gönderildi');
    if (basarisiz.isNotEmpty) {
      b.write('\n❌ ${basarisiz.length} cariye gönderilemedi: ${basarisiz.join(', ')}');
    }
    if (telefonsuz.isNotEmpty) {
      b.write('\n📞 Telefonu olmayan/geçersiz: ${telefonsuz.join(', ')}');
    }
    return b.toString();
  }
}

/// Bir cari için mesaj üretir; `null` dönerse o cari atlanır.
typedef MesajUretici = Future<String> Function(Cari cari);

/// Toplu WhatsApp gönderimi. Bir carideki hata diğerlerini durdurmaz;
/// her gönderimin gerçek sonucu sayılır.
class TopluMesajServisi {
  final Future<bool> Function(String telefon, String mesaj) _gonder;
  final Duration bekleme;

  TopluMesajServisi({
    Future<bool> Function(String telefon, String mesaj)? gonderici,
    this.bekleme = const Duration(seconds: 3),
  }) : _gonder = gonderici ?? WhatsAppService.sendToWhatsApp;

  Future<TopluGonderimSonucu> gonder(
    List<Cari> cariler,
    MesajUretici uret, {
    void Function(int sira, int toplam)? ilerleme,
  }) async {
    final sonuc = TopluGonderimSonucu();
    for (var i = 0; i < cariler.length; i++) {
      final cari = cariler[i];
      final ad = '${cari.ad} ${cari.soyad}';
      ilerleme?.call(i + 1, cariler.length);

      final telefon = WhatsAppService.telefonNormalize(cari.telefon ?? '');
      if (telefon.isEmpty) {
        sonuc.telefonsuz.add(ad);
        continue;
      }
      try {
        final ok = await _gonder(telefon, await uret(cari));
        ok ? sonuc.gonderilen++ : sonuc.basarisiz.add(ad);
      } catch (_) {
        sonuc.basarisiz.add(ad);
      }
      if (i < cariler.length - 1 && bekleme > Duration.zero) {
        await Future.delayed(bekleme);
      }
    }
    return sonuc;
  }
}

/// Süt raporu toplamları: bugün, son 7 gün (bugün dahil), bu ay.
/// [sutler] en az son 7 günü ve ayın başını kapsamalı (bkz. [sutRaporuBaslangici]).
({double gunluk, double haftalik, double aylik}) sutRaporuToplamlari(
  List<Sut> sutler,
  DateTime bugun,
) {
  final f = DateFormat('yyyy-MM-dd');
  final gun = f.format(bugun);
  final haftaBas = f.format(DateTime(bugun.year, bugun.month, bugun.day - 6));
  final ayBas = f.format(DateTime(bugun.year, bugun.month, 1));
  double g = 0, h = 0, a = 0;
  for (final s in sutler) {
    final t = s.tarih.length >= 10 ? s.tarih.substring(0, 10) : s.tarih;
    if (t.compareTo(gun) > 0) continue;
    if (t == gun) g += s.toplam;
    if (t.compareTo(haftaBas) >= 0) h += s.toplam;
    if (t.compareTo(ayBas) >= 0) a += s.toplam;
  }
  return (gunluk: g, haftalik: h, aylik: a);
}

/// Süt raporu için çekilmesi gereken ilk gün: ayın başı ile 6 gün öncesinden erken olanı.
DateTime sutRaporuBaslangici(DateTime bugun) {
  final ayBas = DateTime(bugun.year, bugun.month, 1);
  final haftaBas = DateTime(bugun.year, bugun.month, bugun.day - 6);
  return haftaBas.isBefore(ayBas) ? haftaBas : ayBas;
}

/// Yem raporu: toplam kg (yalnız birimi kg olan ürünler) ve gün gün tüm ürünlerin
/// dökümü. Aynı günün ürünleri tek satırda: "01.11.2026: Süt Yemi: 25 kg, Gübre: 2 çuval".
({double toplam, String detay}) yemRaporuDetayi(List<Yem> yemler, Map<int, Urun> urunler) {
  double toplam = 0;
  final gunler = <String, List<String>>{};
  // Tarih, sonra kayıt sırası (id); eşitlikte gelen sıra korunur (Dart'ın sort'u kararlı değildir).
  final sirali = [for (var i = 0; i < yemler.length; i++) (i, yemler[i])]..sort((a, b) {
      final t = a.$2.tarih.compareTo(b.$2.tarih);
      if (t != 0) return t;
      final k = (a.$2.id ?? 0).compareTo(b.$2.id ?? 0);
      return k != 0 ? k : a.$1.compareTo(b.$1);
    });
  for (final (_, y) in sirali) {
    if (y.miktar <= 0) continue;
    final u = urunler[y.urunId];
    if (u?.kgMi ?? true) toplam += y.miktar;
    gunler
        .putIfAbsent(y.tarih.substring(0, 10), () => [])
        .add('${u?.ad ?? 'Ürün'}: ${sayiGoster(y.miktar)} ${u?.birim ?? ''}'.trimRight());
  }
  final satirlar = [
    for (final e in gunler.entries) '${DateFormat('dd.MM.yyyy').format(DateTime.parse(e.key))}: ${e.value.join(', ')}',
  ];
  return (toplam: toplam, detay: satirlar.join('\n'));
}
