import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';

/// Veritabanı bağlantısını (migration'lar tamamlanmış halde) sağlayan
/// tekil (singleton) provider. Uygulama genelinde tüm repository'ler
/// bu provider üzerinden aynı [Database] örneğine erişir.
final appDatabaseProvider = Provider<AppDatabase>((ref) => AppDatabase.instance);

/// Açılmış ve migration'ları tamamlanmış [Database] nesnesi.
/// Ekranlar bunu doğrudan kullanmaz — repository provider'ları üzerinden
/// erişilir. `main.dart` içindeki splash ekranı bu provider'ı bekleyerek
/// veritabanının hazır olduğundan emin olur.
final databaseProvider = FutureProvider<Database>((ref) async {
  final appDb = ref.watch(appDatabaseProvider);
  return appDb.database;
});
