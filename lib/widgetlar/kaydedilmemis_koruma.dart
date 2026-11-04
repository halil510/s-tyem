import 'package:flutter/material.dart';

/// Girilmiş ama KAYDEDİLMEMİŞ veri varken geri tuşu (cihaz ya da üst
/// çubuktaki ok) ekranı sessizce kapatmasın: "Kaydet / Kaydetmeden Çık /
/// Vazgeç" diye sorar. Değişiklik yoksa geri tuşu normal çalışır.
///
/// [dinle]: değişince [degisiklikVar] yeniden hesaplanacak alanlar
/// (genellikle `Listenable.merge(controller'lar)`).
/// [kaydet]: ekranın kendi kaydet işlemi; başarılı olursa ekranı kendisi
/// kapatır (Navigator.pop). Hatalı girişte ekran açık kalır, hata görünür.
class KaydedilmemisKoruma extends StatefulWidget {
  final Listenable dinle;
  final bool Function() degisiklikVar;
  final Future<void> Function() kaydet;
  final String baslik;
  final Widget child;

  const KaydedilmemisKoruma({
    super.key,
    required this.dinle,
    required this.degisiklikVar,
    required this.kaydet,
    required this.child,
    this.baslik = 'Kaydedilmemiş giriş var',
  });

  @override
  State<KaydedilmemisKoruma> createState() => _KaydedilmemisKorumaState();
}

class _KaydedilmemisKorumaState extends State<KaydedilmemisKoruma> {
  @override
  void initState() {
    super.initState();
    widget.dinle.addListener(_degisti);
  }

  @override
  void didUpdateWidget(KaydedilmemisKoruma eski) {
    super.didUpdateWidget(eski);
    if (eski.dinle != widget.dinle) {
      eski.dinle.removeListener(_degisti);
      widget.dinle.addListener(_degisti);
    }
  }

  @override
  void dispose() {
    widget.dinle.removeListener(_degisti);
    super.dispose();
  }

  void _degisti() {
    if (mounted) setState(() {});
  }

  Future<void> _sor() async {
    final secim = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.baslik),
        content: const Text('Girdiğiniz miktarlar henüz KAYDEDİLMEDİ. Çıkarsanız bu girişler kaybolur.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'vazgec'), child: const Text('Vazgeç')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cik'),
            child: const Text('Kaydetmeden Çık', style: TextStyle(color: Colors.red)),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'kaydet'), child: const Text('Kaydet')),
        ],
      ),
    );
    if (!mounted) return;
    switch (secim) {
      case 'kaydet':
        await widget.kaydet();
      case 'cik':
        Navigator.of(context).pop(); // PopScope'u atlar
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.degisiklikVar(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _sor();
      },
      child: widget.child,
    );
  }
}
