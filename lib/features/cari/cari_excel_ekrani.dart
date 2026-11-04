import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/providers/veri_surumu_provider.dart';
import '../../models/cari_model.dart';
import 'cari_excel_ice_aktarma.dart';

/// Excel'den cari listesi içeri alma.
///
/// Dosya seçilir → isimler okunur → önizleme (yeni / zaten kayıtlı / atlanan)
/// → seçilen yeni cariler TEK transaction'da eklenir. Kayıtlı cariler
/// (pasifler dahil) tekrar eklenmez. Süt/yem rakamları alınmaz, yalnız cariler.
class CariExcelIceAktarmaEkrani extends ConsumerStatefulWidget {
  /// Testler için: dosya seçiciyi atlayıp bu dosyayla başlar.
  @visibleForTesting
  final ({String ad, List<int> baytlar})? hazirDosya;

  const CariExcelIceAktarmaEkrani({super.key, this.hazirDosya});

  @override
  ConsumerState<CariExcelIceAktarmaEkrani> createState() => _CariExcelIceAktarmaEkraniState();
}

class _CariExcelIceAktarmaEkraniState extends ConsumerState<CariExcelIceAktarmaEkrani> {
  static const _hayvanTurleri = ['İnek', 'Koyun', 'Tavuk'];

  String? _dosyaAdi;
  CariExcelSonucu? _sonuc;
  List<CariAdayi> _yeni = [];
  List<CariAdayi> _kayitli = [];
  final Set<int> _secili = {}; // aday satır numaraları
  String _hayvanTuru = 'İnek';
  String? _hata;
  bool _isleniyor = false;

  @override
  void initState() {
    super.initState();
    final d = widget.hazirDosya;
    if (d != null) WidgetsBinding.instance.addPostFrameCallback((_) => _oku(d.ad, d.baytlar));
  }

  Future<void> _dosyaSec() async {
    final secim = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    final f = secim?.files.singleOrNull;
    if (f == null) return;
    final baytlar = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
    if (baytlar == null) {
      setState(() => _hata = 'Dosya okunamadı.');
      return;
    }
    await _oku(f.name, baytlar);
  }

  Future<void> _oku(String ad, List<int> baytlar) async {
    setState(() {
      _isleniyor = true;
      _hata = null;
      _dosyaAdi = ad;
    });
    try {
      final sonuc = CariExcelOkuyucu.oku(baytlar);
      final repo = await ref.read(cariRepositoryProvider.future);
      final plan = iceAktarmaPlani(sonuc.adaylar, await repo.getAll());
      if (!mounted) return;
      setState(() {
        _sonuc = sonuc;
        _yeni = plan.yeni;
        _kayitli = plan.kayitli;
        _secili
          ..clear()
          ..addAll(plan.yeni.map((a) => a.satir));
      });
    } catch (e) {
      if (mounted) setState(() => _hata = '$e');
    } finally {
      if (mounted) setState(() => _isleniyor = false);
    }
  }

  Future<void> _iceAl() async {
    final eklenecek = _yeni.where((a) => _secili.contains(a.satir)).toList();
    if (eklenecek.isEmpty) return;
    setState(() => _isleniyor = true);
    try {
      final repo = await ref.read(cariRepositoryProvider.future);
      final adet = await repo.topluEkle([
        for (final a in eklenecek)
          Cari(ad: a.ad, soyad: a.soyad, telefon: a.telefon, adres: a.adres, hayvanTuru: _hayvanTuru),
      ]);
      ref.veriDegisti();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$adet cari içeri alındı ✓'),
        backgroundColor: Colors.green[700],
      ));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _hata = 'Kaydedilemedi, hiçbir cari eklenmedi: $e');
    } finally {
      if (mounted) setState(() => _isleniyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sonuc = _sonuc;
    final seciliSayi = _secili.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Excel\'den Cari Al')),
      bottomNavigationBar: sonuc == null || _yeni.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: _isleniyor || seciliSayi == 0 ? null : _iceAl,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: Text('$seciliSayi Cariyi İçeri Al', style: const TextStyle(fontSize: 16)),
                ),
              ),
            ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(
                'Excel dosyasındaki isimlerden cari oluşturulur. İlk satırda "Ad Soyad" '
                '(ya da ayrı "Ad" ve "Soyad") sütunu olmalı; varsa "Telefon" ve "Adres" de alınır. '
                'Uygulamanın kendi Süt/Yem raporu Excel\'i de olur. Süt ve yem rakamları alınmaz.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _isleniyor ? null : _dosyaSec,
                icon: const Icon(Icons.upload_file_rounded),
                label: Text(_dosyaAdi == null ? 'Excel Dosyası Seç (.xlsx)' : 'Başka Dosya Seç'),
              ),
              if (_dosyaAdi != null) ...[
                const SizedBox(height: 6),
                Text('Dosya: $_dosyaAdi${sonuc != null ? ' · Sayfa: ${sonuc.sayfa}' : ''}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ]),
          ),
        ),
        if (_isleniyor) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        if (_hata != null)
          Card(
            color: Colors.red[50],
            child: ListTile(
              leading: const Icon(Icons.error_outline, color: Colors.red),
              title: Text(_hata!, style: TextStyle(color: Colors.red[800])),
            ),
          ),
        if (sonuc != null && !_isleniyor) ...[
          _ozet(sonuc),
          if (_yeni.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Hayvan türü', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [for (final t in _hayvanTurleri) ButtonSegment(value: t, label: Text(t))],
                selected: {_hayvanTuru},
                onSelectionChanged: (s) => setState(() => _hayvanTuru = s.first),
              ),
            ),
            const SizedBox(height: 4),
            const Text('Tüm yeni carilere bu tür atanır; sonradan tek tek değiştirilebilir.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: Text('YENİ CARİLER (${_yeni.length})',
                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              TextButton(
                onPressed: () => setState(() => _secili.length == _yeni.length
                    ? _secili.clear()
                    : _secili.addAll(_yeni.map((a) => a.satir))),
                child: Text(_secili.length == _yeni.length ? 'Hiçbirini seçme' : 'Tümünü seç'),
              ),
            ]),
            Card(
              child: Column(children: [
                for (final a in _yeni)
                  CheckboxListTile(
                    dense: true,
                    value: _secili.contains(a.satir),
                    onChanged: (v) => setState(() => v == true ? _secili.add(a.satir) : _secili.remove(a.satir)),
                    title: Text(a.tamAd),
                    subtitle: Text([
                      '${a.satir}. satır',
                      if (a.soyad.isEmpty) 'soyadı yok',
                      if (a.telefon != null) a.telefon!,
                    ].join(' · ')),
                  ),
              ]),
            ),
          ],
          if (_kayitli.isNotEmpty) _katlanirListe('ZATEN KAYITLI — eklenmeyecek', _kayitli.map((a) => a.tamAd)),
          if (sonuc.atlananlar.isNotEmpty) _katlanirListe('ATLANAN SATIRLAR', sonuc.atlananlar),
        ],
      ]),
    );
  }

  Widget _ozet(CariExcelSonucu s) {
    Widget kutu(String sayi, String etiket, Color renk) => Expanded(
          child: Column(children: [
            Text(sayi, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: renk)),
            Text(etiket, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(children: [
          kutu('${s.adaylar.length}', 'dosyadaki isim', Colors.blueGrey),
          kutu('${_yeni.length}', 'yeni', Colors.green[700]!),
          kutu('${_kayitli.length}', 'zaten kayıtlı', Colors.orange[800]!),
          kutu('${s.atlananlar.length}', 'atlanan', Colors.grey),
        ]),
      ),
    );
  }

  Widget _katlanirListe(String baslik, Iterable<String> satirlar) => Card(
        child: ExpansionTile(
          title: Text('$baslik (${satirlar.length})', style: const TextStyle(fontSize: 14)),
          children: [
            for (final s in satirlar) ListTile(dense: true, title: Text(s, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );
}
