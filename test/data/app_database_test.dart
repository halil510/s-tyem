import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/core/database/app_database.dart';
import 'package:sutyem_pro/core/database/migrations/migration.dart';
import 'package:sutyem_pro/core/database/migrations/migration_runner.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v1_initial.dart';

/// Bir sonraki sürüme geçerken hata veren sahte migration.
class _HataliMigration extends Migration {
  @override
  int get version => 99;
  @override
  String get description => 'test: bilerek hata verir';
  @override
  Future<void> up(DatabaseExecutor db) async {
    await db.execute('CREATE TABLE yarim_kalan (id INTEGER)');
    throw StateError('migration patladı');
  }
}

/// Dosya açılışına AppDatabase'i gerçek dosya sistemi üzerinde dener.
void main() {
  late Directory klasor;
  late String dbYolu;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    klasor = await Directory.systemTemp.createTemp('sutyem_db_test_');
    dbYolu = p.join(klasor.path, AppDatabase.dbAdi);
  });

  tearDown(() async {
    try {
      await klasor.delete(recursive: true);
    } catch (_) {}
  });

  AppDatabase ac({MigrationRunner? runner}) => AppDatabase.test(
        factory: databaseFactoryFfi,
        klasor: klasor.path,
        migrationRunner: runner,
      );

  List<String> bozukYedekler() => klasor
      .listSync()
      .map((f) => p.basename(f.path))
      .where((ad) => ad.startsWith('sut_yem_bozuk_'))
      .toList();

  test('normal açılış: şema güncel, yabancı anahtarlar açık', () async {
    final app = ac();
    final db = await app.database;
    final surum = Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version'));
    expect(surum, MigrationRunner.targetVersion);
    final fk = Sqflite.firstIntValue(await db.rawQuery('PRAGMA foreign_keys'));
    expect(fk, 1);
    expect(app.kurtarmaYedegi, isNull);
    await app.close();
  });

  test('aynı anda gelen çağrılar tek bağlantıyı paylaşır', () async {
    final app = ac();
    final sonuc = await Future.wait([app.database, app.database, app.database]);
    expect(identical(sonuc[0], sonuc[1]) && identical(sonuc[1], sonuc[2]), isTrue);
    await app.close();
  });

  test('migration hatası veritabanını SİLMEZ, veriler yerinde kalır', () async {
    // 1) Gerçek verili bir veritabanı (sadece v1).
    final ilk = ac(runner: MigrationRunner(migrations: [MigrationV1Initial()]));
    final db1 = await ilk.database;
    await db1.insert('cariler', {'ad': 'Ayşe', 'soyad': 'Demir'});
    await db1.insert('sutler', {'cari_id': 1, 'tarih': '2026-11-01', 'sabah': 12.5, 'toplam': 12.5});
    await ilk.close();

    // 2) Bir sonraki migration hata veriyor.
    final ikinci = ac(
      runner: MigrationRunner(migrations: [MigrationV1Initial(), _HataliMigration()]),
    );
    await expectLater(
      ikinci.database,
      throwsA(isA<VeritabaniGuncellemeHatasi>()
          .having((e) => e.mevcutSurum, 'mevcutSurum', 1)),
    );
    expect(ikinci.kurtarmaYedegi, isNull);
    expect(bozukYedekler(), isEmpty, reason: 'dosya kenara alınmamalı');

    // 3) Dosya yerinde, veri tam, yarım kalan migration geri alınmış.
    final kontrol = await databaseFactoryFfi.openDatabase(dbYolu);
    expect(await kontrol.query('cariler'), hasLength(1));
    final sut = await kontrol.query('sutler');
    expect(sut.single['sabah'], 12.5);
    expect(Sqflite.firstIntValue(await kontrol.rawQuery('PRAGMA user_version')), 1);
    final yarim = await kontrol.rawQuery(
        "SELECT name FROM sqlite_master WHERE name='yarim_kalan'");
    expect(yarim, isEmpty);
    await kontrol.close();
  });

  test('hatadan sonra tekrar denenince açılabilir', () async {
    final hatali = ac(
      runner: MigrationRunner(migrations: [MigrationV1Initial(), _HataliMigration()]),
    );
    await expectLater(hatali.database, throwsA(isA<VeritabaniGuncellemeHatasi>()));

    final duzgun = ac();
    final db = await duzgun.database;
    expect(db.isOpen, isTrue);
    await duzgun.close();
  });

  test('bozuk dosya silinmez, kenara alınır ve kullanıcıya bildirilir', () async {
    final cop = List<int>.generate(8192, (i) => (i * 7 + 13) % 256);
    await File(dbYolu).writeAsBytes(cop);

    final app = ac();
    final db = await app.database;

    // Yeni, boş ve güncel veritabanı.
    expect(await db.query('cariler'), isEmpty);
    expect(app.kurtarmaYedegi, isNotNull);

    // Eski dosya bayt bayt korunmuş.
    final yedek = File(app.kurtarmaYedegi!);
    expect(await yedek.exists(), isTrue);
    expect(await yedek.readAsBytes(), cop);
    expect(bozukYedekler(), hasLength(1));

    app.kurtarmaBildirildi();
    expect(app.kurtarmaYedegi, isNull);
    await app.close();
  });

  test('bozulma dışındaki hatalar bozulma sayılmaz', () {
    expect(AppDatabase.bozulmaHatasiMi(StateError('x')), isFalse);
    expect(AppDatabase.bozulmaHatasiMi(const FileSystemException('disk dolu')), isFalse);
  });
}
