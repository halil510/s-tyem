import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/cari/providers/cari_providers.dart';
import '../utils/turkce.dart';
import '../features/donem/donem_kapali_bandi.dart';
import 'package:intl/intl.dart';

import '../models/cari_model.dart';
import '../models/yem_model.dart';
import '../utils/tarih_secici.dart';
import '../core/providers/repository_providers.dart';
import '../core/providers/veri_surumu_provider.dart';
import '../utils/sayi_format.dart';
import '../widgetlar/kaydedilmemis_koruma.dart';

/// Yem girişi sekmesi — cari listesi + arama.
///
/// Faz 1 modernizasyonu: `DBHelper` yerine `cariRepositoryProvider`
/// kullanıyor.
class YemEkrani extends ConsumerStatefulWidget {
  const YemEkrani({super.key});

  @override
  ConsumerState<YemEkrani> createState() => _YemEkraniState();
}

class _YemEkraniState extends ConsumerState<YemEkrani> {
  String _aramaMetni = '';
  final TextEditingController _aramaCtrl = TextEditingController();

  @override
  void dispose() {
    _aramaCtrl.dispose();
    super.dispose();
  }

  List<Cari> _filtreUygula(List<Cari> hepsi) {
    return hepsi.where((c) => aramaEslesir(c.tamAd, _aramaMetni)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final carilerAsync = ref.watch(aktifCarilerProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FFF8),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: TextField(
                controller: _aramaCtrl,
                decoration: InputDecoration(
                  hintText: 'Cari ara...',
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  suffixIcon: _aramaMetni.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear, color: Colors.grey), onPressed: () { _aramaCtrl.clear(); setState(() => _aramaMetni = ''); })
                      : null,
                ),
                onChanged: (v) => setState(() => _aramaMetni = v),
              ),
            ),
          ),
          Expanded(
            child: carilerAsync.when(
              data: (cariler) {
                  final filtrelenen = _filtreUygula(cariler);
                  if (filtrelenen.isEmpty) {
                    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.grass, size: 72, color: Colors.green[200]),
                      const SizedBox(height: 16),
                      Text(cariler.isEmpty ? 'Henüz cari kaydı yok' : 'Cari bulunamadı', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                    ]));
                  }
                  return RefreshIndicator(
                    onRefresh: () async => ref.invalidate(aktifCarilerProvider),
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: filtrelenen.length,
                      itemBuilder: (ctx, i) => _CariKarti(
                        cari: filtrelenen[i],
                        onKaydedildi: () => ref.invalidate(aktifCarilerProvider),
                      ),
                    ),
                  );
                },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Hata: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

class _CariKarti extends StatelessWidget {
  final Cari cari;
  final VoidCallback onKaydedildi;
  const _CariKarti({required this.cari, required this.onKaydedildi});

  Future<void> _girisSayfasinaGit(BuildContext context) async {
    final r = await Navigator.push(context, MaterialPageRoute(builder: (_) => YemGirisPage(cari: cari)));
    if (r == true) onKaydedildi();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      // ListTile dokunma efekti en yakın Material'a çizilir; renkli Container
      // onu gizliyordu (dokunduğunu görmüyordun, debug'da hata).
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48, height: 48,
          decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(12)),
          child: Icon(Icons.grass, color: Colors.green[700], size: 22),
        ),
        title: Text(cari.tamAd, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        subtitle: Text(cari.hayvanTuru ?? 'Belirtilmemiş', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        trailing: ElevatedButton(
          onPressed: () => _girisSayfasinaGit(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green[700],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
          child: const Text('Yem Ekle', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        onTap: () => _girisSayfasinaGit(context),
      ),
      ),
    );
  }
}

// ==================== YEM GİRİŞ SAYFASI ====================

class YemGirisPage extends ConsumerStatefulWidget {
  final Cari cari;
  const YemGirisPage({required this.cari, super.key});

  @override
  ConsumerState<YemGirisPage> createState() => _YemGirisPageState();
}

class _YemGirisPageState extends ConsumerState<YemGirisPage> {
  final _sutCtrl = TextEditingController();
  final _besiCtrl = TextEditingController();
  final _bBasCtrl = TextEditingController();
  final _bBuyCtrl = TextEditingController();
  final _kuzuCtrl = TextEditingController();
  final _tavukCtrl = TextEditingController();
  DateTime _tarih = DateTime.now();
  bool _kaydediliyor = false;

  double _parse(String s) => sayiCoz(s) ?? 0;

  List<TextEditingController> get _alanlar => [_sutCtrl, _besiCtrl, _bBasCtrl, _bBuyCtrl, _kuzuCtrl, _tavukCtrl];

  /// Hatalı yazılmış bir alan varsa kayıt yapılmaz (sessizce 0 kg sayılmasın).
  bool get _gecersizAlanVar => _alanlar.any((c) => sayiCoz(c.text) == null);

  double get _toplam => _parse(_sutCtrl.text) + _parse(_besiCtrl.text) + _parse(_bBasCtrl.text) + _parse(_bBuyCtrl.text) + _parse(_kuzuCtrl.text) + _parse(_tavukCtrl.text);

  Future<void> _kaydet() async {
    if (_gecersizAlanVar) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geçersiz miktar var, lütfen kontrol edin'), backgroundColor: Colors.red),
      );
      return;
    }
    if (_toplam == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('En az bir yem türü giriniz'), backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      );
      return;
    }
    setState(() => _kaydediliyor = true);
    try {
      final repo = await ref.read(yemRepositoryProvider.future);
      await repo.insert(Yem(
        cariId: widget.cari.id!,
        tarih: DateFormat('yyyy-MM-dd').format(_tarih),
        sutYemi: _parse(_sutCtrl.text),
        besiYemi: _parse(_besiCtrl.text),
        bBaslangic: _parse(_bBasCtrl.text),
        bBuyutme: _parse(_bBuyCtrl.text),
        kuzuYemi: _parse(_kuzuCtrl.text),
        tavukYemi: _parse(_tavukCtrl.text),
      ));
      ref.veriDegisti();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Yem kaydı başarıyla eklendi'),
        backgroundColor: Colors.green[700],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _kaydediliyor = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e'), backgroundColor: Colors.red));
    }
  }

  Widget _alanOlustur(TextEditingController ctrl, String etiket, IconData ikon, Color renk) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        decoration: InputDecoration(
          labelText: '$etiket (kg)',
          prefixIcon: Icon(ikon, color: renk, size: 20),
          hintText: '0.0',
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  late final _alanDinleyici = Listenable.merge(_alanlar);

  /// Bir alana miktar yazılmış (ya da hatalı yazılmış) ama kaydedilmemiş.
  bool get _kaydedilmemisVar => !_kaydediliyor && _alanlar.any((c) => sayiCoz(c.text) != 0);

  @override
  Widget build(BuildContext context) {
    return KaydedilmemisKoruma(
      dinle: _alanDinleyici,
      degisiklikVar: () => _kaydedilmemisVar,
      kaydet: _kaydet,
      baslik: 'Yem kaydedilmedi',
      child: _ekran(context),
    );
  }

  Widget _ekran(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FFF8),
      appBar: AppBar(
        title: Text(widget.cari.tamAd, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1B5E20),
        elevation: 0,
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Container(height: 1, color: Colors.grey.withOpacity(0.1))),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))]),
              child: Row(
                children: [
                  Container(width: 50, height: 50, decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(12)), child: Icon(Icons.person, color: Colors.green[700], size: 24)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.cari.tamAd, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(widget.cari.hayvanTuru ?? '', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                  ])),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)]),
              child: TarihSecici(
                baslangicTarihi: _tarih,
                showRange: false,
                sonTarih: DateUtils.dateOnly(DateTime.now()),
                onTarihSecildi: (bas, _) => setState(() => _tarih = bas),
              ),
            ),
            const SizedBox(height: 14),
            DonemKapaliBandi(tarih: _tarih),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))]),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.grass, color: Colors.green[700], size: 18),
                    const SizedBox(width: 8),
                    const Text('Yem Türleri', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const Spacer(),
                    if (_toplam > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(8)),
                        child: Text('Toplam: ${sayiGoster(_toplam)} kg', style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                  ]),
                  const SizedBox(height: 16),
                  _alanOlustur(_sutCtrl, 'Süt Yemi', Icons.water_drop, Colors.blue),
                  _alanOlustur(_besiCtrl, 'Besi Yemi', Icons.agriculture, Colors.brown),
                  _alanOlustur(_bBasCtrl, 'B. Başlangıç', Icons.start, Colors.purple),
                  _alanOlustur(_bBuyCtrl, 'B. Büyütme', Icons.trending_up, Colors.indigo),
                  _alanOlustur(_kuzuCtrl, 'Kuzu Yemi', Icons.pets, Colors.orange),
                  _alanOlustur(_tavukCtrl, 'Tavuk Yemi', Icons.egg, Colors.amber),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _kaydediliyor ? null : _kaydet,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                icon: _kaydediliyor
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.check_circle),
                label: Text(_kaydediliyor ? 'Kaydediliyor...' : 'KAYDET', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
