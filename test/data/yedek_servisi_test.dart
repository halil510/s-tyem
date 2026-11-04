import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/data/yedek/yedek_servisi.dart';

import '../helpers/test_db.dart';

/// Gerçekçi bir işletme verisi: 2 cari, süt, yem, fiyat, ödeme, tahsilat.
Future<void> ornekVeriYukle(Database db) async {
  final ali = await cariEkle(db, ad: 'Ali');
  final veli = await cariEkle(db, ad: 'Veli');
  await fiyatTanimla(db, ali, '2026-05', sut: 18.5, sutYemi: 12);
  await fiyatTanimla(db, veli, '2026-05', sut: 19);
  await db.insert('sutler', {'cari_id': ali, 'tarih': '2026-05-01', 'sabah': 20, 'aksam': 18, 'toplam': 38});
  await db.insert('sutler', {'cari_id': veli, 'tarih': '2026-05-01', 'sabah': 30, 'aksam': 0, 'toplam': 30});
  await db.insert('yemler', {'cari_id': ali, 'tarih': '2026-05-02', 'sut_yemi': 50, 'toplam': 50});
  await db.insert('cari_odemeler', {
    'cari_id': ali, 'tarih': '2026-05-15', 'islem_turu': 'odeme',
    'miktar': 1, 'birim_fiyat': 100, 'toplam_tutar': 100,
  });
  await db.insert('cari_odemeler', {
    'cari_id': veli, 'tarih': '2026-05-16', 'islem_turu': 'tahsilat',
    'miktar': 1, 'birim_fiyat': 40, 'toplam_tutar': 40,
  });
}

Future<Map<String, int>> sayilar(Database db) async => {
      for (final t in YedekServisi.tablolar)
        t: Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $t'))!,
    };

void main() {
  late Database db;

  setUp(() async {
    db = await testVeritabaniAc();
    await ornekVeriYukle(db);
  });

  test('yedek TÜM iş tablolarını içerir (ödeme ve fiyatlar dahil)', () async {
    final yedek = await YedekServisi.disaAktar(db);
    expect(yedek['meta']['format_version'], YedekServisi.formatSurumu);
    expect(yedek['cari_odemeler'], hasLength(2));
    expect(yedek['cari_fiyatlar'], hasLength(2));
    expect(YedekServisi.tamYedekMi(yedek), isTrue);
  });

  test('başka bir cihaza tamamen aktarım verileri birebir taşır', () async {
    final json = await YedekServisi.disaAktarJson(db);
    final hedef = await testVeritabaniAc();
    await cariEkle(hedef, ad: 'Hedefte eski cari');

    final ozet = await YedekServisi.iceAktar(hedef, YedekServisi.coz(json), tamamenDegistir: true);

    expect(await sayilar(hedef), await sayilar(db));
    expect(ozet.toplam, 9);
    final cariler = await hedef.query('cariler', orderBy: 'id');
    expect(cariler.map((c) => c['ad']), ['Ali', 'Veli']);
  });

  test('REGRESYON: geri yükleme carinin ödeme/tahsilat kayıtlarını SİLMEZ', () async {
    // Eski kod `INSERT OR REPLACE` kullanıyordu; REPLACE + ON DELETE
    // CASCADE, aynı id'li cariyi yeniden yazarken ödemelerini siliyordu.
    final eskiBicimYedek = {
      'meta': {'app': 'sut_yem', 'version': '1.0'},
      'cariler': await db.query('cariler'),
      'sutler': await db.query('sutler'),
      'yemler': await db.query('yemler'),
    };
    final once = await sayilar(db);

    await YedekServisi.iceAktar(db, YedekServisi.coz(jsonEncode(eskiBicimYedek)));

    expect(await sayilar(db), once);
  });

  test('eski biçimli yedekle "tamamen değiştir" reddedilir, veri korunur', () async {
    final eski = {
      'meta': {'app': 'sut_yem'},
      'cariler': <Object>[],
      'sutler': <Object>[],
      'yemler': <Object>[],
    };
    final once = await sayilar(db);
    await expectLater(
      YedekServisi.iceAktar(db, eski, tamamenDegistir: true),
      throwsA(isA<YedekHatasi>()),
    );
    expect(await sayilar(db), once);
  });

  test('bozuk bir kayıt varsa HİÇBİR değişiklik yazılmaz (ya hep ya hiç)', () async {
    final yedek = await YedekServisi.disaAktar(db);
    final hedef = await testVeritabaniAc();
    final hedefCari = await cariEkle(hedef, ad: 'Korunmalı');
    await hedef.insert('sutler', {'cari_id': hedefCari, 'tarih': '2026-01-01', 'sabah': 9, 'toplam': 9});

    // Var olmayan bir cariye bağlı süt kaydı ekle.
    yedek['sutler'] = [...(yedek['sutler'] as List), {'cari_id': 777, 'tarih': '2026-05-03', 'sabah': 1, 'toplam': 1}];

    await expectLater(
      YedekServisi.iceAktar(hedef, yedek, tamamenDegistir: true),
      throwsA(isA<YedekHatasi>()),
    );
    expect((await hedef.query('cariler')).single['ad'], 'Korunmalı');
    expect(await hedef.query('sutler'), hasLength(1));
  });

  test('birleştirme: aynı gün süt kaydı mükerrer oluşturmaz, günceller', () async {
    final ali = (await db.query('cariler', where: "ad = 'Ali'")).single['id'];
    final yedek = {
      'meta': {'app': 'sut_yem'},
      'cariler': await db.query('cariler'),
      'sutler': [
        // Farklı id, aynı cari + gün → mevcut kaydı güncellemeli.
        {'id': 5000, 'cari_id': ali, 'tarih': '2026-05-01T07:00:00', 'sabah': 22, 'aksam': 18, 'toplam': 40},
      ],
    };
    await YedekServisi.iceAktar(db, yedek);
    final aliSutleri = await db.query('sutler', where: 'cari_id = ?', whereArgs: [ali]);
    expect(aliSutleri, hasLength(1));
    expect(aliSutleri.single['toplam'], 40);
    expect(aliSutleri.single['tarih'], '2026-05-01');
  });

  test('bilinmeyen sütunlar (farklı uygulama sürümü) yok sayılır', () async {
    final yedek = await YedekServisi.disaAktar(db);
    yedek['cariler'] = [
      for (final c in (yedek['cariler'] as List).cast<Map<String, Object?>>())
        {...c, 'gelecek_surum_alani': 'x'},
    ];
    final hedef = await testVeritabaniAc();
    await YedekServisi.iceAktar(hedef, yedek, tamamenDegistir: true);
    expect(await hedef.query('cariler'), hasLength(2));
  });

  group('coz', () {
    test('geçersiz JSON ve yabancı dosyalar anlaşılır hata verir', () {
      expect(() => YedekServisi.coz('{bozuk'), throwsA(isA<YedekHatasi>()));
      expect(() => YedekServisi.coz('[1,2,3]'), throwsA(isA<YedekHatasi>()));
      expect(() => YedekServisi.coz('{"meta":{}}'), throwsA(isA<YedekHatasi>()));
      expect(() => YedekServisi.coz('{"meta":{},"cariler":[],"sutler":"x"}'), throwsA(isA<YedekHatasi>()));
    });
  });
}
