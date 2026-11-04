import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/core/providers/database_provider.dart';
import 'package:sutyem_pro/ekranlar/hizli_sut_giris.dart';
import 'package:sutyem_pro/ekranlar/sut_ekrani.dart';
import 'package:sutyem_pro/features/cari_hesap/widgets/odeme_al_bottom_sheet.dart';
import 'package:sutyem_pro/features/terazi/providers/terazi_providers.dart';
import 'package:sutyem_pro/features/terazi/services/terazi_baglanti_durumu.dart';
import 'package:sutyem_pro/models/cari_model.dart';
import 'package:sutyem_pro/utils/tarih_format.dart';

import 'helpers/test_db.dart';

/// Gerçek ekranlar + gerçek (bellek-içi) SQLite ile kullanıcı akışları.
///
/// Veritabanı gerçek G/Ç yaptığı için bekleme [tester.runAsync] içinde
/// yapılır; [_bekle] koşul sağlanana kadar kare (frame) basar.

class _SahteTeraziNotifier extends TeraziBaglantiNotifier {
  @override
  Future<bool> baslangicOtomatikBaglan() async => false;
}

Future<void> _bekle(WidgetTester tester, bool Function() kosul, {String? aciklama}) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    if (kosul()) return;
  }
  fail('Zaman aşımı: ${aciklama ?? 'koşul sağlanmadı'}');
}

Widget _uygulama(Database db, Widget ekran, {Stream<String>? agirlik, TeraziBaglantiDurumu? terazi}) {
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWith((ref) => db),
      teraziDurumStreamProvider.overrideWith(
          (ref) => Stream.value(terazi ?? TeraziBaglantiDurumu.bagliDegil)),
      teraziAgirlikStreamProvider.overrideWith((ref) => agirlik ?? const Stream.empty()),
      teraziBaglantiNotifierProvider.overrideWith(_SahteTeraziNotifier.new),
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
}

void main() {
  setUpAll(initializeTurkishLocale);

  late Database db;
  late int ali;
  late int veli;
  final bugun = DateTime.now();
  final bugunStr = '${bugun.year.toString().padLeft(4, '0')}-${bugun.month.toString().padLeft(2, '0')}-'
      '${bugun.day.toString().padLeft(2, '0')}';

  Future<void> hazirla(WidgetTester tester) async {
    await tester.runAsync(() async {
      db = await testVeritabaniAc();
      ali = await cariEkle(db, ad: 'Ali', soyad: 'Kaya');
      veli = await cariEkle(db, ad: 'Veli', soyad: 'Demir');
    });
  }

  Future<List<Map<String, Object?>>> sutler(WidgetTester tester) async =>
      (await tester.runAsync(() => db.query('sutler', orderBy: 'cari_id')))!;

  group('Hızlı Süt Girişi', () {
    // Alan sırası: [0] arama, sonra cari başına (ad sırasıyla) sabah, akşam.
    Finder alan(int i) => find.byType(TextField).at(i);

    testWidgets('girilen değerler tek seferde kaydedilir', (tester) async {
      await hazirla(tester);
      await tester.pumpWidget(_uygulama(db, const HizliSutGiris()));
      await _bekle(tester, () => find.text('Ali Kaya').evaluate().isNotEmpty, aciklama: 'cariler yüklenmedi');

      await tester.enterText(alan(1), '20,5'); // Ali sabah
      await tester.enterText(alan(2), '18'); // Ali akşam
      await tester.enterText(alan(3), '30'); // Veli sabah
      await tester.tap(find.text('Tümünü Kaydet'));
      await _bekle(tester, () => find.textContaining('Kaydedildi').evaluate().isNotEmpty,
          aciklama: 'kayıt mesajı çıkmadı');

      final s = await sutler(tester);
      expect(s, hasLength(2));
      expect(s[0]['cari_id'], ali);
      expect(s[0]['tarih'], bugunStr);
      expect(s[0]['toplam'], 38.5);
      expect(s[1]['cari_id'], veli);
      expect(s[1]['toplam'], 30);
    });

    testWidgets('geçersiz miktar varsa HİÇBİR kayıt yapılmaz', (tester) async {
      await hazirla(tester);
      await tester.pumpWidget(_uygulama(db, const HizliSutGiris()));
      await _bekle(tester, () => find.text('Ali Kaya').evaluate().isNotEmpty);

      await tester.enterText(alan(1), '20');
      await tester.enterText(alan(3), '12,5x'); // Veli sabah — hatalı
      await tester.tap(find.text('Tümünü Kaydet'));
      await _bekle(tester, () => find.textContaining('geçersiz miktar').evaluate().isNotEmpty);

      expect(find.text('Geçersiz miktar'), findsOneWidget); // satır işareti
      expect(await sutler(tester), isEmpty);
    });

    testWidgets('mevcut kayıt yüklenir ve güncellenir, mükerrer oluşmaz', (tester) async {
      await hazirla(tester);
      await tester.runAsync(() => db.insert('sutler',
          {'cari_id': ali, 'tarih': bugunStr, 'sabah': 20, 'aksam': 0, 'toplam': 20}));
      await tester.pumpWidget(_uygulama(db, const HizliSutGiris()));
      await _bekle(tester, () => find.text('Kayıtlı · 20 kg').evaluate().isNotEmpty);

      expect(tester.widget<TextField>(alan(1)).controller!.text, '20');
      await tester.enterText(alan(2), '17'); // akşamı ekle
      await tester.tap(find.text('Tümünü Kaydet'));
      await _bekle(tester, () => find.textContaining('1 güncellendi').evaluate().isNotEmpty);

      final s = await sutler(tester);
      expect(s, hasLength(1));
      expect(s.single['toplam'], 37);
    });
  });

  group('Süt Ekle (tek cari)', () {
    Cari cariNesnesi() => Cari(id: ali, ad: 'Ali', soyad: 'Kaya');

    testWidgets('aynı güne ikinci giriş mevcut kaydı günceller', (tester) async {
      await hazirla(tester);
      await tester.runAsync(() => db.insert('sutler',
          {'cari_id': ali, 'tarih': bugunStr, 'sabah': 20, 'aksam': 0, 'toplam': 20}));
      await tester.pumpWidget(_uygulama(db, SutGirisSayfasi(cari: cariNesnesi())));
      await _bekle(tester, () => find.textContaining('Bu tarihte kayıt var').evaluate().isNotEmpty);
      expect(find.text('GÜNCELLE'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Akşam Sütü (kg)'), '18');
      await tester.ensureVisible(find.text('GÜNCELLE'));
      await tester.pump();
      await tester.tap(find.text('GÜNCELLE'));
      await _bekle(tester, () => find.textContaining('güncellendi').evaluate().isNotEmpty);

      final s = await sutler(tester);
      expect(s, hasLength(1));
      expect(s.single['sabah'], 20);
      expect(s.single['aksam'], 18);
    });

    testWidgets('REGRESYON: terazi okuması girilmiş sabah değerini EZMEZ', (tester) async {
      await hazirla(tester);
      final agirlik = StreamController<String>();
      await tester.pumpWidget(_uygulama(
        db,
        SutGirisSayfasi(cari: cariNesnesi()),
        agirlik: agirlik.stream,
        terazi: TeraziBaglantiDurumu.bagli,
      ));
      await _bekle(tester, () => find.text('KAYDET').evaluate().isNotEmpty);

      final sabahAlani = find.widgetWithText(TextField, 'Sabah Sütü (kg)');
      await tester.enterText(sabahAlani, '25');
      FocusManager.instance.primaryFocus?.unfocus();
      agirlik.add('3.40'); // akşam sütü tartılıyor
      await _bekle(tester, () => find.text('3.40').evaluate().isNotEmpty);

      expect(tester.widget<TextField>(sabahAlani).controller!.text, '25');
      await agirlik.close();
    });

    /// Süt Ekle'yi bir "Aç" düğmesinin üstüne itilmiş sayfa olarak açar
    /// (geri tuşunun gerçekten bir önceki ekrana dönmesi için).
    Future<void> sayfaAc(WidgetTester tester) async {
      await tester.pumpWidget(_uygulama(
        db,
        Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(ctx).push(
                    MaterialPageRoute(builder: (_) => SutGirisSayfasi(cari: cariNesnesi()))),
                child: const Text('Aç'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Aç'));
      await _bekle(tester, () => find.text('KAYDET').evaluate().isNotEmpty);
    }

    Future<void> geriTusu(WidgetTester tester) async {
      await tester.binding.handlePopRoute(); // cihazın geri tuşu
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('geri tuşu: giriş yoksa doğrudan çıkar', (tester) async {
      await hazirla(tester);
      await sayfaAc(tester);
      await geriTusu(tester);
      expect(find.text('Süt kaydedilmedi'), findsNothing);
      expect(find.text('Aç'), findsOneWidget);
    });

    testWidgets('geri tuşu: kaydedilmemiş süt varsa sorar; "Vazgeç" ekranda tutar, '
        '"Kaydetmeden Çık" kaydetmeden çıkar', (tester) async {
      await hazirla(tester);
      await sayfaAc(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Sabah Sütü (kg)'), '25');
      await tester.pump();

      await geriTusu(tester);
      expect(find.text('Süt kaydedilmedi'), findsOneWidget);
      await tester.tap(find.text('Vazgeç'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Sabah Sütü (kg)'), findsOneWidget, reason: 'ekranda kaldı');
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Sabah Sütü (kg)')).controller!.text, '25');

      await geriTusu(tester);
      await tester.tap(find.text('Kaydetmeden Çık'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Aç'), findsOneWidget);
      expect(await sutler(tester), isEmpty);
    });

    testWidgets('geri tuşu: "Kaydet" seçilirse kaydedip çıkar', (tester) async {
      await hazirla(tester);
      await sayfaAc(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Akşam Sütü (kg)'), '18,5');
      await tester.pump();

      await geriTusu(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
      await _bekle(tester, () => find.text('Aç').evaluate().isNotEmpty, aciklama: 'kaydedip döndü');
      expect((await sutler(tester)).single['aksam'], 18.5);
    });

    testWidgets('terazi kartı en altta: miktar alanları ve KAYDET onun üstünde', (tester) async {
      await hazirla(tester);
      await tester.pumpWidget(_uygulama(db, SutGirisSayfasi(cari: cariNesnesi())));
      await _bekle(tester, () => find.text('KAYDET').evaluate().isNotEmpty);

      final terazi = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_CanliTeraziKarti');
      expect(terazi, findsOneWidget);
      final aksam = find.widgetWithText(TextField, 'Akşam Sütü (kg)');
      final kaydet = find.text('KAYDET');
      final fis = find.text('KAYDET + FİŞ VER');
      expect(tester.getTopLeft(aksam).dy, lessThan(tester.getTopLeft(kaydet).dy));
      expect(tester.getTopLeft(kaydet).dy, lessThan(tester.getTopLeft(fis).dy));
      expect(tester.getTopLeft(fis).dy, lessThan(tester.getTopLeft(terazi).dy),
          reason: 'klavye açıkken KAYDET görünsün diye terazi en alta alındı');
      // Alana odaklanınca KAYDET düğmeleri de klavyenin üstüne kayar.
      expect(tester.widget<TextField>(aksam).scrollPadding.bottom, greaterThanOrEqualTo(150));
    });

    testWidgets('hatalı miktar kaydedilmez, alan hata gösterir', (tester) async {
      await hazirla(tester);
      await tester.pumpWidget(_uygulama(db, SutGirisSayfasi(cari: cariNesnesi())));
      await _bekle(tester, () => find.text('KAYDET').evaluate().isNotEmpty);

      await tester.enterText(find.widgetWithText(TextField, 'Sabah Sütü (kg)'), '2O'); // O harfi
      await tester.ensureVisible(find.text('KAYDET'));
      await tester.pump();
      await tester.tap(find.text('KAYDET'));
      await tester.pump();

      expect(find.text('Geçersiz miktar'), findsOneWidget);
      expect(await sutler(tester), isEmpty);
    });

    testWidgets('KAYDET + FİŞ VER: kaydeder ve günün fişini önizletir', (tester) async {
      SharedPreferences.setMockInitialValues({'fis_isletme_adi': 'Test Süt'});
      await hazirla(tester);
      await tester.pumpWidget(_uygulama(db, SutGirisSayfasi(cari: cariNesnesi())));
      await _bekle(tester, () => find.text('KAYDET + FİŞ VER').evaluate().isNotEmpty);

      await tester.enterText(find.widgetWithText(TextField, 'Sabah Sütü (kg)'), '20,5');
      await tester.enterText(find.widgetWithText(TextField, 'Akşam Sütü (kg)'), '18');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.ensureVisible(find.text('KAYDET + FİŞ VER'));
      await tester.pump();
      await tester.tap(find.text('KAYDET + FİŞ VER'));
      await _bekle(tester, () => find.text('Üretici Fişi').evaluate().isNotEmpty, aciklama: 'fiş açıldı');

      expect((await sutler(tester)).single['toplam'], 38.5);
      expect(find.textContaining('38,5 kg'), findsWidgets);
      expect(find.textContaining('Ali Kaya'), findsWidgets);
      expect(find.text('Test Süt'), findsOneWidget);
      expect(find.text('Yazıcı Seç'), findsOneWidget, reason: 'yazıcı seçilmemiş');
      expect(find.text('Telefon yok'), findsOneWidget);
    });
  });

  group('Ödeme girişi', () {
    testWidgets('tutar, tarih ve açıklama döner; geçersiz tutar reddedilir', (tester) async {
      NakitHareketGirdisi? sonuc;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('tr', 'TR'),
        supportedLocales: const [Locale('tr', 'TR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                sonuc = await showModalBottomSheet<NakitHareketGirdisi>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const OdemeAlBottomSheet(cariAdi: 'Ali Kaya', baslik: 'Ödeme Yap'),
                );
              },
              child: const Text('aç'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'abc');
      await tester.tap(find.text('Onayla'));
      await tester.pump();
      expect(find.text('Geçerli bir tutar girin'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '1.250,50');
      await tester.enterText(find.byType(TextField).last, 'Mayıs süt parası');
      await tester.tap(find.text('Onayla'));
      await tester.pumpAndSettle();

      expect(sonuc, isNotNull);
      expect(sonuc!.tutar, 1250.5);
      expect(sonuc!.aciklama, 'Mayıs süt parası');
      expect(DateUtils.isSameDay(sonuc!.tarih, DateTime.now()), isTrue);
    });
  });
}
