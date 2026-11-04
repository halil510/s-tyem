import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/core/database/migrations/migration_runner.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v1_initial.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v2_cari_odemeler.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v3_cari_fiyatlar.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v4_indexler.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v5_terazi_cihazlari.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v6_islem_gecmisi.dart';
import 'package:sutyem_pro/core/database/migrations/migration_v7_cari_durum_vade.dart';

import '../helpers/test_db.dart';

/// Uygulamanın önceki sürümündeki (şema v7) bir veritabanını kurar.
Future<Database> v7Veritabani() async {
  final db = await testVeritabaniAc(migrationCalistir: false);
  for (final m in [
    MigrationV1Initial(),
    MigrationV2CariOdemeler(),
    MigrationV3CariFiyatlar(),
    MigrationV4Indexler(),
    MigrationV5TeraziCihazlari(),
    MigrationV6IslemGecmisi(),
    MigrationV7CariDurumVade(),
  ]) {
    await m.up(db);
  }
  await db.execute('PRAGMA user_version = 7');
  return db;
}

void main() {
  test('boş veritabanı en güncel şemaya kurulur', () async {
    final db = await testVeritabaniAc();
    final surum = Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version'));
    expect(surum, MigrationRunner.targetVersion);
    expect(MigrationRunner.targetVersion, 10);

    // İkinci çalıştırma hiçbir şey yapmamalı (idempotent).
    expect(await MigrationRunner().run(db), 0);
  });

  group('v8: süt günlük tekil', () {
    late Database db;
    late int cari;

    setUp(() async {
      db = await v7Veritabani();
      cari = await cariEkle(db);
    });

    test('aynı güne girilmiş mükerrer kayıtlar TOPLANARAK birleştirilir', () async {
      // Eski sürümün ürettiği durum: sabah ve akşam ayrı satırlarda.
      await db.insert('sutler', {'cari_id': cari, 'tarih': '2026-03-10', 'sabah': 20, 'aksam': 0, 'toplam': 20});
      await db.insert('sutler', {'cari_id': cari, 'tarih': '2026-03-10', 'sabah': 0, 'aksam': 18.5, 'toplam': 18.5});
      await db.insert('sutler', {'cari_id': cari, 'tarih': '2026-03-11', 'sabah': 21, 'aksam': 19, 'toplam': 40});

      await MigrationRunner().run(db);

      final satirlar = await db.query('sutler', orderBy: 'tarih');
      expect(satirlar, hasLength(2));
      expect(satirlar[0]['sabah'], 20);
      expect(satirlar[0]['aksam'], 18.5);
      expect(satirlar[0]['toplam'], 38.5);
      expect(satirlar[1]['toplam'], 40);

      // Toplam kg (dolayısıyla carinin alacağı) DEĞİŞMEMELİ.
      final toplam = Sqflite.firstIntValue(await db.rawQuery('SELECT CAST(SUM(toplam) * 10 AS INT) FROM sutler'));
      expect(toplam, 785);
    });

    test('silinen mükerrer satır denetim günlüğüne yazılır', () async {
      await db.insert('sutler', {'cari_id': cari, 'tarih': '2026-03-10', 'sabah': 20, 'toplam': 20});
      final ikinciId = await db.insert('sutler', {'cari_id': cari, 'tarih': '2026-03-10', 'aksam': 18, 'toplam': 18});

      await MigrationRunner().run(db);

      final gunluk = await db.query('islem_gecmisi', where: "tablo_adi = 'sutler'");
      expect(gunluk, hasLength(1));
      expect(gunluk.first['kayit_id'], ikinciId);
      expect(gunluk.first['islem'], 'birlestir');
      expect(jsonDecode(gunluk.first['onceki_deger'] as String)['aksam'], 18);
    });

    test('saatli tarihler gün biçimine normalize edilir', () async {
      await db.insert('sutler', {'cari_id': cari, 'tarih': '2026-03-31T08:15:00.000', 'sabah': 10, 'toplam': 10});
      await db.insert('cari_odemeler', {
        'cari_id': cari, 'tarih': '2026-03-31T09:00:00', 'islem_turu': 'odeme',
        'miktar': 1, 'birim_fiyat': 50, 'toplam_tutar': 50,
      });

      await MigrationRunner().run(db);

      expect((await db.query('sutler')).single['tarih'], '2026-03-31');
      expect((await db.query('cari_odemeler')).single['tarih'], '2026-03-31');
      // Ay sonu sorgusu artık bu kaydı kaçırmıyor.
      final aySonu = await db.query('sutler', where: "tarih BETWEEN '2026-03-01' AND '2026-03-31'");
      expect(aySonu, hasLength(1));
    });

    test('migration sonrası aynı güne ikinci kayıt veritabanı seviyesinde reddedilir', () async {
      await MigrationRunner().run(db);
      await db.insert('sutler', {'cari_id': cari, 'tarih': '2026-03-10', 'sabah': 5, 'toplam': 5});
      expect(
        () => db.insert('sutler', {'cari_id': cari, 'tarih': '2026-03-10', 'sabah': 6, 'toplam': 6}),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('farklı carilerin aynı günkü kayıtlarına dokunulmaz', () async {
      final cari2 = await cariEkle(db, ad: 'Veli');
      await db.insert('sutler', {'cari_id': cari, 'tarih': '2026-03-10', 'sabah': 5, 'toplam': 5});
      await db.insert('sutler', {'cari_id': cari2, 'tarih': '2026-03-10', 'sabah': 7, 'toplam': 7});

      await MigrationRunner().run(db);

      expect(await db.query('sutler'), hasLength(2));
    });
  });
}
