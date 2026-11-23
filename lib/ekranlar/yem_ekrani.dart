import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/cari/providers/cari_providers.dart';
import '../utils/turkce.dart';
import '../features/donem/donem_kapali_bandi.dart';
import 'package:intl/intl.dart';

import '../models/cari_model.dart';
import '../models/urun_model.dart';
import '../models/yem_model.dart';
import '../features/urunler/urun_providers.dart';
import '../data/repositories/donem_kilidi.dart';
import '../utils/tarih_secici.dart';
import '../core/providers/repository_providers.dart';
import '../core/providers/veri_surumu_provider.dart';
import '../utils/sayi_format.dart';
import '../widgetlar/kaydedilmemis_koruma.dart';
import '../widgetlar/rota_rozeti.dart';

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
        title: RotaliAd(cari, stil: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
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

/// Bir cariye bir günde verilen yem / ürünler. Alanlar Menü → Ürünler'deki AKTİF
/// ürünlerden oluşur (Süt Yemi, Besi Yemi, Gübre…). Dolu her alan ayrı bir satır
/// olarak TEK transaction'da yazılır (ya hepsi ya hiçbiri).
class YemGirisPage extends ConsumerStatefulWidget {
  final Cari cari;
  const YemGirisPage({required this.cari, super.key});

  @override
  ConsumerState<YemGirisPage> createState() => _YemGirisPageState();
}

class _YemGirisPageState extends ConsumerState<YemGirisPage> {
  /// urunId → miktar alanı. Ürün listesi yenilense de yazılmış değer kaybolmaz.
  final Map<int, TextEditingController> _alanlar = {};
  final _alanDegisti = _Bildirici();
  DateTime _tarih = DateTime.now();
  bool _kaydediliyor = false;

  @override
  void dispose() {
    for (final c in _alanlar.values) {
      c.dispose();
    }
    _alanDegisti.dispose();
    super.dispose();
  }

  TextEditingController _alan(int urunId) => _alanlar.putIfAbsent(urunId, () {
        final c = TextEditingController();
        c.addListener(_alanDegisti.bildir);
        return c;
      });

  /// Hatalı yazılmış bir alan varsa kayıt yapılmaz (sessizce 0 sayılmasın).
  bool _gecersizAlanVar(List<Urun> urunler) => urunler.any((u) => sayiCoz(_alan(u.id!).text) == null);

  /// Girilmiş (> 0) kalemler, ürün sırasıyla.
  List<(Urun, double)> _kalemler(List<Urun> urunler) => [
        for (final u in urunler)
          if ((sayiCoz(_alan(u.id!).text) ?? 0) > 0) (u, sayiCoz(_alan(u.id!).text)!),
      ];

  Future<void> _kaydet(List<Urun> urunler) async {
    // Çift dokunma: aynı yem İKİ KEZ yazılıp cariye iki kat borç çıkmasın.
    if (_kaydediliyor) return;
    if (_gecersizAlanVar(urunler)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geçersiz miktar var, lütfen kontrol edin'), backgroundColor: Colors.red),
      );
      return;
    }
    final kalemler = _kalemler(urunler);
    if (kalemler.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('En az bir ürünün miktarını girin'), backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      );
      return;
    }
    setState(() => _kaydediliyor = true);
    try {
      final repo = await ref.read(yemRepositoryProvider.future);
      final tarih = DateFormat('yyyy-MM-dd').format(_tarih);
      await repo.topluEkle([
        for (final (u, m) in kalemler) Yem(cariId: widget.cari.id!, tarih: tarih, urunId: u.id!, miktar: m),
      ]);
      ref.veriDegisti();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(kalemler.length == 1 ? 'Yem kaydı başarıyla eklendi' : '${kalemler.length} kalem yem kaydı eklendi'),
        backgroundColor: Colors.green[700],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _kaydediliyor = false);
      final mesaj = donemKapaliHatasiMi(e)
          ? const DonemKapaliHatasi().toString()
          : e is ArgumentError
              ? '${e.message}'
              : 'Kaydedilemedi: $e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mesaj), backgroundColor: Colors.red));
    }
  }

  static const _renkler = [Colors.blue, Colors.brown, Colors.purple, Colors.indigo, Colors.orange, Colors.amber, Colors.teal, Colors.green, Colors.red, Colors.cyan];

  Widget _alanOlustur(Urun u, int sira) {
    final renk = _renkler[sira % _renkler.length];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        key: ValueKey('yemAlani_${u.id}'),
        controller: _alan(u.id!),
        decoration: InputDecoration(
          labelText: '${u.ad} (${u.birim})',
          prefixIcon: Icon(Icons.grass, color: renk, size: 20),
          hintText: '0',
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  /// Bir alana miktar yazılmış (ya da hatalı yazılmış) ama kaydedilmemiş.
  bool get _kaydedilmemisVar => !_kaydediliyor && _alanlar.values.any((c) => sayiCoz(c.text) != 0);

  @override
  Widget build(BuildContext context) {
    final urunlerAsync = ref.watch(aktifUrunlerProvider);
    final urunler = urunlerAsync.valueOrNull ?? const <Urun>[];
    return KaydedilmemisKoruma(
      dinle: _alanDegisti,
      degisiklikVar: () => _kaydedilmemisVar,
      kaydet: () => _kaydet(urunler),
      baslik: 'Yem kaydedilmedi',
      child: _ekran(context, urunlerAsync),
    );
  }

  Widget _ekran(BuildContext context, AsyncValue<List<Urun>> urunlerAsync) {
    final urunler = urunlerAsync.valueOrNull ?? const <Urun>[];
    final kalemler = _kalemler(urunler);
    final kgToplam = kalemler.where((k) => k.$1.kgMi).fold(0.0, (t, k) => t + k.$2);
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
                    const Expanded(child: Text('Yem / Ürünler', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                    if (kalemler.isNotEmpty)
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(8)),
                          child: Text(
                            kgToplam > 0 ? '${kalemler.length} kalem · ${sayiGoster(kgToplam)} kg' : '${kalemler.length} kalem',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 16),
                  ...urunlerAsync.when(
                    loading: () => const [Center(child: CircularProgressIndicator())],
                    error: (e, _) => [Text('Ürünler okunamadı: $e', style: const TextStyle(color: Colors.red))],
                    data: (l) => l.isEmpty
                        ? [
                            Text('Aktif ürün yok. Menü → Ürünler (Yem, Gübre…) ekranından ürün ekleyin.',
                                style: TextStyle(color: Colors.orange[800])),
                          ]
                        : [for (var i = 0; i < l.length; i++) _alanOlustur(l[i], i)],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _kaydediliyor || urunler.isEmpty ? null : () => _kaydet(urunler),
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

/// Alanlardan herhangi biri değişince "kaydedilmemiş değişiklik" korumasını uyandırır.
class _Bildirici extends ChangeNotifier {
  void bildir() => notifyListeners();
}
