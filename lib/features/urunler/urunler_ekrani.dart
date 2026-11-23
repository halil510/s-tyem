import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/providers/veri_surumu_provider.dart';
import '../../data/repositories/donem_kilidi.dart';
import '../../data/repositories/urun_repository.dart';
import '../../models/urun_model.dart';
import 'urun_providers.dart';

/// Önerilen birimler (serbest yazı da girilebilir).
const urunBirimOnerileri = ['kg', 'çuval', 'adet', 'balya', 'litre', 'ton'];

/// ─────────────────────────────────────────────────────────────
/// ÜRÜNLER (Yem, Gübre…) — Menü → Ürünler
/// ─────────────────────────────────────────────────────────────
/// Üreticiye verilip süt parasından düşülen her şey: süt yemi, besi yemi,
/// gübre, saman… Buradan eklenen ürün Yem Ekle ve Yem Fiyatları ekranlarında
/// kendiliğinden görünür. Sürükleyerek sıralanır.
class UrunlerEkrani extends ConsumerStatefulWidget {
  const UrunlerEkrani({super.key});

  @override
  ConsumerState<UrunlerEkrani> createState() => _UrunlerEkraniState();
}

class _UrunlerEkraniState extends ConsumerState<UrunlerEkrani> {
  Map<int, int> _kayitSayilari = {};
  bool _isleniyor = false;

  @override
  void initState() {
    super.initState();
    _sayilariYukle();
  }

  Future<void> _sayilariYukle() async {
    final repo = await ref.read(urunRepositoryProvider.future);
    final s = await repo.kayitSayilari();
    if (mounted) setState(() => _kayitSayilari = s);
  }

  void _mesaj(String metin, {bool hata = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(metin),
      backgroundColor: hata ? Colors.red[700] : Colors.green[700],
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// Ortak: işlemi yapar, hatayı okunur gösterir, ekranları yeniler.
  Future<bool> _islem(Future<void> Function(UrunRepository repo) f, {String? basari}) async {
    if (_isleniyor) return false;
    setState(() => _isleniyor = true);
    try {
      final repo = await ref.read(urunRepositoryProvider.future);
      await f(repo);
      ref.veriDegisti();
      await _sayilariYukle();
      if (basari != null) _mesaj(basari);
      return true;
    } catch (e) {
      _mesaj(e is UrunHatasi || donemKapaliHatasiMi(e) ? e.toString() : 'İşlem yapılamadı: $e', hata: true);
      return false;
    } finally {
      if (mounted) setState(() => _isleniyor = false);
    }
  }

  Future<void> _ekleDuzenle([Urun? urun]) async {
    final kayitVar = urun != null && (_kayitSayilari[urun.id] ?? 0) > 0;
    final sonuc = await showDialog<({String ad, String birim})>(
      context: context,
      builder: (_) => UrunFormDialog(urun: urun, birimKilitli: kayitVar),
    );
    if (sonuc == null) return;
    if (urun == null) {
      await _islem((r) => r.ekle(ad: sonuc.ad, birim: sonuc.birim), basari: '"${sonuc.ad}" eklendi. Fiyatını Yem Fiyatları ekranından girin.');
    } else {
      await _islem((r) => r.guncelle(urun.id!, ad: sonuc.ad, birim: sonuc.birim), basari: 'Kaydedildi');
    }
  }

  Future<void> _sil(Urun u) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ürün silinsin mi?'),
        content: Text('"${u.ad}" ve bu ürüne girilmiş FİYATLAR silinecek. Bu ürünün hiç kaydı yok.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red[700]),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (onay == true) await _islem((r) => r.sil(u.id!), basari: '"${u.ad}" silindi');
  }

  Future<void> _sirala(List<Urun> liste, int eski, int yeni) async {
    if (yeni > eski) yeni--;
    final l = [...liste];
    l.insert(yeni, l.removeAt(eski));
    await _islem((r) => r.siraKaydet([for (final u in l) u.id!]));
  }

  @override
  Widget build(BuildContext context) {
    final urunler = ref.watch(urunlerProvider);
    return Scaffold(
      backgroundColor: const Color(0xFFF8FFF8),
      appBar: AppBar(
        title: const Text('Ürünler (Yem, Gübre…)', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('urunEkleButonu'),
        onPressed: _isleniyor ? null : () => _ekleDuzenle(),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Ürün Ekle'),
      ),
      body: urunler.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Hata: $e')),
        data: (liste) => Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green[100]!),
              ),
              child: Row(children: [
                Icon(Icons.info_outline, color: Colors.green[700], size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Burada eklenen ürün Yem Ekle ve Yem Fiyatları ekranlarında görünür. '
                    'Sıralamak için basılı tutup sürükleyin. Kaydı olan ürün silinemez, pasife alınır.',
                    style: TextStyle(color: Colors.green[900], fontSize: 12),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: liste.isEmpty
                  ? Center(child: Text('Henüz ürün yok', style: TextStyle(color: Colors.grey[600])))
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: liste.length,
                      onReorder: (e, y) => _sirala(liste, e, y),
                      itemBuilder: (ctx, i) => _urunKarti(liste[i], key: ValueKey('urun_${liste[i].id}')),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _urunKarti(Urun u, {required Key key}) {
    final kayit = _kayitSayilari[u.id] ?? 0;
    return Card(
      key: key,
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: u.aktif ? Colors.white : Colors.grey[200],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey[300]!)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: u.aktif ? Colors.green[50] : Colors.grey[300],
          child: Icon(Icons.grass, color: u.aktif ? Colors.green[700] : Colors.grey[600]),
        ),
        title: Text(u.ad,
            style: TextStyle(fontWeight: FontWeight.w600, color: u.aktif ? null : Colors.grey[700]),
            overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${u.birim} · ${kayit == 0 ? 'kaydı yok' : '$kayit kayıt'}${u.aktif ? '' : ' · PASİF'}',
          style: TextStyle(fontSize: 12, color: u.aktif ? Colors.grey[600] : Colors.red[700]),
        ),
        onTap: () => _ekleDuzenle(u),
        trailing: PopupMenuButton<String>(
          key: ValueKey('urunMenu_${u.id}'),
          onSelected: (v) {
            switch (v) {
              case 'duzenle':
                _ekleDuzenle(u);
              case 'pasif':
                _islem((r) => r.aktiflikDegistir(u.id!, false), basari: '"${u.ad}" pasife alındı');
              case 'aktif':
                _islem((r) => r.aktiflikDegistir(u.id!, true), basari: '"${u.ad}" yeniden aktif');
              case 'sil':
                _sil(u);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'duzenle', child: Text('Düzenle')),
            if (u.aktif)
              const PopupMenuItem(value: 'pasif', child: Text('Pasife al'))
            else
              const PopupMenuItem(value: 'aktif', child: Text('Aktif yap')),
            if (kayit == 0) const PopupMenuItem(value: 'sil', child: Text('Sil', style: TextStyle(color: Colors.red))),
          ],
        ),
      ),
    );
  }
}

/// Ürün ekleme / düzenleme penceresi. Sonuç: (ad, birim) ya da null (vazgeç).
class UrunFormDialog extends StatefulWidget {
  final Urun? urun;

  /// Ürünün kaydı varsa birim değiştirilemez.
  final bool birimKilitli;
  const UrunFormDialog({super.key, this.urun, this.birimKilitli = false});

  @override
  State<UrunFormDialog> createState() => _UrunFormDialogState();
}

class _UrunFormDialogState extends State<UrunFormDialog> {
  late final _adCtrl = TextEditingController(text: widget.urun?.ad ?? '');
  late final _birimCtrl = TextEditingController(text: widget.urun?.birim ?? 'kg');
  String? _adHata, _birimHata;

  @override
  void dispose() {
    _adCtrl.dispose();
    _birimCtrl.dispose();
    super.dispose();
  }

  void _tamam() {
    final ad = _adCtrl.text.trim();
    final birim = _birimCtrl.text.trim();
    setState(() {
      _adHata = ad.isEmpty
          ? 'Ürün adını yazın'
          : ad.length > UrunRepository.maksimumAdUzunlugu
              ? 'En çok ${UrunRepository.maksimumAdUzunlugu} harf'
              : null;
      _birimHata = birim.isEmpty
          ? 'Birim yazın (ör. kg, çuval)'
          : birim.length > UrunRepository.maksimumBirimUzunlugu
              ? 'En çok ${UrunRepository.maksimumBirimUzunlugu} harf'
              : null;
    });
    if (_adHata != null || _birimHata != null) return;
    Navigator.pop(context, (ad: ad, birim: birim));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.urun == null ? 'Yeni Ürün' : 'Ürünü Düzenle'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('urunAdAlani'),
              controller: _adCtrl,
              autofocus: widget.urun == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Ürün adı',
                hintText: 'ör. Gübre, Saman, Düve Yemi',
                errorText: _adHata,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('urunBirimAlani'),
              controller: _birimCtrl,
              enabled: !widget.birimKilitli,
              decoration: InputDecoration(
                labelText: 'Birim',
                helperText: widget.birimKilitli
                    ? 'Kaydı olduğu için birim değiştirilemez'
                    : 'Fiyat bu birim başına girilir (₺/${_birimCtrl.text.isEmpty ? 'birim' : _birimCtrl.text})',
                helperMaxLines: 2,
                errorText: _birimHata,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (!widget.birimKilitli) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final b in urunBirimOnerileri)
                    ChoiceChip(
                      label: Text(b),
                      selected: _birimCtrl.text.trim() == b,
                      onSelected: (_) => setState(() => _birimCtrl.text = b),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          key: const ValueKey('urunKaydetButonu'),
          onPressed: _tamam,
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
