import 'package:sqflite/sqflite.dart';
import '../table_builder.dart';
import 'migration.dart';

/// v10 — Yalnızca tarihe göre yapılan sorgular için indeksler.
///
/// v4'teki `(cari_id, tarih)` indeksleri "bir carinin kayıtları" sorgusunu
/// hızlandırır; ama "bir günün / bir ayın TÜM kayıtları" (Hızlı Süt Girişi,
/// Özet, Aylık Rapor, Dönem Kapanışı) `cari_id` vermediği için o indeksi
/// kullanamaz ve tabloyu baştan sona tarar. Kayıt sayısı yıllar içinde
/// on binlere çıktığında bu ekranlar yavaşlar.
class MigrationV10TarihIndeksleri extends Migration {
  @override
  int get version => 10;

  @override
  String get description => 'sutler/yemler/cari_odemeler tarih indeksleri';

  @override
  Future<void> up(DatabaseExecutor db) async {
    await SchemaInspector.createIndexIfMissing(db, 'idx_sutler_tarih', 'sutler', ['tarih']);
    await SchemaInspector.createIndexIfMissing(db, 'idx_yemler_tarih', 'yemler', ['tarih']);
    await SchemaInspector.createIndexIfMissing(db, 'idx_odemeler_tarih', 'cari_odemeler', ['tarih']);
  }
}
