import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/providers/veri_surumu_provider.dart';
import '../../features/cari/providers/cari_providers.dart';
import '../../features/cari_hesap/providers/cari_hesap_providers.dart';
import '../../models/cari_model.dart';
import '../../utils/turkce.dart';
import 'cari_duzenle.dart';
import 'cari_form.dart';

/// Pasife alınmış cariler: listelerde ve rotada görünmezler, geçmiş kayıtları
/// durur. Buradan bakiyeleri görülür ve "Geri Getir" ile yeniden aktif yapılır
/// (isteğe bağlı rota sırasıyla).
class PasifCarilerEkrani extends ConsumerStatefulWidget {
  const PasifCarilerEkrani({super.key});

  @override
  ConsumerState<PasifCarilerEkrani> createState() => _PasifCarilerEkraniState();
}

class _PasifCarilerEkraniState extends ConsumerState<PasifCarilerEkrani> {
  String _arama = '';
  final _para = NumberFormat('#,##0.00', 'tr_TR');

  Future<void> _geriGetir(Cari cari) async {
    final sira = await showDialog<({int? sira})>(
      context: context,
      builder: (_) => _GeriGetirDialog(cari: cari),
    );
    if (sira == null) return;
    try {
      final repo = await ref.read(cariRepositoryProvider.future);
      await repo.aktifYap(cari.id!, sira: sira.sira);
      ref.veriDegisti();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(sira.sira == null
            ? '${cari.tamAd} geri getirildi (rotada sırasız, listede en sonda)'
            : '${cari.tamAd} geri getirildi · rotada ${sira.sira}. sıra'),
        backgroundColor: Colors.green[700],
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Geri getirilemedi: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final carilerAsync = ref.watch(butunCarilerProvider);
    final bakiyeler = ref.watch(tumKalanBorclarProvider).valueOrNull ?? const <int, double>{};

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        title: const Text('Pasif Cariler'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.blue[800],
        elevation: 0,
      ),
      body: carilerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Yüklenemedi: $e')),
        data: (hepsi) {
          final pasifler = hepsi.where((c) => !c.aktif).toList();
          final gorunen = pasifler.where((c) => _arama.isEmpty || aramaEslesir(c.tamAd, _arama)).toList();
          return Column(
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blueGrey[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Pasif cariler Cariler, Süt, Yem listelerinde ve toplama rotasında görünmez. '
                  'Geçmiş kayıtları silinmez. "Geri Getir" ile yeniden aktif olur.',
                  style: TextStyle(fontSize: 12.5, color: Colors.blueGrey[800]),
                ),
              ),
              if (pasifler.length > 5)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Pasif cari ara...',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _arama = v.trim()),
                  ),
                ),
              Expanded(
                child: pasifler.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.how_to_reg_outlined, size: 56, color: Colors.grey[400]),
                            const SizedBox(height: 12),
                            Text('Pasif cari yok', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: gorunen.length,
                        itemBuilder: (_, i) => _PasifKart(
                          cari: gorunen[i],
                          bakiye: bakiyeler[gorunen[i].id] ?? 0,
                          para: _para,
                          onGeriGetir: () => _geriGetir(gorunen[i]),
                          onDuzenle: () => Navigator.push(
                              context, MaterialPageRoute(builder: (_) => CariDuzenle(cari: gorunen[i]))),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PasifKart extends StatelessWidget {
  final Cari cari;
  final double bakiye;
  final NumberFormat para;
  final VoidCallback onGeriGetir;
  final VoidCallback onDuzenle;
  const _PasifKart({
    required this.cari,
    required this.bakiye,
    required this.para,
    required this.onGeriGetir,
    required this.onDuzenle,
  });

  @override
  Widget build(BuildContext context) {
    final acik = bakiye.abs() > 0.005;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onDuzenle,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.grey[200],
                child: Icon(Icons.person_off_outlined, color: Colors.grey[600]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cari.tamAd,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(
                      [cari.hayvanTuru, cari.telefon].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    if (acik)
                      Text(
                        bakiye > 0
                            ? 'Açık bakiye: ${para.format(bakiye)} ₺ (cari alacaklı)'
                            : 'Açık bakiye: ${para.format(-bakiye)} ₺ (cari borçlu)',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: bakiye > 0 ? Colors.blue[800] : Colors.orange[800]),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: onGeriGetir,
                // Dar telefonda / büyük yazıda isim alanına yer kalsın.
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.restore, size: 18),
                label: const Text('Geri Getir'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Geri getirirken rota sırası sorulur (boş → sırasız, en sonda).
class _GeriGetirDialog extends StatefulWidget {
  final Cari cari;
  const _GeriGetirDialog({required this.cari});

  @override
  State<_GeriGetirDialog> createState() => _GeriGetirDialogState();
}

class _GeriGetirDialogState extends State<_GeriGetirDialog> {
  final _form = GlobalKey<FormState>();
  final _sira = TextEditingController();

  @override
  void dispose() {
    _sira.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.cari.tamAd} geri getirilsin mi?'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Toplama rotasında kaçıncı sırada olsun?', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              RotaSirasiAlani(controller: _sira, cariId: widget.cari.id),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(context, (sira: RotaSirasiAlani.siraOku(_sira.text)));
          },
          child: const Text('Geri Getir'),
        ),
      ],
    );
  }
}
