import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers/veri_surumu_provider.dart';
import '../../models/cari_model.dart';
import '../../utils/app_theme.dart';
import '../../utils/excel_export.dart';
import 'donem_providers.dart';
import 'donem_servisi.dart';

/// Dönem Kapanışı & Hakediş.
///
/// Bitmiş bir ayın üretici hakedişlerini gösterir; kapatıldığında bordro
/// dondurulur ve o aya süt/yem/ödeme/fiyat girişi kilitlenir. Kapalı dönem
/// yalnızca gerekçe yazılarak yeniden açılabilir (denetim kaydına geçer).
class DonemEkrani extends ConsumerStatefulWidget {
  const DonemEkrani({super.key});

  @override
  ConsumerState<DonemEkrani> createState() => _DonemEkraniState();
}

class _DonemEkraniState extends ConsumerState<DonemEkrani> {
  // Varsayılan: geçen ay (kapatılmaya aday en son ay).
  DateTime _ay = DateTime(DateTime.now().year, DateTime.now().month - 1);
  bool _islem = false;

  static final _para = NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2);
  static final _kg = NumberFormat.decimalPattern('tr_TR');

  String get _anahtar => DonemServisi.ayAnahtari(_ay);
  String get _ayAdi => DateFormat('MMMM yyyy', 'tr_TR').format(_ay);
  bool get _bitmisAy => _anahtar.compareTo(DonemServisi.ayAnahtari(DateTime.now())) < 0;
  bool get _buAyMi => _anahtar == DonemServisi.ayAnahtari(DateTime.now());

  void _ayDegistir(int fark) => setState(() => _ay = DateTime(_ay.year, _ay.month + fark));

  void _mesaj(String m, {bool hata = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: hata ? AppRenkler.hata : AppRenkler.basari,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _calistir(Future<void> Function() islem) async {
    setState(() => _islem = true);
    try {
      await islem();
    } catch (e) {
      _mesaj('$e', hata: true);
    } finally {
      if (mounted) setState(() => _islem = false);
    }
  }

  Future<void> _kapat(DonemBilgisi b) async {
    final odenecek = b.satirlar.where((s) => s.donemSonu > 0).fold(0.0, (t, s) => t + s.donemSonu);
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.lock_outline_rounded, size: 36),
        title: Text('$_ayAdi dönemi kapatılsın mı?'),
        content: Text(
          '${b.satirlar.length} üreticinin hakedişi dondurulacak.\n'
          'Toplam ödenecek: ${_para.format(odenecek)}\n\n'
          'Kapattıktan sonra $_ayAdi tarihli süt, yem, ödeme ve fiyat kayıtları '
          'eklenemez, değiştirilemez ve silinemez. Hata fark ederseniz dönemi '
          'gerekçe yazarak yeniden açabilirsiniz.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.lock_rounded, size: 18),
            label: const Text('Dönemi Kapat'),
          ),
        ],
      ),
    );
    if (onay != true) return;
    await _calistir(() async {
      final servis = await ref.read(donemServisiProvider.future);
      await servis.kapat(_anahtar);
      ref.veriDegisti();
      _mesaj('$_ayAdi dönemi kapatıldı ✓');
    });
  }

  Future<void> _yenidenAc() async {
    final gerekce = await showDialog<String>(
      context: context,
      builder: (_) => _GerekceDialog(ayAdi: _ayAdi),
    );
    if (gerekce == null) return;
    await _calistir(() async {
      final servis = await ref.read(donemServisiProvider.future);
      await servis.yenidenAc(_anahtar, gerekce);
      ref.veriDegisti();
      _mesaj('$_ayAdi dönemi yeniden açıldı');
    });
  }

  Future<void> _excel(DonemBilgisi b, Map<int, Cari> cariler) async {
    await _calistir(() async {
      final file = await ExcelExport.exportHakedisBordrosu(
        satirlar: _sirali(b, cariler),
        ayAdi: _ayAdi,
        kapali: b.kapali,
      );
      await ExcelExport.shareFile(file);
    });
  }

  List<({Cari cari, HakedisSatiri satir})> _sirali(DonemBilgisi b, Map<int, Cari> cariler) {
    final liste = [
      for (final s in b.satirlar)
        (cari: cariler[s.cariId] ?? Cari(id: s.cariId, ad: 'Silinmiş cari', soyad: '#${s.cariId}'), satir: s),
    ]..sort((a, b) => '${a.cari.ad} ${a.cari.soyad}'
        .toLowerCase()
        .compareTo('${b.cari.ad} ${b.cari.soyad}'.toLowerCase()));
    return liste;
  }

  @override
  Widget build(BuildContext context) {
    final bilgi = ref.watch(donemBilgisiProvider(_anahtar));
    final cariler = ref.watch(tumCarilerProvider);
    final hazir = bilgi.hasValue && cariler.hasValue;

    return Scaffold(
      backgroundColor: AppRenkler.arkaplan,
      appBar: AppBar(
        title: const Text('Dönem Kapanışı & Hakediş'),
        actions: [
          if (hazir && bilgi.value!.satirlar.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.file_download_outlined),
              tooltip: 'Bordroyu Excel\'e aktar',
              onPressed: _islem ? null : () => _excel(bilgi.value!, cariler.value!),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ayKutusu(),
          const SizedBox(height: 12),
          if (bilgi.hasError || cariler.hasError)
            _uyari(Icons.error_outline, 'Yüklenemedi: ${bilgi.error ?? cariler.error}', AppRenkler.hata)
          else if (!hazir)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            _durumKarti(bilgi.value!),
            const SizedBox(height: 12),
            if (bilgi.value!.satirlar.isEmpty)
              _uyari(Icons.inbox_outlined, '$_ayAdi için hakediş yok.', AppRenkler.metinIkincil)
            else ...[
              _toplamKarti(bilgi.value!),
              const SizedBox(height: 12),
              ..._sirali(bilgi.value!, cariler.value!).map((r) => _HakedisKarti(r.cari, r.satir)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _ayKutusu() => Card(
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'Önceki ay',
            onPressed: _islem ? null : () => _ayDegistir(-1),
          ),
          Expanded(
            child: Text(_ayAdi,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: 'Sonraki ay',
            onPressed: _islem || _buAyMi ? null : () => _ayDegistir(1),
          ),
        ]),
      );

  Widget _durumKarti(DonemBilgisi b) {
    final renk = b.kapali ? AppRenkler.basari : Colors.orange.shade800;
    final String aciklama;
    if (b.kapali) {
      aciklama = 'Bordro dondurulmuş; bu aya kayıt girilemez.'
          '${b.kapanisTarihi != null ? '\nKapanış: ${b.kapanisTarihi} (UTC)' : ''}'
          '${b.acilisSayisi > 0 ? '\nDaha önce ${b.acilisSayisi} kez yeniden açıldı.' : ''}';
    } else if (!_bitmisAy) {
      aciklama = 'Ay bitmeden dönem kapatılamaz. Rakamlar canlı (taslak).';
    } else if (b.fiyatEksikVar) {
      aciklama = 'Bazı üreticilerin bu ay fiyatı tanımlı değil; fiyatları girmeden kapatılamaz.';
    } else {
      aciklama = 'Rakamlar canlı (taslak). Kontrol ettikten sonra dönemi kapatın.';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(b.kapali ? Icons.lock_rounded : Icons.lock_open_rounded, color: renk),
            const SizedBox(width: 8),
            Text(b.kapali ? 'KAPALI DÖNEM' : 'AÇIK DÖNEM',
                style: TextStyle(fontWeight: FontWeight.bold, color: renk)),
          ]),
          const SizedBox(height: 6),
          Text(aciklama, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 10),
          if (b.kapali)
            OutlinedButton.icon(
              onPressed: _islem ? null : _yenidenAc,
              icon: const Icon(Icons.lock_open_rounded),
              label: const Text('Dönemi Yeniden Aç'),
            )
          else
            FilledButton.icon(
              onPressed: _islem || !_bitmisAy || b.fiyatEksikVar || b.satirlar.isEmpty
                  ? null
                  : () => _kapat(b),
              icon: const Icon(Icons.lock_rounded),
              label: const Text('Dönemi Kapat'),
            ),
        ]),
      ),
    );
  }

  Widget _toplamKarti(DonemBilgisi b) {
    double topla(double Function(HakedisSatiri) f) => b.satirlar.fold(0.0, (t, s) => t + f(s));
    final odenecek = b.satirlar.where((s) => s.donemSonu > 0).fold(0.0, (t, s) => t + s.donemSonu);
    final alacak = b.satirlar.where((s) => s.donemSonu < 0).fold(0.0, (t, s) => t - s.donemSonu);
    Widget kalem(String etiket, String deger) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(etiket, style: const TextStyle(color: AppRenkler.metinIkincil))),
            Text(deger, style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          kalem('Toplanan süt', '${_kg.format(topla((s) => s.sutKg))} kg'),
          kalem('Süt tutarı', _para.format(topla((s) => s.sutTutar))),
          kalem('Verilen yem', _para.format(topla((s) => s.yemTutar))),
          kalem('Ay içinde ödenen', _para.format(topla((s) => s.odeme))),
          kalem('Ay içinde tahsil edilen', _para.format(topla((s) => s.tahsilat))),
          const Divider(),
          kalem('Üreticilere ödenecek', _para.format(odenecek)),
          kalem('Üreticilerden alacak', _para.format(alacak)),
        ]),
      ),
    );
  }

  Widget _uyari(IconData ikon, String metin, Color renk) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Icon(ikon, color: renk),
            const SizedBox(width: 10),
            Expanded(child: Text(metin, style: TextStyle(color: renk))),
          ]),
        ),
      );
}

class _HakedisKarti extends StatelessWidget {
  final Cari cari;
  final HakedisSatiri s;
  const _HakedisKarti(this.cari, this.s);

  static final _para = NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2);

  @override
  Widget build(BuildContext context) {
    final sonuc = s.donemSonu;
    final kapali = sonuc.abs() < 0.005;
    final renk = kapali ? AppRenkler.basari : (sonuc > 0 ? AppRenkler.bilgi : const Color(0xFFE65100));
    Widget satir(String etiket, double tutar, {bool eksi = false}) => tutar.abs() < 0.005
        ? const SizedBox.shrink()
        : Row(children: [
            Expanded(child: Text(etiket, style: const TextStyle(fontSize: 12, color: AppRenkler.metinIkincil))),
            Text('${eksi ? '−' : '+'} ${_para.format(tutar.abs())}', style: const TextStyle(fontSize: 12)),
          ]);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: s.fiyatEksik ? Colors.orange.shade300 : AppRenkler.sinir),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${cari.ad} ${cari.soyad}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_para.format(sonuc.abs()),
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: renk)),
              Text(kapali ? 'Kapalı' : (sonuc > 0 ? 'Ödenecek' : 'Borçlu'),
                  style: TextStyle(fontSize: 11, color: renk)),
            ]),
          ]),
          if (s.fiyatEksik)
            Text('Bu ay fiyatı tanımlı değil',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
          const SizedBox(height: 6),
          satir('Önceki dönemden devir', s.devir, eksi: s.devir < 0),
          if (s.sutKg > 0)
            satir('Süt ${s.sutKg.toStringAsFixed(1)} kg × ${s.sutFiyat.toStringAsFixed(2)} ₺', s.sutTutar),
          satir('Yem ${s.yemKg.toStringAsFixed(1)} kg', s.yemTutar, eksi: true),
          satir('Ödenen', s.odeme, eksi: true),
          satir('Tahsil edilen', s.tahsilat),
        ]),
      ),
    );
  }
}

/// Yeniden açma gerekçesi (zorunlu).
class _GerekceDialog extends StatefulWidget {
  final String ayAdi;
  const _GerekceDialog({required this.ayAdi});

  @override
  State<_GerekceDialog> createState() => _GerekceDialogState();
}

class _GerekceDialogState extends State<_GerekceDialog> {
  final _ctrl = TextEditingController();
  String? _hata;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onayla() {
    final g = _ctrl.text.trim();
    if (g.length < 3) {
      setState(() => _hata = 'Neden açtığınızı kısaca yazın');
      return;
    }
    Navigator.pop(context, g);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        icon: const Icon(Icons.lock_open_rounded, size: 36),
        title: Text('${widget.ayAdi} yeniden açılsın mı?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'Dondurulmuş bordro silinir (bir kopyası işlem geçmişinde saklanır) '
            've bu aya yeniden kayıt girilebilir. Düzeltmeden sonra dönemi tekrar kapatın.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Gerekçe',
              hintText: 'Örn: Ali Yılmaz 12 Ekim sütü yanlış girilmiş',
              border: const OutlineInputBorder(),
              errorText: _hata,
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
          FilledButton(onPressed: _onayla, child: const Text('Yeniden Aç')),
        ],
      );
}
