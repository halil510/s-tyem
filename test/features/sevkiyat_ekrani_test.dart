import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/core/providers/database_provider.dart';
import 'package:sutyem_pro/features/fabrika/sevkiyat_ekrani.dart';
import 'package:sutyem_pro/utils/tarih_format.dart';

import '../helpers/test_db.dart';

/// TANK & FABRİKA SEVKİYATI ekran akışı (gerçek ekran + gerçek veritabanı).
void main() {
  late Database db;

  setUpAll(initializeTurkishLocale);

  Widget uygulama(Widget ekran) => ProviderScope(
        overrides: [databaseProvider.overrideWith((ref) => db)],
        child: MaterialApp(
          locale: const Locale('tr', 'TR'),
          supportedLocales: const [Locale('tr', 'TR')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: ekran,
        ),
      );

  Future<void> bekle(WidgetTester tester, [int tur = 30]) async {
    for (var i = 0; i < tur; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
  }

  Future<int> say(WidgetTester tester, String t) async =>
      (await tester.runAsync(() => db.rawQuery('SELECT COUNT(*) AS n FROM $t')))!.first['n'] as int;

  testWidgets('fabrika yokken "Sevkiyat ekle" önce fabrikayı ister; hatalı kg kaydedilmez; doğru kayıt yazılır ve listelenir',
      (tester) async {
    db = (await tester.runAsync(() => testVeritabaniAc()))!;
    await tester.binding.setSurfaceSize(const Size(360, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(uygulama(const SevkiyatEkrani(baslangicSekmesi: 1)));
    await bekle(tester);
    expect(find.textContaining('Henüz fabrika yok'), findsOneWidget);

    await tester.tap(find.text('Sevkiyat ekle'));
    await bekle(tester);
    expect(find.text('Yeni Fabrika'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Fabrika adı'), 'Pınar Süt');
    await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
    await bekle(tester);

    // Sevkiyat penceresi: hatalı kg → hata, kayıt yok.
    expect(find.text('Fabrikaya Sevkiyat'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Sevk edilen (kg)'), '12,5x');
    await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
    await bekle(tester, 10);
    expect(find.textContaining('Sevk miktarı geçersiz'), findsOneWidget);
    expect(await say(tester, 'sevkiyatlar'), 0);

    await tester.enterText(find.widgetWithText(TextField, 'Sevk edilen (kg)'), '1250,5');
    await tester.enterText(find.widgetWithText(TextField, 'Fabrika fiyatı (₺/kg)'), '18,75');
    await tester.pump();
    expect(find.textContaining('23.446,88'), findsOneWidget, reason: '1250,5 × 18,75 = 23.446,875 → 23.446,88 ₺');
    await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
    await bekle(tester);

    expect(find.text('Fabrikaya Sevkiyat'), findsNothing, reason: 'pencere kapanır');
    expect(await say(tester, 'sevkiyatlar'), 1);
    final s = (await tester.runAsync(() => db.query('sevkiyatlar')))!.single;
    expect(s['kg'], 1250.5);
    expect(s['birim_fiyat'], 18.75);
    expect(find.textContaining('1.250,5 kg'), findsWidgets, reason: 'listede görünür');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => db.close());
  });
}

