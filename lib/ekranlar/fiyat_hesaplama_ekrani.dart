import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/repositories/cari_repository.dart' show cariSirala;
import 'package:intl/intl.dart';
import '../models/cari_model.dart';
import '../services/whatsapp_service.dart';
import '../utils/app_theme.dart';
import '../utils/excel_export.dart';
import '../utils/sayi_format.dart';
import '../core/providers/repository_providers.dart';
import '../features/cari_hesap/providers/cari_hesap_providers.dart'
    show AylikCariOzet, aylikOzetProvider;

/// Aylık Hesaplama & Rapor.
///
/// Tutarlar her carinin O AYKİ gerçek fiyatıyla, bakiye ve ekstreyle
/// aynı fonksiyonlardan ([aylikOzetProvider]) gelir. Ekranda elle fiyat
/// girilmez: eskiden burada sabit 12 ₺ / 8 ₺ ile hesaplanıp müşteriye
/// WhatsApp'tan yanlış tutar gidiyordu.
class FiyatHesaplamaEkrani extends ConsumerStatefulWidget {
  const FiyatHesaplamaEkrani({super.key});

  @override
  ConsumerState<FiyatHesaplamaEkrani> createState() => _FiyatHesaplamaEkraniState();
}

final _carilerHepsiProvider = FutureProvider.autoDispose<List<Cari>>((ref) async {
  final repo = await ref.watch(cariRepositoryProvider.future);
  return repo.getAll(sadeceAktif: false);
});

typedef _Satir = ({Cari cari, AylikCariOzet ozet});

class _FiyatHesaplamaEkraniState extends ConsumerState<FiyatHesaplamaEkrani> {
  DateTime _ay = DateTime(DateTime.now().year, DateTime.now().month);
  bool _islem = false;

  String get _ayAnahtari => DateFormat('yyyy-MM').format(_ay);
  String get _ayAdi => DateFormat('MMMM yyyy', 'tr_TR').format(_ay);
  bool get _buAyMi {
    final n = DateTime.now();
    return _ay.year == n.year && _ay.month == n.month;
  }

  void _ayDegistir(int fark) => setState(() => _ay = DateTime(_ay.year, _ay.month + fark));

  List<_Satir> _satirlar(List<Cari> cariler, Map<int, AylikCariOzet> ozet) {
    final liste = <_Satir>[
      for (final c in cariler)
        if (c.id != null && ozet[c.id!] != null) (cari: c, ozet: ozet[c.id!]!),
    ];
    liste.sort((a, b) => cariSirala(a.cari, b.cari));
    return liste;
  }

  Future<void> _excelOlustur(List<_Satir> satirlar) async {
    setState(() => _islem = true);
    try {
      final file = await ExcelExport.exportHesaplamaRaporu(
        satirlar: satirlar,
        ayAdi: DateFormat('MMMM_yyyy', 'tr_TR').format(_ay),
      );
      await ExcelExport.shareFile(file);
      if (mounted) _snack('Excel hazırlandı ✓');
    } catch (e) {
      if (mounted) _snack('Hata: $e', hata: true);
    } finally {
      if (mounted) setState(() => _islem = false);
    }
  }

  String? _telefon(Cari cari) {
    final ham = cari.telefon?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
    if (ham.isEmpty) return null;
    if (ham.startsWith('0')) return '90${ham.substring(1)}';
    if (ham.length == 10) return '90$ham';
    return ham;
  }

  Future<bool> _whatsappGonder(_Satir s, {bool sessiz = false}) async {
    final tel = _telefon(s.cari);
    if (tel == null) {
      if (!sessiz) _snack('Telefon numarası yok', hata: true);
      return false;
    }
    final o = s.ozet;
    final msg = WhatsAppService.createHesapOzetiMessage(
      cariAd: '${s.cari.ad} ${s.cari.soyad}',
      ayAdi: _ayAdi,
      sutKg: o.sutKg,
      sutFiyat: o.sutFiyat,
      fiyatDegisti: o.fiyatDegisti,
      sutTutar: o.sutTutar,
      yemKg: o.yemKg,
      yemTutar: o.yemTutar,
      odeme: o.odeme,
      tahsilat: o.tahsilat,
      kalanBorc: o.genelBakiye,
    );
    final ok = await WhatsAppService.sendToWhatsApp(tel, msg);
    if (mounted && !sessiz) _snack(ok ? '${s.cari.ad} — Gönderildi ✓' : 'Gönderilemedi', hata: !ok);
    return ok;
  }

  Future<void> _tumunuGonder(List<_Satir> satirlar) async {
    final telli = satirlar.where((s) => _telefon(s.cari) != null).toList();
    final eksikFiyat = satirlar.where((s) => s.ozet.fiyatEksik).length;
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tümüne WhatsApp'),
        content: Text(
          '$_ayAdi hesap özeti ${telli.length} cariye gönderilecek.'
          '${satirlar.length - telli.length > 0 ? '\n${satirlar.length - telli.length} carinin telefonu yok.' : ''}'
          '${eksikFiyat > 0 ? '\n\n⚠️ $eksikFiyat carinin bu ay fiyatı tanımlı değil; tutarları 0 görünecek.' : ''}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Gönder')),
        ],
      ),
    );
    if (onay != true || !mounted) return;

    setState(() => _islem = true);
    var gonderilen = 0;
    for (final s in telli) {
      if (!mounted) return;
      if (await _whatsappGonder(s, sessiz: true)) gonderilen++;
      await Future.delayed(const Duration(seconds: 3));
    }
    if (mounted) {
      setState(() => _islem = false);
      _snack('$gonderilen / ${telli.length} gönderildi');
    }
  }

  void _snack(String m, {bool hata = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m, style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: hata ? AppRenkler.hata : AppRenkler.basari,
        behavior: SnackBarBehavior.floating,
      ));

  @override
  Widget build(BuildContext context) {
    final cariler = ref.watch(_carilerHepsiProvider);
    final ozet = ref.watch(aylikOzetProvider(_ayAnahtari));

    final hata = cariler.error ?? ozet.error;
    final hazir = cariler.hasValue && ozet.hasValue;
    final satirlar = hazir ? _satirlar(cariler.value!, ozet.value!) : const <_Satir>[];

    return Scaffold(
      backgroundColor: AppRenkler.arkaplan,
      appBar: AppBar(
        title: const Text('Aylık Hesaplama & Rapor'),
        actions: [
          if (_islem)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppRenkler.birincil))))
          else if (satirlar.isNotEmpty) ...[
            IconButton(
                icon: const Icon(Icons.file_download_outlined),
                tooltip: 'Excel',
                onPressed: () => _excelOlustur(satirlar)),
            IconButton(
                icon: const Icon(Icons.send_rounded, color: Color(0xFF25D366)),
                tooltip: 'Tümüne WhatsApp',
                onPressed: () => _tumunuGonder(satirlar)),
          ],
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _ayKutusu(),
        const SizedBox(height: 12),
        if (hata != null)
          _bilgi(Icons.error_outline, 'Hesaplanamadı: $hata', AppRenkler.hata)
        else if (!hazir)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator(color: AppRenkler.birincil)),
          )
        else if (satirlar.isEmpty)
          _bilgi(Icons.inbox_outlined, '$_ayAdi için hareket yok.', AppRenkler.metinIkincil)
        else ...[
          _genelOzet(satirlar),
          if (satirlar.any((s) => s.ozet.fiyatEksik)) ...[
            const SizedBox(height: 12),
            _bilgi(
              Icons.warning_amber_rounded,
              '${satirlar.where((s) => s.ozet.fiyatEksik).length} carinin bu ay fiyatı tanımlı değil; '
              'tutarları 0 hesaplandı. Menü → Süt / Yem Fiyatları ekranından fiyat girin.',
              Colors.orange.shade800,
            ),
          ],
          const SizedBox(height: 12),
          ...satirlar.map(_cariKarti),
        ],
      ]),
    );
  }

  Widget _ayKutusu() => _box(
        child: Row(children: [
          IconButton(
              icon: const Icon(Icons.chevron_left_rounded, color: AppRenkler.birincil),
              tooltip: 'Önceki ay',
              onPressed: () => _ayDegistir(-1)),
          Expanded(
              child: Center(
                  child: Text(_ayAdi,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600, fontFamily: 'Poppins')))),
          IconButton(
              icon: const Icon(Icons.chevron_right_rounded, color: AppRenkler.birincil),
              tooltip: 'Sonraki ay',
              onPressed: _buAyMi ? null : () => _ayDegistir(1)),
        ]),
      );

  Widget _genelOzet(List<_Satir> satirlar) {
    double topla(double Function(AylikCariOzet) f) => satirlar.fold(0.0, (t, s) => t + f(s.ozet));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF1565C0), Color(0xFF1976D2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        _ozKpi('${sayiGoster(topla((o) => o.sutKg))} kg', 'Süt'),
        _div(),
        _ozKpi('${sayiGoster(topla((o) => o.yemKg))} kg', 'Yem'),
        _div(),
        _ozKpi('${topla((o) => o.ayNet).toStringAsFixed(0)} ₺', 'Bu Ay Net'),
        _div(),
        _ozKpi('${topla((o) => o.genelBakiye).toStringAsFixed(0)} ₺', 'Genel Bakiye'),
      ]),
    );
  }

  Widget _cariKarti(_Satir s) {
    final o = s.ozet;
    final kalan = o.genelBakiye;
    final kapali = kalan.abs() < 0.005;
    final durumRenk =
        kapali ? AppRenkler.basari : (kalan > 0 ? AppRenkler.bilgi : const Color(0xFFE65100));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppRenkler.yuzey,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: o.fiyatEksik
                ? Colors.orange.shade300
                : (kapali ? AppRenkler.basari.withValues(alpha: 0.35) : AppRenkler.sinir)),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration:
                  BoxDecoration(color: AppRenkler.birincilCok, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.person, color: AppRenkler.birincil, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${s.cari.ad} ${s.cari.soyad}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Poppins')),
              Text(
                o.sutKg > 0
                    ? '${sayiGoster(o.sutKg)} kg × ${o.fiyatDegisti ? 'ort. ' : ''}${o.sutFiyat.toStringAsFixed(2)} ₺'
                    : (s.cari.telefon ?? ''),
                style: const TextStyle(
                    fontSize: 11, color: AppRenkler.metinUcuncul, fontFamily: 'Poppins'),
              ),
              if (o.fiyatEksik)
                Text('Bu ay fiyat tanımlı değil',
                    style: TextStyle(
                        fontSize: 11, color: Colors.orange.shade800, fontFamily: 'Poppins')),
            ])),
            IconButton(
              onPressed: _islem ? null : () => _whatsappGonder(s),
              icon: const Icon(Icons.chat_rounded, color: Color(0xFF25D366), size: 22),
              tooltip: 'WhatsApp Gönder',
            ),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            color: AppRenkler.yuzeyVar,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
          ),
          child: Row(children: [
            _deger(Icons.water_drop, 'Süt', '${o.sutTutar.toStringAsFixed(2)} ₺', AppRenkler.birincil),
            _div2(),
            _deger(Icons.grass, '${sayiGoster(o.yemKg)} kg yem',
                '${o.yemTutar.toStringAsFixed(2)} ₺', const Color(0xFF2E7D32)),
            _div2(),
            _deger(Icons.summarize, 'Bu ay net', '${o.ayNet.toStringAsFixed(2)} ₺', AppRenkler.bilgi),
            _div2(),
            _deger(
              kapali
                  ? Icons.check_circle_rounded
                  : (kalan > 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded),
              kapali ? 'Kapalı' : (kalan > 0 ? 'Alacaklı' : 'Borçlu'),
              '${kalan.abs().toStringAsFixed(2)} ₺',
              durumRenk,
            ),
          ]),
        ),
      ]),
    );
  }

  // ─── Yardımcı widgetlar ────────────────────────────────────────────
  Widget _bilgi(IconData ikon, String metin, Color renk) => _box(
        child: Row(children: [
          Icon(ikon, color: renk),
          const SizedBox(width: 10),
          Expanded(
              child: Text(metin, style: TextStyle(color: renk, fontFamily: 'Poppins', fontSize: 13))),
        ]),
      );

  Widget _box({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: AppRenkler.yuzey,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppRenkler.sinir)),
        child: child,
      );

  Widget _ozKpi(String d, String e) => Expanded(
          child: Column(children: [
        Text(d,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white, fontFamily: 'Poppins'),
            textAlign: TextAlign.center),
        Text(e,
            style: TextStyle(
                fontSize: 10, color: Colors.white.withValues(alpha: 0.75), fontFamily: 'Poppins'),
            textAlign: TextAlign.center),
      ]));

  Widget _div() => Container(
      width: 1,
      height: 32,
      color: Colors.white.withValues(alpha: 0.25),
      margin: const EdgeInsets.symmetric(horizontal: 4));
  Widget _div2() => Container(
      width: 1, height: 32, color: AppRenkler.sinir, margin: const EdgeInsets.symmetric(horizontal: 4));

  Widget _deger(IconData ikon, String alt, String deger, Color renk) => Expanded(
          child: Column(children: [
        Icon(ikon, color: renk, size: 16),
        Text(alt,
            style: TextStyle(fontSize: 10, color: renk, fontFamily: 'Poppins'),
            textAlign: TextAlign.center),
        Text(deger,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: renk, fontFamily: 'Poppins'),
            textAlign: TextAlign.center),
      ]));
}
