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
