import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/providers/veri_surumu_provider.dart';
import '../../models/cari_model.dart';
import '../../widgetlar/kaydedilmemis_koruma.dart';

/// Süt toplama rotası: aktif carileri sürükle-bırak ile sıralar.
/// Kaydet → listedeki sırayla 1, 2, 3… (`CariRepository.rotaKaydet`).
/// Süt, Yem, Hızlı Süt Girişi ve Cariler listeleri bu sırayla dizilir.
class ToplamaSirasiEkrani extends ConsumerStatefulWidget {
  const ToplamaSirasiEkrani({super.key});

  @override
  ConsumerState<ToplamaSirasiEkrani> createState() => _ToplamaSirasiEkraniState();
}

class _ToplamaSirasiEkraniState extends ConsumerState<ToplamaSirasiEkrani> {
  List<Cari> _liste = [];
  List<int> _ilkSira = [];
  bool _yukleniyor = true;
  bool _kaydediliyor = false;
  final _degisti = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    _degisti.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    final repo = await ref.read(cariRepositoryProvider.future);
    final aktifler = await repo.getAll(sadeceAktif: true); // rota sırasıyla gelir
    if (!mounted) return;
    setState(() {
      _liste = aktifler;
      _ilkSira = [for (final c in aktifler) c.id!];
      _yukleniyor = false;
    });
  }

  /// Hiç sırası olmayan cari var mı? (O zaman kaydetmek de bir değişikliktir.)
  bool get _sirasizVar => _liste.any((c) => c.sira == null);

  bool get _degisiklikVar {
    if (_yukleniyor) return false;
    final simdi = [for (final c in _liste) c.id!];
    for (var i = 0; i < simdi.length; i++) {
      if (simdi[i] != _ilkSira[i]) return true;
    }
    return false;
  }

  void _tasi(int eski, int yeni) {
    setState(() {
      if (yeni > eski) yeni--;
      _liste.insert(yeni, _liste.removeAt(eski));
    });
    _degisti.value++;
  }

  Future<void> _kaydet() async {
    setState(() => _kaydediliyor = true);
    try {
      final repo = await ref.read(cariRepositoryProvider.future);
      await repo.rotaKaydet([for (final c in _liste) c.id!]);
      ref.veriDegisti();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Toplama sırası kaydedildi (${_liste.length} cari)'),
        backgroundColor: Colors.green[700],
      ));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _kaydediliyor = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return KaydedilmemisKoruma(
      dinle: _degisti,
      degisiklikVar: () => !_kaydediliyor && _degisiklikVar,
      kaydet: _kaydet,
      baslik: 'Sıra kaydedilmedi',
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFF),
        appBar: AppBar(
          title: const Text('Toplama Sırası (Rota)'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.blue[800],
          elevation: 0,
        ),
        body: _yukleniyor
            ? const Center(child: CircularProgressIndicator())
            : _liste.isEmpty
                ? const Center(child: Text('Aktif cari yok'))
                : Column(
                    children: [
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(12)),
                        child: Text(
                          'Süt toplarken uğradığınız sırayla dizin: sağdaki ≡ tutamağından tutup sürükleyin. '
                          'Kaydedince numaralar 1\'den başlayarak verilir.'
                          '${_sirasizVar ? '\nSırası olmayan cariler (—) en altta; kaydedince onlar da numaralanır.' : ''}',
                          style: TextStyle(fontSize: 12.5, color: Colors.blue[900]),
                        ),
                      ),
                      Expanded(
                        child: ReorderableListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          buildDefaultDragHandles: false,
                          itemCount: _liste.length,
                          onReorder: _tasi,
                          itemBuilder: (_, i) {
                            final c = _liste[i];
                            return Card(
                              key: ValueKey(c.id),
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.blue[700],
                                  foregroundColor: Colors.white,
                                  child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                ),
                                title: Text(c.tamAd,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                  c.sira == null ? 'Şu an sırasız' : 'Kayıtlı sıra: ${c.sira}',
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                ),
                                trailing: ReorderableDragStartListener(
                                  index: i,
                                  child: const Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Icon(Icons.drag_handle),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
        bottomNavigationBar: _liste.isEmpty
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _kaydediliyor || (!_degisiklikVar && !_sirasizVar) ? null : _kaydet,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[700],
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.save),
                      label: const Text('Sırayı Kaydet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
