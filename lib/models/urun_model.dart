/// ─────────────────────────────────────────────────────────────
/// ÜRÜN (yem, gübre, saman…) — migration v16
/// ─────────────────────────────────────────────────────────────
///
/// Üreticiye verilip süt parasından düşülen her şey bir üründür. Ürünler
/// Menü → Ürünler (Yem, Gübre…) ekranından eklenir; Yem Ekle ve Yem
/// Fiyatları ekranları bu listeden kendiliğinden oluşur.
///
/// Kurallar:
///  • Kaydı (yem satırı) olan ürün SİLİNMEZ, pasife alınır (geçmiş ekstre bozulmasın).
///  • Kaydı olan ürünün BİRİMİ değiştirilemez (5 "kg" sonradan 5 "çuval" olmasın).
///  • Fiyat birim başınadır: ₺/kg, ₺/çuval, ₺/adet…
class Urun {
  final int? id;
  final String ad;

  /// 'kg', 'çuval', 'adet', 'litre', 'balya'… (serbest, kısa metin).
  final String birim;

  /// Ekranlardaki sıra (küçük önce).
  final int sira;
  final bool aktif;

  /// Cihazlar arası kimlik. İlk 6 ürünün kimliği SABİTTİR ([sistemUrunleri]):
  /// iki telefon güncellemeyi ayrı ayrı yapsa da aynı ürün iki kez oluşmaz.
  final String? uuid;

  const Urun({
    this.id,
    required this.ad,
    this.birim = 'kg',
    this.sira = 0,
    this.aktif = true,
    this.uuid,
  });

  /// Toplamlarda "kg" olarak toplanabilir mi? (çuval / adet kg'a eklenmez.)
  bool get kgMi => birimKgMi(birim);

  static bool birimKgMi(String birim) => birim.trim().toLowerCase() == 'kg';

  factory Urun.fromMap(Map<String, Object?> m) => Urun(
        id: m['id'] as int?,
        ad: (m['ad'] as String?) ?? '',
        birim: ((m['birim'] as String?) ?? '').trim().isEmpty ? 'kg' : (m['birim'] as String).trim(),
        sira: (m['sira'] as int?) ?? 0,
        aktif: ((m['aktif'] as int?) ?? 1) == 1,
        uuid: m['uuid'] as String?,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'ad': ad,
        'birim': birim,
        'sira': sira,
        'aktif': aktif ? 1 : 0,
        if (uuid != null) 'uuid': uuid,
      };

  Urun kopya({String? ad, String? birim, int? sira, bool? aktif}) => Urun(
        id: id,
        ad: ad ?? this.ad,
        birim: birim ?? this.birim,
        sira: sira ?? this.sira,
        aktif: aktif ?? this.aktif,
        uuid: uuid,
      );
}

/// v16 öncesi yem türleri: eski `yemler` / `cari_fiyatlar` sütunları ve
/// bunlardan oluşturulan ürünlerin SABİT kimlikleri. Eski veri (migration,
/// eski biçimli yedek) bu tabloyla ürünlere çevrilir. Sıra = eski ekran sırası.
class EskiYemTuru {
  final String uuid;
  final String ad;
  final String yemSutunu;
  final String fiyatSutunu;
  const EskiYemTuru(this.uuid, this.ad, this.yemSutunu, this.fiyatSutunu);
}

const sistemUrunleri = <EskiYemTuru>[
  EskiYemTuru('urun-sut-yemi', 'Süt Yemi', 'sut_yemi', 'sut_yemi_fiyat'),
  EskiYemTuru('urun-besi-yemi', 'Besi Yemi', 'besi_yemi', 'besi_yemi_fiyat'),
  EskiYemTuru('urun-b-baslangic', 'B. Başlangıç', 'b_baslangic', 'b_baslangic_fiyat'),
  EskiYemTuru('urun-b-buyutme', 'B. Büyütme', 'b_buyutme', 'b_buyutme_fiyat'),
  EskiYemTuru('urun-kuzu-yemi', 'Kuzu Yemi', 'kuzu_yemi', 'kuzu_yemi_fiyat'),
  EskiYemTuru('urun-tavuk-yemi', 'Tavuk Yemi', 'tavuk_yemi', 'tavuk_yemi_fiyat'),
];

/// Cari + ürün + geçerlilik başlangıcı için birim fiyat (`cari_urun_fiyatlari`).
///
/// [ay]: `'yyyy-MM'` (ayın 1'inden itibaren) ya da `'yyyy-MM-dd'` (o günden
/// itibaren — yalnız eski verinin çevrilmesinden gelir; ekran aylık yazar).
/// Kural süt fiyatıyla aynı: kaydın gününe kadar başlamış EN SON fiyat.
class UrunFiyat {
  final int? id;
  final int cariId;
  final int urunId;
  final String ay;
  final double fiyat;

  const UrunFiyat({this.id, required this.cariId, required this.urunId, required this.ay, required this.fiyat});

  factory UrunFiyat.fromMap(Map<String, Object?> m) => UrunFiyat(
        id: m['id'] as int?,
        cariId: m['cari_id'] as int,
        urunId: m['urun_id'] as int,
        ay: m['ay'] as String,
        fiyat: (m['fiyat'] as num?)?.toDouble() ?? 0,
      );
}

/// Ürün fiyatlarını belleğe alıp "bu cari, bu ürün, bu gün için birim fiyat
/// nedir?" sorusunu sorgusuz yanıtlar (bkz. `CariFiyatLookup` — aynı kural).
/// Metin karşılaştırması doğru sıralar: `'2026-10-20' < '2026-11' < '2026-11-04'`.
class UrunFiyatLookup {
  final Map<String, List<UrunFiyat>> _sirali = {};

  UrunFiyatLookup(Iterable<UrunFiyat> fiyatlar) {
    for (final f in fiyatlar) {
      _sirali.putIfAbsent('${f.cariId}|${f.urunId}', () => []).add(f);
    }
    for (final l in _sirali.values) {
      l.sort((a, b) => a.ay.compareTo(b.ay));
    }
  }

  /// [tarih]: kaydın günü (`'yyyy-MM-dd'`, saatli olabilir) ya da ay (`'yyyy-MM'` → ay başı).
  /// Tanımlı fiyat yoksa 0.
  double fiyat(int cariId, int urunId, String tarih) {
    final l = _sirali['$cariId|$urunId'];
    if (l == null) return 0;
    final gun = tarih.length > 10 ? tarih.substring(0, 10) : tarih;
    double sonuc = 0;
    for (final f in l) {
      if (f.ay.compareTo(gun) <= 0) {
        sonuc = f.fiyat;
      } else {
        break;
      }
    }
    return sonuc;
  }
}
