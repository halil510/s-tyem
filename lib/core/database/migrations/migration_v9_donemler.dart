import 'package:sqflite/sqflite.dart';
import '../table_builder.dart';
import 'migration.dart';

/// v9 — Aylık dönem kapanışı ve üretici hakedişi.
///
/// - `donemler`: her ay ('yyyy-MM') için durum: 'acik' | 'kapali'.
/// - `donem_hakedisleri`: kapanış anındaki bordro (sonradan fiyat ya da
///   kayıt değişse bile kapanmış dönemin rakamları değişmez).
/// - Tetikleyiciler: kapalı aya ait süt / yem / ödeme / fiyat satırı
///   eklenemez, değiştirilemez, silinemez (`RAISE(ABORT, 'DONEM_KAPALI')`).
///   Kilit veritabanında olduğu için hangi ekrandan gelirse gelsin geçerli.
class MigrationV9Donemler extends Migration {
  @override
  int get version => 9;

  @override
  String get description => 'donemler + donem_hakedisleri + kapalı dönem kilidi';

  /// Kilitlenen tablolar ve ayı veren SQL ifadesi (NEW/OLD önekiyle).
  static const _kilitli = {
    'sutler': 'substr(%.tarih, 1, 7)',
    'yemler': 'substr(%.tarih, 1, 7)',
    'cari_odemeler': 'substr(%.tarih, 1, 7)',
    'cari_fiyatlar': '%.ay',
  };

  static String _kapali(String ayIfadesi) =>
      "EXISTS (SELECT 1 FROM donemler WHERE ay = $ayIfadesi AND durum = 'kapali')";

  @override
  Future<void> up(DatabaseExecutor db) async {
    await TableBuilder('donemler')
        .id()
        .text('ay', notNull: true) // 'yyyy-MM'
        .text('durum', notNull: true, defaultValue: 'acik') // 'acik' | 'kapali'
        .text('kapanis_tarihi')
        .integer('acilis_sayisi', defaultValue: '0')
        .text('aciklama')
        .timestamps()
        .unique(['ay'])
        .create(db);

    await TableBuilder('donem_hakedisleri')
        .id()
        .integer('donem_id', notNull: true)
        .integer('cari_id', notNull: true)
        .real('devir')
        .real('sut_kg')
        .real('sut_fiyat')
        .real('sut_tutar')
        .real('yem_kg')
        .real('yem_tutar')
        .real('odeme')
        .real('tahsilat')
        .real('donem_sonu')
        .raw("created_at TEXT DEFAULT (datetime('now'))")
        .unique(['donem_id', 'cari_id'])
        .foreignKey('donem_id', refTable: 'donemler')
        .foreignKey('cari_id', refTable: 'cariler')
        .create(db);

    for (final e in _kilitli.entries) {
      final t = e.key;
      String ay(String onek) => e.value.replaceAll('%', onek);
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_${t}_donem_ekle BEFORE INSERT ON $t
        WHEN ${_kapali(ay('NEW'))}
        BEGIN SELECT RAISE(ABORT, 'DONEM_KAPALI'); END''');
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_${t}_donem_guncelle BEFORE UPDATE ON $t
        WHEN ${_kapali(ay('OLD'))} OR ${_kapali(ay('NEW'))}
        BEGIN SELECT RAISE(ABORT, 'DONEM_KAPALI'); END''');
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_${t}_donem_sil BEFORE DELETE ON $t
        WHEN ${_kapali(ay('OLD'))}
        BEGIN SELECT RAISE(ABORT, 'DONEM_KAPALI'); END''');
    }

    // Kapalı dönemin bordrosu da korunur (ör. cari silinince CASCADE ile).
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_donem_hakedisleri_sil BEFORE DELETE ON donem_hakedisleri
      WHEN EXISTS (SELECT 1 FROM donemler WHERE id = OLD.donem_id AND durum = 'kapali')
      BEGIN SELECT RAISE(ABORT, 'DONEM_KAPALI'); END''');
  }
}
