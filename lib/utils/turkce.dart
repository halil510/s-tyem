/// Türkçe kurallarıyla küçük harf (İ→i, I→ı).
///
/// Dart'ın `toLowerCase()`'i "İ"yi "i̇" (i + birleşik nokta) yapar; bu yüzden
/// büyük harfle kayıtlı "İSMAİL" araması "ismail" yazınca BULUNMAZDI.
String turkceKucuk(String s) => s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();

/// Arama: büyük/küçük harf ve Türkçe İ/ı farkı gözetmeden, fazla boşlukları
/// yok sayarak [metin] içinde [sorgu] var mı?
bool aramaEslesir(String metin, String sorgu) {
  String n(String s) => turkceKucuk(s.trim().replaceAll(RegExp(r'\s+'), ' '));
  final q = n(sorgu);
  return q.isEmpty || n(metin).contains(q);
}

const _alfabe = 'abcçdefgğhıijklmnoöprsştuüvwxyz';

/// Türk alfabesine göre karşılaştırma (sıralama için):
/// A < B < C < Ç < D … < I < İ < … < O < Ö < … < S < Ş < … < U < Ü < … < Z.
///
/// Veritabanının `ORDER BY ad` ve Dart'ın `compareTo`'su harfleri kod
/// sırasına göre dizer: ÇETİN, ŞÜKRÜ, ÖMER, ÜMİT, İSMAİL listenin EN SONUNA
/// (Z'den sonraya) düşüyordu.
int turkceKarsilastir(String a, String b) {
  final x = turkceKucuk(a.trim()), y = turkceKucuk(b.trim());
  final n = x.length < y.length ? x.length : y.length;
  for (var i = 0; i < n; i++) {
    if (x[i] == y[i]) continue;
    final ix = _alfabe.indexOf(x[i]), iy = _alfabe.indexOf(y[i]);
    // Alfabe dışı karakterler (rakam, boşluk, nokta…) harflerden önce, kendi kod sırasıyla.
    if (ix < 0 || iy < 0) {
      if (ix >= 0) return 1;
      if (iy >= 0) return -1;
      return x.codeUnitAt(i).compareTo(y.codeUnitAt(i));
    }
    return ix.compareTo(iy);
  }
  return x.length.compareTo(y.length);
}
