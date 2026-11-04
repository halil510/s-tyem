import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sutyem_pro/core/database/migrations/migration_runner.dart';

import '../helpers/test_db.dart';

/// Genel kural: yerel SQLite şemasına eklenen her tablo ve sütun
/// `supabase/supabase_sema.sql` dosyasında da bulunmalı. Yeni bir
/// migration yazılıp SQL dosyası güncellenmezse bu test kırılır.
void main() {
  /// Buluta taşınmayan, cihaza özel teknik tablolar.
  const buluttaOlmayan = {'_migration_log', 'sqlite_sequence', 'android_metadata'};

  late String sql;

  setUpAll(() {
    sql = File('supabase/supabase_sema.sql').readAsStringSync().toLowerCase();
  });

  /// `create table ... public.<tablo> ( ... );` bloğunun gövdesi.
  String? tabloGovdesi(String tablo) {
    final m = RegExp(
      'create table if not exists public\\.$tablo \\((.*?)\\n\\);',
      dotAll: true,
    ).firstMatch(sql);
    return m?.group(1);
  }

  test('her yerel tablo ve sütun Supabase SQL dosyasında var', () async {
    final db = await testVeritabaniAc();
    addTearDown(db.close);

    final tablolar = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    );
    final eksikler = <String>[];

    for (final t in tablolar) {
      final tablo = t['name']! as String;
      if (buluttaOlmayan.contains(tablo)) continue;

      final govde = tabloGovdesi(tablo);
      if (govde == null) {
        eksikler.add('tablo: $tablo');
        continue;
      }
      final sutunlar = await db.rawQuery('PRAGMA table_info($tablo)');
      for (final s in sutunlar) {
        final ad = s['name']! as String;
        if (!RegExp('^\\s*$ad\\s', multiLine: true).hasMatch(govde)) {
          eksikler.add('sütun: $tablo.$ad');
        }
      }
    }

    expect(eksikler, isEmpty,
        reason: 'supabase/supabase_sema.sql güncellenmeli: $eksikler');
  });

  test('SQL dosyası güncel yerel şema sürümünü belirtiyor', () {
    expect(
      sql,
      contains('yerel şema sürümü: v${MigrationRunner.targetVersion}'),
      reason: 'Yeni migration eklendi; SQL dosyasının başlığındaki sürümü '
          've DEĞİŞİKLİK GEÇMİŞİ bölümünü güncelle.',
    );
  });
}
