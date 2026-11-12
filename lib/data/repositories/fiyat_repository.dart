import 'package:sqflite/sqflite.dart';
import '../../models/fiyat_model.dart';
import '../../models/cari_fiyat_model.dart';
import 'donem_kilidi.dart';

/// Eski / global (cariye bağlı olmayan) fiyat tanımları.
class FiyatRepository {
  final Database db;
  const FiyatRepository(this.db);

  Future<int> insert(Fiyat fiyat) => db.insert('fiyatlar', fiyat.toMap());

  Future<List<Fiyat>> getByUrunTuru(String urunTuru) async {
    final maps = await db.query(
      'fiyatlar',
      where: 'urun_turu = ?',
      whereArgs: [urunTuru],
      orderBy: 'tarih DESC, id DESC',
    );
    return maps.map(Fiyat.fromMap).toList();
  }

  Future<Fiyat?> getGuncel(String urunTuru) async {
    final maps = await db.query(
      'fiyatlar',
      where: 'urun_turu = ?',
      whereArgs: [urunTuru],
      orderBy: 'tarih DESC, id DESC',
      limit: 1,
    );
    return maps.isNotEmpty ? Fiyat.fromMap(maps.first) : null;
  }

  Future<int> delete(int id) => db.delete('fiyatlar', where: 'id = ?', whereArgs: [id]);
}

/// Cari bazlı fiyat tanımları (her müşteri için farklı fiyat). Anahtar
/// `ay`: `'yyyy-MM'` (ay başından) ya da `'yyyy-MM-dd'` (o günden itibaren).
class CariFiyatRepository {
  final Database db;
  const CariFiyatRepository(this.db);

  Future<CariFiyat?> getirTekil(int cariId, String ay) async {
    final maps = await db.query(
      'cari_fiyatlar',
      where: 'cari_id = ? AND ay = ?',
      whereArgs: [cariId, ay],
    );
    return maps.isNotEmpty ? CariFiyat.fromMap(maps.first) : null;
  }

  Future<CariFiyat?> getirSonGecerli(int cariId, String ay) async {
    final maps = await db.query(
      'cari_fiyatlar',
      where: 'cari_id = ? AND ay <= ?',
      whereArgs: [cariId, ay],
      orderBy: 'ay DESC',
      limit: 1,
    );
    return maps.isNotEmpty ? CariFiyat.fromMap(maps.first) : null;
  }

  Future<void> kaydet(CariFiyat fiyat) => donemKilidiyle(() => _kaydet(fiyat));

  /// Birçok carinin fiyatını TEK transaction'da yazar: ya hepsi ya hiçbiri
  /// (fiyat ekranında 100 cari = tek disk yazımı; eskiden cari başına ayrı).
  ///
  /// [yemFiyatiniAyaYay]: Yem fiyatları AYLIK girilir. Ay ortasından geçerli
  /// süt fiyatı satırları (`'yyyy-MM-dd'`) da yem fiyatı taşır; aylık yem
  /// fiyatı kaydedilince aynı ayın bu gün satırlarının yem fiyatları da
  /// güncellenir — yoksa ayın kalanı eski yem fiyatıyla hesaplanırdı.
  Future<void> topluKaydet(List<CariFiyat> fiyatlar, {bool yemFiyatiniAyaYay = false}) =>
      donemKilidiyle(
        () => db.transaction((txn) async {
          for (final f in fiyatlar) {
            final map = f.toMap()..remove('id');
            final guncellenen = await txn.update('cari_fiyatlar', map,
                where: 'cari_id = ? AND ay = ?', whereArgs: [f.cariId, f.ay]);
            // Yeni satırda ekranın DEĞİŞTİRMEDİĞİ grup (Yem Fiyatı ekranında süt fiyatı, Süt Fiyatı
            // ekranında yem fiyatları) yalnız kopyadır: başka telefonda girilmiş gerçek fiyatı
            // çoklu cihaz birleşmesinde ezmesin diye zamanı "en eski" ('') verilir.
            if (guncellenen == 0) {
              await txn.insert('cari_fiyatlar', {...map, if (yemFiyatiniAyaYay) 'sut_zaman': '' else 'yem_zaman': ''});
            }
            if (yemFiyatiniAyaYay && f.ay.length == 7) {
              await txn.update(
                'cari_fiyatlar',
                {
                  'sut_yemi_fiyat': f.sutYemiFiyat,
                  'besi_yemi_fiyat': f.besiYemiFiyat,
                  'b_baslangic_fiyat': f.bBaslangicFiyat,
                  'b_buyutme_fiyat': f.bBuyutmeFiyat,
                  'kuzu_yemi_fiyat': f.kuzuYemiFiyat,
                  'tavuk_yemi_fiyat': f.tavukYemiFiyat,
                },
                where: 'cari_id = ? AND ay LIKE ?',
                whereArgs: [f.cariId, '${f.ay}-%'],
              );
            }
          }
        }),
      );

  Future<void> _kaydet(CariFiyat fiyat) async {
    final mevcut = await getirTekil(fiyat.cariId, fiyat.ay);
    if (mevcut != null) {
      // ÖNEMLİ: `toMap()` içindeki `id` alanı UPDATE'e dahil edilmemeli.
      // `id`, INTEGER PRIMARY KEY (rowid) olduğundan NULL yazılmaya
      // çalışılması "datatype mismatch (code 20)" hatasına yol açar.
      final guncellemeMap = fiyat.toMap()..remove('id');
      await db.update('cari_fiyatlar', guncellemeMap,
          where: 'cari_id = ? AND ay = ?', whereArgs: [fiyat.cariId, fiyat.ay]);
    } else {
      final eklemeMap = fiyat.toMap()..remove('id');
      await db.insert('cari_fiyatlar', eklemeMap);
    }
  }

  /// Bir ay için fiyat tanımlı değilse, bir önceki aydan devralır.
  Future<CariFiyat> oncekiAydanDevral(int cariId, String ay) async {
    final parts = ay.split('-');
    final yil = int.parse(parts[0]);
    final ayNo = int.parse(parts[1]);
    final oncekiAy = ayNo == 1 ? '${yil - 1}-12' : '$yil-${(ayNo - 1).toString().padLeft(2, '0')}';

    final onceki = await getirSonGecerli(cariId, oncekiAy);
    if (onceki != null) {
      return CariFiyat(
        cariId: cariId,
        ay: ay,
        sutFiyat: onceki.sutFiyat,
        sutYemiFiyat: onceki.sutYemiFiyat,
        besiYemiFiyat: onceki.besiYemiFiyat,
        bBaslangicFiyat: onceki.bBaslangicFiyat,
        bBuyutmeFiyat: onceki.bBuyutmeFiyat,
        kuzuYemiFiyat: onceki.kuzuYemiFiyat,
        tavukYemiFiyat: onceki.tavukYemiFiyat,
      );
    }
    return CariFiyat(cariId: cariId, ay: ay);
  }

  /// Bir cari için TÜM ay fiyatlarını tek sorguda getirir (N+1
  /// sorgu sorununu önlemek için — canlı bakiye hesaplamasında
  /// kullanılır, bkz. `CariFiyatLookup`).
  Future<List<CariFiyat>> getTumFiyatlar({int? cariId}) async {
    final maps = cariId != null
        ? await db.query('cari_fiyatlar', where: 'cari_id = ?', whereArgs: [cariId])
        : await db.query('cari_fiyatlar');
    return maps.map(CariFiyat.fromMap).toList();
  }

  /// Bir listedeki tüm cariler için, belirtilen ayın fiyatını getirir.
  /// O ay için tanımlı fiyat yoksa önceki aydan devralır (varsayılan).
  /// Her cari için [ay]'ın geçerli fiyatı: o ay tanımlıysa kendisi (id'li),
  /// değilse en son önceki ayın fiyatı bu aya taşınmış olarak (id'siz), hiç
  /// yoksa sıfır fiyat. TEK sorgu (eskiden cari başına 2 sorgu — 100 cari = 200).
  Future<Map<int, CariFiyat>> getAyFiyatlariHepsi(List<int> cariIdleri, String ay) async {
    final istenen = cariIdleri.toSet();
    final sonGecerli = <int, CariFiyat>{};
    final satirlar = await db.query('cari_fiyatlar', where: 'ay <= ?', whereArgs: [ay], orderBy: 'cari_id, ay');
    for (final m in satirlar) {
      final f = CariFiyat.fromMap(m);
      if (istenen.contains(f.cariId)) sonGecerli[f.cariId] = f; // ay sıralı: sonuncusu en yeni
    }
    return {
      for (final id in cariIdleri)
        id: switch (sonGecerli[id]) {
          null => CariFiyat(cariId: id, ay: ay),
          final f when f.ay == ay => f,
          final f => CariFiyat(
              cariId: id,
              ay: ay,
              sutFiyat: f.sutFiyat,
              sutYemiFiyat: f.sutYemiFiyat,
              besiYemiFiyat: f.besiYemiFiyat,
              bBaslangicFiyat: f.bBaslangicFiyat,
              bBuyutmeFiyat: f.bBuyutmeFiyat,
              kuzuYemiFiyat: f.kuzuYemiFiyat,
              tavukYemiFiyat: f.tavukYemiFiyat,
            ),
        },
    };
  }
}
