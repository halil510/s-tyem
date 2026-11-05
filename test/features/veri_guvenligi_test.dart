// Veri güvenliği (2026-11-05 derin tarama: şarj biterse / kilitlenirse veri
// kaybı olmasın): otomatik güvenlik yedeği, tek adımda .db değiştirme,
// tutarlı .db kopyası, Hızlı Süt Girişi taslağı, çift dokunma korumaları.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/core/database/app_database.dart';
import 'package:sutyem_pro/core/providers/database_provider.dart';
import 'package:sutyem_pro/data/repositories/veri_yonetimi_repository.dart';
import 'package:sutyem_pro/data/yedek/otomatik_yedek.dart';
import 'package:sutyem_pro/data/yedek/yedek_servisi.dart';
import 'package:sutyem_pro/ekranlar/hizli_sut_giris.dart';
import 'package:sutyem_pro/ekranlar/yem_ekrani.dart';
import 'package:sutyem_pro/models/cari_model.dart';
import 'package:sutyem_pro/utils/tarih_format.dart';

import '../helpers/test_db.dart';

Future<int> _say(Database db, String tablo) async =>
    Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $tablo'))!;

Future<void> _bekle(WidgetTester tester, bool Function() kosul, {String? aciklama}) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
    if (kosul()) return;
  }
  fail('Zaman aşımı: ${aciklama ?? 'koşul sağlanmadı'}');
}

Widget _uygulama(Database db, Widget ekran) => ProviderScope(
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

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    await initializeTurkishLocale();
  });

  group('Otomatik güvenlik yedeği', () {
    late Directory klasor;
    late Database db;

    setUp(() async {
      klasor = await Directory.systemTemp.createTemp('otomatik_yedek_');
      db = await testVeritabaniAc();
      final ali = await cariEkle(db, ad: 'Ali');
      await db.insert('sutler', {'cari_id': ali, 'tarih': '2026-11-01', 'sabah': 20, 'aksam': 18, 'toplam': 38});
      await db.insert('yemler', {'cari_id': ali, 'tarih': '2026-11-02', 'sut_yemi': 50, 'toplam': 50});
      await db.insert('cari_odemeler', {
        'cari_id': ali, 'tarih': '2026-11-03', 'islem_turu': 'odeme',
        'miktar': 1, 'birim_fiyat': 100, 'toplam_tutar': 100,
      });
    });
    tearDown(() async {
      await db.close();
      try {
        await klasor.delete(recursive: true);
      } catch (_) {}
    });

    test('yedek tam ve okunur; listede tarih ve sebebiyle görünür', () async {
      final y = OtomatikYedek(db, klasor);
      final dosya = await y.al(YedekSebebi.islemOncesi, aciklama: 'sut_yem_silme', simdi: DateTime(2026, 11, 5, 9, 30, 15));
      expect(p.basename(dosya.path), 'sutyem_2026-11-05_09-30-15_islem_sut_yem_silme.json');

      final veri = YedekServisi.coz(await dosya.readAsString());
      expect(YedekServisi.tamYedekMi(veri), isTrue);
      expect(veri['sutler'], hasLength(1));
      expect(veri['cari_odemeler'], hasLength(1));

      final liste = await y.listele();
      expect(liste, hasLength(1));
      expect(liste.single.tarih, DateTime(2026, 11, 5, 9, 30, 15));
      expect(liste.single.sebep, YedekSebebi.islemOncesi);
      expect(liste.single.aciklama, 'sut_yem_silme');
      expect(OtomatikYedek.islemEtiketi(liste.single.aciklama), 'Süt/yem silme öncesi');
    });

    test('toplu silmeden sonra güvenlik yedeğine dönünce HER ŞEY geri gelir', () async {
      final y = OtomatikYedek(db, klasor);
      final dosya = await y.al(YedekSebebi.islemOncesi, aciklama: 'sut_yem_silme');
      await VeriYonetimiRepository(db).sutVeYemSil();
      expect(await _say(db, 'sutler'), 0);

      await VeriYonetimiRepository(db)
          .yedekYukle(YedekServisi.coz(await dosya.readAsString()), tamamenDegistir: true);
      expect(await _say(db, 'sutler'), 1);
      expect(await _say(db, 'yemler'), 1);
      expect(await _say(db, 'cari_odemeler'), 1);
    });

    test('otomatik yedek en çok 4 saatte bir alınır', () async {
      final y = OtomatikYedek(db, klasor);
      final t0 = DateTime(2026, 11, 5, 8);
      expect(await y.gerekirseAl(simdi: t0), isNotNull);
      expect(await y.gerekirseAl(simdi: t0.add(const Duration(hours: 1))), isNull);
      expect(await y.gerekirseAl(simdi: t0.add(const Duration(hours: 4))), isNotNull);
      // İşlem öncesi yedek otomatik sayacı etkilemez.
      await y.al(YedekSebebi.islemOncesi, aciklama: 'cari_silme', simdi: t0.add(const Duration(hours: 5)));
      expect(await y.gerekirseAl(simdi: t0.add(const Duration(hours: 5))), isNull);
      expect((await y.listele()).where((e) => e.sebep == YedekSebebi.otomatik), hasLength(2));
    });

    test('eski yedekler silinir: son 15 otomatik + 10 işlem öncesi kalır, en yeniler', () async {
      final y = OtomatikYedek(db, klasor);
      final t0 = DateTime(2026, 11, 1);
      for (var i = 0; i < 18; i++) {
        await y.al(YedekSebebi.otomatik, simdi: t0.add(Duration(hours: i)));
      }
      for (var i = 0; i < 12; i++) {
        await y.al(YedekSebebi.islemOncesi, aciklama: 'cari_silme', simdi: t0.add(Duration(minutes: i)));
      }
      final liste = await y.listele();
      final oto = liste.where((e) => e.sebep == YedekSebebi.otomatik).toList();
      final islem = liste.where((e) => e.sebep == YedekSebebi.islemOncesi).toList();
      expect(oto, hasLength(OtomatikYedek.otomatikSakla));
      expect(islem, hasLength(OtomatikYedek.islemOncesiSakla));
      expect(oto.first.tarih, t0.add(const Duration(hours: 17)), reason: 'en yeni korunur');
      expect(oto.last.tarih, t0.add(const Duration(hours: 3)), reason: 'en eski 3 silindi');
    });

    test('aynı saniyede iki yedek birbirinin üzerine yazmaz', () async {
      final y = OtomatikYedek(db, klasor);
      final t = DateTime(2026, 11, 5, 10);
      final a = await y.al(YedekSebebi.islemOncesi, simdi: t);
      final b = await y.al(YedekSebebi.islemOncesi, simdi: t);
      expect(a.path, isNot(b.path));
      expect(await y.listele(), hasLength(2));
    });

    test('şarj bitip yarım kalan .tmp yedek sayılmaz ve temizlenir', () async {
      final y = OtomatikYedek(db, klasor);
      await klasor.create(recursive: true);
      final yarim = File(p.join(klasor.path, 'sutyem_2026-11-05_10-00-00_otomatik.json.tmp'))
        ..writeAsStringSync('{"meta": {"app": "sut_y');
      expect(await y.listele(), isEmpty);
      await y.al(YedekSebebi.otomatik);
      expect(yarim.existsSync(), isFalse);
      expect(await y.listele(), hasLength(1));
    });

    test('yedek yazılırken bile tutarlı: tablolar tek transaction içinde okunur', () async {
      // Yedek alınırken araya giren bir yazma yedeği yarım bırakmaz: ya
      // yazmadan önceki ya sonraki hali içerir (sutler ile toplam tutarlı).
      final yedekGelecek = YedekServisi.disaAktarJson(db);
      final yazma = db.insert('sutler', {'cari_id': 1, 'tarih': '2026-11-04', 'sabah': 5, 'aksam': 0, 'toplam': 5});
      final veri = jsonDecode(await yedekGelecek) as Map<String, dynamic>;
      await yazma;
      final sut = (veri['sutler'] as List).length;
      expect((veri['meta']['tables'] as Map)['sutler'], sut);
    });
  });

  group('Veritabanı dosyası (geri yükleme / .db yedeği)', () {
    late Directory klasor;
    setUp(() async => klasor = await Directory.systemTemp.createTemp('sutyem_dosya_'));
    tearDown(() async {
      try {
        await klasor.delete(recursive: true);
      } catch (_) {}
    });

    AppDatabase ac() => AppDatabase.test(factory: databaseFactoryFfi, klasor: klasor.path);

    test('tutarlı .db kopyası: kayıtları içerir ve sağlam', () async {
      final app = ac();
      final db = await app.database;
      await cariEkle(db, ad: 'Ali');
      final hedef = p.join(klasor.path, 'kopya.db');
      await app.tutarliKopyala(hedef);
      await VeriYonetimiRepository.dbDosyasiniDogrula(hedef, factory: databaseFactoryFfi);
      final kopya = await databaseFactoryFfi.openDatabase(hedef, options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
      expect(await _say(kopya, 'cariler'), 1);
      await kopya.close();
      await app.close();
    });

    test('dosya değiştirilirken gelen çağrı ESKİ dosyayı açmaz, yeni dosyayı bekler', () async {
      // Yeni (geri yüklenecek) veritabanı: 2 cari.
      final kaynakApp = AppDatabase.test(factory: databaseFactoryFfi, klasor: p.join(klasor.path, 'kaynak'));
      final kaynakDb = await kaynakApp.database;
      await cariEkle(kaynakDb, ad: 'Yeni1');
      await cariEkle(kaynakDb, ad: 'Yeni2');
      await kaynakApp.close();
      final kaynak = File(p.join(klasor.path, 'kaynak', AppDatabase.dbAdi));

      // Mevcut veritabanı: 1 cari.
      final app = ac();
      await cariEkle(await app.database, ad: 'Eski');

      Future<Database>? aradaGelen;
      await app.dosyayiDegistir((yol) async {
        aradaGelen = app.database; // başka bir ekranın çağrısı
        final gecici = File('$yol.geri_yukleme');
        await kaynak.copy(gecici.path);
        await AppDatabase.dosyayiYerineKoy(gecici, yol);
      });
      final db = await aradaGelen!;
      expect((await db.query('cariler', orderBy: 'id')).map((c) => c['ad']), ['Yeni1', 'Yeni2']);
      expect(File(p.join(klasor.path, '${AppDatabase.dbAdi}.geri_yukleme')).existsSync(), isFalse);
      await app.close();
    });

    test('dosyayiYerineKoy: hedef hiçbir an yok olmaz, eski günlük ekleri temizlenir', () async {
      final hedef = p.join(klasor.path, 'a.db');
      File(hedef).writeAsStringSync('ESKI');
      File('$hedef-journal').writeAsStringSync('eski gunluk');
      final kaynak = File(p.join(klasor.path, 'b.tmp'))..writeAsStringSync('YENI');
      await AppDatabase.dosyayiYerineKoy(kaynak, hedef);
      expect(File(hedef).readAsStringSync(), 'YENI');
      expect(File('$hedef-journal').existsSync(), isFalse);
      expect(kaynak.existsSync(), isFalse);
    });
  });

  group('Hızlı Süt Girişi taslağı (şarj biterse girilenler kaybolmasın)', () {
    late Database db;
    late int ali;
    late int veli;
    final b = DateTime.now();
    final bugun = '${b.year}-${b.month.toString().padLeft(2, '0')}-${b.day.toString().padLeft(2, '0')}';

    Future<void> hazirla(WidgetTester tester) async {
      await tester.runAsync(() async {
        db = await testVeritabaniAc();
        ali = await cariEkle(db, ad: 'Ali', soyad: 'Kaya');
        veli = await cariEkle(db, ad: 'Veli', soyad: 'Demir');
      });
    }

    Future<String?> taslak(WidgetTester tester) async =>
        (await tester.runAsync<String?>(() async => (await SharedPreferences.getInstance()).getString('hizli_sut_taslak')));

    testWidgets('girilen değer kaydedilmeden telefona taslak olarak yazılır', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await hazirla(tester);
      await tester.pumpWidget(_uygulama(db, const HizliSutGiris()));
      await _bekle(tester, () => find.text('Ali Kaya').evaluate().isNotEmpty);

      await tester.enterText(find.byType(TextField).at(1), '20,5'); // Ali sabah
      String? t;
      for (var i = 0; i < 30 && t == null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        t = await taslak(tester);
      }
      expect(t, isNotNull);
      final v = jsonDecode(t!) as Map<String, dynamic>;
      expect(v['tarih'], bugun);
      expect((v['sabah'] as Map)['$ali'], '20,5');
    });

    testWidgets('uygulama kapanmış olsa bile taslak bir sonraki açılışta geri gelir', (tester) async {
      await hazirla(tester);
      SharedPreferences.setMockInitialValues({
        'hizli_sut_taslak': jsonEncode({
          'tarih': bugun,
          'sabah': {'$ali': '25'},
          'aksam': {'$veli': '12,5'},
        }),
      });
      await tester.pumpWidget(_uygulama(db, const HizliSutGiris()));
      await _bekle(tester, () => find.textContaining('KAYDEDİLMEMİŞ 2 giriş').evaluate().isNotEmpty,
          aciklama: 'taslak geri getirilmedi');
      expect(find.widgetWithText(TextField, '25'), findsOneWidget);
      expect(find.widgetWithText(TextField, '12,5'), findsOneWidget);
      expect(await tester.runAsync(() => db.query('sutler')), isEmpty, reason: 'taslak kendiliğinden KAYDEDİLMEZ');

      await tester.tap(find.byTooltip('Tümünü Kaydet'));
      await _bekle(tester, () => find.textContaining('Kaydedildi').evaluate().isNotEmpty);
      final s = (await tester.runAsync(() => db.query('sutler', orderBy: 'cari_id')))!;
      expect(s.map((r) => r['toplam']), [25, 12.5]);
      await _bekle(tester, () => true);
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      expect(await taslak(tester), isNull, reason: 'kaydedince taslak silinir');
    });

    testWidgets('kayıtlı (kilitli) öğüne taslak YAZILMAZ', (tester) async {
      await hazirla(tester);
      await tester.runAsync(() => db.insert('sutler',
          {'cari_id': ali, 'tarih': bugun, 'sabah': 20, 'aksam': 0, 'toplam': 20}));
      SharedPreferences.setMockInitialValues({
        'hizli_sut_taslak': jsonEncode({
          'tarih': bugun,
          'sabah': {'$ali': '99'},
          'aksam': <String, String>{},
        }),
      });
      await tester.pumpWidget(_uygulama(db, const HizliSutGiris()));
      await _bekle(tester, () => find.text('Kayıtlı · 20 kg').evaluate().isNotEmpty);
      expect(find.text('99'), findsNothing);
      expect(find.textContaining('KAYDEDİLMEMİŞ'), findsNothing);
    });
  });

  testWidgets('Yem: KAYDET\'e çift dokunma yemi İKİ KEZ yazmaz', (tester) async {
    late Database db;
    late int ali;
    await tester.runAsync(() async {
      db = await testVeritabaniAc();
      ali = await cariEkle(db, ad: 'Ali', soyad: 'Kaya');
    });
    await tester.pumpWidget(_uygulama(db, YemGirisPage(cari: Cari(id: ali, ad: 'Ali', soyad: 'Kaya'))));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField).first, '50');
    await tester.pump();
    final kaydet = find.text('KAYDET');
    await tester.ensureVisible(kaydet);
    await tester.pump();
    await tester.tap(kaydet, warnIfMissed: false);
    await tester.tap(kaydet, warnIfMissed: false); // aynı karede ikinci dokunma
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(await tester.runAsync(() => _say(db, 'yemler')), 1);
  });
}
