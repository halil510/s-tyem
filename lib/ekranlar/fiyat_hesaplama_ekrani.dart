import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/cari_model.dart';
import '../services/whatsapp_service.dart';
import '../utils/app_theme.dart';
import '../utils/excel_export.dart';
import '../data/repositories/cari_repository.dart';
import '../data/repositories/sut_repository.dart';
import '../data/repositories/yem_repository.dart';
import '../core/providers/repository_providers.dart';
import '../features/cari_hesap/providers/cari_hesap_providers.dart' show tumKalanBorclarProvider;

class FiyatHesaplamaEkrani extends ConsumerStatefulWidget {
  const FiyatHesaplamaEkrani({super.key});
  @override
  ConsumerState<FiyatHesaplamaEkrani> createState() => _FiyatHesaplamaEkraniState();
}

class _FiyatHesaplamaEkraniState extends ConsumerState<FiyatHesaplamaEkrani> {
  late CariRepository _cariRepo;
  late SutRepository _sutRepo;
  late YemRepository _yemRepo;
  List<Cari> _cariler = [];
  bool _yukleniyor = true, _islem = false;
  DateTime _ay = DateTime.now();
  double _sutFiyat = 12.0, _yemFiyat = 8.0;
  // hesaplar[cariId] = { sutKg, yemKg, sutTutar, yemTutar, toplamBorc, toplamOdenen, kalanBorc }
  Map<int, Map<String, double>> _hesaplar = {};

  @override
  void initState() { super.initState(); _yukle(); }

  Future<void> _yukle() async {
    setState(() => _yukleniyor = true);
    try {
      _cariRepo = await ref.read(cariRepositoryProvider.future);
      _sutRepo = await ref.read(sutRepositoryProvider.future);
      _yemRepo = await ref.read(yemRepositoryProvider.future);
      _cariler = await _cariRepo.getAll(sadeceAktif: true);
      final ayIlk = DateTime(_ay.year, _ay.month, 1);
      final aySon = DateTime(_ay.year, _ay.month + 1, 0);
      final bas = DateFormat('yyyy-MM-dd').format(ayIlk);
      final bit = DateFormat('yyyy-MM-dd').format(aySon);

      // Genel (tüm zamanlar) canlı bakiye — Ödemeler sekmesi ve
      // Dashboard ile AYNI kaynaktan, tutarlı rakam için. Bkz.
      // `lib/features/cari_hesap/providers/cari_hesap_providers.dart`.
      final canliBakiyeler = await ref.read(tumKalanBorclarProvider.future);

      _hesaplar = {};
      for (var c in _cariler) {
        if (c.id == null) continue;
        final sutler = await _sutRepo.getByCari(c.id!, bas, bit);
        final yemler = await _yemRepo.getByCari(c.id!, bas, bit);
        final sutKg  = sutler.fold(0.0, (s, e) => s + e.toplam);
        final yemKg  = yemler.fold(0.0, (s, e) => s + e.toplam);
        final bakiye = canliBakiyeler[c.id!] ?? 0.0;
        _hesaplar[c.id!] = {
          'sutKg': sutKg, 'yemKg': yemKg,
          'sutTutar': sutKg * _sutFiyat, 'yemTutar': yemKg * _yemFiyat,
          'toplamBorc': bakiye > 0 ? bakiye : 0,
          'toplamOdenen': bakiye < 0 ? -bakiye : 0,
          'kalanBorc': bakiye,
        };
      }
    } catch (e) { debugPrint('Fiyat yukle: $e'); }
    finally { if (mounted) setState(() => _yukleniyor = false); }
  }

  void _fiyatGuncelle() {
    setState(() {
      for (var id in _hesaplar.keys) {
        final h = _hesaplar[id]!;
        _hesaplar[id] = {
          'sutKg': h['sutKg']!, 'yemKg': h['yemKg']!,
          'sutTutar': h['sutKg']! * _sutFiyat,
          'yemTutar': h['yemKg']! * _yemFiyat,
          'toplamBorc': h['toplamBorc']!, 'toplamOdenen': h['toplamOdenen']!,
          'kalanBorc': h['toplamBorc']! - h['toplamOdenen']!,
        };
      }
    });
  }

  Future<void> _excelOlustur() async {
    setState(() => _islem = true);
    try {
      final ayAdi = DateFormat('MMMM_yyyy', 'tr_TR').format(_ay);
      final file = await ExcelExport.exportHesaplamaRaporu(
        cariler: _cariler,
        hesaplar: _hesaplar,
        sutFiyat: _sutFiyat,
        yemFiyat: _yemFiyat,
        ayAdi: ayAdi,
      );
      await ExcelExport.shareFile(file);
      if (mounted) _snack('Excel hazırlandı ✓');
    } catch (e) { if (mounted) _snack('Hata: $e', hata: true); }
    finally { if (mounted) setState(() => _islem = false); }
  }

  Future<void> _whatsappGonder(Cari cari) async {
    final h = _hesaplar[cari.id!];
    if (h == null) return;
    if (cari.telefon == null || cari.telefon!.isEmpty) {
      _snack('Telefon numarası yok', hata: true); return;
    }
    String tel = cari.telefon!.replaceAll(RegExp(r'[^0-9]'), '');
    if (tel.startsWith('0')) {
      tel = '90${tel.substring(1)}';
    } else if (tel.length == 10) tel = '90$tel';

    final ayAdi = DateFormat('MMMM yyyy', 'tr_TR').format(_ay);
    final msg = WhatsAppService.createHesapOzetiMessage(
      cariAd: '${cari.ad} ${cari.soyad}', ayAdi: ayAdi,
      sutKg: h['sutKg']!, sutFiyat: _sutFiyat, sutTutar: h['sutTutar']!,
      yemKg: h['yemKg']!, yemFiyat: _yemFiyat, yemTutar: h['yemTutar']!,
      kalanBorc: h['kalanBorc']!,
    );
    final ok = await WhatsAppService.sendToWhatsApp(tel, msg);
    if (mounted) _snack(ok ? '${cari.ad} — Gönderildi ✓' : 'Hata', hata: !ok);
  }

  Future<void> _tumunuGonder() async {
    setState(() => _islem = true);
    int gonder = 0, telYok = 0;
    for (var c in _cariler) {
      if (c.telefon == null || c.telefon!.isEmpty) { telYok++; continue; }
      await _whatsappGonder(c);
      await Future.delayed(const Duration(seconds: 3));
      gonder++;
    }
    if (mounted) {
      setState(() => _islem = false);
      _snack('$gonder gönderildi${telYok > 0 ? ', $telYok telefon yok' : ''}');
    }
  }

  void _snack(String m, {bool hata = false}) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m, style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: hata ? AppRenkler.hata : AppRenkler.basari,
      behavior: SnackBarBehavior.floating,
    ));

  double get _genelSutKg  => _hesaplar.values.fold(0.0, (s, h) => s + (h['sutKg']  ?? 0));
  double get _genelYemKg  => _hesaplar.values.fold(0.0, (s, h) => s + (h['yemKg']  ?? 0));
  double get _genelTutar  => _hesaplar.values.fold(0.0, (s, h) => s + (h['sutTutar']! + h['yemTutar']!));
  double get _genelKalan  => _hesaplar.values.fold(0.0, (s, h) => s + (h['kalanBorc'] ?? 0));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppRenkler.arkaplan,
      appBar: AppBar(
        title: const Text('Hesaplama & Fiyatlar'),
        actions: [
          if (_islem)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(child: SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppRenkler.birincil))))
          else ...[
            IconButton(icon: const Icon(Icons.file_download_outlined), tooltip: 'Excel', onPressed: _excelOlustur),
            IconButton(icon: const Icon(Icons.send_rounded, color: Color(0xFF25D366)), tooltip: 'Tümüne WhatsApp', onPressed: _tumunuGonder),
          ],
        ],
      ),
      body: _yukleniyor
        ? const Center(child: CircularProgressIndicator(color: AppRenkler.birincil))
        : ListView(padding: const EdgeInsets.all(16), children: [
            // ─── Ay + Fiyat ──────────────────────────────────────────
            _box(child: Column(children: [
              Row(children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded, color: AppRenkler.birincil),
                  onPressed: () { setState(() => _ay = DateTime(_ay.year, _ay.month - 1)); _yukle(); }),
                Expanded(child: Center(child: Text(
                  DateFormat('MMMM yyyy', 'tr_TR').format(_ay),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, fontFamily: 'Poppins')))),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded, color: AppRenkler.birincil),
                  onPressed: () { setState(() => _ay = DateTime(_ay.year, _ay.month + 1)); _yukle(); }),
              ]),
              const Divider(height: 16),
              Row(children: [
                Expanded(child: _fiyatKutu('Süt Alış Fiyatı', _sutFiyat, AppRenkler.birincil, Icons.water_drop,
                  (v) { setState(() => _sutFiyat = v); _fiyatGuncelle(); })),
                const SizedBox(width: 12),
                Expanded(child: _fiyatKutu('Yem Satış Fiyatı', _yemFiyat, const Color(0xFF2E7D32), Icons.grass,
                  (v) { setState(() => _yemFiyat = v); _fiyatGuncelle(); })),
              ]),
            ])),
            const SizedBox(height: 12),

            // ─── Genel özet ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1565C0), Color(0xFF1976D2)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                _ozKpi('${_genelSutKg.toStringAsFixed(0)} kg', 'Süt'),
                _div(),
                _ozKpi('${_genelYemKg.toStringAsFixed(0)} kg', 'Yem'),
                _div(),
                _ozKpi('${_genelTutar.toStringAsFixed(0)} ₺', 'Toplam'),
                _div(),
                _ozKpi('${_genelKalan.toStringAsFixed(0)} ₺', 'Net Bakiye'),
              ]),
            ),
            const SizedBox(height: 12),

            // ─── Cari listesi ─────────────────────────────────────────
            ..._cariler.where((c) => c.id != null).map((c) {
              final h = _hesaplar[c.id!];
              if (h == null) return const SizedBox.shrink();
              final sutKg    = h['sutKg']!;
              final yemKg    = h['yemKg']!;
              final sutTutar = h['sutTutar']!;
              final yemTutar = h['yemTutar']!;
              final kalan    = h['kalanBorc']!;
              final toplam   = sutTutar + yemTutar;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: AppRenkler.yuzey,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: kalan.abs() <= 0.01 ? AppRenkler.basari.withOpacity(0.35) : AppRenkler.sinir),
                ),
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
                    child: Row(children: [
                      Container(
                        width: 38, height: 38,
                        decoration: BoxDecoration(color: AppRenkler.birincilCok, borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.person, color: AppRenkler.birincil, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${c.ad} ${c.soyad}',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Poppins')),
                        if (c.telefon != null)
                          Text(c.telefon!,
                            style: const TextStyle(fontSize: 11, color: AppRenkler.metinUcuncul, fontFamily: 'Poppins')),
                      ])),
                      IconButton(
                        onPressed: () => _whatsappGonder(c),
                        icon: const Icon(Icons.chat_rounded, color: Color(0xFF25D366), size: 22),
                        tooltip: 'WhatsApp Gönder',
                      ),
                    ]),
                  ),
                  // Alt değer şeridi
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: const BoxDecoration(
                      color: AppRenkler.yuzeyVar,
                      borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
                    ),
                    child: Row(children: [
                      _deger(Icons.water_drop, '${sutKg.toStringAsFixed(1)} kg',
                        '${sutTutar.toStringAsFixed(2)} ₺', AppRenkler.birincil),
                      _div2(),
                      _deger(Icons.grass, '${yemKg.toStringAsFixed(1)} kg',
                        '${yemTutar.toStringAsFixed(2)} ₺', const Color(0xFF2E7D32)),
                      _div2(),
                      _deger(Icons.summarize, 'Toplam',
                        '${toplam.toStringAsFixed(2)} ₺', AppRenkler.bilgi),
                      _div2(),
                      _deger(
                        kalan.abs() <= 0.01
                            ? Icons.check_circle_rounded
                            : (kalan > 0.01 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded),
                        kalan.abs() <= 0.01 ? 'Kapalı' : (kalan > 0.01 ? 'Alacaklı' : 'Borçlu'),
                        '${kalan.abs().toStringAsFixed(2)} ₺',
                        kalan.abs() <= 0.01 ? AppRenkler.basari : (kalan > 0.01 ? AppRenkler.bilgi : const Color(0xFFE65100)),
                      ),
                    ]),
                  ),
                ]),
              );
            }),
          ]),
    );
  }

  // ─── Yardımcı widgetlar ────────────────────────────────────────────
  Widget _fiyatKutu(String etiket, double fiyat, Color renk, IconData ikon, Function(double) onDegis) {
    final ctrl = TextEditingController(text: fiyat.toStringAsFixed(2));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(ikon, size: 14, color: renk),
        const SizedBox(width: 4),
        Expanded(child: Text(etiket, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
          color: AppRenkler.metinIkincil, fontFamily: 'Poppins'), overflow: TextOverflow.ellipsis)),
      ]),
      const SizedBox(height: 6),
      TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: TextStyle(fontWeight: FontWeight.w700, color: renk, fontFamily: 'Poppins'),
        onSubmitted: (v) { final val = double.tryParse(v.replaceAll(',', '.')); if (val != null && val > 0) onDegis(val); },
        onEditingComplete: () { final val = double.tryParse(ctrl.text.replaceAll(',', '.')); if (val != null && val > 0) onDegis(val); },
        decoration: InputDecoration(
          suffixText: '₺/kg',
          suffixStyle: TextStyle(color: renk, fontFamily: 'Poppins', fontSize: 12),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          filled: true,
          fillColor: renk.withOpacity(0.07),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: renk.withOpacity(0.3))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: renk, width: 2)),
          border: InputBorder.none,
        ),
      ),
    ]);
  }

  Widget _box({required Widget child}) => Container(
    width: double.infinity, padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: AppRenkler.yuzey, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppRenkler.sinir)),
    child: child,
  );

  Widget _ozKpi(String d, String e) => Expanded(child: Column(children: [
    Text(d, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white,
      fontFamily: 'Poppins'), textAlign: TextAlign.center),
    Text(e, style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.75), fontFamily: 'Poppins')),
  ]));

  Widget _div() => Container(width: 1, height: 32, color: Colors.white.withOpacity(0.25),
    margin: const EdgeInsets.symmetric(horizontal: 4));
  Widget _div2() => Container(width: 1, height: 32, color: AppRenkler.sinir,
    margin: const EdgeInsets.symmetric(horizontal: 4));

  Widget _deger(IconData ikon, String alt, String deger, Color renk) => Expanded(child: Column(children: [
    Icon(ikon, color: renk, size: 16),
    Text(alt, style: TextStyle(fontSize: 10, color: renk, fontFamily: 'Poppins'), textAlign: TextAlign.center),
    Text(deger, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: renk, fontFamily: 'Poppins'),
      textAlign: TextAlign.center),
  ]));
}
