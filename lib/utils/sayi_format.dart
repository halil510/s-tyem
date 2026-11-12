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
/// - BELİRSİZ binlik (2026-11-13 denetimi): `1.500` / `12.500` Türk usulüyle "bin beş yüz"
///   de olabilir, "bir buçuk" da → `null` (eskiden sessizce 1,5 okunuyordu: 1.500 TL ödeme
///   1,50 TL kaydediliyordu). Bozuk binlik `1.2,3` → `null` (eskiden 12,3).
double? sayiCoz(String girdi) {
  var metin = girdi.trim().replaceAll(' ', '');
  if (metin.isEmpty) return 0;

  if (metin.contains(',') && metin.contains('.')) {
    // "1.250,5" → binlik nokta + ondalık virgül; binlik grupları tam 3 hane olmalı.
    if (!RegExp(r'^\d{1,3}(\.\d{3})+,\d+$').hasMatch(metin)) return null;
    metin = metin.replaceAll('.', '').replaceAll(',', '.');
  } else if (RegExp(r'^[1-9]\d{0,2}\.\d{3}$').hasMatch(metin)) {
    return null; // "1.500": binlik mi ondalık mı belli değil → kullanıcı "1500" ya da "1,5" yazsın
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

/// Miktarı gereksiz sıfırlar olmadan gösterir: `12` · `12.5` · `12.25` · `12.345`.
/// (`12.340000000000001` gibi kayan nokta artıklarını gizler.)
/// Toplamlar tek haneye YUVARLANMAZ: 47.8 + 30.54 = `78.34` (eskiden 78.3).
/// 3 haneye kadar (2026-11-13): terazi/elle 12,345 kg girilince ekstrede "12.35 kg × 30" yazıp
/// 370,35 TL gösteriyordu (üretici elle 370,50 buluyordu).
String sayiGoster(double deger) {
  var metin = deger.toStringAsFixed(3);
  if (metin.contains('.')) {
    metin = metin.replaceFirst(RegExp(r'0+$'), '');
    if (metin.endsWith('.')) metin = metin.substring(0, metin.length - 1);
  }
  return metin == '-0' ? '0' : metin;
}

/// Kayıtlı değeri bir GİRİŞ KUTUSUNA geri yazmak için: [sayiCoz] ile birebir aynı değere
/// döner (virgüllü, binliksiz, 3 haneye kadar): `12,345` · `1500` · `12,5`.
/// ([sayiGoster]'in "12.345"i yeniden okunurken belirsiz binlik sayılırdı; 2 haneye
/// yuvarlayan eski hali ise Düzenle'de dokunulmayan öğünü sessizce değiştiriyordu.)
String sayiGirdi(double deger) => sayiGoster(deger).replaceAll('.', ',');
