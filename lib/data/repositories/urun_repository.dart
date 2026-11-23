import 'package:sqflite/sqflite.dart';

import '../../models/urun_model.dart';
import '../../utils/turkce.dart';
import 'denetim_kaydi.dart';
import 'donem_kilidi.dart';

/// Ürün tanımı / fiyatı kaydedilemediğinde. Mesaj doğrudan kullanıcıya
/// gösterilebilir; fırlatıldığında HİÇBİR şey yazılmamıştır.
class UrunHatasi implements Exception {
  final String mesaj;
  const UrunHatasi(this.mesaj);
  @override
  String toString() => mesaj;
}

/// ─────────────────────────────────────────────────────────────
/// ÜRÜNLER (yem, gübre…) — migration v16
/// ─────────────────────────────────────────────────────────────
class UrunRepository {
  final Database db;
  const UrunRepository(this.db);

  static const maksimumAdUzunlugu = 40;
  static const maksimumBirimUzunlugu = 12;

  /// Ekran sırasıyla (sıra, sonra eklenme).
  Future<List<Urun>> getAll({bool sadeceAktif = false}) async {
    final r = await db.query('urunler', where: sadeceAktif ? 'aktif = 1' : null, orderBy: 'sira, id');
    return r.map(Urun.fromMap).toList();
  }

  /// Ürünün yem (veriş) kaydı sayısı. > 0 ise ürün silinemez, birimi değişmez.
  Future<int> kayitSayisi(int urunId) async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM yemler WHERE urun_id = ?', [urunId])) ?? 0;

  /// Her ürünün kayıt sayısı (ekranda "kaydı var" bilgisi için, tek sorgu).
  Future<Map<int, int>> kayitSayilari() async => {
        for (final r in await db.rawQuery('SELECT urun_id, COUNT(*) AS n FROM yemler WHERE urun_id IS NOT NULL GROUP BY urun_id'))
          r['urun_id'] as int: r['n'] as int,
      };

  static (String, String) _dogrula(String ad, String birim) {
    final a = ad.trim().replaceAll(RegExp(r'\s+'), ' ');
    final b = birim.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (a.isEmpty) throw const UrunHatasi('Ürün adı boş olamaz.');
    if (a.length > maksimumAdUzunlugu) throw const UrunHatasi('Ürün adı en çok $maksimumAdUzunlugu harf olabilir.');
    if (b.isEmpty) throw const UrunHatasi('Birim boş olamaz (ör. kg, çuval, adet).');
    if (b.length > maksimumBirimUzunlugu) throw const UrunHatasi('Birim en çok $maksimumBirimUzunlugu harf olabilir.');
    return (a, b);
  }

  /// Aynı adlı (Türkçe büyük/küçük harf farkı gözetmeksizin) başka ürün var mı?
  static Future<void> _ayniAdKontrol(DatabaseExecutor ex, String ad, int? haricId) async {
    final hedef = turkceKucuk(ad);
    for (final r in await ex.query('urunler', columns: ['id', 'ad'])) {
      if (r['id'] == haricId) continue;
      if (turkceKucuk((r['ad'] as String).trim()) == hedef) {
        throw UrunHatasi('"${r['ad']}" adında bir ürün zaten var.');
      }
    }
  }

  Future<int> ekle({required String ad, String birim = 'kg'}) async {
    final (a, b) = _dogrula(ad, birim);
    return db.transaction((txn) async {
      await _ayniAdKontrol(txn, a, null);
      final sira = (Sqflite.firstIntValue(await txn.rawQuery('SELECT COALESCE(MAX(sira), 0) FROM urunler')) ?? 0) + 1;
      final map = {'ad': a, 'birim': b, 'sira': sira, 'aktif': 1};
      final id = await txn.insert('urunler', map);
      await denetimKaydet(txn, tablo: 'urunler', kayitId: id, islem: 'ekle', yeniDeger: map);
      return id;
    });
  }

  /// Ad ve birimi değiştirir. Kaydı olan ürünün birimi DEĞİŞTİRİLEMEZ
  /// (geçmişteki "5 kg" sonradan "5 çuval" okunmasın).
  Future<void> guncelle(int id, {required String ad, required String birim}) async {
    final (a, b) = _dogrula(ad, birim);
    await db.transaction((txn) async {
      final eski = await txn.query('urunler', where: 'id = ?', whereArgs: [id], limit: 1);
      if (eski.isEmpty) throw const UrunHatasi('Ürün bulunamadı (başka telefonda silinmiş olabilir).');
      await _ayniAdKontrol(txn, a, id);
      final eskiBirim = (eski.first['birim'] as String?) ?? 'kg';
      if (eskiBirim != b) {
        final n = Sqflite.firstIntValue(await txn.rawQuery('SELECT COUNT(*) FROM yemler WHERE urun_id = ?', [id])) ?? 0;
        if (n > 0) {
          throw UrunHatasi('Bu ürünün $n kaydı var; birimi değiştirilemez ("$eskiBirim" kalmalı). '
              'Farklı birim gerekiyorsa yeni ürün ekleyin.');
        }
      }
      final map = {'ad': a, 'birim': b, 'updated_at': sqliteSimdi()};
      await txn.update('urunler', map, where: 'id = ?', whereArgs: [id]);
      await denetimKaydet(txn, tablo: 'urunler', kayitId: id, islem: 'guncelle', oncekiDeger: eski.first, yeniDeger: map);
    });
  }

  /// Pasif ürün Yem Ekle ve Yem Fiyatları ekranlarında görünmez; geçmiş kayıtları
  /// ve bakiyeye etkisi aynen kalır.
  Future<void> aktiflikDegistir(int id, bool aktif) async {
    await db.transaction((txn) async {
      final n = await txn.update('urunler', {'aktif': aktif ? 1 : 0, 'updated_at': sqliteSimdi()}, where: 'id = ?', whereArgs: [id]);
      if (n == 0) throw const UrunHatasi('Ürün bulunamadı.');
      await denetimKaydet(txn, tablo: 'urunler', kayitId: id, islem: 'guncelle', yeniDeger: {'aktif': aktif ? 1 : 0});
    });
  }

  /// Ekran sırasını verilen sıraya göre 1..N yazar (değişmeyenlere dokunmaz).
  Future<void> siraKaydet(List<int> idler) async {
    await db.transaction((txn) async {
      final mevcut = {for (final r in await txn.query('urunler', columns: ['id', 'sira'])) r['id'] as int: r['sira'] as int?};
      for (var i = 0; i < idler.length; i++) {
        if (!mevcut.containsKey(idler[i]) || mevcut[idler[i]] == i + 1) continue;
        await txn.update('urunler', {'sira': i + 1, 'updated_at': sqliteSimdi()}, where: 'id = ?', whereArgs: [idler[i]]);
      }
    });
  }

  /// Yalnız HİÇ kaydı olmayan ürün silinir (fiyat tanımları da silinir).
  /// Kaydı olan ürün pasife alınmalıdır; veritabanı da (RESTRICT) izin vermez.
  Future<void> sil(int id) async {
    await donemKilidiyle(() => db.transaction((txn) async {
          final eski = await txn.query('urunler', where: 'id = ?', whereArgs: [id], limit: 1);
          if (eski.isEmpty) return;
          final n = Sqflite.firstIntValue(await txn.rawQuery('SELECT COUNT(*) FROM yemler WHERE urun_id = ?', [id])) ?? 0;
          if (n > 0) {
            throw UrunHatasi('"${eski.first['ad']}" ürününün $n kaydı var; silinemez. '
                'Kullanmayacaksanız pasife alın (geçmiş kayıtlar ve bakiyeler korunur).');
          }
          await txn.delete('urunler', where: 'id = ?', whereArgs: [id]);
          await denetimKaydet(txn, tablo: 'urunler', kayitId: id, islem: 'sil', oncekiDeger: eski.first);
        }));
  }
}

/// ─────────────────────────────────────────────────────────────
/// CARİ ÜRÜN FİYATLARI (cari + ürün + ay → birim fiyat)
/// ─────────────────────────────────────────────────────────────
/// Kural süt fiyatıyla aynı: kaydın gününe kadar başlamış EN SON fiyat
/// ([UrunFiyatLookup]). Ekran fiyatı AYLIK girer ('yyyy-MM').
class UrunFiyatRepository {
  final Database db;
  const UrunFiyatRepository(this.db);

  static const maksimumFiyat = 1000000.0;
  static final _ayDeseni = RegExp(r'^\d{4}-(0[1-9]|1[0-2])$');

  Future<List<UrunFiyat>> getTumFiyatlar({int? cariId}) async {
    final r = cariId != null
        ? await db.query('cari_urun_fiyatlari', where: 'cari_id = ?', whereArgs: [cariId])
        : await db.query('cari_urun_fiyatlari');
    return r.map(UrunFiyat.fromMap).toList();
  }

  Future<UrunFiyatLookup> lookup({int? cariId}) async => UrunFiyatLookup(await getTumFiyatlar(cariId: cariId));

  /// [ay] ('yyyy-MM') başında geçerli fiyatlar: cariId → (urunId → fiyat).
  /// Tanımsız fiyat haritada yoktur (= 0, önceki aydan devralınacak bir şey yok).
  Future<Map<int, Map<int, double>>> ayBasiFiyatlari(List<int> cariIdleri, String ay) async {
    final istenen = cariIdleri.toSet();
    final satirlar = (await db.query('cari_urun_fiyatlari', where: 'ay <= ?', whereArgs: [ay]))
        .map(UrunFiyat.fromMap)
        .where((f) => istenen.contains(f.cariId))
        .toList();
    final l = UrunFiyatLookup(satirlar);
    final sonuc = <int, Map<int, double>>{for (final id in cariIdleri) id: {}};
    for (final f in satirlar) {
      sonuc[f.cariId]![f.urunId] = l.fiyat(f.cariId, f.urunId, ay);
    }
    return sonuc;
  }

  /// Bir ayın ürün fiyatlarını TEK transaction'da yazar (ya hepsi ya hiçbiri).
  ///
  /// Her (cari, ürün) için:
  ///  • o ayın satırı varsa fiyatı güncellenir;
  ///  • yoksa ve fiyat ay başında zaten geçerli olandan (devralınan) FARKLIYSA ayın satırı eklenir
  ///    (değişmeyen fiyat için gereksiz satır yazılmaz — sonraki ayların devri bozulmasın);
  ///  • ayın içindeki gün başlangıçlı eski satırlar ('yyyy-MM-dd', eski veriden) silinir:
  ///    aylık girilen fiyat ayın TAMAMINA uygulanır (eski "aya yay" davranışı).
  Future<void> ayFiyatlariniKaydet(String ay, List<({int cariId, int urunId, double fiyat})> fiyatlar) async {
    if (!_ayDeseni.hasMatch(ay)) throw UrunHatasi('Geçersiz ay: "$ay"');
    for (final f in fiyatlar) {
      if (!f.fiyat.isFinite || f.fiyat < 0) throw const UrunHatasi('Fiyat negatif ya da geçersiz olamaz.');
      if (f.fiyat > maksimumFiyat) throw const UrunHatasi('Fiyat çok büyük; yazımı kontrol edin.');
    }
    await donemKilidiyle(() => db.transaction((txn) async {
          final cariler = fiyatlar.map((f) => f.cariId).toSet();
          final mevcut = (await txn.query('cari_urun_fiyatlari', where: 'ay <= ?', whereArgs: [ay]))
              .map(UrunFiyat.fromMap)
              .where((f) => cariler.contains(f.cariId))
              .toList();
          final l = UrunFiyatLookup(mevcut);
          final ayinSatiri = {for (final f in mevcut.where((f) => f.ay == ay)) '${f.cariId}|${f.urunId}': f};
          for (final f in fiyatlar) {
            final satir = ayinSatiri['${f.cariId}|${f.urunId}'];
            if (satir != null) {
              if (satir.fiyat != f.fiyat) {
                await txn.update('cari_urun_fiyatlari', {'fiyat': f.fiyat, 'updated_at': sqliteSimdi()},
                    where: 'id = ?', whereArgs: [satir.id]);
              }
            } else if (l.fiyat(f.cariId, f.urunId, ay) != f.fiyat) {
              await txn.insert('cari_urun_fiyatlari', {'cari_id': f.cariId, 'urun_id': f.urunId, 'ay': ay, 'fiyat': f.fiyat});
            }
            await txn.delete('cari_urun_fiyatlari',
                where: 'cari_id = ? AND urun_id = ? AND ay LIKE ?', whereArgs: [f.cariId, f.urunId, '$ay-%']);
          }
        }));
  }

  /// Tek fiyat (testler ve tekil düzeltme için) — [ayFiyatlariniKaydet] ile aynı kural.
  Future<void> kaydet({required int cariId, required int urunId, required String ay, required double fiyat}) =>
      ayFiyatlariniKaydet(ay, [(cariId: cariId, urunId: urunId, fiyat: fiyat)]);
}
