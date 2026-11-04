import 'package:sqflite/sqflite.dart';
import '../../models/yem_model.dart';
import 'donem_kilidi.dart';

class YemRepository {
  final Database db;
  const YemRepository(this.db);

  /// Aynı gün birden çok yem teslimatı olabilir; bu yüzden (sütün aksine)
  /// her teslimat ayrı satırdır.
  Future<int> insert(Yem yem) {
    _dogrula(yem);
    return donemKilidiyle(() => db.insert('yemler', yem.toMap()..remove('id')));
  }

  static void _dogrula(Yem y) {
    final miktarlar = [y.sutYemi, y.besiYemi, y.bBaslangic, y.bBuyutme, y.kuzuYemi, y.tavukYemi];
    if (miktarlar.any((m) => !m.isFinite || m < 0)) {
      throw ArgumentError('Yem miktarı negatif veya geçersiz olamaz');
    }
  }

  Future<List<Yem>> getByCari(int cariId, String start, String end) async {
    final maps = await db.query(
      'yemler',
      where: 'cari_id = ? AND tarih BETWEEN ? AND ?',
      whereArgs: [cariId, start, end],
      orderBy: 'tarih ASC',
    );
    return maps.map(Yem.fromMap).toList();
  }

  Future<List<Yem>> getAllInRange(String start, String end) async {
    final maps = await db.query(
      'yemler',
      where: 'tarih BETWEEN ? AND ?',
      whereArgs: [start, end],
      orderBy: 'tarih ASC',
    );
    return maps.map(Yem.fromMap).toList();
  }

  Future<int> update(Yem yem) {
    _dogrula(yem);
    return donemKilidiyle(
        () => db.update('yemler', yem.toMap()..remove('id'), where: 'id = ?', whereArgs: [yem.id]));
  }

  Future<int> delete(int id) =>
      donemKilidiyle(() => db.delete('yemler', where: 'id = ?', whereArgs: [id]));
}
