import 'package:sqflite/sqflite.dart';

import '../../models/fabrika_model.dart';
import '../../utils/sayi_format.dart';
import 'denetim_kaydi.dart';

/// Fabrika / sevkiyat / tank kaydı doğrulanamadığında ya da işlem yapılamadığında.
/// Mesaj doğrudan kullanıcıya gösterilebilir; fırlatıldığında HİÇBİR şey yazılmamıştır.
class FabrikaKayitHatasi implements Exception {
  final String mesaj;
  const FabrikaKayitHatasi(this.mesaj);
  @override
  String toString() => mesaj;
}

/// ─────────────────────────────────────────────────────────────
/// TANK, FABRİKAYA SEVKİYAT ve FABRİKA CARİ HESABI (migration v15)
/// ─────────────────────────────────────────────────────────────
/// Fabrika hesabı üretici (cari) hesaplarından AYRIDIR; bakiyeleri etkilemez.
///   fabrika bakiyesi = Σ sevkiyat tutarı + Σ ek − Σ tahsilat − Σ kesinti
///   > 0 → fabrika bize borçlu (alacağımız) · < 0 → fazla ödeme almışız
/// Her yazma tek transaction'da, denetim kaydıyla (islem_gecmisi) birlikte yapılır.
class FabrikaRepository {
  final Database db;
  const FabrikaRepository(this.db);

  /// Tek sevkiyat için üst sınır (kg). Büyük tanker ~30 ton; üstü yazım hatasıdır.
  static const maksimumSevkKg = 60000.0;

  /// Birim fiyat üst sınırı (₺/kg) — "18,5" yerine "185" gibi hatayı yakalar.
  static const maksimumBirimFiyat = 1000.0;

  /// Tek hareket tutarı üst sınırı (₺).
  static const maksimumTutar = 100000000.0;

  /// Gün sonu tank miktarı üst sınırı (kg).
  static const maksimumTankKg = 100000.0;

  static final _tarihDeseni = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  static final _saatDeseni = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

  // ───────────────────────────── FABRİKALAR ─────────────────────────────

  Future<List<Fabrika>> fabrikalar({bool sadeceAktif = false}) async {
    final r = await db.query('fabrikalar',
        where: sadeceAktif ? 'COALESCE(aktif, 1) = 1' : null, orderBy: 'COALESCE(aktif, 1) DESC, ad COLLATE NOCASE, id');
    return r.map(Fabrika.fromMap).toList();
  }

  Future<int> fabrikaEkle(Fabrika f) async {
    final map = _fabrikaDogrula(f);
    return db.transaction((txn) async {
      await _ayniAdKontrol(txn, map['ad'] as String, null);
      final id = await txn.insert('fabrikalar', map);
      await denetimKaydet(txn, tablo: 'fabrikalar', kayitId: id, islem: 'ekle', yeniDeger: map);
      return id;
    });
  }

  Future<void> fabrikaGuncelle(Fabrika f) async {
    if (f.id == null) throw const FabrikaKayitHatasi('Fabrika kaydı bulunamadı.');
    final map = _fabrikaDogrula(f);
    return db.transaction((txn) async {
      final onceki = await txn.query('fabrikalar', where: 'id = ?', whereArgs: [f.id]);
      if (onceki.isEmpty) throw const FabrikaKayitHatasi('Fabrika kaydı bulunamadı (silinmiş olabilir).');
      await _ayniAdKontrol(txn, map['ad'] as String, f.id);
      map['updated_at'] = sqliteSimdi();
      await txn.update('fabrikalar', map, where: 'id = ?', whereArgs: [f.id]);
      await denetimKaydet(txn, tablo: 'fabrikalar', kayitId: f.id!, islem: 'guncelle', oncekiDeger: onceki.first, yeniDeger: map);
    });
  }

  /// Hareketi (sevkiyat / tahsilat…) olan fabrika SİLİNMEZ: pasife alınmalı.
  Future<void> fabrikaSil(int id) => db.transaction((txn) async {
        final n = await hareketSayisi(id, txn);
        if (n > 0) {
          throw FabrikaKayitHatasi(
              'Bu fabrikanın $n kaydı (sevkiyat / ödeme) var; silinirse fabrika hesabı kaybolur. '
              'Silmek yerine pasife alın.');
        }
        final onceki = await txn.query('fabrikalar', where: 'id = ?', whereArgs: [id]);
        if (onceki.isEmpty) return;
        await txn.delete('fabrikalar', where: 'id = ?', whereArgs: [id]);
        await denetimKaydet(txn, tablo: 'fabrikalar', kayitId: id, islem: 'sil', oncekiDeger: onceki.first);
      });

  /// Fabrikanın sevkiyat + hareket sayısı.
  Future<int> hareketSayisi(int fabrikaId, [DatabaseExecutor? ex]) async {
    final r = await (ex ?? db).rawQuery('''
      SELECT (SELECT COUNT(*) FROM sevkiyatlar WHERE fabrika_id = ?) +
             (SELECT COUNT(*) FROM fabrika_hareketleri WHERE fabrika_id = ?) AS n''', [fabrikaId, fabrikaId]);
    return (r.first['n'] as int?) ?? 0;
  }

  static Map<String, Object?> _fabrikaDogrula(Fabrika f) {
    final ad = f.ad.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (ad.isEmpty) throw const FabrikaKayitHatasi('Fabrika adı boş olamaz.');
    String? bosNull(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
    return {
      'ad': ad,
      'telefon': bosNull(f.telefon),
      'adres': bosNull(f.adres),
      'not_metni': bosNull(f.notMetni),
      'aktif': f.aktif ? 1 : 0,
    };
  }

  static Future<void> _ayniAdKontrol(DatabaseExecutor ex, String ad, int? haricId) async {
    final r = await ex.query('fabrikalar',
        columns: ['id', 'ad'], where: haricId == null ? null : 'id <> ?', whereArgs: haricId == null ? null : [haricId]);
    if (r.any((x) => _adAnahtari(x['ad'] as String? ?? '') == _adAnahtari(ad))) {
      throw FabrikaKayitHatasi('"$ad" adında bir fabrika zaten var.');
    }
  }

  /// Türkçe büyük/küçük harf farkı gözetmeyen ad karşılaştırması.
  static String _adAnahtari(String s) => s
      .trim()
      .replaceAll('İ', 'i')
      .replaceAll('I', 'ı')
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ');

  // ───────────────────────────── SEVKİYATLAR ─────────────────────────────

  /// Aralıktaki sevkiyatlar (tarih, saat, id sırasıyla). [fabrikaId] verilirse yalnız o fabrika.
  Future<List<Sevkiyat>> sevkiyatlar(String start, String end, {int? fabrikaId}) async {
    final r = await db.query('sevkiyatlar',
        where: 'tarih BETWEEN ? AND ?${fabrikaId != null ? ' AND fabrika_id = ?' : ''}',
        whereArgs: [start, end, if (fabrikaId != null) fabrikaId],
        orderBy: "tarih, COALESCE(saat, ''), id");
    return r.map(Sevkiyat.fromMap).toList();
  }

  /// Bir fabrikanın TÜM sevkiyatları (fabrika ekstresi / bakiye için).
  Future<List<Sevkiyat>> fabrikaSevkiyatlari(int fabrikaId) async {
    final r = await db.query('sevkiyatlar',
        where: 'fabrika_id = ?', whereArgs: [fabrikaId], orderBy: "tarih, COALESCE(saat, ''), id");
    return r.map(Sevkiyat.fromMap).toList();
  }

  /// Aralıkta her günün toplam sevk kg'ı ('yyyy-MM-dd' → kg), tüm fabrikalar.
  Future<Map<String, double>> gunlukSevkToplamlari(String start, String end) async {
    final r = await db.rawQuery(
        'SELECT tarih, SUM(kg) AS kg FROM sevkiyatlar WHERE tarih BETWEEN ? AND ? GROUP BY tarih', [start, end]);
    return {for (final x in r) x['tarih'] as String: ((x['kg'] as num?) ?? 0).toDouble()};
  }

  /// Fabrikanın en son girilen (0'dan büyük) birim fiyatı — yeni sevkiyat formunu doldurmak için.
  Future<double?> sonBirimFiyat(int fabrikaId) async {
    final r = await db.query('sevkiyatlar',
        columns: ['birim_fiyat'],
        where: 'fabrika_id = ? AND birim_fiyat > 0',
        whereArgs: [fabrikaId],
        orderBy: "tarih DESC, COALESCE(saat, '') DESC, id DESC",
        limit: 1);
    return r.isEmpty ? null : (r.first['birim_fiyat'] as num).toDouble();
  }

  Future<int> sevkiyatEkle(Sevkiyat s) async {
    final map = _sevkiyatDogrula(s);
    return db.transaction((txn) async {
      await _fabrikaVarMi(txn, s.fabrikaId);
      final id = await txn.insert('sevkiyatlar', map);
      await denetimKaydet(txn, tablo: 'sevkiyatlar', kayitId: id, islem: 'ekle', yeniDeger: map);
      return id;
    });
  }

  Future<void> sevkiyatGuncelle(Sevkiyat s) async {
    if (s.id == null) throw const FabrikaKayitHatasi('Sevkiyat kaydı bulunamadı.');
    final map = _sevkiyatDogrula(s);
    return db.transaction((txn) async {
      final onceki = await txn.query('sevkiyatlar', where: 'id = ?', whereArgs: [s.id]);
      if (onceki.isEmpty) throw const FabrikaKayitHatasi('Sevkiyat kaydı bulunamadı (silinmiş olabilir).');
      await _fabrikaVarMi(txn, s.fabrikaId);
      map['updated_at'] = sqliteSimdi();
      await txn.update('sevkiyatlar', map, where: 'id = ?', whereArgs: [s.id]);
      await denetimKaydet(txn, tablo: 'sevkiyatlar', kayitId: s.id!, islem: 'guncelle', oncekiDeger: onceki.first, yeniDeger: map);
    });
  }

  Future<void> sevkiyatSil(int id) => db.transaction((txn) async {
        final onceki = await txn.query('sevkiyatlar', where: 'id = ?', whereArgs: [id]);
        if (onceki.isEmpty) return;
        await txn.delete('sevkiyatlar', where: 'id = ?', whereArgs: [id]);
        await denetimKaydet(txn, tablo: 'sevkiyatlar', kayitId: id, islem: 'sil', oncekiDeger: onceki.first);
      });

  /// Fabrikanın açıkladığı fiyatı aralıktaki sevkiyatlara uygular (tek transaction).
  /// [sadeceFiyatsiz]: yalnız fiyatı girilmemiş (0) sevkiyatlar değişir.
  /// Dönüş: değişen sevkiyat sayısı.
  Future<int> fiyatUygula({
    required int fabrikaId,
    required String start,
    required String end,
    required double birimFiyat,
    bool sadeceFiyatsiz = true,
  }) async {
    _tarihDogrula(start);
    _tarihDogrula(end);
    if (!birimFiyat.isFinite || birimFiyat <= 0) throw const FabrikaKayitHatasi('Birim fiyat 0\'dan büyük olmalı.');
    if (birimFiyat > maksimumBirimFiyat) {
      throw FabrikaKayitHatasi('Birim fiyat çok yüksek: $birimFiyat ₺/kg (en fazla ${maksimumBirimFiyat.toStringAsFixed(0)}).');
    }
    return db.transaction((txn) async {
      final hedef = await txn.query('sevkiyatlar',
          where: 'fabrika_id = ? AND tarih BETWEEN ? AND ?${sadeceFiyatsiz ? ' AND COALESCE(birim_fiyat, 0) <= 0' : ''}',
          whereArgs: [fabrikaId, start, end]);
      var n = 0;
      for (final s in hedef) {
        if (((s['birim_fiyat'] as num?) ?? 0).toDouble() == birimFiyat) continue;
        final yeni = {'birim_fiyat': birimFiyat, 'updated_at': sqliteSimdi()};
        await txn.update('sevkiyatlar', yeni, where: 'id = ?', whereArgs: [s['id']]);
        await denetimKaydet(txn, tablo: 'sevkiyatlar', kayitId: s['id'] as int, islem: 'guncelle', oncekiDeger: s, yeniDeger: yeni);
        n++;
      }
      return n;
    });
  }

  static Map<String, Object?> _sevkiyatDogrula(Sevkiyat s) {
    _tarihDogrula(s.tarih);
    final saat = (s.saat == null || s.saat!.trim().isEmpty) ? null : s.saat!.trim();
    if (saat != null && !_saatDeseni.hasMatch(saat)) throw FabrikaKayitHatasi('Geçersiz saat: "$saat" (SS:dd).');
    if (!s.kg.isFinite || s.kg <= 0) throw const FabrikaKayitHatasi('Sevk miktarı 0\'dan büyük olmalı.');
    if (s.kg > maksimumSevkKg) {
      throw FabrikaKayitHatasi('Sevk miktarı çok yüksek: ${s.kg} kg (en fazla ${maksimumSevkKg.toStringAsFixed(0)} kg).');
    }
    if (!s.birimFiyat.isFinite || s.birimFiyat < 0) throw const FabrikaKayitHatasi('Birim fiyat geçersiz.');
    if (s.birimFiyat > maksimumBirimFiyat) {
      throw FabrikaKayitHatasi(
          'Birim fiyat çok yüksek: ${s.birimFiyat} ₺/kg (en fazla ${maksimumBirimFiyat.toStringAsFixed(0)}).');
    }
    String? bosNull(String? x) => (x == null || x.trim().isEmpty) ? null : x.trim();
    return {
      'fabrika_id': s.fabrikaId,
      'tarih': s.tarih,
      'saat': saat,
      'kg': s.kg,
      'birim_fiyat': s.birimFiyat,
      'fis_no': bosNull(s.fisNo),
      'plaka': bosNull(s.plaka),
      'aciklama': bosNull(s.aciklama),
    };
  }

  // ───────────────────────── FABRİKA HAREKETLERİ ─────────────────────────

  /// Bir fabrikanın TÜM hareketleri (tahsilat, kesinti, ek).
  Future<List<FabrikaHareketi>> fabrikaHareketleri(int fabrikaId) async {
    final r = await db.query('fabrika_hareketleri', where: 'fabrika_id = ?', whereArgs: [fabrikaId], orderBy: 'tarih, id');
    return r.map(FabrikaHareketi.fromMap).toList();
  }

  Future<int> hareketEkle(FabrikaHareketi h) async {
    final map = _hareketDogrula(h);
    return db.transaction((txn) async {
      await _fabrikaVarMi(txn, h.fabrikaId);
      final id = await txn.insert('fabrika_hareketleri', map);
      await denetimKaydet(txn, tablo: 'fabrika_hareketleri', kayitId: id, islem: 'ekle', yeniDeger: map);
      return id;
    });
  }

  Future<void> hareketGuncelle(FabrikaHareketi h) async {
    if (h.id == null) throw const FabrikaKayitHatasi('Kayıt bulunamadı.');
    final map = _hareketDogrula(h);
    return db.transaction((txn) async {
      final onceki = await txn.query('fabrika_hareketleri', where: 'id = ?', whereArgs: [h.id]);
      if (onceki.isEmpty) throw const FabrikaKayitHatasi('Kayıt bulunamadı (silinmiş olabilir).');
      await _fabrikaVarMi(txn, h.fabrikaId);
      map['updated_at'] = sqliteSimdi();
      await txn.update('fabrika_hareketleri', map, where: 'id = ?', whereArgs: [h.id]);
      await denetimKaydet(txn,
          tablo: 'fabrika_hareketleri', kayitId: h.id!, islem: 'guncelle', oncekiDeger: onceki.first, yeniDeger: map);
    });
  }

  Future<void> hareketSil(int id) => db.transaction((txn) async {
        final onceki = await txn.query('fabrika_hareketleri', where: 'id = ?', whereArgs: [id]);
        if (onceki.isEmpty) return;
        await txn.delete('fabrika_hareketleri', where: 'id = ?', whereArgs: [id]);
        await denetimKaydet(txn, tablo: 'fabrika_hareketleri', kayitId: id, islem: 'sil', oncekiDeger: onceki.first);
      });

  static Map<String, Object?> _hareketDogrula(FabrikaHareketi h) {
    _tarihDogrula(h.tarih);
    final tutar = h.tutar.isFinite ? kurusaYuvarla(h.tutar) : 0.0;
    if (tutar <= 0) throw const FabrikaKayitHatasi('Tutar 0\'dan büyük olmalı.');
    if (tutar > maksimumTutar) throw FabrikaKayitHatasi('Tutar çok yüksek: $tutar ₺.');
    return {
      'fabrika_id': h.fabrikaId,
      'tarih': h.tarih,
      'tur': h.tur.kod,
      'tutar': tutar,
      'aciklama': (h.aciklama == null || h.aciklama!.trim().isEmpty) ? null : h.aciklama!.trim(),
    };
  }

  /// Tüm fabrikaların bakiyeleri (fabrika id → ₺, > 0 fabrika bize borçlu).
  /// Sevkiyat tutarı satır satır kuruşa yuvarlanır (ekstreyle kuruşu kuruşuna aynı).
  Future<Map<int, double>> bakiyeler() async {
    final sonuc = <int, double>{};
    for (final r in await db.query('sevkiyatlar', columns: ['fabrika_id', 'kg', 'birim_fiyat'])) {
      final s = Sevkiyat.fromMap({...r, 'tarih': ''});
      sonuc[s.fabrikaId] = (sonuc[s.fabrikaId] ?? 0) + s.tutar;
    }
    for (final r in await db.query('fabrika_hareketleri', columns: ['fabrika_id', 'tur', 'tutar'])) {
      final h = FabrikaHareketi.fromMap({...r, 'tarih': ''});
      sonuc[h.fabrikaId] = (sonuc[h.fabrikaId] ?? 0) + h.etki;
    }
    return {for (final e in sonuc.entries) e.key: kurusaYuvarla(e.value)};
  }

  // ───────────────────────────── TANK SAYIMI ─────────────────────────────

  /// Aralıktaki gün sonu tank miktarları ('yyyy-MM-dd' → kg).
  Future<Map<String, double>> tankSayimlari(String start, String end) async {
    final r = await db.query('tank_sayimlari', where: 'tarih BETWEEN ? AND ?', whereArgs: [start, end]);
    return {for (final x in r) x['tarih'] as String: ((x['kalan_kg'] as num?) ?? 0).toDouble()};
  }

  Future<({double kalanKg, String? aciklama})?> tankSayimi(String tarih) async {
    final r = await db.query('tank_sayimlari', where: 'tarih = ?', whereArgs: [tarih], limit: 1);
    if (r.isEmpty) return null;
    return (kalanKg: ((r.first['kalan_kg'] as num?) ?? 0).toDouble(), aciklama: r.first['aciklama'] as String?);
  }

  /// Gün sonu tank miktarını yazar (günde tek satır). [kalanKg] 0 ise sayım silinir
  /// (boş tank = sayım yok, fire hesabında ikisi aynı).
  Future<void> tankKaydet(String tarih, double kalanKg, {String? aciklama}) async {
    _tarihDogrula(tarih);
    if (!kalanKg.isFinite || kalanKg < 0) throw const FabrikaKayitHatasi('Tank miktarı geçersiz.');
    if (kalanKg > maksimumTankKg) {
      throw FabrikaKayitHatasi('Tank miktarı çok yüksek: $kalanKg kg (en fazla ${maksimumTankKg.toStringAsFixed(0)} kg).');
    }
    final not = (aciklama == null || aciklama.trim().isEmpty) ? null : aciklama.trim();
    return db.transaction((txn) async {
      final onceki = await txn.query('tank_sayimlari', where: 'tarih = ?', whereArgs: [tarih], limit: 1);
      if (kalanKg == 0) {
        if (onceki.isEmpty) return;
        await txn.delete('tank_sayimlari', where: 'id = ?', whereArgs: [onceki.first['id']]);
        await denetimKaydet(txn, tablo: 'tank_sayimlari', kayitId: onceki.first['id'] as int, islem: 'sil', oncekiDeger: onceki.first);
        return;
      }
      final yeni = {'tarih': tarih, 'kalan_kg': kalanKg, 'aciklama': not};
      if (onceki.isEmpty) {
        final id = await txn.insert('tank_sayimlari', yeni);
        await denetimKaydet(txn, tablo: 'tank_sayimlari', kayitId: id, islem: 'ekle', yeniDeger: yeni);
      } else {
        final o = onceki.first;
        if (((o['kalan_kg'] as num?) ?? 0).toDouble() == kalanKg && o['aciklama'] == not) return;
        final degisen = {...yeni, 'updated_at': sqliteSimdi()};
        await txn.update('tank_sayimlari', degisen, where: 'id = ?', whereArgs: [o['id']]);
        await denetimKaydet(txn, tablo: 'tank_sayimlari', kayitId: o['id'] as int, islem: 'guncelle', oncekiDeger: o, yeniDeger: degisen);
      }
    });
  }

  // ───────────────────────────── ORTAK ─────────────────────────────

  static Future<void> _fabrikaVarMi(DatabaseExecutor ex, int fabrikaId) async {
    final r = await ex.query('fabrikalar', columns: ['id'], where: 'id = ?', whereArgs: [fabrikaId], limit: 1);
    if (r.isEmpty) throw const FabrikaKayitHatasi('Fabrika bulunamadı (silinmiş olabilir). Fabrikayı yeniden seçin.');
  }

  static void _tarihDogrula(String tarih) {
    final gun = _tarihDeseni.hasMatch(tarih) ? DateTime.tryParse(tarih) : null;
    final gecerli = gun != null &&
        '${gun.year.toString().padLeft(4, '0')}-${gun.month.toString().padLeft(2, '0')}-${gun.day.toString().padLeft(2, '0')}' ==
            tarih;
    if (!gecerli) throw FabrikaKayitHatasi('Geçersiz tarih: "$tarih" (beklenen biçim yyyy-AA-gg).');
  }
}
