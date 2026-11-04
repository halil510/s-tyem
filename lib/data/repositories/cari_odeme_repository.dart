import 'denetim_kaydi.dart';
import 'donem_kilidi.dart';
import 'package:sqflite/sqflite.dart';
import '../../models/cari_odeme_model.dart';

/// Cari hesap hareketleri (süt alımı, yem verişi, ödeme, tahsilat) için
/// veri erişim katmanı.
///
/// ─────────────────────────────────────────────────────────────
/// İŞ MANTIĞI — SÜT TOPLAMA İŞLETMESİNDE "CARİ HESAP" NASIL ÇALIŞIR
/// ─────────────────────────────────────────────────────────────
/// Bu, normal bir "müşteri veresiye alır, borçlanır" hesabının TERSİNE
/// işler: işletme süt topladıkça çiftçiye (cariye) borçlanır, çiftçi de
/// yem/nakit aldıkça işletmeye borçlanır. Tek bir işaretli (signed)
/// bakiye üzerinden netleştirilir:
///
///   bakiye = (toplam süt değeri + toplam tahsilat)
///          - (toplam yem değeri + toplam ödeme)
///
///   bakiye > 0  → Cari ALACAKLI (işletme cariye şu kadar borçlu)
///   bakiye < 0  → Cari BORÇLU   (cari işletmeye şu kadar borçlu)
///   bakiye == 0 → Hesap kapalı
///
/// Örnek: 10 kg süt × 25 ₺ = 250 ₺ alacak → bakiye +250 (cari alacaklı).
/// 100 ₺'lik yem verildi → bakiye +150 (hâlâ alacaklı, azaldı).
/// 150 ₺ ödendi → bakiye 0 (hesap kapandı).
/// 200 ₺ ödendi (fazla) → bakiye -50 (cari artık işletmeye 50 ₺ borçlu).
///
/// `islem_turu` şu değerleri alır:
///   'sut'      → süt alımı (KREDİ, +): işletme cariye borçlanır
///   'yem'      → yem verişi (BORÇ, -): cari işletmeye borçlanır
///   'odeme'    → işletmenin cariye yaptığı nakit ödeme (BORÇ, -)
///   'tahsilat' → işletmenin cariden tahsil ettiği nakit (KREDİ, +)
///
/// Geriye dönük uyumluluk için eski 'alim' kaydı da 'sut' ile aynı
/// (kredi, +) yönde sayılır.
class CariOdemeRepository {
  final Database db;
  const CariOdemeRepository(this.db);

  /// Yazma işlemi: transaction + kapalı dönem kilidinin okunur hataya çevrilmesi.
  Future<T> _yaz<T>(Future<T> Function(Transaction txn) islem) =>
      donemKilidiyle(() => db.transaction(islem));

  static const _tablo = 'cari_odemeler';

  /// Bakiyeyi ARTIRAN (krediye/cari alacağına katkı yapan) işlem türleri.
  static const krediTurleri = ['sut', 'alim', 'tahsilat'];

  /// Bakiyeyi AZALTAN (cari borcuna katkı yapan) işlem türleri.
  static const borcTurleri = ['yem', 'odeme'];

  static String get _krediSql =>
      "islem_turu IN (${krediTurleri.map((_) => '?').join(',')})";
  static String get _borcSql =>
      "islem_turu IN (${borcTurleri.map((_) => '?').join(',')})";

  /// Kayıt ve denetim satırı aynı transaction'da yazılır: ikisinden biri
  /// başarısız olursa hiçbiri yazılmaz.
  Future<int> insert(CariOdeme odeme) {
    if (!odeme.toplamTutar.isFinite || odeme.toplamTutar < 0) {
      throw ArgumentError.value(odeme.toplamTutar, 'toplamTutar', 'Geçersiz tutar');
    }
    return _yaz((txn) async {
      final map = odeme.toMap()..remove('id');
      final id = await txn.insert(_tablo, map);
      await denetimKaydet(txn, tablo: _tablo, kayitId: id, islem: 'ekle', yeniDeger: map);
      return id;
    });
  }

  Future<List<CariOdeme>> getByCari(int cariId) async {
    final maps = await db.query(
      _tablo,
      where: 'cari_id = ?',
      whereArgs: [cariId],
      orderBy: 'tarih DESC, id DESC',
    );
    return maps.map(CariOdeme.fromMap).toList();
  }

  Future<CariOdeme?> getById(int id) async {
    final maps = await db.query(_tablo, where: 'id = ?', whereArgs: [id]);
    return maps.isNotEmpty ? CariOdeme.fromMap(maps.first) : null;
  }

  Future<int> update(CariOdeme odeme) {
    return _yaz((txn) async {
      final onceki = await txn.query(_tablo, where: 'id = ?', whereArgs: [odeme.id]);
      final yeni = odeme.toMap()..remove('id');
      final result = await txn.update(_tablo, yeni, where: 'id = ?', whereArgs: [odeme.id]);
      if (result > 0) {
        await denetimKaydet(txn,
            tablo: _tablo, kayitId: odeme.id!, islem: 'guncelle',
            oncekiDeger: onceki.first, yeniDeger: yeni);
      }
      return result;
    });
  }

  Future<int> delete(int id) {
    return _yaz((txn) async {
      final onceki = await txn.query(_tablo, where: 'id = ?', whereArgs: [id]);
      final result = await txn.delete(_tablo, where: 'id = ?', whereArgs: [id]);
      if (result > 0) {
        await denetimKaydet(txn, tablo: _tablo, kayitId: id, islem: 'sil', oncekiDeger: onceki.first);
      }
      return result;
    });
  }

  /// ⚠️ KULLANILMIYOR: Yalnızca `cari_odemeler`'daki 'sut'/'yem'
  /// kayıtlarını sayar; canlı hesaplama artık `tumKalanBorclarProvider`
  /// üzerinden yapılıyor (bkz. cari_hesap_providers.dart).
  /// Tüm carilerin güncel, İŞARETLİ (signed) bakiyesi.
  /// Pozitif = cari alacaklı (işletme cariye borçlu).
  /// Negatif = cari borçlu (cari işletmeye borçlu).
  Future<Map<int, double>> getTumKalanBorclar() async {
    final result = await db.rawQuery('''
      SELECT cari_id,
        SUM(CASE WHEN $_krediSql THEN toplam_tutar ELSE 0 END) -
        SUM(CASE WHEN $_borcSql THEN toplam_tutar ELSE 0 END) AS bakiye
      FROM $_tablo
      GROUP BY cari_id
    ''', [...krediTurleri, ...borcTurleri]);
    return {
      for (final r in result)
        r['cari_id'] as int: (r['bakiye'] as num? ?? 0).toDouble(),
    };
  }

  /// Tek bir carinin işaretli bakiyesi (pozitif = alacaklı, negatif = borçlu).
  Future<double> getKalanBorc(int cariId) async {
    final result = await db.rawQuery('''
      SELECT
        SUM(CASE WHEN $_krediSql THEN toplam_tutar ELSE 0 END) -
        SUM(CASE WHEN $_borcSql THEN toplam_tutar ELSE 0 END) AS bakiye
      FROM $_tablo WHERE cari_id = ?
    ''', [...krediTurleri, ...borcTurleri, cariId]);
    return (result.first['bakiye'] as num? ?? 0).toDouble();
  }

  /// ⚠️ KULLANILMIYOR (geriye dönük referans için tutuluyor): Bu metod
  /// yalnızca `cari_odemeler` tablosundaki 'sut'/'yem' kayıtlarını
  /// sayar. Mimari artık süt/yem'i CANLI olarak `sutler`/`yemler`
  /// tablolarından hesaplıyor (bkz. `lib/features/cari_hesap/providers/
  /// cari_hesap_providers.dart` içindeki `cariEkstreProvider` ve
  /// `tumKalanBorclarProvider`). Ekranlar artık bu metodu çağırmıyor.
  Future<CariHesapOzeti> getHesapOzeti(int cariId) async {
    final result = await db.rawQuery('''
      SELECT
        SUM(CASE WHEN islem_turu IN ('sut','alim') THEN toplam_tutar ELSE 0 END) AS toplamSut,
        SUM(CASE WHEN islem_turu = 'yem' THEN toplam_tutar ELSE 0 END) AS toplamYem,
        SUM(CASE WHEN islem_turu = 'odeme' THEN toplam_tutar ELSE 0 END) AS toplamOdeme,
        SUM(CASE WHEN islem_turu = 'tahsilat' THEN toplam_tutar ELSE 0 END) AS toplamTahsilat,
        COUNT(*) AS hareketSayisi
      FROM $_tablo WHERE cari_id = ?
    ''', [cariId]);
    final row = result.first;
    final toplamSut = (row['toplamSut'] as num? ?? 0).toDouble();
    final toplamYem = (row['toplamYem'] as num? ?? 0).toDouble();
    final toplamOdeme = (row['toplamOdeme'] as num? ?? 0).toDouble();
    final toplamTahsilat = (row['toplamTahsilat'] as num? ?? 0).toDouble();
    return CariHesapOzeti(
      cariId: cariId,
      toplamSut: toplamSut,
      toplamYem: toplamYem,
      toplamOdeme: toplamOdeme,
      toplamTahsilat: toplamTahsilat,
      kalanBakiye: (toplamSut + toplamTahsilat) - (toplamYem + toplamOdeme),
      hareketSayisi: (row['hareketSayisi'] as num? ?? 0).toInt(),
    );
  }

  Future<List<CariOdeme>> getByCariInRange(int cariId, String start, String end) async {
    final maps = await db.query(
      _tablo,
      where: 'cari_id = ? AND tarih BETWEEN ? AND ?',
      whereArgs: [cariId, start, end],
      orderBy: 'tarih ASC, id ASC',
    );
    return maps.map(CariOdeme.fromMap).toList();
  }

  /// TÜM carilerin ödeme/tahsilat kayıtlarını (süt/yem/alim HARİÇ) tek
  /// sorguda getirir — toplu canlı bakiye hesaplamasında (bkz.
  /// `tumKalanBorclarProvider`) N+1 sorgu sorununu önlemek için
  /// kullanılır. Süt/yem artık canlı hesaplandığından, olası eski
  /// (kapatma özelliğinden kalma) 'sut'/'yem'/'alim' kayıtları burada
  /// KASITLI OLARAK hariç tutulur — aksi halde çift sayım olur.
  Future<List<CariOdeme>> getTumOdemeTahsilatlar() async {
    final maps = await db.query(
      _tablo,
      where: "islem_turu IN ('odeme','tahsilat')",
      orderBy: 'tarih ASC, id ASC',
    );
    return maps.map(CariOdeme.fromMap).toList();
  }

  /// Bir kaydın geçmiş değişiklik günlüğü (denetim izi).
  Future<List<Map<String, Object?>>> gecmisi(int kayitId) async {
    return db.query(
      'islem_gecmisi',
      where: 'tablo_adi = ? AND kayit_id = ?',
      whereArgs: [_tablo, kayitId],
      orderBy: 'id DESC',
    );
  }
}

/// Bir carinin özet hesap durumu (dashboard ve ekstre ekranlarında kullanılır).
///
/// `kalanBakiye` İŞARETLİDİR: pozitif = cari alacaklı (işletme borçlu),
/// negatif = cari borçlu (cari işletmeye borçlu).
class CariHesapOzeti {
  final int cariId;
  final double toplamSut;
  final double toplamYem;
  final double toplamOdeme;
  final double toplamTahsilat;
  final double kalanBakiye;
  final int hareketSayisi;

  const CariHesapOzeti({
    required this.cariId,
    required this.toplamSut,
    required this.toplamYem,
    required this.toplamOdeme,
    required this.toplamTahsilat,
    required this.kalanBakiye,
    required this.hareketSayisi,
  });

  /// Cari alacaklı mı? (işletme cariye borçlu)
  /// Kayan nokta (floating point) birikimli yuvarlama hatalarını
  /// tolere etmek için 1 kuruşluk (0.01) bir eşik kullanılır — aksi
  /// halde tam kapanmış bir hesap, ondalık yuvarlama yüzünden
  /// "0.0000000001 ₺ alacaklı" gibi anlamsız bir bakiye gösterebilir.
  static const _epsilon = 0.01;

  bool get alacakliMi => kalanBakiye > _epsilon;

  /// Cari borçlu mu? (cari işletmeye borçlu)
  bool get borcluMu => kalanBakiye < -_epsilon;

  bool get hesapKapaliMi => kalanBakiye.abs() <= _epsilon;
}
