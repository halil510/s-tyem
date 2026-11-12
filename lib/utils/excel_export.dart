import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../data/repositories/cari_repository.dart' show cariSirala;
import '../models/cari_model.dart';
import '../models/sut_model.dart';
import '../models/yem_model.dart';
import '../features/cari_hesap/providers/cari_hesap_providers.dart' show AylikCariOzet;
import '../features/donem/donem_servisi.dart' show HakedisSatiri;
import 'ekstre_satirlari.dart';
import 'sayi_format.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart';

/// Tüm Excel raporları.
///
/// Ortak kurallar (2026-11-05 Excel taraması):
/// * Kitapta boş "Sheet1" sayfası KALMAZ (eskiden dosya boş sayfayla açılıyordu).
/// * Her sayı kuruşa / 2 haneye yuvarlanır (0.1 + 0.2 → 0.3, `0.30000000000000004` değil).
/// * Hücreler sütun/satır numarasıyla yazılır (harf hesabı 702. sütunda çöküyordu → yıllık rapor).
/// * Dosya adındaki `/ \ : * ? " < > |` temizlenir (cari adında "/" dosyayı yazdırmıyordu).
/// * Raporda listede olmayan (pasif / silinmiş) bir carinin kaydı varsa satır
///   olarak yine gösterilir — genel toplam her zaman TÜM kayıtların toplamıdır.
/// * Girdi listeleri değiştirilmez (yem raporu eskiden ekrandaki listeyi sıralıyordu).
class ExcelExport {
  static final _baslikStil = CellStyle(
    backgroundColorHex: ExcelColor.fromHexString('#B3E5FC'),
    bold: true,
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
  );
  static final _isimStil = CellStyle(backgroundColorHex: ExcelColor.fromHexString('#E0E0E0'), bold: true);
  static final _toplamStil = CellStyle(backgroundColorHex: ExcelColor.fromHexString('#FFF59D'), bold: true);
  static final _gunFormat = DateFormat('yyyy-MM-dd');

  // ─── Ortak yardımcılar ────────────────────────────────────────────

  /// Dosya adında işletim sisteminin kabul etmediği karakterleri temizler.
  static String dosyaAdi(String ad) {
    final temiz = ad
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return temiz.isEmpty ? 'Rapor' : temiz;
  }

  static double _y(num v) => kurusaYuvarla(v.toDouble());

  static const _bosSayfa = 'Sheet1';

  /// Yeni kitap; [sayfa] açılışta gösterilen sayfa olur. `createExcel`'in
  /// eklediği boş "Sheet1" [_kaydet] içinde silinir. (excel 3.0'da silme/yeniden
  /// adlandırma "unmodifiable list" hatasıyla çöküyordu → Hakediş Excel'i hiç
  /// oluşmuyordu; paket 4.0.6'ya yükseltildi.)
  static Excel _yeniKitap(String sayfa) {
    final excel = Excel.createExcel();
    excel[sayfa];
    excel.setDefaultSheet(sayfa);
    return excel;
  }

  static void _yaz(Sheet sheet, int sutun, int satir, Object? deger, [CellStyle? stil]) {
    final hucre = sheet.cell(CellIndex.indexByColumnRow(columnIndex: sutun, rowIndex: satir));
    hucre.value = switch (deger) {
      null => null,
      num n => DoubleCellValue(_y(n)),
      _ => TextCellValue(deger.toString()),
    };
    if (stil != null) hucre.cellStyle = stil;
  }

  static void _basliklar(Sheet sheet, int satir, List<String> basliklar) {
    for (var i = 0; i < basliklar.length; i++) {
      _yaz(sheet, i, satir, basliklar[i], _baslikStil);
    }
  }

  static Future<File> _kaydet(Excel excel, String ad) async {
    if (excel.tables.length > 1 && excel.tables.containsKey(_bosSayfa)) {
      excel.delete(_bosSayfa);
    }
    final bytes = excel.save();
    if (bytes == null) throw Exception('Excel dosyası oluşturulamadı.');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}${dosyaAdi(ad)}.xlsx');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Listede olmayan cari kimlikleri için yer tutucu ekleyip Türkçe sıralar.
  static List<Cari> _carileriTamamla(List<Cari> cariler, Iterable<int> kayitCariIdleri) {
    final bilinen = {for (final c in cariler) if (c.id != null) c.id!};
    final eksik = kayitCariIdleri.toSet().difference(bilinen).toList()..sort();
    return [
      ...cariler.where((c) => c.id != null),
      for (final id in eksik) Cari(id: id, ad: 'Silinmiş/pasif cari', soyad: '#$id'),
    ]..sort(cariSirala);
  }

  static String _gunAnahtari(String tarih) =>
      tarih.length >= 10 ? tarih.substring(0, 10) : _gunFormat.format(DateTime.parse(tarih));

  // ─── 🥛 SÜT RAPORU ─────────────────────────────────────────────────

  static Future<File> exportSutRaporu({
    required List<Cari> cariler,
    required List<Sut> sutler,
    required DateTime startDate,
    required DateTime endDate,
    required String raporAdi,
  }) async {
    try {
      final excel = _yeniKitap('Süt Raporu');
      final toplamlar = _sutSayfasi(excel['Süt Raporu'], cariler, sutler, startDate, endDate);
      _sutToplamSayfasi(excel[sutToplamSayfasi], toplamlar, startDate, endDate);
      return await _kaydet(excel, raporAdi);
    } catch (e, st) {
      debugPrint('❌ Süt raporu hatası: $e\n$st');
      rethrow;
    }
  }

  /// Süt raporunun 2. sayfası: her cari tek satır, yalnız dönem toplamı.
  static const sutToplamSayfasi = 'Süt Toplamları';

  /// "Süt Toplamları" sayfası: başlıkta tarih aralığı; İsim Soyisim | Toplam (kg);
  /// en altta GENEL TOPLAM. Sıra ve rakamlar 1. sayfayla BİREBİR aynıdır.
  static void _sutToplamSayfasi(
      Sheet sheet, List<(String, double)> toplamlar, DateTime startDate, DateTime endDate) {
    final f = DateFormat('dd.MM.yyyy');
    _yaz(sheet, 0, 0, 'Süt Toplamları — ${f.format(startDate)} - ${f.format(endDate)}',
        CellStyle(bold: true, fontSize: 13));
    _basliklar(sheet, 2, ['İsim Soyisim', 'Toplam (kg)']);
    var satir = 3;
    var genel = 0.0;
    for (final (ad, toplam) in toplamlar) {
      _yaz(sheet, 0, satir, ad, _isimStil);
      _yaz(sheet, 1, satir, toplam);
      genel += toplam;
      satir++;
    }
    _yaz(sheet, 0, satir, 'GENEL TOPLAM', _toplamStil);
    _yaz(sheet, 1, satir, genel, _toplamStil);
    sheet.setColumnWidth(0, 34);
    sheet.setColumnWidth(1, 16);
  }

  /// 1. sayfa (günlük sabah/akşam). Her carinin dönem toplamını, sayfadaki
  /// sırayla döner (2. sayfa bunu kullanır).
  static List<(String, double)> _sutSayfasi(
      Sheet sheet, List<Cari> cariler, List<Sut> sutler, DateTime startDate, DateTime endDate) {
    final bas = DateTime(startDate.year, startDate.month, startDate.day);
    final bit = DateTime(endDate.year, endDate.month, endDate.day);
    final gunler = <String>[];
    for (var g = bas; !g.isAfter(bit); g = DateTime(g.year, g.month, g.day + 1)) {
      gunler.add(_gunFormat.format(g));
    }
    final gunSirasi = {for (var i = 0; i < gunler.length; i++) gunler[i]: i};

    // cariId → gün sırası → [sabah, akşam]  (tek geçiş; eskiden cari×gün×kayıt tarama)
    final tablo = <int, Map<int, List<double>>>{};
    for (final s in sutler) {
      final i = gunSirasi[_gunAnahtari(s.tarih)];
      if (i == null) continue; // aralık dışı
      final hucre = tablo.putIfAbsent(s.cariId, () => {}).putIfAbsent(i, () => [0, 0]);
      hucre[0] += s.sabah;
      hucre[1] += s.aksam;
    }

    final basliklar = ['İsim Soyisim / Günler'];
    for (final g in gunler) {
      final gun = DateFormat('dd MMM', 'tr_TR').format(DateTime.parse(g));
      basliklar
        ..add('$gun S')
        ..add('$gun A');
    }
    basliklar.add('TOPLAM (kg)');
    _basliklar(sheet, 0, basliklar);

    final gunSabah = List<double>.filled(gunler.length, 0);
    final gunAksam = List<double>.filled(gunler.length, 0);
    final ozet = <(String, double)>[];
    var satir = 1;
    for (final cari in _carileriTamamla(cariler, tablo.keys)) {
      final kayitlar = tablo[cari.id] ?? const {};
      _yaz(sheet, 0, satir, cari.tamAd, _isimStil);
      var toplam = 0.0;
      for (var i = 0; i < gunler.length; i++) {
        final h = kayitlar[i] ?? const [0.0, 0.0];
        _yaz(sheet, 1 + i * 2, satir, h[0]);
        _yaz(sheet, 2 + i * 2, satir, h[1]);
        gunSabah[i] += h[0];
        gunAksam[i] += h[1];
        toplam += h[0] + h[1];
      }
      _yaz(sheet, 1 + gunler.length * 2, satir, toplam, _toplamStil);
      ozet.add((cari.tamAd, toplam)); // yuvarlama yazarken (2. sayfa genel toplamı 1. sayfayla aynı)
      satir++;
    }

    _yaz(sheet, 0, satir, 'GENEL TOPLAM', _toplamStil);
    var genel = 0.0;
    for (var i = 0; i < gunler.length; i++) {
      _yaz(sheet, 1 + i * 2, satir, gunSabah[i], _toplamStil);
      _yaz(sheet, 2 + i * 2, satir, gunAksam[i], _toplamStil);
      genel += gunSabah[i] + gunAksam[i];
    }
    _yaz(sheet, 1 + gunler.length * 2, satir, genel, _toplamStil);
    return ozet;
  }

  // ─── 🐮 YEM RAPORU ─────────────────────────────────────────────────

  static const _yemBasliklari = [
    'İsim Soyisim', 'Tarih', 'Süt Yemi (kg)', 'Besi Yemi (kg)', 'B. Başlangıç (kg)',
    'B. Büyütme (kg)', 'Kuzu Yemi (kg)', 'Tavuk Yemi (kg)', 'TOPLAM (kg)',
  ];

  static Future<File> exportYemRaporu({
    required List<Cari> cariler,
    required List<Yem> yemler,
    required DateTime startDate,
    required DateTime endDate,
    required String raporAdi,
  }) async {
    try {
      final excel = _yeniKitap('Yem Raporu');
      _yemSayfasi(excel['Yem Raporu'], cariler, yemler, startDate, endDate);
      return await _kaydet(excel, raporAdi);
    } catch (e, st) {
      debugPrint('❌ Yem raporu hatası: $e\n$st');
      rethrow;
    }
  }

  /// Cari (Türkçe alfabetik) → tarih sırasıyla; her carinin altında ara toplam,
  /// en altta her yem türünün genel toplamı.
  static void _yemSayfasi(
      Sheet sheet, List<Cari> cariler, List<Yem> yemler, DateTime startDate, DateTime endDate) {
    final bas = _gunFormat.format(startDate), bit = _gunFormat.format(endDate);
    final secili = yemler.where((y) {
      final g = _gunAnahtari(y.tarih);
      return g.compareTo(bas) >= 0 && g.compareTo(bit) <= 0;
    }).toList(); // kopya: çağıranın listesi değişmez

    final cariYemleri = <int, List<Yem>>{};
    for (final y in secili) {
      cariYemleri.putIfAbsent(y.cariId, () => []).add(y);
    }

    _basliklar(sheet, 0, _yemBasliklari);
    final genel = List<double>.filled(7, 0);
    var satir = 1;
    for (final cari in _carileriTamamla(cariler, cariYemleri.keys)) {
      final liste = cariYemleri[cari.id];
      if (liste == null || liste.isEmpty) continue;
      liste.sort((a, b) => a.tarih.compareTo(b.tarih));
      final ara = List<double>.filled(7, 0);
      for (final y in liste) {
        final d = [y.sutYemi, y.besiYemi, y.bBaslangic, y.bBuyutme, y.kuzuYemi, y.tavukYemi, y.toplam];
        _yaz(sheet, 0, satir, cari.tamAd);
        _yaz(sheet, 1, satir, _tarihYazi(y.tarih));
        for (var i = 0; i < d.length; i++) {
          _yaz(sheet, 2 + i, satir, d[i]);
          ara[i] += d[i];
          genel[i] += d[i];
        }
        satir++;
      }
      if (liste.length > 1) {
        _yaz(sheet, 0, satir, '${cari.tamAd} — toplam', _isimStil);
        for (var i = 0; i < ara.length; i++) {
          _yaz(sheet, 2 + i, satir, ara[i], _isimStil);
        }
        satir++;
      }
    }
    _yaz(sheet, 0, satir, 'GENEL TOPLAM', _toplamStil);
    for (var i = 0; i < genel.length; i++) {
      _yaz(sheet, 2 + i, satir, genel[i], _toplamStil);
    }
  }

  static String _tarihYazi(String tarih) {
    try {
      return DateFormat('dd.MM.yyyy').format(DateTime.parse(tarih));
    } catch (_) {
      return tarih;
    }
  }

  // ─── 🥛+🐮 SÜT VE YEM (tek dosya, iki sayfa) ─────────────────────────

  static Future<File> exportSutVeYemRaporu({
    required List<Cari> cariler,
    required List<Sut> sutler,
    required List<Yem> yemler,
    required DateTime startDate,
    required DateTime endDate,
    required String raporAdi,
  }) async {
    final excel = _yeniKitap('Süt Raporu');
    final toplamlar = _sutSayfasi(excel['Süt Raporu'], cariler, sutler, startDate, endDate);
    _sutToplamSayfasi(excel[sutToplamSayfasi], toplamlar, startDate, endDate);
    _yemSayfasi(excel['Yem Raporu'], cariler, yemler, startDate, endDate);
    return _kaydet(excel, raporAdi);
  }

  // ─── 🧮 AYLIK HESAPLAMA RAPORU (fiyat_hesaplama_ekrani.dart) ─────────

  static Future<File> exportHesaplamaRaporu({
    required List<({Cari cari, AylikCariOzet ozet})> satirlar,
    required String ayAdi,
  }) async {
    try {
      final excel = _yeniKitap('Aylık Hesaplama');
      final sheet = excel['Aylık Hesaplama'];

      // Bakiye işareti: + cari alacaklı (işletme ödeyecek), − cari borçlu.
      const basliklar = [
        'İsim Soyisim', 'Süt (kg)', 'Süt Fiyatı (₺/kg)', 'Süt Tutarı (₺)', 'Yem (kg)',
        'Yem Tutarı (₺)', 'Ödenen (₺)', 'Tahsil Edilen (₺)', 'Bu Ay Net (₺)',
        'Genel Bakiye (₺)', 'Not',
      ];
      _basliklar(sheet, 0, basliklar);

      final toplam = List<double>.filled(basliklar.length, 0);
      var satir = 1;
      for (final s in satirlar) {
        final o = s.ozet;
        final d = <double>[
          o.sutKg, o.sutFiyat, o.sutTutar, o.yemKg, o.yemTutar,
          o.odeme, o.tahsilat, o.ayNet, o.genelBakiye,
        ];
        _yaz(sheet, 0, satir, s.cari.tamAd, _isimStil);
        for (var i = 0; i < d.length; i++) {
          _yaz(sheet, i + 1, satir, d[i]);
          toplam[i + 1] += d[i];
        }
        _yaz(sheet, 10, satir, _not(fiyatEksik: o.fiyatEksik, fiyatDegisti: o.fiyatDegisti));
        satir++;
      }

      _yaz(sheet, 0, satir, 'GENEL TOPLAM', _toplamStil);
      for (var i = 1; i <= 9; i++) {
        if (i == 2) continue; // fiyat toplanmaz
        _yaz(sheet, i, satir, toplam[i], _toplamStil);
      }
      return await _kaydet(excel, 'Hesaplama_$ayAdi');
    } catch (e, st) {
      debugPrint('❌ Hesaplama raporu hatası: $e\n$st');
      rethrow;
    }
  }

  static String _not({required bool fiyatEksik, bool fiyatDegisti = false}) {
    if (fiyatEksik) return 'FİYAT EKSİK — tutar eksik hesaplandı';
    if (fiyatDegisti) return 'Fiyat ay içinde değişti (ortalama)';
    return '';
  }

  // ─── 📋 HAKEDİŞ BORDROSU (dönem kapanışı) ───────────────────────────

  static Future<File> exportHakedisBordrosu({
    required List<({Cari cari, HakedisSatiri satir})> satirlar,
    required String ayAdi,
    required bool kapali,
  }) async {
    final sayfa = 'Hakediş $ayAdi';
    final excel = _yeniKitap(sayfa);
    final sheet = excel[sayfa];

    _yaz(sheet, 0, 0, 'Hakediş Bordrosu — $ayAdi ${kapali ? '(KAPALI DÖNEM)' : '(TASLAK — dönem açık)'}',
        CellStyle(bold: true, fontSize: 13));

    // Bakiye işareti: + üreticiye ödenecek, − üretici borçlu.
    const basliklar = [
      'Üretici', 'Devir (₺)', 'Süt (kg)', 'Süt Fiyatı (₺/kg)', 'Süt Tutarı (₺)',
      'Yem (kg)', 'Yem Tutarı (₺)', 'Ödenen (₺)', 'Tahsil Edilen (₺)', 'Dönem Sonu (₺)', 'Not',
    ];
    _basliklar(sheet, 2, basliklar);

    final toplam = List<double>.filled(basliklar.length, 0);
    var satir = 3;
    for (final r in satirlar) {
      final s = r.satir;
      final d = [s.devir, s.sutKg, s.sutFiyat, s.sutTutar, s.yemKg, s.yemTutar, s.odeme, s.tahsilat, s.donemSonu];
      _yaz(sheet, 0, satir, r.cari.tamAd);
      for (var i = 0; i < d.length; i++) {
        _yaz(sheet, i + 1, satir, d[i]);
        toplam[i + 1] += d[i];
      }
      _yaz(sheet, 10, satir, _not(fiyatEksik: s.fiyatEksik));
      satir++;
    }
    _yaz(sheet, 0, satir, 'TOPLAM', _toplamStil);
    for (var i = 1; i <= 9; i++) {
      if (i == 3) continue; // fiyat toplanmaz
      _yaz(sheet, i, satir, toplam[i], _toplamStil);
    }
    return _kaydet(excel, 'Hakedis_$ayAdi');
  }

  // ─── 📋 CARİ HESAP EKSTRESİ ─────────────────────────────────────────

  /// [hareketler]: {tarih ('yyyy-MM-dd'), islemAdi, kredi(bool), tutar, aciklama}
  /// — sırası önemsiz; Excel'de eskiden yeniye ve yürüyen bakiyeyle yazılır.
  /// [baslangic] / [bitis] doluysa ekstre o tarih aralığıdır: son satır
  /// "DÖNEM NETİ" olur (tüm zamanların bakiyesi DEĞİL).
  static Future<File> exportCariHesapEkstresi({
    required String cariAdi,
    required List<Map<String, dynamic>> hareketler,
    required double toplamSut,
    required double toplamYem,
    required double toplamOdeme,
    required double toplamTahsilat,
    required double kalanBakiye,
    DateTime? baslangic,
    DateTime? bitis,
  }) async {
    try {
      final excel = _yeniKitap('Hesap Ekstresi');
      final sheet = excel['Hesap Ekstresi'];
      final filtreli = baslangic != null || bitis != null;

      _yaz(sheet, 0, 0, 'Cari Hesap Ekstresi — $cariAdi', CellStyle(bold: true, fontSize: 14));
      _yaz(sheet, 0, 1, ekstreDonemYazisi(baslangic, bitis));

      _basliklar(sheet, 3, ['Tarih', 'İşlem', 'Açıklama', 'Alacak (₺)', 'Borç (₺)', 'Bakiye (₺)']);

      final krediStil = CellStyle(fontColorHex: ExcelColor.fromHexString('#0D47A1'));
      final borcStil = CellStyle(fontColorHex: ExcelColor.fromHexString('#E65100'));
      var satir = 4;
      for (final s in ekstreSatirlari(hareketler)) {
        _yaz(sheet, 0, satir, s.tarih);
        _yaz(sheet, 1, satir, s.islemAdi);
        _yaz(sheet, 2, satir, s.aciklama);
        if (s.alacak != null) _yaz(sheet, 3, satir, s.alacak, krediStil);
        if (s.borc != null) _yaz(sheet, 4, satir, s.borc, borcStil);
        _yaz(sheet, 5, satir, s.bakiye);
        satir++;
      }

      satir++;
      final ozet = <(String, double)>[
        ('Toplam Süt (Alacak)', toplamSut),
        ('Toplam Tahsilat (Alacak)', toplamTahsilat),
        ('Toplam Yem (Borç)', toplamYem),
        ('Toplam Ödeme (Borç)', toplamOdeme),
        (filtreli ? '${ekstreBakiyeEtiketi(filtreli: true)} (dönemin net etkisi)' : '${ekstreBakiyeEtiketi(filtreli: false)} (${ekstreDurumu(kalanBakiye)})', kalanBakiye),
      ];
      for (var i = 0; i < ozet.length; i++) {
        final son = i == ozet.length - 1;
        _yaz(sheet, 0, satir, ozet[i].$1, son ? _toplamStil : null);
        _yaz(sheet, 5, satir, ozet[i].$2, son ? _toplamStil : null);
        satir++;
      }
      if (filtreli) _yaz(sheet, 0, satir, ekstreDonemNotu);

      return await _kaydet(excel, 'Hesap_Ekstresi_$cariAdi');
    } catch (e, st) {
      debugPrint('❌ Hesap ekstresi export hatası: $e\n$st');
      rethrow;
    }
  }

  // ─── 📤 PAYLAŞ ───────────────────────────────────────────────────────

  static Future<void> shareFile(File file) async {
    if (!await file.exists()) throw Exception('Paylaşılacak dosya bulunamadı');
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Süt Yem Takip Raporu',
      text: 'Süt Yem Takip Sistemi tarafından oluşturulan rapor',
    );
  }
}
