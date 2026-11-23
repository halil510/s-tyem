import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/providers/veri_surumu_provider.dart';
import '../../models/urun_model.dart';

/// Tüm ürünler (aktif + pasif), ekran sırasıyla. Ürün eklenince / değişince
/// `veriDegisti` → yeniden okunur (Yem sekmesi IndexedStack'te açık kalır).
final urunlerProvider = FutureProvider<List<Urun>>((ref) async {
  ref.watch(veriSurumuProvider);
  final repo = await ref.watch(urunRepositoryProvider.future);
  return repo.getAll();
});

/// Yalnız aktif ürünler: Yem Ekle ve Yem Fiyatları ekranları.
final aktifUrunlerProvider = FutureProvider<List<Urun>>((ref) async {
  final hepsi = await ref.watch(urunlerProvider.future);
  return hepsi.where((u) => u.aktif).toList();
});

/// id → ürün (pasifler dahil; geçmiş kayıtların adını göstermek için).
final urunHaritasiProvider = FutureProvider<Map<int, Urun>>((ref) async {
  final hepsi = await ref.watch(urunlerProvider.future);
  return {for (final u in hepsi) u.id!: u};
});
