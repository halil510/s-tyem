/// Bluetooth aramasında bulunan cihaz (fiş yazıcısı ve terazi ekranları ortak kullanır).
class BtCihaz {
  final String ad; // boş = isimsiz
  final String adres;
  final int? rssi; // sinyal gücü (yakınlık); bilinmiyorsa null
  final bool eslesmis;
  const BtCihaz({required this.ad, required this.adres, this.rssi, this.eslesmis = false});

  bool get isimsiz => ad.trim().isEmpty || ad.trim().toLowerCase() == 'unknown device';
  String get gorunenAd => isimsiz ? '(İsimsiz cihaz)' : ad.trim();
}

enum BtAranan { yazici, terazi }

/// ─────────────────────────────────────────────────────────────
/// Bluetooth aramasında etraftaki HER cihaz (telefon, saat, kulaklık, TV…) çıkar.
/// Bu süzgeç: isimsizleri (istenmedikçe) gizler, adı aranan cihaza benzeyenleri
/// ("POS-58", "PT-210", "HC-05", "Scale"…) en üste alır, sonra eşleşmişleri, sonra
/// sinyali güçlü (yakın) olanları.
/// ─────────────────────────────────────────────────────────────
class BtCihazSuzgeci {
  static const _yaziciIpuclari = [
    'print', 'yazici', 'yazıcı', 'pos', 'pt-', 'pt2', 'mpt', 'mtp', 'rpp', 'xp-', 'xp5', 'xp8', 'zj', 'gp-', 'gprinter', 'hprt', 'hoin',
    'goojprt', 'munbyn', 'bixolon', 'spp-r', 'epson', 'tm-', 'sunmi', 'inner', 'thermal', 'termal', 'receipt', 'fis', 'fiş', '58mm', '80mm',
    'bt-58', 'bt58', 'mp-58', 'qs-', 'issyzone', 'netum', 'rongta', 'xprinter', 'cashino',
  ];
  static const _teraziIpuclari = [
    'terazi', 'tarti', 'tartı', 'kantar', 'scale', 'weigh', 'hc-05', 'hc-06', 'hc05', 'hc06', 'hc-08', 'jdy', 'bt05', 'bt-05', 'hm-10',
    'hm10', 'at-09', 'rs232', 'serial', 'uart', 'spp', 'bluno', 'dx-', 'ble-', 'dibal', 'baykon', 'tunaylar',
  ];

  /// Ad aranan cihaza benziyor mu?
  static bool benziyor(String ad, BtAranan aranan) {
    final a = ad.toLowerCase();
    return (aranan == BtAranan.yazici ? _yaziciIpuclari : _teraziIpuclari).any(a.contains);
  }

  /// Aynı adresi tekleştirir (eşleşmiş bilgi ve en güçlü sinyal korunur), isimsizleri
  /// [isimsizleriGoster] değilse atar ve sıralar.
  static List<BtCihaz> sirala(Iterable<BtCihaz> cihazlar, BtAranan aranan, {bool isimsizleriGoster = false}) {
    final tek = <String, BtCihaz>{};
    for (final c in cihazlar) {
      final o = tek[c.adres];
      tek[c.adres] = o == null
          ? c
          : BtCihaz(
              ad: o.isimsiz ? c.ad : o.ad,
              adres: c.adres,
              rssi: [o.rssi, c.rssi].whereType<int>().fold<int?>(null, (m, v) => m == null || v > m ? v : m),
              eslesmis: o.eslesmis || c.eslesmis,
            );
    }
    int puan(BtCihaz c) => (benziyor(c.ad, aranan) ? 4 : 0) + (c.eslesmis ? 2 : 0) + (c.isimsiz ? 0 : 1);
    return tek.values.where((c) => isimsizleriGoster || !c.isimsiz).toList()
      ..sort((x, y) {
        final p = puan(y).compareTo(puan(x));
        if (p != 0) return p;
        final r = (y.rssi ?? -999).compareTo(x.rssi ?? -999);
        return r != 0 ? r : x.gorunenAd.toLowerCase().compareTo(y.gorunenAd.toLowerCase());
      });
  }

  static int isimsizSayisi(Iterable<BtCihaz> cihazlar) => {for (final c in cihazlar) if (c.isimsiz) c.adres}.length;
}
