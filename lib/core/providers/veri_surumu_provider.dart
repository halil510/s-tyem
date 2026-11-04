import 'dart:async';

import 'package:flutter/material.dart' show DateUtils;
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

/// Bugünün tarihi (saatsiz). Gün değişince (gece yarısı ya da telefon sabah
/// arka plandan açılınca) yeni değer yayar. [AnaEkran] bunu dinleyip
/// [veriDegisti] çağırır → Özet'teki "Bugün", Cariler'deki "bu ay" gibi
/// hesaplar yenilenir. Eskiden uygulama gece açık kalırsa sabah Özet
/// DÜNÜN rakamlarını "Bugün" diye gösteriyordu.
final bugunProvider = StreamProvider<DateTime>((ref) {
  DateTime gun() => DateUtils.dateOnly(DateTime.now());
  var son = gun();
  final akis = StreamController<DateTime>();
  akis.add(son);
  final zamanlayici = Timer.periodic(const Duration(seconds: 30), (_) {
    final g = gun();
    if (g != son) {
      son = g;
      akis.add(g);
    }
  });
  // Zamanlayıcı sağlayıcıyla birlikte HEMEN durur (async* + await for
  // iptalde bir sonraki 30 sn'lik olaya kadar asılı kalıyordu).
  ref.onDispose(() {
    zamanlayici.cancel();
    akis.close();
  });
  return akis.stream;
});
