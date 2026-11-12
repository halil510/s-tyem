import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sutyem_pro/features/fis/fis_ekranlari.dart';
import 'package:sutyem_pro/features/fis/fis_servisi.dart';
import 'package:sutyem_pro/utils/bt_cihaz_suzgeci.dart';
import 'package:sutyem_pro/utils/tarih_format.dart';

/// Bluetooth aramada: isimsizler gizli, yazıcı/teraziye benzeyenler üstte; fiş yazıcısı
/// eşleşmemiş yazıcıyı "Yakındaki yazıcıları ara" ile bulur ve kaydeder.
void main() {
  setUpAll(initializeTurkishLocale);

  group('Süzgeç', () {
    final cihazlar = [
      const BtCihaz(ad: 'Galaxy Buds', adres: 'AA', eslesmis: true),
      const BtCihaz(ad: '', adres: 'BB', rssi: -40),
      const BtCihaz(ad: 'Unknown Device', adres: 'CC'),
      const BtCihaz(ad: 'PT-210', adres: 'DD', rssi: -70),
      const BtCihaz(ad: 'HC-05', adres: 'EE', rssi: -50),
      const BtCihaz(ad: 'Samsung TV', adres: 'FF', rssi: -30),
      const BtCihaz(ad: 'PT-210', adres: 'DD', rssi: -55, eslesmis: true), // aynı cihaz, ikinci görülüş
    ];

    test('Yazıcı aranırken: isimsizler gizli, yazıcı en üstte, aynı adres tekleşir (eşleşmiş + en güçlü sinyal)', () {
      final l = BtCihazSuzgeci.sirala(cihazlar, BtAranan.yazici);
      expect(l.map((c) => c.adres), ['DD', 'AA', 'FF', 'EE']);
      expect([l.first.eslesmis, l.first.rssi], [true, -55]);
      expect(BtCihazSuzgeci.isimsizSayisi(cihazlar), 2);
      expect(BtCihazSuzgeci.sirala(cihazlar, BtAranan.yazici, isimsizleriGoster: true).length, 6);
    });

    test('Terazi aranırken HC-05 en üstte', () {
      expect(BtCihazSuzgeci.sirala(cihazlar, BtAranan.terazi).first.ad, 'HC-05');
      expect(BtCihazSuzgeci.benziyor('Galaxy Buds', BtAranan.terazi), isFalse);
      expect(BtCihazSuzgeci.benziyor('XP-58IIH', BtAranan.yazici), isTrue);
    });
  });

  testWidgets('Fiş yazıcısı: eşleşmiş listede yazıcı yok → "Yakındaki yazıcıları ara" → PT-210 üstte, isimsizler gizli → seçilip kaydedilir',
      (t) async {
    t.view.physicalSize = const Size(360, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    SharedPreferences.setMockInitialValues({});
    const kanal = MethodChannel('classic_bluetooth');
    final cagrilar = <String>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(kanal, (c) async {
      cagrilar.add(c.method);
      final eslesmis = [
        {'name': 'Galaxy Buds', 'address': 'AA:AA', 'bonded': true, 'rssi': null},
      ];
      if (c.method == 'getPairedDevices') return eslesmis;
      if (c.method == 'discover') {
        return [
          ...eslesmis,
          {'name': '', 'address': 'BB:BB', 'bonded': false, 'rssi': -40},
          {'name': 'Samsung TV', 'address': 'FF:FF', 'bonded': false, 'rssi': -30},
          {'name': 'PT-210', 'address': 'DD:DD', 'bonded': false, 'rssi': -65},
        ];
      }
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(kanal, null));

    await t.pumpWidget(const MaterialApp(
      locale: Locale('tr', 'TR'),
      supportedLocales: [Locale('tr', 'TR')],
      localizationsDelegates: [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      home: FisYaziciAyarlariEkrani(),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('Bluetooth'));
    await t.pumpAndSettle();
    expect(find.text('Galaxy Buds'), findsOneWidget);
    expect(find.text('PT-210'), findsNothing);

    await t.tap(find.byKey(const ValueKey('btAra')));
    await t.pumpAndSettle();
    expect(cagrilar, contains('discover'));
    expect(find.text('PT-210'), findsOneWidget);
    expect(find.text('yazıcı olabilir'), findsOneWidget);
    expect(find.text('(İsimsiz cihaz)'), findsNothing);
    expect(find.text('İsimsiz cihazları da göster (1)'), findsOneWidget);
    // Yazıcı listenin en üstünde.
    expect(t.getTopLeft(find.text('PT-210')).dy, lessThan(t.getTopLeft(find.text('Samsung TV')).dy));
    expect(t.getTopLeft(find.text('PT-210')).dy, lessThan(t.getTopLeft(find.text('Galaxy Buds')).dy));

    await t.ensureVisible(find.text('PT-210'));
    await t.pumpAndSettle();
    await t.tap(find.text('PT-210'));
    await t.pump();
    await t.ensureVisible(find.byKey(const ValueKey('yaziciKaydet')));
    await t.tap(find.byKey(const ValueKey('yaziciKaydet')));
    await t.pumpAndSettle();
    final a = await FisAyarlari.yukle();
    expect([a.baglanti, a.yaziciAdres, a.yaziciAdi], [YaziciBaglantisi.bluetooth, 'DD:DD', 'PT-210']);
    expect(t.takeException(), isNull);
  });
}
