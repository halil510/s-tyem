import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/features/dashboard/providers/dashboard_providers.dart';
import 'package:sutyem_pro/features/donem/donem_servisi.dart';
import 'package:sutyem_pro/models/cari_model.dart';
import 'package:sutyem_pro/models/sut_model.dart';
import 'package:sutyem_pro/utils/tarih_format.dart';

import '../helpers/test_db.dart';

/// Özet (ana sayfa) verileri.
void main() {
  setUpAll(initializeTurkishLocale);

  final f = DateFormat('yyyy-MM-dd');
  final bugun = DateTime.now();
  String gun(int geri) => f.format(DateTime(bugun.year, bugun.month, bugun.day - geri));

  group('gelmeyenUreticiler', () {
    Cari c(int id, String ad) => Cari(id: id, ad: ad, soyad: 'X');
    Sut s(int cari, String tarih, {double sabah = 10, double aksam = 0}) =>
        Sut(cariId: cari, tarih: tarih, sabah: sabah, aksam: aksam);

    test('düzenli getirip bugün kaydı olmayanlar, ada göre sıralı', () {
      final sonuc = gelmeyenUreticiler(
        aktifCariler: [c(1, 'Zeki'), c(2, 'Ali'), c(3, 'Can'), c(4, 'Ece'), c(5, 'Naz')],
        sonSutler: [
          s(1, gun(1)), // dün geldi, bugün yok → gelmeyen
          s(2, gun(3)), s(2, gun(0)), // bugün geldi
          s(3, gun(13)), // 13 gün önce → hâlâ düzenli
          s(4, gun(15)), // 15 gün önce → düzenli sayılmaz
          s(5, gun(2)), s(5, gun(0), sabah: 0, aksam: 0), // bugün 0 kg satırı → gelmedi sayılır
        ],
        bugun: bugun,
      );
      expect(sonuc.map((x) => x.ad), ['Can', 'Naz', 'Zeki']);
    });

    test('yalnız akşam getiren de "geldi" sayılır', () {
      final sonuc = gelmeyenUreticiler(
        aktifCariler: [c(1, 'Ali')],
        sonSutler: [s(1, gun(1)), s(1, gun(0), sabah: 0, aksam: 12)],
        bugun: bugun,
      );
      expect(sonuc, isEmpty);
    });
  });

  group('dashboardDataProvider', () {
    late Database db;
    late ProviderContainer container;
    late int ali, veli, can;

    setUp(() async {
      db = await testVeritabaniAc();
      container = testContainer(db);
      ali = await cariEkle(db, ad: 'Ali');
      veli = await cariEkle(db, ad: 'Veli');
      can = await cariEkle(db, ad: 'Can');
      Future<void> sut(int cari, String tarih, double sabah, double aksam) => db.insert('sutler',
          {'cari_id': cari, 'tarih': tarih, 'sabah': sabah, 'aksam': aksam, 'toplam': sabah + aksam});
      await sut(ali, gun(0), 20, 18);
      await sut(veli, gun(0), 15, 0);
      await sut(ali, gun(1), 30, 0);
      await sut(can, gun(1), 12, 0); // dün geldi, bugün yok
      await db.insert('yemler', {'cari_id': ali, 'tarih': gun(0), 'b_baslangic': 5, 'b_buyutme': 3, 'toplam': 8});
    });

    tearDown(() => container.dispose());

    test('bugün sabah/akşam, dün, gelen sayısı, gelmeyenler', () async {
      final d = await container.read(dashboardDataProvider.future);
      expect(d.bugunSabah, 35);
      expect(d.bugunAksam, 18);
      expect(d.bugunToplamSut, 53);
      expect(d.dunToplamSut, 42);
      expect(d.bugunGelenSayisi, 2);
      expect(d.gelmeyenler.map((c) => c.id), [can]);
    });

    test('buzağı yemleri "Besi" değil kendi diliminde', () async {
      final d = await container.read(dashboardDataProvider.future);
      final dilim = {for (final y in d.yemDagilimi) y.tur: y.miktar};
      expect(dilim['Buzağı'], 8);
      expect(dilim.containsKey('Besi'), isFalse);
    });

    test('geçen ay kapatılmadıysa hatırlatır, kapatılınca hatırlatma kalkar', () async {
      final gecenAy = DateTime(bugun.year, bugun.month - 1);
      final ay = DateFormat('yyyy-MM').format(gecenAy);
      await fiyatTanimla(db, ali, ay, sut: 20);
      await db.insert('sutler', {'cari_id': ali, 'tarih': '$ay-10', 'sabah': 5, 'toplam': 5});

      expect((await container.read(dashboardDataProvider.future)).kapanmamisGecenAy, ay);

      await DonemServisi(db).kapat(ay);
      container.invalidate(dashboardDataProvider);
      expect((await container.read(dashboardDataProvider.future)).kapanmamisGecenAy, isNull);
    });
  });
}
