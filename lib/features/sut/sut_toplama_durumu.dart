import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/providers/veri_surumu_provider.dart';
import '../../models/sut_model.dart';

/// Süt sekmesindeki "alındı" yeşil tiki (kullanıcı isteği 2026-11-05).
///
/// Tik AYRICA KAYDEDİLMEZ: bugünkü süt satırından hesaplanır.
/// - Saat [aksamBaslangicSaati]'nden önce → bugün SABAH sütü girilmiş cariye tik.
/// - Sonra → bugün AKŞAM sütü girilmiş cariye tik (sabah tikleri kendiliğinden "sıfırlanır").
/// - Ertesi gün yeni tarih → hepsi boş başlar.
/// Uygulama kapanıp açılsa da, şarj bitse de tik doğru kalır.
enum ToplamaOgunu { sabah, aksam }

/// Akşam toplamasının başladığı saat (12:00 ve sonrası akşam sayılır).
const aksamBaslangicSaati = 12;

ToplamaOgunu toplamaOgunu(DateTime an) =>
    an.hour < aksamBaslangicSaati ? ToplamaOgunu.sabah : ToplamaOgunu.aksam;

/// Bu öğünün kg'ı (kayıt yoksa 0).
double ogunKg(Sut? kayit, ToplamaOgunu ogun) =>
    kayit == null ? 0 : (ogun == ToplamaOgunu.sabah ? kayit.sabah : kayit.aksam);

bool ogunAlindi(Sut? kayit, ToplamaOgunu ogun) => ogunKg(kayit, ogun) > 0;

String ogunAdi(ToplamaOgunu ogun) => ogun == ToplamaOgunu.sabah ? 'Sabah' : 'Akşam';

String gunAnahtari(DateTime an) => DateFormat('yyyy-MM-dd').format(an);

/// Şu anki zaman — testte sabit saat verilebilsin diye provider.
final simdiProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Bir gündeki tüm carilerin süt satırları (cari id → kayıt). Süt girilince
/// [veriSurumuProvider] üzerinden kendiliğinden yenilenir.
final gunlukSutlerProvider = FutureProvider.family<Map<int, Sut>, String>((ref, tarih) async {
  ref.watch(veriSurumuProvider);
  final repo = await ref.watch(sutRepositoryProvider.future);
  return repo.getGunlukHepsi(tarih);
});
