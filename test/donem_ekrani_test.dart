import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/core/providers/database_provider.dart';
import 'package:sutyem_pro/features/donem/donem_ekrani.dart';
import 'package:sutyem_pro/utils/tarih_format.dart';

import 'helpers/test_db.dart';

/// Dönem Kapanışı ekranı: kullanıcı gibi geçen ayı kapatır ve yeniden açar.
Future<void> _bekle(WidgetTester tester, bool Function() kosul, {String? aciklama}) async {
  for (var i = 0; i < 150; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    if (kosul()) return;
  }
  fail('Zaman aşımı: ${aciklama ?? 'koşul sağlanmadı'}');
}

Widget _uygulama(Database db) => ProviderScope(
      overrides: [databaseProvider.overrideWith((ref) => db)],
      child: const MaterialApp(
        locale: Locale('tr', 'TR'),
        supportedLocales: [Locale('tr', 'TR')],
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: DonemEkrani(),
      ),
    );

void main() {
  setUpAll(initializeTurkishLocale);

  testWidgets('geçen ay kapatılır, kilitlenir ve gerekçeyle yeniden açılır', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final n = DateTime.now();
    final gecen = DateTime(n.year, n.month - 1);
    final ay = '${gecen.year}-${gecen.month.toString().padLeft(2, '0')}';
    late Database db;
    await tester.runAsync(() async {
      db = await testVeritabaniAc();
      final ali = await cariEkle(db, ad: 'Ali', soyad: 'Kaya');
      await fiyatTanimla(db, ali, ay, sut: 20);
      await db.insert('sutler', {'cari_id': ali, 'tarih': '$ay-10', 'sabah': 50, 'toplam': 50});
    });

    await tester.pumpWidget(_uygulama(db));
    await _bekle(tester, () => find.text('AÇIK DÖNEM').evaluate().isNotEmpty, aciklama: 'açık dönem');
    expect(find.text('Ali Kaya'), findsOneWidget);
    expect(find.textContaining('1.000,00'), findsWidgets); // 50 kg × 20 ₺

    await tester.tap(find.widgetWithText(FilledButton, 'Dönemi Kapat'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Dönemi Kapat').last); // onay diyaloğu
    await _bekle(tester, () => find.text('KAPALI DÖNEM').evaluate().isNotEmpty, aciklama: 'kapandı');

    final durum = await tester.runAsync(() => db.query('donemler'));
    expect(durum!.single['durum'], 'kapali');

    // Yeniden aç: gerekçesiz olmaz.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Dönemi Yeniden Aç'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Yeniden Aç'));
    await tester.pump();
    expect(find.text('Neden açtığınızı kısaca yazın'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Sabah sütü yanlış');
    await tester.tap(find.widgetWithText(FilledButton, 'Yeniden Aç'));
    await _bekle(tester, () => find.text('AÇIK DÖNEM').evaluate().isNotEmpty, aciklama: 'yeniden açıldı');

    await tester.runAsync(() => db.close());
  });
}
