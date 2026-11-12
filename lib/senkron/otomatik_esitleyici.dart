import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/database_provider.dart';
import '../core/providers/veri_surumu_provider.dart';
import 'senkron_yoneticisi.dart';

/// Ana ekranı sarar: açılışta senkronu başlatır (bulut / yerel ağ ayarlıysa dakikada bir
/// eşitler), uygulama öne gelince ve arka plana geçerken (telefon kilitlenmeden önce
/// değişiklikler gitsin) eşitler. Başka cihazdan veri gelince tüm ekranlar yenilenir.
/// Hata uygulamayı durdurmaz. Testlerde çalışmaz.
class OtomatikEsitleyici extends ConsumerStatefulWidget {
  final Widget child;
  const OtomatikEsitleyici({super.key, required this.child});

  @override
  ConsumerState<OtomatikEsitleyici> createState() => _OtomatikEsitleyiciState();
}

class _OtomatikEsitleyiciState extends ConsumerState<OtomatikEsitleyici> with WidgetsBindingObserver {
  static final _testte = Platform.environment.containsKey('FLUTTER_TEST');

  @override
  void initState() {
    super.initState();
    if (_testte) return;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _baslat());
  }

  Future<void> _baslat() async {
    try {
      final db = await ref.read(databaseProvider.future);
      SenkronYoneticisi().veriGeldi = () {
        if (mounted) ref.veriDegisti();
      };
      await SenkronYoneticisi().baslat(db);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _baslat().then((_) => SenkronYoneticisi().otomatikEsitle());
    } else if (state == AppLifecycleState.paused) {
      SenkronYoneticisi().otomatikEsitle();
    }
  }

  @override
  void dispose() {
    if (!_testte) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
