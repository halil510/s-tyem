import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../ekranlar/splash_ekrani.dart';
import '../../ekranlar/ana_ekran.dart';
import '../../ekranlar/app_activation_screen.dart';
import '../../models/cari_model.dart';
import '../../features/cari_hesap/screens/cari_hesap_ekstresi_ekrani.dart';
import '../../features/terazi/screens/terazi_baglanti_ekrani_pro.dart';

/// ─────────────────────────────────────────────────────────────
/// MERKEZİ ROUTER (go_router)
/// ─────────────────────────────────────────────────────────────
///
/// Eskiden `Navigator.push(MaterialPageRoute(...))` ile dağınık bir
/// şekilde yapılan ekran geçişleri, tek bir yerden tanımlanan,
/// isimlendirilmiş (named) route'lara taşındı. Böylece:
/// - Derin bağlantı (deep link) desteği eklemek kolaylaşır.
/// - Her ekrana nereden gidileceği tek bir dosyadan izlenebilir.
/// - `context.go('/terazi')` gibi kısa, tip güvenli çağrılarla gezinme
///   yapılabilir.
///
/// Yeni bir ekran eklemek için: bu dosyaya bir `GoRoute` ekle ve
/// [AppRoutes] içine yol sabitini tanımla.
class AppRoutes {
  static const splash = '/';
  static const activate = '/activate';
  static const main = '/main';
  static const cariHesap = '/cari-hesap';
  static const terazi = '/terazi';
}

final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.splash,
  routes: [
    GoRoute(
      path: AppRoutes.splash,
      builder: (context, state) => const SplashVeGuvenlik(),
    ),
    GoRoute(
      path: AppRoutes.activate,
      builder: (context, state) => const AppActivationScreen(),
    ),
    GoRoute(
      path: AppRoutes.main,
      builder: (context, state) => const AnaEkran(),
    ),
    GoRoute(
      path: AppRoutes.cariHesap,
      builder: (context, state) {
        final cari = state.extra as Cari;
        return CariHesapEkstresiEkrani(cari: cari);
      },
    ),
    GoRoute(
      path: AppRoutes.terazi,
      builder: (context, state) => const TeraziBaglantiEkraniPro(),
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: Center(child: Text('Sayfa bulunamadı: ${state.uri}')),
  ),
);
