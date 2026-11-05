import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/core/providers/database_provider.dart';
import 'package:sutyem_pro/ekranlar/sut_ekrani.dart';
import 'package:sutyem_pro/features/sut/sut_toplama_durumu.dart';
import 'package:sutyem_pro/models/sut_model.dart';

import '../helpers/test_db.dart';

/// Süt sekmesindeki yeşil "alındı" tiki: 12:00'den önce sabah, sonra akşam sütü
/// girilmiş cariye tik; ertesi gün boş başlar. Tik ayrıca saklanmaz.
void main() {
  group('öğün kuralı', () {
    test('12:00 öncesi sabah, 12:00 ve sonrası akşam', () {
      expect(toplamaOgunu(DateTime(2026, 11, 5, 5, 30)), ToplamaOgunu.sabah);
      expect(toplamaOgunu(DateTime(2026, 11, 5, 11, 59)), ToplamaOgunu.sabah);
      expect(toplamaOgunu(DateTime(2026, 11, 5, 12, 0)), ToplamaOgunu.aksam);
      expect(toplamaOgunu(DateTime(2026, 11, 5, 23, 59)), ToplamaOgunu.aksam);
    });

    test('alındı: yalnız o öğünün kg > 0 ise', () {
      final s = Sut(cariId: 1, tarih: '2026-11-05', sabah: 40, aksam: 0);
      expect(ogunAlindi(s, ToplamaOgunu.sabah), isTrue);
      expect(ogunAlindi(s, ToplamaOgunu.aksam), isFalse);
      expect(ogunAlindi(null, ToplamaOgunu.sabah), isFalse);
    });
  });

  group('Süt sekmesi', () {
    late Database db;
    late int ali;
    late int veli;

    Future<void> bekle(WidgetTester tester, bool Function() kosul, String aciklama) async {
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
        if (kosul()) return;
      }
      fail('Zaman aşımı: $aciklama');
    }

    Future<void> ac(WidgetTester tester, DateTime an) async {
      await tester.runAsync(() async {
        db = await testVeritabaniAc();
        ali = await cariEkle(db, ad: 'Ali', soyad: 'Kaya');
        veli = await cariEkle(db, ad: 'Veli', soyad: 'Demir');
        // Bugün: Ali sabah 40 kg verdi, akşam yok. Dün: Veli sabah+akşam verdi.
        await db.insert('sutler', {'cari_id': ali, 'tarih': '2026-11-05', 'sabah': 40, 'aksam': 0, 'toplam': 40});
        await db.insert('sutler', {'cari_id': veli, 'tarih': '2026-11-04', 'sabah': 30, 'aksam': 25, 'toplam': 55});
      });
      await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) => db),
          simdiProvider.overrideWithValue(() => an),
        ],
        child: const MaterialApp(home: SutEkrani()),
      ));
      await bekle(tester, () => find.byKey(const ValueKey('toplamaOzeti')).evaluate().isNotEmpty, 'liste');
    }

    testWidgets('sabah: sabahı girilen cariye yeşil tik, diğerine yok', (tester) async {
      await ac(tester, DateTime(2026, 11, 5, 8));
      await bekle(tester, () => find.text('1 / 2 alındı').evaluate().isNotEmpty, 'sayaç');
      expect(find.byKey(ValueKey('alindiTik-$ali')), findsOneWidget);
      expect(find.byKey(ValueKey('alindiTik-$veli')), findsNothing);
      expect(find.text('Sabah alındı · 40 kg'), findsOneWidget);
      expect(find.text('Sabah toplaması'), findsOneWidget);
    });

    testWidgets('öğleden sonra sabah tikleri sıfırlanır (akşam girilmemiş)', (tester) async {
      await ac(tester, DateTime(2026, 11, 5, 15));
      await bekle(tester, () => find.text('0 / 2 alındı').evaluate().isNotEmpty, 'sayaç');
      expect(find.text('Akşam toplaması'), findsOneWidget);
      expect(find.byKey(ValueKey('alindiTik-$ali')), findsNothing);
    });

    testWidgets('akşam sütü girilince tik çıkar; dünkü kayıt bugüne tik vermez', (tester) async {
      await ac(tester, DateTime(2026, 11, 5, 18));
      await tester.runAsync(() => db.update('sutler', {'aksam': 35, 'toplam': 75},
          where: 'cari_id = ? AND tarih = ?', whereArgs: [ali, '2026-11-05']));
      // Süt girişi ekranı kaydedince veriDegisti() çağırır; burada aynısı.
      final container = ProviderScope.containerOf(tester.element(find.byType(SutEkrani)));
      container.invalidate(gunlukSutlerProvider('2026-11-05'));
      await bekle(tester, () => find.text('1 / 2 alındı').evaluate().isNotEmpty, 'akşam tiki');
      expect(find.text('Akşam alındı · 35 kg'), findsOneWidget);
      expect(find.byKey(ValueKey('alindiTik-$veli')), findsNothing);
    });
  });
}
