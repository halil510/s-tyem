import 'package:flutter/material.dart';
// Small reusable widget placeholder
class SutGirisKarti extends StatelessWidget {
  final VoidCallback? onTap;
  final String title;
  const SutGirisKarti({required this.title, this.onTap, super.key});
  @override
  Widget build(BuildContext context) {
    return Card(child: ListTile(title: Text(title), onTap: onTap));
  }
}