import 'package:flutter/material.dart';

import '../models/cari_model.dart';

/// Listelerde cari adının önünde süt toplama sırası (rota) rozeti: "1", "2"…
/// Sırasız ya da pasif caride hiçbir şey çizmez.
class RotaRozeti extends StatelessWidget {
  final Cari cari;
  const RotaRozeti(this.cari, {super.key});

  @override
  Widget build(BuildContext context) {
    final sira = cari.aktif ? cari.sira : null;
    if (sira == null) return const SizedBox.shrink();
    return Container(
      key: ValueKey('rota-${cari.id}'),
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: Colors.blue[700], borderRadius: BorderRadius.circular(10)),
      child: Text('$sira', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }
}

/// Rozet + ad (taşmaya dayanıklı).
class RotaliAd extends StatelessWidget {
  final Cari cari;
  final TextStyle? stil;
  const RotaliAd(this.cari, {super.key, this.stil});

  @override
  Widget build(BuildContext context) {
    final ad = Text(cari.tamAd, style: stil, maxLines: 1, overflow: TextOverflow.ellipsis);
    return LayoutBuilder(builder: (context, c) {
      // Çok dar yerde (küçük telefon + büyük yazı) rozete yer yoksa yalnız ad.
      if (c.maxWidth < 80) return ad;
      return Row(children: [RotaRozeti(cari), Flexible(child: ad)]);
    });
  }
}
