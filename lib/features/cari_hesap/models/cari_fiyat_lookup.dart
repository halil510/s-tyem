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
/// Fiyat bulma kuralı: Tam o ay için tanımlı bir fiyat varsa o kullanılır;
/// yoksa GERİYE DOĞRU en son tanımlı fiyata bakılır (ör. Mart için fiyat
/// girilmemişse ama Ocak'ta girilmişse, Ocak'ın fiyatı kullanılır).
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

  /// Bir cari + ay ('yyyy-MM') için etkin fiyatı bulur.
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
