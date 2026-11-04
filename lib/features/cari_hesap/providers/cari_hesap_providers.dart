import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/repository_providers.dart';
import '../../../core/providers/veri_surumu_provider.dart';
import '../../../models/cari_fiyat_model.dart';
import '../../../models/cari_odeme_model.dart';
import '../../../models/sut_model.dart';
import '../../../models/yem_model.dart';
import '../../../utils/sayi_format.dart';
import '../models/cari_fiyat_lookup.dart';
import '../models/cari_hareket.dart';

/// Bir cari + opsiyonel tarih aralığı için parametre anahtarı.
/// `baslangic`/`bitis` null ise TÜM ZAMANLAR anlamına gelir.
///
/// ÖNEMLİ (family provider parametre kararlılığı): `baslangic`/`bitis`
/// her zaman GÜN hassasiyetinde (saat/dakika/saniye sıfırlanmış)
/// DateTime olmalıdır. Aksi halde `DateTime.now()` gibi mikrosaniye
/// hassasiyetli bir değer geçilirse, Riverpod her rebuild'de "farklı"
/// bir parametre görüp hesaplamayı sonsuza dek yeniden başlatır — bu
/// projede daha önce yaşanmış ve düzeltilmiş bir hata sınıfıdır (bkz.
/// eski `_buAy` hatası). Ekran tarafı, seçilen tarihleri her zaman
/// `DateTime(y, m, d)` şeklinde normalize ederek geçirmelidir.
typedef CariEkstreParam = ({int cariId, DateTime? baslangic, DateTime? bitis});

const _tumZamanlarBaslangic = '1970-01-01';
const _tumZamanlarBitis = '2999-12-31';

final _gunFormat = DateFormat('yyyy-MM-dd');

/// ─────────────────────────────────────────────────────────────
/// BAKİYE HESABININ TEK KAYNAĞI
/// ─────────────────────────────────────────────────────────────
///
/// Ekstre ve toplu bakiye AYNI fonksiyonları kullanır; böylece Ödemeler
/// sekmesindeki rakam ile carinin ekstresindeki rakam asla ayrışmaz.
/// Her satır kuruşa yuvarlanır — ekstrede satırların toplamı, gösterilen
/// genel toplamla kuruşu kuruşuna aynıdır.
double sutTutari(Sut s, CariFiyat fiyat) => kurusaYuvarla(s.toplam * fiyat.sutFiyat);

double yemTutari(Yem y, CariFiyat fiyat) => kurusaYuvarla(fiyat.yemBorc(
    y.sutYemi, y.besiYemi, y.bBaslangic, y.bBuyutme, y.kuzuYemi, y.tavukYemi));

/// ─────────────────────────────────────────────────────────────
/// CANLI CARİ EKSTRESİ
/// ─────────────────────────────────────────────────────────────
///
/// Süt ve yem hareketleri artık ayrı bir "kapatma" adımı gerektirmez —
/// `sutler`/`yemler` tablolarındaki GERÇEK ZAMANLI kayıtlardan, ilgili
/// ayın tanımlı fiyatıyla (bkz. `CariFiyatLookup`) anında hesaplanır.
/// Ödeme/tahsilat ise kullanıcının elle girdiği, `cari_odemeler`
/// tablosunda saklanan gerçek kayıtlardır.
///
/// Tarih filtresi verilirse (`baslangic`/`bitis` doluysa), hem hareket
/// listesi hem de bakiye YALNIZCA o aralığa göre hesaplanır (o dönemin
/// net hareketi). Filtre yoksa tüm zamanların toplamı gösterilir.
///
/// `autoDispose`: ekran kapanınca önbellek bırakılır, her açılışta güncel
/// veriyle yeniden hesaplanır. [veriSurumuProvider] izlendiği için ekran
/// açıkken yapılan değişiklikler de anında yansır.
final cariEkstreProvider = FutureProvider.autoDispose
    .family<CariEkstreSonucu, CariEkstreParam>((ref, params) async {
  ref.watch(veriSurumuProvider);
  final sutRepo = await ref.watch(sutRepositoryProvider.future);
  final yemRepo = await ref.watch(yemRepositoryProvider.future);
  final fiyatRepo = await ref.watch(cariFiyatRepositoryProvider.future);
  final odemeRepo = await ref.watch(cariOdemeRepositoryProvider.future);

  final filtreliMi = params.baslangic != null || params.bitis != null;
  final bas = params.baslangic != null ? _gunFormat.format(params.baslangic!) : _tumZamanlarBaslangic;
  final bit = params.bitis != null ? _gunFormat.format(params.bitis!) : _tumZamanlarBitis;

  final sutler = await sutRepo.getByCari(params.cariId, bas, bit);
  final yemler = await yemRepo.getByCari(params.cariId, bas, bit);
  final odemeler = (await odemeRepo.getByCariInRange(params.cariId, bas, bit))
      .where((o) => o.islemTuru == 'odeme' || o.islemTuru == 'tahsilat')
      .toList();

  final tumFiyatlar = await fiyatRepo.getTumFiyatlar(cariId: params.cariId);
  final lookup = CariFiyatLookup(tumFiyatlar);

  final hareketler = <CariHareket>[];
  double toplamSut = 0, toplamYem = 0, toplamOdeme = 0, toplamTahsilat = 0;
  double toplamSutKg = 0, toplamYemKg = 0;
  var herhangiFiyatEksikMi = false;

  for (final s in sutler) {
    final fiyat = lookup.fiyatIcin(params.cariId, s.tarih.substring(0, 7));
    final tutar = sutTutari(s, fiyat);
    final eksik = s.toplam > 0 && tutar <= 0;
    if (eksik) herhangiFiyatEksikMi = true;
    toplamSut += tutar;
    toplamSutKg += s.toplam;
    hareketler.add(CariHareket(
      tarih: DateTime.parse(s.tarih),
      tur: 'sut',
      tutar: tutar,
      kredi: true,
      baslik: 'Süt Alımı',
      aciklama: '${sayiGoster(s.toplam)} kg × ${fiyat.sutFiyat.toStringAsFixed(2)} ₺',
      fiyatEksik: eksik,
    ));
  }

  for (final y in yemler) {
    final fiyat = lookup.fiyatIcin(params.cariId, y.tarih.substring(0, 7));
    final tutar = yemTutari(y, fiyat);
    final eksik = y.toplam > 0 && tutar <= 0;
    if (eksik) herhangiFiyatEksikMi = true;
    toplamYem += tutar;
    toplamYemKg += y.toplam;
    hareketler.add(CariHareket(
      tarih: DateTime.parse(y.tarih),
      tur: 'yem',
      tutar: tutar,
      kredi: false,
      baslik: 'Yem Verişi',
      aciklama: '${sayiGoster(y.toplam)} kg',
      fiyatEksik: eksik,
    ));
  }

  for (final o in odemeler) {
    final kredi = o.islemTuru == 'tahsilat';
    final tutar = kurusaYuvarla(o.toplamTutar);
    if (kredi) {
      toplamTahsilat += tutar;
    } else {
      toplamOdeme += tutar;
    }
    hareketler.add(CariHareket(
      tarih: DateTime.parse(o.tarih),
      tur: o.islemTuru,
      tutar: tutar,
      kredi: kredi,
      baslik: o.islemAdi,
      aciklama: o.aciklama,
      kayitId: o.id,
    ));
  }

  // Yeni → eski; aynı gün içinde sabit sıra: süt, yem, ödeme, tahsilat
  // (Dart'ın sort'u kararlı değildir, ikinci anahtar açıkça verilir).
  const turSirasi = {'sut': 0, 'yem': 1, 'odeme': 2, 'tahsilat': 3};
  hareketler.sort((a, b) {
    final t = b.tarih.compareTo(a.tarih);
    if (t != 0) return t;
    final s = (turSirasi[a.tur] ?? 9).compareTo(turSirasi[b.tur] ?? 9);
    return s != 0 ? s : (b.kayitId ?? 0).compareTo(a.kayitId ?? 0);
  });

  return CariEkstreSonucu(
    hareketler: hareketler,
    toplamSut: kurusaYuvarla(toplamSut),
    toplamYem: kurusaYuvarla(toplamYem),
    toplamOdeme: kurusaYuvarla(toplamOdeme),
    toplamTahsilat: kurusaYuvarla(toplamTahsilat),
    toplamSutKg: toplamSutKg,
    toplamYemKg: toplamYemKg,
    bakiye: kurusaYuvarla((toplamSut + toplamTahsilat) - (toplamYem + toplamOdeme)),
    filtreliMi: filtreliMi,
    filtreBaslangic: params.baslangic,
    filtreBitis: params.bitis,
    herhangiFiyatEksikMi: herhangiFiyatEksikMi,
  );
});

/// Tüm carilerin İŞARETLİ (signed), CANLI bakiyesi — Ödemeler sekmesi
/// ve Dashboard'da kullanılır. `cariEkstreProvider` ile AYNI hesaplama
/// fonksiyonlarını ([sutTutari], [yemTutari]) tüm cariler için TEK
/// seferde, verimli toplu sorgularla uygular (N+1 sorgusu yok).
final tumKalanBorclarProvider = FutureProvider<Map<int, double>>((ref) async {
  ref.watch(veriSurumuProvider);
  final sutRepo = await ref.watch(sutRepositoryProvider.future);
  final yemRepo = await ref.watch(yemRepositoryProvider.future);
  final fiyatRepo = await ref.watch(cariFiyatRepositoryProvider.future);
  final odemeRepo = await ref.watch(cariOdemeRepositoryProvider.future);

  final sutler = await sutRepo.getAllInRange(_tumZamanlarBaslangic, _tumZamanlarBitis);
  final yemler = await yemRepo.getAllInRange(_tumZamanlarBaslangic, _tumZamanlarBitis);
  final lookup = CariFiyatLookup(await fiyatRepo.getTumFiyatlar());

  final bakiyeler = <int, double>{};
  void ekle(int cariId, double tutar) => bakiyeler[cariId] = (bakiyeler[cariId] ?? 0) + tutar;

  for (final s in sutler) {
    ekle(s.cariId, sutTutari(s, lookup.fiyatIcin(s.cariId, s.tarih.substring(0, 7))));
  }
  for (final y in yemler) {
    ekle(y.cariId, -yemTutari(y, lookup.fiyatIcin(y.cariId, y.tarih.substring(0, 7))));
  }
  for (final o in await odemeRepo.getTumOdemeTahsilatlar()) {
    final tutar = kurusaYuvarla(o.toplamTutar);
    ekle(o.cariId, o.islemTuru == 'tahsilat' ? tutar : -tutar);
  }

  return bakiyeler.map((id, b) => MapEntry(id, kurusaYuvarla(b)));
});

/// Bir kaydın denetim (değişiklik) geçmişi.
final cariOdemeGecmisiProvider =
    FutureProvider.family<List<Map<String, Object?>>, int>((ref, kayitId) async {
  final repo = await ref.watch(cariOdemeRepositoryProvider.future);
  return repo.gecmisi(kayitId);
});

/// ─────────────────────────────────────────────────────────────
/// CARİ HESAP NOTIFIER — ödeme/tahsilat CRUD + otomatik yenileme
/// ─────────────────────────────────────────────────────────────
///
/// Süt/yem artık canlı hesaplandığı için burada "ekle" metotları yok —
/// yalnızca manuel nakit hareketleri (ödeme/tahsilat) ve bunların
/// silinmesi bu notifier üzerinden yapılır. Her değişiklik
/// [veriDegisti] ile tüm bakiye ekranlarını yeniler.
class CariHesapNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> sil(int id) async {
    final repo = await ref.read(cariOdemeRepositoryProvider.future);
    await repo.delete(id);
    veriDegisti(ref);
  }

  /// İşletmenin cariye yaptığı nakit ödeme (bakiye azalır / negatife
  /// dönebilir — fazla ödenirse cari işletmeye borçlanır).
  Future<void> odemeYap({
    required int cariId,
    required double tutar,
    DateTime? tarih,
    String? aciklama,
  }) => _hareketEkle(
        cariId: cariId,
        islemTuru: 'odeme',
        tutar: tutar,
        tarih: tarih,
        aciklama: aciklama ?? 'Nakit ödeme',
      );

  /// İşletmenin cariden tahsil ettiği nakit (cari borcu azalır).
  Future<void> tahsilatAl({
    required int cariId,
    required double tutar,
    DateTime? tarih,
    String? aciklama,
  }) => _hareketEkle(
        cariId: cariId,
        islemTuru: 'tahsilat',
        tutar: tutar,
        tarih: tarih,
        aciklama: aciklama ?? 'Nakit tahsilat',
      );

  Future<void> _hareketEkle({
    required int cariId,
    required String islemTuru,
    required double tutar,
    DateTime? tarih,
    String? aciklama,
  }) async {
    if (!tutar.isFinite || tutar <= 0) {
      throw ArgumentError.value(tutar, 'tutar', 'Tutar sıfırdan büyük olmalı');
    }
    final yuvarli = kurusaYuvarla(tutar);
    final repo = await ref.read(cariOdemeRepositoryProvider.future);
    await repo.insert(CariOdeme(
      cariId: cariId,
      tarih: _gunFormat.format(tarih ?? DateTime.now()),
      islemTuru: islemTuru,
      miktar: 1,
      birimFiyat: yuvarli,
      toplamTutar: yuvarli,
      aciklama: (aciklama == null || aciklama.trim().isEmpty) ? null : aciklama.trim(),
    ));
    veriDegisti(ref);
  }
}

final cariHesapNotifierProvider =
    AsyncNotifierProvider<CariHesapNotifier, void>(CariHesapNotifier.new);
