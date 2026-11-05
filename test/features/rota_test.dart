// Süt toplama rotası (cariler.sira, migration v12), Cari Ekle / Düzenle sırası,
// pasife alma ve Pasif Cariler'den geri getirme (2026-11-05).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/core/providers/database_provider.dart';
import 'package:sutyem_pro/data/repositories/cari_repository.dart';
import 'package:sutyem_pro/ekranlar/cari/cari_duzenle.dart';
import 'package:sutyem_pro/ekranlar/cari/pasif_cariler_ekrani.dart';
import 'package:sutyem_pro/ekranlar/cari/toplama_sirasi_ekrani.dart';
import 'package:sutyem_pro/ekranlar/cari_ekle.dart';
import 'package:sutyem_pro/models/cari_model.dart';
import 'package:sutyem_pro/utils/tarih_format.dart';

import '../helpers/test_db.dart';

void main() {
  setUpAll(initializeTurkishLocale);

  group('CariRepository rota', () {
    late Database db;
    late CariRepository repo;
    setUp(() async {
      db = await testVeritabaniAc();
      repo = CariRepository(db);
    });
    tearDown(() => db.close());

    Future<List<String>> rota() async =>
        [for (final c in await repo.getAll(sadeceAktif: true)) '${c.sira ?? '-'} ${c.tamAd}'];

    test('kullanıcı örneği: Ahmet Atağ 1 verilince Ahmet Anıl 2\'ye kayar', () async {
      final anil = await repo.insert(Cari(ad: 'AHMET', soyad: 'ANIL'), sira: 1);
      final atag = await repo.insert(Cari(ad: 'AHMET', soyad: 'ATAĞ'), sira: 2);
      expect(await rota(), ['1 AHMET ANIL', '2 AHMET ATAĞ']);

      await repo.siraAta(atag, 1);
      expect(await rota(), ['1 AHMET ATAĞ', '2 AHMET ANIL']);
      expect((await repo.getById(anil))!.sira, 2);
    });

    test('araya ekleme sonrakileri kaydırır; numaralar 1..N boşluksuz', () async {
      for (final ad in ['A', 'B', 'C', 'D']) {
        await repo.insert(Cari(ad: ad, soyad: 'X'), sira: 99); // en sona
      }
      expect(await rota(), ['1 A X', '2 B X', '3 C X', '4 D X']);
      final e = await repo.insert(Cari(ad: 'E', soyad: 'X'), sira: 2);
      expect(await rota(), ['1 A X', '2 E X', '3 B X', '4 C X', '5 D X']);
      await repo.siraAta(e, 5); // sona taşı
      expect(await rota(), ['1 A X', '2 B X', '3 C X', '4 D X', '5 E X']);
      await repo.siraAta(e, null); // rotadan çıkar → sırasız, en sonda
      expect(await rota(), ['1 A X', '2 B X', '3 C X', '4 D X', '- E X']);
    });

    test('sırasızlar sıralıların ardından Türk alfabesiyle', () async {
      await repo.insert(Cari(ad: 'ZEKİ', soyad: 'A'));
      await repo.insert(Cari(ad: 'ÇETİN', soyad: 'B'));
      await repo.insert(Cari(ad: 'VELİ', soyad: 'C'), sira: 1);
      expect(await rota(), ['1 VELİ C', '- ÇETİN B', '- ZEKİ A']);
    });

    test('pasife alınca rotadan çıkar, kalanlar yeniden numaralanır; geri getirince istenen sıraya girer', () async {
      final a = await repo.insert(Cari(ad: 'A', soyad: 'X'), sira: 1);
      final b = await repo.insert(Cari(ad: 'B', soyad: 'X'), sira: 2);
      await repo.insert(Cari(ad: 'C', soyad: 'X'), sira: 3);
      await repo.pasifeAl(b);
      expect(await rota(), ['1 A X', '2 C X']);
      expect((await repo.getById(b))!.sira, isNull);

      await repo.aktifYap(b, sira: 1);
      expect(await rota(), ['1 B X', '2 A X', '3 C X']);
      await repo.pasifeAl(a);
      await repo.aktifYap(a); // sırasız geri gelir
      expect(await rota(), ['1 B X', '2 C X', '- A X']);
    });

    test('update: bilgiler + sıra + pasif TEK işlemde; cari.sira alanı yok sayılır', () async {
      final a = await repo.insert(Cari(ad: 'A', soyad: 'X'), sira: 1);
      final b = await repo.insert(Cari(ad: 'B', soyad: 'X'), sira: 2);
      // Eski nesnedeki sira (5) yazılmaz.
      await repo.update(Cari(id: a, ad: 'A2', soyad: 'X', sira: 5));
      expect(await rota(), ['1 A2 X', '2 B X']);
      await repo.update(Cari(id: b, ad: 'B', soyad: 'X'), siraGuncelle: true, sira: 1);
      expect(await rota(), ['1 B X', '2 A2 X']);
      await repo.update(Cari(id: b, ad: 'B', soyad: 'X', aktif: false));
      expect(await rota(), ['1 A2 X']);
    });

    test('rotaKaydet: verilen sırayla 1..N, listede olmayan sırasız', () async {
      final a = await repo.insert(Cari(ad: 'A', soyad: 'X'), sira: 1);
      final b = await repo.insert(Cari(ad: 'B', soyad: 'X'), sira: 2);
      final c = await repo.insert(Cari(ad: 'C', soyad: 'X'));
      await repo.rotaKaydet([c, a]);
      expect(await rota(), ['1 C X', '2 A X', '- B X']);
      expect(await repo.rotadakiSayi(), 2);
      expect(b, isPositive);
    });

    test('Excel\'den toplu ekleme sırasız ekler, rotayı bozmaz', () async {
      await repo.insert(Cari(ad: 'A', soyad: 'X'), sira: 1);
      await repo.topluEkle([Cari(ad: 'B', soyad: 'X'), Cari(ad: 'C', soyad: 'X')]);
      expect(await rota(), ['1 A X', '- B X', '- C X']);
    });
  });

  group('ekranlar', () {
    late Database db;

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
            // Ekran bir "Aç" sayfasının üstüne itilir: kaydedince Navigator.pop
            // gerçekten bir önceki sayfaya döner (kök sayfa kapanamaz).
            home: Builder(
              builder: (ctx) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => ekran)),
                    child: const Text('Aç'),
                  ),
                ),
              ),
            ),
          ),
        );

    Future<void> ac(WidgetTester tester, Widget ekran) async {
      await tester.pumpWidget(uygulama(ekran));
      await tester.tap(find.text('Aç'));
      await tester.pump(const Duration(milliseconds: 500)); // geçiş animasyonu
    }

    Future<void> bekle(WidgetTester tester, bool Function() kosul, String neyi) async {
      for (var i = 0; i < 150; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 50));
        if (kosul()) return;
      }
      fail('Zaman aşımı: $neyi');
    }

    Future<List<String>> rota(WidgetTester tester) async {
      final l = (await tester.runAsync(() => CariRepository(db).getAll(sadeceAktif: true)))!;
      return [for (final c in l) '${c.sira ?? '-'} ${c.tamAd}'];
    }

    Future<void> buyukEkran(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
    }

    testWidgets('Cari Ekle: sıra 1 yazılan yeni cari en başa girer, eskisi 2\'ye kayar', (tester) async {
      await buyukEkran(tester);
      await tester.runAsync(() async {
        db = await testVeritabaniAc();
        await CariRepository(db).insert(Cari(ad: 'AHMET', soyad: 'ANIL'), sira: 1);
      });
      await ac(tester, const CariEkle());
      // Varsayılan: rotanın sonu (2).
      await bekle(tester, () => tester.widget<TextFormField>(find.byKey(const ValueKey('rotaSirasi'))).controller!.text == '2',
          'varsayılan sıra');

      await tester.enterText(find.widgetWithText(TextFormField, 'Ad'), 'AHMET');
      await tester.enterText(find.widgetWithText(TextFormField, 'Soyad'), 'ATAĞ');
      await tester.enterText(find.byKey(const ValueKey('rotaSirasi')), '1');
      await bekle(tester, () => find.textContaining('AHMET ANIL var → 2. sıraya kayar').evaluate().isNotEmpty, 'önizleme');
      await tester.tap(find.text('Cari Kaydet'));
      await bekle(tester, () => find.text('Cari Kaydet').evaluate().isEmpty, 'kaydedildi');

      expect(await rota(tester), ['1 AHMET ATAĞ', '2 AHMET ANIL']);
      await tester.runAsync(() => db.close());
    });

    testWidgets('Cari Düzenle: sırayı değiştirir; pasife alınca listeden ve rotadan çıkar', (tester) async {
      await buyukEkran(tester);
      late int atag;
      await tester.runAsync(() async {
        db = await testVeritabaniAc();
        final r = CariRepository(db);
        await r.insert(Cari(ad: 'AHMET', soyad: 'ANIL'), sira: 1);
        atag = await r.insert(Cari(ad: 'AHMET', soyad: 'ATAĞ', notMetni: 'eski not'), sira: 2);
      });
      Future<Cari> atagCari() async => (await tester.runAsync(() => CariRepository(db).getById(atag)))!;

      await ac(tester, CariDuzenle(cari: await atagCari()));
      await tester.pump();
      expect(find.text('eski not'), findsOneWidget, reason: 'not artık düzenlenebilir');
      await tester.enterText(find.byKey(const ValueKey('rotaSirasi')), '1');
      await tester.tap(find.text('Kaydet'));
      await bekle(tester, () => find.text('Cari Düzenle').evaluate().isEmpty, 'kaydedildi');
      expect(await rota(tester), ['1 AHMET ATAĞ', '2 AHMET ANIL']);
      expect((await atagCari()).notMetni, 'eski not');

      // Pasife al
      await ac(tester, CariDuzenle(cari: await atagCari()));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('aktifAnahtari')));
      await tester.pump();
      expect(find.byKey(const ValueKey('rotaSirasi')), findsNothing, reason: 'pasifte sıra alanı yok');
      await tester.tap(find.text('Kaydet'));
      await bekle(tester, () => find.text('Cari pasife alınsın mı?').evaluate().isNotEmpty, 'onay');
      await tester.tap(find.text('Pasife Al'));
      await bekle(tester, () => find.text('Cari Düzenle').evaluate().isEmpty, 'kaydedildi');

      expect(await rota(tester), ['1 AHMET ANIL']);
      expect((await atagCari()).aktif, isFalse);
      await tester.runAsync(() => db.close());
    });

    testWidgets('Pasif Cariler: listelenir, "Geri Getir" istenen sırayla rotaya döner', (tester) async {
      await buyukEkran(tester);
      await tester.runAsync(() async {
        db = await testVeritabaniAc();
        final r = CariRepository(db);
        await r.insert(Cari(ad: 'VELİ', soyad: 'KAYA'), sira: 1);
        final p = await r.insert(Cari(ad: 'AHMET', soyad: 'ANIL'), sira: 2);
        await r.pasifeAl(p);
      });
      await ac(tester, const PasifCarilerEkrani());
      await bekle(tester, () => find.text('AHMET ANIL').evaluate().isNotEmpty, 'pasif listesi');
      expect(find.text('VELİ KAYA'), findsNothing);

      await tester.tap(find.text('Geri Getir'));
      await bekle(tester, () => find.text('AHMET ANIL geri getirilsin mi?').evaluate().isNotEmpty, 'diyalog');
      await tester.enterText(find.byKey(const ValueKey('rotaSirasi')), '1');
      await tester.pump();
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(FilledButton, 'Geri Getir')));
      await bekle(tester, () => find.text('Pasif cari yok').evaluate().isNotEmpty, 'liste boşaldı');

      expect(await rota(tester), ['1 AHMET ANIL', '2 VELİ KAYA']);
      await tester.runAsync(() => db.close());
    });

    testWidgets('Toplama Sırası: sürükle-bırak sonrası kaydet → 1..N', (tester) async {
      await buyukEkran(tester);
      await tester.runAsync(() async {
        db = await testVeritabaniAc();
        final r = CariRepository(db);
        await r.insert(Cari(ad: 'A', soyad: 'X'), sira: 1);
        await r.insert(Cari(ad: 'B', soyad: 'X'), sira: 2);
        await r.insert(Cari(ad: 'C', soyad: 'X')); // sırasız
      });
      await ac(tester, const ToplamaSirasiEkrani());
      await bekle(tester, () => find.text('C X').evaluate().isNotEmpty, 'liste');

      expect(find.byIcon(Icons.drag_handle), findsNWidgets(3), reason: 'her satırda sürükleme tutamağı');
      // C'yi (3.) en üste taşı: listenin sürükle-bırak olayı (onReorder 2 → 0).
      tester.widget<ReorderableListView>(find.byType(ReorderableListView)).onReorder!(2, 0);
      await tester.pump();
      expect(tester.getTopLeft(find.text('C X')).dy, lessThan(tester.getTopLeft(find.text('A X')).dy));

      await tester.tap(find.text('Sırayı Kaydet'));
      await bekle(tester, () => find.text('Sırayı Kaydet').evaluate().isEmpty, 'kaydedildi');
      expect(await rota(tester), ['1 C X', '2 A X', '3 B X']);
      await tester.runAsync(() => db.close());
    });
  });
}
