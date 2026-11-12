// Süt giriş ekranları ve akışları — derin denetim (ajan: sut_ekran).
//
// "DÜZELTİLDİ: ..." testleri DOĞRU davranışı bekler; hata varken BAŞARISIZ olur.
// "KONTROL: ..." testleri doğrulanmış doğru davranışlardır (geçmeli).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/core/providers/database_provider.dart';
import 'package:sutyem_pro/core/providers/veri_surumu_provider.dart';
import 'package:sutyem_pro/ekranlar/detay/kayit_duzenle_dialoglari.dart';
import 'package:sutyem_pro/ekranlar/hizli_sut_giris.dart';
import 'package:sutyem_pro/ekranlar/sut_ekrani.dart';
import 'package:sutyem_pro/features/sut/sut_toplama_durumu.dart';
import 'package:sutyem_pro/features/terazi/providers/terazi_providers.dart';
import 'package:sutyem_pro/features/terazi/services/terazi_baglanti_durumu.dart';
import 'package:sutyem_pro/models/cari_model.dart';
import 'package:sutyem_pro/models/sut_model.dart';
import 'package:sutyem_pro/utils/tarih_format.dart';

import '../helpers/test_db.dart';

class _SahteTerazi extends TeraziBaglantiNotifier {
  @override
  Future<bool> baslangicOtomatikBaglan() async => false;
}

Future<void> _bekle(WidgetTester tester, bool Function() kosul, String neyi) async {
  for (var i = 0; i < 150; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    if (kosul()) return;
  }
  fail('Zaman aşımı: $neyi');
}

Future<void> _gercekBekle(WidgetTester tester, [int ms = 300]) async {
  for (var i = 0; i < ms ~/ 20; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

Widget _uygulama(Database db, Widget ekran, {double yaziOlcegi = 1.0, DateTime? simdi}) => ProviderScope(
      overrides: [
        databaseProvider.overrideWith((ref) => db),
        teraziDurumStreamProvider.overrideWith((ref) => Stream.value(TeraziBaglantiDurumu.bagliDegil)),
        teraziAgirlikStreamProvider.overrideWith((ref) => const Stream.empty()),
        teraziBaglantiNotifierProvider.overrideWith(_SahteTerazi.new),
        if (simdi != null) simdiProvider.overrideWithValue(() => simdi),
      ],
      child: MaterialApp(
        locale: const Locale('tr', 'TR'),
        supportedLocales: const [Locale('tr', 'TR')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(yaziOlcegi)),
          child: child!,
        ),
        home: ekran,
      ),
    );

/// Ekranı "Aç" düğmesinin üstüne itilmiş sayfa olarak açar (geri tuşu gerçekten dönsün).
Widget _acici(Widget Function() sayfa) => Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => sayfa())),
            child: const Text('Aç'),
          ),
        ),
      ),
    );

/// Taşma hatalarını (hangi Row/Column, ne kadar) metin olarak toplar.
/// Dönen fonksiyon eski işleyiciyi geri koyar ve toplananları verir (expect'ten ÖNCE çağır).
List<String> Function() _tasmaDinle() {
  final hatalar = <String>[];
  final eski = FlutterError.onError;
  FlutterError.onError = (d) {
    final m = d.toString();
    hatalar.add(m
        .split('\n')
        .where((l) =>
            l.contains('overflowed') ||
            l.contains('creator') ||
            l.contains('lib/') ||
            l.contains('direction:') ||
            l.contains('constraints:'))
        .take(8)
        .join(' | '));
  };
  return () {
    FlutterError.onError = eski;
    return hatalar;
  };
}

String _gun(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  setUpAll(initializeTurkishLocale);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late Database db;
  late int ali;
  late int veli;
  final bugun = DateTime.now();
  final bugunStr = _gun(bugun);

  Future<void> hazirla(WidgetTester tester) async {
    await tester.runAsync(() async {
      db = await testVeritabaniAc();
      ali = await cariEkle(db, ad: 'Ali', soyad: 'Kaya');
      veli = await cariEkle(db, ad: 'Veli', soyad: 'Demir');
    });
  }

  Future<List<Map<String, Object?>>> sutler(WidgetTester tester) async =>
      (await tester.runAsync(() => db.query('sutler', orderBy: 'cari_id')))!;

  Future<void> geriTusu(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Cari aliNesnesi() => Cari(id: ali, ad: 'Ali', soyad: 'Kaya');

  // ════════════════════════════════════════════════════════════════
  group('Süt Ekle', () {
    Finder sabahAlani() => find.widgetWithText(TextField, 'Sabah Sütü (kg)');
    Finder aksamAlani() => find.widgetWithText(TextField, 'Akşam Sütü (kg)');

    Future<void> kaydeteBas(WidgetTester tester) async {
      await tester.ensureVisible(find.text('KAYDET'));
      await tester.pump();
      await tester.tap(find.text('KAYDET'));
    }

    for (final hatali in ['abc', '-5', '1,2,3', '12,5x', '5..5', '1e3']) {
      testWidgets('KONTROL: geçersiz kg "$hatali" kaydedilmez, alan hata gösterir', (tester) async {
        await hazirla(tester);
        await tester.pumpWidget(_uygulama(db, SutGirisSayfasi(cari: aliNesnesi())));
        await _bekle(tester, () => find.text('KAYDET').evaluate().isNotEmpty, 'ekran');
        await tester.enterText(sabahAlani(), hatali);
        await kaydeteBas(tester);
        await _gercekBekle(tester);
        expect(find.text('Geçersiz miktar'), findsOneWidget);
        expect(await sutler(tester), isEmpty);
      });
    }

    testWidgets(
        'DÜZELTİLDİ: bozuk binlik "1.2,3" geçersiz sayılmıyor → 12,3 kg kaydediliyor '
        '(binlik grup 3 hane olmalı; 1,23 mü 12,3 mü belirsiz)', (tester) async {
      await hazirla(tester);
      await tester.pumpWidget(_uygulama(db, SutGirisSayfasi(cari: aliNesnesi())));
      await _bekle(tester, () => find.text('KAYDET').evaluate().isNotEmpty, 'ekran');
      await tester.enterText(sabahAlani(), '1.2,3');
      await kaydeteBas(tester);
      await _gercekBekle(tester, 400);
      final s = await sutler(tester);
      expect(s, isEmpty, reason: 'kaydedilen: ${s.isEmpty ? '-' : s.single['sabah']} kg');
    });

    testWidgets('KONTROL: çok büyük kg (25000) reddedilir, kayıt yok, ekran açık', (tester) async {
      await hazirla(tester);
      await tester.pumpWidget(_uygulama(db, SutGirisSayfasi(cari: aliNesnesi())));
      await _bekle(tester, () => find.text('KAYDET').evaluate().isNotEmpty, 'ekran');
      await tester.enterText(sabahAlani(), '25000');
      await kaydeteBas(tester);
      await _bekle(tester, () => find.textContaining('çok yüksek').evaluate().isNotEmpty, 'hata mesajı');
      expect(await sutler(tester), isEmpty);
    });

    testWidgets('KONTROL: KAYDET\'e çift dokunma tek kayıt yazar (25 kg, 50 değil)', (tester) async {
      await hazirla(tester);
      await tester.pumpWidget(_uygulama(db, _acici(() => SutGirisSayfasi(cari: aliNesnesi()))));
      await tester.tap(find.text('Aç'));
      await _bekle(tester, () => find.text('KAYDET').evaluate().isNotEmpty, 'ekran');
      await tester.enterText(sabahAlani(), '25');
      await tester.ensureVisible(find.text('KAYDET'));
      await tester.pump();
      await tester.tap(find.text('KAYDET'));
      await tester.tap(find.text('KAYDET'), warnIfMissed: false);
      await _bekle(tester, () => find.text('Aç').evaluate().isNotEmpty, 'kaydedip döndü');
      final s = await sutler(tester);
      expect(s, hasLength(1));
      expect(s.single['sabah'], 25);
      expect(s.single['tarih'], bugunStr);
    });

    testWidgets('KONTROL: klavyede "Bitti" (onSubmitted) + KAYDET hızlıca → tek kayıt', (tester) async {
      await hazirla(tester);
      await tester.pumpWidget(_uygulama(db, _acici(() => SutGirisSayfasi(cari: aliNesnesi()))));
      await tester.tap(find.text('Aç'));
      await _bekle(tester, () => find.text('KAYDET').evaluate().isNotEmpty, 'ekran');
      await tester.enterText(aksamAlani(), '18');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.ensureVisible(find.text('KAYDET'));
      await tester.tap(find.text('KAYDET'), warnIfMissed: false);
      await _bekle(tester, () => find.text('Aç').evaluate().isNotEmpty, 'döndü');
      final s = await sutler(tester);
      expect(s, hasLength(1));
      expect(s.single['aksam'], 18);
    });

    testWidgets(
        'DÜZELTİLDİ: KAYDET sürerken geri tuşu → kayıt yazılır ama ref.veriDegisti() çağrılmaz '
        '(Süt sekmesi tiki, bakiye, Özet eski kalır)', (tester) async {
      await hazirla(tester);
      await tester.pumpWidget(_uygulama(db, _acici(() => SutGirisSayfasi(cari: aliNesnesi()))));
      final container = ProviderScope.containerOf(tester.element(find.text('Aç')));
      await tester.tap(find.text('Aç'));
      await _bekle(tester, () => find.text('KAYDET').evaluate().isNotEmpty, 'ekran');
      final surum0 = container.read(veriSurumuProvider);

      await tester.enterText(sabahAlani(), '25');
      await kaydeteBas(tester);
      await tester.pump(); // _kaydediliyor = true; DB yazımı (gerçek G/Ç) sürüyor
      await geriTusu(tester); // kullanıcı beklemeden geri tuşuna basar
      expect(find.text('Aç'), findsOneWidget, reason: 'kayıt sürerken ekran kapandı');

      await _bekle(tester, () => true, 'bekle');
      await _gercekBekle(tester, 400);
      final s = await sutler(tester);
      expect(s, hasLength(1), reason: 'kayıt veritabanına yazıldı');
      expect(s.single['sabah'], 25);
      expect(container.read(veriSurumuProvider), greaterThan(surum0),
          reason: 'süt yazıldı ama veri sürümü artmadı → bağlı ekranlar yenilenmez');
    });

    testWidgets(
        'DÜZELTİLDİ: tarih değiştirilince girilmiş ama kaydedilmemiş miktar SORMADAN silinir '
        '(Hızlı Süt Girişi soruyor)', (tester) async {
      if (bugun.day == 1) return; // ayın 1'inde "1" günü bugündür; test anlamsız
      await hazirla(tester);
      await tester.pumpWidget(_uygulama(db, SutGirisSayfasi(cari: aliNesnesi())));
      await _bekle(tester, () => find.text('KAYDET').evaluate().isNotEmpty, 'ekran');
      await tester.enterText(sabahAlani(), '25');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.calendar_today).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.tap(find.text('Tamam'));
      await tester.pump();
      await _gercekBekle(tester);

      final uyariVar = find.textContaining('kaydedilmemiş').evaluate().isNotEmpty ||
          find.textContaining('KAYDEDİLMEDİ').evaluate().isNotEmpty;
      final metin = sabahAlani().evaluate().isEmpty
          ? ''
          : tester.widget<TextField>(sabahAlani()).controller!.text;
      expect(uyariVar || metin == '25', isTrue,
          reason: 'yazılan 25 kg uyarısız silindi (alan: "$metin")');
    });

    testWidgets('KONTROL: geçmiş tarih seçilip kaydedilen süt o güne yazılır', (tester) async {
      if (bugun.day == 1) return;
      await hazirla(tester);
      await tester.pumpWidget(_uygulama(db, SutGirisSayfasi(cari: aliNesnesi())));
      await _bekle(tester, () => find.text('KAYDET').evaluate().isNotEmpty, 'ekran');
      await tester.tap(find.byIcon(Icons.calendar_today).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.tap(find.text('Tamam'));
      await tester.pump();
      await _gercekBekle(tester);
      await tester.enterText(sabahAlani(), '30');
      await kaydeteBas(tester);
      await _gercekBekle(tester, 400);
      final s = await sutler(tester);
      expect(s.single['tarih'], _gun(DateTime(bugun.year, bugun.month, 1)));
      expect(s.single['sabah'], 30);
    });

    testWidgets('KONTROL: 360 px + yazı x1.5 — kayıtlı öğün (19999,99 kg) ve uzun ad taşmaz', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await hazirla(tester);
      final uzun = await tester.runAsync(() => cariEkle(db, ad: 'Şükrüye Gülümser İğdeli', soyad: 'Çağlayangöçmen'));
      await tester.runAsync(() => db.insert('sutler',
          {'cari_id': uzun, 'tarih': bugunStr, 'sabah': 19999.99, 'aksam': 0, 'toplam': 19999.99}));
      await tester.pumpWidget(_uygulama(
          db, SutGirisSayfasi(cari: Cari(id: uzun, ad: 'Şükrüye Gülümser İğdeli', soyad: 'Çağlayangöçmen')),
          yaziOlcegi: 1.5));
      await _bekle(tester, () => find.byKey(const ValueKey('kilitliSabah')).evaluate().isNotEmpty, 'kilitli');
      expect(tester.takeException(), isNull);
    });
  });

  // ════════════════════════════════════════════════════════════════
  group('Hızlı Süt Girişi', () {
    Finder alan(int i) => find.byType(TextField).at(i);

    String kutuDegeri(WidgetTester tester, String baslik) {
      final kolon = find.ancestor(of: find.text(baslik), matching: find.byType(Column)).first;
      final yazilar = find.descendant(of: kolon, matching: find.byType(Text));
      return tester.widget<Text>(yazilar.first).data!;
    }

    testWidgets('KONTROL: arama sonrası girilen değer DOĞRU cariye gider (indeks kayması yok)', (tester) async {
      await hazirla(tester);
      await tester.pumpWidget(_uygulama(db, const HizliSutGiris()));
      await _bekle(tester, () => find.text('Veli Demir').evaluate().isNotEmpty, 'cariler');
      await tester.enterText(alan(0), 'velİ'); // Türkçe büyük İ ile arama
      await tester.pump();
      expect(find.text('Ali Kaya'), findsNothing);
      await tester.enterText(alan(1), '33'); // görünen ilk satırın sabahı = Veli
      await tester.enterText(alan(0), '');
      await tester.pump();
      await tester.tap(find.text('Tümünü Kaydet'));
      await _bekle(tester, () => find.textContaining('Kaydedildi').evaluate().isNotEmpty, 'kayıt');
      final s = await sutler(tester);
      expect(s, hasLength(1));
      expect(s.single['cari_id'], veli);
      expect(s.single['sabah'], 33);
    });

    testWidgets('KONTROL: "Tümünü Kaydet"e çift dokunma mükerrer/çift toplam yazmaz', (tester) async {
      await hazirla(tester);
      await tester.pumpWidget(_uygulama(db, const HizliSutGiris()));
      await _bekle(tester, () => find.text('Ali Kaya').evaluate().isNotEmpty, 'cariler');
      await tester.enterText(alan(1), '20');
      await tester.tap(find.text('Tümünü Kaydet'));
      await tester.tap(find.byTooltip('Tümünü Kaydet'), warnIfMissed: false);
      await _bekle(tester, () => find.textContaining('Kaydedildi').evaluate().isNotEmpty, 'kayıt');
      final s = await sutler(tester);
      expect(s, hasLength(1));
      expect(s.single['sabah'], 20);
    });

    testWidgets('KONTROL: geçersiz satır arama ile gizli olsa da kayıt engellenir (hiçbiri yazılmaz)',
        (tester) async {
      await hazirla(tester);
      await tester.pumpWidget(_uygulama(db, const HizliSutGiris()));
      await _bekle(tester, () => find.text('Ali Kaya').evaluate().isNotEmpty, 'cariler');
      await tester.enterText(alan(1), '-5'); // Ali sabah hatalı
      await tester.enterText(alan(3), '30'); // Veli sabah
      await tester.enterText(alan(0), 'Veli');
      await tester.pump();
      await tester.tap(find.text('Tümünü Kaydet'));
      await _gercekBekle(tester);
      expect(await sutler(tester), isEmpty);
    });

    testWidgets(
        'DÜZELTİLDİ: KAYDET sürerken geri tuşu → kayıt yazılır ama veriDegisti çağrılmaz '
        '(ekranlar eski rakamı gösterir)', (tester) async {
      await hazirla(tester);
      await tester.pumpWidget(_uygulama(db, _acici(() => const HizliSutGiris())));
      final container = ProviderScope.containerOf(tester.element(find.text('Aç')));
      await tester.tap(find.text('Aç'));
      await _bekle(tester, () => find.text('Ali Kaya').evaluate().isNotEmpty, 'cariler');
      final surum0 = container.read(veriSurumuProvider);
      await tester.enterText(alan(1), '20');
      await tester.enterText(alan(3), '30');
      await tester.tap(find.text('Tümünü Kaydet'));
      await tester.pump();
      await geriTusu(tester);
      expect(find.text('Aç'), findsOneWidget, reason: 'kayıt sürerken ekran kapandı');
      await _gercekBekle(tester, 400);
      final s = await sutler(tester);
      expect(s, hasLength(2), reason: 'kayıt veritabanına yazıldı');
      expect(container.read(veriSurumuProvider), greaterThan(surum0),
          reason: 'süt yazıldı ama veri sürümü artmadı');
    });

    testWidgets(
        'DÜZELTİLDİ: o gün kaydı olan PASİF cari alt paneldeki "Kayıtlı/Boş" sayısını bozar '
        '(aktif carilerin hiçbiri kayıtlı değilken "Kayıtlı 1, Boş 1")', (tester) async {
      await hazirla(tester);
      await tester.runAsync(() async {
        final pasif = await cariEkle(db, ad: 'Cem', soyad: 'Pasif');
        await db.insert('sutler', {'cari_id': pasif, 'tarih': bugunStr, 'sabah': 40, 'aksam': 0, 'toplam': 40});
        await db.update('cariler', {'aktif': 0, 'sira': null}, where: 'id = ?', whereArgs: [pasif]);
      });
      await tester.pumpWidget(_uygulama(db, const HizliSutGiris()));
      await _bekle(tester, () => find.text('Ali Kaya').evaluate().isNotEmpty, 'cariler');
      expect(find.text('Cem Pasif'), findsNothing, reason: 'pasif cari listede yok');
      expect(kutuDegeri(tester, 'Kayıtlı'), '0', reason: 'listedeki 2 aktif carinin hiçbiri kayıtlı değil');
      expect(kutuDegeri(tester, 'Boş'), '2');
    });

    testWidgets(
        'DÜZELTİLDİ: İLERİ tarihli taslak (telefon saati geri alınınca) BUGÜNÜN alanlarına uygulanır',
        (tester) async {
      await hazirla(tester);
      final yarin = _gun(DateTime(bugun.year, bugun.month, bugun.day + 1));
      SharedPreferences.setMockInitialValues({
        HizliSutGirisDurumuAnahtari.taslak: jsonEncode({
          'tarih': yarin,
          'sabah': {'$ali': '30'},
          'aksam': <String, String>{},
        }),
      });
      await tester.pumpWidget(_uygulama(db, const HizliSutGiris()));
      await _bekle(tester, () => find.text('Ali Kaya').evaluate().isNotEmpty, 'cariler');
      await _gercekBekle(tester);
      final aliSabah = tester.widget<TextField>(alan(1)).controller!.text;
      expect(aliSabah, isNot('30'),
          reason: '$yarin tarihli taslak bugünün ($bugunStr) Ali sabah alanına yazıldı');
    });

    testWidgets('KONTROL: taslak doğru cariye ve kendi gününe (dün) geri gelir, kendiliğinden kaydedilmez',
        (tester) async {
      await hazirla(tester);
      final dun = DateTime(bugun.year, bugun.month, bugun.day - 1);
      SharedPreferences.setMockInitialValues({
        HizliSutGirisDurumuAnahtari.taslak: jsonEncode({
          'tarih': _gun(dun),
          'sabah': {'$veli': '12,5'},
          'aksam': <String, String>{},
        }),
      });
      await tester.pumpWidget(_uygulama(db, const HizliSutGiris()));
      await _bekle(tester, () => find.textContaining('geri getirildi').evaluate().isNotEmpty, 'taslak');
      expect(tester.widget<TextField>(alan(3)).controller!.text, '12,5', reason: 'Veli sabah');
      expect(tester.widget<TextField>(alan(1)).controller!.text, '', reason: 'Ali sabah');
      expect(await sutler(tester), isEmpty);
      await tester.tap(find.text('Tümünü Kaydet'));
      await _bekle(tester, () => find.textContaining('Kaydedildi').evaluate().isNotEmpty, 'kayıt');
      final s = await sutler(tester);
      expect(s.single['tarih'], _gun(dun));
      expect(s.single['cari_id'], veli);
    });

    testWidgets('KONTROL: kayıtlı öğün Hızlı Girişte kilitli; aynı değer Süt Ekle ile de değiştirilemez',
        (tester) async {
      await hazirla(tester);
      await tester.runAsync(() => db.insert('sutler',
          {'cari_id': ali, 'tarih': bugunStr, 'sabah': 20, 'aksam': 0, 'toplam': 20}));
      await tester.pumpWidget(_uygulama(db, const HizliSutGiris()));
      await _bekle(tester, () => find.byKey(ValueKey('kilitli-sabah-$ali')).evaluate().isNotEmpty, 'kilit');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_uygulama(db, SutGirisSayfasi(cari: aliNesnesi())));
      await _bekle(tester, () => find.byKey(const ValueKey('kilitliSabah')).evaluate().isNotEmpty, 'kilit');
      expect(find.widgetWithText(TextField, 'Sabah Sütü (kg)'), findsNothing);
    });

    testWidgets('KONTROL: 360 px + yazı x1.5 — Hızlı Süt Girişi taşmaz', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await hazirla(tester);
      await tester.runAsync(() async {
        final c = await cariEkle(db, ad: 'Şükrüye Gülümser İğdeli', soyad: 'Çağlayangöçmen');
        await db.insert('sutler',
            {'cari_id': c, 'tarih': bugunStr, 'sabah': 19999.99, 'aksam': 19999.99, 'toplam': 39999.98});
      });
      final bitir = _tasmaDinle();
      await tester.pumpWidget(_uygulama(db, const HizliSutGiris(), yaziOlcegi: 1.5));
      var bulundu = false;
      for (var i = 0; i < 60 && !bulundu; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
        bulundu = find.textContaining('Ali Kaya').evaluate().isNotEmpty;
      }
      if (bulundu) {
        await tester.drag(find.byType(NestedScrollView), const Offset(0, -800));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }
      final kayitliGorundu = find.textContaining('Kayıtlı ·').evaluate().isNotEmpty;
      final tasmalar = bitir();
      expect(bulundu, isTrue, reason: 'liste yüklenmedi');
      expect(tasmalar, isEmpty, reason: tasmalar.join('\n'));
      expect(kayitliGorundu, isTrue, reason: 'uzun adlı kayıtlı satır görünmedi');
    });
  });

  // ════════════════════════════════════════════════════════════════
  group('Süt sekmesi listesi', () {
    testWidgets(
        'DÜZELTİLDİ: 360 px + yazı x1.5 — "Sabah toplaması · 1 / 3 alındı" özet satırı sağdan taşar '
        '(sut_ekrani.dart:179 Row)', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await hazirla(tester);
      await tester.runAsync(() async {
        final c = await cariEkle(db, ad: 'Şükrüye Gülümser İğdeli', soyad: 'Çağlayangöçmen');
        await db.update('cariler', {'telefon': '0555 123 45 67'}, where: 'id = ?', whereArgs: [c]);
        await db.insert('sutler',
            {'cari_id': c, 'tarih': bugunStr, 'sabah': 19999.99, 'aksam': 0, 'toplam': 19999.99});
      });
      await tester.pumpWidget(_uygulama(db, const SutEkrani(),
          yaziOlcegi: 1.5, simdi: DateTime(bugun.year, bugun.month, bugun.day, 7)));
      final bitir = _tasmaDinle();
      for (var i = 0; i < 60 && find.textContaining('Sabah alındı').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      final tikVar = find.textContaining('Sabah alındı').evaluate().isNotEmpty;
      final tasmalar = bitir();
      expect(tikVar, isTrue);
      expect(tasmalar, isEmpty, reason: tasmalar.join('\n'));
    });

    testWidgets('KONTROL: Süt Ekle ile kaydedince listede yeşil tik hemen çıkar ve sayaç artar', (tester) async {
      await hazirla(tester);
      await tester.pumpWidget(_uygulama(db, const SutEkrani(),
          simdi: DateTime(bugun.year, bugun.month, bugun.day, 7)));
      await _bekle(tester, () => find.text('0 / 2 alındı').evaluate().isNotEmpty, 'liste');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Süt Ekle').first);
      await _bekle(tester, () => find.text('KAYDET').evaluate().isNotEmpty, 'Süt Ekle');
      // Liste rota/alfabetik: ilk kart Ali Kaya mı Veli Demir mi? Başlıktan kontrol edilir.
      final baslik = tester.widget<Text>(find.descendant(of: find.byType(AppBar), matching: find.byType(Text)).first).data;
      await tester.enterText(find.widgetWithText(TextField, 'Sabah Sütü (kg)'), '22');
      await tester.ensureVisible(find.text('KAYDET'));
      await tester.pump();
      await tester.tap(find.text('KAYDET'));
      await _bekle(tester, () => find.text('1 / 2 alındı').evaluate().isNotEmpty, 'sayaç');
      final s = await sutler(tester);
      expect(s.single['cari_id'], baslik == 'Ali Kaya' ? ali : veli, reason: 'dokunulan cariye yazıldı');
    });
  });

  // ════════════════════════════════════════════════════════════════
  group('Cari Detay → Düzenle (süt satırı)', () {
    Future<void> dialogAc(WidgetTester tester, Sut sut, {double yaziOlcegi = 1.0}) async {
      await tester.pumpWidget(_uygulama(
          db,
          Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showDialog<bool>(context: ctx, builder: (_) => SutDuzenleDialog(sut: sut)),
                  child: const Text('Düzenle Aç'),
                ),
              ),
            ),
          ),
          yaziOlcegi: yaziOlcegi));
      await tester.tap(find.text('Düzenle Aç'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('KONTROL: geçersiz kg Düzenle\'de kaydedilmez (kayıt aynı kalır)', (tester) async {
      await hazirla(tester);
      final id = await tester.runAsync(() => db.insert('sutler',
          {'cari_id': ali, 'tarih': bugunStr, 'sabah': 20, 'aksam': 10, 'toplam': 30}));
      await dialogAc(tester, Sut(id: id, cariId: ali, tarih: bugunStr, sabah: 20, aksam: 10));
      await tester.enterText(find.widgetWithText(TextField, 'Sabah (kg)'), '2O'); // O harfi
      await tester.tap(find.text('Kaydet'));
      await _gercekBekle(tester);
      expect(find.textContaining('Geçersiz miktar'), findsOneWidget);
      final s = await sutler(tester);
      expect(s.single['sabah'], 20);
      expect(s.single['toplam'], 30);
    });

    testWidgets(
        'DÜZELTİLDİ: Düzenle\'de yalnız akşam değiştirilince DOKUNULMAYAN sabah 2 haneye yuvarlanıp '
        'kaydedilir (Süt Ekle 12,345 kabul ediyor)', (tester) async {
      await hazirla(tester);
      // Önce Süt Ekle'nin 3 ondalığı olduğu gibi kaydettiğini göster.
      await tester.pumpWidget(_uygulama(db, SutGirisSayfasi(cari: aliNesnesi())));
      await _bekle(tester, () => find.text('KAYDET').evaluate().isNotEmpty, 'ekran');
      await tester.enterText(find.widgetWithText(TextField, 'Sabah Sütü (kg)'), '12,345');
      await tester.ensureVisible(find.text('KAYDET'));
      await tester.pump();
      await tester.tap(find.text('KAYDET'));
      await _gercekBekle(tester, 400);
      final once = (await sutler(tester)).single;
      expect(once['sabah'], 12.345);

      await tester.pumpWidget(const SizedBox());
      await dialogAc(tester,
          Sut(id: once['id'] as int, cariId: ali, tarih: bugunStr, sabah: 12.345, aksam: 0));
      await tester.enterText(find.widgetWithText(TextField, 'Akşam (kg)'), '10');
      await tester.tap(find.text('Kaydet'));
      await _gercekBekle(tester, 400);
      final sonra = (await sutler(tester)).single;
      expect(sonra['aksam'], 10);
      expect(sonra['sabah'], 12.345, reason: 'dokunulmayan sabah değişti: ${sonra['sabah']}');
    });

    testWidgets('KONTROL: 360 px + yazı x1.5 — Düzenle penceresi taşmaz', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await hazirla(tester);
      await dialogAc(tester, Sut(id: 1, cariId: ali, tarih: bugunStr, sabah: 19999.99, aksam: 19999.99),
          yaziOlcegi: 1.5);
      expect(tester.takeException(), isNull);
    });
  });
}

/// Taslak anahtarı ekranda `static const` (özel sınıfta); testte aynı değer.
abstract final class HizliSutGirisDurumuAnahtari {
  static const taslak = 'hizli_sut_taslak';
}
