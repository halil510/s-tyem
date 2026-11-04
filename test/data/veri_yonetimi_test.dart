import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/data/repositories/donem_kilidi.dart';
import 'package:sutyem_pro/data/repositories/fiyat_repository.dart';
import 'package:sutyem_pro/data/repositories/sut_repository.dart';
import 'package:sutyem_pro/data/repositories/veri_yonetimi_repository.dart';
import 'package:sutyem_pro/data/yedek/yedek_servisi.dart';
import 'package:sutyem_pro/features/donem/donem_servisi.dart';
import 'package:sutyem_pro/models/cari_fiyat_model.dart';

import '../helpers/test_db.dart';

/// A6: repository'ye taşınan toplu işlemler ve tarih indeksleri.
void main() {
  late Database db;
  late int ali, veli;

  setUp(() async {
    db = await testVeritabaniAc();
    ali = await cariEkle(db, ad: 'Ali');
    veli = await cariEkle(db, ad: 'Veli');
  });
  tearDown(() => db.close());

  Future<void> sut(int cari, String tarih, double kg) =>
      db.insert('sutler', {'cari_id': cari, 'tarih': tarih, 'sabah': kg, 'toplam': kg});

  group('VeriYonetimiRepository', () {
    test('kayıt sayıları tek sorguda', () async {
      await sut(ali, '2026-11-01', 10);
      await sut(veli, '2026-11-01', 20);
      await db.insert('yemler', {'cari_id': ali, 'tarih': '2026-11-01', 'sut_yemi': 5, 'toplam': 5});
      final s = await VeriYonetimiRepository(db).kayitSayilari();
      expect((s.cari, s.sut, s.yem, s.odeme), (2, 2, 1, 0));
    });

    test('süt ve yem temizliği: carileri korur, denetime yazar', () async {
      await sut(ali, '2026-11-01', 10);
      await db.insert('yemler', {'cari_id': ali, 'tarih': '2026-11-01', 'sut_yemi': 5, 'toplam': 5});
      final r = await VeriYonetimiRepository(db).sutVeYemSil();
      expect((r.sut, r.yem), (1, 1));
      expect(await db.query('sutler'), isEmpty);
      expect(await db.query('cariler'), hasLength(2));
      final denetim = await db.query('islem_gecmisi', where: "islem = 'sil'");
      expect(denetim.single['onceki_deger'], contains('toplu_temizlik'));
    });

    test('kapalı dönem varsa temizlik HİÇBİR şeyi silmez', () async {
      await fiyatTanimla(db, ali, '2026-09', sut: 10);
      await sut(ali, '2026-09-10', 10);
      await sut(ali, '2026-11-01', 7);
      await DonemServisi(db).kapat('2026-09', simdi: DateTime(2026, 11, 4));
      await expectLater(VeriYonetimiRepository(db).sutVeYemSil(), throwsA(isA<DonemKapaliHatasi>()));
      expect(await db.query('sutler'), hasLength(2));
    });

    group('dbDosyasiniDogrula', () {
      late Directory klasor;
      setUp(() async => klasor = await Directory.systemTemp.createTemp('sutyem_dogrula_'));
      tearDown(() async {
        try {
          await klasor.delete(recursive: true);
        } catch (_) {}
      });

      test('uygulamanın sağlam veritabanı kabul edilir', () async {
        final yol = p.join(klasor.path, 'iyi.db');
        final d = await databaseFactoryFfi.openDatabase(yol);
        for (final t in ['cariler', 'sutler', 'yemler']) {
          await d.execute('CREATE TABLE $t (id INTEGER)');
        }
        await d.close();
        await VeriYonetimiRepository.dbDosyasiniDogrula(yol, factory: databaseFactoryFfi);
      });

      test('başka bir veritabanı ve bozuk dosya reddedilir', () async {
        final baska = p.join(klasor.path, 'baska.db');
        final d = await databaseFactoryFfi.openDatabase(baska);
        await d.execute('CREATE TABLE musteriler (id INTEGER)');
        await d.close();
        await expectLater(VeriYonetimiRepository.dbDosyasiniDogrula(baska, factory: databaseFactoryFfi),
            throwsA(isA<YedekHatasi>().having((e) => e.mesaj, 'mesaj', contains('eksik tablo'))));

        final cop = p.join(klasor.path, 'cop.db');
        await File(cop).writeAsBytes(List.generate(4096, (i) => i % 251));
        await expectLater(VeriYonetimiRepository.dbDosyasiniDogrula(cop, factory: databaseFactoryFfi),
            throwsA(isA<YedekHatasi>()));
      });
    });
  });

  group('CariFiyatRepository.topluKaydet', () {
    test('ekler ve günceller', () async {
      await fiyatTanimla(db, ali, '2026-11', sut: 15);
      await CariFiyatRepository(db).topluKaydet([
        CariFiyat(cariId: ali, ay: '2026-11', sutFiyat: 18),
        CariFiyat(cariId: veli, ay: '2026-11', sutFiyat: 19),
      ]);
      final r = await db.query('cari_fiyatlar', orderBy: 'cari_id');
      expect(r.map((x) => x['sut_fiyat']), [18, 19]);
    });

    test('biri kapalı aya düşerse HİÇBİRİ yazılmaz', () async {
      await fiyatTanimla(db, ali, '2026-09', sut: 10);
      await sut(ali, '2026-09-10', 10);
      await DonemServisi(db).kapat('2026-09', simdi: DateTime(2026, 11, 4));
      final once = await db.query('cari_fiyatlar');
      await expectLater(
        CariFiyatRepository(db).topluKaydet([
          CariFiyat(cariId: veli, ay: '2026-11', sutFiyat: 19), // açık ay
          CariFiyat(cariId: ali, ay: '2026-09', sutFiyat: 99), // kapalı ay
        ]),
        throwsA(isA<DonemKapaliHatasi>()),
      );
      expect(await db.query('cari_fiyatlar'), once);
    });
  });

  test('SutRepository: cari aralık toplamı ve kayıt var mı', () async {
    await sut(ali, '2026-10-31', 99);
    await sut(ali, '2026-11-01', 10);
    await sut(ali, '2026-11-03', 5.5);
    await sut(veli, '2026-11-02', 7);
    final repo = SutRepository(db);
    expect(await repo.toplamCari(ali, '2026-11-01', '2026-11-30'), 15.5);
    expect(await repo.toplamCari(veli, '2026-12-01', '2026-12-31'), 0);
    expect(await repo.kayitVarMi('2026-11-01', '2026-11-30'), isTrue);
    expect(await repo.kayitVarMi('2026-12-01', '2026-12-31'), isFalse);
  });

  group('v10 tarih indeksleri', () {
    Future<String> plan(String sql, List<Object?> args) async =>
        (await db.rawQuery('EXPLAIN QUERY PLAN $sql', args)).map((r) => r['detail']).join(' | ');

    test('tarihe göre sorgular tabloyu taramaz, indeks kullanır', () async {
      expect(await plan('SELECT * FROM sutler WHERE tarih = ?', ['2026-11-01']),
          contains('idx_sutler_tarih'));
      expect(await plan('SELECT * FROM sutler WHERE tarih BETWEEN ? AND ?', ['2026-11-01', '2026-11-30']),
          contains('idx_sutler_tarih'));
      expect(await plan('SELECT * FROM yemler WHERE tarih BETWEEN ? AND ?', ['2026-11-01', '2026-11-30']),
          contains('idx_yemler_tarih'));
      expect(await plan('SELECT * FROM cari_odemeler WHERE tarih BETWEEN ? AND ?', ['2026-11-01', '2026-11-30']),
          contains('idx_odemeler_tarih'));
    });

    test('cariye göre sorgu hâlâ cari indeksini kullanır', () async {
      final p = await plan('SELECT * FROM sutler WHERE cari_id = ? AND tarih BETWEEN ? AND ?',
          [1, '2026-11-01', '2026-11-30']);
      expect(p, isNot(contains('SCAN sutler')));
    });
  });
}
