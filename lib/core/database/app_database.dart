import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'migrations/migration_runner.dart';

/// ─────────────────────────────────────────────────────────────
/// APP DATABASE
/// ─────────────────────────────────────────────────────────────
///
/// Eski `DBHelper` sınıfının yerini alır. Sorumlulukları:
/// - Veritabanı dosyasını açmak (bozuksa yedekleyip sıfırdan kurmak)
/// - [MigrationRunner] ile şemayı güncel tutmak
/// - Ham [Database] nesnesini repository katmanına sunmak
///
/// NOT: Bu sınıf artık CRUD metodları içermez — CRUD işlemleri
/// `lib/data/repositories/` altındaki repository sınıflarına taşındı.
/// Bu ayrım (separation of concerns) test edilebilirliği ve bakımı
/// kolaylaştırır.
class AppDatabase {
  AppDatabase._internal();
  static final AppDatabase instance = AppDatabase._internal();

  static const String _dbName = 'sut_yem.db';
  Database? _database;
  final MigrationRunner _migrationRunner = MigrationRunner();

  Future<Database> get database async {
    _database ??= await _open();
    return _database!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    try {
      await Directory(dbPath).create(recursive: true);
    } catch (_) {
      // Dizin zaten var olabilir; yok sayılabilir.
    }

    try {
      final db = await _openAndMigrate(path);
      // Hızlı sağlık kontrolü — dosya açılabiliyor mu, sorgu çalışıyor mu?
      await db.rawQuery('SELECT name FROM sqlite_master WHERE type="table" LIMIT 1');
      return db;
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('[AppDatabase] Açılış hatası, yedekleyip sıfırdan kuruluyor: $e\n$stack');
      }
      return _recoverCorrupted(path, dbPath);
    }
  }

  Future<Database> _openAndMigrate(String path) async {
    final db = await openDatabase(
      path,
      // Versiyon yönetimini sqflite'ın onCreate/onUpgrade'ine değil,
      // kendi MigrationRunner'ımıza bırakıyoruz — bu yüzden burada
      // version belirtmiyoruz (varsayılan sürüm 1, gerçek şema
      // kontrolü PRAGMA user_version üzerinden MigrationRunner'da).
      onOpen: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
    await _migrationRunner.run(db);
    return db;
  }

  Future<Database> _recoverCorrupted(String path, String dbDir) async {
    try {
      final backupPath = join(dbDir, 'sut_yem_backup_${DateTime.now().millisecondsSinceEpoch}.db');
      final file = File(path);
      if (await file.exists()) {
        await file.copy(backupPath);
        await file.delete();
      }
    } catch (_) {
      // Yedekleme başarısız olsa bile sıfırdan kurmayı dene.
    }
    return _openAndMigrate(path);
  }

  /// Uygulanan migration geçmişini döner (ayarlar/teşhis ekranında
  /// gösterilebilir).
  Future<List<Map<String, Object?>>> migrationHistory() async {
    final db = await database;
    return _migrationRunner.history(db);
  }

  int get schemaVersion => MigrationRunner.targetVersion;

  Future<void> close() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }
  }
}
