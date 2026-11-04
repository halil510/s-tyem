/// ─────────────────────────────────────────────────────────────
/// SAYI GİRİŞİ / GÖSTERİMİ — tüm ekranlarda ortak, tek kaynak
/// ─────────────────────────────────────────────────────────────
///
/// Eskiden her ekran kendi `double.tryParse(x.replaceAll(',', '.')) ?? 0`
/// kopyasını kullanıyordu. Bu, "12,5x" veya "1.2.3" gibi hatalı bir
/// girişi SESSİZCE 0 kg olarak kaydediyordu — müşterinin sütü kayboluyor
/// ama kullanıcı bunu fark etmiyordu. [sayiCoz] geçersiz girişte `null`
/// döner; ekran bu durumda kullanıcıyı uyarmalıdır.
library;

/// Kullanıcının yazdığı metni pozitif bir ondalık sayıya çevirir.
///
/// - Boş metin → `0` (alan boş bırakılmış demektir).
/// - Virgül ve nokta ondalık ayırıcı olarak kabul edilir: `12,5` = `12.5`.
/// - Türk usulü binlik ayırıcı desteklenir: `1.250,5` = `1250.5`.
/// - Negatif, sonsuz, harf içeren veya belirsiz (`1.2.3`) giriş → `null`.
double? sayiCoz(String girdi) {
  var metin = girdi.trim().replaceAll(' ', '');
  if (metin.isEmpty) return 0;

  if (metin.contains(',') && metin.contains('.')) {
    // "1.250,5" → binlik nokta + ondalık virgül.
    if (metin.lastIndexOf('.') > metin.indexOf(',')) return null;
    metin = metin.replaceAll('.', '').replaceAll(',', '.');
  } else {
    metin = metin.replaceAll(',', '.');
  }

  if (!RegExp(r'^\d*\.?\d+$|^\d+\.$').hasMatch(metin)) return null;
  final deger = double.tryParse(metin);
  if (deger == null || !deger.isFinite || deger < 0) return null;
  return deger;
}

/// Parayı kuruş hassasiyetine yuvarlar (kayan nokta birikimini önler;
/// ekstrede satır toplamı ile genel toplamın kuruşu kuruşuna tutması için).
///
/// Yarım kuruş sıfırdan uzağa yuvarlanır (ticari yuvarlama). `12.345` gibi
/// değerler ikili tabanda `12.34499…` olarak saklandığından, saf
/// `round()` bunları aşağı yuvarlardı; küçük bir tolerans bunu düzeltir.
double kurusaYuvarla(double tutar) {
  final kurus = tutar * 100;
  return (kurus + (kurus >= 0 ? 1e-7 : -1e-7)).roundToDouble() / 100;
}

/// Miktarı gereksiz sıfırlar olmadan gösterir: `12` · `12.5` · `12.25`.
/// (`12.340000000000001` gibi kayan nokta artıklarını gizler.)
/// Toplamlar tek haneye YUVARLANMAZ: 47.8 + 30.54 = `78.34` (eskiden 78.3).
String sayiGoster(double deger) {
  var metin = deger.toStringAsFixed(2);
  if (metin.contains('.')) {
    metin = metin.replaceFirst(RegExp(r'0+$'), '');
    if (metin.endsWith('.')) metin = metin.substring(0, metin.length - 1);
  }
  return metin == '-0' ? '0' : metin;
}
