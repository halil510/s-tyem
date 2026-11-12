// AJAN DENETİMİ — CARİ YÖNETİMİ (cari ekle/düzenle/pasif/sil, rota, arama, Excel'den içe alma).
// "DÜZELTİLDİ: ..." testleri DOĞRU davranışı bekler (hata varken başarısız olur).
// "KONTROL: ..." testleri doğrulanmış doğru davranışlardır (geçmeli).
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/core/providers/database_provider.dart';
import 'package:sutyem_pro/data/repositories/cari_repository.dart';
import 'package:sutyem_pro/ekranlar/cari/cari_duzenle.dart';
import 'package:sutyem_pro/ekranlar/cari/cari_form.dart';
import 'package:sutyem_pro/ekranlar/cari/pasif_cariler_ekrani.dart';
import 'package:sutyem_pro/ekranlar/cari_ekle.dart';
import 'package:sutyem_pro/ekranlar/cari_listesi.dart';
import 'package:sutyem_pro/features/cari/cari_excel_ice_aktarma.dart';
import 'package:sutyem_pro/features/cari/providers/cari_providers.dart';
import 'package:sutyem_pro/features/cari_hesap/providers/cari_hesap_providers.dart';
import 'package:sutyem_pro/models/cari_model.dart';
import 'package:sutyem_pro/utils/tarih_format.dart';
import 'package:sutyem_pro/utils/turkce.dart';

import '../helpers/test_db.dart';

List<int> _excelYap(List<List<Object?>> satirlar, {String sayfa = 'Liste'}) {
  final x = Excel.createExcel();
  final s = x[sayfa];
  for (var r = 0; r < satirlar.length; r++) {
    for (var c = 0; c < satirlar[r].length; c++) {
      final v = satirlar[r][c];
      if (v == null) continue;
      s.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).value = switch (v) {
        int i => IntCellValue(i),
        double d => DoubleCellValue(d),
        _ => TextCellValue(v.toString()),
      };
    }
  }
  return x.encode()!;
}

void main() {
  setUpAll(initializeTurkishLocale);

  // ───────────────────────── Kayıt katmanı ─────────────────────────
  group('CariRepository', () {
    late Database db;
    late CariRepository repo;
    setUp(() async {
      db = await testVeritabaniAc();
      repo = CariRepository(db);
    });
    tearDown(() => db.close());

    Future<List<String>> rota() async =>
        [for (final c in await repo.getAll(sadeceAktif: true)) '${c.sira ?? '-'} ${c.tamAd}'];

    test('DÜZELTİLDİ: rotada sırası olan cari kalıcı silinince rota 1..N boşluksuz kalmalı', () async {
      await repo.insert(Cari(ad: 'A', soyad: 'X'), sira: 1);
      final b = await repo.insert(Cari(ad: 'B', soyad: 'X'), sira: 2);
      await repo.insert(Cari(ad: 'C', soyad: 'X'), sira: 3);
      await repo.delete(b); // Cariler → Sil (hareketsiz cari, tek onay)
      expect(await rota(), ['1 A X', '2 C X'], reason: 'C rozette hâlâ "3" görünüyor; rotada 2 cari var');
    });

    test('KONTROL: rota değişmezliği — ekle/araya ekle/pasife al/aktif yap/rotaKaydet sonrası 1..N', () async {
      final a = await repo.insert(Cari(ad: 'A', soyad: 'X'), sira: 1);
      final b = await repo.insert(Cari(ad: 'B', soyad: 'X'), sira: 99);
      final c = await repo.insert(Cari(ad: 'C', soyad: 'X'), sira: 2); // araya
      expect(await rota(), ['1 A X', '2 C X', '3 B X']);
      await repo.pasifeAl(c);
      expect(await rota(), ['1 A X', '2 B X']);
      await repo.aktifYap(c, sira: 1);
      expect(await rota(), ['1 C X', '2 A X', '3 B X']);
      await repo.rotaKaydet([b, a, c]);
      expect(await rota(), ['1 B X', '2 A X', '3 C X']);
      // Pasif cari update ile tekrar düzenlenirse sıra almaz.
      await repo.update(Cari(id: a, ad: 'A', soyad: 'X', aktif: false), siraGuncelle: true, sira: 1);
      expect(await rota(), ['1 B X', '2 C X']);
      // Pasif cari eklerken verilen sıra yok sayılır.
      await repo.insert(Cari(ad: 'P', soyad: 'X', aktif: false), sira: 1);
      expect(await rota(), ['1 B X', '2 C X']);
      expect(await repo.rotadakiSayi(), 2);
    });

    test('KONTROL: pasif cari aktif listelerde yok; geçmiş süt/yem/ödeme bakiyede kalır', () async {
      final id = await repo.insert(Cari(ad: 'ŞÜKRÜ', soyad: 'ÖZ'), sira: 1);
      await fiyatTanimla(db, id, '2026-10', sut: 20, sutYemi: 10);
      await db.insert('sutler', {'cari_id': id, 'tarih': '2026-10-05', 'sabah': 10, 'aksam': 5, 'toplam': 15});
      await db.insert('yemler', {'cari_id': id, 'tarih': '2026-10-06', 'sut_yemi': 3, 'toplam': 3});
      final c = testContainer(db);
      addTearDown(c.dispose);
      final once = (await c.read(tumKalanBorclarProvider.future))[id];
      expect(once, 270.0); // 15*20 - 3*10

      await repo.pasifeAl(id);
      c.invalidate(tumKalanBorclarProvider);
      c.invalidate(aktifCarilerProvider);
      expect((await c.read(aktifCarilerProvider.future)).map((e) => e.id), isNot(contains(id)));
      expect((await c.read(butunCarilerProvider.future)).map((e) => e.id), contains(id));
      expect((await c.read(tumKalanBorclarProvider.future))[id], 270.0);
    });

    test('KONTROL: hareketli cari silinince (CASCADE) bakiyeden düşer, diğer cari etkilenmez', () async {
      final a = await repo.insert(Cari(ad: 'A', soyad: 'X'), sira: 1);
      final b = await repo.insert(Cari(ad: 'B', soyad: 'X'), sira: 2);
      for (final id in [a, b]) {
        await fiyatTanimla(db, id, '2026-10', sut: 10);
        await db.insert('sutler', {'cari_id': id, 'tarih': '2026-10-05', 'sabah': 10, 'aksam': 0, 'toplam': 10});
        await db.insert('cari_odemeler', {
          'cari_id': id,
          'tarih': '2026-10-07',
          'islem_turu': 'odeme',
          'toplam_tutar': 30.0,
        });
      }
      final say = await repo.hareketSayilari(a);
      expect((say.sut, say.yem, say.odeme), (1, 0, 1));
      await repo.delete(a);
      final c = testContainer(db);
      addTearDown(c.dispose);
      final bakiye = await c.read(tumKalanBorclarProvider.future);
      expect(bakiye.containsKey(a), isFalse);
      expect(bakiye[b], 70.0);
      expect(await db.query('sutler', where: 'cari_id = ?', whereArgs: [a]), isEmpty);
      expect(await db.query('cari_odemeler', where: 'cari_id = ?', whereArgs: [a]), isEmpty);
      expect(await db.query('cari_fiyatlar', where: 'cari_id = ?', whereArgs: [a]), isEmpty);
    });

    test('KONTROL: aynı isim kontrolü büyük/küçük harf, İ/ı ve boşluk farkını yakalar', () async {
      await repo.insert(Cari(ad: 'MEHMET ALİ', soyad: 'YILMAZ'));
      expect(await ayniIsimliCariler(repo, 'mehmet  ali', 'yılmaz'), hasLength(1));
      expect(await ayniIsimliCariler(repo, 'Mehmet', 'Ali Yılmaz'), hasLength(1));
      expect(await ayniIsimliCariler(repo, ' Mehmet Ali ', ' Yılmaz '), hasLength(1));
      // Pasif de sayılır.
      final p = await repo.insert(Cari(ad: 'VELİ', soyad: 'KAYA'));
      await repo.pasifeAl(p);
      expect(await ayniIsimliCariler(repo, 'veli', 'kaya'), hasLength(1));
    });
  });

  // ───────────────────────── Türkçe arama/sıralama ─────────────────────────
  group('Türkçe', () {
    test('KONTROL: arama "ŞÜKRÜ" ↔ "şükrü", "İSMAİL" ↔ "ismail", "IŞIK" ↔ "ışık"', () {
      expect(aramaEslesir('ŞÜKRÜ ÖZTÜRK', 'şükrü'), isTrue);
      expect(aramaEslesir('şükrü öztürk', 'ŞÜKRÜ'), isTrue);
      expect(aramaEslesir('İSMAİL ÇAKIR', 'ismail çakır'), isTrue);
      expect(aramaEslesir('IŞIK GÜL', 'ışık'), isTrue);
      expect(aramaEslesir('Ali   Veli', 'ali veli'), isTrue);
      expect(aramaEslesir('ALİ', 'alı'), isFalse);
    });

    test('KONTROL: Türk alfabesiyle sıralama (Ç Ş Ö Ü İ kendi yerinde)', () {
      final l = ['ZEKİ', 'ÇETİN', 'CEM', 'ŞÜKRÜ', 'SAMİ', 'İSMAİL', 'IŞIK', 'ÖMER', 'OSMAN', 'ÜMİT', 'UĞUR']
        ..sort(turkceKarsilastir);
      expect(l, ['CEM', 'ÇETİN', 'IŞIK', 'İSMAİL', 'OSMAN', 'ÖMER', 'SAMİ', 'ŞÜKRÜ', 'UĞUR', 'ÜMİT', 'ZEKİ']);
    });

    test('DÜZELTİLDİ: ASCII yazılmış isim ("ALI VELI") kayıtlı "ALİ VELİ" ile aynı kişi sayılmalı (Excel çift cari / arama)',
        () async {
      // Excel listeleri çoğu zaman Türkçe karakter olmadan (ASCII büyük I) gelir.
      final plan = iceAktarmaPlani(
        [const CariAdayi(ad: 'ALI', soyad: 'VELI', satir: 2)],
        [Cari(id: 1, ad: 'ALİ', soyad: 'VELİ')],
      );
      expect(plan.kayitli, hasLength(1), reason: 'ALI VELI yeni cari olarak eklenir → aynı kişi iki kez');
      expect(aramaEslesir('HALIL KAYA', 'halil'), isTrue, reason: '"halil" araması ASCII "HALIL"i bulmuyor');
    });
  });

  // ───────────────────────── Excel'den içe alma ─────────────────────────
  group('Excel içe alma', () {
    test('DÜZELTİLDİ: ASCII büyük harfli başlık "ISIM SOYISIM" başlık sayılmalı, cari olarak alınmamalı', () {
      final s = CariExcelOkuyucu.oku(_excelYap([
        ['ISIM SOYISIM', 'TELEFON'],
        ['AHMET YILMAZ', '05551112233'],
        ['AYŞE DEMİR', '05554445566'],
      ]));
      expect(s.adaylar.map((a) => a.tamAd), ['AHMET YILMAZ', 'AYŞE DEMİR'],
          reason: 'başlık satırı "ISIM SOYISIM" adlı bir cari olarak listeye giriyor');
      expect(s.adaylar.first.telefon, '05551112233', reason: 'başlık tanınmayınca telefon sütunu da okunmuyor');
    });

    test('DÜZELTİLDİ: tek "Ad" başlıklı sütun (+ Telefon) başlık sayılmalı, "Ad" adlı cari oluşmamalı', () {
      final s = CariExcelOkuyucu.oku(_excelYap([
        ['Ad', 'Telefon'],
        ['Mehmet Kara', '05321234567'],
      ]));
      expect(s.adaylar.map((a) => a.tamAd), ['Mehmet Kara']);
    });

    test('KONTROL: dosya içi tekrar (İ/ı, boşluk), boş satır, toplam, sayı atlanır; kayıtlı (pasif) eklenmez', () {
      final s = CariExcelOkuyucu.oku(_excelYap([
        ['Ad Soyad', 'Telefon'],
        ['İSMAİL  ÇAKIR', 5551234567],
        [null, null],
        ['ismail çakır', null],
        ['   ', null],
        ['12345', null],
        ['GENEL TOPLAM', null],
        ['Ayşe Demir', null],
        ['Veli Kaya', null],
      ]));
      expect(s.adaylar.map((a) => a.tamAd), ['İSMAİL ÇAKIR', 'Ayşe Demir', 'Veli Kaya']);
      expect(s.adaylar.first.telefon, '5551234567');
      final plan = iceAktarmaPlani(s.adaylar, [Cari(id: 9, ad: 'VELİ', soyad: 'KAYA', aktif: false)]);
      expect(plan.yeni.map((a) => a.tamAd), ['İSMAİL ÇAKIR', 'Ayşe Demir']);
      expect(plan.kayitli.map((a) => a.tamAd), ['Veli Kaya']);
    });
  });

  // ───────────────────────── Ekranlar ─────────────────────────
  group('ekranlar', () {
    late Database db;

    Widget uygulama(Widget ekran, {double yazi = 1.0}) => ProviderScope(
          overrides: [databaseProvider.overrideWith((ref) => db)],
          child: MaterialApp(
            locale: const Locale('tr', 'TR'),
            supportedLocales: const [Locale('tr', 'TR')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (ctx, child) => MediaQuery(
              data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(yazi)),
              child: child!,
            ),
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

    Future<void> ac(WidgetTester tester, Widget ekran, {double yazi = 1.0}) async {
      await tester.pumpWidget(uygulama(ekran, yazi: yazi));
      await tester.tap(find.text('Aç'));
      await tester.pump(const Duration(milliseconds: 500));
    }

    Future<bool> bekle(WidgetTester tester, bool Function() kosul, {int tur = 100}) async {
      for (var i = 0; i < tur; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 50));
        if (kosul()) return true;
      }
      return false;
    }

    Future<void> telefon(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
    }

    testWidgets('DÜZELTİLDİ: Excel\'den soyadsız gelen cari (tek kelime) Cari Düzenle\'de kaydedilebilmeli', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      late int id;
      await tester.runAsync(() async {
        db = await testVeritabaniAc();
        // Excel içe alma tek kelimelik ismi soyad = '' ile kaydeder (cari_excel_ekrani).
        await CariRepository(db).topluEkle([Cari(ad: 'HÜSEYİN', soyad: '', hayvanTuru: 'İnek')]);
        id = (await db.query('cariler')).first['id'] as int;
      });
      final cari = (await tester.runAsync(() => CariRepository(db).getById(id)))!;
      await ac(tester, CariDuzenle(cari: cari));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextFormField, 'Telefon'), '05551234567');
      await tester.tap(find.text('Kaydet'));
      final kapandi = await bekle(tester, () => find.text('Cari Düzenle').evaluate().isEmpty, tur: 40);
      final kayit = await tester.runAsync(() => CariRepository(db).getById(id));
      await tester.runAsync(() => db.close());
      expect(find.text('Soyad zorunludur'), findsNothing,
          reason: 'Excel\'in eklediği soyadsız cari için telefon bile değiştirilemiyor / pasife alınamıyor');
      expect(kapandi, isTrue);
      expect(kayit!.telefon, '05551234567');
    });

    testWidgets('DÜZELTİLDİ: Cariler ekranı "Süt Toplam" hayvan türü boş carinin sütünü de saymalı', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final bugun = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await tester.runAsync(() async {
        db = await testVeritabaniAc();
        // Eski sürümden / yedekten gelen cari: hayvan_turu NULL ("Belirtilmemiş" gösterilir).
        final a = await cariEkle(db, ad: 'ESKİ', soyad: 'CARİ');
        final b = await CariRepository(db).insert(Cari(ad: 'YENİ', soyad: 'CARİ', hayvanTuru: 'İnek'));
        await db.insert('sutler', {'cari_id': a, 'tarih': bugun, 'sabah': 7, 'aksam': 0, 'toplam': 7});
        await db.insert('sutler', {'cari_id': b, 'tarih': bugun, 'sabah': 5, 'aksam': 0, 'toplam': 5});
      });
      await tester.pumpWidget(uygulama(const Scaffold(body: CariListesi())));
      await tester.tap(find.text('Aç'));
      await bekle(tester, () => find.text('ESKİ CARİ').evaluate().isNotEmpty);
      expect(find.text('7 kg'), findsOneWidget, reason: 'cari kartında 7 kg görünüyor');
      final kart = find.ancestor(of: find.text('Süt Toplam'), matching: find.byType(Row)).first;
      final kartYazilari =
          tester.widgetList<Text>(find.descendant(of: kart, matching: find.byType(Text))).map((t) => t.data).toList();
      await tester.runAsync(() => db.close());
      expect(kartYazilari, contains('12 kg'), reason: 'Süt Toplam kartı: $kartYazilari');
      // Süt Toplam kartı: 7 + 5 = 12 kg olmalı (Özet ekranı da 12 sayar).
      expect(find.text('12 kg'), findsOneWidget, reason: 'Süt Toplam yalnız İnek/Koyun/Tavuk carileri topluyor (5 kg)');
    });

    testWidgets('KONTROL: Cari Ekle — aynı isim (İ/ı, büyük/küçük) uyarısı çıkar, Vazgeç ile eklenmez', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(() async {
        db = await testVeritabaniAc();
        await CariRepository(db).insert(Cari(ad: 'İSMAİL', soyad: 'IŞIK'), sira: 1);
      });
      await ac(tester, const CariEkle());
      await bekle(tester, () =>
          tester.widget<TextFormField>(find.byKey(const ValueKey('rotaSirasi'))).controller!.text == '2');
      await tester.enterText(find.widgetWithText(TextFormField, 'Ad'), 'ismail ');
      await tester.enterText(find.widgetWithText(TextFormField, 'Soyad'), 'ışık');
      await tester.tap(find.text('Cari Kaydet'));
      expect(await bekle(tester, () => find.text('Aynı isimde cari var').evaluate().isNotEmpty), isTrue);
      await tester.tap(find.text('Vazgeç'));
      await tester.pump(const Duration(milliseconds: 300));
      final n = (await tester.runAsync(() => db.query('cariler')))!.length;
      await tester.runAsync(() => db.close());
      expect(n, 1);
    });

    testWidgets('KONTROL: Cari Ekle boş ad/soyad kaydetmez; sıra "0" reddedilir', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(() async => db = await testVeritabaniAc());
      await ac(tester, const CariEkle());
      await bekle(tester, () =>
          tester.widget<TextFormField>(find.byKey(const ValueKey('rotaSirasi'))).controller!.text == '1');
      await tester.enterText(find.widgetWithText(TextFormField, 'Ad'), '   ');
      await tester.enterText(find.byKey(const ValueKey('rotaSirasi')), '0');
      await tester.tap(find.text('Cari Kaydet'));
      await tester.pump();
      expect(find.text('Ad zorunludur'), findsOneWidget);
      expect(find.text('Soyad zorunludur'), findsOneWidget);
      expect(find.textContaining('Sıra 1 veya daha büyük'), findsOneWidget);
      final n = (await tester.runAsync(() => db.query('cariler')))!.length;
      await tester.runAsync(() => db.close());
      expect(n, 0);
    });

    for (final (yazi, ekranlar, etiket) in [
      (1.0, const ['ekle', 'duzenle', 'pasif'], 'KONTROL: 360 px, yazı ×1.0 — Cari Ekle / Cari Düzenle / Pasif Cariler taşmaz'),
      (1.3, const ['ekle', 'duzenle', 'pasif'], 'KONTROL: 360 px, yazı ×1.3 — Cari Ekle / Cari Düzenle / Pasif Cariler taşmaz'),
      (1.6, const ['ekle', 'duzenle'], 'KONTROL: 360 px, yazı ×1.6 — Cari Ekle / Cari Düzenle taşmaz'),
      (1.6, const ['pasif'], 'DÜZELTİLDİ: 360 px, yazı ×1.6 — Pasif Cariler kartı ("Geri Getir" + uzun ad) taşmamalı'),
    ]) {
      testWidgets(etiket, (tester) async {
        await telefon(tester);
        late Cari uzun;
        await tester.runAsync(() async {
          db = await testVeritabaniAc();
          final r = CariRepository(db);
          await r.insert(Cari(ad: 'MUSTAFA KEMAL ABDURRAHMAN', soyad: 'KARAMUSTAFAOĞULLARI'), sira: 1);
          final p = await r.insert(
              Cari(ad: 'HÜSEYİN HÜSNÜ', soyad: 'ÇAKIROĞLUGİLLERDEN', telefon: '0532 123 45 67', hayvanTuru: 'Koyun'));
          await r.pasifeAl(p);
          uzun = (await r.getById(1))!;
        });
        final secilen = <String, Widget>{
          'ekle': const CariEkle(),
          'duzenle': CariDuzenle(cari: uzun),
          'pasif': const PasifCarilerEkrani(),
        };
        for (final ekran in [for (final e in ekranlar) secilen[e]!]) {
          await tester.pumpWidget(const SizedBox()); // önceki ekranın gezgini kapansın
          await tester.pumpWidget(ProviderScope(
            overrides: [databaseProvider.overrideWith((ref) => db)],
            child: MaterialApp(
              locale: const Locale('tr', 'TR'),
              supportedLocales: const [Locale('tr', 'TR')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              builder: (ctx, child) => MediaQuery(
                data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(yazi)),
                child: child!,
              ),
              home: ekran,
            ),
          ));
          await bekle(tester, () => false, tur: 5);
          expect(find.byWidget(ekran), findsOneWidget);
          // Taşan Row'u bul (hangi parçanın taştığını raporda göstermek için).
          final tasanlar = <String>[];
          for (final el in find.byType(Row).evaluate()) {
            final r = el.renderObject;
            if (r is! RenderFlex || !r.hasSize) continue;
            var toplam = 0.0;
            var ch = r.firstChild;
            while (ch != null) {
              toplam += (ch as RenderBox).size.width;
              ch = (ch.parentData as FlexParentData).nextSibling;
            }
            if (toplam > r.size.width + 0.5) {
              final yazilar = find
                  .descendant(of: find.byElementPredicate((e) => e == el), matching: find.byType(Text))
                  .evaluate()
                  .map((e) => (e.widget as Text).data)
                  .join(' | ');
              tasanlar.add('Row ${r.size.width.toStringAsFixed(0)} px < ${toplam.toStringAsFixed(0)} px: $yazilar');
            }
          }
          if (tasanlar.isNotEmpty) debugPrint('TAŞAN (${ekran.runtimeType}, ×$yazi): $tasanlar');
          expect(tester.takeException(), isNull, reason: '${ekran.runtimeType} taşma');
        }
        await tester.runAsync(() => db.close());
      });
    }
  });
}
