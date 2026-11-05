import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/database/app_database.dart';
import '../data/repositories/cari_repository.dart';
import '../data/repositories/sut_repository.dart';
import '../data/repositories/yem_repository.dart';
import '../models/cari_model.dart';
import '../models/sut_model.dart';
import '../models/yem_model.dart';
import 'excel_export.dart';

/// Yedekleme ekranındaki "Excel" düğmesi: süt + yem kayıtlarını tek Excel
/// dosyasında (iki sayfa) verir. Bu bir RAPORDUR; uygulamaya geri yüklenemez
/// (tam yedek: JSON yedeği). Hesap kodu [ExcelExport] ile ortaktır.
class ExcelYedekleme {
  static Future<void> showYedeklemeDialog(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (_) => _YedeklemeDialog(),
    );
  }

  static Future<File> exportSutVeYemRaporu({
    required List<Cari> cariler,
    required List<Sut> sutler,
    required List<Yem> yemler,
    required DateTime startDate,
    required DateTime endDate,
    required String raporAdi,
  }) =>
      ExcelExport.exportSutVeYemRaporu(
        cariler: cariler,
        sutler: sutler,
        yemler: yemler,
        startDate: startDate,
        endDate: endDate,
        raporAdi: raporAdi,
      );

  static Future<void> shareFile(File file) => ExcelExport.shareFile(file);
}

class _YedeklemeDialog extends StatefulWidget {
  @override
  State<_YedeklemeDialog> createState() => _YedeklemeDialogState();
}

class _YedeklemeDialogState extends State<_YedeklemeDialog> {
  String _periyot = 'aylik';
  bool _loading = false;

  Future<void> _yedekle() async {
    setState(() => _loading = true);
    try {
      await _olusturVePaylas();
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      // Eskiden hata olursa diyalog sonsuza dek "yükleniyor"da kalıyordu.
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Excel oluşturulamadı: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _olusturVePaylas() async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now();
    final DateTime start, end;
    if (_periyot == 'aylik') {
      start = DateTime(now.year, now.month, 1);
      end = DateTime(now.year, now.month + 1, 0);
    } else {
      start = DateTime(now.year, 1, 1);
      end = DateTime(now.year, 12, 31);
    }
    final gun = DateFormat('yyyy-MM-dd');
    final sutler = await SutRepository(db).getAllInRange(gun.format(start), gun.format(end));
    final yemler = await YemRepository(db).getAllInRange(gun.format(start), gun.format(end));

    // Aktif cariler + bu aralıkta kaydı olan pasif cariler.
    final kayitli = {...sutler.map((s) => s.cariId), ...yemler.map((y) => y.cariId)};
    final cariler = (await CariRepository(db).getAll())
        .where((c) => c.aktif || kayitli.contains(c.id))
        .toList();

    final file = await ExcelYedekleme.exportSutVeYemRaporu(
      cariler: cariler,
      sutler: sutler,
      yemler: yemler,
      startDate: start,
      endDate: end,
      raporAdi: 'Sut_Yem_Raporu_${DateFormat('yyyy_MM_dd').format(now)}',
    );
    await ExcelYedekleme.shareFile(file);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Excel Raporu'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Süt ve yem kayıtları Excel dosyası olarak hazırlanır. Bu dosya uygulamaya '
            'geri YÜKLENEMEZ; tam yedek için JSON yedeğini kullanın.',
            style: TextStyle(fontSize: 12),
          ),
          RadioListTile<String>(
            title: const Text('Bu ay'),
            value: 'aylik',
            groupValue: _periyot,
            onChanged: _loading ? null : (v) => setState(() => _periyot = v ?? _periyot),
          ),
          RadioListTile<String>(
            title: const Text('Bu yıl'),
            value: 'yillik',
            groupValue: _periyot,
            onChanged: _loading ? null : (v) => setState(() => _periyot = v ?? _periyot),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: CircularProgressIndicator(),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _yedekle,
          child: const Text('Oluştur'),
        ),
      ],
    );
  }
}
