import '../../data/repositories/cari_odeme_repository.dart';
import '../../data/repositories/cari_repository.dart';
import '../../data/repositories/fiyat_repository.dart';
import '../../data/repositories/sut_repository.dart';
import '../../data/repositories/urun_repository.dart';
import '../../data/repositories/yem_repository.dart';
import '../../models/cari_model.dart';
import '../../models/urun_model.dart';
import '../../utils/sayi_format.dart';
import '../../utils/turkce.dart';
import '../cari_hesap/models/cari_fiyat_lookup.dart';
import '../cari_hesap/providers/cari_hesap_providers.dart' show kgUrunuMu, sutTutari, yemTutari;
import 'rapor_modeli.dart';

/// ─────────────────────────────────────────────────────────────
/// RAPOR SERVİSİ — tüm raporlar gerçek kayıtlardan.
/// Tutarlar ekstre ve bakiyeyle AYNI fonksiyonlarla ([sutTutari], [yemTutari],
/// [CariFiyatLookup] — kaydın GÜNÜNDEKİ fiyat) hesaplanır: rapordaki rakam ile
/// cari ekstresindeki rakam kuruşu kuruşuna aynıdır.
/// Veriye yalnız repository'lerle erişilir (SQL yok). Pasif / silinmiş carilerin
/// kayıtları da raporlara girer (toplamlar eksik kalmasın).
/// ─────────────────────────────────────────────────────────────
class RaporServisi {
  final CariRepository cariRepo;
  final SutRepository sutRepo;
  final YemRepository yemRepo;
  final CariFiyatRepository fiyatRepo;
  final CariOdemeRepository odemeRepo;
  final UrunRepository urunRepo;
  final UrunFiyatRepository urunFiyatRepo;
  RaporServisi({
    required this.cariRepo,
    required this.sutRepo,
    required this.yemRepo,
    required this.fiyatRepo,
    required this.odemeRepo,
    required this.urunRepo,
    required this.urunFiyatRepo,
  });

  static const _enEski = '1970-01-01';

  static String gun(String tarih) => tarih.length >= 10 ? tarih.substring(0, 10) : tarih;
  static String _tarihYaz(String iso) => '${iso.substring(8, 10)}.${iso.substring(5, 7)}.${iso.substring(0, 4)}';

  /// Ürünün raporda görünen adı ve birimi (silinmiş / henüz eşitlenmemiş ürün de yazılır).
  static String urunAdi(Map<int, Urun> u, int id) => u[id]?.ad ?? 'Ürün #$id';
  static String urunBirimi(Map<int, Urun> u, int id) => u[id]?.birim ?? '';

  Future<RaporTablosu> olustur(RaporTuru tur, RaporFiltresi f) async {
    final cariler = await cariRepo.getAll();
    final adlar = {for (final c in cariler) if (c.id != null) c.id!: c};
    String ad(int id) => adlar[id]?.tamAd ?? 'Silinmiş cari #$id';
    // Cari adına göre Türkçe alfabetik (raporlar alfabetik — SUTYEM kural 16).
    int cariKarsilastir(int a, int b) {
      final ca = adlar[a], cb = adlar[b];
      if (ca != null && cb != null) return cariSirala(ca, cb);
      return turkceKarsilastir(ad(a), ad(b));
    }

    final lookup = CariFiyatLookup(await fiyatRepo.getTumFiyatlar());
    final urunFiyatlari = await urunFiyatRepo.lookup();
    final urunler = {for (final u in await urunRepo.getAll()) u.id!: u};
    final alt = f.bas == f.bit ? _tarihYaz(f.bas) : '${_tarihYaz(f.bas)} – ${_tarihYaz(f.bit)}';

    if (tur.cariZorunlu && f.cariId == null) {
      return RaporTablosu(baslik: tur.baslik, altBaslik: 'Cari seçin', sutunlar: const [RaporSutun('Bilgi')], satirlar: const [], toplamSatiri: false);
    }
    final cariAdi = f.cariId == null ? '' : ' · ${ad(f.cariId!)}';

    switch (tur) {
      // ── SÜT ───────────────────────────────────────────────────
      case RaporTuru.gunlukSut:
        final l = (await sutRepo.getAllInRange(f.bas, f.bit)).where((s) => f.cariId == null || s.cariId == f.cariId).toList()
          ..sort((a, b) {
            final t = gun(a.tarih).compareTo(gun(b.tarih));
            return t != 0 ? t : cariKarsilastir(a.cariId, b.cariId);
          });
        var eksik = 0;
        final satirlar = <List<Object?>>[];
        for (final s in l) {
          final fiyat = lookup.fiyatIcin(s.cariId, gun(s.tarih));
          final tutar = sutTutari(s, fiyat);
          if (s.toplam > 0 && tutar <= 0) eksik++;
          satirlar.add([gun(s.tarih), ad(s.cariId), s.sabah, s.aksam, s.toplam, fiyat.sutFiyat, tutar]);
        }
        return RaporTablosu(
          baslik: tur.baslik,
          altBaslik: '$alt$cariAdi',
          sutunlar: const [
            RaporSutun('Tarih', SutunTipi.tarih),
            RaporSutun('Cari'),
            RaporSutun('Sabah kg', SutunTipi.miktar),
            RaporSutun('Akşam kg', SutunTipi.miktar),
            RaporSutun('Toplam kg', SutunTipi.miktar),
            RaporSutun('Fiyat', SutunTipi.para, false),
            RaporSutun('Tutar', SutunTipi.para),
          ],
          satirlar: satirlar,
          not: _eksikNotu(eksik),
        );

      case RaporTuru.gunlukSutToplami:
        final gunler = <String, ({Set<int> cari, double sabah, double aksam, double tutar})>{};
        for (final s in await sutRepo.getAllInRange(f.bas, f.bit)) {
          final g = gun(s.tarih);
          final o = gunler[g] ?? (cari: <int>{}, sabah: 0.0, aksam: 0.0, tutar: 0.0);
          if (s.toplam > 0) o.cari.add(s.cariId);
          gunler[g] = (
            cari: o.cari,
            sabah: o.sabah + s.sabah,
            aksam: o.aksam + s.aksam,
            tutar: o.tutar + sutTutari(s, lookup.fiyatIcin(s.cariId, g)),
          );
        }
        final anahtarlar = gunler.keys.toList()..sort();
        return RaporTablosu(
          baslik: tur.baslik,
          altBaslik: alt,
          sutunlar: const [
            RaporSutun('Tarih', SutunTipi.tarih),
            RaporSutun('Gelen üretici', SutunTipi.sayi, false),
            RaporSutun('Sabah kg', SutunTipi.miktar),
            RaporSutun('Akşam kg', SutunTipi.miktar),
            RaporSutun('Toplam kg', SutunTipi.miktar),
            RaporSutun('Tutar', SutunTipi.para),
          ],
          satirlar: [
            for (final g in anahtarlar)
              [
                g,
                gunler[g]!.cari.length,
                kgYuvarla(gunler[g]!.sabah),
                kgYuvarla(gunler[g]!.aksam),
                kgYuvarla(gunler[g]!.sabah + gunler[g]!.aksam),
                kurusaYuvarla(gunler[g]!.tutar),
              ],
          ],
        );

      case RaporTuru.cariSutToplami:
        final m = <int, ({int gun, double sabah, double aksam, double tutar, bool eksik})>{};
        for (final s in await sutRepo.getAllInRange(f.bas, f.bit)) {
          final tutar = sutTutari(s, lookup.fiyatIcin(s.cariId, gun(s.tarih)));
          final o = m[s.cariId] ?? (gun: 0, sabah: 0.0, aksam: 0.0, tutar: 0.0, eksik: false);
          m[s.cariId] = (
            gun: o.gun + (s.toplam > 0 ? 1 : 0),
            sabah: o.sabah + s.sabah,
            aksam: o.aksam + s.aksam,
            tutar: o.tutar + tutar,
            eksik: o.eksik || (s.toplam > 0 && tutar <= 0),
          );
        }
        final idler = m.keys.toList()..sort(cariKarsilastir);
        return RaporTablosu(
          baslik: tur.baslik,
          altBaslik: alt,
          sutunlar: const [
            RaporSutun('Cari'),
            RaporSutun('Gün', SutunTipi.sayi, false),
            RaporSutun('Sabah kg', SutunTipi.miktar),
            RaporSutun('Akşam kg', SutunTipi.miktar),
            RaporSutun('Toplam kg', SutunTipi.miktar),
            RaporSutun('Ort. fiyat', SutunTipi.para, false),
            RaporSutun('Tutar', SutunTipi.para),
          ],
          satirlar: [
            for (final id in idler)
              () {
                final o = m[id]!;
                final kg = o.sabah + o.aksam;
                return [ad(id), o.gun, kgYuvarla(o.sabah), kgYuvarla(o.aksam), kgYuvarla(kg), kg > 0 ? kurusaYuvarla(o.tutar / kg) : 0.0, kurusaYuvarla(o.tutar)];
              }(),
          ],
          not: _eksikNotu(m.values.where((o) => o.eksik).length, cari: true),
        );

      case RaporTuru.aylikSut:
        final aylar = <String, ({double kg, double tutar, Set<int> cari})>{};
        for (final s in await sutRepo.getAllInRange(f.bas, f.bit)) {
          final ay = gun(s.tarih).substring(0, 7);
          final o = aylar[ay] ?? (kg: 0.0, tutar: 0.0, cari: <int>{});
          if (s.toplam > 0) o.cari.add(s.cariId);
          aylar[ay] = (kg: o.kg + s.toplam, tutar: o.tutar + sutTutari(s, lookup.fiyatIcin(s.cariId, gun(s.tarih))), cari: o.cari);
        }
        final anahtarlar = aylar.keys.toList()..sort();
        return RaporTablosu(
          baslik: tur.baslik,
          altBaslik: alt,
          sutunlar: const [
            RaporSutun('Ay'),
            RaporSutun('Üretici', SutunTipi.sayi, false),
            RaporSutun('Toplam kg', SutunTipi.miktar),
            RaporSutun('Ort. fiyat', SutunTipi.para, false),
            RaporSutun('Tutar', SutunTipi.para),
          ],
          satirlar: [
            for (final a in anahtarlar)
              [
                '${a.substring(5, 7)}.${a.substring(0, 4)}',
                aylar[a]!.cari.length,
                kgYuvarla(aylar[a]!.kg),
                aylar[a]!.kg > 0 ? kurusaYuvarla(aylar[a]!.tutar / aylar[a]!.kg) : 0.0,
                kurusaYuvarla(aylar[a]!.tutar),
              ],
          ],
        );

      // ── YEM / ÜRÜN ────────────────────────────────────────────
      // v16: her satır TEK ürün + miktar (ürünün kendi biriminde). Miktar sütunları farklı
      // birimleri (kg, çuval…) karıştırabileceği için toplanmaz; "Toplam kg" yalnız kg ürünlerdir.
      case RaporTuru.yemTeslimleri:
        final l = (await yemRepo.getAllInRange(f.bas, f.bit)).where((y) => f.cariId == null || y.cariId == f.cariId).toList()
          ..sort((a, b) {
            final t = gun(a.tarih).compareTo(gun(b.tarih));
            if (t != 0) return t;
            final c = cariKarsilastir(a.cariId, b.cariId);
            return c != 0 ? c : (a.id ?? 0).compareTo(b.id ?? 0);
          });
        var eksik = 0;
        final satirlar = <List<Object?>>[];
        for (final y in l) {
          final birimFiyat = urunFiyatlari.fiyat(y.cariId, y.urunId, gun(y.tarih));
          final tutar = yemTutari(y, urunFiyatlari);
          if (y.miktar > 0 && tutar <= 0) eksik++;
          satirlar.add([gun(y.tarih), ad(y.cariId), urunAdi(urunler, y.urunId), y.miktar, urunBirimi(urunler, y.urunId), birimFiyat, tutar]);
        }
        return RaporTablosu(
          baslik: tur.baslik,
          altBaslik: '$alt$cariAdi',
          sutunlar: const [
            RaporSutun('Tarih', SutunTipi.tarih),
            RaporSutun('Cari'),
            RaporSutun('Ürün'),
            RaporSutun('Miktar', SutunTipi.miktar, false),
            RaporSutun('Birim'),
            RaporSutun('Birim fiyat', SutunTipi.para, false),
            RaporSutun('Tutar', SutunTipi.para),
          ],
          satirlar: satirlar,
          not: _eksikNotu(eksik),
        );

      case RaporTuru.yemTuruBazli:
        final miktar = <int, double>{}, tl = <int, double>{};
        for (final y in await yemRepo.getAllInRange(f.bas, f.bit)) {
          miktar[y.urunId] = (miktar[y.urunId] ?? 0) + y.miktar;
          tl[y.urunId] = (tl[y.urunId] ?? 0) + yemTutari(y, urunFiyatlari);
        }
        // Ürün ekran sırasıyla; listede olmayan (silinmiş / eşitlenmemiş) en sonda.
        final sira = [for (final u in urunler.values) u.id!];
        final idler = miktar.keys.toList()
          ..sort((a, b) {
            final ia = sira.indexOf(a), ib = sira.indexOf(b);
            return (ia < 0 ? 1 << 30 : ia).compareTo(ib < 0 ? 1 << 30 : ib);
          });
        return RaporTablosu(
          baslik: tur.baslik,
          altBaslik: alt,
          sutunlar: const [
            RaporSutun('Ürün'),
            RaporSutun('Birim'),
            RaporSutun('Miktar', SutunTipi.miktar, false),
            RaporSutun('Ort. fiyat', SutunTipi.para, false),
            RaporSutun('Tutar', SutunTipi.para),
          ],
          satirlar: [
            for (final id in idler)
              if (miktar[id]! > 0)
                [
                  urunAdi(urunler, id),
                  urunBirimi(urunler, id),
                  kgYuvarla(miktar[id]!),
                  kurusaYuvarla(tl[id]! / miktar[id]!),
                  kurusaYuvarla(tl[id]!),
                ],
          ],
        );

      case RaporTuru.cariYemToplami:
        final m = <int, ({int adet, double kg, double tutar})>{};
        for (final y in await yemRepo.getAllInRange(f.bas, f.bit)) {
          final o = m[y.cariId] ?? (adet: 0, kg: 0.0, tutar: 0.0);
          m[y.cariId] = (
            adet: o.adet + 1,
            kg: o.kg + (kgUrunuMu(urunler, y.urunId) ? y.miktar : 0),
            tutar: o.tutar + yemTutari(y, urunFiyatlari),
          );
        }
        final idler = m.keys.toList()..sort(cariKarsilastir);
        return RaporTablosu(
          baslik: tur.baslik,
          altBaslik: alt,
          sutunlar: const [
            RaporSutun('Cari'),
            RaporSutun('Kalem', SutunTipi.sayi, false),
            RaporSutun('Toplam kg', SutunTipi.miktar),
            RaporSutun('Tutar', SutunTipi.para),
          ],
          satirlar: [for (final id in idler) [ad(id), m[id]!.adet, kgYuvarla(m[id]!.kg), kurusaYuvarla(m[id]!.tutar)]],
          not: 'Toplam kg yalnız birimi kg olan ürünlerdir (çuval / adet gibi ürünler yalnız tutara girer).',
        );

      // ── CARİ HESAP ────────────────────────────────────────────
      case RaporTuru.cariHesapOzeti:
        final donem = await _hesaplar(f.bas, f.bit, lookup, urunFiyatlari, urunler);
        final genel = await _hesaplar(_enEski, f.bit, lookup, urunFiyatlari, urunler);
        final idler = {...donem.keys, ...genel.entries.where((e) => e.value.bakiye.abs() >= 0.005).map((e) => e.key)}.toList()..sort(cariKarsilastir);
        return RaporTablosu(
          baslik: tur.baslik,
          altBaslik: '$alt · genel bakiye ${_tarihYaz(f.bit)} itibarıyla',
          sutunlar: const [
            RaporSutun('Cari'),
            RaporSutun('Süt kg', SutunTipi.miktar),
            RaporSutun('Süt tutarı', SutunTipi.para),
            RaporSutun('Yem kg', SutunTipi.miktar),
            RaporSutun('Yem tutarı', SutunTipi.para),
            RaporSutun('Ödeme', SutunTipi.para),
            RaporSutun('Tahsilat', SutunTipi.para),
            RaporSutun('Dönem net', SutunTipi.para),
            RaporSutun('Genel bakiye', SutunTipi.para),
            RaporSutun('Durum'),
          ],
          satirlar: [
            for (final id in idler)
              () {
                final d = donem[id] ?? _Hesap();
                final b = genel[id]?.bakiye ?? 0.0;
                return [ad(id), d.sutKg, d.sut, d.yemKg, d.yem, d.odeme, d.tahsilat, d.bakiye, b, durum(b)];
              }(),
          ],
          not: 'Net / bakiye: (süt + tahsilat) − (yem + ödeme). Artı = cari ALACAKLI (işletme borçlu), eksi = cari BORÇLU.',
        );

      case RaporTuru.bakiyeListesi:
        final genel = await _hesaplar(_enEski, f.bit, lookup, urunFiyatlari, urunler);
        final idler = genel.entries.where((e) => e.value.bakiye.abs() >= 0.005).map((e) => e.key).toList()..sort(cariKarsilastir);
        return RaporTablosu(
          baslik: tur.baslik,
          altBaslik: '${_tarihYaz(f.bit)} itibarıyla',
          sutunlar: const [
            RaporSutun('Cari'),
            RaporSutun('Telefon'),
            RaporSutun('Durum'),
            RaporSutun('Alacaklı (işletme borçlu)', SutunTipi.para),
            RaporSutun('Borçlu (cari borçlu)', SutunTipi.para),
          ],
          satirlar: [
            for (final id in idler)
              () {
                final b = genel[id]!.bakiye;
                return [
                  ad(id),
                  adlar[id]?.telefon ?? '',
                  '${durum(b)}${adlar[id]?.aktif == false ? ' (pasif)' : ''}',
                  b > 0 ? b : null,
                  b < 0 ? -b : null,
                ];
              }(),
          ],
          not: () {
            final net = kurusaYuvarla(genel.values.fold<double>(0, (a, h) => a + h.bakiye));
            return 'Net: ${net >= 0 ? 'işletme carilere' : 'cariler işletmeye'} toplam ${tlYaz(net.abs())} borçlu.';
          }(),
        );

      case RaporTuru.odemeTahsilat:
        final l = (await odemeRepo.getTumOdemeTahsilatlar())
            .where((o) => gun(o.tarih).compareTo(f.bas) >= 0 && gun(o.tarih).compareTo(f.bit) <= 0)
            .where((o) => f.cariId == null || o.cariId == f.cariId)
            .toList()
          ..sort((a, b) {
            final t = gun(a.tarih).compareTo(gun(b.tarih));
            return t != 0 ? t : (a.id ?? 0).compareTo(b.id ?? 0);
          });
        return RaporTablosu(
          baslik: tur.baslik,
          altBaslik: '$alt$cariAdi',
          sutunlar: const [
            RaporSutun('Tarih', SutunTipi.tarih),
            RaporSutun('Cari'),
            RaporSutun('Ödeme (cariye)', SutunTipi.para),
            RaporSutun('Tahsilat (cariden)', SutunTipi.para),
            RaporSutun('Açıklama'),
          ],
          satirlar: [
            for (final o in l)
              [
                gun(o.tarih),
                ad(o.cariId),
                o.islemTuru == 'odeme' ? kurusaYuvarla(o.toplamTutar) : null,
                o.islemTuru == 'tahsilat' ? kurusaYuvarla(o.toplamTutar) : null,
                o.aciklama ?? '',
              ],
          ],
        );

      case RaporTuru.cariEkstre:
        final id = f.cariId!;
        final devir = (await _hesaplar(_enEski, _oncekiGun(f.bas), lookup, urunFiyatlari, urunler, cariId: id))[id]?.bakiye ?? 0.0;
        final hareketler = await _hareketler(id, f.bas, f.bit, lookup, urunFiyatlari, urunler);
        var yuruyen = devir;
        final satirlar = <List<Object?>>[
          [f.bas, 'Devir', 'Önceki bakiye', null, null, devir],
        ];
        for (final h in hareketler) {
          yuruyen = kurusaYuvarla(yuruyen + h.arti - h.eksi);
          satirlar.add([h.tarih, h.islem, h.aciklama, h.arti > 0 ? h.arti : null, h.eksi > 0 ? h.eksi : null, yuruyen]);
        }
        return RaporTablosu(
          baslik: tur.baslik,
          altBaslik: '${ad(id)} · $alt',
          sutunlar: const [
            RaporSutun('Tarih', SutunTipi.tarih),
            RaporSutun('İşlem'),
            RaporSutun('Açıklama'),
            RaporSutun('Süt / Tahsilat (+)', SutunTipi.para),
            RaporSutun('Yem / Ödeme (−)', SutunTipi.para),
            RaporSutun('Bakiye', SutunTipi.para, false),
          ],
          satirlar: satirlar,
          not: 'Son bakiye: ${tlYaz(yuruyen.abs())} · ${durum(yuruyen)}. Artı = cari alacaklı, eksi = cari borçlu.',
        );

      // ── KONTROL ───────────────────────────────────────────────
      case RaporTuru.fiyatEksik:
        final satirlar = <List<Object?>>[];
        for (final s in await sutRepo.getAllInRange(f.bas, f.bit)) {
          if (s.toplam > 0 && sutTutari(s, lookup.fiyatIcin(s.cariId, gun(s.tarih))) <= 0) {
            satirlar.add([gun(s.tarih), ad(s.cariId), 'Süt', s.toplam]);
          }
        }
        for (final y in await yemRepo.getAllInRange(f.bas, f.bit)) {
          if (y.miktar > 0 && yemTutari(y, urunFiyatlari) <= 0) {
            satirlar.add([gun(y.tarih), ad(y.cariId), urunAdi(urunler, y.urunId), y.miktar]);
          }
        }
        satirlar.sort((a, b) {
          final t = (a[0] as String).compareTo(b[0] as String);
          return t != 0 ? t : turkceKarsilastir(a[1] as String, b[1] as String);
        });
        return RaporTablosu(
          baslik: tur.baslik,
          altBaslik: alt,
          sutunlar: const [RaporSutun('Tarih', SutunTipi.tarih), RaporSutun('Cari'), RaporSutun('Tür'), RaporSutun('Miktar', SutunTipi.miktar, false)],
          satirlar: satirlar,
          not: satirlar.isEmpty ? 'Sorun yok: bu dönemde fiyatı eksik kayıt bulunmadı.' : 'Bu kayıtlar 0 TL sayıldı. Süt / Yem Fiyatları ekranından fiyat tanımlayın.',
        );
    }
  }

  static String durum(double b) => b > 0.004 ? 'Alacaklı' : (b < -0.004 ? 'Borçlu' : 'Sıfır');

  static String? _eksikNotu(int n, {bool cari = false}) =>
      n == 0 ? null : '$n ${cari ? 'caride' : 'kayıtta'} fiyat tanımlı değil, tutar 0 TL sayıldı (Kontrol → Fiyatı Eksik Kayıtlar).';

  static String _oncekiGun(String iso) {
    final d = DateTime.parse(iso).subtract(const Duration(days: 1));
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// Cari başına süt/yem/ödeme/tahsilat ve net (ekstre / tumKalanBorclar ile aynı formül).
  Future<Map<int, _Hesap>> _hesaplar(
      String bas, String bit, CariFiyatLookup lookup, UrunFiyatLookup urunFiyatlari, Map<int, Urun> urunler,
      {int? cariId}) async {
    final m = <int, _Hesap>{};
    _Hesap h(int id) => m.putIfAbsent(id, _Hesap.new);
    if (bit.compareTo(bas) < 0) return m;
    for (final s in await sutRepo.getAllInRange(bas, bit)) {
      if (cariId != null && s.cariId != cariId) continue;
      h(s.cariId)
        ..sutKg += s.toplam
        ..sut += sutTutari(s, lookup.fiyatIcin(s.cariId, gun(s.tarih)));
    }
    for (final y in await yemRepo.getAllInRange(bas, bit)) {
      if (cariId != null && y.cariId != cariId) continue;
      h(y.cariId)
        ..yemKg += kgUrunuMu(urunler, y.urunId) ? y.miktar : 0
        ..yem += yemTutari(y, urunFiyatlari);
    }
    for (final o in await odemeRepo.getTumOdemeTahsilatlar()) {
      if (cariId != null && o.cariId != cariId) continue;
      final g = gun(o.tarih);
      if (g.compareTo(bas) < 0 || g.compareTo(bit) > 0) continue;
      final t = kurusaYuvarla(o.toplamTutar);
      if (o.islemTuru == 'tahsilat') {
        h(o.cariId).tahsilat += t;
      } else {
        h(o.cariId).odeme += t;
      }
    }
    for (final x in m.values) {
      x.yuvarla();
    }
    return m;
  }

  /// Ekstre hareketleri, eskiden yeniye; aynı gün sırası süt, yem, ödeme, tahsilat.
  Future<List<({String tarih, String islem, String aciklama, double arti, double eksi})>> _hareketler(
      int cariId, String bas, String bit, CariFiyatLookup lookup, UrunFiyatLookup urunFiyatlari, Map<int, Urun> urunler) async {
    final l = <({String tarih, int sira, int id, String islem, String aciklama, double arti, double eksi})>[];
    for (final s in await sutRepo.getByCari(cariId, bas, bit)) {
      final fiyat = lookup.fiyatIcin(cariId, gun(s.tarih));
      l.add((
        tarih: gun(s.tarih),
        sira: 0,
        id: s.id ?? 0,
        islem: 'Süt alımı',
        aciklama: '${kgYaz(s.toplam)} kg × ${tlYaz(fiyat.sutFiyat)}',
        arti: sutTutari(s, fiyat),
        eksi: 0.0,
      ));
    }
    for (final y in await yemRepo.getByCari(cariId, bas, bit)) {
      l.add((
        tarih: gun(y.tarih),
        sira: 1,
        id: y.id ?? 0,
        islem: 'Yem verişi',
        aciklama: '${urunAdi(urunler, y.urunId)} ${kgYaz(y.miktar)} ${urunBirimi(urunler, y.urunId)} × ${tlYaz(urunFiyatlari.fiyat(cariId, y.urunId, gun(y.tarih)))}',
        arti: 0.0,
        eksi: yemTutari(y, urunFiyatlari),
      ));
    }
    for (final o in await odemeRepo.getByCariInRange(cariId, bas, bit)) {
      if (o.islemTuru != 'odeme' && o.islemTuru != 'tahsilat') continue;
      final t = kurusaYuvarla(o.toplamTutar);
      final tahsilat = o.islemTuru == 'tahsilat';
      l.add((
        tarih: gun(o.tarih),
        sira: tahsilat ? 3 : 2,
        id: o.id ?? 0,
        islem: tahsilat ? 'Tahsilat (cariden)' : 'Ödeme (cariye)',
        aciklama: o.aciklama ?? '',
        arti: tahsilat ? t : 0.0,
        eksi: tahsilat ? 0.0 : t,
      ));
    }
    l.sort((a, b) {
      final t = a.tarih.compareTo(b.tarih);
      if (t != 0) return t;
      final s = a.sira.compareTo(b.sira);
      return s != 0 ? s : a.id.compareTo(b.id);
    });
    return [for (final x in l) (tarih: x.tarih, islem: x.islem, aciklama: x.aciklama, arti: x.arti, eksi: x.eksi)];
  }
}

class _Hesap {
  double sutKg = 0, sut = 0, yemKg = 0, yem = 0, odeme = 0, tahsilat = 0;
  double get bakiye => kurusaYuvarla((sut + tahsilat) - (yem + odeme));
  void yuvarla() {
    sutKg = kgYuvarla(sutKg);
    sut = kurusaYuvarla(sut);
    yemKg = kgYuvarla(yemKg);
    yem = kurusaYuvarla(yem);
    odeme = kurusaYuvarla(odeme);
    tahsilat = kurusaYuvarla(tahsilat);
  }
}

/// Rapor ekranında cari seçimi için (aktif + pasif, alfabetik).
List<Cari> raporCarileri(List<Cari> l) => [...l]..sort(cariSirala);
