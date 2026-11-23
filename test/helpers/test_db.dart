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
}) async {
  await db.insert('cari_fiyatlar', {'cari_id': cariId, 'ay': ay, 'sut_fiyat': sut});
  // v16: yem fiyatları ürün fiyatı tablosunda (0 = tanımlanmadı, yazılmaz).
  if (sutYemi != 0) await urunFiyatiTanimla(db, cariId, urunSutYemi, ay, sutYemi);
  if (besiYemi != 0) await urunFiyatiTanimla(db, cariId, urunBesiYemi, ay, besiYemi);
}

/// v16: yeni veritabanında eski 6 yem türü bu sırayla ürün olarak eklenir (id 1..6).
const urunSutYemi = 1, urunBesiYemi = 2, urunBBaslangic = 3, urunBBuyutme = 4, urunKuzuYemi = 5, urunTavukYemi = 6;

/// Test verisi: bir cariye bir ürünün fiyatını tanımlar ([ay]: 'yyyy-MM' ya da 'yyyy-MM-dd').
Future<void> urunFiyatiTanimla(Database db, int cariId, int urunId, String ay, double fiyat) async {
  final n = await db.update('cari_urun_fiyatlari', {'fiyat': fiyat},
      where: 'cari_id = ? AND urun_id = ? AND ay = ?', whereArgs: [cariId, urunId, ay]);
  if (n == 0) await db.insert('cari_urun_fiyatlari', {'cari_id': cariId, 'urun_id': urunId, 'ay': ay, 'fiyat': fiyat});
}

/// Test verisi: yem satırı (tek ürün + miktar). Dönen: satır id'si.
Future<int> yemSatiriEkle(Database db, int cariId, String tarih, double miktar, {int urunId = urunSutYemi}) =>
    db.insert('yemler', {'cari_id': cariId, 'tarih': tarih, 'urun_id': urunId, 'miktar': miktar, 'toplam': miktar});
