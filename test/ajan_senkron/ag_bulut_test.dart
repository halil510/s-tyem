// AJAN TESTİ — açı: BULUT KANALI + SUPABASE SQL + YEREL AĞ + YÖNETİCİ DURUM MAKİNESİ.
// "BUG:" testleri DOĞRU davranışı bekler (hata varken başarısız olur).
// "KONTROL:" testleri doğru çalıştığı doğrulanan durumlardır (geçmeli).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/data/repositories/sut_repository.dart';
import 'package:sutyem_pro/senkron/bulut_kanali.dart';
import 'package:sutyem_pro/senkron/senk_cekirdek.dart';
import 'package:sutyem_pro/senkron/senkron_yoneticisi.dart';
import 'package:sutyem_pro/senkron/yerel_ag_kanali.dart';

import '../helpers/test_db.dart';

const gun = '2026-11-10';

/// supabase/sutyem_bulut_sema.sql'i daha SADIK taklit eden sahte bulut:
/// birden çok işletme, global sıra (sequence), şifre ≥ 6, 28000 → 403, veri=null (silinmişse),
/// c yoksa p_cihaz, limit 1..2000. Ayrıca gönderimi bekletme kapısı ve istek kaydı.
class GercekciBulut {
  final sifreler = <String, String>{}; // kod → şifre
  final kayitlar = <String, Map<String, Map<String, Object?>>>{}; // işletme → tablo|anahtar → satır
  var sira = 0;
  final istekler = <(String, Map<String, dynamic>)>[];

  /// Doluysa sutyem_gonder bu tamamlanana kadar bekler.
  Completer<void>? gonderKapisi;
  Completer<void>? gonderBasladi;

  /// >0 ise sıradaki N gönderim 500 hatası verir (yarıda kesilen eşitleme).
  var gonderHatasi = 0;
  var gonderSayisi = 0;

  http.Response _cevap(Object? govde, [int kod = 200]) =>
      http.Response.bytes(utf8.encode(jsonEncode(govde)), kod, headers: {'date': HttpDate.format(DateTime.now()), 'content-type': 'application/json'});

  http.Response? _dogrula(String isl, String? sifre) {
    if (sifreler[isl] == null || sifreler[isl] != sifre) {
      return _cevap({'code': '28000', 'message': 'SUTYEM_YETKISIZ: işletme kodu veya şifresi hatalı'}, 403);
    }
    return null;
  }

  Map<String, Map<String, Object?>> isletme(String kod) => kayitlar[kod] ??= {};

  http.Client istemci() => MockClient((rq) async {
        final fn = rq.url.pathSegments.last;
        final g = jsonDecode(utf8.decode(rq.bodyBytes)) as Map<String, dynamic>;
        istekler.add((fn, g));
        final isl = g['p_isletme'] as String;
        switch (fn) {
          case 'sutyem_baglan':
            final s = (g['p_sifre'] as String?) ?? '';
            if (s.length < 6) return _cevap({'code': 'P0001', 'message': 'SUTYEM_SIFRE_KISA: işletme şifresi en az 6 karakter olmalı'}, 400);
            var yeni = false;
            if (!sifreler.containsKey(isl)) {
              sifreler[isl] = s;
              yeni = true;
            }
            final h = _dogrula(isl, s);
            if (h != null) return h;
            final l = isletme(isl).values;
            return _cevap({
              'yeni': yeni,
              'kayit_sayisi': l.length,
              'son_sira': l.isEmpty ? 0 : l.map((r) => r['sira'] as int).reduce((a, b) => a > b ? a : b),
              'sunucu_zamani': DateTime.now().toUtc().toIso8601String(),
            });
          case 'sutyem_gonder':
            final h = _dogrula(isl, g['p_sifre'] as String?);
            if (h != null) return h;
            gonderSayisi++;
            if (gonderBasladi != null && !gonderBasladi!.isCompleted) gonderBasladi!.complete();
            if (gonderKapisi != null) await gonderKapisi!.future;
            if (gonderHatasi > 0) {
              gonderHatasi--;
              return _cevap({'message': 'canceling statement due to statement timeout'}, 500);
            }
            var n = 0;
            final t = isletme(isl);
            for (final k in (g['p_kayitlar'] as List).cast<Map>()) {
              final a = '${k['t']}|${k['k']}';
              final o = t[a];
              final s = k['s'] == true;
              final c = (k['c'] as String?) ?? g['p_cihaz'] as String;
              final yeni = o == null ||
                  (k['z'] as String).compareTo(o['z'] as String) > 0 ||
                  (k['z'] == o['z'] && c.compareTo(o['c'] as String) > 0);
              sira++; // nextval varsayılanı çakışmada da tüketilir (boşluk normal)
              if (!yeni) continue;
              t[a] = {'t': k['t'], 'k': k['k'], 'z': k['z'], 'c': c, 's': s, 'v': k['v'], 'sira': ++sira};
              n++;
            }
            return _cevap({'yazilan': n, 'son_sira': sira});
          case 'sutyem_cek':
            final h = _dogrula(isl, g['p_sifre'] as String?);
            if (h != null) return h;
            final lim = ((g['p_limit'] as int?) ?? 500).clamp(1, 2000);
            final l = isletme(isl).values.where((r) => (r['sira'] as int) > (g['p_sira'] as int)).toList()
              ..sort((a, b) => (a['sira'] as int).compareTo(b['sira'] as int));
            return _cevap(l.take(lim).toList());
          case 'sutyem_cihaz_listesi':
            final h = _dogrula(isl, g['p_sifre'] as String?);
            if (h != null) return h;
            return _cevap([
              {'cihaz': 'cihaz-A', 'ad': 'Telefon', 'son_gorulme': DateTime.now().toUtc().toIso8601String()}
            ]);
        }
        return _cevap({'code': 'PGRST202', 'message': 'Could not find the function public.$fn'}, 404);
      });

  /// "İşletmenin TÜM bulut verisini silmek" (SQL dosyasındaki yardımcı sorgu).
  void isletmeyiSil(String kod) {
    sifreler.remove(kod);
    kayitlar.remove(kod);
  }
}

Future<Database> cihazDb(String ad) async {
  final db = await testVeritabaniAc();
  await SenkCekirdek.cihazAyarla(db, 'cihaz-$ad');
  return db;
}

Future<SenkronYoneticisi> yonetici(String ad, Database db) async {
  await SenkronYoneticisi().testSifirla();
  SenkronYoneticisi.testCihaz = 'cihaz-$ad';
  final y = SenkronYoneticisi();
  await y.baslat(db);
  return y;
}

const ayar = BulutAyari(url: 'https://deneme.supabase.co', anahtar: 'sb_publishable_test', isletme: 'kabatli-sut', sifre: 'gizli123');
const ayarYeni = BulutAyari(url: 'https://deneme.supabase.co', anahtar: 'sb_publishable_test', isletme: 'yeni-isletme', sifre: 'gizli456');

Future<List<String>> cariAdlari(Database db) async => [for (final r in await db.query('cariler', orderBy: 'ad')) r['ad'] as String];

/// Bu testlerin kullandığı port; başka bir süreç tutuyorsa yerel ağ testleri atlanır.
Future<bool> portBos() async {
  try {
    final s = await ServerSocket.bind(InternetAddress.anyIPv4, yerelAgPortu);
    await s.close();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  late GercekciBulut bulut;
  setUp(() {
    bulut = GercekciBulut();
    BulutKanali.testIstemci = bulut.istemci;
  });
  tearDown(() async {
    BulutKanali.testIstemci = null;
    SenkronYoneticisi.testCihaz = null;
    await SenkronYoneticisi().testSifirla();
  });

  // ═══════════════════════════════ BULUT ═══════════════════════════════

  test('BUG: TEK telefon + bulut: süt kaydı eşitlenip SİLİNİNCE, sonraki eşitlemede bulutun yankısı onu geri diriltir', () async {
    final a = await cihazDb('A');
    final ali = await cariEkle(a, ad: 'Ali');
    await fiyatTanimla(a, ali, '2026-11', sut: 20);
    final y = await yonetici('A', a);
    await y.bulutBaglan(ayar);
    await SutRepository(a).gunlukKaydet(cariId: ali, tarih: gun, sabah: 40, aksam: 0);
    await y.buluttaEsitle(); // süt buluta gider (sira N); son_cekilen hâlâ 0
    final sutId = (await a.query('sutler')).single['id'] as int;
    await SutRepository(a).delete(sutId); // kullanıcı yanlış girilen sütü siler
    await y.buluttaEsitle(); // önce AL: kendi gönderdiği eski süt geri gelir
    expect(await a.query('sutler'), isEmpty, reason: 'silinen süt telefonda geri dirildi (bakiye 800 TL fazla)');
    final bulutSut = bulut.isletme('kabatli-sut').values.where((r) => r['t'] == 'sutler').single;
    expect(bulutSut['s'], isTrue, reason: 'silme buluta hiç gitmedi');
  });

  test('BUG: eşitleme sürerken işletme/bulut değiştirilirse eski eşitleme sayaçları yeni bulutun üstüne yazar → kayıtlar yeni buluta HİÇ gitmez', () async {
    final a = await cihazDb('A');
    await cariEkle(a, ad: 'Ali');
    await cariEkle(a, ad: 'Veli');
    final y = await yonetici('A', a);
    await y.bulutBaglan(ayar);
    bulut
      ..gonderKapisi = Completer()
      ..gonderBasladi = Completer();
    final suren = y.buluttaEsitle(sessiz: true); // otomatik eşitleme (dakikada bir) gibi
    await bulut.gonderBasladi!.future;
    await y.bulutBaglan(ayarYeni); // kullanıcı ekranda yeni işletmeye bağlanır → sayaçlar sıfırlanır
    bulut.gonderKapisi!.complete();
    await suren; // eski eşitleme bitince son_gonderilen'i ESKİ değerle yazar
    bulut.gonderKapisi = null;
    await y.buluttaEsitle();
    final yeniBulut = bulut.isletme('yeni-isletme').values.where((r) => r['t'] == 'cariler').length;
    expect(yeniBulut, 2, reason: 'yeni işletmenin bulutunda cari yok: bu telefonun kayıtları hiç gönderilmedi');
  });

  test('BUG: bulutta işletme silinip AYNI kodla yeniden kurulunca (bağlan → "yeni") telefon eski kayıtlarını yeniden göndermez', () async {
    final a = await cihazDb('A');
    await cariEkle(a, ad: 'Ali');
    final y = await yonetici('A', a);
    await y.bulutBaglan(ayar);
    await y.buluttaEsitle();
    expect(bulut.isletme('kabatli-sut').length, greaterThan(0));
    bulut.isletmeyiSil('kabatli-sut'); // SQL dosyasındaki "TÜM bulut verisini silmek" sorgusu
    final r = await y.bulutBaglan(ayar);
    expect(r['yeni'], isTrue);
    await y.buluttaEsitle();
    expect(bulut.isletme('kabatli-sut').values.where((r) => r['t'] == 'cariler').length, 1,
        reason: 'işletme sıfırdan kuruldu ama telefon verisini göndermedi; yeni katılan telefon boş kalır');
  });

  test('BUG: alınıp bekletilen/hatalı kayıt, o kanaldan YENİ veri gelmedikçe bir daha hiç denenmez (sorun giderilse bile)', () async {
    // Kaynak telefon: cari + süt.
    final kaynak = await cihazDb('K');
    final ali = await cariEkle(kaynak, ad: 'Ali');
    await SutRepository(kaynak).gunlukKaydet(cariId: ali, tarih: gun, sabah: 40, aksam: 0);
    final (paket, _) = await SenkCekirdek(kaynak).gonderilecekler(sonra: 0, haricKaynak: null);
    final cari = paket.where((k) => k.tablo == 'cariler').toList();
    final sut = paket.where((k) => k.tablo == 'sutler').toList();
    expect([cari.length, sut.length], [1, 1]);

    final b = await cihazDb('B');
    final y = await yonetici('B', b);
    await y.bulutBaglan(ayar);
    // Buluttan süt geldi ama carisi bu telefonda henüz yok → bekletildi.
    final s1 = await b.transaction((t) => SenkCekirdek(t).uygula(sut, kanal: 'bulut'));
    expect(s1.bekletilen, 1);
    // Cari başka yoldan (yerel ağ) geldi; sorun giderildi.
    await b.transaction((t) => SenkCekirdek(t).uygula(cari, kanal: 'lan'));
    // Kullanıcı "Bulutla eşitle"ye basar; bulutta yeni bir şey yok.
    await y.buluttaEsitle();
    expect((await b.query('sutler')).length, 1, reason: 'bekleyen süt kaydı yeniden denenmedi; ekranda "bekliyor" kalır');
  });

  test('BUG: bulut adresi 200 + HTML dönerse (otel/kafe WiFi giriş sayfası) BulutHatasi yerine ham FormatException fırlar', () async {
    final k = BulutKanali(ayar, istemci: MockClient((_) async => http.Response('<html>Giris yapin</html>', 200, headers: {'content-type': 'text/html'})));
    await expectLater(k.cek(cihaz: 'x', sira: 0), throwsA(isA<BulutHatasi>()));
  });

  test('KONTROL: Dart RPC gövdeleri SQL fonksiyon imzalarıyla birebir (p_ adları, varsayılansız parametreler) ve sutyem_cek dönüş kolonları t,k,z,c,s,v,sira', () async {
    final sql = await File('supabase/sutyem_bulut_sema.sql').readAsString();
    final imzalar = <String, (Set<String>, Set<String>)>{}; // fn → (tümü, zorunlu)
    for (final m in RegExp(r'create or replace function public\.(\w+)\(([^)]*)\)', caseSensitive: false).allMatches(sql)) {
      final tum = <String>{}, zorunlu = <String>{};
      for (final p in m.group(2)!.split(',')) {
        final ad = p.trim().split(RegExp(r'\s+')).first;
        tum.add(ad);
        if (!p.toLowerCase().contains('default')) zorunlu.add(ad);
      }
      imzalar[m.group(1)!] = (tum, zorunlu);
    }
    final donus = RegExp(r'sutyem_cek\([^)]*\)\s*returns table \(([^)]*)\)', caseSensitive: false).firstMatch(sql)!.group(1)!;
    expect(donus.split(',').map((e) => e.trim().split(' ').first).toList(), ['t', 'k', 'z', 'c', 's', 'v', 'sira']);

    final a = await cihazDb('A');
    await cariEkle(a, ad: 'Ali');
    final y = await yonetici('A', a);
    await y.bulutBaglan(ayar);
    await y.buluttaEsitle();
    await y.buluttaEsitle();
    expect((await y.bulutCihazlari()).single['cihaz'], 'cihaz-A');
    final cagrilan = {for (final (fn, _) in bulut.istekler) fn};
    expect(cagrilan, containsAll(['sutyem_baglan', 'sutyem_gonder', 'sutyem_cek', 'sutyem_cihaz_listesi']));
    for (final (fn, govde) in bulut.istekler) {
      final (tum, zorunlu) = imzalar[fn]!;
      expect(tum, containsAll(govde.keys), reason: '$fn: SQL\'de olmayan parametre');
      expect(govde.keys, containsAll(zorunlu), reason: '$fn: zorunlu parametre eksik');
    }
    // Gönderilen kayıt biçimi SQL'in okuduğu alanlarla aynı (t,k,z,c,s,v).
    final kayit = (bulut.istekler.firstWhere((e) => e.$1 == 'sutyem_gonder').$2['p_kayitlar'] as List).first as Map;
    expect(kayit.keys.toSet().difference({'t', 'k', 'z', 'c', 's', 'v'}), isEmpty);
    // Hata ayrıştırma: kısa şifre ve yanlış şifre anlaşılır mesaj verir.
    await expectLater(y.bulutBaglan(const BulutAyari(url: 'https://deneme.supabase.co', anahtar: 'k', isletme: 'abc', sifre: '123')),
        throwsA(predicate((e) => e is BulutHatasi && e.mesaj.contains('6 karakter'))));
    await expectLater(y.bulutBaglan(const BulutAyari(url: 'https://deneme.supabase.co', anahtar: 'k', isletme: 'kabatli-sut', sifre: 'yanlis99')),
        throwsA(predicate((e) => e is BulutHatasi && e.mesaj.contains('hatalı'))));
  });

  test('KONTROL: yarıda kesilen eşitleme (2. gönderim 500) kayıt kaybetmez; 520 cari 300\'lük gönderim + 500\'lük çekim sayfalarıyla eksiksiz geçer', () async {
    final a = await cihazDb('A');
    final batch = a.batch();
    for (var i = 0; i < 520; i++) {
      batch.insert('cariler', {'ad': 'C${i.toString().padLeft(3, '0')}', 'soyad': 'X'});
    }
    await batch.commit(noResult: true);
    var y = await yonetici('A', a);
    await y.bulutBaglan(ayar);
    bulut.gonderHatasi = 0;
    // İlk gönderim başarılı, ikincisi hata → sayaç yalnız ilk 300'e ilerlemeli.
    var ilk = true;
    final asil = bulut.istemci;
    BulutKanali.testIstemci = () => MockClient((rq) async {
          if (rq.url.pathSegments.last == 'sutyem_gonder') {
            if (!ilk) return http.Response(jsonEncode({'message': 'timeout'}), 500);
            ilk = false;
          }
          final c = asil();
          final r = await c.post(rq.url, headers: rq.headers, body: rq.bodyBytes);
          return r;
        });
    await expectLater(y.buluttaEsitle(), throwsA(isA<BulutHatasi>()));
    expect(bulut.isletme('kabatli-sut').length, 300);
    BulutKanali.testIstemci = bulut.istemci;
    await y.buluttaEsitle();
    expect(bulut.isletme('kabatli-sut').values.where((r) => r['t'] == 'cariler').length, 520);

    final b = await cihazDb('B');
    y = await yonetici('B', b);
    await y.bulutBaglan(ayar);
    await y.buluttaEsitle();
    expect((await b.query('cariler')).length, 520);
    expect(await y.buluttaEsitle(), isNot(contains('gönderildi')), reason: 'B aldıklarını geri göndermemeli (yankı yok)');
  });

  test('KONTROL: bulut eşitlemesi sürerken yerel ağ / ikinci bulut eşitlemesi beklemeden döner; bitince bayrak kalkar', () async {
    final a = await cihazDb('A');
    await cariEkle(a, ad: 'Ali');
    final y = await yonetici('A', a);
    await y.bulutBaglan(ayar);
    await y.ayarYaz(SenkAyar.lanAdres, '127.0.0.1');
    await y.ayarYaz(SenkAyar.lanIstemciKod, '123456');
    bulut
      ..gonderKapisi = Completer()
      ..gonderBasladi = Completer();
    final suren = y.buluttaEsitle();
    await bulut.gonderBasladi!.future;
    expect(await y.buluttaEsitle(), 'Eşitleme zaten sürüyor');
    expect(await y.yerelAgdaEsitle(), 'Eşitleme zaten sürüyor');
    bulut.gonderKapisi!.complete();
    expect(await suren, contains('gönderildi'));
    bulut.gonderKapisi = null;
    expect(await y.buluttaEsitle(), isNot(contains('zaten')));
  });

  test('KONTROL: SaatFarki — Date başlığı yoksa / bozuksa null; 10 dk ileri sunucu "geride" uyarısı', () {
    final t = DateTime.now();
    expect(SaatFarki.hesapla(null, t, t), isNull);
    expect(SaatFarki.hesapla('bozuk', t, t), isNull);
    final f = SaatFarki.hesapla(HttpDate.format(t.add(const Duration(minutes: 10))), t, t)!;
    expect(SaatFarki.sapmaVar(f), isTrue);
    expect(SaatFarki.metin(f), contains('geride'));
  });

  // ═══════════════════════════════ YEREL AĞ ═══════════════════════════════

  test('BUG: ana cihaz değişince (yeni telefon ana olur) bağlı cihazın daha önce ESKİ ana cihaza gönderdiği kayıtlar yeni ana cihaza hiç gitmez', () async {
    if (!await portBos()) {
      markTestSkipped('port $yerelAgPortu meşgul');
      return;
    }
    final b = await cihazDb('B');
    await cariEkle(b, ad: 'Bora');
    final eskiAna = await cihazDb('A');
    final s1 = YerelAgSunucusu();
    await s1.baslat(db: eskiAna, cihaz: 'cihaz-A', cihazAd: 'Eski', kod: '123456');
    final y = await yonetici('B', b);
    try {
      await y.anaCihazaBaglan('127.0.0.1', '123456');
    } finally {
      await s1.durdur();
    }
    expect(await cariAdlari(eskiAna), ['Bora']);

    final yeniAna = await cihazDb('C');
    await cariEkle(yeniAna, ad: 'Cem');
    final s2 = YerelAgSunucusu();
    await s2.baslat(db: yeniAna, cihaz: 'cihaz-C', cihazAd: 'Yeni', kod: '123456');
    try {
      await y.yerelAgdaEsitle();
      await y.yerelAgdaEsitle();
    } finally {
      await s2.durdur();
    }
    expect(await cariAdlari(b), ['Bora', 'Cem'], reason: 'B yeni ana cihazın verisini alır (son_cekilen sıfırlanıyor)');
    expect(await cariAdlari(yeniAna), ['Bora', 'Cem'], reason: 'B\'nin eski kaydı yeni ana cihaza gitmedi (son_gonderilen sıfırlanmıyor)');
  });

  test('KONTROL: ana cihaza aynı anda iki istemci; ikisi de verisini verir, yankı (kendi kaydı) geri gelmez, sunucuda çoğalma olmaz', () async {
    if (!await portBos()) {
      markTestSkipped('port $yerelAgPortu meşgul');
      return;
    }
    final ana = await cihazDb('A');
    final s = YerelAgSunucusu();
    await s.baslat(db: ana, cihaz: 'cihaz-A', cihazAd: 'Ana', kod: '123456');
    try {
      final b = await cihazDb('B'), c = await cihazDb('C');
      await cariEkle(b, ad: 'Bora');
      await cariEkle(c, ad: 'Can');
      final (gb, _) = await SenkCekirdek(b).gonderilecekler(sonra: 0, haricKaynak: 'lan');
      final (gc, _) = await SenkCekirdek(c).gonderilecekler(sonra: 0, haricKaynak: 'lan');
      final sonuc = await Future.wait([
        YerelAgIstemcisi.tur(adres: '127.0.0.1', kod: '123456', cihaz: 'cihaz-B', sonCekilen: 0, giden: gb),
        YerelAgIstemcisi.tur(adres: '127.0.0.1', kod: '123456', cihaz: 'cihaz-C', sonCekilen: 0, giden: gc),
      ]);
      expect(await cariAdlari(ana), ['Bora', 'Can']);
      // Her istemciye kendi kaydı geri gönderilmez.
      expect(sonuc[0].$1.where((k) => k.anahtar == gb.single.anahtar), isEmpty);
      expect(sonuc[1].$1.where((k) => k.anahtar == gc.single.anahtar), isEmpty);
      // Tekrar aynı gönderim çoğaltmaz.
      await YerelAgIstemcisi.tur(adres: '127.0.0.1', kod: '123456', cihaz: 'cihaz-B', sonCekilen: 0, giden: gb);
      expect((await ana.query('cariler')).length, 2);
      // sonCekilen sunucudakinden büyükse sunucu baştan verir (veritabanı yenilenmiş).
      final (gelen, sonId, sunucuSon, _) =
          await YerelAgIstemcisi.tur(adres: '127.0.0.1', kod: '123456', cihaz: 'cihaz-B', sonCekilen: 999999, giden: const []);
      expect(gelen.map((k) => k.anahtar), contains(gc.single.anahtar));
      expect(sonId, lessThanOrEqualTo(sunucuSon));
    } finally {
      await s.durdur();
    }
  });

  test('KONTROL: yanlış eşleşme kodu 5 kez → o adres 5 dk engellenir (doğru kod da reddedilir)', () async {
    if (!await portBos()) {
      markTestSkipped('port $yerelAgPortu meşgul');
      return;
    }
    final ana = await cihazDb('A');
    final s = YerelAgSunucusu();
    await s.baslat(db: ana, cihaz: 'cihaz-A', cihazAd: 'Ana', kod: '123456');
    try {
      for (var i = 0; i < 5; i++) {
        await expectLater(YerelAgIstemcisi.tur(adres: '127.0.0.1', kod: '00000$i', cihaz: 'x', sonCekilen: 0, giden: const []),
            throwsA(predicate((e) => e is YerelAgHatasi && e.mesaj.contains('kodu hatalı'))));
      }
      await expectLater(YerelAgIstemcisi.tur(adres: '127.0.0.1', kod: '123456', cihaz: 'x', sonCekilen: 0, giden: const []),
          throwsA(predicate((e) => e is YerelAgHatasi && e.mesaj.contains('5 dakika'))));
    } finally {
      await s.durdur();
    }
  });
}
