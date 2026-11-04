import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../../core/providers/repository_providers.dart';
import '../../../models/terazi_cihaz_model.dart';
import '../services/terazi_service_pro.dart';
import '../services/terazi_baglanti_durumu.dart';

/// Uygulama genelinde tek bir [TeraziServicePro] örneği.
/// Veritabanı (dolayısıyla cihaz repository'si) hazır olduğunda kurulur.
final teraziServiceProvider = FutureProvider<TeraziServicePro>((ref) async {
  final cihazRepo = await ref.watch(teraziCihazRepositoryProvider.future);
  final servis = TeraziServicePro(cihazRepo);
  ref.onDispose(servis.dispose);
  return servis;
});

/// Anlık bağlantı durumu (bağlı / bağlanıyor / hata / vs.).
final teraziDurumStreamProvider = StreamProvider<TeraziBaglantiDurumu>((ref) async* {
  final servis = await ref.watch(teraziServiceProvider.future);
  yield servis.durum;
  yield* servis.durumStream;
});

/// Anlık ağırlık okuması (ham string, örn. "12.45").
final teraziAgirlikStreamProvider = StreamProvider<String>((ref) async* {
  final servis = await ref.watch(teraziServiceProvider.future);
  yield* servis.agirlikStream;
});

/// Kayıtlı tüm terazi cihazları (geçmiş bağlantılar).
final kayitliTeraziCihazlariProvider = FutureProvider<List<TeraziCihazi>>((ref) async {
  final repo = await ref.watch(teraziCihazRepositoryProvider.future);
  return repo.getAll();
});

/// ─────────────────────────────────────────────────────────────
/// TERAZİ BAĞLANTI NOTIFIER — ekranların çağırdığı eylemler
/// ─────────────────────────────────────────────────────────────
class TeraziBaglantiNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<List<BluetoothDevice>> bleTara() async {
    final servis = await ref.read(teraziServiceProvider.future);
    return servis.bleTara();
  }

  Future<void> bleyeBagla(BluetoothDevice device) async {
    final servis = await ref.read(teraziServiceProvider.future);
    await servis.bleyeBagla(device);
    ref.invalidate(kayitliTeraziCihazlariProvider);
  }

  Future<void> classicBagla(String address, {String? cihazAdi}) async {
    final servis = await ref.read(teraziServiceProvider.future);
    await servis.classicBagla(address, cihazAdi: cihazAdi);
    ref.invalidate(kayitliTeraziCihazlariProvider);
  }

  Future<void> wifiBagla(String ip, int port) async {
    final servis = await ref.read(teraziServiceProvider.future);
    await servis.wifiBagla(ip, port);
    ref.invalidate(kayitliTeraziCihazlariProvider);
  }

  Future<void> baglantiyiKes() async {
    final servis = await ref.read(teraziServiceProvider.future);
    await servis.baglantiyiKes();
  }

  /// Uygulama açılışında kayıtlı varsayılan cihaza otomatik bağlanmayı
  /// dener (BLE dahil — bkz. TeraziServicePro.baslangicOtomatikBaglan
  /// doc yorumu).
  Future<bool> baslangicOtomatikBaglan() async {
    final servis = await ref.read(teraziServiceProvider.future);
    return servis.baslangicOtomatikBaglan();
  }

  Future<void> varsayilanYap(int cihazId) async {
    final repo = await ref.read(teraziCihazRepositoryProvider.future);
    await repo.varsayilanYap(cihazId);
    ref.invalidate(kayitliTeraziCihazlariProvider);
  }

  Future<void> cihaziSil(int cihazId) async {
    final repo = await ref.read(teraziCihazRepositoryProvider.future);
    await repo.sil(cihazId);
    ref.invalidate(kayitliTeraziCihazlariProvider);
  }
}

final teraziBaglantiNotifierProvider =
    AsyncNotifierProvider<TeraziBaglantiNotifier, void>(TeraziBaglantiNotifier.new);
