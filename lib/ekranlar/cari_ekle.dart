import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/cari_model.dart';
import '../core/providers/repository_providers.dart';
import '../core/providers/veri_surumu_provider.dart';
import '../utils/turkce.dart';

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
  String _hayvanTuru = 'İnek';
  bool _kaydediliyor = false;

  final List<Map<String, dynamic>> _hayvanSecenekleri = [
    {'value': 'İnek', 'icon': Icons.agriculture, 'color': Colors.blue},
    {'value': 'Koyun', 'icon': Icons.pets, 'color': Colors.green},
    {'value': 'Tavuk', 'icon': Icons.egg, 'color': Colors.orange},
  ];

  @override
  void dispose() {
    _adController.dispose();
    _soyadController.dispose();
    _adresController.dispose();
    _telefonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yeni Cari Ekle'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.blue[800],
        elevation: 0,
        actions: [
          if (_kaydediliyor)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBaslik(),
                const SizedBox(height: 32),
                _buildKisiselBilgiler(),
                const SizedBox(height: 24),
                _buildHayvanTurleri(),
                const SizedBox(height: 32),
                _buildKaydetButonu(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBaslik() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.person_add, color: Colors.blue[700]),
        ),
        const SizedBox(height: 16),
        Text(
          'Yeni Cari Ekle',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.blue[800],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Cari bilgilerini eksiksiz doldurun',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildKisiselBilgiler() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Kişisel Bilgiler',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.grey[800],
          ),
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _adController,
          label: 'Ad',
          icon: Icons.person_outline,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Ad zorunludur';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _soyadController,
          label: 'Soyad',
          icon: Icons.person_outline,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Soyad zorunludur';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _telefonController,
          label: 'Telefon',
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _adresController,
          label: 'Adres',
          icon: Icons.location_on_outlined,
          maxLines: 3,
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.grey[600]),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[400]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.blue[700]!, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[50],
      ),
    );
  }

  Widget _buildHayvanTurleri() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hayvan Türü',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.grey[800],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _hayvanSecenekleri.map((secenek) {
            final secili = _hayvanTuru == secenek['value'];
            return GestureDetector(
              onTap: () => setState(() => _hayvanTuru = secenek['value']),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: secili ? secenek['color'].withOpacity(0.1) : Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: secili ? secenek['color'] : Colors.grey[300]!,
                    width: secili ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      secenek['icon'],
                      color: secili ? secenek['color'] : Colors.grey[600],
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      secenek['value'],
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: secili ? secenek['color'] : Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildKaydetButonu() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _kaydediliyor ? null : _cariKaydet,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue[700],
          foregroundColor: Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        child: _kaydediliyor
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : const Text(
                'Cari Kaydet',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  Future<void> _cariKaydet() async {
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
      String anahtar(String ad, String soyad) =>
          turkceKucuk('$ad $soyad'.trim().replaceAll(RegExp(r'\s+'), ' '));
      final ayniIsim = (await repo.getAll())
          .where((c) => anahtar(c.ad, c.soyad) == anahtar(yeniCari.ad, yeniCari.soyad))
          .toList();
      if (ayniIsim.isNotEmpty) {
        if (!mounted) return;
        final devam = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Aynı isimde cari var'),
            content: Text(
              '"${yeniCari.tamAd}" adında ${ayniIsim.length} cari zaten kayıtlı'
              '${ayniIsim.any((c) => !c.aktif) ? ' (pasif olabilir)' : ''}.\n\n'
              'Yine de YENİ bir cari olarak eklensin mi?',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yine de Ekle')),
            ],
          ),
        );
        if (devam != true) {
          if (mounted) setState(() => _kaydediliyor = false);
          return;
        }
      }

      await repo.insert(yeniCari);
      ref.veriDegisti();

      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Cari başarıyla eklendi'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );

      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _kaydediliyor = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hata: $error'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}