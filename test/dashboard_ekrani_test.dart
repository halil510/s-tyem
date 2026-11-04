import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/core/providers/database_provider.dart';
import 'package:sutyem_pro/ekranlar/dashboard_ekrani.dart';
import 'package:sutyem_pro/utils/tarih_format.dart';

import 'helpers/test_db.dart';

/// Özet ekranı telefon genişliğinde taşmadan çizilir ve yeni bölümleri gösterir.
void main() {
  setUpAll(initializeTurkishLocale);

  testWidgets('360 px genişlikte: gelmeyenler ve dönem hatırlatması', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DateTime.now();
    final f = DateFormat('yyyy-MM-dd');
    String gun(int geri) => f.format(DateTime(n.year, n.month, n.day - geri));
    final gecenAy = DateFormat('yyyy-MM').format(DateTime(n.year, n.month - 1));

    late Database db;
    await tester.runAsync(() async {
      db = await testVeritabaniAc();
      final ali = await cariEkle(db, ad: 'Ali', soyad: 'Kaya');
      final can = await cariEkle(db, ad: 'Can', soyad: 'Uzunisimlioğulları Büyükçekmeceli');
      await db.insert('sutler', {'cari_id': ali, 'tarih': gun(0), 'sabah': 1234.5, 'aksam': 1100, 'toplam': 2334.5});
      await db.insert('sutler', {'cari_id': can, 'tarih': gun(1), 'sabah': 12, 'toplam': 12});
      await db.insert('sutler', {'cari_id': can, 'tarih': '$gecenAy-05', 'sabah': 3, 'toplam': 3});
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWith((ref) => db)],
      child: const MaterialApp(
        locale: Locale('tr', 'TR'),
        supportedLocales: [Locale('tr', 'TR')],
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: DashboardEkrani()),
      ),
    ));
    for (var i = 0; i < 100 && find.textContaining('GELMEYENLER').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }

    expect(find.text('BUGÜN GELMEYENLER (1)'), findsOneWidget);
    expect(find.textContaining('Uzunisimlioğulları'), findsWidgets);
    expect(find.textContaining('dönemi henüz kapatılmadı'), findsOneWidget);
    expect(find.textContaining('Sabah 1.234,5 kg'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Grafik animasyonu zamanlayıcıları bitsin.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));

    await tester.runAsync(() => db.close());
  });
}
