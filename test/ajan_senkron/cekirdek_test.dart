// SENKRON ÇEKİRDEĞİ + MIGRATION v13 TETİKLEYİCİLERİ — denetim testleri.
// "BUG: ..." testleri DOĞRU davranışı bekler (hata varken başarısız olur).
// "KONTROL: ..." testleri doğrulanmış doğru davranıştır (geçmeli).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/data/repositories/cari_repository.dart';
import 'package:sutyem_pro/data/repositories/sut_repository.dart';
import 'package:sutyem_pro/data/repositories/yem_repository.dart';
import 'package:sutyem_pro/data/yedek/yedek_servisi.dart';
import 'package:sutyem_pro/features/cari_hesap/providers/cari_hesap_providers.dart';
import 'package:sutyem_pro/features/donem/donem_servisi.dart';
import 'package:sutyem_pro/models/cari_model.dart';
import 'package:sutyem_pro/models/sut_model.dart';
import 'package:sutyem_pro/models/yem_model.dart';
import 'package:sutyem_pro/senkron/senk_cekirdek.dart';

import '../helpers/test_db.dart';

class Cihaz {
  final String ad;
  final Database db;
  final Map<String, int> gonderilen = {};
  late final ProviderContainer c = testContainer(db);
  Cihaz(this.ad, this.db);
  SutRepository get sut => SutRepository(db);
  YemRepository get yem => YemRepository(db);
  CariRepository get cari => CariRepository(db);
  Future<Map<int, double>> bakiyeler() async {
    c.invalidate(tumKalanBorclarProvider);
    return c.read(tumKalanBorclarProvider.future);
  }

  Future<int> cariId(String ad) async => (await db.query('cariler', where: 'ad = ?', whereArgs: [ad])).single['id'] as int;
  Future<Map<String, Object?>?> cariSatiri(String ad) async => (await db.query('cariler', where: 'ad = ?', whereArgs: [ad])).firstOrNull;
  Future<Map<String, Object?>?> sutSatiri(String cariAd, String tarih) async {
    final r = await db.rawQuery('SELECT s.* FROM sutler s JOIN cariler c ON c.id = s.cari_id WHERE c.ad = ? AND s.tarih = ?', [cariAd, tarih]);
    return r.isEmpty ? null : r.single;
  }
}

Future<Cihaz> cihaz(String ad) async {
  final db = await testVeritabaniAc();
  await SenkCekirdek.cihazAyarla(db, 'cihaz-$ad');
  return Cihaz(ad, db);
}

Future<UygulamaSonucu> aktar(Cihaz kimden, Cihaz kime) async {
  final (kayitlar, sonId) =
      await SenkCekirdek(kimden.db).gonderilecekler(sonra: kimden.gonderilen[kime.ad] ?? 0, haricKaynak: 'kanal:${kime.ad}', limit: 100000);
  kimden.gonderilen[kime.ad] = sonId;
  return kime.db.transaction((txn) => SenkCekirdek(txn).uygula(kayitlar, kanal: 'kanal:${kimden.ad}'));
}

Future<void> esitle(Cihaz a, Cihaz b) async {
  for (var i = 0; i < 4; i++) {
    await aktar(a, b);
    await aktar(b, a);
  }
}

Future<int> say(Database db, String tablo) async => (await db.rawQuery('SELECT COUNT(*) AS n FROM $tablo')).first['n'] as int;

Future<void> bekle() => Future<void>.delayed(const Duration(milliseconds: 5));

const gun = '2026-11-10';

void main() {
  late Cihaz a, b;
  setUp(() async {
    a = await cihaz('A');
    b = await cihaz('B');
  });
  tearDown(() {
    a.c.dispose();
    b.c.dispose();
  });

  Future<void> aliHazirla() async {
    final ali = await cariEkle(a.db, ad: 'Ali', soyad: 'Kaya');
    await fiyatTanimla(a.db, ali, '2026-11', sut: 20, sutYemi: 12);
    await esitle(a, b);
  }

  // ───────────────────────── SÜT: silme ↔ öğün yarışları ─────────────────────────

  test('BUG: yedekten geri yükleme (tabanYenile), başka telefonda SONRADAN silinmiş süt satırını geri getirir', () async {
    await aliHazirla();
    await a.sut.gunlukKaydet(cariId: await a.cariId('Ali'), tarih: gun, sabah: 40, aksam: 0);
    await esitle(a, b);
    final json = YedekServisi.coz(await YedekServisi.disaAktarJson(a.db)); // yedekte süt VAR
    await bekle();
    final bSatir = (await b.sutSatiri('Ali', gun))!;
    await b.sut.delete(bSatir['id'] as int); // B yedekten SONRA siler
    await esitle(a, b);
    expect(await a.sutSatiri('Ali', gun), isNull);

    await YedekServisi.iceAktar(a.db, json, tamamenDegistir: true); // A eski yedeğe döner
    a.gonderilen.clear();
    b.gonderilen.clear();
    await esitle(a, b);
    // Belgelenen kural: "geri yüklenen eski veri diğer cihazlardaki DAHA YENİ kayıtları ezmez/silmez".
    // Silme yedekten daha yeni → satır iki telefonda da YOK olmalı.
    expect(await b.sutSatiri('Ali', gun), isNull, reason: 'B\'nin silmesi eski yedekle geri alınmamalı');
    expect(await a.sutSatiri('Ali', gun), isNull);
  });

  test('BUG: daha ESKİ süt değişikliği, karşıdaki daha YENİ silmeyi geri alır (satır diriltilir)', () async {
    await aliHazirla();
    await a.sut.gunlukKaydet(cariId: await a.cariId('Ali'), tarih: gun, sabah: 40, aksam: 0);
    await esitle(a, b);
    final aSatir = (await a.sutSatiri('Ali', gun))!;
    // A (internetsiz) akşamı düzeltir — t1
    await a.sut.update(Sut(id: aSatir['id'] as int, cariId: aSatir['cari_id'] as int, tarih: gun, sabah: 40, aksam: 35));
    await bekle();
    // B (A'nın düzeltmesini görmeden) satırı tamamen siler — t2 > t1
    final bSatir = (await b.sutSatiri('Ali', gun))!;
    await b.sut.delete(bSatir['id'] as int);
    await esitle(a, b);
    final sa = await a.sutSatiri('Ali', gun), sb = await b.sutSatiri('Ali', gun);
    // Diğer tüm tablolarda "son yazan kazanır": daha yeni silme kazanır. En azından B'nin sildiği
    // sabah 40 kg geri gelmemeli.
    expect(sb?['sabah'] ?? 0.0, 0.0, reason: 'B\'de silinen sabah 40 geri geldi: ${sb?['sabah']}');
    expect(sa?['sabah'] ?? 0.0, 0.0, reason: 'A\'da: ${sa?['sabah']}');
  });

  test('BUG: A satırı siler, B (silmeyi görmeden) yalnız akşamı ekler → A\'nın sildiği sabah iki telefonda da geri gelir', () async {
    await aliHazirla();
    await a.sut.gunlukKaydet(cariId: await a.cariId('Ali'), tarih: gun, sabah: 40, aksam: 0);
    await esitle(a, b);
    await bekle();
    await a.sut.delete((await a.sutSatiri('Ali', gun))!['id'] as int); // t1: sabah 40 yanlıştı, silindi
    await bekle();
    // B'de Süt Ekle ekranı kayıtlı sabahı korur, yalnız akşam eklenir — t2
    await b.sut.gunlukKaydet(cariId: await b.cariId('Ali'), tarih: gun, sabah: 40, aksam: 35, kayitliOgunuKoru: true);
    await esitle(a, b);
    for (final x in [a, b]) {
      final s = await x.sutSatiri('Ali', gun);
      expect(s, isNotNull, reason: '${x.ad}: B\'nin akşamı korunmalı');
      expect([s!['sabah'], s['aksam']], [0.0, 35.0], reason: '${x.ad}: sabahın zamanı (t0) silmeden (t1) eski; silinen sabah dirilmemeli');
    }
  });

  test('KONTROL: daha YENİ silme, daha eski süt satırını karşıda siler (satır değişmediyse)', () async {
    await aliHazirla();
    await a.sut.gunlukKaydet(cariId: await a.cariId('Ali'), tarih: gun, sabah: 40, aksam: 10);
    await esitle(a, b);
    await bekle();
    await b.sut.delete((await b.sutSatiri('Ali', gun))!['id'] as int);
    await esitle(a, b);
    expect(await a.sutSatiri('Ali', gun), isNull);
    expect(await b.sutSatiri('Ali', gun), isNull);
  });

  test('KONTROL: üç telefonda farklı öğün/düzeltme sonrası birleşme durulur — gönderilecekler boşalır (ping-pong yok)', () async {
    final c = await cihaz('C');
    addTearDown(c.c.dispose);
    await aliHazirla();
    await esitle(a, c);
    await esitle(b, c);
    await a.sut.gunlukKaydet(cariId: await a.cariId('Ali'), tarih: gun, sabah: 40, aksam: 0);
    await bekle();
    await b.sut.gunlukKaydet(cariId: await b.cariId('Ali'), tarih: gun, sabah: 0, aksam: 35);
    await bekle();
    await c.sut.gunlukKaydet(cariId: await c.cariId('Ali'), tarih: gun, sabah: 41, aksam: 0); // C sabahı farklı girer (daha yeni)
    for (var i = 0; i < 4; i++) {
      await esitle(a, b);
      await esitle(b, c);
      await esitle(a, c);
    }
    for (final x in [a, b, c]) {
      final s = (await x.sutSatiri('Ali', gun))!;
      expect([s['sabah'], s['aksam'], s['toplam']], [41.0, 35.0, 76.0], reason: x.ad);
    }
    // Bir tur daha: hiçbir kanalda gönderilecek bir şey kalmamalı.
    for (final (x, y) in [(a, b), (b, a), (a, c), (c, a), (b, c), (c, b)]) {
      final (k, _) = await SenkCekirdek(x.db).gonderilecekler(sonra: x.gonderilen[y.ad] ?? 0, haricKaynak: 'kanal:${y.ad}', limit: 100000);
      expect(k, isEmpty, reason: '${x.ad}→${y.ad}: ${k.map((e) => e.toJson()).toList()}');
    }
  });

  test('KONTROL: süt satırının TARİHİ değişirse (doğal anahtar) karşıda eski gün silinir, yeni gün eklenir', () async {
    await aliHazirla();
    await a.sut.gunlukKaydet(cariId: await a.cariId('Ali'), tarih: gun, sabah: 40, aksam: 5);
    await esitle(a, b);
    await a.db.rawUpdate("UPDATE sutler SET tarih = '2026-11-11'");
    await esitle(a, b);
    expect(await b.sutSatiri('Ali', gun), isNull);
    final s = (await b.sutSatiri('Ali', '2026-11-11'))!;
    expect([s['sabah'], s['aksam'], s['toplam']], [40.0, 5.0, 45.0]);
    expect(await say(b.db, 'sutler'), 1);
  });

  test('KONTROL: eşit zaman damgalı iki farklı paket (aynı an, farklı cihaz) iki telefonda aynı sonuca varır', () async {
    await aliHazirla();
    final cariUuid = (await a.db.query('cariler')).single['uuid'] as String;
    const z = '2026-11-10T05:00:00.000Z';
    SenkKayit k(String cihaz, double sabah) => SenkKayit(
        tablo: 'sutler', anahtar: '$cariUuid|$gun', zaman: z, cihaz: cihaz,
        veri: {'tarih': gun, 'sabah': sabah, 'aksam': 0.0, 'toplam': sabah, 'sabah_zaman': z, '_ref': {'cari_id': cariUuid}});
    await a.db.transaction((t) => SenkCekirdek(t).uygula([k('X', 10)], kanal: 'kanal:X'));
    await a.db.transaction((t) => SenkCekirdek(t).uygula([k('Y', 20)], kanal: 'kanal:Y'));
    await b.db.transaction((t) => SenkCekirdek(t).uygula([k('Y', 20)], kanal: 'kanal:Y'));
    await b.db.transaction((t) => SenkCekirdek(t).uygula([k('X', 10)], kanal: 'kanal:X'));
    expect((await a.sutSatiri('Ali', gun))!['sabah'], (await b.sutSatiri('Ali', gun))!['sabah']);
  });

  // ───────────────────────── Cari silme / CASCADE ─────────────────────────

  test('BUG: cari silinince CASCADE ile silinen süt/fiyat satırları günlüğe carisiz anahtarla ("|tarih") yazılır', () async {
    await aliHazirla();
    final uuid = (await a.db.query('cariler')).single['uuid'] as String;
    await a.sut.gunlukKaydet(cariId: await a.cariId('Ali'), tarih: gun, sabah: 40, aksam: 0);
    await a.db.delete('cariler');
    final silinen = await a.db.rawQuery("SELECT anahtar FROM senk_gunluk WHERE tablo IN ('sutler', 'cari_fiyatlar') AND islem = 's'");
    expect(silinen.map((r) => r['anahtar']), containsAll(['$uuid|$gun', '$uuid|2026-11']),
        reason: 'CASCADE çalışırken cari satırı zaten silinmiş; anahtar ifadesindeki alt sorgu boş döner');
  });

  test('BUG: A cariyi siler, B aynı anda o cariye süt girer → A\'da kayıt sonsuza kadar "bekliyor" kalır', () async {
    await aliHazirla();
    await b.sut.gunlukKaydet(cariId: await b.cariId('Ali'), tarih: gun, sabah: 30, aksam: 0);
    await a.cari.delete(await a.cariId('Ali'));
    await aktar(b, a); // B'nin sütü A'ya önce varır: carisi yok → bekletilir
    for (var i = 0; i < 5; i++) {
      await esitle(a, b);
    }
    expect(await say(b.db, 'cariler'), 0);
    expect(await say(b.db, 'sutler'), 0);
    final bekleyen = await a.db.query('senk_bekleyen');
    expect(bekleyen, isEmpty,
        reason: 'carisi silinmiş kayıt her turda yeniden deneniyor, ekranda sürekli "bekliyor" görünür: '
            '${bekleyen.map((r) => '${r['tablo']} ${r['anahtar']} deneme=${r['deneme']}').toList()}');
  });

  test('BUG: A cariyi siler, B (daha sonra) carinin telefonunu düzeltir → iki telefon FARKLI süt/fiyat/bakiye ile kalır', () async {
    await aliHazirla();
    await a.sut.gunlukKaydet(cariId: await a.cariId('Ali'), tarih: gun, sabah: 40, aksam: 0);
    await a.yem.insert(Yem(cariId: await a.cariId('Ali'), tarih: gun, sutYemi: 5));
    await esitle(a, b);
    await a.cari.delete(await a.cariId('Ali'));
    await bekle();
    await b.db.update('cariler', {'telefon': '555'});
    await esitle(a, b);
    final farklar = <String>[];
    for (final t in ['cariler', 'sutler', 'yemler', 'cari_fiyatlar']) {
      final na = await say(a.db, t), nb = await say(b.db, t);
      if (na != nb) farklar.add('$t A=$na B=$nb');
    }
    final ba = (await a.bakiyeler()).values.toList(), bb = (await b.bakiyeler()).values.toList();
    if ('$ba' != '$bb') farklar.add('bakiye A=$ba B=$bb');
    expect(farklar, isEmpty, reason: 'iki telefon farklı sonuca vardı');
  });

  test('BUG: A ayı kapatır, B (kapanışı görmeden) cariyi siler → A\'da KAPALI dönemin yem/bordrosu sessizce silinir', () async {
    await aliHazirla();
    final aAli = await a.cariId('Ali');
    await fiyatTanimla(a.db, aAli, '2026-10', sut: 20, sutYemi: 12);
    await a.yem.insert(Yem(cariId: aAli, tarih: '2026-10-15', sutYemi: 5));
    await esitle(a, b);
    await DonemServisi(a.db).kapat('2026-10', simdi: DateTime(2026, 11, 12)); // t1 (A)
    await bekle();
    await b.cari.delete(await b.cariId('Ali')); // t2 (B, internetsiz; B'de ay hâlâ açık)
    await esitle(a, b);
    expect(await say(a.db, "yemler WHERE tarih LIKE '2026-10%'"), 1, reason: 'kapalı ayın kaydı uzaktan silinmemeli');
    expect(await say(a.db, 'donem_hakedisleri'), greaterThan(0), reason: 'kapalı dönemin bordrosu korunmalı');
  });

  // ───────────────────────── Rota / cariler ─────────────────────────

  test('BUG: B rotaya yeni cari ekleyince A\'da aynı anda yapılan "pasife al" geri alınır (pasif cari rotaya döner)', () async {
    await aliHazirla(); // Ali sırasız
    await a.cari.update(Cari(id: await a.cariId('Ali'), ad: 'Ali', soyad: 'Kaya'), siraGuncelle: true, sira: 1);
    await a.cari.insert(Cari(ad: 'Veli', soyad: 'X'), sira: 2);
    await esitle(a, b);
    await a.cari.pasifeAl(await a.cariId('Ali')); // t1
    await bekle();
    await b.cari.insert(Cari(ad: 'Can', soyad: 'Y'), sira: 1); // t2: B tüm rotayı yeniden numaralar
    await esitle(a, b);
    for (final x in [a, b]) {
      final ali = (await x.cariSatiri('Ali'))!;
      expect(ali['aktif'], 0, reason: '${x.ad}: Ali pasife alınmıştı, rota değişikliği bunu geri almamalı');
    }
  });

  test('BUG: B rota sırası değiştirince A\'da aynı anda düzeltilen cari telefonu kaybolur', () async {
    await aliHazirla();
    await a.cari.update(Cari(id: await a.cariId('Ali'), ad: 'Ali', soyad: 'Kaya'), siraGuncelle: true, sira: 1);
    await esitle(a, b);
    await a.cari.update(Cari(id: await a.cariId('Ali'), ad: 'Ali', soyad: 'Kaya', telefon: '05321112233')); // t1
    await bekle();
    await b.cari.insert(Cari(ad: 'Can', soyad: 'Y'), sira: 1); // t2: Ali'nin sırası 2 olur
    await esitle(a, b);
    for (final x in [a, b]) {
      expect((await x.cariSatiri('Ali'))!['telefon'], '05321112233', reason: x.ad);
    }
  });

  test('KONTROL: rotaDuzelt iki telefonda aynı sırayı üretir, pasif cari rotadan çıkar ve gönderilecekler durulur', () async {
    await a.cari.insert(Cari(ad: 'Veli', soyad: 'X'), sira: 1);
    await a.cari.insert(Cari(ad: 'Pasif', soyad: 'P'), sira: 2);
    await esitle(a, b);
    await a.cari.insert(Cari(ad: 'Can', soyad: 'Y'), sira: 1);
    await b.cari.insert(Cari(ad: 'Deniz', soyad: 'Z'), sira: 1);
    await b.cari.pasifeAl(await b.cariId('Pasif'));
    await esitle(a, b);
    Future<List<Object?>> siralar(Cihaz c) async =>
        (await c.db.rawQuery("SELECT ad || ':' || COALESCE(sira, '-') AS s FROM cariler ORDER BY ad")).map((r) => r['s']).toList();
    expect(await siralar(a), await siralar(b));
    expect((await a.cariSatiri('Pasif'))!['sira'], isNull);
    for (final (x, y) in [(a, b), (b, a)]) {
      final (k, _) = await SenkCekirdek(x.db).gonderilecekler(sonra: x.gonderilen[y.ad] ?? 0, haricKaynak: 'kanal:${y.ad}');
      expect(k, isEmpty, reason: '${x.ad}→${y.ad}');
    }
  });

  // ───────────────────────── Tetikleyiciler / bayraklar ─────────────────────────

  test('KONTROL: uuid tetikleyicisi batch insert ve rawInsert ile her satıra ayrı uuid verir, günlüğe TEK satır yazar', () async {
    final batch = a.db.batch();
    for (var i = 0; i < 5; i++) {
      batch.insert('cariler', {'ad': 'K$i', 'soyad': 'S'});
    }
    await batch.commit(noResult: true);
    await a.db.rawInsert("INSERT INTO cariler (ad, soyad) VALUES ('R', 'S')");
    await a.db.rawInsert("INSERT INTO cariler (ad, soyad) SELECT 'Q' || ad, soyad FROM cariler WHERE ad LIKE 'K%'");
    final cariler = await a.db.query('cariler');
    expect(cariler.length, 11);
    expect(cariler.map((r) => r['uuid']).toSet().length, 11);
    expect(cariler.every((r) => (r['uuid'] as String?)?.length == 32), isTrue);
    final gunluk = await a.db.rawQuery("SELECT anahtar, COUNT(*) AS n FROM senk_gunluk WHERE tablo = 'cariler' GROUP BY anahtar");
    expect(gunluk.length, 11);
    expect(gunluk.every((r) => r['n'] == 1), isTrue);
    expect(await say(a.db, "senk_gunluk WHERE tablo = 'cariler' AND anahtar IS NULL"), 0);
  });

  test('KONTROL: hatalı kayıt uygula\'da yakalanır; uygulaniyor bayrağı sıfırlanır, dönem kilidi yerel yazımda yeniden çalışır', () async {
    await aliHazirla();
    await DonemServisi(a.db).kapat('2026-10', simdi: DateTime(2026, 11, 12));
    final cariUuid = (await a.db.query('cariler')).single['uuid'] as String;
    // tarih yok (NOT NULL) → insert hata verir
    final bozuk = SenkKayit(tablo: 'yemler', anahtar: 'bozuk-uuid', zaman: SenkCekirdek.simdiUtc(), cihaz: 'X', veri: {
      'sut_yemi': 1.0,
      '_ref': {'cari_id': cariUuid}
    });
    final s = await a.db.transaction((t) => SenkCekirdek(t).uygula([bozuk], kanal: 'kanal:X'));
    expect(s.hatali, 1);
    expect((await a.db.query('senk_durum')).single['uygulaniyor'], 0);
    expect(await say(a.db, 'senk_hatalar'), 1);
    expect(await say(a.db, 'senk_bekleyen'), 1);
    await expectLater(a.yem.insert(Yem(cariId: await a.cariId('Ali'), tarih: '2026-10-20', sutYemi: 1)), throwsA(anything));
    await expectLater(a.db.insert('sutler', {'cari_id': await a.cariId('Ali'), 'tarih': '2026-10-20', 'sabah': 1}), throwsA(anything));
  });

  test('KONTROL: uygula dışarı istisna fırlatırsa (transaction geri alınır) uygulaniyor bayrağı 1\'de takılı kalmaz', () async {
    await aliHazirla();
    try {
      await a.db.transaction((t) async {
        await SenkCekirdek(t).uygula(const [], kanal: 'kanal:X');
        await t.rawUpdate('UPDATE senk_durum SET uygulaniyor = 1 WHERE tek = 1');
        throw StateError('kesinti');
      });
    } on StateError catch (_) {}
    expect((await a.db.query('senk_durum')).single['uygulaniyor'], 0);
  });

  test('KONTROL: cari_fiyatlar \'yyyy-MM\' ve \'yyyy-MM-dd\' karışık anahtarlar ayrı ayrı eşitlenir, bakiye aynı', () async {
    final ali = await cariEkle(a.db, ad: 'Ali', soyad: 'Kaya');
    await fiyatTanimla(a.db, ali, '2026-11', sut: 20);
    await fiyatTanimla(a.db, ali, '2026-11-15', sut: 25);
    await a.sut.gunlukKaydet(cariId: ali, tarih: gun, sabah: 10, aksam: 0);
    await a.sut.gunlukKaydet(cariId: ali, tarih: '2026-11-20', sabah: 10, aksam: 0);
    await esitle(a, b);
    expect(await say(b.db, 'cari_fiyatlar'), 2);
    expect((await b.bakiyeler())[await b.cariId('Ali')], (await a.bakiyeler())[ali]);
  });

  test('KONTROL: dönem kapatma (donemler + donem_hakedisleri iç içe doğal anahtar) karşıya çoğalmadan geçer, tekrar eşitlemede değişmez', () async {
    await aliHazirla();
    await fiyatTanimla(a.db, await a.cariId('Ali'), '2026-10', sut: 20, sutYemi: 12);
    await a.yem.insert(Yem(cariId: await a.cariId('Ali'), tarih: '2026-10-15', sutYemi: 5));
    await DonemServisi(a.db).kapat('2026-10', simdi: DateTime(2026, 11, 12));
    await esitle(a, b);
    expect(await say(b.db, 'donemler'), 1);
    expect(await say(b.db, 'donem_hakedisleri'), greaterThan(0));
    expect(await say(b.db, 'donem_hakedisleri'), await say(a.db, 'donem_hakedisleri'));
    final s = await aktar(a, b);
    expect(s.uygulanan, 0);
  });

  test('KONTROL: budama sonrası gönderim aynı sonucu verir (son hal gider)', () async {
    await aliHazirla();
    final ali = await a.cariId('Ali');
    await a.sut.gunlukKaydet(cariId: ali, tarih: gun, sabah: 10, aksam: 0);
    await a.sut.gunlukKaydet(cariId: ali, tarih: gun, sabah: 10, aksam: 20);
    await SenkCekirdek(a.db).budama();
    await esitle(a, b);
    expect([(await b.sutSatiri('Ali', gun))!['sabah'], (await b.sutSatiri('Ali', gun))!['aksam']], [10.0, 20.0]);
  });
}
