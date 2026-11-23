import 'package:sqflite/sqflite.dart';
import '../../models/yem_model.dart';
import 'donem_kilidi.dart';

class YemRepository {
  final Database db;
  const YemRepository(this.db);

  /// Tek satır miktarı için üst sınır (yazım hatası: "50" yerine "50000").
  static const maksimumMiktar = 100000.0;

  /// Aynı gün birden çok yem teslimatı olabilir; bu yüzden (sütün aksine)
  /// her teslimat — ve her ürün — ayrı satırdır.
  Future<int> insert(Yem yem) async {
    _dogrula(yem);
    return donemKilidiyle(() => db.insert('yemler', yem.toMap()..remove('id')));
  }

  /// Bir teslimattaki birden çok ürünü TEK transaction'da yazar: ya hepsi ya hiçbiri
  /// (ortada hata olursa cariye yarım yem borcu yazılmaz).
  Future<List<int>> topluEkle(List<Yem> yemler) async {
    for (final y in yemler) {
      _dogrula(y);
    }
    return donemKilidiyle(() => db.transaction((txn) async => [
          for (final y in yemler) await txn.insert('yemler', y.toMap()..remove('id')),
        ]));
  }

  static void _dogrula(Yem y) {
    if (!y.miktar.isFinite || y.miktar <= 0) {
      throw ArgumentError('Miktar sıfırdan büyük olmalı');
    }
    if (y.miktar > maksimumMiktar) {
      throw ArgumentError('Miktar çok büyük; yazımı kontrol edin');
    }
    if (y.urunId <= 0) throw ArgumentError('Ürün seçilmedi');
  }

  Future<List<Yem>> getByCari(int cariId, String start, String end) async {
    final maps = await db.query(
      'yemler',
      where: 'cari_id = ? AND tarih BETWEEN ? AND ?',
      whereArgs: [cariId, start, end],
      orderBy: 'tarih ASC, id ASC',
    );
    return maps.map(Yem.fromMap).toList();
  }

  Future<List<Yem>> getAllInRange(String start, String end) async {
    final maps = await db.query(
      'yemler',
      where: 'tarih BETWEEN ? AND ?',
      whereArgs: [start, end],
      orderBy: 'tarih ASC, id ASC',
    );
    return maps.map(Yem.fromMap).toList();
  }

  Future<int> update(Yem yem) async {
    _dogrula(yem);
    return donemKilidiyle(
        () => db.update('yemler', yem.toMap()..remove('id'), where: 'id = ?', whereArgs: [yem.id]));
  }

  Future<int> delete(int id) =>
      donemKilidiyle(() => db.delete('yemler', where: 'id = ?', whereArgs: [id]));
}
