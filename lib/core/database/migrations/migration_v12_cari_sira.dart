import 'package:sqflite/sqflite.dart';
import '../table_builder.dart';
import 'migration.dart';

/// v12 — Süt toplama sırası (rota).
///
/// `cariler.sira`: aktif carinin toplama turundaki yeri (1, 2, 3…). Boş
/// (NULL) ise cari rotada sırasızdır ve listelerde sıralıların ardından
/// alfabetik gelir. Numaralar `CariRepository.siraAta` / `rotaKaydet` ile
/// daima 1..N boşluksuz tutulur; pasife alınan carinin sırası boşaltılır.
class MigrationV12CariSira extends Migration {
  @override
  int get version => 12;

  @override
  String get description => 'cariler.sira (süt toplama rotası)';

  @override
  Future<void> up(DatabaseExecutor db) async {
    await SchemaInspector.addColumnIfMissing(db, 'cariler', 'sira', 'INTEGER');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cariler_sira ON cariler(sira)');
  }
}
