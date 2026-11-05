import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/repository_providers.dart';
import '../core/providers/veri_surumu_provider.dart';
import '../models/cari_model.dart';
import 'cari/cari_form.dart';

/// Yeni cari. Süt toplama sırası varsayılan olarak rotanın sonu; 1 yazılırsa
/// en başa girer, o sıradaki ve sonrakiler birer kayar.
class CariEkle extends ConsumerStatefulWidget {
  const CariEkle({super.key});

  @override
  ConsumerState<CariEkle> createState() => _CariEkleState();
}

class _CariEkleState extends ConsumerState<CariEkle> {
  final _formKey = GlobalKey<FormState>();
  final _adController = TextEditingController();
  final _soyadController = TextEditingController();
  final _adresController = TextEditingController();
  final _telefonController = TextEditingController();
  final _siraController = TextEditingController();
  String _hayvanTuru = 'İnek';
  bool _kaydediliyor = false;

  @override
  void initState() {
    super.initState();
    _varsayilanSira();
  }

  /// Yeni cari varsayılan olarak rotanın sonuna (N+1) girer.
  Future<void> _varsayilanSira() async {
    try {
      final repo = await ref.read(cariRepositoryProvider.future);
      final n = await repo.rotadakiSayi();
      if (mounted && _siraController.text.isEmpty) _siraController.text = '${n + 1}';
    } catch (_) {/* alan boş kalır → sırasız */}
  }

  @override
  void dispose() {
    _adController.dispose();
    _soyadController.dispose();
    _adresController.dispose();
    _telefonController.dispose();
    _siraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        title: const Text('Yeni Cari Ekle'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.blue[800],
        elevation: 0,
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CariBolumKarti(
                baslik: 'Kişisel Bilgiler',
                ikon: Icons.person_outline,
                child: Column(
                  children: [
                    CariMetinAlani(
                      controller: _adController,
                      etiket: 'Ad',
                      ikon: Icons.person_outline,
                      buyukHarf: TextCapitalization.characters,
                      dogrula: (v) => zorunlu(v, 'Ad'),
                    ),
                    const SizedBox(height: 12),
                    CariMetinAlani(
                      controller: _soyadController,
                      etiket: 'Soyad',
                      ikon: Icons.badge_outlined,
                      buyukHarf: TextCapitalization.characters,
                      dogrula: (v) => zorunlu(v, 'Soyad'),
                    ),
                    const SizedBox(height: 12),
                    CariMetinAlani(
                      controller: _telefonController,
                      etiket: 'Telefon',
                      ikon: Icons.phone_outlined,
                      klavye: TextInputType.phone,
                      ipucu: '05xx xxx xx xx',
                    ),
                    const SizedBox(height: 12),
                    CariMetinAlani(
                      controller: _adresController,
                      etiket: 'Adres / Köy',
                      ikon: Icons.location_on_outlined,
                      satir: 2,
                    ),
                  ],
                ),
              ),
              CariBolumKarti(
                baslik: 'Hayvan Türü',
                ikon: Icons.pets_outlined,
                child: HayvanTuruSecici(secili: _hayvanTuru, onSecildi: (v) => setState(() => _hayvanTuru = v)),
              ),
              CariBolumKarti(
                baslik: 'Süt Toplama Sırası',
                ikon: Icons.route_outlined,
                aciklama: 'Süt toplarken uğradığınız sıra. Süt, Yem ve Hızlı Giriş listeleri bu sırayla dizilir.',
                child: RotaSirasiAlani(controller: _siraController),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _kaydediliyor ? null : _cariKaydet,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[700],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: _kaydediliyor
                      ? const SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.person_add),
                  label: const Text('Cari Kaydet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
          ),
        ),
      ),
    );
  }

  Future<void> _cariKaydet() async {
    if (_kaydediliyor) return; // çift dokunma: aynı cari iki kez eklenmesin
    if (!_formKey.currentState!.validate()) return;
    setState(() => _kaydediliyor = true);

    try {
      final yeniCari = Cari(
        ad: _adController.text.trim(),
        soyad: _soyadController.text.trim(),
        adres: _adresController.text.trim(),
        telefon: _telefonController.text.trim(),
        hayvanTuru: _hayvanTuru,
      );
      final repo = await ref.read(cariRepositoryProvider.future);

      // Aynı ad-soyadla ikinci cari açılırsa süt/yem yanlış kişiye yazılabilir.
      final ayniIsim = await ayniIsimliCariler(repo, yeniCari.ad, yeniCari.soyad);
      if (ayniIsim.isNotEmpty) {
        if (!mounted) return;
        final devam = await ayniIsimOnayi(context, yeniCari.tamAd, ayniIsim,
            soru: 'Yine de YENİ bir cari olarak eklensin mi?', dugme: 'Yine de Ekle');
        if (!devam) {
          if (mounted) setState(() => _kaydediliyor = false);
          return;
        }
      }

      await repo.insert(yeniCari, sira: RotaSirasiAlani.siraOku(_siraController.text));
      ref.veriDegisti();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cari başarıyla eklendi'), backgroundColor: Colors.green),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _kaydediliyor = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $error'), backgroundColor: Colors.red),
      );
    }
  }
}
