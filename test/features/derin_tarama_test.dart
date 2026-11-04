import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/core/providers/database_provider.dart';
import 'package:sutyem_pro/data/repositories/cari_repository.dart';
import 'package:sutyem_pro/ekranlar/cari_ekle.dart';
import 'package:sutyem_pro/ekranlar/detay/kayit_duzenle_dialoglari.dart';
import 'package:sutyem_pro/models/sut_model.dart';
import 'package:sutyem_pro/utils/tarih_format.dart';
import 'package:sutyem_pro/utils/turkce.dart';

import '../helpers/test_db.dart';

/// 2026-11-05 tüm ekran taramasında bulunan hataların regresyon testleri.
void main() {
  setUpAll(initializeTurkishLocale);

  Widget uygulama(Database db, Widget ekran) => ProviderScope(
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

  Future<void> bekle(WidgetTester tester, bool Function() kosul, String neyi) async {
    for (var i = 0; i < 150; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      if (kosul()) return;
    }
    fail('Zaman aşımı: $neyi');
  }

  group('Türkçe sıralama', () {
    test('Ç, Ş, Ö, Ü, İ, I kendi yerinde (Z\'den sonra değil)', () {
      final adlar = ['ZEKİ', 'ÇETİN', 'CEM', 'ŞÜKRÜ', 'SAMİ', 'ÖMER', 'OSMAN', 'ÜMİT', 'UĞUR', 'İSMAİL', 'IŞIK', 'HASAN', 'DERYA']
        ..sort(turkceKarsilastir);
      expect(adlar, ['CEM', 'ÇETİN', 'DERYA', 'HASAN', 'IŞIK', 'İSMAİL', 'OSMAN', 'ÖMER', 'SAMİ', 'ŞÜKRÜ', 'UĞUR', 'ÜMİT', 'ZEKİ']);
    });

    test('küçük/büyük harf farkı sırayı bozmaz; önek kısa olan önce', () {
      expect(turkceKarsilastir('ali', 'ALİ'), 0);
      expect(turkceKarsilastir('ALİ', 'ALİCAN'), lessThan(0));
    });

    test('Cariler listesi (repository) Türk alfabesiyle gelir, ad eşitse soyada bakılır', () async {
      final db = await testVeritabaniAc();
      for (final (ad, soyad) in [('ZEKİ', 'A'), ('ÇETİN', 'B'), ('ALİ', 'ŞEN'), ('ALİ', 'SARI'), ('ÖMER', 'C')]) {
        await cariEkle(db, ad: ad, soyad: soyad);
      }
      final liste = await CariRepository(db).getAll();
      expect(liste.map((c) => c.tamAd), ['ALİ SARI', 'ALİ ŞEN', 'ÇETİN B', 'ÖMER C', 'ZEKİ A']);
      await db.close();
    });
  });

  testWidgets('Cari Ekle: aynı ad-soyad varsa sorar; "Vazgeç" eklemez, "Yine de Ekle" ekler', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late Database db;
    await tester.runAsync(() async {
      db = await testVeritabaniAc();
      await cariEkle(db, ad: 'AHMET', soyad: 'ALMAÇ');
    });
    Future<int> sayi() async => (await tester.runAsync(() => db.query('cariler')))!.length;

    await tester.pumpWidget(uygulama(db, const CariEkle()));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextFormField, 'Ad'), 'ahmet'); // küçük harfle de yakalanır
    await tester.enterText(find.widgetWithText(TextFormField, 'Soyad'), 'almaç ');
    await tester.ensureVisible(find.text('Cari Kaydet'));
    await tester.tap(find.text('Cari Kaydet'));
    await bekle(tester, () => find.text('Aynı isimde cari var').evaluate().isNotEmpty, 'uyarı');

    await tester.tap(find.text('Vazgeç'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(await sayi(), 1);
    expect(find.text('Cari Kaydet'), findsOneWidget, reason: 'düğme yeniden kullanılabilir');

    await tester.tap(find.text('Cari Kaydet'));
    await bekle(tester, () => find.text('Aynı isimde cari var').evaluate().isNotEmpty, 'uyarı 2');
    await tester.tap(find.text('Yine de Ekle'));
    for (var i = 0; i < 100 && await sayi() < 2; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(await sayi(), 2);
    await tester.pump(const Duration(seconds: 5));
    await tester.runAsync(() => db.close());
  });

  testWidgets('Süt düzenle: sabah ve akşam 0 yapılırsa kayıt silinir (0 kg satır kalmaz)', (tester) async {
    late Database db;
    late int id;
    await tester.runAsync(() async {
      db = await testVeritabaniAc();
      final ali = await cariEkle(db);
      id = await db.insert('sutler', {'cari_id': ali, 'tarih': '2026-11-03', 'sabah': 12, 'aksam': 8, 'toplam': 20});
    });
    final sut = Sut(id: id, cariId: 1, tarih: '2026-11-03', sabah: 12, aksam: 8);

    await tester.pumpWidget(uygulama(
      db,
      Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<bool>(context: ctx, builder: (_) => SutDuzenleDialog(sut: sut)),
            child: const Text('Aç'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Aç'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Sabah (kg)'), '0');
    await tester.enterText(find.widgetWithText(TextField, 'Akşam (kg)'), '');
    await tester.tap(find.text('Kaydet'));
    await bekle(tester, () => find.text('Miktar 0').evaluate().isNotEmpty, 'silme onayı');
    await tester.tap(find.text('Sil'));
    for (var i = 0; i < 100 && (await tester.runAsync(() => db.query('sutler')))!.isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(await tester.runAsync(() => db.query('sutler')), isEmpty);
    await tester.runAsync(() => db.close());
  });
}
