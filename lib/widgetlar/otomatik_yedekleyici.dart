import 'dart:io';

import 'package:flutter/widgets.dart';

import '../data/yedek/otomatik_yedek.dart';

/// Uygulama açılınca ve arka plana geçince (ekran kilitlendi, başka
/// uygulamaya geçildi, şarj azaldı…) gerekiyorsa otomatik güvenlik yedeği
/// alır — en çok [OtomatikYedek.otomatikAralik]'ta bir. Hata uygulamayı
/// durdurmaz. Testlerde çalışmaz.
class OtomatikYedekleyici extends StatefulWidget {
  final Widget child;
  const OtomatikYedekleyici({super.key, required this.child});

  @override
  State<OtomatikYedekleyici> createState() => _OtomatikYedekleyiciState();
}

class _OtomatikYedekleyiciState extends State<OtomatikYedekleyici> with WidgetsBindingObserver {
  static final _testte = Platform.environment.containsKey('FLUTTER_TEST');

  @override
  void initState() {
    super.initState();
    if (_testte) return;
    WidgetsBinding.instance.addObserver(this);
    // Açılıştaki ekran çizimini geciktirmesin.
    Future.delayed(const Duration(seconds: 5), OtomatikYedek.gerekirseOtomatikAl);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) OtomatikYedek.gerekirseOtomatikAl();
  }

  @override
  void dispose() {
    if (!_testte) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
