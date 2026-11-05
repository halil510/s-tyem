import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/cari_repository.dart';
import '../../features/cari/providers/cari_providers.dart';
import '../../models/cari_model.dart';
import '../../utils/turkce.dart';

/// Cari Ekle ve Cari Düzenle'nin ORTAK form parçaları (aynı görünüm, aynı kurallar).

/// Başlıklı, beyaz bölüm kartı.
class CariBolumKarti extends StatelessWidget {
  final String baslik;
  final IconData ikon;
  final Widget child;
  final String? aciklama;
  const CariBolumKarti({super.key, required this.baslik, required this.ikon, required this.child, this.aciklama});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ikon, size: 18, color: Colors.blue[700]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(baslik, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ],
          ),
          if (aciklama != null) ...[
            const SizedBox(height: 4),
            Text(aciklama!, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
          const SizedBox(height: 14),
          // ListTile/Switch dokunma efekti en yakın Material'a çizilir; beyaz
          // kart onu gizlemesin.
          Material(type: MaterialType.transparency, child: child),
        ],
      ),
    );
  }
}

/// Ortak metin alanı.
class CariMetinAlani extends StatelessWidget {
  final TextEditingController controller;
  final String etiket;
  final IconData ikon;
  final TextInputType? klavye;
  final String? Function(String?)? dogrula;
  final int satir;
  final TextCapitalization buyukHarf;
  final String? ipucu;
  final Key? alanKey;

  const CariMetinAlani({
    super.key,
    required this.controller,
    required this.etiket,
    required this.ikon,
    this.klavye,
    this.dogrula,
    this.satir = 1,
    this.buyukHarf = TextCapitalization.none,
    this.ipucu,
    this.alanKey,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: alanKey,
      controller: controller,
      keyboardType: klavye,
      validator: dogrula,
      maxLines: satir,
      textCapitalization: buyukHarf,
      decoration: InputDecoration(
        labelText: etiket,
        hintText: ipucu,
        prefixIcon: Icon(ikon, color: Colors.grey[600]),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
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
}

String? zorunlu(String? v, String ad) => (v == null || v.trim().isEmpty) ? '$ad zorunludur' : null;

/// İnek / Koyun / Tavuk seçimi.
class HayvanTuruSecici extends StatelessWidget {
  final String secili;
  final ValueChanged<String> onSecildi;
  const HayvanTuruSecici({super.key, required this.secili, required this.onSecildi});

  static const secenekler = <(String, IconData, MaterialColor)>[
    ('İnek', Icons.agriculture, Colors.blue),
    ('Koyun', Icons.pets, Colors.green),
    ('Tavuk', Icons.egg, Colors.orange),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final (ad, ikon, renk) in secenekler)
          ChoiceChip(
            avatar: Icon(ikon, size: 18, color: secili == ad ? renk[700] : Colors.grey[600]),
            label: Text(ad),
            selected: secili == ad,
            onSelected: (_) => onSecildi(ad),
            selectedColor: renk[50],
            labelStyle: TextStyle(
              fontWeight: FontWeight.w600,
              color: secili == ad ? renk[800] : Colors.grey[800],
            ),
            side: BorderSide(color: secili == ad ? renk : Colors.grey[300]!),
            showCheckmark: false,
          ),
      ],
    );
  }
}

/// "Süt toplama sırası" alanı. Boş → rotada sırasız (en sonda, alfabetik).
/// Yazılan sıradaki carinin kayacağını önceden gösterir.
class RotaSirasiAlani extends ConsumerWidget {
  final TextEditingController controller;

  /// Düzenlenen carinin kimliği (yeni caride null) — kendisi hesaba katılmaz.
  final int? cariId;
  const RotaSirasiAlani({super.key, required this.controller, this.cariId});

  /// Alandaki sıra: boş → null; geçersiz → hata fırlatmaz, [siraDogrula] yakalar.
  static int? siraOku(String metin) => metin.trim().isEmpty ? null : int.tryParse(metin.trim());

  static String? siraDogrula(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final s = int.tryParse(v.trim());
    if (s == null || s < 1) return 'Sıra 1 veya daha büyük bir tam sayı olmalı';
    if (s > 9999) return 'Sıra çok büyük';
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rota = [
      for (final c in ref.watch(aktifCarilerProvider).valueOrNull ?? const <Cari>[])
        if (c.sira != null && c.id != cariId) c,
    ]..sort(rotaSirala);

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, deger, _) {
        final s = siraOku(deger.text);
        String bilgi;
        if (deger.text.trim().isEmpty) {
          bilgi = 'Boş bırakılırsa rotada sırasız olur, listelerde en sonda (alfabetik) görünür.';
        } else if (s == null || s < 1) {
          bilgi = '';
        } else if (s > rota.length) {
          bilgi = 'Rotanın sonuna eklenir (${rota.length + 1}. sıra).';
        } else {
          final simdiki = rota[s - 1];
          bilgi = 'Şu an $s. sırada ${simdiki.tamAd} var → ${s + 1}. sıraya kayar, '
              'sonrakiler de birer kayar.';
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 120,
                  child: TextFormField(
                    key: const ValueKey('rotaSirasi'),
                    controller: controller,
                    keyboardType: TextInputType.number,
                    validator: siraDogrula,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      hintText: '—',
                      prefixIcon: const Icon(Icons.route_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[50],
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Rotada ${rota.length} cari sıralı',
                      style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                ),
                if (deger.text.isNotEmpty)
                  IconButton(
                    tooltip: 'Sırayı kaldır',
                    icon: const Icon(Icons.clear),
                    onPressed: controller.clear,
                  ),
              ],
            ),
            if (bilgi.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(bilgi, style: TextStyle(fontSize: 12, color: Colors.blue[800])),
            ],
          ],
        );
      },
    );
  }
}

/// Aynı ad-soyadla (Türkçe harf ve boşluk farkı gözetmeden) kayıtlı cariler.
/// [haricId]: düzenlenen carinin kendisi sayılmaz.
Future<List<Cari>> ayniIsimliCariler(CariRepository repo, String ad, String soyad, {int? haricId}) async {
  String anahtar(String a, String s) => turkceKucuk('$a $s'.trim().replaceAll(RegExp(r'\s+'), ' '));
  final aranan = anahtar(ad, soyad);
  return (await repo.getAll()).where((c) => c.id != haricId && anahtar(c.ad, c.soyad) == aranan).toList();
}

/// "Aynı isimde cari var, yine de devam?" onayı. true → devam.
Future<bool> ayniIsimOnayi(BuildContext context, String tamAd, List<Cari> ayniIsim,
    {required String soru, required String dugme}) async {
  final devam = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Aynı isimde cari var'),
      content: Text(
        '"$tamAd" adında ${ayniIsim.length} cari zaten kayıtlı'
        '${ayniIsim.any((c) => !c.aktif) ? ' (pasif olabilir)' : ''}.\n\n'
        'Süt/yem yanlış kişiye yazılabilir. $soru',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(dugme)),
      ],
    ),
  );
  return devam == true;
}
