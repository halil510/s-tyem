import 'package:sqflite/sqflite.dart';
import '../table_builder.dart';
import 'migration.dart';

/// v3 — Cari bazlı, aylık fiyat tablosu (her müşteri için farklı
/// süt/yem birim fiyatı tanımlanabilir) ve ödeme kalemlerinin
/// detayını JSON olarak saklayan sütun.
class MigrationV3CariFiyatlar extends Migration {
  @override
  int get version => 3;

  @override
  String get description =>
      'cari_fiyatlar tablosu + cari_odemeler.detay_json sütunu';

  @override
  Future<void> up(DatabaseExecutor db) async {
    await TableBuilder('cari_fiyatlar')
        .id()
        .integer('cari_id', notNull: true)
        .text('ay', notNull: true) // 'yyyy-MM'
        .real('sut_fiyat', defaultValue: '0')
        .real('sut_yemi_fiyat', defaultValue: '0')
        .real('besi_yemi_fiyat', defaultValue: '0')
        .real('b_baslangic_fiyat', defaultValue: '0')
        .real('b_buyutme_fiyat', defaultValue: '0')
        .real('kuzu_yemi_fiyat', defaultValue: '0')
        .real('tavuk_yemi_fiyat', defaultValue: '0')
        .unique(['cari_id', 'ay'])
        .foreignKey('cari_id', refTable: 'cariler')
        .create(db);

    await SchemaInspector.addColumnIfMissing(
      db,
      'cari_odemeler',
      'detay_json',
      'TEXT',
    );
  }
}
