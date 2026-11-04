import 'package:sqflite/sqflite.dart';
import '../table_builder.dart';
import 'migration.dart';

/// v1 — Uygulamanın temel şeması: cariler, süt/yem hareketleri ve
/// eski (global, cari'ye bağlı olmayan) fiyat tablosu.
class MigrationV1Initial extends Migration {
  @override
  int get version => 1;

  @override
  String get description => 'Temel şema: cariler, sutler, yemler, fiyatlar';

  @override
  Future<void> up(DatabaseExecutor db) async {
    await TableBuilder('cariler')
        .id()
        .text('ad', notNull: true)
        .text('soyad', notNull: true)
        .text('adres')
        .text('telefon')
        .text('hayvan_turu')
        .timestamps()
        .create(db);

    await TableBuilder('sutler')
        .id()
        .integer('cari_id', notNull: true)
        .text('tarih', notNull: true)
        .real('sabah', defaultValue: '0')
        .real('aksam', defaultValue: '0')
        .real('toplam', defaultValue: '0')
        .text('aciklama')
        .timestamps()
        .foreignKey('cari_id', refTable: 'cariler')
        .create(db);

    await TableBuilder('yemler')
        .id()
        .integer('cari_id', notNull: true)
        .text('tarih', notNull: true)
        .real('sut_yemi', defaultValue: '0')
        .real('besi_yemi', defaultValue: '0')
        .real('b_baslangic', defaultValue: '0')
        .real('b_buyutme', defaultValue: '0')
        .real('kuzu_yemi', defaultValue: '0')
        .real('tavuk_yemi', defaultValue: '0')
        .real('toplam', defaultValue: '0')
        .text('aciklama')
        .timestamps()
        .foreignKey('cari_id', refTable: 'cariler')
        .create(db);

    await TableBuilder('fiyatlar')
        .id()
        .text('urun_turu', notNull: true)
        .real('birim_fiyat', notNull: true, defaultValue: '0')
        .text('tarih', notNull: true)
        .text('aciklama')
        .timestamps()
        .create(db);
  }
}
