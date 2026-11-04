import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/data/repositories/cari_odeme_repository.dart';
import 'package:sutyem_pro/data/repositories/cari_repository.dart';
import 'package:sutyem_pro/data/repositories/sut_repository.dart';
import 'package:sutyem_pro/models/cari_model.dart';
import 'package:sutyem_pro/models/cari_odeme_model.dart';

import '../helpers/test_db.dart';

void main() {
  late Database db;
  late CariRepository repo;
  late int ali;

  setUp(() async {
    db = await testVeritabaniAc();
    repo = CariRepository(db);
    ali = await repo.insert(Cari(ad: 'Ali', soyad: 'Kaya', notMetni: 'Pazartesi öder'));
    await SutRepository(db).gunlukKaydet(cariId: ali, tarih: '2026-05-01', sabah: 10, aksam: 0);
    await SutRepository(db).gunlukKaydet(cariId: ali, tarih: '2026-05-02', sabah: 11, aksam: 0);
    await CariOdemeRepository(db).insert(CariOdeme(
      cariId: ali, tarih: '2026-05-03', islemTuru: 'odeme', miktar: 1, birimFiyat: 50, toplamTutar: 50,
    ));
  });

  test('hareket sayıları silme uyarısı için doğru sayılır', () async {
    final s = await repo.hareketSayilari(ali);
    expect((s.sut, s.yem, s.odeme), (2, 0, 1));
  });

  test('pasife alınan cari listeden kalkar ama TÜM kayıtları korunur', () async {
    await repo.pasifeAl(ali);
    expect(await repo.getAll(sadeceAktif: true), isEmpty);
    expect(await db.query('sutler'), hasLength(2));
    expect(await db.query('cari_odemeler'), hasLength(1));

    await repo.aktifYap(ali);
    expect((await repo.getAll(sadeceAktif: true)).single.tamAd, 'Ali Kaya');
  });

  test('kalıcı silme hareketleri de siler (bu yüzden ekran önce uyarır)', () async {
    await repo.delete(ali);
    expect(await db.query('sutler'), isEmpty);
    expect(await db.query('cari_odemeler'), isEmpty);
  });

  test('güncelleme not ve durum alanlarını korur', () async {
    final cari = (await repo.getById(ali))!;
    await repo.update(Cari(
      id: ali, ad: 'Ali', soyad: 'Kaya', telefon: '05551112233',
      aktif: cari.aktif, notMetni: cari.notMetni,
    ));
    final guncel = (await repo.getById(ali))!;
    expect(guncel.telefon, '05551112233');
    expect(guncel.notMetni, 'Pazartesi öder');
  });
}
