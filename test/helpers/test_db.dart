import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/core/database/migrations/migration_runner.dart';
import 'package:sutyem_pro/core/providers/database_provider.dart';

/// Her test için izole, bellek-içi (in-memory) ve migration'ları
/// uygulanmış bir veritabanı açar. Gerçek uygulamadaki gibi yabancı
/// anahtar (foreign key) denetimi açıktır.
Future<Database> testVeritabaniAc({bool migrationCalistir = true}) async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      singleInstance: false,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    ),
  );
  if (migrationCalistir) await MigrationRunner().run(db);
  return db;
}

/// Uygulamadaki tüm provider'ları verilen test veritabanına bağlayan
/// bir [ProviderContainer].
ProviderContainer testContainer(Database db) {
  return ProviderContainer(overrides: [
    databaseProvider.overrideWith((ref) => db),
  ]);
}

/// Test verisi: cari ekler, id'sini döner.
Future<int> cariEkle(Database db, {String ad = 'Ali', String soyad = 'Yılmaz'}) =>
    db.insert('cariler', {'ad': ad, 'soyad': soyad});

/// Test verisi: bir cari için bir ayın fiyatlarını tanımlar.
Future<void> fiyatTanimla(
  Database db,
  int cariId,
  String ay, {
  double sut = 0,
  double sutYemi = 0,
  double besiYemi = 0,
}) =>
    db.insert('cari_fiyatlar', {
      'cari_id': cariId,
      'ay': ay,
      'sut_fiyat': sut,
      'sut_yemi_fiyat': sutYemi,
      'besi_yemi_fiyat': besiYemi,
    });
