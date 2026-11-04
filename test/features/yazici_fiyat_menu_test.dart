import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/core/providers/database_provider.dart';
import 'package:sutyem_pro/ekranlar/ana_ekran.dart';
import 'package:sutyem_pro/ekranlar/sut_fiyat_ekrani.dart';
import 'package:sutyem_pro/ekranlar/yem_fiyat_ekrani.dart';
import 'package:sutyem_pro/features/fis/fis_ekranlari.dart';
import 'package:sutyem_pro/features/fis/fis_servisi.dart';
import 'package:sutyem_pro/features/fis/uretici_fisi.dart';
import 'package:sutyem_pro/features/terazi/providers/terazi_providers.dart';
import 'package:sutyem_pro/features/terazi/services/terazi_baglanti_durumu.dart';
import 'package:sutyem_pro/models/cari_fiyat_model.dart';
import 'package:sutyem_pro/utils/tarih_format.dart';

import '../helpers/test_db.dart';

class _SahteTerazi extends TeraziBaglantiNotifier {
  @override
  Future<bool> baslangicOtomatikBaglan() async => false;
}

/// Yerel ağdaki termal yazıcıyı taklit eder: 127.0.0.1'de port açar, gelen baytları toplar.
class _SahteAgYazicisi {
  late ServerSocket sunucu;
  final gelen = <int>[];
  int baglantiSayisi = 0;

  Future<void> baslat() async {
    sunucu = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    sunucu.listen((s) {
      baglantiSayisi++;
      s.listen(gelen.addAll, onDone: s.destroy);
    });
  }

  int get port => sunucu.port;
  Future<void> kapat() => sunucu.close();
}

Widget _uygulama(Database db, Widget ekran) => ProviderScope(
      overrides: [
        databaseProvider.overrideWith((ref) => db),
        teraziDurumStreamProvider.overrideWith((ref) => Stream.value(TeraziBaglantiDurumu.bagliDegil)),
        teraziAgirlikStreamProvider.overrideWith((ref) => const Stream.empty()),
        teraziBaglantiNotifierProvider.overrideWith(_SahteTerazi.new),
      ],
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

Future<void> _bekle(WidgetTester tester, bool Function() kosul, String neyi) async {
  for (var i = 0; i < 150; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    if (kosul()) return;
  }
  fail('Zaman aşımı: $neyi');
}

final _fis = UreticiFisi(
  isletmeAdi: 'Test',
  fisNo: 7,
  tarih: DateTime(2026, 11, 4),
  basimZamani: DateTime(2026, 11, 4, 8),
  ureticiAdi: 'Ali Kaya',
  sabah: 20,
  aksam: 18,
  buAyKg: 100,
);

void main() {
  setUpAll(initializeTurkishLocale);

  group('Wi-Fi fiş yazıcısı', () {
    test('IP adresi doğrulama', () {
      expect(FisAyarlari.gecerliAgAdresi('192.168.1.50'), isTrue);
      expect(FisAyarlari.gecerliAgAdresi(' 10.0.0.7 '), isTrue);
      expect(FisAyarlari.gecerliAgAdresi('yazici.local'), isTrue);
      for (final kotu in ['', '192.168.1', '192.168.1.300', '192.168 .1.5', null]) {
        expect(FisAyarlari.gecerliAgAdresi(kotu), isFalse, reason: '$kotu');
      }
    });

    test('fiş ağdan (TCP) yazıcıya ESC/POS olarak gider', () async {
      final yazici = _SahteAgYazicisi();
      await yazici.baslat();
      addTearDown(yazici.kapat);
      final ayar = FisAyarlari(baglanti: YaziciBaglantisi.wifi, wifiAdres: '127.0.0.1', wifiPort: yazici.port);
      expect(ayar.yaziciSecili, isTrue);
      expect(ayar.yaziciEtiketi, '127.0.0.1:${yazici.port} (Wi-Fi)');

      await TermalYaziciServisi.yazdir(ayar, _fis.satirlar(40));
      for (var i = 0; i < 50 && yazici.gelen.length < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(yazici.gelen.take(2), [0x1B, 0x40]);
      expect(String.fromCharCodes(yazici.gelen), contains('Ali Kaya'));
      expect(String.fromCharCodes(yazici.gelen), contains('38 kg'));
    });

    test('ulaşılamayan yazıcıda anlaşılır hata, kilit takılı kalmaz', () async {
      final bos = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = bos.port;
      await bos.close(); // port artık kapalı
      final ayar = FisAyarlari(baglanti: YaziciBaglantisi.wifi, wifiAdres: '127.0.0.1', wifiPort: port);
      for (var i = 0; i < 2; i++) {
        await expectLater(TermalYaziciServisi.yazdir(ayar, _fis.satirlar(40)),
            throwsA(isA<YaziciHatasi>().having((e) => e.mesaj, 'mesaj', contains('AYNI Wi-Fi'))));
      }
      await expectLater(TermalYaziciServisi.wifiTest('127.0.0.1', port), throwsA(isA<YaziciHatasi>()));
    });

    test('Wi-Fi ayarı kaydedilir ve geri okunur', () async {
      SharedPreferences.setMockInitialValues({});
      await const FisAyarlari(baglanti: YaziciBaglantisi.wifi, wifiAdres: '192.168.1.50', wifiPort: 9101).kaydet();
      final a = await FisAyarlari.yukle();
      expect((a.baglanti, a.wifiAdres, a.wifiPort, a.yaziciSecili), (YaziciBaglantisi.wifi, '192.168.1.50', 9101, true));
    });

    testWidgets('ekran: Wi-Fi yazıcı test edilip kaydedilir, sonra KİLİTLİ kalır', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(400, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final yazici = _SahteAgYazicisi();
      await tester.runAsync(yazici.baslat);
      final db = (await tester.runAsync(testVeritabaniAc))!;

      await tester.pumpWidget(_uygulama(db, const FisYaziciAyarlariEkrani()));
      await _bekle(tester, () => find.text('Wi-Fi / Ağ').evaluate().isNotEmpty, 'seçim alanı');
      await tester.tap(find.text('Wi-Fi / Ağ'));
      await tester.pump();

      // Hatalı IP kaydedilmez.
      await tester.enterText(find.byKey(const ValueKey('yaziciIp')), '192.168.1');
      await tester.tap(find.byKey(const ValueKey('yaziciKaydet')));
      await tester.pump();
      expect(find.textContaining('Geçerli bir IP'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('yaziciIp')), '127.0.0.1');
      await tester.enterText(find.byKey(const ValueKey('yaziciPort')), '${yazici.port}');
      await tester.tap(find.byKey(const ValueKey('yaziciKaydet')));
      await _bekle(tester, () => find.byKey(const ValueKey('kayitliYazici')).evaluate().isNotEmpty, 'kayıtlı kart');
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('kayitliYazici')),
              matching: find.textContaining('127.0.0.1:${yazici.port} (Wi-Fi)')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('yaziciIp')), findsNothing, reason: 'kayıtlıyken alanlar kilitli');

      // Ekran yeniden açılınca yazıcı hâlâ kayıtlı ve kilitli.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_uygulama(db, const FisYaziciAyarlariEkrani()));
      await _bekle(tester, () => find.byKey(const ValueKey('kayitliYazici')).evaluate().isNotEmpty, 'yeniden açılış');

      // Değiştir → onay → seçim açılır.
      await tester.tap(find.text('Değiştir'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Değiştir'));
      await _bekle(tester, () => find.byKey(const ValueKey('yaziciIp')).evaluate().isNotEmpty, 'değiştirme alanı');

      await tester.runAsync(() async {
        await yazici.kapat();
        await db.close();
      });
    });
  });

  testWidgets('süt fiyatı: tümüne aynı fiyat → kaydet → her cari aynı fiyat', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late Database db;
    await tester.runAsync(() async {
      db = await testVeritabaniAc();
      final ali = await cariEkle(db, ad: 'Ali', soyad: 'Kaya');
      await cariEkle(db, ad: 'Veli', soyad: 'Demir');
      await cariEkle(db, ad: 'Ayşe', soyad: 'Kaya');
      final n = DateTime.now();
      await fiyatTanimla(db, ali, '${n.year}-${n.month.toString().padLeft(2, '0')}', sut: 15);
    });

    await tester.pumpWidget(_uygulama(db, const SutFiyatEkrani()));
    await _bekle(tester, () => find.byKey(const ValueKey('topluSutFiyati')).evaluate().isNotEmpty, 'ekran');

    await tester.enterText(find.byKey(const ValueKey('topluSutFiyati')), 'abc');
    await tester.tap(find.textContaining('Tümüne'));
    await tester.pump();
    expect(find.textContaining('Geçerli bir fiyat'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('topluSutFiyati')), '18,75');
    await tester.tap(find.textContaining('Tümüne'));
    await tester.pump();
    expect(find.text('18.75'), findsNWidgets(3), reason: 'üç carinin alanı doldu');
    expect((await tester.runAsync(() => db.query('cari_fiyatlar')))!.single['sut_fiyat'], 15,
        reason: 'Kaydet basılmadan veritabanı değişmez');

    await tester.tap(find.text('Kaydet'));
    // Varsayılan: fiyat BUGÜNDEN itibaren geçerli (ayın 1'iyse aylık anahtar).
    final bugun = DateTime.now();
    final anahtar = CariFiyat.anahtar(bugun);
    var fiyatlar = <Map<String, Object?>>[];
    for (var i = 0; i < 100 && fiyatlar.length < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      fiyatlar = (await tester.runAsync(() => db.query('cari_fiyatlar',
          where: 'ay = ?', whereArgs: [anahtar], orderBy: 'cari_id')))!;
    }
    expect(fiyatlar.map((r) => r['sut_fiyat']), [18.75, 18.75, 18.75]);
    if (bugun.day != 1) {
      final ay = await tester.runAsync(() => db.query('cari_fiyatlar',
          where: 'ay = ?', whereArgs: [anahtar.substring(0, 7)]));
      expect(ay!.single['sut_fiyat'], 15, reason: 'ayın önceki günleri eski fiyatta kalır');
    }
    await tester.pump(const Duration(seconds: 10)); // bildirimler kapansın
    await tester.runAsync(() => db.close());
  });

  testWidgets('yem fiyatı: tür seç → tümüne aynı fiyat → kaydet; diğer türler korunur', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late Database db;
    final ay = CariFiyat.anahtar(DateTime(DateTime.now().year, DateTime.now().month, 1));
    await tester.runAsync(() async {
      db = await testVeritabaniAc();
      final ali = await cariEkle(db, ad: 'Ali', soyad: 'Kaya');
      await cariEkle(db, ad: 'Veli', soyad: 'Demir');
      await fiyatTanimla(db, ali, ay, sut: 15, sutYemi: 11);
    });

    await tester.pumpWidget(_uygulama(db, const YemFiyatEkrani()));
    await _bekle(tester, () => find.byKey(const ValueKey('topluYemFiyati')).evaluate().isNotEmpty, 'ekran');

    // Geçersiz fiyat uyarısı
    await tester.enterText(find.byKey(const ValueKey('topluYemFiyati')), '0');
    await tester.tap(find.textContaining('Tümüne'));
    await tester.pump();
    expect(find.textContaining('Geçerli bir fiyat'), findsOneWidget);

    // Besi Yemi seç, 9,50 yaz, tümüne uygula
    await tester.tap(find.byKey(const ValueKey('topluYemTuru')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Besi Yemi').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('topluYemFiyati')), '9,50');
    await tester.tap(find.textContaining('Tümüne'));
    await tester.pump();
    expect((await tester.runAsync(() => db.query('cari_fiyatlar')))!.single['besi_yemi_fiyat'], 0,
        reason: 'Kaydet basılmadan veritabanı değişmez');

    await tester.tap(find.text('Kaydet'));
    var satirlar = <Map<String, Object?>>[];
    for (var i = 0; i < 100 && satirlar.length < 2; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      satirlar = (await tester.runAsync(() =>
          db.query('cari_fiyatlar', where: 'ay = ?', whereArgs: [ay], orderBy: 'cari_id')))!;
    }
    expect(satirlar.map((r) => r['besi_yemi_fiyat']), [9.5, 9.5]);
    expect(satirlar.first['sut_yemi_fiyat'], 11, reason: 'Ali\'nin süt yemi fiyatı korunur');
    expect(satirlar.first['sut_fiyat'], 15, reason: 'süt fiyatına dokunulmaz');
    await tester.pump(const Duration(seconds: 10)); // bildirimler kapansın
    await tester.runAsync(() => db.close());
  });

  testWidgets('Excel\'den cari alma ⋮ menüsünde; Cariler Excel diyalogunda yok', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = (await tester.runAsync(testVeritabaniAc))!;
    await tester.pumpWidget(_uygulama(db, const AnaEkran()));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.more_vert));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text("Excel'den Cari İçeri Al"), findsOneWidget);
    await tester.tap(find.text("Excel'den Cari İçeri Al"));
    await _bekle(tester, () => gorunurMu("Excel'den Cari Al"), 'içe alma ekranı');

    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.text('Cariler'));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
      await tester.pump();
    }
    // Cariler ekranındaki Excel düğmesi (resimli IconButton).
    await tester.tap(find.descendant(of: find.byType(IconButton), matching: find.byType(Image)).hitTestable().first);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text("Excel'e Aktar"), findsOneWidget);
    expect(find.text("Excel'den Cari İçeri Al"), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    await tester.runAsync(() => db.close());
  });
}

bool gorunurMu(String metin) => find.textContaining(metin).evaluate().isNotEmpty;
