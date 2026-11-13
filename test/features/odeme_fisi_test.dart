import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/core/providers/repository_providers.dart';
import 'package:sutyem_pro/features/cari_hesap/providers/cari_hesap_providers.dart';
import 'package:sutyem_pro/features/fis/fis_servisi.dart';
import 'package:sutyem_pro/features/fis/odeme_fisi.dart';
import 'package:sutyem_pro/features/fis/uretici_fisi.dart';
import 'package:sutyem_pro/utils/tarih_format.dart';

import '../helpers/test_db.dart';

/// Ödeme / tahsilat fişi: önceki bakiye + hareket = kalan bakiye.
void main() {
  late Database db;
  late ProviderContainer container;
  late int ali;

  setUpAll(initializeTurkishLocale);

  setUp(() async {
    db = await testVeritabaniAc();
    container = testContainer(db);
    ali = await cariEkle(db, ad: 'Ali');
  });

  tearDown(() => container.dispose());

  Future<OdemeFisi?> fis(int kayitId) async {
    final e = await container.read(cariEkstreProvider((cariId: ali, baslangic: null, bitis: null)).future);
    return odemeFisiOlustur(
      tumHareketler: e.hareketler,
      kayitId: kayitId,
      ureticiAdi: 'Ali Kaya',
      isletmeAdi: 'Kabatlı Süt',
      simdi: DateTime(2026, 5, 20, 9, 30),
    );
  }

  String metin(OdemeFisi f, int g) => f.satirlar(g).map((s) => s.metin).join('\n');

  test('ödeme: önceki alacak − ödeme = kalan; aynı günün sütü önceki bakiyeye dahil', () async {
    await fiyatTanimla(db, ali, '2026-05', sut: 20);
    final sutRepo = await container.read(sutRepositoryProvider.future);
    await sutRepo.gunlukKaydet(cariId: ali, tarih: '2026-05-01', sabah: 50, aksam: 0); // 1000
    await sutRepo.gunlukKaydet(cariId: ali, tarih: '2026-05-10', sabah: 10, aksam: 0); // 200 (ödeme günü)
    final n = container.read(cariHesapNotifierProvider.notifier);
    final id = await n.odemeYap(cariId: ali, tutar: 700, tarih: DateTime(2026, 5, 10), aciklama: 'Elden');
    await sutRepo.gunlukKaydet(cariId: ali, tarih: '2026-05-15', sabah: 5, aksam: 0); // 100 (sonradan)

    final f = (await fis(id))!;
    expect(f.tahsilatMi, isFalse);
    expect(f.oncekiBakiye, 1200);
    expect(f.tutar, 700);
    expect(f.kalanBakiye, 500);
    expect(f.guncelBakiye, 600);
    expect(f.fisNo, id);

    for (final g in FisAyarlari.gecerliGenislikler) {
      for (final s in f.satirlar(g)) {
        expect(s.metin.length, lessThanOrEqualTo(s.buyuk ? g ~/ 2 : g), reason: '$g: "${s.metin}"');
      }
    }
    final m = metin(f, 32);
    expect(m, contains('ÖDEME FİŞİ'));
    expect(m, contains('Önceki Alacağınız'));
    expect(m, contains('1.200,00 TL'));
    expect(m, contains('-700,00 TL'));
    expect(m, contains('KALAN ALACAĞINIZ'));
    expect(m, contains('500,00 TL'));
    expect(m, contains('Bugünkü Alacağınız'));
    expect(m, contains('600,00 TL'));
    expect(m, contains('Elden'));
    expect(m, contains('10.05.2026'));
    expect(m, contains('Ali Kaya'));
    expect(f.baslik, 'Ödeme Fişi');
  });

  test('tahsilat: önceki borç + tahsilat = kalan borç; borç kapanınca "HESAP KAPANDI"', () async {
    await fiyatTanimla(db, ali, '2026-05', sut: 20, sutYemi: 10);
    await db.insert('yemler', {'cari_id': ali, 'tarih': '2026-05-03', 'sut_yemi': 30, 'toplam': 30}); // 300 borç
    final n = container.read(cariHesapNotifierProvider.notifier);
    final t1 = await n.tahsilatAl(cariId: ali, tutar: 100, tarih: DateTime(2026, 5, 4));
    final t2 = await n.tahsilatAl(cariId: ali, tutar: 200, tarih: DateTime(2026, 5, 4));

    final f1 = (await fis(t1))!;
    expect(f1.tahsilatMi, isTrue);
    expect(f1.oncekiBakiye, -300);
    expect(f1.kalanBakiye, -200);
    final m1 = metin(f1, 40);
    expect(m1, contains('TAHSİLAT FİŞİ'));
    expect(m1, contains('Önceki Borcunuz'));
    expect(m1, contains('+100,00 TL'));
    expect(m1, contains('KALAN BORCUNUZ'));
    expect(m1, contains('200,00 TL'));
    // Aynı gün sonraki tahsilat hesabı kapattı → yeniden basılan fişte bugünkü durum da görünür.
    expect(m1, contains('Bugünkü Bakiye'));

    // Aynı gündeki ikinci tahsilat ilkinden SONRA sayılır.
    final f2 = (await fis(t2))!;
    expect(f2.oncekiBakiye, -200);
    expect(f2.kalanBakiye, 0);
    expect(metin(f2, 32), contains('HESAP KAPANDI'));
    expect(metin(f2, 32), isNot(contains('Bugünkü')));
    expect(f2.whatsappMetni(), startsWith('```'));
  });

  test('silinmiş / süt satırı kimliği → null', () async {
    final n = container.read(cariHesapNotifierProvider.notifier);
    final id = await n.odemeYap(cariId: ali, tutar: 10, tarih: DateTime(2026, 5, 4));
    await n.sil(id);
    expect(await fis(id), isNull);
  });

  test('UreticiFisi ve OdemeFisi ortak Fis arayüzü (önizleme ikisini de gösterir)', () {
    final List<Fis> fisler = [
      UreticiFisi(
        isletmeAdi: 'X', fisNo: 1, tarih: DateTime(2026, 5, 1), basimZamani: DateTime(2026, 5, 1),
        ureticiAdi: 'Ali', sabah: 1, aksam: 0, buAyKg: 1,
      ),
      OdemeFisi(
        isletmeAdi: 'X', fisNo: 2, tahsilatMi: false, tarih: DateTime(2026, 5, 1),
        basimZamani: DateTime(2026, 5, 1), ureticiAdi: 'Ali', tutar: 5, oncekiBakiye: 0,
      ),
    ];
    expect(fisler.map((f) => f.baslik), ['Üretici Fişi', 'Ödeme Fişi']);
    // Sıfır bakiyeden ödeme → cari borçlu kalır.
    expect(metin(fisler[1] as OdemeFisi, 32), contains('KALAN BORCUNUZ'));
  });
}
