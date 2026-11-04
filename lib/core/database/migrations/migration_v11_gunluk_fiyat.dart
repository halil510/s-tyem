import 'package:sqflite/sqflite.dart';
import 'migration.dart';

/// v11 — Ay ortasından geçerli fiyat (ör. süt 25 ₺ iken 4 Kasım'dan itibaren
/// 27 ₺).
///
/// `cari_fiyatlar.ay` artık `'yyyy-MM'` (ayın 1'inden itibaren) YA DA
/// `'yyyy-MM-dd'` (o günden itibaren) tutar; şema değişmez. Ancak v9'un
/// kapalı dönem tetikleyicileri `ay` değerini doğrudan dönem ayıyla
/// karşılaştırıyordu — `'2026-09-15'` hiçbir dönemle eşleşmez ve kapalı
/// Eylül'e fiyat yazılabilirdi. Tetikleyiciler `substr(ay, 1, 7)` ile
/// yeniden kurulur.
class MigrationV11GunlukFiyat extends Migration {
  @override
  int get version => 11;

  @override
  String get description => 'cari_fiyatlar gün bazlı geçerlilik: dönem kilidi substr(ay,1,7)';

  static String _kapali(String onek) =>
      "EXISTS (SELECT 1 FROM donemler WHERE ay = substr($onek.ay, 1, 7) AND durum = 'kapali')";

  @override
  Future<void> up(DatabaseExecutor db) async {
    for (final islem in ['ekle', 'guncelle', 'sil']) {
      await db.execute('DROP TRIGGER IF EXISTS trg_cari_fiyatlar_donem_$islem');
    }
    await db.execute('''
      CREATE TRIGGER trg_cari_fiyatlar_donem_ekle BEFORE INSERT ON cari_fiyatlar
      WHEN ${_kapali('NEW')}
      BEGIN SELECT RAISE(ABORT, 'DONEM_KAPALI'); END''');
    await db.execute('''
      CREATE TRIGGER trg_cari_fiyatlar_donem_guncelle BEFORE UPDATE ON cari_fiyatlar
      WHEN ${_kapali('OLD')} OR ${_kapali('NEW')}
      BEGIN SELECT RAISE(ABORT, 'DONEM_KAPALI'); END''');
    await db.execute('''
      CREATE TRIGGER trg_cari_fiyatlar_donem_sil BEFORE DELETE ON cari_fiyatlar
      WHEN ${_kapali('OLD')}
      BEGIN SELECT RAISE(ABORT, 'DONEM_KAPALI'); END''');
  }
}
