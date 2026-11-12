import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/core/providers/database_provider.dart';
import 'package:sutyem_pro/core/providers/repository_providers.dart';
import 'package:sutyem_pro/core/providers/veri_surumu_provider.dart';
import 'package:sutyem_pro/features/cari_hesap/providers/cari_hesap_providers.dart';
import 'package:sutyem_pro/features/raporlar/rapor_disa_aktarim.dart';
import 'package:sutyem_pro/features/raporlar/rapor_ekrani.dart';
import 'package:sutyem_pro/features/raporlar/rapor_modeli.dart';
import 'package:sutyem_pro/utils/tarih_format.dart';

import '../helpers/test_db.dart';

/// Raporlar: rakamlar ekstre / bakiyeyle kuruşu kuruşuna aynı, kaydın GÜNÜNDEKİ fiyat,
/// pasif cari dahil, eksik fiyat yakalanır, Excel/PDF üretilir, tüm raporlar dar ekranda açılır.
void main() {
  late Database db;
  late ProviderContainer c;
  late int ali, veli, pasif;

  setUpAll(initializeTurkishLocale);

  Future<void> veriHazirla(Database db) async {
    ali = await cariEkle(db, ad: 'Ali', soyad: 'Kaya');
    veli = await cariEkle(db, ad: 'Veli', soyad: 'Şahin');
    pasif = await cariEkle(db, ad: 'Çetin', soyad: 'Öz');
    await db.update('cariler', {'aktif': 0}, where: 'id = ?', whereArgs: [pasif]);
    // Ali: Ekim 25 TL, 4 Kasım'dan itibaren 27 TL; süt yemi 12 TL.
    await fiyatTanimla(db, ali, '2026-10', sut: 25, sutYemi: 12);
    await db.insert('cari_fiyatlar', {'cari_id': ali, 'ay': '2026-11-04', 'sut_fiyat': 27, 'sut_yemi_fiyat': 12});
    await fiyatTanimla(db, pasif, '2026-10', sut: 20);
    // Veli: FİYAT YOK (eksik fiyat raporuna düşmeli).
    for (final s in [
      {'cari_id': ali, 'tarih': '2026-10-31', 'sabah': 10.0, 'aksam': 0.0, 'toplam': 10.0}, // devir: 250
      {'cari_id': ali, 'tarih': '2026-11-03', 'sabah': 20.0, 'aksam': 18.5, 'toplam': 38.5}, // 25 → 962,5
      {'cari_id': ali, 'tarih': '2026-11-04', 'sabah': 21.0, 'aksam': 19.0, 'toplam': 40.0}, // 27 → 1080
      {'cari_id': veli, 'tarih': '2026-11-04', 'sabah': 15.0, 'aksam': 0.0, 'toplam': 15.0}, // 0 (fiyat yok)
      {'cari_id': pasif, 'tarih': '2026-11-05', 'sabah': 5.0, 'aksam': 5.0, 'toplam': 10.0}, // 20 → 200
    ]) {
      await db.insert('sutler', s);
    }
    await db.insert('yemler', {'cari_id': ali, 'tarih': '2026-11-06', 'sut_yemi': 50, 'toplam': 50}); // 600
    await db.insert('yemler', {'cari_id': veli, 'tarih': '2026-11-06', 'besi_yemi': 20, 'toplam': 20}); // 0
    await db.insert('cari_odemeler', {
      'cari_id': ali, 'tarih': '2026-11-10', 'islem_turu': 'odeme', 'miktar': 1, 'birim_fiyat': 1000, 'toplam_tutar': 1000, 'aciklama': 'nakit'
    });
    await db.insert('cari_odemeler', {
      'cari_id': veli, 'tarih': '2026-11-11', 'islem_turu': 'tahsilat', 'miktar': 1, 'birim_fiyat': 50, 'toplam_tutar': 50
    });
  }

  Future<RaporTablosu> rapor(RaporTuru t, {String bas = '2026-11-01', String bit = '2026-11-30', int? cari}) async {
    final s = await c.read(raporServisiProvider.future);
    return s.olustur(t, RaporFiltresi(bas: bas, bit: bit, cariId: cari));
  }

  int sutun(RaporTablosu t, String ad) => t.sutunlar.indexWhere((s) => s.ad == ad);
  List<Object?> satir(RaporTablosu t, String cari) => t.satirlar.firstWhere((r) => r.contains(cari));

  group('servis', () {
    setUp(() async {
      db = await testVeritabaniAc();
      c = testContainer(db);
      await veriHazirla(db);
    });
    tearDown(() => c.dispose());

    test('Süt girişleri: her gün KENDİ fiyatıyla (3 Kasım 25, 4 Kasım 27); toplam doğru', () async {
      final t = await rapor(RaporTuru.gunlukSut, cari: ali);
      expect(t.satirlar.map((r) => r[5]), [25.0, 27.0]);
      expect(t.satirlar.map((r) => r[6]), [962.5, 1080.0]);
      expect(t.toplamlar[sutun(t, 'Toplam kg')], 78.5);
      expect(t.toplamlar[sutun(t, 'Tutar')], 2042.5);
      expect(t.toplamlar[sutun(t, 'Fiyat')], isNull, reason: 'fiyat sütunu toplanmaz');
    });

    test('Cari hesap özeti ekstreyle ve genel bakiye tumKalanBorclar ile kuruşu kuruşuna aynı; pasif cari dahil', () async {
      final t = await rapor(RaporTuru.cariHesapOzeti);
      final e = await c.read(cariEkstreProvider((cariId: ali, baslangic: DateTime(2026, 11, 1), bitis: DateTime(2026, 11, 30))).future);
      final a = satir(t, 'Ali Kaya');
      expect(a[sutun(t, 'Süt tutarı')], e.toplamSut);
      expect(a[sutun(t, 'Yem tutarı')], e.toplamYem);
      expect(a[sutun(t, 'Ödeme')], e.toplamOdeme);
      expect(a[sutun(t, 'Dönem net')], e.bakiye);
      final genel = await c.read(tumKalanBorclarProvider.future);
      for (final r in t.satirlar) {
        final id = {'Ali Kaya': ali, 'Veli Şahin': veli, 'Çetin Öz': pasif}[r[0]]!;
        expect(r[sutun(t, 'Genel bakiye')], genel[id] ?? 0.0, reason: '${r[0]}');
      }
      expect(t.satirlar.map((r) => r[0]), ['Ali Kaya', 'Çetin Öz', 'Veli Şahin'], reason: 'Türkçe alfabetik');
      expect(satir(t, 'Ali Kaya')[sutun(t, 'Durum')], 'Alacaklı'); // 250+962,5+1080−600−1000 = 692,5
      expect(satir(t, 'Ali Kaya')[sutun(t, 'Genel bakiye')], 692.5);
    });

    test('Bakiye listesi: bitiş tarihi itibarıyla; alacaklı/borçlu ayrı sütunda', () async {
      final t = await rapor(RaporTuru.bakiyeListesi, bit: '2026-11-05');
      // 5 Kasım itibarıyla Ali: 250 + 962,5 + 1080 = 2292,5 alacaklı (yem/ödeme sonra).
      expect(satir(t, 'Ali Kaya')[sutun(t, 'Alacaklı (işletme borçlu)')], 2292.5);
      expect(satir(t, 'Çetin Öz')[sutun(t, 'Durum')], 'Alacaklı (pasif)');
      final son = await rapor(RaporTuru.bakiyeListesi, bit: '2026-11-30');
      expect(satir(son, 'Veli Şahin')[sutun(son, 'Durum')], 'Alacaklı'); // tahsilat 50; süt/yem fiyatsız 0
    });

    test('Cari ekstre: devir + yürüyen bakiye; son bakiye genel bakiyeyle aynı', () async {
      final t = await rapor(RaporTuru.cariEkstre, cari: ali);
      expect(t.satirlar.first[1], 'Devir');
      expect(t.satirlar.first[5], 250.0);
      expect(t.satirlar.last[5], 692.5);
      expect(t.satirlar.map((r) => r[1]), ['Devir', 'Süt alımı', 'Süt alımı', 'Yem verişi', 'Ödeme (cariye)']);
      final bos = await rapor(RaporTuru.cariEkstre);
      expect(bos.satirlar, isEmpty, reason: 'cari seçilmeden ekstre yok');
    });

    test('Fiyatı eksik kayıtlar yakalanır; ilgili raporlarda not düşülür', () async {
      final t = await rapor(RaporTuru.fiyatEksik);
      expect(t.satirlar.map((r) => '${r[1]} ${r[2]}'), ['Veli Şahin Süt', 'Veli Şahin Yem']);
      expect((await rapor(RaporTuru.gunlukSut)).not, contains('1 kayıtta fiyat'));
    });

    test('Günlük toplam, aylık, yem türü, cari yem, ödeme/tahsilat raporları', () async {
      final g = await rapor(RaporTuru.gunlukSutToplami);
      expect(g.satirlar.map((r) => r[0]), ['2026-11-03', '2026-11-04', '2026-11-05']);
      expect(g.satirlar[1][1], 2, reason: '4 Kasım: Ali + Veli');
      expect(g.toplamlar[sutun(g, 'Toplam kg')], 103.5);

      final a = await rapor(RaporTuru.aylikSut, bas: '2026-01-01');
      expect(a.satirlar.map((r) => r[0]), ['10.2026', '11.2026']);
      expect(a.satirlar.last[sutun(a, 'Tutar')], 2242.5); // 962,5 + 1080 + 0 + 200

      final y = await rapor(RaporTuru.yemTuruBazli);
      expect(y.satirlar.map((r) => r[0]), ['Süt Yemi', 'Besi Yemi']);
      expect(y.toplamlar[sutun(y, 'Tutar')], 600.0);

      final o = await rapor(RaporTuru.odemeTahsilat);
      expect(o.toplamlar[sutun(o, 'Ödeme (cariye)')], 1000.0);
      expect(o.toplamlar[sutun(o, 'Tahsilat (cariden)')], 50.0);
    });

    test('Rapor veriden sonra yenilenir (yeni süt girişi rapora yansır)', () async {
      final once = await c.read(raporProvider((RaporTuru.cariSutToplami, '2026-11-01', '2026-11-30', null)).future);
      final repo = await c.read(sutRepositoryProvider.future);
      await repo.gunlukKaydet(cariId: ali, tarih: '2026-11-20', sabah: 10, aksam: 0);
      c.read(veriSurumuProvider.notifier).state++;
      final sonra = await c.read(raporProvider((RaporTuru.cariSutToplami, '2026-11-01', '2026-11-30', null)).future);
      expect((satir(sonra, 'Ali Kaya')[sutun(sonra, 'Tutar')] as double) - (satir(once, 'Ali Kaya')[sutun(once, 'Tutar')] as double), 270.0);
    });

    test('Excel: sayılar sayı hücresi, toplam satırı var; PDF baytları üretilir', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final t = await rapor(RaporTuru.cariHesapOzeti);
      final x = Excel.decodeBytes(RaporDisaAktarim.excelBaytlari(t));
      final s = x.tables['Rapor']!;
      expect(s.cell(CellIndex.indexByString('A1')).value.toString(), 'Cari Hesap Özeti');
      final aliSatiri = s.rows.indexWhere((r) => r.isNotEmpty && r.first?.value.toString() == 'Ali Kaya');
      expect(s.rows[aliSatiri][sutun(t, 'Genel bakiye')]!.value, isA<DoubleCellValue>());
      expect(s.rows.any((r) => r.isNotEmpty && r.first?.value.toString() == 'TOPLAM'), isTrue);
      final pdf = await RaporDisaAktarim.pdfBaytlari(t);
      expect(String.fromCharCodes(pdf.take(4)), '%PDF');
    });
  });

  testWidgets('Ekran: menü listesi → her rapor 360 px telefonda hatasız açılır, tablo ve toplam görünür', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.runAsync(() async {
      db = await testVeritabaniAc();
      await veriHazirla(db);
    });
    Future<void> bekle() async {
      for (var i = 0; i < 15; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
    }

    Widget uygulama(Widget ekran) => ProviderScope(
          overrides: [databaseProvider.overrideWith((ref) => db)],
          child: MaterialApp(
            locale: const Locale('tr', 'TR'),
            supportedLocales: const [Locale('tr', 'TR')],
            localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
            home: ekran,
          ),
        );

    await tester.pumpWidget(uygulama(const RaporAnaEkrani()));
    await bekle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('rapor-cariHesapOzeti')), 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.byKey(const ValueKey('rapor-cariHesapOzeti')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rapor-cariHesapOzeti')));
    await tester.pump(const Duration(milliseconds: 400)); // sayfa geçişi
    await bekle();
    expect(find.byType(RaporEkrani), findsOneWidget);
    await tester.tap(find.text('Bu yıl'));
    await bekle();
    expect(find.text('TOPLAM'), findsOneWidget);
    expect(tester.takeException(), isNull);

    for (final t in RaporTuru.values) {
      await tester.pumpWidget(uygulama(RaporEkrani(tur: t, cariId: t.cariFiltresi ? ali : null)));
      await bekle();
      expect(tester.takeException(), isNull, reason: t.baslik);
    }
  });
}
