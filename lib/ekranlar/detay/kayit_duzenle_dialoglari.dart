import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/providers/veri_surumu_provider.dart';
import '../../models/sut_model.dart';
import '../../models/yem_model.dart';
import '../../utils/sayi_format.dart';

/// Detay ekranındaki süt/yem kaydı düzenleme diyalogları.
/// Geçersiz miktar 0 olarak kaydedilmez, kullanıcıya hata gösterilir.

/// Tüm miktarlar 0 yapıldıysa: boş satır bırakmak yerine kaydı silmeyi sorar.
Future<bool?> _sifirSilOnayi(BuildContext context, String tur) => showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Miktar 0'),
        content: Text('Tüm miktarlar 0. Bu $tur kaydı silinsin mi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

class SutDuzenleDialog extends ConsumerStatefulWidget {
  final Sut sut;
  const SutDuzenleDialog({required this.sut, super.key});

  @override
  ConsumerState<SutDuzenleDialog> createState() => _SutDuzenleDialogState();
}

class _SutDuzenleDialogState extends ConsumerState<SutDuzenleDialog> {
  final _sabahController = TextEditingController();
  final _aksamController = TextEditingController();
  bool _kaydediliyor = false;

  // Virgül/nokta dönüşümü
  /// Geçersiz girişte 0 yerine hata fırlatır — hatalı yazım sessizce
  /// "0 kg" olarak kaydedilmesin.
  double _parseYerelSayi(String girdi) {
    final deger = sayiCoz(girdi);
    if (deger == null) throw FormatException('Geçersiz miktar: "$girdi"');
    return deger;
  }

  @override
  void initState() {
    super.initState();
    _sabahController.text = sayiGirdi(widget.sut.sabah);
    _aksamController.text = sayiGirdi(widget.sut.aksam);
  }

  @override
  void dispose() {
    _sabahController.dispose();
    _aksamController.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    if (_kaydediliyor) return;

    setState(() => _kaydediliyor = true);

    try {
      final sabah = _parseYerelSayi(_sabahController.text);
      final aksam = _parseYerelSayi(_aksamController.text);

      final guncellenenSut = Sut(
        id: widget.sut.id,
        cariId: widget.sut.cariId,
        tarih: widget.sut.tarih,
        sabah: sabah,
        aksam: aksam,
      );

      final repo = await ref.read(sutRepositoryProvider.future);
      if (sabah == 0 && aksam == 0) {
        // 0 kg'lık boş satır bırakma: kaydı silmeyi öner.
        if (!mounted || await _sifirSilOnayi(context, 'süt') != true) return;
        await repo.delete(widget.sut.id!);
      } else {
        await repo.update(guncellenenSut);
      }
      ref.veriDegisti();

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is FormatException ? e.message : 'Hata: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _kaydediliyor = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Süt Kaydını Düzenle'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Tarih: ${DateFormat('dd.MM.yyyy', 'tr_TR').format(DateTime.parse(widget.sut.tarih))}'),
          const SizedBox(height: 16),
          TextField(
            controller: _sabahController,
            decoration: const InputDecoration(
              labelText: 'Sabah (kg)',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _aksamController,
            decoration: const InputDecoration(
              labelText: 'Akşam (kg)',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.numberWithOptions(decimal: true),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _kaydediliyor ? null : () => Navigator.pop(context, false),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          onPressed: _kaydediliyor ? null : _kaydet,
          child: _kaydediliyor
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Kaydet'),
        ),
      ],
    );
  }
}

// Yem Düzenleme Dialog (virgül/nokta desteği)
class YemDuzenleDialog extends ConsumerStatefulWidget {
  final Yem yem;
  const YemDuzenleDialog({required this.yem, super.key});

  @override
  ConsumerState<YemDuzenleDialog> createState() => _YemDuzenleDialogState();
}

class _YemDuzenleDialogState extends ConsumerState<YemDuzenleDialog> {
  final _sutController = TextEditingController();
  final _besiController = TextEditingController();
  final _bBasController = TextEditingController();
  final _bBuyController = TextEditingController();
  final _kuzuController = TextEditingController();
  final _tavukController = TextEditingController();
  bool _kaydediliyor = false;

  /// Geçersiz girişte 0 yerine hata fırlatır — hatalı yazım sessizce
  /// "0 kg" olarak kaydedilmesin.
  double _parseYerelSayi(String girdi) {
    final deger = sayiCoz(girdi);
    if (deger == null) throw FormatException('Geçersiz miktar: "$girdi"');
    return deger;
  }

  @override
  void initState() {
    super.initState();
    _sutController.text = sayiGirdi(widget.yem.sutYemi);
    _besiController.text = sayiGirdi(widget.yem.besiYemi);
    _bBasController.text = sayiGirdi(widget.yem.bBaslangic);
    _bBuyController.text = sayiGirdi(widget.yem.bBuyutme);
    _kuzuController.text = sayiGirdi(widget.yem.kuzuYemi);
    _tavukController.text = sayiGirdi(widget.yem.tavukYemi);
  }

  @override
  void dispose() {
    _sutController.dispose();
    _besiController.dispose();
    _bBasController.dispose();
    _bBuyController.dispose();
    _kuzuController.dispose();
    _tavukController.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    if (_kaydediliyor) return;

    setState(() => _kaydediliyor = true);

    try {
      final guncellenenYem = Yem(
        id: widget.yem.id,
        cariId: widget.yem.cariId,
        tarih: widget.yem.tarih,
        sutYemi: _parseYerelSayi(_sutController.text),
        besiYemi: _parseYerelSayi(_besiController.text),
        bBaslangic: _parseYerelSayi(_bBasController.text),
        bBuyutme: _parseYerelSayi(_bBuyController.text),
        kuzuYemi: _parseYerelSayi(_kuzuController.text),
        tavukYemi: _parseYerelSayi(_tavukController.text),
      );

      final repo = await ref.read(yemRepositoryProvider.future);
      if (guncellenenYem.toplam == 0) {
        if (!mounted || await _sifirSilOnayi(context, 'yem') != true) return;
        await repo.delete(widget.yem.id!);
      } else {
        await repo.update(guncellenenYem);
      }
      ref.veriDegisti();

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is FormatException ? e.message : 'Hata: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _kaydediliyor = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Yem Kaydını Düzenle'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Tarih: ${DateFormat('dd.MM.yyyy', 'tr_TR').format(DateTime.parse(widget.yem.tarih))}'),
            const SizedBox(height: 16),
            TextField(
              controller: _sutController,
              decoration: const InputDecoration(
                labelText: 'Süt Yemi (kg)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _besiController,
              decoration: const InputDecoration(
                labelText: 'Besi Yemi (kg)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _bBasController,
              decoration: const InputDecoration(
                labelText: 'B. Başlangıç (kg)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _bBuyController,
              decoration: const InputDecoration(
                labelText: 'B. Büyütme (kg)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _kuzuController,
              decoration: const InputDecoration(
                labelText: 'Kuzu Yemi (kg)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _tavukController,
              decoration: const InputDecoration(
                labelText: 'Tavuk Yemi (kg)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _kaydediliyor ? null : () => Navigator.pop(context, false),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          onPressed: _kaydediliyor ? null : _kaydet,
          child: _kaydediliyor
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Kaydet'),
        ),
      ],
    );
  }
}