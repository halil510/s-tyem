import 'package:flutter/material.dart';
import '../models/cari_model.dart';

class CariKarti extends StatelessWidget {
  final Cari cari;
  final VoidCallback? onTap;
  const CariKarti({required this.cari, this.onTap, super.key});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text('${cari.ad} ${cari.soyad}'),
        subtitle: Text(cari.hayvanTuru ?? ''),
        onTap: onTap,
      ),
    );
  }
}
