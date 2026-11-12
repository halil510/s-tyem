// AJAN SENKRON — EKRANLAR, YAŞAM DÖNGÜSÜ VE GERÇEK KULLANICI SENARYOLARI (2-3 telefon).
// "BUG: ..." testleri DOĞRU davranışı bekler (hata varken başarısız olur).
// "KONTROL: ..." testleri doğrulanmış doğru davranıştır (geçmeli).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/core/providers/database_provider.dart';
import 'package:sutyem_pro/data/repositories/cari_odeme_repository.dart';
import 'package:sutyem_pro/data/repositories/cari_repository.dart';
import 'package:sutyem_pro/data/repositories/fiyat_repository.dart';
import 'package:sutyem_pro/data/repositories/sut_repository.dart';
import 'package:sutyem_pro/data/repositories/yem_repository.dart';
import 'package:sutyem_pro/features/donem/donem_servisi.dart';
import 'package:sutyem_pro/features/raporlar/rapor_modeli.dart';
import 'package:sutyem_pro/features/raporlar/rapor_servisi.dart';
import 'package:sutyem_pro/models/cari_odeme_model.dart';
import 'package:sutyem_pro/models/yem_model.dart';
import 'package:sutyem_pro/senkron/bulut_kanali.dart';
import 'package:sutyem_pro/senkron/senk_cekirdek.dart';
import 'package:sutyem_pro/senkron/senkron_ekrani.dart';
import 'package:sutyem_pro/senkron/senkron_yoneticisi.dart';

import '../helpers/test_db.dart';
import '../senkron/senkron_test.dart' show Cihaz, cihaz, aktar, esitle, say;

const g10 = '2026-11-10';
const g20 = '2026-11-20';

Future<void> bekle() => Future<void>.delayed(const Duration(milliseconds: 3));

/// Bakiyeler cari ADINA göre (yerel id her telefonda farklı).
Future<Map<String, double>> bakiyeAdla(Cihaz c) async {
  final b = await c.bakiyeler();
  final adlar = {for (final r in await c.db.query('cariler')) r['id'] as int: r['ad'] as String};
  return {for (final e in b.entries) adlar[e.key] ?? '#${e.key}': e.value};
}

RaporServisi rapor(Database db) => RaporServisi(
      cariRepo: CariRepository(db),
      sutRepo: SutRepository(db),
      yemRepo: YemRepository(db),
      fiyatRepo: CariFiyatRepository(db),
      odemeRepo: CariOdemeRepository(db),
    );

Future<String> raporMetni(Database db, RaporTuru tur) async {
  final t = await rapor(db).olustur(tur, const RaporFiltresi(bas: '2026-11-01', bit: '2026-11-30'));
  return jsonEncode(t.satirlar.map((s) => s.map((h) => h?.toString()).toList()).toList());
}

/// Bulut/LAN gibi parça parça (limit 300) gönderim: telefon günlerce internetsiz kaldıysa.
Future<void> parcaliAktar(Cihaz kimden, Cihaz kime, {int limit = 300}) async {
  var sonra = kimden.gonderilen[kime.ad] ?? 0;
  while (true) {
    final (kayitlar, sonId) =
        await SenkCekirdek(kimden.db).gonderilecekler(sonra: sonra, haricKaynak: 'kanal:${kime.ad}', limit: limit);
    if (sonId == sonra) break;
    final s = await kime.db.transaction((txn) => SenkCekirdek(txn).uygula(kayitlar, kanal: 'kanal:${kimden.ad}'));
    expect(s.hatali, 0, reason: (await kime.db.query('senk_hatalar')).toString());
    sonra = sonId;
  }
  kimden.gonderilen[kime.ad] = sonra;
}

/// Patron telefonu merkez (bulut/ana cihaz gibi); toplayıcılar ona eşitlenir.
Future<void> yildizEsitle(Cihaz p, List<Cihaz> digerleri) async {
  for (var i = 0; i < 2; i++) {
    for (final d in digerleri) {
      await esitle(p, d);
    }
  }
}

void main() {
  // ═══════════════════════════ GERÇEK KULLANIM SENARYOLARI ═══════════════════════════
  group('Senaryo — patron + 2 toplayıcı', () {
    late Cihaz p, t1, t2;
    setUp(() async {
      p = await cihaz('P');
      t1 = await cihaz('T1');
      t2 = await cihaz('T2');
    });
    tearDown(() {
      for (final c in [p, t1, t2]) {
        c.c.dispose();
      }
    });

    Future<void> carileriKur() async {
      for (final ad in ['Ali', 'Veli', 'Can']) {
        final id = await cariEkle(p.db, ad: ad, soyad: 'K');
        await fiyatTanimla(p.db, id, '2026-11', sut: 20, sutYemi: 12);
      }
      await yildizEsitle(p, [t1, t2]);
    }

    List<GunlukSutGirdisi> girdiler(Map<int, (double, double)> m) =>
        [for (final e in m.entries) GunlukSutGirdisi(cariId: e.key, sabah: e.value.$1, aksam: e.value.$2)];

    test(
        'KONTROL: T1 sabah rotası, T2 (internetsiz) akşam rotası Hızlı Süt ile; patron yem/ödeme/tahsilat + ay ortası fiyat → '
        'üç telefonda süt satırları birleşik, bakiyeler ve raporlar (bakiye listesi, cari hesap özeti, günlük süt) aynı', () async {
      await carileriKur();
      Future<Map<int, (double, double)>> m(Cihaz c, List<double> deger, {required bool sabah}) async => {
            for (var i = 0; i < 3; i++)
              await c.cariId(['Ali', 'Veli', 'Can'][i]): sabah ? (deger[i], 0) : (0, deger[i]),
          };
      // 10 Kasım
      await SutRepository(t1.db).topluGunlukKaydet(g10, girdiler(await m(t1, [40, 30, 20], sabah: true)), kayitliOgunuKoru: true);
      await bekle();
      await SutRepository(t2.db).topluGunlukKaydet(g10, girdiler(await m(t2, [35, 25, 15], sabah: false)), kayitliOgunuKoru: true);
      // 20 Kasım (T2 hâlâ internetsiz — iki gün de birikmiş)
      await SutRepository(t1.db).topluGunlukKaydet(g20, girdiler(await m(t1, [41, 31, 21], sabah: true)), kayitliOgunuKoru: true);
      await bekle();
      await SutRepository(t2.db).topluGunlukKaydet(g20, girdiler(await m(t2, [36, 26, 16], sabah: false)), kayitliOgunuKoru: true);
      // Patron: Can'ın süt fiyatı 15 Kasım'dan itibaren 25; Ali'ye yem, Veli'ye ödeme, Can'dan tahsilat.
      await fiyatTanimla(p.db, await p.cariId('Can'), '2026-11-15', sut: 25, sutYemi: 12);
      await p.yem.insert(Yem(cariId: await p.cariId('Ali'), tarih: g10, sutYemi: 50));
      await p.odeme.insert(CariOdeme(cariId: await p.cariId('Veli'), tarih: g10, islemTuru: 'odeme', miktar: 1, birimFiyat: 300, toplamTutar: 300));
      await p.odeme.insert(CariOdeme(cariId: await p.cariId('Can'), tarih: g20, islemTuru: 'tahsilat', miktar: 1, birimFiyat: 100, toplamTutar: 100));

      await yildizEsitle(p, [t1, t2]);

      for (final c in [p, t1, t2]) {
        expect(await say(c.db, 'sutler'), 6, reason: c.ad);
        final ali = (await c.sutSatiri('Ali', g20))!;
        expect([ali['sabah'], ali['aksam'], ali['toplam']], [41.0, 36.0, 77.0], reason: c.ad);
      }
      final beklenen = {
        'Ali': (75 + 77) * 20.0 - 50 * 12,
        'Veli': (55 + 57) * 20.0 - 300,
        'Can': 35 * 20.0 + 37 * 25.0 + 100,
      };
      for (final c in [p, t1, t2]) {
        expect(await bakiyeAdla(c), beklenen, reason: c.ad);
      }
      for (final tur in [RaporTuru.bakiyeListesi, RaporTuru.cariHesapOzeti, RaporTuru.gunlukSut, RaporTuru.cariSutToplami]) {
        final pm = await raporMetni(p.db, tur);
        expect(await raporMetni(t1.db, tur), pm, reason: '$tur T1');
        expect(await raporMetni(t2.db, tur), pm, reason: '$tur T2');
      }
    });

    test('KONTROL: eşitlemeden sonra eski ekranla Hızlı Süt Girişi başka telefonun girdiği öğünü EZEMEZ — '
        'KayitliOgunHatasi, topluda hiçbir satır yazılmaz, günlüğe bir şey gitmez', () async {
      await carileriKur();
      await t1.sut.gunlukKaydet(cariId: await t1.cariId('Ali'), tarih: g10, sabah: 40, aksam: 0, kayitliOgunuKoru: true);
      await esitle(t1, p);
      await esitle(p, t2); // T2 arka planda eşitlendi; ekranı eski (Ali'nin sabahı boş görünüyor)
      final gunlukOnce = await say(t2.db, 'senk_gunluk');
      await expectLater(
        t2.sut.topluGunlukKaydet(
            g10,
            girdiler({
              await t2.cariId('Veli'): (30, 0),
              await t2.cariId('Ali'): (42, 0), // çakışan öğün
            }),
            kayitliOgunuKoru: true),
        throwsA(isA<KayitliOgunHatasi>()),
      );
      expect(await say(t2.db, 'sutler'), 1, reason: 'Veli de yazılmamalı (ya hep ya hiç)');
      expect((await t2.sutSatiri('Ali', g10))!['sabah'], 40.0);
      expect(await say(t2.db, 'senk_gunluk'), gunlukOnce);
    });

    test(
        'BUG: iki toplayıcı (biri internetsiz) AYNI carinin AYNI öğününe farklı kg girer → biri SESSİZCE silinir; '
        'Hızlı Süt\'teki "girilmiş öğün değiştirilemez" kuralı eşitlemede atlanır, hiçbir telefonda çakışma kaydı/uyarısı yok', () async {
      await carileriKur();
      await t1.sut.topluGunlukKaydet(g10, girdiler({await t1.cariId('Ali'): (40, 0)}), kayitliOgunuKoru: true);
      await bekle();
      await t2.sut.topluGunlukKaydet(g10, girdiler({await t2.cariId('Ali'): (42, 0)}), kayitliOgunuKoru: true);
      await yildizEsitle(p, [t1, t2]);
      // Davranış: son yazan (T2: 42) kazanır, T1'in 40 kg'ı her yerde kaybolur.
      for (final c in [p, t1, t2]) {
        expect((await c.sutSatiri('Ali', g10))!['sabah'], 42.0, reason: c.ad);
      }
      var cakisma = 0;
      for (final c in [p, t1, t2]) {
        cakisma += await say(c.db, "senk_hatalar WHERE tablo = 'sutler'");
      }
      expect(cakisma, greaterThan(0),
          reason: 'Girilmiş bir öğün başka telefonun değeriyle değişti (40 → 42 kg, 40 TL fark); '
              'en az bir telefonda "Eşitleme sorunları" kartında görünmeliydi');
    });

    test(
        'BUG: patron Ekim\'i kapatır; T2 (internetsiz) aynı ay için önceden girdiği sütü sonra gönderir → kayıt kapalı aya girer '
        'ama donmuş BORDRO (hakediş) güncellenmez: bordro ≠ canlı hesap, bakiye ≠ bordro', () async {
      final ali = await cariEkle(p.db, ad: 'Ali', soyad: 'K');
      await fiyatTanimla(p.db, ali, '2026-10', sut: 20);
      await esitle(p, t2);
      await p.sut.gunlukKaydet(cariId: ali, tarih: '2026-10-05', sabah: 50, aksam: 0);
      await t2.sut.gunlukKaydet(cariId: await t2.cariId('Ali'), tarih: '2026-10-15', sabah: 10, aksam: 0); // T2 internetsiz
      await DonemServisi(p.db).kapat('2026-10', simdi: DateTime(2026, 11, 12));
      await esitle(p, t2);
      for (final c in [p, t2]) {
        expect(await say(c.db, "sutler WHERE tarih LIKE '2026-10%'"), 2, reason: '${c.ad}: kayıt kaybolmamalı');
      }
      final bordro = (await DonemServisi(p.db).bilgi('2026-10')).satirlar.single;
      final canli = (await DonemServisi(p.db).hesapla('2026-10')).single;
      expect(bordro.sutKg, canli.sutKg,
          reason: 'Kapalı ayın bordrosu ${bordro.sutKg} kg / ${bordro.donemSonu} TL gösteriyor, gerçek ${canli.sutKg} kg / '
              '${canli.donemSonu} TL. Üreticiye bordroyla ödeme yapılırsa geç gelen süt ödenmez, bakiye ile bordro uyuşmaz '
              've hiçbir telefonda uyarı yok.');
    });

    test('KONTROL: patron cariyi pasife alırken toplayıcı (internetsiz) o cariye süt girer → süt kaybolmaz, cari iki telefonda da pasif, '
        'rotadan çıkar, bakiyeler aynı', () async {
      await carileriKur();
      await p.cari.siraAta(await p.cariId('Veli'), 1);
      await esitle(p, t1);
      await t1.sut.gunlukKaydet(cariId: await t1.cariId('Veli'), tarih: g10, sabah: 30, aksam: 0, kayitliOgunuKoru: true);
      await p.cari.pasifeAl(await p.cariId('Veli'));
      await esitle(p, t1);
      for (final c in [p, t1]) {
        final v = (await c.db.query('cariler', where: "ad = 'Veli'")).single;
        expect([v['aktif'], v['sira']], [0, null], reason: c.ad);
        expect((await c.sutSatiri('Veli', g10))!['sabah'], 30.0, reason: c.ad);
      }
      expect(await bakiyeAdla(t1), await bakiyeAdla(p));
    });

    test('KONTROL: aynı cariye iki telefondan aynı gün ödeme ve tahsilat → ikisi de kalır, tekrar tekrar eşitlemede çoğalmaz', () async {
      await carileriKur();
      await t1.odeme.insert(CariOdeme(cariId: await t1.cariId('Ali'), tarih: g10, islemTuru: 'odeme', miktar: 1, birimFiyat: 200, toplamTutar: 200));
      await t2.odeme.insert(CariOdeme(cariId: await t2.cariId('Ali'), tarih: g10, islemTuru: 'odeme', miktar: 1, birimFiyat: 200, toplamTutar: 200));
      await p.odeme.insert(CariOdeme(cariId: await p.cariId('Ali'), tarih: g10, islemTuru: 'tahsilat', miktar: 1, birimFiyat: 50, toplamTutar: 50));
      for (var i = 0; i < 3; i++) {
        await yildizEsitle(p, [t1, t2]);
      }
      for (final c in [p, t1, t2]) {
        expect(await say(c.db, 'cari_odemeler'), 3, reason: c.ad);
        expect((await bakiyeAdla(c))['Ali'], -350.0, reason: c.ad);
      }
    });

    test(
        'KONTROL: T2 40 gün internetsiz (süt+yem 400+ değişiklik, bazıları düzeltilmiş/silinmiş); patron aynı günlerde başka öğünleri '
        'girer → 300\'lük parçalarla gönderimde hiçbir kayıt kaybolmaz, çoğalmaz, bakiyeler aynı', () async {
      await carileriKur();
      final idler = [for (final ad in ['Ali', 'Veli', 'Can']) await t2.cariId(ad)];
      final pIdler = [for (final ad in ['Ali', 'Veli', 'Can']) await p.cariId(ad)];
      final yemIdleri = <int>[];
      for (var d = 0; d < 40; d++) {
        final tarih = DateTime(2026, 9, 1).add(Duration(days: d));
        final t = '${tarih.year}-${tarih.month.toString().padLeft(2, '0')}-${tarih.day.toString().padLeft(2, '0')}';
        for (var i = 0; i < 3; i++) {
          await t2.sut.gunlukKaydet(cariId: idler[i], tarih: t, sabah: 10.0 + i, aksam: 0);
          yemIdleri.add(await t2.yem.insert(Yem(cariId: idler[i], tarih: t, sutYemi: 1)));
          await p.sut.gunlukKaydet(cariId: pIdler[i], tarih: t, sabah: 0, aksam: 5.0 + i);
        }
      }
      for (final y in yemIdleri.take(10)) {
        await t2.yem.delete(y);
      }
      expect(await say(t2.db, 'senk_gunluk'), greaterThan(300));
      for (var i = 0; i < 3; i++) {
        await parcaliAktar(p, t2);
        await parcaliAktar(t2, p);
      }
      for (final c in [p, t2]) {
        expect(await say(c.db, 'sutler'), 120, reason: c.ad);
        expect(await say(c.db, 'yemler'), 110, reason: c.ad);
        expect(await say(c.db, 'sutler WHERE sabah = 0 OR aksam = 0'), 0, reason: '${c.ad}: öğünler birleşmeli');
      }
      expect(await bakiyeAdla(t2), await bakiyeAdla(p));
    });
  });

  // ═══════════════════════════ BULUT FORMU / BAĞLANTI ═══════════════════════════
  group('Bulut formu doğrulaması', () {
    tearDown(() async {
      BulutKanali.testIstemci = null;
      SenkronYoneticisi.testCihaz = null;
      await SenkronYoneticisi().testSifirla();
    });

    test(
        'BUG (güvenlik): "http://" (şifresiz bağlantı) adresle Bağlan → işletme ŞİFRESİ düz metin olarak ağa gönderilir; '
        'https zorunlu olmalı', () async {
      final db = await testVeritabaniAc();
      SenkronYoneticisi.testCihaz = 'cihaz-A';
      final y = SenkronYoneticisi();
      await y.baslat(db);
      final giden = <Uri>[];
      BulutKanali.testIstemci = () => MockClient((rq) async {
            giden.add(rq.url);
            return http.Response(jsonEncode({'yeni': true}), 200, headers: {'content-type': 'application/json'});
          });
      Object? hata;
      try {
        await y.bulutBaglan(const BulutAyari(url: 'http://deneme.supabase.co', anahtar: 'sb_publishable_x', isletme: 'kabatli', sifre: 'gizli123'));
      } catch (e) {
        hata = e;
      }
      expect(giden.where((u) => u.scheme == 'http'), isEmpty,
          reason: 'Şifre (p_sifre) şu adrese şifrelenmeden gönderildi: $giden. Hata: $hata');
    });

    test('KONTROL: "https://" yazılmadan girilen adres (ör. deneme.supabase.co) çökmez, BulutHatasi olarak bildirilir', () async {
      final k = BulutKanali(const BulutAyari(url: 'deneme.supabase.co', anahtar: 'sb_publishable_x', isletme: 'kabatli', sifre: 'gizli123'));
      Object? hata;
      try {
        await k.baglan(cihaz: 'c', cihazAd: 'Telefon');
      } catch (e) {
        hata = e;
      } finally {
        k.kapat();
      }
      expect(hata, isA<BulutHatasi>(), reason: 'Gelen: ${hata.runtimeType}: $hata');
    });
  });

  // ═══════════════════════════ EKRAN (widget) ═══════════════════════════
  group('Çoklu Cihaz ve Bulut ekranı', () {
    tearDown(() async {
      BulutKanali.testIstemci = null;
      SenkronYoneticisi.testCihaz = null;
      await SenkronYoneticisi().testSifirla();
    });

    Future<Database> hazirla(WidgetTester t, {Map<String, String> ayarlar = const {}}) async {
      late Database db;
      await t.runAsync(() async {
        db = await testVeritabaniAc();
        SenkronYoneticisi.testCihaz = 'cihaz-test-uzun-kimlik';
        await SenkronYoneticisi().testSifirla();
        await SenkronYoneticisi().baslat(db); // sunucu açılmasın diye ayarlar SONRA yazılır
        for (final e in ayarlar.entries) {
          await db.insert('senk_ayarlar', {'anahtar': e.key, 'deger': e.value});
        }
      });
      return db;
    }

    Future<void> pompala(WidgetTester t, [int n = 15]) async {
      for (var i = 0; i < n; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
        await t.pump();
      }
    }

    Widget uygulama(Database db, {Widget home = const SenkronEkrani()}) => ProviderScope(
          overrides: [databaseProvider.overrideWith((ref) => db)],
          child: MaterialApp(
            locale: const Locale('tr', 'TR'),
            supportedLocales: const [Locale('tr', 'TR')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate
            ],
            home: home,
          ),
        );

    Future<List<Object>> tumunuKaydirVeTopla(WidgetTester t) async {
      final hatalar = <Object>[];
      void al() {
        Object? e;
        while ((e = t.takeException()) != null) {
          hatalar.add(e!);
        }
      }

      al();
      for (var i = 0; i < 12; i++) {
        await t.drag(find.byType(Scrollable).first, const Offset(0, -300));
        await t.pump();
        al();
      }
      return hatalar;
    }

    const bulutAyarlar = {
      'bulut_url': 'https://cok-uzun-bir-proje-adresi-abcdefghijkl.supabase.co',
      'bulut_anahtar': 'sb_publishable_test',
      'isletme': 'kabatli-sut-ve-yem-isletmesi',
      'isletme_sifre': 'gizli123',
    };

    for (final (ad, ayarlar) in <(String, Map<String, String>)>[
      ('bulut formu + LAN kapalı', const {}),
      ('bulut bağlı + LAN bağlı', {...bulutAyarlar, 'lan_rol': 'bagli', 'lan_adres': '192.168.100.200', 'lan_istemci_kod': '123456'}),
      ('LAN ana cihaz', const {'lan_rol': 'ana', 'lan_kod': '987654'}),
    ]) {
      testWidgets('KONTROL: 360 px telefonda, yazı ölçeği 2.0 ile ($ad) taşma/istisna yok', (t) async {
        t.view.physicalSize = const Size(360, 740);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final db = await hazirla(t, ayarlar: ayarlar);
        await t.pumpWidget(uygulama(db));
        await pompala(t);
        final hatalar = await tumunuKaydirVeTopla(t);
        expect(hatalar, isEmpty, reason: hatalar.join('\n---\n'));
      });
    }

    testWidgets('KONTROL: bulut formu boşken "Bağlan ve eşitle" → "Dört alanı da doldurun." mesajı; hiçbir ayar yazılmaz', (t) async {
      t.view.physicalSize = const Size(360, 740);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      final db = await hazirla(t);
      await t.pumpWidget(uygulama(db));
      await pompala(t);
      final buton = find.widgetWithText(FilledButton, 'Bağlan ve eşitle').first;
      await t.ensureVisible(buton);
      await t.pump();
      await t.tap(buton);
      await pompala(t, 8);
      expect(find.text('Dört alanı da doldurun.'), findsOneWidget);
      late List<Map<String, Object?>> a;
      await t.runAsync(() async => a = await db.query('senk_ayarlar', where: "anahtar LIKE 'bulut%' OR anahtar LIKE 'isletme%'"));
      expect(a, isEmpty);
      expect(t.takeException(), isNull);
    });

    testWidgets(
        'BUG: ana cihaz "Bağlı"ya geçirilince sunucu kapanır ama rol KAYDEDİLMEZ (lan_rol hâlâ "ana") → '
        'uygulama yeniden açılınca telefon kendiliğinden yine ana cihaz olur', (t) async {
      t.view.physicalSize = const Size(360, 740);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      final db = await hazirla(t, ayarlar: const {'lan_rol': 'ana', 'lan_kod': '987654'});
      await t.pumpWidget(uygulama(db));
      await pompala(t);
      await t.scrollUntilVisible(find.text('Kodu değiştir'), 200, scrollable: find.byType(Scrollable).first);
      await t.pump();
      expect(find.text('Kod: 987654'), findsOneWidget);
      final bagli = find.text('Bağlı');
      await t.ensureVisible(bagli);
      await t.pump();
      await t.tap(bagli);
      await pompala(t, 8);
      expect(find.text('Ana cihaz adresi'), findsOneWidget, reason: 'ekran Bağlı görünümüne geçti');
      late String? rol;
      await t.runAsync(() async => rol = await SenkronYoneticisi().ayar(SenkAyar.lanRol));
      expect(rol, isNot('ana'),
          reason: 'Sunucu durduruldu ama ayar "ana" kaldı: bir sonraki açılışta baslat() → _yerelAgiKur() sunucuyu yeniden açar, '
              'ekran tekrar "Ana cihaz" gösterir; telefon hem ana hem (kullanıcının sandığı) bağlı olamaz.');
    });

    testWidgets(
        'BUG: "Şimdi eşitle" sürerken kullanıcı ekrandan çıkarsa eşitleme bitince _islem → _yukle kapanmış ekranın ref\'ini kullanır '
        '(yakalanmamış istisna)', (t) async {
      t.view.physicalSize = const Size(360, 740);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      final kapi = Completer<void>();
      BulutKanali.testIstemci = () => MockClient((rq) async {
            await kapi.future;
            final fn = rq.url.pathSegments.last;
            return http.Response(fn == 'sutyem_cek' ? '[]' : '{"yazilan":0}', 200, headers: {'content-type': 'application/json'});
          });
      final db = await hazirla(t, ayarlar: bulutAyarlar);
      await t.pumpWidget(uygulama(db,
          home: Builder(
              builder: (c) => Scaffold(
                  body: Center(
                      child: TextButton(
                          onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const SenkronEkrani())),
                          child: const Text('aç')))))));
      await t.tap(find.text('aç'));
      await pompala(t, 20);
      expect(find.byKey(const ValueKey('bulutEsitle')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('bulutEsitle')));
      await t.pump();
      // Kullanıcı geri tuşuna basar.
      Navigator.of(t.element(find.byType(SenkronEkrani))).pop();
      await pompala(t, 10);
      expect(find.byType(SenkronEkrani), findsNothing);
      kapi.complete();
      await pompala(t, 20);
      final ex = t.takeException();
      expect(ex, isNull, reason: '$ex');
    });
  });
  // ═══════════════════════════ YAŞAM DÖNGÜSÜ ═══════════════════════════
  group('Yaşam döngüsü', () {
    tearDown(() async {
      SenkronYoneticisi.testCihaz = null;
      await SenkronYoneticisi().testSifirla();
    });

    test('KONTROL: .db değiştirilince (veritabaniDegisti) eski bağlantıyla eşitleme yapılmaz; baslat(yeni) yeni veritabanına geçer', () async {
      SenkronYoneticisi.testCihaz = 'cihaz-A';
      final y = SenkronYoneticisi();
      final eski = await testVeritabaniAc();
      await y.baslat(eski);
      await y.ayarYaz(SenkAyar.cihazAd, 'eski');
      y.veritabaniDegisti();
      await eski.close();
      expect(await y.ayar(SenkAyar.cihazAd), isNull);
      await y.otomatikEsitle(); // _db null → sessizce hiçbir şey yapmaz, kapalı db'ye dokunmaz
      final yeni = await testVeritabaniAc();
      await y.baslat(yeni);
      expect(await y.cihazAdi(), isNot('eski'));
      expect((await yeni.query('senk_durum')).single['yerel_cihaz'], 'cihaz-A');
    });

    test('KONTROL: ekran yeniden açılınca baslat aynı db için tekrar taban kurmaz (günlük/sayaçlar korunur)', () async {
      SenkronYoneticisi.testCihaz = 'cihaz-A';
      final db = await testVeritabaniAc();
      final y = SenkronYoneticisi();
      await y.baslat(db);
      await cariEkle(db, ad: 'Ali');
      await db.insert('senk_kanallar', {'kanal': 'bulut', 'son_gonderilen': 1});
      final once = await say(db, 'senk_gunluk');
      await y.baslat(db);
      await y.testSifirla();
      await y.baslat(db); // uygulama yeniden açıldı (aynı cihaz kimliği)
      expect(await say(db, 'senk_gunluk'), once);
      expect((await db.query('senk_kanallar', where: "kanal = 'bulut'")).single['son_gonderilen'], 1);
    });
  });

}
