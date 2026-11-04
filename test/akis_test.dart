import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/core/providers/database_provider.dart';
import 'package:sutyem_pro/core/providers/veri_surumu_provider.dart';
import 'package:sutyem_pro/ekranlar/ana_ekran.dart';
import 'package:sutyem_pro/features/terazi/providers/terazi_providers.dart';
import 'package:sutyem_pro/features/terazi/services/terazi_baglanti_durumu.dart';
import 'package:sutyem_pro/utils/tarih_format.dart';

import 'helpers/test_db.dart';

/// Uygulama içi akışlar: sekmeler arası geçişte ekranlar güncel veriyi göstermeli.
class _SahteTerazi extends TeraziBaglantiNotifier {
  @override
  Future<bool> baslangicOtomatikBaglan() async => false;
}

Future<void> bekle(WidgetTester tester, bool Function() kosul, String neyi) async {
  for (var i = 0; i < 150; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    if (kosul()) return;
  }
  fail('Zaman aşımı: $neyi');
}

bool gorunur(String metin) => find.textContaining(metin).evaluate().isNotEmpty;

Widget uygulama(Database db) => ProviderScope(
      overrides: [
        databaseProvider.overrideWith((ref) => db),
        teraziDurumStreamProvider.overrideWith((ref) => Stream.value(TeraziBaglantiDurumu.bagliDegil)),
        teraziAgirlikStreamProvider.overrideWith((ref) => const Stream.empty()),
        teraziBaglantiNotifierProvider.overrideWith(_SahteTerazi.new),
      ],
      child: const MaterialApp(
        locale: Locale('tr', 'TR'),
        supportedLocales: [Locale('tr', 'TR')],
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: AnaEkran(),
      ),
    );

void main() {
  setUpAll(initializeTurkishLocale);

  testWidgets('Süt sekmesinde girilen süt Cariler listesinde ve cari detayında görünür', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    late Database db;
    await tester.runAsync(() async {
      db = await testVeritabaniAc();
      await cariEkle(db, ad: 'AHMET', soyad: 'ATAĞ');
      await cariEkle(db, ad: 'AYŞE', soyad: 'KAVÇIN');
    });

    await tester.pumpWidget(uygulama(db));

    // 1) Önce Cariler sekmesini aç (liste belleğe yüklenir — IndexedStack).
    await tester.tap(find.byIcon(Icons.people_outline_rounded));
    await bekle(tester, () => gorunur('AHMET ATAĞ'), 'cari listesi');

    // 2) Süt sekmesi → AHMET ATAĞ → Süt Ekle → 25 kg → KAYDET
    await tester.tap(find.byIcon(Icons.water_drop_outlined));
    await tester.pump();
    final sutKarti = find.ancestor(of: find.text('AHMET ATAĞ').hitTestable(), matching: find.byType(ListTile));
    await bekle(tester, () => sutKarti.evaluate().isNotEmpty, 'süt listesi');
    await tester.tap(find.descendant(of: sutKarti.first, matching: find.text('Süt Ekle')));
    await bekle(tester, () => gorunur('KAYDET'), 'süt giriş sayfası');
    await tester.enterText(find.widgetWithText(TextField, 'Sabah Sütü (kg)'), '25');
    await tester.ensureVisible(find.text('KAYDET'));
    await tester.pump();
    await tester.tap(find.text('KAYDET'));
    await bekle(tester, () => !gorunur('Sabah Sütü (kg)'), 'kaydedip geri dönme');
    expect((await tester.runAsync(() => db.query('sutler')))!.single['toplam'], 25);

    // 3) Cariler sekmesi: liste güncel olmalı, detayda süt görünmeli.
    await tester.tap(find.byIcon(Icons.people_outline_rounded));
    await bekle(tester, () => gorunur('25.0 kg'), 'cari listesinde bu ayki süt (25.0 kg)');
    await tester.tap(find.text('AHMET ATAĞ').hitTestable().first);
    await bekle(tester, () => gorunur('Süt Kayıtları'), 'detay ekranı');
    await bekle(tester, () => gorunur('Sabah: 25'), 'detayda süt kaydı');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    await tester.runAsync(() => db.close());
  });

  testWidgets('Excel''den / başka ekrandan eklenen cari, açık sekmelere ANINDA düşer; Türkçe arama', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    late Database db;
    await tester.runAsync(() async {
      db = await testVeritabaniAc();
      await cariEkle(db, ad: 'Ali', soyad: 'Kaya');
      final pasif = await cariEkle(db, ad: 'Pasif', soyad: 'Alacaklı');
      await fiyatTanimla(db, pasif, '2020-01', sut: 10);
      await db.insert('sutler', {'cari_id': pasif, 'tarih': '2020-01-05', 'sabah': 10, 'toplam': 10});
      await db.update('cariler', {'aktif': 0}, where: 'id = ?', whereArgs: [pasif]);
    });
    await tester.pumpWidget(uygulama(db));

    // Tüm sekmeleri bir kez aç (hepsi IndexedStack'te bellekte kalır).
    for (final ikon in [Icons.people_outline_rounded, Icons.water_drop_outlined, Icons.grass_outlined]) {
      await tester.tap(find.byIcon(ikon));
      await bekle(tester, () => gorunur('Ali Kaya'), 'liste');
    }

    // Uygulama açıkken Excel'den içeri alınmış gibi yeni cari + "veri değişti" sinyali.
    await tester.runAsync(() => cariEkle(db, ad: 'İSMAİL', soyad: 'IŞIK'));
    ProviderScope.containerOf(tester.element(find.byType(AnaEkran))).read(veriSurumuProvider.notifier).state++;

    await bekle(tester, () => gorunur('İSMAİL IŞIK'), 'Yem sekmesinde yeni cari');
    await tester.tap(find.byIcon(Icons.water_drop_outlined));
    await bekle(tester, () => find.text('İSMAİL IŞIK').hitTestable().evaluate().isNotEmpty, 'Süt sekmesinde yeni cari');

    // Türkçe arama: küçük harf "ismail ışık" büyük harfli kaydı bulur.
    await tester.enterText(find.widgetWithText(TextField, 'Cari ara...').hitTestable(), 'ismail ışık');
    await tester.pump();
    expect(find.text('İSMAİL IŞIK').hitTestable(), findsOneWidget);
    expect(find.text('Ali Kaya').hitTestable(), findsNothing);

    // Cariler sekmesi de yeni cariyi gösterir.
    await tester.tap(find.byIcon(Icons.people_outline_rounded));
    await bekle(tester, () => find.text('İSMAİL IŞIK').hitTestable().evaluate().isNotEmpty, 'Cariler sekmesinde yeni cari');

    // Ödemeler: pasif ama alacaklı cari listede (toplamda sayılıp listede yoktu).
    await tester.tap(find.byIcon(Icons.account_balance_wallet_outlined));
    await bekle(tester, () => gorunur('Pasif Alacaklı (pasif)'), 'Ödemelerde pasif alacaklı cari');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    await tester.runAsync(() => db.close());
  });
}
