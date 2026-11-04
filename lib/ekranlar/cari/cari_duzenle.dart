import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/providers/veri_surumu_provider.dart';
import '../../models/cari_model.dart';

/// Cari düzenleme sayfası. Formda olmayan alanlar (aktif, not) korunur.
class CariDuzenle extends ConsumerStatefulWidget {
  final Cari cari;
  const CariDuzenle({required this.cari, super.key});

  @override
  ConsumerState<CariDuzenle> createState() => _CariDuzenleState();
}

class _CariDuzenleState extends ConsumerState<CariDuzenle> {
  final _formKey = GlobalKey<FormState>();
  final _adController = TextEditingController();
  final _soyadController = TextEditingController();
  final _adresController = TextEditingController();
  final _telefonController = TextEditingController();
  String _hayvanTuru = 'İnek';
  bool _kaydediliyor = false;

  @override
  void initState() {
    super.initState();
    _adController.text = widget.cari.ad;
    _soyadController.text = widget.cari.soyad;
    _adresController.text = widget.cari.adres ?? '';
    _telefonController.text = widget.cari.telefon ?? '';
    _hayvanTuru = widget.cari.hayvanTuru ?? 'İnek';
  }

  @override
  void dispose() {
    _adController.dispose();
    _soyadController.dispose();
    _adresController.dispose();
    _telefonController.dispose();
    super.dispose();
  }

  Future<void> _cariGuncelle() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _kaydediliyor = true);

    try {
      final guncellenenCari = Cari(
        id: widget.cari.id,
        ad: _adController.text.trim(),
        soyad: _soyadController.text.trim(),
        adres: _adresController.text.trim(),
        telefon: _telefonController.text.trim(),
        hayvanTuru: _hayvanTuru,
        // Formda olmayan alanlar korunur; aksi halde her düzenlemede
        // carinin notu silinir ve pasif durumu sıfırlanırdı.
        aktif: widget.cari.aktif,
        notMetni: widget.cari.notMetni,
      );

      final repo = await ref.read(cariRepositoryProvider.future);
      await repo.update(guncellenenCari);
      ref.veriDegisti();

      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cari başarıyla güncellendi')),
      );

      Navigator.pop(context, true);
    } catch (error) {
      setState(() => _kaydediliyor = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cari Düzenle'),
        actions: [
          if (_kaydediliyor)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: CircularProgressIndicator(),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _adController,
                decoration: const InputDecoration(labelText: 'Ad'),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Ad zorunludur';
                  return null;
                },
              ),
              TextFormField(
                controller: _soyadController,
                decoration: const InputDecoration(labelText: 'Soyad'),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Soyad zorunludur';
                  return null;
                },
              ),
              TextFormField(
                controller: _telefonController,
                decoration: const InputDecoration(labelText: 'Telefon'),
              ),
              TextFormField(
                controller: _adresController,
                decoration: const InputDecoration(labelText: 'Adres'),
                maxLines: 3,
              ),
              DropdownButtonFormField<String>(
                value: _hayvanTuru,
                items: ['İnek', 'Koyun', 'Tavuk'].map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (value) => setState(() => _hayvanTuru = value!),
                decoration: const InputDecoration(labelText: 'Hayvan Türü'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _kaydediliyor ? null : _cariGuncelle,
                child: _kaydediliyor 
                    ? const CircularProgressIndicator()
                    : const Text('Güncelle'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}