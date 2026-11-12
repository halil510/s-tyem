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

/// Supabase'deki sutyem_* fonksiyonlarının davranışını taklit eden sahte bulut
/// (supabase/sutyem_bulut_sema.sql ile aynı kurallar: şifre, son yazan kazanır, sıra ile çekme).
class SahteBulut {
  final kayitlar = <String, Map<String, Object?>>{}; // tablo|anahtar → satır
  var sira = 0;
  String? sifre;

  /// Sunucu saati cihazdan bu kadar farklı (saat farkı uyarısı testi).
  Duration saatKaymasi = Duration.zero;

  http.Client istemci() => MockClient((rq) async {
        final h = {'date': HttpDate.format(DateTime.now().add(saatKaymasi)), 'content-type': 'application/json'};
        final fn = rq.url.pathSegments.last;
        final g = jsonDecode(utf8.decode(rq.bodyBytes)) as Map<String, dynamic>;
        if (fn == 'sutyem_baglan') sifre ??= g['p_sifre'] as String;
        if (g['p_sifre'] != sifre) return http.Response(jsonEncode({'message': 'SUTYEM_YETKISIZ'}), 400, headers: h);
        switch (fn) {
          case 'sutyem_baglan':
            return http.Response(jsonEncode({'yeni': kayitlar.isEmpty, 'kayit_sayisi': kayitlar.length, 'son_sira': sira}), 200, headers: h);
          case 'sutyem_gonder':
            var n = 0;
            for (final k in (g['p_kayitlar'] as List).cast<Map>()) {
              final a = '${k['t']}|${k['k']}';
              final o = kayitlar[a];
              final yeni = o == null ||
                  (k['z'] as String).compareTo(o['z'] as String) > 0 ||
                  (k['z'] == o['z'] && (k['c'] as String).compareTo(o['c'] as String) > 0);
              if (!yeni) continue;
              kayitlar[a] = {'t': k['t'], 'k': k['k'], 'z': k['z'], 'c': k['c'], 's': k['s'] == true, 'v': k['s'] == true ? null : k['v'], 'sira': ++sira};
              n++;
            }
            return http.Response(jsonEncode({'yazilan': n, 'son_sira': sira}), 200, headers: h);
          case 'sutyem_cek':
            final l = kayitlar.values.where((r) => (r['sira'] as int) > (g['p_sira'] as int)).toList()
              ..sort((a, b) => (a['sira'] as int).compareTo(b['sira'] as int));
            return http.Response.bytes(utf8.encode(jsonEncode(l.take(g['p_limit'] as int).toList())), 200, headers: h);
          case 'sutyem_cihaz_listesi':
            return http.Response('[]', 200, headers: h);
        }
        return http.Response('{}', 404, headers: h);
      });
}

Future<Database> cihazDb(String ad) async {
  final db = await testVeritabaniAc();
  await SenkCekirdek.cihazAyarla(db, 'cihaz-$ad');
  return db;
}

Future<Map<String, Object?>?> sut(Database db, String tarih) async {
  final r = await db.query('sutler', where: 'tarih = ?', whereArgs: [tarih]);
  return r.isEmpty ? null : r.single;
}

void main() {
  tearDown(() async {
    BulutKanali.testIstemci = null;
    SenkronYoneticisi.testCihaz = null;
    await SenkronYoneticisi().testSifirla();
  });

  const ayar = BulutAyari(url: 'https://deneme.supabase.co', anahtar: 'sb_publishable_test', isletme: 'kabatli-sut', sifre: 'gizli123');

  Future<SenkronYoneticisi> yonetici(String ad, Database db) async {
    await SenkronYoneticisi().testSifirla();
    SenkronYoneticisi.testCihaz = 'cihaz-$ad';
    final y = SenkronYoneticisi();
    await y.baslat(db);
    return y;
  }

  test('BULUT (sahte Supabase): A kurar ve gönderir; B bağlanır, alır; öğünler bulut üzerinden birleşir; yanlış şifre reddedilir', () async {
    final bulut = SahteBulut();
    BulutKanali.testIstemci = bulut.istemci;

    final a = await cihazDb('A');
    final ali = await cariEkle(a, ad: 'Ali', soyad: 'Kaya');
    await fiyatTanimla(a, ali, '2026-11', sut: 20);
    var y = await yonetici('A', a);
    expect((await y.bulutBaglan(ayar))['yeni'], isTrue);
    expect(await y.buluttaEsitle(), contains('gönderildi'));
    expect(bulut.kayitlar.keys.where((k) => k.startsWith('cariler|')).length, 1);

    final b = await cihazDb('B');
    y = await yonetici('B', b);
    await expectLater(
        y.bulutBaglan(const BulutAyari(url: 'https://deneme.supabase.co', anahtar: 'sb_publishable_test', isletme: 'kabatli-sut', sifre: 'yanlis1')),
        throwsA(isA<BulutHatasi>()));
    await y.bulutBaglan(ayar);
    await y.buluttaEsitle();
    final bAli = (await b.query('cariler')).single['id'] as int;
    // B internetsiz: akşamı girer. A: sabahı girer.
    await SutRepository(b).gunlukKaydet(cariId: bAli, tarih: gun, sabah: 0, aksam: 35);
    await SutRepository(a).gunlukKaydet(cariId: ali, tarih: gun, sabah: 40, aksam: 0);
    await y.buluttaEsitle(); // B gönderir
    y = await yonetici('A', a);
    await y.buluttaEsitle(); // A alır, birleştirir, geri gönderir
    y = await yonetici('B', b);
    await y.buluttaEsitle(); // B birleşik halini alır
    for (final db in [a, b]) {
      final s = (await sut(db, gun))!;
      expect([s['sabah'], s['aksam'], s['toplam']], [40.0, 35.0, 75.0]);
    }
  });

  test('Saat farkı: sunucu saati 10 dk farklıysa uyarı verilir; 1 dk ise verilmez', () async {
    final bulut = SahteBulut()..saatKaymasi = const Duration(minutes: 10);
    BulutKanali.testIstemci = bulut.istemci;
    final a = await cihazDb('A');
    final y = await yonetici('A', a);
    await y.bulutBaglan(ayar);
    await y.buluttaEsitle();
    expect(SaatFarki.sapmaVar(y.saatFarki.value), isTrue);
    expect(SaatFarki.metin(y.saatFarki.value!), contains('geride'));
    bulut.saatKaymasi = const Duration(minutes: 1);
    await y.buluttaEsitle();
    expect(SaatFarki.sapmaVar(y.saatFarki.value), isFalse);
  });

  test('Gizli (secret / service_role) anahtar kabul edilmez', () {
    expect(BulutAyari.anahtarSorunu('sb_secret_abc'), isNotNull);
    expect(BulutAyari.anahtarSorunu('sb_publishable_abc'), isNull);
  });

  test('Senkron ayarları cihazda; yedeğe girmez', () async {
    final a = await cihazDb('A');
    final y = await yonetici('A', a);
    await y.ayarYaz(SenkAyar.isletmeSifre, 'gizli123');
    expect(await y.ayar(SenkAyar.isletmeSifre), 'gizli123');
    final yedek = await a.query('senk_ayarlar');
    expect(yedek, isNotEmpty);
    // YedekServisi.tablolar senk_ayarlar içermez.
    expect((await File('lib/data/yedek/yedek_servisi.dart').readAsString()).contains("'senk_ayarlar'"), isFalse);
  });

  test('YEREL AĞ (gerçek HTTP): A ana cihaz, B bağlı; iki yönlü eşitleme; yanlış kod reddedilir', () async {
    final a = await cihazDb('A');
    final ali = await cariEkle(a, ad: 'Ali');
    await fiyatTanimla(a, ali, '2026-11', sut: 20);
    await SutRepository(a).gunlukKaydet(cariId: ali, tarih: gun, sabah: 40, aksam: 0);

    final sunucu = YerelAgSunucusu();
    await sunucu.baslat(db: a, cihaz: 'cihaz-A', cihazAd: 'Dükkan', kod: '123456');
    addTearDown(sunucu.durdur);

    await expectLater(
        YerelAgIstemcisi.tur(adres: '127.0.0.1', kod: '999999', cihaz: 'cihaz-B', sonCekilen: 0, giden: const []), throwsA(isA<YerelAgHatasi>()));

    final b = await cihazDb('B');
    final y = await yonetici('B', b);
    expect(await y.anaCihazaBaglan('127.0.0.1', '123456'), contains('alındı'));
    final bAli = (await b.query('cariler')).single['id'] as int;
    expect((await sut(b, gun))!['sabah'], 40.0);

    await SutRepository(b).gunlukKaydet(cariId: bAli, tarih: gun, sabah: 40, aksam: 33);
    await y.yerelAgdaEsitle();
    expect((await sut(a, gun))!['aksam'], 33.0);
    await y.yerelAgdaEsitle();
    expect((await a.query('sutler')).length, 1);
    expect((await a.query('cariler')).length, 1);
  });
}
