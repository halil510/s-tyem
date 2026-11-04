import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/data/repositories/sut_repository.dart';

import '../helpers/test_db.dart';

void main() {
  late Database db;
  late SutRepository repo;
  late int cari;

  setUp(() async {
    db = await testVeritabaniAc();
    repo = SutRepository(db);
    cari = await cariEkle(db);
  });

  Future<List<Map<String, Object?>>> sutSatirlari() => db.query('sutler', orderBy: 'cari_id, tarih');

  group('gunlukKaydet', () {
    test('ilk kayıt eklenir', () async {
      final durum = await repo.gunlukKaydet(cariId: cari, tarih: '2026-05-01', sabah: 20, aksam: 0);
      expect(durum, SutKayitDurumu.eklendi);
      final s = (await sutSatirlari()).single;
      expect(s['sabah'], 20);
      expect(s['toplam'], 20);
    });

    test('aynı güne ikinci giriş YENİ SATIR AÇMAZ, mevcut kaydı günceller', () async {
      await repo.gunlukKaydet(cariId: cari, tarih: '2026-05-01', sabah: 20, aksam: 0);
      final durum = await repo.gunlukKaydet(cariId: cari, tarih: '2026-05-01', sabah: 20, aksam: 18.5);

      expect(durum, SutKayitDurumu.guncellendi);
      final satirlar = await sutSatirlari();
      expect(satirlar, hasLength(1));
      expect(satirlar.single['toplam'], 38.5);
    });

    test('aynı değerler tekrar kaydedilirse hiçbir şey değişmez', () async {
      await repo.gunlukKaydet(cariId: cari, tarih: '2026-05-01', sabah: 20, aksam: 18);
      final durum = await repo.gunlukKaydet(cariId: cari, tarih: '2026-05-01', sabah: 20, aksam: 18);
      expect(durum, SutKayitDurumu.degismedi);
    });

    test('iki alan da 0 ise mevcut kayıt silinir; kayıt yoksa bir şey olmaz', () async {
      expect(await repo.gunlukKaydet(cariId: cari, tarih: '2026-05-01', sabah: 0, aksam: 0),
          SutKayitDurumu.degismedi);
      await repo.gunlukKaydet(cariId: cari, tarih: '2026-05-01', sabah: 10, aksam: 0);
      expect(await repo.gunlukKaydet(cariId: cari, tarih: '2026-05-01', sabah: 0, aksam: 0),
          SutKayitDurumu.silindi);
      expect(await sutSatirlari(), isEmpty);
    });

    test('her değişiklik denetim günlüğüne yazılır', () async {
      await repo.gunlukKaydet(cariId: cari, tarih: '2026-05-01', sabah: 10, aksam: 0);
      await repo.gunlukKaydet(cariId: cari, tarih: '2026-05-01', sabah: 12, aksam: 0);
      await repo.gunlukKaydet(cariId: cari, tarih: '2026-05-01', sabah: 0, aksam: 0);
      final gunluk = await db.query('islem_gecmisi', where: "tablo_adi = 'sutler'", orderBy: 'id');
      expect(gunluk.map((g) => g['islem']), ['ekle', 'guncelle', 'sil']);
    });

    test('geçersiz değerler reddedilir ve hiçbir şey yazılmaz', () async {
      final hatalilar = <Future<SutKayitDurumu> Function()>[
        () => repo.gunlukKaydet(cariId: cari, tarih: '2026-05-01', sabah: -1, aksam: 0),
        () => repo.gunlukKaydet(cariId: cari, tarih: '2026-05-01', sabah: double.nan, aksam: 0),
        () => repo.gunlukKaydet(cariId: cari, tarih: '2026-05-01', sabah: double.infinity, aksam: 0),
        () => repo.gunlukKaydet(cariId: cari, tarih: '2026-05-01', sabah: 0, aksam: 25000),
        () => repo.gunlukKaydet(cariId: cari, tarih: '01.05.2026', sabah: 10, aksam: 0),
        () => repo.gunlukKaydet(cariId: cari, tarih: '2026-02-30', sabah: 10, aksam: 0),
        () => repo.gunlukKaydet(cariId: cari, tarih: '2026-05-01T10:00:00', sabah: 10, aksam: 0),
      ];
      for (final f in hatalilar) {
        await expectLater(f(), throwsA(isA<SutKayitHatasi>()));
      }
      expect(await sutSatirlari(), isEmpty);
    });

    test('olmayan bir cariye kayıt yapılamaz (yabancı anahtar)', () async {
      await expectLater(
        repo.gunlukKaydet(cariId: 9999, tarih: '2026-05-01', sabah: 10, aksam: 0),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('topluGunlukKaydet', () {
    test('ekler, günceller, siler ve sonucu doğru sayar', () async {
      final cari2 = await cariEkle(db, ad: 'Veli');
      final cari3 = await cariEkle(db, ad: 'Ayşe');
      await repo.gunlukKaydet(cariId: cari2, tarih: '2026-05-01', sabah: 5, aksam: 5);
      await repo.gunlukKaydet(cariId: cari3, tarih: '2026-05-01', sabah: 7, aksam: 0);

      final sonuc = await repo.topluGunlukKaydet('2026-05-01', [
        GunlukSutGirdisi(cariId: cari, sabah: 20, aksam: 18),
        GunlukSutGirdisi(cariId: cari2, sabah: 6, aksam: 5),
        GunlukSutGirdisi(cariId: cari3, sabah: 0, aksam: 0),
      ]);

      expect((sonuc.eklenen, sonuc.guncellenen, sonuc.silinen), (1, 1, 1));
      final gunluk = await repo.getGunlukHepsi('2026-05-01');
      expect(gunluk.keys, unorderedEquals([cari, cari2]));
      expect(gunluk[cari]!.toplam, 38);
      expect(gunluk[cari2]!.sabah, 6);
    });

    test('bir satır geçersizse HİÇBİR satır yazılmaz', () async {
      await expectLater(
        repo.topluGunlukKaydet('2026-05-01', [
          GunlukSutGirdisi(cariId: cari, sabah: 20, aksam: 18),
          const GunlukSutGirdisi(cariId: 1, sabah: -3, aksam: 0),
        ]),
        throwsA(isA<SutKayitHatasi>()),
      );
      expect(await sutSatirlari(), isEmpty);
    });

    test('ortada veritabanı hatası olursa önceki satırlar geri alınır (rollback)', () async {
      await expectLater(
        repo.topluGunlukKaydet('2026-05-01', [
          GunlukSutGirdisi(cariId: cari, sabah: 20, aksam: 18),
          const GunlukSutGirdisi(cariId: 9999, sabah: 10, aksam: 0), // cari yok
        ]),
        throwsA(isA<DatabaseException>()),
      );
      expect(await sutSatirlari(), isEmpty);
      expect(await db.query('islem_gecmisi', where: "tablo_adi = 'sutler'"), isEmpty);
    });
  });

  test('update: Detay ekranındaki düzenleme toplamı yeniden hesaplar', () async {
    await repo.gunlukKaydet(cariId: cari, tarih: '2026-05-01', sabah: 10, aksam: 10);
    final kayit = (await repo.getGunluk(cari, '2026-05-01'))!;
    kayit
      ..sabah = 12.5
      ..aksam = 11;
    await repo.update(kayit);
    expect((await repo.getGunluk(cari, '2026-05-01'))!.toplam, 23.5);
  });

  test('ay sonu (son gün) aralık sorgusuna dahildir', () async {
    await repo.gunlukKaydet(cariId: cari, tarih: '2026-05-31', sabah: 10, aksam: 0);
    expect(await repo.getByCari(cari, '2026-05-01', '2026-05-31'), hasLength(1));
  });
}
