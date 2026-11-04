import 'package:sqflite/sqflite.dart';
import '../table_builder.dart';
import 'migration.dart';

/// v4 — Performans indexleri.
///
/// Uygulama büyüdükçe (yüzlerce cari, binlerce süt/yem/ödeme kaydı)
/// `cari_id` ve `tarih` üzerinden yapılan sorgular yavaşlar. Bu
/// migration, en sık kullanılan sorgu desenlerine (cariye göre
/// filtreleme + tarih aralığı) karşılık gelen index'leri ekler.
class MigrationV4Indexler extends Migration {
  @override
  int get version => 4;

  @override
  String get description => 'Performans indexleri (cari_id + tarih)';

  @override
  Future<void> up(DatabaseExecutor db) async {
    await SchemaInspector.createIndexIfMissing(
      db, 'idx_sutler_cari_tarih', 'sutler', ['cari_id', 'tarih'],
    );
    await SchemaInspector.createIndexIfMissing(
      db, 'idx_yemler_cari_tarih', 'yemler', ['cari_id', 'tarih'],
    );
    await SchemaInspector.createIndexIfMissing(
      db, 'idx_odemeler_cari_tarih', 'cari_odemeler', ['cari_id', 'tarih'],
    );
    await SchemaInspector.createIndexIfMissing(
      db, 'idx_odemeler_islem_turu', 'cari_odemeler', ['islem_turu'],
    );
    await SchemaInspector.createIndexIfMissing(
      db, 'idx_cari_fiyatlar_ay', 'cari_fiyatlar', ['ay'],
    );
    await SchemaInspector.createIndexIfMissing(
      db, 'idx_cariler_ad_soyad', 'cariler', ['ad', 'soyad'],
    );
  }
}
