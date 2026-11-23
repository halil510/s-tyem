import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/providers/veri_surumu_provider.dart';
import '../../data/repositories/fabrika_repository.dart';
import '../../models/fabrika_model.dart';
import '../../utils/app_theme.dart';
import 'fabrika_dialoglari.dart';
import 'fabrika_providers.dart';

final _para = NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2);

/// Fabrika kartları: ekle, düzenle, pasife al / aktif yap, (hareketsizse) sil.
class FabrikalarEkrani extends ConsumerStatefulWidget {
  const FabrikalarEkrani({super.key});

  @override
  ConsumerState<FabrikalarEkrani> createState() => _FabrikalarEkraniState();
}

class _FabrikalarEkraniState extends ConsumerState<FabrikalarEkrani> {
  bool _islem = false;

  void _mesaj(String m, {bool hata = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: hata ? AppRenkler.hata : AppRenkler.basari,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _calistir(Future<bool> Function(FabrikaRepository repo) islem, {String? basariMesaji}) async {
    if (_islem) return;
    setState(() => _islem = true);
    try {
      final repo = await ref.read(fabrikaRepositoryProvider.future);
      if (!mounted) return;
      if (await islem(repo)) {
        ref.veriDegisti();
        if (basariMesaji != null) _mesaj(basariMesaji);
      }
    } catch (e) {
      _mesaj(e is FabrikaKayitHatasi ? e.mesaj : 'İşlem yapılamadı: $e', hata: true);
    } finally {
      if (mounted) setState(() => _islem = false);
    }
  }

  Future<void> _sil(Fabrika f) => _calistir((repo) async {
        final n = await repo.hareketSayisi(f.id!);
        if (!mounted) return false;
        if (n > 0) {
          _mesaj('${f.ad}: $n kaydı (sevkiyat / ödeme) var, silinemez. Kullanmıyorsanız pasife alın.', hata: true);
          return false;
        }
        if (!await silmeOnayi(context, 'Fabrika silinsin mi?', '${f.ad} silinecek. Hiç kaydı olmadığı için hesap etkilenmez.')) {
          return false;
        }
        await repo.fabrikaSil(f.id!);
        return true;
      }, basariMesaji: 'Fabrika silindi');

  @override
  Widget build(BuildContext context) {
    final liste = ref.watch(fabrikalarProvider);
    final bakiyeler = ref.watch(fabrikaBakiyeleriProvider).valueOrNull ?? const <int, double>{};
    return Scaffold(
      backgroundColor: AppRenkler.arkaplan,
      appBar: AppBar(title: const Text('Fabrikalar')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_fabrika',
        onPressed: _islem
            ? null
            : () => _calistir((repo) async => await fabrikaPenceresi(context, repo: repo) == true, basariMesaji: 'Fabrika eklendi ✓'),
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Fabrika ekle'),
      ),
      body: liste.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Yüklenemedi: $e', style: const TextStyle(color: AppRenkler.hata))),
        data: (fabrikalar) => fabrikalar.isEmpty
            ? const Center(
                child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Henüz fabrika yok. Sütü teslim ettiğiniz fabrikayı ekleyin.', textAlign: TextAlign.center),
              ))
            : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
                for (final f in fabrikalar)
                  Card(
                    child: ListTile(
                      onTap: _islem
                          ? null
                          : () => _calistir((repo) async => await fabrikaPenceresi(context, repo: repo, mevcut: f) == true,
                              basariMesaji: 'Güncellendi ✓'),
                      leading: Icon(Icons.factory_outlined, color: f.aktif ? AppRenkler.birincil : AppRenkler.metinIpucu),
                      title: Text(f.aktif ? f.ad : '${f.ad} (pasif)',
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text([
                        'Bakiye: ${_para.format(bakiyeler[f.id] ?? 0)}',
                        if (f.telefon != null) f.telefon!,
                      ].join(' · ')),
                      trailing: PopupMenuButton<String>(
                        enabled: !_islem,
                        onSelected: (v) {
                          if (v == 'durum') {
                            _calistir((repo) async {
                              await repo.fabrikaGuncelle(f.copyWith(aktif: !f.aktif));
                              return true;
                            }, basariMesaji: f.aktif ? '${f.ad} pasife alındı' : '${f.ad} yeniden aktif');
                          } else if (v == 'sil') {
                            _sil(f);
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'durum', child: Text(f.aktif ? 'Pasife al' : 'Aktif yap')),
                          const PopupMenuItem(value: 'sil', child: Text('Sil')),
                        ],
                      ),
                    ),
                  ),
              ]),
      ),
    );
  }
}
