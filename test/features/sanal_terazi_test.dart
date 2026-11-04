import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/core/providers/database_provider.dart';
import 'package:sutyem_pro/ekranlar/sut_ekrani.dart';
import 'package:sutyem_pro/features/terazi/providers/terazi_providers.dart';
import 'package:sutyem_pro/models/cari_model.dart';
import 'package:sutyem_pro/utils/tarih_format.dart';

import '../helpers/test_db.dart';

/// SANAL TERAZİ: bilgisayarda gerçek bir TCP sunucusu (Wi-Fi terazi gibi)
/// tartı satırları gönderir. Uygulamanın GERÇEK terazi servisi bağlanır;
/// Süt Ekle ekranında okunan kilo "Sabaha/Akşama Uygula" + KAYDET ile
/// veritabanına doğru yazılmalı. Hiçbir terazi parçası taklit (mock) edilmez.
class SanalTerazi {
  late final ServerSocket _sunucu;
  final _baglantilar = <Socket>[];
  final _ilkBaglanti = Completer<void>();

  int get port => _sunucu.port;

  Future<void> baslat() async {
    _sunucu = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _sunucu.listen((s) {
      _baglantilar.add(s);
      s.listen((_) {}, onDone: () => _baglantilar.remove(s), onError: (_) => _baglantilar.remove(s));
      if (!_ilkBaglanti.isCompleted) _ilkBaglanti.complete();
    });
  }

  Future<void> baglantiBekle() => _ilkBaglanti.future.timeout(const Duration(seconds: 5));

  /// Ham baytları gönderir (gerçek terazide bir "paket").
  Future<void> gonder(String veri) async {
    for (final s in List.of(_baglantilar)) {
      s.write(veri);
      await s.flush();
    }
  }

  Future<void> kapat() async {
    for (final s in List.of(_baglantilar)) {
      s.destroy();
    }
    await _sunucu.close();
  }
}

void main() {
  setUpAll(initializeTurkishLocale);

  late Database db;
  late int ali;
  late SanalTerazi terazi;
  late ProviderContainer container;

  Future<void> bekle(WidgetTester tester, bool Function() kosul, String neyi) async {
    for (var i = 0; i < 150; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      if (kosul()) return;
    }
    fail('Zaman aşımı: $neyi');
  }

  /// Teraziye paket gönderir ve ekranın işlemesi için kısa süre bekler.
  Future<void> paket(WidgetTester tester, String veri, {int ms = 60}) async {
    await tester.runAsync(() async {
      await terazi.gonder(veri);
      await Future<void>.delayed(Duration(milliseconds: ms));
    });
    await tester.pump();
  }

  /// Süt Ekle ekranındaki büyük terazi göstergesi.
  String gosterge(WidgetTester tester) {
    final kart = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_CanliTeraziKarti');
    final yazilar = find.descendant(of: kart, matching: find.byType(Text));
    return tester
        .widgetList<Text>(yazilar)
        .map((t) => t.data ?? '')
        .firstWhere((s) => RegExp(r'^-?\d+\.\d\d$').hasMatch(s) || s == '--.--', orElse: () => '?');
  }

  Future<void> hazirla(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Bilgisayarda Android'in Klasik Bluetooth eklentisi yok; kanal boş
    // yanıt versin (bu testte terazi Wi-Fi ile bağlanıyor).
    final mesaj = tester.binding.defaultBinaryMessenger;
    mesaj.setMockMethodCallHandler(const MethodChannel('classic_bluetooth'), (_) async => null);
    mesaj.setMockStreamHandler(const EventChannel('classic_bluetooth_events'),
        MockStreamHandler.inline(onListen: (_, __) {}));
    await tester.runAsync(() async {
      db = await testVeritabaniAc();
      ali = await cariEkle(db, ad: 'Ali', soyad: 'Kaya');
      terazi = SanalTerazi();
      await terazi.baslat();
    });
    container = ProviderContainer(overrides: [databaseProvider.overrideWith((ref) => db)]);

    // Terazi ekranındaki "Wi-Fi ile bağlan" ile aynı çağrı.
    await tester.runAsync(() async {
      await container.read(teraziBaglantiNotifierProvider.notifier).wifiBagla('127.0.0.1', terazi.port);
      await terazi.baglantiBekle();
    });

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('tr', 'TR'),
        supportedLocales: const [Locale('tr', 'TR')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: SutGirisSayfasi(cari: Cari(id: ali, ad: 'Ali', soyad: 'Kaya')),
      ),
    ));
    await bekle(tester, () => find.text('KAYDET').evaluate().isNotEmpty, 'Süt Ekle ekranı');
    await bekle(tester, () => find.text('TERAZİ BAĞLI — CANLI ÖLÇÜM').evaluate().isNotEmpty, 'terazi BAĞLI görünür');
  }

  Future<void> temizle(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await container.read(teraziBaglantiNotifierProvider.notifier).baglantiyiKes();
      container.dispose();
      await terazi.kapat();
      await db.close();
    });
  }

  Future<Map<String, Object?>?> kayit(WidgetTester tester) async {
    final r = await tester.runAsync(() => db.query('sutler', where: 'cari_id = ?', whereArgs: [ali]));
    return r!.isEmpty ? null : r.single;
  }

  testWidgets('tartı gelir → Sabaha Uygula → yeni tartı → Akşama Uygula → KAYDET', (tester) async {
    await hazirla(tester);

    await paket(tester, 'ST,GS,+0025.40kg\r\n');
    await bekle(tester, () => gosterge(tester) == '25.40', 'göstergede 25.40');
    await tester.tap(find.text('Sabaha Uygula'));
    await tester.pump();

    await paket(tester, 'ST,GS,+0018.75kg\r\n');
    await bekle(tester, () => gosterge(tester) == '18.75', 'göstergede 18.75');
    await tester.tap(find.text('Akşama Uygula'));
    await tester.pump();

    expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Sabah Sütü (kg)')).controller!.text, '25.40');
    expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Akşam Sütü (kg)')).controller!.text, '18.75');

    await tester.ensureVisible(find.text('KAYDET'));
    await tester.pump();
    await tester.tap(find.text('KAYDET'));
    for (var i = 0; i < 100 && await kayit(tester) == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }

    final k = (await kayit(tester))!;
    expect(k['sabah'], 25.4);
    expect(k['aksam'], 18.75);
    expect(k['toplam'], 44.15);
    expect(k['tarih'], DateTime.now().toIso8601String().substring(0, 10));
    await temizle(tester);
  });

  testWidgets('satır iki pakete bölünerek gelirse yanlış kilo GÖSTERİLMEZ', (tester) async {
    await hazirla(tester);
    await paket(tester, 'ST,GS,+0010.00kg\r\n');
    await bekle(tester, () => gosterge(tester) == '10.00', 'ilk tartı');

    // Bluetooth / Wi-Fi'da sık olur: "+0012.80kg" iki parçada gelir.
    final gorulen = <String>{};
    await paket(tester, 'ST,GS,+0012', ms: 40);
    gorulen.add(gosterge(tester));
    await paket(tester, '.80kg\r\n');
    await bekle(tester, () => gosterge(tester) == '12.80', 'parçalar birleşince 12.80');
    gorulen.add(gosterge(tester));
    expect(gorulen.difference({'10.00', '12.80'}), isEmpty,
        reason: 'ara değer (12.00 / 80.00 gibi) hiç görünmemeli; görülen: $gorulen');
    await temizle(tester);
  });

  testWidgets('bir pakette birden çok satır: en SON tartı gösterilir', (tester) async {
    await hazirla(tester);
    await paket(tester, 'ST,GS,+0020.10kg\r\nST,GS,+0020.20kg\r\nST,GS,+0020.30kg\r\n');
    await bekle(tester, () => gosterge(tester) == '20.30', 'son satır 20.30');
    await temizle(tester);
  });

  testWidgets('farklı terazi biçimleri doğru okunur; anlamsız satır göstergeyi bozmaz', (tester) async {
    await hazirla(tester);
    final ornekler = {
      'ST,GS,+0025.40kg\r\n': '25.40', // yaygın gösterge (ST=stabil, GS=brüt)
      'US,GS,+0031.05kg\r\n': '31.05', // dengesiz (US) okuma da gösterilir
      '  42.5 kg\r\n': '42.50',
      'W: 7,25 kg\n': '7.25', // virgüllü
      '001 0033.60\r\n': '33.60', // başta terazi numarası
      'NET 0015.20 kg\r\n': '15.20',
      '\x02+0019.90kg\x03': '19.90', // STX/ETX çerçeve
      '12500 g\r\n': '12.50', // gram birimi
    };
    for (final e in ornekler.entries) {
      await paket(tester, e.key);
      await bekle(tester, () => gosterge(tester) == e.value,
          '${e.key.replaceAll('\r', r'\r').replaceAll('\n', r'\n')} → ${e.value} (görülen: ${gosterge(tester)})');
    }
    // Durum / hata satırları son geçerli tartıyı silmemeli.
    await paket(tester, 'OL\r\n');
    await paket(tester, 'ST\r\n');
    expect(gosterge(tester), '12.50');
    await temizle(tester);
  });
}
