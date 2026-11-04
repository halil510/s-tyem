import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ─────────────────────────────────────────────────────────────
/// VERİ SÜRÜMÜ — hesaplanmış ekranları güncel tutan tek sinyal
/// ─────────────────────────────────────────────────────────────
///
/// Cari bakiyeleri (`tumKalanBorclarProvider`), cari ekstresi ve
/// dashboard verileri önbellekli `FutureProvider`'lardır. Eskiden süt,
/// yem ya da fiyat girildiğinde bu önbellekler GEÇERSİZ KILINMIYORDU:
/// müşteriye süt girildikten sonra Ödemeler sekmesi ve ana sayfa eski
/// bakiyeyi göstermeye devam ediyordu.
///
/// Artık bu provider'ların hepsi [veriSurumuProvider]'ı izler. Herhangi
/// bir hesabı etkileyen yazma işleminden sonra [veriDegisti] çağrılır;
/// sayaç artar ve izleyen tüm hesaplamalar yeniden yapılır.
final veriSurumuProvider = StateProvider<int>((ref) => 0);

/// Süt, yem, ödeme, fiyat veya cari kaydı değiştikten sonra çağrılır.
void veriDegisti(Ref ref) => ref.read(veriSurumuProvider.notifier).state++;

extension VeriDegistiWidgetRef on WidgetRef {
  /// Widget tarafından [veriDegisti] kısayolu.
  void veriDegisti() => read(veriSurumuProvider.notifier).state++;
}

/// Riverpod'a bağlı olmayan (düz `StatefulWidget`) ekranlar için:
/// yedek geri yükleme gibi toplu değişikliklerden sonra çağrılır.
void veriDegistiBildir(BuildContext context) =>
    ProviderScope.containerOf(context, listen: false).read(veriSurumuProvider.notifier).state++;
