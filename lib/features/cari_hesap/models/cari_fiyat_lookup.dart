import '../../../models/cari_fiyat_model.dart';

/// Bir veya birden çok carinin TÜM ay fiyatlarını önceden belleğe alıp,
/// hızlı ve SENKRON "bu ay için etkin fiyat nedir?" sorgusu sağlayan
/// yardımcı sınıf.
///
/// Neden gerekli: Canlı bakiye hesaplaması, her süt/yem kaydı için o
/// kaydın ait olduğu ayın fiyatını bilmesi gerekir. Bunu her kayıt için
/// ayrı ayrı veritabanına sorarak yapmak (N+1 sorgu) yüzlerce kayıtta
/// yavaşlar. Bunun yerine, ilgili cari(ler)in TÜM fiyat geçmişi TEK
/// sorguda çekilir, burada gruplanır ve "ay X için fiyat nedir?"
/// sorusu bellekten, anında yanıtlanır.
///
/// Fiyat anahtarı (`ay` sütunu) iki biçimde olabilir:
/// - `'yyyy-MM'`     → o ayın 1'inden itibaren geçerli,
/// - `'yyyy-MM-dd'`  → o GÜNDEN itibaren geçerli (ay ortası fiyat değişikliği).
///
/// Fiyat bulma kuralı: sorgulanan tarihe (kaydın günü `'yyyy-MM-dd'` ya da
/// ay `'yyyy-MM'`) kadar başlamış EN SON fiyat kullanılır. Metin karşılaştırması
/// doğru sıralar: `'2026-10-20' < '2026-11' < '2026-11-01' < '2026-11-04'`.
/// Örnek: Kasım 25 ₺, 4 Kasım'dan itibaren 27 ₺ → 1–3 Kasım sütü 25 ₺'dan,
/// 4 Kasım ve sonrası 27 ₺'dan hesaplanır; Aralık'ta yeni fiyat yoksa 27 ₺.
/// Ay (`'yyyy-MM'`) ile sorgulanırsa ayın BAŞINDAKİ fiyat döner.
/// Hiç fiyat tanımlanmamışsa sıfır fiyatlı bir varsayılan döner.
class CariFiyatLookup {
  final Map<String, CariFiyat> _tekilFiyatlar;
  final Map<int, List<MapEntry<String, CariFiyat>>> _cariBazliSirali;

  CariFiyatLookup(List<CariFiyat> tumFiyatlar)
      : _tekilFiyatlar = {for (final f in tumFiyatlar) '${f.cariId}|${f.ay}': f},
        _cariBazliSirali = _grupla(tumFiyatlar);

  static Map<int, List<MapEntry<String, CariFiyat>>> _grupla(List<CariFiyat> hepsi) {
    final map = <int, List<MapEntry<String, CariFiyat>>>{};
    for (final f in hepsi) {
      map.putIfAbsent(f.cariId, () => []).add(MapEntry(f.ay, f));
    }
    for (final list in map.values) {
      list.sort((a, b) => a.key.compareTo(b.key));
    }
    return map;
  }

  /// Bir cari + tarih ('yyyy-MM-dd') ya da ay ('yyyy-MM') için etkin fiyatı bulur.
  CariFiyat fiyatIcin(int cariId, String ay) {
    final tam = _tekilFiyatlar['$cariId|$ay'];
    if (tam != null) return tam;

    final liste = _cariBazliSirali[cariId];
    if (liste == null || liste.isEmpty) return CariFiyat(cariId: cariId, ay: ay);

    CariFiyat? enSonUygun;
    for (final entry in liste) {
      if (entry.key.compareTo(ay) <= 0) {
        enSonUygun = entry.value;
      } else {
        break;
      }
    }
    return enSonUygun ?? CariFiyat(cariId: cariId, ay: ay);
  }

  /// Bir cari için hiç fiyat tanımlanmış mı (herhangi bir ay için)?
  /// "Fiyat eksik" uyarısı göstermek için kullanılır.
  bool cariIcinHicFiyatVarMi(int cariId) =>
      _cariBazliSirali[cariId]?.isNotEmpty ?? false;
}
