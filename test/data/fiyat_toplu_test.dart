import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/data/repositories/fiyat_repository.dart';

import '../helpers/test_db.dart';

/// getAyFiyatlariHepsi tek sorguya indirildi; sonuç eski cari-başına
/// yöntemle (getirTekil ?? oncekiAydanDevral) BİREBİR aynı olmalı.
void main() {
  late Database db;
  setUp(() async => db = await testVeritabaniAc());
  tearDown(() => db.close());

  test('tek sorgu = eski yöntem: kendi ay, devralma, hiç fiyat yok', () async {
    final a = await cariEkle(db, ad: 'A');
    final b = await cariEkle(db, ad: 'B');
    final c = await cariEkle(db, ad: 'C');
    final d = await cariEkle(db, ad: 'D');
    await fiyatTanimla(db, a, '2026-11', sut: 20, sutYemi: 12); // kendi ayı
    await fiyatTanimla(db, a, '2026-09', sut: 15);
    await fiyatTanimla(db, b, '2026-08', sut: 16, besiYemi: 9); // devralır
    await fiyatTanimla(db, b, '2026-10', sut: 17); //               en yenisi bu
    await fiyatTanimla(db, c, '2026-12', sut: 99); //              yalnız GELECEK ay → yok sayılır
    final repo = CariFiyatRepository(db);

    final yeni = await repo.getAyFiyatlariHepsi([a, b, c, d], '2026-11');
    for (final id in [a, b, c, d]) {
      final eski = await repo.getirTekil(id, '2026-11') ?? await repo.oncekiAydanDevral(id, '2026-11');
      expect(yeni[id]!.toMap(), eski.toMap(), reason: 'cari $id');
    }
    expect(yeni[a]!.id, isNotNull, reason: 'kendi ayı: kayıt id\x27si korunur');
    expect((yeni[b]!.sutFiyat, yeni[b]!.ay, yeni[b]!.id), (17, '2026-11', null));
    expect(yeni[c]!.sutFiyat, 0);
    expect(yeni[d]!.sutFiyat, 0);
  });
}
