import 'package:flutter/material.dart';
class YemGirisKarti extends StatelessWidget {
  final VoidCallback? onTap;
  final String title;
  const YemGirisKarti({required this.title, this.onTap, super.key});
  @override
  Widget build(BuildContext context) {
    return Card(child: ListTile(title: Text(title), onTap: onTap));
  }
}
