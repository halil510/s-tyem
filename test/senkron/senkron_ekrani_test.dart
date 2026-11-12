import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/core/providers/database_provider.dart';
import 'package:sutyem_pro/senkron/senkron_ekrani.dart';
import 'package:sutyem_pro/senkron/senkron_yoneticisi.dart';

import '../helpers/test_db.dart';

void main() {
  tearDown(() async {
    SenkronYoneticisi.testCihaz = null;
    await SenkronYoneticisi().testSifirla();
  });

  testWidgets('Çoklu Cihaz ve Bulut ekranı 360 px telefonda hatasız açılır; bulut formu ve yerel ağ seçenekleri görünür', (t) async {
    t.view.physicalSize = const Size(360, 740);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    late Database db;
    await t.runAsync(() async => db = await testVeritabaniAc());
    SenkronYoneticisi.testCihaz = 'cihaz-test';
    await t.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWith((ref) => db)],
      child: const MaterialApp(
        locale: Locale('tr', 'TR'),
        supportedLocales: [Locale('tr', 'TR')],
        localizationsDelegates: [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
        home: SenkronEkrani(),
      ),
    ));
    for (var i = 0; i < 20; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('bulutUrl')), findsOneWidget);
    expect(find.text('SQL\'i kopyala'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Ana cihaz'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Bağlı'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
