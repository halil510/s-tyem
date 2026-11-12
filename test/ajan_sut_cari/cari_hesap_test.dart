// AJAN DENETİMİ — Cari hesap, ekstre, ödeme/tahsilat ve fiyat ekranları.
// "DÜZELTİLDİ: ..." testleri DOĞRU davranışı bekler (hata varken başarısız olur).
// "KONTROL: ..." testleri doğrulanmış doğru davranışlardır (geçmeli).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/core/providers/database_provider.dart';
import 'package:sutyem_pro/core/providers/repository_providers.dart';
import 'package:sutyem_pro/ekranlar/sut_fiyat_ekrani.dart';
import 'package:sutyem_pro/features/cari_hesap/models/cari_fiyat_lookup.dart';
import 'package:sutyem_pro/features/cari_hesap/models/cari_hareket.dart';
import 'package:sutyem_pro/features/cari_hesap/providers/cari_hesap_providers.dart';
import 'package:sutyem_pro/features/cari_hesap/screens/cari_hesap_ekstresi_ekrani.dart';
import 'package:sutyem_pro/features/raporlar/rapor_modeli.dart';
import 'package:sutyem_pro/features/raporlar/rapor_servisi.dart';
import 'package:sutyem_pro/features/terazi/providers/terazi_providers.dart';
import 'package:sutyem_pro/features/terazi/services/terazi_baglanti_durumu.dart';
import 'package:sutyem_pro/models/cari_fiyat_model.dart';
import 'package:sutyem_pro/models/cari_model.dart';
import 'package:sutyem_pro/models/yem_model.dart';
import 'package:sutyem_pro/utils/sayi_format.dart';

import '../helpers/test_db.dart';

class _SahteTerazi extends TeraziBaglantiNotifier {
  @override
  Future<bool> baslangicOtomatikBaglan() async => false;
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

Future<void> _biraz(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Future<void> _tamFiyat(Database db, int cariId, String ay, {double sut = 0, double sutYemi = 0, double besi = 0}) =>
    db.insert('cari_fiyatlar', {
      'cari_id': cariId,
      'ay': ay,
      'sut_fiyat': sut,
      'sut_yemi_fiyat': sutYemi,
      'besi_yemi_fiyat': besi,
    });

void main() {
  // ─────────────────────── HESAP / RAPOR UYUMU ───────────────────────
  group('bakiye her yerde aynı', () {
    late Database db;
    late ProviderContainer c;
    late int ali, veli;
    late RaporServisi rapor;

    setUp(() async {
      db = await testVeritabaniAc();
      c = testContainer(db);
      ali = await cariEkle(db, ad: 'Ali', soyad: 'Kaya');
      veli = await cariEkle(db, ad: 'Veli', soyad: 'Çelik');
      // Ali: Eylül 20 ₺, 15 Ekim'den itibaren 22,37 ₺; yem fiyatları ayrı.
      await _tamFiyat(db, ali, '2026-09', sut: 20, sutYemi: 9.85);
      await _tamFiyat(db, ali, '2026-10-15', sut: 22.37, sutYemi: 9.85);
      await _tamFiyat(db, ali, '2026-11', sut: 22.37, sutYemi: 10.4, besi: 12.15);
      await _tamFiyat(db, veli, '2026-10', sut: 18.5, sutYemi: 11);

      final sut = await c.read(sutRepositoryProvider.future);
      final yem = await c.read(yemRepositoryProvider.future);
      await sut.gunlukKaydet(cariId: ali, tarih: '2026-09-30', sabah: 10.35, aksam: 7.2);
      await sut.gunlukKaydet(cariId: ali, tarih: '2026-10-14', sabah: 12.33, aksam: 0);
      await sut.gunlukKaydet(cariId: ali, tarih: '2026-10-15', sabah: 12.33, aksam: 4.41);
      await sut.gunlukKaydet(cariId: ali, tarih: '2026-10-31', sabah: 9.99, aksam: 9.99);
      await sut.gunlukKaydet(cariId: ali, tarih: '2026-11-01', sabah: 3.33, aksam: 0);
      await sut.gunlukKaydet(cariId: veli, tarih: '2026-10-10', sabah: 40.05, aksam: 0);
      await yem.insert(Yem(cariId: ali, tarih: '2026-10-20', sutYemi: 33.3));
      await yem.insert(Yem(cariId: ali, tarih: '2026-11-02', sutYemi: 7.7, besiYemi: 1.1));
      await yem.insert(Yem(cariId: veli, tarih: '2026-10-10', sutYemi: 100));

      final n = c.read(cariHesapNotifierProvider.notifier);
      await n.odemeYap(cariId: ali, tutar: 150.555, tarih: DateTime(2026, 10, 31));
      await n.tahsilatAl(cariId: ali, tutar: 12.345, tarih: DateTime(2026, 11, 2));
      await n.odemeYap(cariId: veli, tutar: 0.01, tarih: DateTime(2026, 10, 11));

      rapor = RaporServisi(
        cariRepo: await c.read(cariRepositoryProvider.future),
        sutRepo: sut,
        yemRepo: yem,
        fiyatRepo: await c.read(cariFiyatRepositoryProvider.future),
        odemeRepo: await c.read(cariOdemeRepositoryProvider.future),
      );
    });

    tearDown(() async {
      c.dispose();
      await db.close();
    });

    Future<CariEkstreSonucu> ekstre(int id, [DateTime? bas, DateTime? bit]) =>
        c.read(cariEkstreProvider((cariId: id, baslangic: bas, bitis: bit)).future);

    test('KONTROL: Ödemeler/Özet (tumKalanBorclar) = Ekstre = Aylık Özet = Bakiye Listesi = Rapor Ekstre (kuruşu kuruşuna)',
        () async {
      // Elle hesap (her satır kuruşa yuvarlı):
      final aliBeklenen = kurusaYuvarla(
        kurusaYuvarla(17.55 * 20) + // 30 Eylül
            kurusaYuvarla(12.33 * 20) + // 14 Ekim (eski fiyat)
            kurusaYuvarla(16.74 * 22.37) + // 15 Ekim (yeni fiyat)
            kurusaYuvarla(19.98 * 22.37) + // 31 Ekim
            kurusaYuvarla(3.33 * 22.37) + // 1 Kasım
            12.35 - // tahsilat 12,345 → 12,35
            kurusaYuvarla(33.3 * 9.85) - // 20 Ekim yem
            kurusaYuvarla(7.7 * 10.4 + 1.1 * 12.15) - // 2 Kasım yem
            150.56, // ödeme 150,555 → 150,56
      );

      final bakiyeler = await c.read(tumKalanBorclarProvider.future);
      final e = await ekstre(ali);
      expect(bakiyeler[ali], aliBeklenen);
      expect(e.bakiye, aliBeklenen);

      final kasim = await c.read(aylikOzetProvider('2026-11').future);
      expect(kasim[ali]!.genelBakiye, aliBeklenen);

      // Aylık netlerin toplamı = genel bakiye
      var toplam = 0.0;
      for (final ay in ['2026-09', '2026-10', '2026-11']) {
        final o = await c.read(aylikOzetProvider(ay).future);
        toplam += o[ali]?.ayNet ?? 0;
        // Filtreli ekstre (ayın 1'i – son günü) = aylık özetin "bu ay net"i
        final bas = DateTime.parse('$ay-01');
        final bit = DateTime(bas.year, bas.month + 1, 0);
        expect((await ekstre(ali, bas, bit)).bakiye, o[ali]?.ayNet ?? 0, reason: ay);
      }
      expect(kurusaYuvarla(toplam), aliBeklenen);

      final bugun = _iso(DateTime.now());
      final liste = await rapor.olustur(RaporTuru.bakiyeListesi, RaporFiltresi(bas: '2020-01-01', bit: bugun));
      final aliSatir = liste.satirlar.firstWhere((s) => s[0] == 'Ali Kaya');
      final raporBakiye = (aliSatir[3] as double?) ?? -(aliSatir[4] as double);
      expect(raporBakiye, aliBeklenen);

      final rEkstre =
          await rapor.olustur(RaporTuru.cariEkstre, RaporFiltresi(bas: '2020-01-01', bit: bugun, cariId: ali));
      expect(rEkstre.satirlar.last[5], aliBeklenen);

      // Veli 0,01 ₺ ödeme kaybolmaz
      expect(bakiyeler[veli], kurusaYuvarla(kurusaYuvarla(40.05 * 18.5) - 1100 - 0.01));
      expect((await ekstre(veli)).bakiye, bakiyeler[veli]);
    });

    test('KONTROL: Rapor Cari Ekstre devri = ekstrenin önceki dönem bakiyesi; yürüyen bakiye son satırda dönem sonu bakiyesi',
        () async {
      final rEkstre = await rapor.olustur(
          RaporTuru.cariEkstre, RaporFiltresi(bas: '2026-10-15', bit: '2026-10-31', cariId: ali));
      final oncesi = await ekstre(ali, DateTime(2020), DateTime(2026, 10, 14));
      final ekimSonu = await ekstre(ali, DateTime(2020), DateTime(2026, 10, 31));
      expect(rEkstre.satirlar.first[1], 'Devir');
      expect(rEkstre.satirlar.first[5], oncesi.bakiye);
      expect(rEkstre.satirlar.last[5], ekimSonu.bakiye);
    });

    test(
        'DÜZELTİLDİ: Aylık Hesaplama (Ekim) "Genel Bakiye" / WhatsApp "Alacaklısınız" = Raporlar → Cari Hesap Özeti (Ekim) '
        'genel bakiye (31.10 itibarıyla) olmalı; Kasım hareketleri Ekim özetine girmemeli', () async {
      final ekim = await c.read(aylikOzetProvider('2026-10').future);
      final r = await rapor.olustur(
          RaporTuru.cariHesapOzeti, const RaporFiltresi(bas: '2026-10-01', bit: '2026-10-31'));
      final aliSatir = r.satirlar.firstWhere((s) => s[0] == 'Ali Kaya');
      final raporGenel = aliSatir[8] as double;
      final ekimSonu = (await ekstre(ali, DateTime(2020), DateTime(2026, 10, 31))).bakiye;
      expect(raporGenel, ekimSonu, reason: 'rapor ay sonu itibarıyla');
      expect(ekim[ali]!.genelBakiye, raporGenel,
          reason: 'Aylık Hesaplama Ekim ekranı / WhatsApp mesajı, Kasım süt/yem/tahsilatını da '
              'içeren BUGÜNKÜ bakiyeyi gösteriyor; Raporlar aynı ay için 31 Ekim bakiyesini');
    });

    test('KONTROL: ödeme/tahsilat 0, negatif, NaN, sonsuz reddedilir; işaretler doğru; silince ekstre yenilenir', () async {
      final n = c.read(cariHesapNotifierProvider.notifier);
      for (final t in [0.0, -5.0, double.nan, double.infinity]) {
        await expectLater(n.odemeYap(cariId: veli, tutar: t), throwsArgumentError, reason: '$t');
        await expectLater(n.tahsilatAl(cariId: veli, tutar: t), throwsArgumentError, reason: '$t');
      }
      final onceki = (await ekstre(veli)).bakiye;
      // Ekstreyi canlı tut (ekran açık gibi)
      final sub = c.listen(cariEkstreProvider((cariId: veli, baslangic: null, bitis: null)), (_, __) {});
      await c.read(cariEkstreProvider((cariId: veli, baslangic: null, bitis: null)).future);
      await n.tahsilatAl(cariId: veli, tutar: 100);
      var e = await c.read(cariEkstreProvider((cariId: veli, baslangic: null, bitis: null)).future);
      expect(e.bakiye, kurusaYuvarla(onceki + 100), reason: 'tahsilat bakiyeyi ARTIRIR');
      final id = e.hareketler.firstWhere((h) => h.tur == 'tahsilat').kayitId!;
      await n.sil(id);
      e = await c.read(cariEkstreProvider((cariId: veli, baslangic: null, bitis: null)).future);
      expect(e.bakiye, onceki, reason: 'silme sonrası ekstre yenilendi');
      expect((await c.read(tumKalanBorclarProvider.future))[veli], onceki);
      sub.close();
    });
  });

  // ─────────────────────────── FİYAT EKRANI ───────────────────────────
  testWidgets(
      'DÜZELTİLDİ: Süt Fiyatı ekranında YALNIZ Ali\'nin fiyatı değişince Veli\'ye bugünden itibaren "hayalet" fiyat satırı '
      'açılıyor; sonra Veli\'nin ay başı fiyatı değiştirilince bugün ve sonrası ESKİ fiyatta kalıyor', (tester) async {
    final bugun = DateUtils.dateOnly(DateTime.now());
    if (bugun.day == 1) return; // ayın 1'inde gün anahtarı = ay anahtarı, senaryo oluşmaz
    final ay = bugun.toString().substring(0, 7);
    await tester.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late Database db;
    late int veli;
    await tester.runAsync(() async {
      db = await testVeritabaniAc();
      final ali = await cariEkle(db, ad: 'Ali', soyad: 'Kaya');
      veli = await cariEkle(db, ad: 'Veli', soyad: 'Demir');
      await fiyatTanimla(db, ali, ay, sut: 25);
      await fiyatTanimla(db, veli, ay, sut: 25);
    });

    await tester.pumpWidget(_uygulama(db, const SutFiyatEkrani()));
    await _bekle(tester, () => find.byType(TextField).evaluate().length >= 3, 'ekran');
    // 0: toplu alan, 1: Ali, 2: Veli (alfabetik)
    await tester.enterText(find.byType(TextField).at(1), '27');
    await tester.tap(find.text('Kaydet'));
    var gunSatirlari = <Map<String, Object?>>[];
    for (var i = 0; i < 100 && gunSatirlari.isEmpty; i++) {
      await _biraz(tester, 1);
      gunSatirlari = (await tester.runAsync(
          () => db.query('cari_fiyatlar', where: 'ay = ?', whereArgs: [CariFiyat.anahtar(bugun)])))!;
    }
    await _biraz(tester, 10);

    // Kullanıcı Veli'nin TÜM AY fiyatını 26 yapar ("Ayın başından").
    await tester.tap(find.byKey(const ValueKey('fiyatAyBasindan')));
    await _biraz(tester, 15);
    await _bekle(tester, () => find.byType(TextField).evaluate().length >= 3, 'ay başı yüklendi');
    await tester.enterText(find.byType(TextField).at(2), '26');
    await tester.tap(find.text('Kaydet'));
    double? veliAy;
    for (var i = 0; i < 100 && veliAy != 26; i++) {
      await _biraz(tester, 1);
      final r = (await tester.runAsync(() => db.query('cari_fiyatlar',
          where: 'cari_id = ? AND ay = ?', whereArgs: [veli, ay])))!;
      veliAy = (r.single['sut_fiyat'] as num).toDouble();
    }
    expect(veliAy, 26);

    final lookup = CariFiyatLookup(
        (await tester.runAsync(() => db.query('cari_fiyatlar')))!.map(CariFiyat.fromMap).toList());
    final veliSatirlari = gunSatirlari.where((r) => r['cari_id'] == veli).toList();
    await tester.pump(const Duration(seconds: 10));
    await tester.runAsync(() => db.close());

    expect(lookup.fiyatIcin(veli, _iso(bugun)).sutFiyat, 26,
        reason: 'Veli\'nin fiyatı hiç değişmemişti; Ali için kaydette ${CariFiyat.anahtar(bugun)} anahtarlı 25 ₺ '
            'kopyası yazıldığından ay başı değişikliği bugünden itibaren geçersiz kaldı');
    expect(veliSatirlari, isEmpty, reason: 'fiyatı değişmeyen cariye gün satırı açılmamalı (koddaki yorumun amacı)');
  });

  // ─────────────────────────── EKSTRE EKRANI ───────────────────────────
  testWidgets(
      'DÜZELTİLDİ: tarih filtreli ekstrede cari GENELDE BORÇLU iken dönem netine bakıp "Cari Alacaklı — Ödenecek" yazıyor',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final bugun = DateUtils.dateOnly(DateTime.now());
    final buAyBasi = DateTime(bugun.year, bugun.month, 1);
    final gecenAy = DateTime(bugun.year, bugun.month - 1, 10);
    late Database db;
    late Cari ali;
    await tester.runAsync(() async {
      db = await testVeritabaniAc();
      final id = await cariEkle(db, ad: 'Ali', soyad: 'Kaya');
      ali = Cari.fromMap((await db.query('cariler', where: 'id = ?', whereArgs: [id])).single);
      await _tamFiyat(db, id, _iso(gecenAy).substring(0, 7), sut: 20, sutYemi: 10);
      await db.insert('yemler', {'cari_id': id, 'tarih': _iso(gecenAy), 'sut_yemi': 100, 'toplam': 100});
      await db.insert('sutler', {'cari_id': id, 'tarih': _iso(buAyBasi), 'sabah': 10, 'aksam': 0, 'toplam': 10});
    });
    await tester.pumpWidget(_uygulama(db, CariHesapEkstresiEkrani(cari: ali)));
    await _bekle(tester, () => find.textContaining('Cari Borçlu').evaluate().isNotEmpty, 'ekstre');
    expect(find.text('Cari Borçlu — Tahsil Edilecek'), findsOneWidget, reason: 'genel bakiye -800');

    await tester.tap(find.text('Tüm Zamanlar'));
    await tester.pumpAndSettle();
    final ctx = tester.element(find.byType(CariHesapEkstresiEkrani));
    final kaydet = MaterialLocalizations.of(ctx).saveButtonLabel;
    await tester.tap(find.text(kaydet).last);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await _bekle(tester, () => find.text('Dönem Neti').evaluate().isNotEmpty, 'filtreli ekstre');
    final yanlisEtiket = find.text('Cari Alacaklı — Ödenecek').evaluate().isNotEmpty;
    await tester.runAsync(() => db.close());
    expect(yanlisEtiket, isFalse,
        reason: 'Bu ay +200 ₺ süt var ama cari toplamda 800 ₺ BORÇLU; ekran "Ödenecek ₺200" diyor, '
            'Raporlar → Cari Ekstre aynı aralıkta devirle -800 gösteriyor');
  });

  testWidgets('KONTROL: ekstrede Tahsilat Al — geçersiz giriş reddedilir, Onayla\'ya çift dokunma TEK kayıt, bakiye yenilenir',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late Database db;
    late Cari ali;
    await tester.runAsync(() async {
      db = await testVeritabaniAc();
      final id = await cariEkle(db, ad: 'Ali', soyad: 'Kaya');
      ali = Cari.fromMap((await db.query('cariler', where: 'id = ?', whereArgs: [id])).single);
    });
    await tester.pumpWidget(_uygulama(db, CariHesapEkstresiEkrani(cari: ali)));
    await _bekle(tester, () => find.text('Hesap Kapalı').evaluate().isNotEmpty, 'ekstre');

    await tester.tap(find.text('Tahsilat Al'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '12,5x');
    await tester.tap(find.text('Onayla'));
    await tester.pump();
    expect(find.text('Geçerli bir tutar girin'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '1.250,55');
    await tester.tap(find.text('Onayla'));
    await tester.tap(find.text('Onayla'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(CariHesapEkstresiEkrani), findsOneWidget, reason: 'çift dokunma ekstreyi kapatmadı');
    await _bekle(tester, () => find.text('Cari Alacaklı — Ödenecek').evaluate().isNotEmpty, 'bakiye yenilendi');
    final kayitlar = (await tester.runAsync(() => db.query('cari_odemeler')))!;
    await tester.pump(const Duration(seconds: 10));
    await tester.runAsync(() => db.close());
    expect(kayitlar, hasLength(1));
    expect(kayitlar.single['islem_turu'], 'tahsilat');
    expect(kayitlar.single['toplam_tutar'], 1250.55);
  });

  testWidgets('DÜZELTİLDİ: ödeme formu "0,001" tutarını kabul edip kapanıyor (kuruşa yuvarlanınca 0) — form içinde reddetmeli',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late Database db;
    late Cari ali;
    await tester.runAsync(() async {
      db = await testVeritabaniAc();
      final id = await cariEkle(db, ad: 'Ali', soyad: 'Kaya');
      ali = Cari.fromMap((await db.query('cariler', where: 'id = ?', whereArgs: [id])).single);
    });
    await tester.pumpWidget(_uygulama(db, CariHesapEkstresiEkrani(cari: ali)));
    await _bekle(tester, () => find.text('Hesap Kapalı').evaluate().isNotEmpty, 'ekstre');
    await tester.tap(find.text('Ödeme Yap'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '0,001');
    await tester.tap(find.text('Onayla'));
    await _biraz(tester, 10);
    final formAcik = find.text('Onayla').evaluate().isNotEmpty;
    final hataMetni = find.text('Geçerli bir tutar girin').evaluate().isNotEmpty;
    final ingilizceHata = find.textContaining('Invalid argument').evaluate().isNotEmpty;
    await tester.pump(const Duration(seconds: 10));
    await tester.runAsync(() => db.close());
    expect(ingilizceHata, isFalse, reason: 'kullanıcı "Kayıt yapılamadı: Invalid argument(s)…" görüyor');
    expect(formAcik && hataMetni, isTrue, reason: 'form açık kalıp "Geçerli bir tutar girin" demeli');
  });
}
