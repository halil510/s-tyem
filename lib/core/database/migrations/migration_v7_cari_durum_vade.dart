import 'package:sqflite/sqflite.dart';
import '../table_builder.dart';
import 'migration.dart';

/// v7 — Profesyonel cari yönetimi için ek alanlar:
/// - `cariler.aktif`: pasife alınan (ör. artık süt getirmeyen) cariler
///   silinmeden listeden gizlenebilir (soft delete yerine durum bayrağı).
/// - `cariler.not_metni`: serbest metin not alanı.
/// - `cari_odemeler.vade_tarihi`: borcun ödenmesi beklenen tarih —
///   vadesi geçmiş borçları raporlamak için kullanılır.
class MigrationV7CariDurumVade extends Migration {
  @override
  int get version => 7;

  @override
  String get description =>
      'cariler.aktif/not_metni + cari_odemeler.vade_tarihi sütunları';

  @override
  Future<void> up(DatabaseExecutor db) async {
    await SchemaInspector.addColumnIfMissing(
      db, 'cariler', 'aktif', 'INTEGER DEFAULT 1',
    );
    await SchemaInspector.addColumnIfMissing(
      db, 'cariler', 'not_metni', 'TEXT',
    );
    await SchemaInspector.addColumnIfMissing(
      db, 'cari_odemeler', 'vade_tarihi', 'TEXT',
    );
  }
}
