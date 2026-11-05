import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/core/providers/database_provider.dart';
import 'package:sutyem_pro/data/repositories/cari_repository.dart';
import 'package:sutyem_pro/features/cari/cari_excel_ekrani.dart';
import 'package:sutyem_pro/features/cari/cari_excel_ice_aktarma.dart';
import 'package:sutyem_pro/models/cari_model.dart';

import '../helpers/test_db.dart';

/// Verilen satırlardan bellekte .xlsx üretir (testte gerçek müşteri verisi yok).
List<int> excelYap(List<List<Object?>> satirlar, {String sayfa = 'Liste'}) {
  final x = Excel.createExcel();
  final s = x[sayfa];
  for (var r = 0; r < satirlar.length; r++) {
    for (var c = 0; c < satirlar[r].length; c++) {
      final v = satirlar[r][c];
      if (v == null) continue;
      s.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).value = switch (v) {
        int i => IntCellValue(i),
        double d => DoubleCellValue(d),
        _ => TextCellValue(v.toString()),
      };
    }
  }
  return x.encode()!;
}

void main() {
  group('CariExcelOkuyucu', () {
    test('uygulamanın Süt Raporu Excel\'i: başlık ve GENEL TOPLAM atlanır', () {
      final s = CariExcelOkuyucu.oku(excelYap([
        ['İsim Soyisim / Günler', '01 Kas S', '01 Kas A', 'TOPLAM'],
        ['AHMET YILMAZ', 0.0, 55.0, 55.0],
        ['ŞÜKRÜ ÇAĞLAR', 10.0, 0.0, 10.0],
        ['GENEL TOPLAM', 10.0, 55.0, 65.0],
      ], sayfa: 'Süt Raporu'));
      expect(s.adaylar.map((a) => (a.ad, a.soyad, a.satir)), [('AHMET', 'YILMAZ', 2), ('ŞÜKRÜ', 'ÇAĞLAR', 3)]);
      expect(s.atlananlar.single, contains('toplam'));
    });

    test('ayrı Ad / Soyad / Telefon / Adres sütunları; sayı olarak telefon', () {
      final s = CariExcelOkuyucu.oku(excelYap([
        ['Sıra', 'Adı', 'Soyadı', 'Cep Tel', 'Köy'],
        [1, 'Mehmet Ali', 'Kaya', 5551234567.0, 'Yeşilköy'],
        [2, 'Ayşe', 'Demir', null, null],
      ]));
      final a = s.adaylar.first;
      expect((a.ad, a.soyad, a.telefon, a.adres), ('Mehmet Ali', 'Kaya', '5551234567', 'Yeşilköy'));
      expect(s.adaylar[1].telefon, isNull);
    });

    test('"Cari Kodu" sütunu isim sanılmaz', () {
      final s = CariExcelOkuyucu.oku(excelYap([
        ['Cari Kodu', 'Cari Adı', 'Bakiye'],
        ['C001', 'Hasan Öz', 120.5],
      ]));
      expect(s.adaylar.single.tamAd, 'Hasan Öz');
    });

    test('başlıksız tek sütun; boşluklar, üç kelimeli isim, tek kelime, tekrar', () {
      final s = CariExcelOkuyucu.oku(excelYap([
        ['  Mehmet   Ali  Yılmaz '],
        ['Veli'],
        [null],
        ['mehmet ali YILMAZ'], // aynı kişi, farklı yazım
      ]));
      expect(s.adaylar.map((a) => (a.ad, a.soyad)), [('Mehmet Ali', 'Yılmaz'), ('Veli', '')]);
      expect(s.atlananlar.single, contains('tekrar'));
    });

    test('isim bulunamazsa ve bozuk dosyada anlaşılır hata', () {
      expect(() => CariExcelOkuyucu.oku(excelYap([[1, 2], [3, 4]])), throwsA(isA<CariExcelHatasi>()));
      expect(() => CariExcelOkuyucu.oku([1, 2, 3, 4]),
          throwsA(isA<CariExcelHatasi>().having((e) => e.mesaj, 'mesaj', contains('.xlsx'))));
    });
  });

  test('Türkçe büyük/küçük harf: İ/i, I/ı farkı kayıtlı cariyi kaçırmaz', () {
    expect(adAnahtari('İSMAİL  IŞIK'), adAnahtari('ismail ışık'));
    final plan = iceAktarmaPlani(
      const [
        CariAdayi(ad: 'İSMAİL', soyad: 'IŞIK', satir: 2),
        CariAdayi(ad: 'Yeni', soyad: 'Kişi', satir: 3),
      ],
      [Cari(id: 1, ad: 'İsmail', soyad: 'Işık', aktif: false)], // pasif de sayılır
    );
    expect(plan.kayitli.single.satir, 2);
    expect(plan.yeni.single.satir, 3);
  });

  test('topluEkle tek transaction', () async {
    final db = await testVeritabaniAc();
    addTearDown(db.close);
    final adet = await CariRepository(db).topluEkle([
      Cari(ad: 'A', soyad: 'B', hayvanTuru: 'Koyun'),
      Cari(ad: 'C', soyad: 'D', hayvanTuru: 'Koyun'),
    ]);
    expect(adet, 2);
    expect((await db.query('cariler')).map((r) => r['hayvan_turu']), ['Koyun', 'Koyun']);
  });

  testWidgets('ekran: önizleme gösterir, kayıtlıyı atlar, seçilenleri ekler', (tester) async {
    late Database db;
    await tester.runAsync(() async {
      db = await testVeritabaniAc();
      await cariEkle(db, ad: 'Ahmet', soyad: 'Yılmaz'); // zaten kayıtlı
    });
    final dosya = excelYap([
      ['Ad Soyad'],
      ['AHMET YILMAZ'],
      ['Ayşe Demir'],
      ['Can Uz'],
      ['TOPLAM'],
    ]);

    await tester.binding.setSurfaceSize(const Size(360, 1400)); // telefon genişliği
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWith((ref) => db)],
      child: MaterialApp(home: CariExcelIceAktarmaEkrani(hazirDosya: (ad: 'liste.xlsx', baytlar: dosya))),
    ));
    for (var i = 0; i < 100 && find.text('2 Cariyi İçeri Al').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(find.text('YENİ CARİLER (2)'), findsOneWidget);
    expect(find.textContaining('ZATEN KAYITLI'), findsOneWidget);

    // Can Uz'u çıkar, yalnız Ayşe eklensin.
    await tester.tap(find.text('Can Uz'));
    await tester.pump();
    await tester.tap(find.text('1 Cariyi İçeri Al'));
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      final n = await tester.runAsync(() => db.query('cariler'));
      if (n!.length == 2) break;
    }
    final adlar = (await tester.runAsync(() => db.query('cariler', orderBy: 'id')))!
        .map((r) => '${r['ad']} ${r['soyad']}');
    expect(adlar, ['Ahmet Yılmaz', 'Ayşe Demir']);
    await tester.runAsync(() => db.close());
  });
}
