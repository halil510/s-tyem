import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/core/providers/database_provider.dart';
import 'package:sutyem_pro/ekranlar/ana_ekran.dart';
import 'package:sutyem_pro/ekranlar/app_activation_screen.dart';
import 'package:sutyem_pro/ekranlar/cari/cari_duzenle.dart';
import 'package:sutyem_pro/ekranlar/cari/pasif_cariler_ekrani.dart';
import 'package:sutyem_pro/ekranlar/cari/toplama_sirasi_ekrani.dart';
import 'package:sutyem_pro/ekranlar/cari_ekle.dart';
import 'package:sutyem_pro/ekranlar/detay_ekrani.dart';
import 'package:sutyem_pro/ekranlar/fiyat_hesaplama_ekrani.dart';
import 'package:sutyem_pro/ekranlar/fiyat_yonetim_ekrani.dart';
import 'package:sutyem_pro/ekranlar/hizli_sut_giris.dart';
import 'package:sutyem_pro/ekranlar/sut_ekrani.dart';
import 'package:sutyem_pro/ekranlar/sut_fiyat_ekrani.dart';
import 'package:sutyem_pro/ekranlar/yedekleme_ekrani.dart';
import 'package:sutyem_pro/ekranlar/yem_ekrani.dart';
import 'package:sutyem_pro/ekranlar/yem_fiyat_ekrani.dart';
import 'package:sutyem_pro/ekranlar/otomatik_yedekler_ekrani.dart';
import 'package:sutyem_pro/features/cari/cari_excel_ekrani.dart';
import 'package:sutyem_pro/features/cari_hesap/screens/cari_hesap_ekstresi_ekrani.dart';
import 'package:sutyem_pro/features/donem/donem_ekrani.dart';
import 'package:sutyem_pro/features/fis/fis_ekranlari.dart';
import 'package:sutyem_pro/features/terazi/providers/terazi_providers.dart';
import 'package:sutyem_pro/features/terazi/services/terazi_baglanti_durumu.dart';
import 'package:sutyem_pro/models/cari_model.dart';
import 'package:sutyem_pro/utils/tarih_format.dart';

import 'helpers/test_db.dart';

/// EKRAN TARAMASI: uygulamadaki her ekran, telefon genişliğinde (360 px),
/// gerçekçi veriyle açılır. Çizim hatası, taşma (overflow) ya da yakalanmamış
/// istisna varsa test kırılır. Yeni ekran eklenince buraya da eklenmeli.
class _SahteTerazi extends TeraziBaglantiNotifier {
  @override
  Future<bool> baslangicOtomatikBaglan() async => false;
}

late Database db;
late Cari ali;

Future<void> veriHazirla() async {
  db = await testVeritabaniAc();
  final f = DateFormat('yyyy-MM-dd');
  final n = DateTime.now();
  final buAy = DateFormat('yyyy-MM').format(n);
  final gecenAy = DateFormat('yyyy-MM').format(DateTime(n.year, n.month - 1));
  final idler = <int>[
    await cariEkle(db, ad: 'Ahmet', soyad: 'Yılmaz'),
    await cariEkle(db, ad: 'MEHMET ALİ', soyad: 'UZUNİSİMLİOĞULLARI BÜYÜKÇEKMECELİ'),
    await cariEkle(db, ad: 'Ayşe', soyad: 'Kaya'),
  ];
  await db.update('cariler', {'telefon': '05551234567', 'adres': 'Yeşilköy'}, where: 'id = ?', whereArgs: [idler[0]]);
  for (final id in idler) {
    for (final ay in [gecenAy, buAy]) {
      await fiyatTanimla(db, id, ay, sut: 18.5, sutYemi: 12, besiYemi: 11);
    }
    for (var g = 0; g < 20; g++) {
      final t = f.format(DateTime(n.year, n.month, n.day - g));
      await db.insert('sutler', {'cari_id': id, 'tarih': t, 'sabah': 1234.5, 'aksam': 987.25, 'toplam': 2221.75});
    }
    await db.insert('yemler', {
      'cari_id': id, 'tarih': f.format(n), 'sut_yemi': 50, 'besi_yemi': 25, 'b_baslangic': 5,
      'b_buyutme': 5, 'kuzu_yemi': 3, 'tavuk_yemi': 2, 'toplam': 90,
    });
    await db.insert('cari_odemeler', {
      'cari_id': id, 'tarih': f.format(n), 'islem_turu': 'odeme', 'toplam_tutar': 125000.5,
      'aciklama': 'Elden ödeme, uzun bir açıklama metni ekrana sığıyor mu',
    });
  }
  // Toplama rotası + bir pasif cari (rozetler, Pasif Cariler, Toplama Sırası).
  for (var i = 0; i < idler.length; i++) {
    await db.update('cariler', {'sira': 98 + i}, where: 'id = ?', whereArgs: [idler[i]]);
  }
  final pasif = await cariEkle(db, ad: 'HÜSEYİN HASAN', soyad: 'PASİFOĞULLARI UZUNSOYADLI');
  await db.update('cariler', {'aktif': 0, 'telefon': '05559998877'}, where: 'id = ?', whereArgs: [pasif]);
  await db.insert('cari_odemeler', {'cari_id': pasif, 'tarih': f.format(n), 'islem_turu': 'odeme', 'toplam_tutar': 98765.43});
  ali = Cari(
      id: idler[1], ad: 'MEHMET ALİ', soyad: 'UZUNİSİMLİOĞULLARI BÜYÜKÇEKMECELİ', telefon: '05551234567', sira: 99);
}

Widget uygulama(Widget ekran) => ProviderScope(
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

/// Ekranı açar, veri yüklenene kadar bekler; hata/taşma olursa test kırılır.
Future<void> ekranAc(WidgetTester tester, Widget ekran) async {
  await tester.pumpWidget(uygulama(ekran));
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump();
  }
  // Kaydırılabilir içeriğin altı da çizilsin.
  final kaydir = find.byType(Scrollable);
  if (kaydir.evaluate().isNotEmpty) {
    await tester.drag(kaydir.first, const Offset(0, -3000), warnIfMissed: false);
    await tester.pump();
  }
  final hata = tester.takeException();
  if (hata != null) {
    // ignore: avoid_print
    print(hata is FlutterError ? hata.toStringDeep() : '$hata');
  }
  expect(hata, isNull);
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5)); // animasyon/zamanlayıcılar bitsin
}

void main() {
  setUpAll(() async {
    await initializeTurkishLocale();
    await veriHazirla();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({'fis_isletme_adi': 'Kabatlı Süt Toplama Merkezi'});
  });

  Future<void> telefon(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  final ekranlar = <String, Widget Function()>{
    'Aktivasyon': () => const AppActivationScreen(),
    'Cari Ekle': () => const CariEkle(),
    'Cari Düzenle': () => CariDuzenle(cari: ali),
    'Cari Detay': () => DetayEkrani(cari: ali),
    'Hesap Ekstresi': () => CariHesapEkstresiEkrani(cari: ali),
    'Süt Girişi (tek cari)': () => SutGirisSayfasi(cari: ali),
    'Yem Girişi (tek cari)': () => YemGirisPage(cari: ali),
    'Hızlı Süt Girişi': () => const HizliSutGiris(),
    'Süt Fiyatları': () => const SutFiyatEkrani(),
    'Yem Fiyatları': () => const YemFiyatEkrani(),
    'Piyasa Fiyat Notları': () => const FiyatYonetimEkrani(),
    'Aylık Hesaplama & Rapor': () => const FiyatHesaplamaEkrani(),
    'Dönem Kapanışı': () => const DonemEkrani(),
    'Fiş Yazıcısı': () => const FisYaziciAyarlariEkrani(),
    'Excel\'den Cari Al': () => const CariExcelIceAktarmaEkrani(),
    'Yedekleme': () => const YedeklemeEkrani(),
    'Pasif Cariler': () => const PasifCarilerEkrani(),
    'Toplama Sırası (Rota)': () => const ToplamaSirasiEkrani(),
    'Otomatik Güvenlik Yedekleri': () => const OtomatikYedeklerEkrani(),
  };

  for (final e in ekranlar.entries) {
    testWidgets('ekran: ${e.key}', (tester) async {
      await telefon(tester);
      await ekranAc(tester, e.value());
    });
  }

  testWidgets('ana ekran: 5 sekme, panel yazıları her zaman görünür', (tester) async {
    await telefon(tester);
    await tester.pumpWidget(uygulama(const AnaEkran()));
    for (final ad in ['Özet', 'Cariler', 'Süt', 'Yem', 'Ödemeler']) {
      // Panel yazısı seçili olmasa da görünür.
      final yazi = find.descendant(of: find.byKey(const ValueKey('altPanel')), matching: find.text(ad));
      expect(yazi, findsOneWidget, reason: 'panelde "$ad" yazısı yok');
    }
    for (final ad in ['Özet', 'Cariler', 'Süt', 'Yem', 'Ödemeler']) {
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('altPanel')), matching: find.text(ad)));
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
        await tester.pump();
      }
      expect(tester.takeException(), isNull, reason: '$ad sekmesi');
      // Seçim değişse de 5 yazının hepsi panelde kalır.
      for (final diger in ['Özet', 'Cariler', 'Süt', 'Yem', 'Ödemeler']) {
        expect(find.descendant(of: find.byKey(const ValueKey('altPanel')), matching: find.text(diger)), findsOneWidget);
      }
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('⋮ menüsü dar ekranda taşmadan açılır', (tester) async {
    await telefon(tester);
    await tester.pumpWidget(uygulama(const AnaEkran()));
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
      await tester.pump();
    }
    await tester.tap(find.byIcon(Icons.more_vert));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    for (final oge in ['Hızlı Süt Girişi', "Excel'den Cari İçeri Al", 'Süt Fiyatları', 'Dönem Kapanışı & Hakediş', 'Fiş Yazıcısı', 'Yedekleme']) {
      expect(find.text(oge), findsOneWidget, reason: oge);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('boş veritabanında (ilk kurulum) ana ekran ve sekmeler', (tester) async {
    await telefon(tester);
    final dolu = db;
    db = (await tester.runAsync(() => testVeritabaniAc()))!;
    addTearDown(() => db = dolu);
    await tester.pumpWidget(uygulama(const AnaEkran()));
    for (final ad in ['Özet', 'Cariler', 'Süt', 'Yem', 'Ödemeler']) {
      await tester.tap(find.text(ad).last);
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
        await tester.pump();
      }
      expect(tester.takeException(), isNull, reason: 'boş veritabanı: $ad');
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  // ─── Farklı cihaz boyutları (2026-11-05): küçük telefon, yatay, tablet, büyük yazı ───
  const boyutlar = <String, (Size, double)>{
    'küçük telefon 320x568': (Size(320, 568), 1.0),
    'telefon yatay 760x360': (Size(760, 360), 1.0),
    'tablet dikey 800x1280': (Size(800, 1280), 1.0),
    'tablet yatay 1280x800': (Size(1280, 800), 1.0),
    'büyük yazı 360x760 x1.3': (Size(360, 760), 1.3),
  };
  for (final b in boyutlar.entries) {
    group('cihaz: ${b.key}', () {
      Future<void> boyutla(WidgetTester tester) async {
        await tester.binding.setSurfaceSize(b.value.$1);
        tester.platformDispatcher.textScaleFactorTestValue = b.value.$2;
        addTearDown(() {
          tester.binding.setSurfaceSize(null);
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
      }

      for (final e in ekranlar.entries) {
        testWidgets(e.key, (tester) async {
          await boyutla(tester);
          await ekranAc(tester, e.value());
        });
      }
      testWidgets('ana ekran sekmeleri', (tester) async {
        await boyutla(tester);
        await tester.pumpWidget(uygulama(const AnaEkran()));
        for (final ad in ['Özet', 'Cariler', 'Süt', 'Yem', 'Ödemeler']) {
          await tester.tap(find.descendant(of: find.byKey(const ValueKey('altPanel')), matching: find.text(ad)));
          for (var i = 0; i < 30; i++) {
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
            await tester.pump();
          }
          final hata = tester.takeException();
          if (hata != null) {
            // ignore: avoid_print
            print(hata is FlutterError ? hata.toStringDeep() : '$hata');
          }
          expect(hata, isNull, reason: '$ad sekmesi');
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 5));
      });
    });
  }
}
