import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/cari/providers/cari_providers.dart';
import '../utils/turkce.dart';
import 'package:go_router/go_router.dart';

import '../models/cari_model.dart';
import '../core/router/app_router.dart';
import '../features/cari_hesap/providers/cari_hesap_providers.dart';

/// "Ödemeler" sekmesi — tüm carilerin güncel (işaretli) bakiyesini listeler.
///
/// ─────────────────────────────────────────────────────────────
/// İŞ MANTIĞI: bakiye pozitifse cari ALACAKLI'dır (işletme cariye
/// borçludur — süt bedeli ödenecektir). Bakiye negatifse cari
/// BORÇLU'dur (cari işletmeye borçludur — yem/nakit borcu tahsil
/// edilecektir). Bkz. `CariOdemeRepository` doc yorumu.
/// ─────────────────────────────────────────────────────────────
class OdeEkrani extends ConsumerStatefulWidget {
  const OdeEkrani({super.key});

  @override
  ConsumerState<OdeEkrani> createState() => _OdeEkraniState();
}

class _OdeEkraniState extends ConsumerState<OdeEkrani> {
  String _aramaMetni = '';
  final TextEditingController _aramaController = TextEditingController();

  @override
  void dispose() {
    _aramaController.dispose();
    super.dispose();
  }

  List<Cari> _filtreUygula(List<Cari> hepsi) {
    return hepsi.where((c) => aramaEslesir(c.tamAd, _aramaMetni)).toList();
  }

  @override
  Widget build(BuildContext context) {
    // Eskiden her yeniden çizimde veritabanına yeni sorgu atılıyordu (titreme);
    // artık veri değişince kendiliğinden yenilenen ortak provider.
    final carilerAsync = ref.watch(butunCarilerProvider);
    final bakiyelerAsync = ref.watch(tumKalanBorclarProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      body: Builder(
        builder: (context) {
          if (carilerAsync.hasError) {
            return Center(child: Text('Hata: ${carilerAsync.error}'));
          }
          if (!carilerAsync.hasValue) {
            return const Center(child: CircularProgressIndicator());
          }
          final hepsi = carilerAsync.value!;

          return bakiyelerAsync.when(
            data: (bakiyeler) {
              // Pasif cari listede yalnız açık bakiyesi varsa görünür — aksi halde
              // üstteki toplamda sayılıp listede bulunmuyordu (ödeme yapılamıyordu).
              final cariler = hepsi
                  .where((c) => c.aktif || ((bakiyeler[c.id] ?? 0).abs() >= 0.005))
                  .toList();
              final filtrelenen = _filtreUygula(cariler);
              // Kayan nokta yuvarlama hatalarını tolere etmek için 1 kuruşluk
              // eşik — kart gösterimindeki (Hesap Kapalı) mantıkla tutarlı
              // olması için burada da aynı tolerans kullanılıyor.
              const epsilon = 0.005;
              // Alacaklı cariler için toplam (işletmenin ödeyeceği tutar)
              final toplamAlacak = bakiyeler.values.fold(0.0, (s, v) => s + (v > epsilon ? v : 0));
              // Borçlu cariler için toplam (işletmenin tahsil edeceği tutar)
              final toplamBorc = bakiyeler.values.fold(0.0, (s, v) => s + (v < -epsilon ? -v : 0));
              final alacakliSayisi = bakiyeler.values.where((v) => v > epsilon).length;
              final borcluSayisi = bakiyeler.values.where((v) => v < -epsilon).length;

              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(tumKalanBorclarProvider),
                // Özet + arama listeyle birlikte kayar (yatay telefonda / büyük
                // yazıda eskiden liste alanı kalmıyor, taşıyordu).
                child: NestedScrollView(
                  headerSliverBuilder: (context, _) => [
                    SliverToBoxAdapter(
                      child: Column(
                        children: [
                    _OzetKarti(
                      toplamAlacak: toplamAlacak,
                      toplamBorc: toplamBorc,
                      alacakliSayisi: alacakliSayisi,
                      borcluSayisi: borcluSayisi,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))],
                        ),
                        child: TextField(
                          controller: _aramaController,
                          decoration: InputDecoration(
                            hintText: 'Cari ara...',
                            prefixIcon: const Icon(Icons.search, color: Colors.grey),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            suffixIcon: _aramaMetni.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, color: Colors.grey),
                                    onPressed: () {
                                      _aramaController.clear();
                                      setState(() => _aramaMetni = '');
                                    },
                                  )
                                : null,
                          ),
                          onChanged: (v) => setState(() => _aramaMetni = v),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text('Cari Hesapları',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                          ),
                          Text('${filtrelenen.length} cari', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                        ],
                      ),
                    ),
                        ],
                      ),
                    ),
                  ],
                  body: filtrelenen.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.account_balance_wallet_outlined, size: 64, color: Colors.grey[300]),
                                  const SizedBox(height: 16),
                                  Text('Cari bulunamadı', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              itemCount: filtrelenen.length,
                              itemBuilder: (ctx, i) {
                                final cari = filtrelenen[i];
                                final bakiye = bakiyeler[cari.id] ?? 0.0;
                                return _CariOdemeKarti(
                                  cari: cari,
                                  bakiye: bakiye,
                                  onTap: () => context.push(AppRoutes.cariHesap, extra: cari),
                                );
                              },
                            ),
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Hata: $e')),
          );
        },
      ),
    );
  }
}

class _OzetKarti extends StatelessWidget {
  final double toplamAlacak;
  final double toplamBorc;
  final int alacakliSayisi;
  final int borcluSayisi;

  const _OzetKarti({
    required this.toplamAlacak,
    required this.toplamBorc,
    required this.alacakliSayisi,
    required this.borcluSayisi,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D47A1), Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: const Color(0xFF0D47A1).withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Ödenecek (Alacaklı)', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 4),
                Text('${toplamAlacak.toStringAsFixed(2)} ₺',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                Text('$alacakliSayisi cari', style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
          ),
          Container(width: 1, height: 48, color: Colors.white24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tahsil Edilecek (Borçlu)', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 4),
                Text('${toplamBorc.toStringAsFixed(2)} ₺',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                Text('$borcluSayisi cari', style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CariOdemeKarti extends StatelessWidget {
  final Cari cari;
  /// İşaretli bakiye: pozitif = cari alacaklı, negatif = cari borçlu.
  final double bakiye;
  final VoidCallback onTap;

  const _CariOdemeKarti({required this.cari, required this.bakiye, required this.onTap});

  IconData _hayvanIkonu(String? tur) {
    switch (tur) {
      case 'İnek': return Icons.agriculture;
      case 'Koyun': return Icons.pets;
      case 'Tavuk': return Icons.egg;
      default: return Icons.pets;
    }
  }

  Color _hayvanRengi(String? tur) {
    switch (tur) {
      case 'İnek': return Colors.blue;
      case 'Koyun': return Colors.green;
      case 'Tavuk': return Colors.orange;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Kayan nokta yuvarlama hatalarını tolere etmek için 1 kuruşluk eşik
    // (bkz. CariHesapOzeti.hesapKapaliMi ile aynı mantık).
    const epsilon = 0.005;
    final alacakliMi = bakiye > epsilon;
    final borcluMu = bakiye < -epsilon;

    // Alacaklı (işletme borçlu) → mavi. Borçlu (cari borçlu) → turuncu.
    final durumRenk = alacakliMi
        ? const Color(0xFF0D47A1)
        : (borcluMu ? const Color(0xFFE65100) : Colors.grey);
    final bgRenk = alacakliMi
        ? const Color(0xFFE3F2FD)
        : (borcluMu ? const Color(0xFFFFF3E0) : const Color(0xFFF5F5F5));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: alacakliMi ? Border.all(color: const Color(0xFF90CAF9), width: 1) : null,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: _hayvanRengi(cari.hayvanTuru).withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(_hayvanIkonu(cari.hayvanTuru), color: _hayvanRengi(cari.hayvanTuru), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cari.aktif ? cari.tamAd : '${cari.tamAd} (pasif)',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(cari.hayvanTuru ?? 'Belirtilmemiş', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                  ],
                ),
              ),
              // Büyük bakiye dar ekranda taşmasın: kesilmez, gerekirse küçülür.
              Flexible(flex: 2, child: FittedBox(fit: BoxFit.scaleDown, child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: bgRenk, borderRadius: BorderRadius.circular(10)),
                    child: Text(
                      bakiye.abs() <= epsilon ? 'Hesap Kapalı' : '${bakiye.abs().toStringAsFixed(2)} ₺',
                      style: TextStyle(color: durumRenk, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(alacakliMi ? 'Alacaklı' : (borcluMu ? 'Borçlu' : 'Temiz'), style: TextStyle(fontSize: 10, color: durumRenk)),
                ],
              ))),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: Colors.grey[400], size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
