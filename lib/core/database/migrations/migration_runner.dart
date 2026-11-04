import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'migration.dart';
import 'migration_v1_initial.dart';
import 'migration_v2_cari_odemeler.dart';
import 'migration_v3_cari_fiyatlar.dart';
import 'migration_v4_indexler.dart';
import 'migration_v5_terazi_cihazlari.dart';
import 'migration_v6_islem_gecmisi.dart';
import 'migration_v7_cari_durum_vade.dart';
import 'migration_v8_sut_gunluk_tekil.dart';
import 'migration_v9_donemler.dart';

/// ─────────────────────────────────────────────────────────────
/// MIGRATION RUNNER
/// ─────────────────────────────────────────────────────────────
///
/// Veritabanının şema versiyonunu SQLite'ın kendi `PRAGMA user_version`
/// mekanizması ile takip eder (sqflite'ın `onCreate`/`onUpgrade`
/// callback'lerine bağımlı kalmak yerine tam kontrol sağlar).
///
/// Uygulama her açıldığında [run] çağrılır:
/// 1. Mevcut `user_version` okunur.
/// 2. Bu değerden büyük versiyon numarasına sahip tüm migration'lar,
///    versiyon sırasına göre bulunur.
/// 3. Her migration bir transaction içinde uygulanır, `user_version`
///    o migration'ın versiyonuna güncellenir ve `_migration_log`
///    tablosuna bir kayıt düşülür.
/// 4. Bir migration hata verirse işlem durur ve versiyon ilerletilmez
///    (bir sonraki açılışta kaldığı yerden devam eder).
///
/// Yeni bir şema değişikliği eklemek için:
/// 1. `migrations/migration_vN_aciklama.dart` dosyasını oluştur.
/// 2. [Migration]'dan türet, `version` ve `up()` yaz.
/// 3. Bu dosyadaki [_all] listesine ekle.
class MigrationRunner {
  /// Tüm migration'lar, versiyon sırasına göre.
  /// YENİ MIGRATION EKLERKEN SADECE BURAYA EKLE.
  static final List<Migration> _all = [
    MigrationV1Initial(),
    MigrationV2CariOdemeler(),
    MigrationV3CariFiyatlar(),
    MigrationV4Indexler(),
    MigrationV5TeraziCihazlari(),
    MigrationV6IslemGecmisi(),
    MigrationV7CariDurumVade(),
    MigrationV8SutGunlukTekil(),
    MigrationV9Donemler(),
  ]..sort((a, b) => a.version.compareTo(b.version));

  /// Bu örneğin uygulayacağı migration listesi. Uygulamada daima [_all];
  /// testlerde hatalı bir migration enjekte etmek için değiştirilebilir.
  final List<Migration> _liste;

  MigrationRunner({@visibleForTesting List<Migration>? migrations})
      : _liste = migrations ?? _all;

  /// Şu anki en güncel şema versiyonu (uygulamanın "hedef" versiyonu).
  static int get targetVersion =>
      _all.isEmpty ? 0 : _all.map((m) => m.version).reduce((a, b) => a > b ? a : b);

  Future<int> currentVersion(Database db) async {
    final result = await db.rawQuery('PRAGMA user_version');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Bekleyen tüm migration'ları sırayla uygular.
  /// Dönen değer: kaç migration'ın uygulandığı.
  Future<int> run(Database db) async {
    await _ensureMigrationLogTable(db);

    final current = await currentVersion(db);
    final pending = _liste.where((m) => m.version > current).toList()
      ..sort((a, b) => a.version.compareTo(b.version));

    if (pending.isEmpty) {
      if (kDebugMode) {
        debugPrint('[MigrationRunner] Güncel — şema v$current, yapılacak migration yok.');
      }
      return 0;
    }

    var applied = 0;
    for (final migration in pending) {
      final started = DateTime.now();
      try {
        await db.transaction((txn) async {
          // KRİTİK: `db` değil `txn` geçilir — aksi halde aynı bağlantı
          // üzerinde açık transaction varken dışarıdaki `db` kullanılırsa
          // sqflite kilitlenir (bkz. migration.dart'taki açıklama).
          await migration.up(txn);
          await txn.rawUpdate('PRAGMA user_version = ${migration.version}');
        });

        await _logMigration(db, migration, started, success: true);
        applied++;

        if (kDebugMode) {
          debugPrint('[MigrationRunner] ✓ v${migration.version} uygulandı: ${migration.description}');
        }
      } catch (e, stack) {
        await _logMigration(db, migration, started, success: false, error: e.toString());
        if (kDebugMode) {
          debugPrint('[MigrationRunner] ✗ v${migration.version} BAŞARISIZ: $e\n$stack');
        }
        // Versiyon ilerletilmediği için bir sonraki açılışta bu
        // migration'dan tekrar denenir. Zincir burada durur.
        rethrow;
      }
    }
    return applied;
  }

  Future<void> _ensureMigrationLogTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS _migration_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        version INTEGER NOT NULL,
        description TEXT NOT NULL,
        basari INTEGER NOT NULL,
        hata TEXT,
        baslangic TEXT NOT NULL,
        bitis TEXT NOT NULL
      )
    ''');
  }

  Future<void> _logMigration(
    Database db,
    Migration migration,
    DateTime started, {
    required bool success,
    String? error,
  }) async {
    try {
      await db.insert('_migration_log', {
        'version': migration.version,
        'description': migration.description,
        'basari': success ? 1 : 0,
        'hata': error,
        'baslangic': started.toIso8601String(),
        'bitis': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      // Günlük kaydı asla ana akışı bozmamalı.
    }
  }

  /// Geliştirme/teşhis amaçlı: uygulanmış tüm migration kayıtlarını döner.
  Future<List<Map<String, Object?>>> history(Database db) async {
    await _ensureMigrationLogTable(db);
    return db.query('_migration_log', orderBy: 'id ASC');
  }
}
