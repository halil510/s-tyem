import 'dart:async';

/// ─────────────────────────────────────────────────────────────
/// TERAZİ VERİ ÇÖZÜCÜ — ham bayt akışı → kilo
/// ─────────────────────────────────────────────────────────────
///
/// Terazi göstergeleri tartıyı satır satır gönderir
/// (ör. `ST,GS,+0025.40kg\r\n`). Ancak Bluetooth ve Wi-Fi bu satırları
/// PARÇALAR halinde iletebilir: `ST,GS,+0012` + `.80kg\r\n`. Eski kod her
/// parçayı ayrı tartı sayıyordu → ekranda bir an 12.00 / 80.00 görünüyor,
/// o an "Sabaha Uygula"ya basılırsa YANLIŞ kilo kaydediliyordu.
///
/// Bu sınıf:
/// - Parçaları biriktirir, satır sonu (`\r`, `\n`, ETX `0x03`) gelince
///   satırı çözer. Bir pakette birden çok satır varsa EN SONUNCUSU geçerlidir.
/// - Satır sonu göndermeyen teraziler için: [bosBekleme] süresince yeni veri
///   gelmezse bekleyen parça tam satır sayılır.
/// - Çözülemeyen satırları (ör. `OL` aşırı yük, `ST` durum) YOK SAYAR —
///   son geçerli tartı ekranda kalır (eskiden "0.00" basılıyordu).
class TeraziVeriCozucu {
  TeraziVeriCozucu(this._agirlik, {this.bosBekleme = const Duration(milliseconds: 200)});

  final void Function(double kg) _agirlik;
  final Duration bosBekleme;

  final StringBuffer _bekleyen = StringBuffer();
  Timer? _bosZamanlayici;

  /// Gelen ham parça.
  void ekle(String parca) {
    _bosZamanlayici?.cancel();
    _bekleyen.write(parca);
    final metin = _bekleyen.toString();
    final son = metin.lastIndexOf(_satirSonu);
    if (son >= 0) {
      _bekleyen.clear();
      _bekleyen.write(metin.substring(son + 1));
      final satirlar = metin.substring(0, son).split(_satirSonu);
      for (final satir in satirlar.reversed) {
        final kg = agirlikCoz(satir);
        if (kg != null) {
          _agirlik(kg);
          break;
        }
      }
    }
    // Aşırı uzun çöp birikmesin.
    if (_bekleyen.length > 256) _bekleyen.clear();
    if (_bekleyen.isNotEmpty) {
      _bosZamanlayici = Timer(bosBekleme, () {
        final satir = _bekleyen.toString();
        _bekleyen.clear();
        final kg = agirlikCoz(satir);
        if (kg != null) _agirlik(kg);
      });
    }
  }

  void sifirla() {
    _bosZamanlayici?.cancel();
    _bekleyen.clear();
  }

  static final _satirSonu = RegExp('[\r\n\x03]');

  /// İşaret, sayı ve (varsa) birim. Birim kendi başına bir kelime olmalı:
  /// "25.40 gross" içindeki "g" gram sayılmaz.
  static final _sayi =
      RegExp(r'([-+])?\s*(\d+(?:[.,]\d+)?)\s*(?:(kg|g|lb)(?![a-z]))?', caseSensitive: false);

  /// Tek bir terazi satırından kiloyu çıkarır; kilo yoksa `null`.
  ///
  /// Satırda birden çok sayı varsa (ör. `001 0033.60` = terazi no + tartı):
  /// birimi (kg/g) yazılı olan → yoksa ondalıklı olan → yoksa sonuncusu.
  /// `g` birimi kiloya çevrilir (`12500 g` = 12.5 kg).
  static double? agirlikCoz(String satir) {
    final temiz = satir.replaceAll(RegExp(r'[\x00-\x1F]'), ' ');
    final adaylar = _sayi.allMatches(temiz).toList();
    if (adaylar.isEmpty) return null;

    RegExpMatch secilen;
    final birimli = adaylar.where((m) => m.group(3) != null).toList();
    final ondalikli = adaylar.where((m) => m.group(2)!.contains(RegExp('[.,]'))).toList();
    if (birimli.isNotEmpty) {
      secilen = birimli.last;
    } else if (ondalikli.isNotEmpty) {
      secilen = ondalikli.last;
    } else {
      secilen = adaylar.last;
    }

    final deger = double.tryParse(secilen.group(2)!.replaceAll(',', '.'));
    if (deger == null || !deger.isFinite) return null;
    var kg = secilen.group(1) == '-' ? -deger : deger;
    if (secilen.group(3)?.toLowerCase() == 'g') kg /= 1000;
    return kg;
  }
}
