import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/database/app_database.dart';
import '../data/repositories/cari_repository.dart';
import '../data/repositories/sut_repository.dart';
import '../data/repositories/yem_repository.dart';
import '../models/cari_model.dart';
import '../models/sut_model.dart';
import '../models/yem_model.dart';

class ExcelYedekleme {
  // ===================== DIALOG =====================
  static Future<void> showYedeklemeDialog(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (_) => _YedeklemeDialog(),
    );
  }

  // ===================== EXCEL OLUŞTUR =====================
  static Future<File> exportSutVeYemRaporu({
    required List<Cari> cariler,
    required List<Sut> sutler,
    required List<Yem> yemler,
    required DateTime startDate,
    required DateTime endDate,
    required String raporAdi,
  }) async {
    final excel = Excel.createExcel();

    // ======================================================
    // 🥛 SÜT RAPORU
    // ======================================================
    final sutSheet = excel['Süt Raporu'];
    final gunSayisi = endDate.difference(startDate).inDays + 1;

    // ---------- BAŞLIKLAR ----------
    List<String> headers = ['İsim Soyisim'];
    for (int i = 0; i < gunSayisi; i++) {
      final gun = DateFormat('dd.MM', 'tr_TR')
          .format(startDate.add(Duration(days: i)));
      headers.add('$gun S');
      headers.add('$gun A');
    }
    headers.add('TOPLAM');

    for (int i = 0; i < headers.length; i++) {
      sutSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
        ..value = headers[i]
        ..cellStyle = CellStyle(
          bold: true,
          backgroundColorHex: '#B3E5FC',
          horizontalAlign: HorizontalAlign.Center,
        );
    }

    // ---------- SATIRLAR ----------
    int row = 1;

    for (final cari in cariler) {
      sutSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        ..value = '${cari.ad} ${cari.soyad}'
        ..cellStyle = CellStyle(bold: true);

      int col = 1;
      double cariToplam = 0;

      for (int i = 0; i < gunSayisi; i++) {
        final gun = startDate.add(Duration(days: i));

        final gunluk = sutler.where((s) {
          final t = DateTime.parse(s.tarih);
          return s.cariId == cari.id &&
              t.year == gun.year &&
              t.month == gun.month &&
              t.day == gun.day;
        });

        double sabah = 0;
        double aksam = 0;

        for (final s in gunluk) {
          sabah += s.sabah ?? 0;
          aksam += s.aksam ?? 0;
        }

        sutSheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row)).value = sabah;
        sutSheet.cell(CellIndex.indexByColumnRow(columnIndex: col + 1, rowIndex: row)).value = aksam;

        cariToplam += sabah + aksam;
        col += 2;
      }

      sutSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
        ..value = cariToplam
        ..cellStyle = CellStyle(
          bold: true,
          backgroundColorHex: '#FFF59D',
        );

      row++;
    }

    // ---------- GENEL TOPLAM (ALT SATIR – SÜT) ----------
    sutSheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
      ..value = 'GENEL TOPLAM'
      ..cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: '#FFE082',
      );

    List<double> gunlukSabah = List.filled(gunSayisi, 0);
    List<double> gunlukAksam = List.filled(gunSayisi, 0);

    for (final s in sutler) {
      final t = DateTime.parse(s.tarih);
      final index = t.difference(startDate).inDays;
      if (index >= 0 && index < gunSayisi) {
        gunlukSabah[index] += s.sabah ?? 0;
        gunlukAksam[index] += s.aksam ?? 0;
      }
    }

    int col = 1;
    double genelSutToplam = 0;

    for (int i = 0; i < gunSayisi; i++) {
      sutSheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row)).value = gunlukSabah[i];
      sutSheet.cell(CellIndex.indexByColumnRow(columnIndex: col + 1, rowIndex: row)).value = gunlukAksam[i];

      genelSutToplam += gunlukSabah[i] + gunlukAksam[i];
      col += 2;
    }

    sutSheet
        .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
      ..value = genelSutToplam
      ..cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: '#FFD54F',
      );

    // ======================================================
    // 🐮 YEM RAPORU
    // ======================================================
    final yemSheet = excel['Yem Raporu'];

    final yemHeaders = [
      'İsim Soyisim',
      'Tarih',
      'Süt Yemi',
      'Besi Yemi',
      'B.Başlangıç',
      'B.Büyütme',
      'Kuzu Yemi',
      'Tavuk Yemi',
      'TOPLAM'
    ];

    for (int i = 0; i < yemHeaders.length; i++) {
      yemSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
        ..value = yemHeaders[i]
        ..cellStyle = CellStyle(
          bold: true,
          backgroundColorHex: '#C5E1A5',
          horizontalAlign: HorizontalAlign.Center,
        );
    }

    yemler.sort((a, b) => a.tarih.compareTo(b.tarih));
    row = 1;

    double sutYemiT = 0,
        besiT = 0,
        baslangicT = 0,
        buyutmeT = 0,
        kuzuT = 0,
        tavukT = 0,
        genelYemToplam = 0;

    for (final yem in yemler) {
      final cari = cariler.firstWhere(
        (c) => c.id == yem.cariId,
        orElse: () => Cari(ad: 'Bilinmeyen', soyad: ''),
      );

      yemSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = '${cari.ad} ${cari.soyad}';
      yemSheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = yem.tarih;

      yemSheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value = yem.sutYemi ?? 0;
      yemSheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value = yem.besiYemi ?? 0;
      yemSheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).value = yem.bBaslangic ?? 0;
      yemSheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row)).value = yem.bBuyutme ?? 0;
      yemSheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row)).value = yem.kuzuYemi ?? 0;
      yemSheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: row)).value = yem.tavukYemi ?? 0;
      yemSheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: row)).value = yem.toplam ?? 0;

      sutYemiT += yem.sutYemi ?? 0;
      besiT += yem.besiYemi ?? 0;
      baslangicT += yem.bBaslangic ?? 0;
      buyutmeT += yem.bBuyutme ?? 0;
      kuzuT += yem.kuzuYemi ?? 0;
      tavukT += yem.tavukYemi ?? 0;
      genelYemToplam += yem.toplam ?? 0;

      row++;
    }

    // ---------- GENEL TOPLAM (ALT SATIR – YEM) ----------
    yemSheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
      ..value = 'GENEL TOPLAM'
      ..cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: '#FFE082',
      );

    yemSheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value = sutYemiT;
    yemSheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value = besiT;
    yemSheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).value = baslangicT;
    yemSheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row)).value = buyutmeT;
    yemSheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row)).value = kuzuT;
    yemSheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: row)).value = tavukT;
    yemSheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: row)).value = genelYemToplam;

    // ======================================================
    // KAYDET & PAYLAŞ
    // ======================================================
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$raporAdi.xlsx';

    final bytes = excel.save();
    final file = File(path);
    await file.writeAsBytes(bytes!, flush: true);

    return file;
  }

  static Future<void> shareFile(File file) async {
    await Share.shareXFiles([XFile(file.path)]);
  }
}

// ======================================================
// DIALOG
// ======================================================
class _YedeklemeDialog extends StatefulWidget {
  @override
  State<_YedeklemeDialog> createState() => _YedeklemeDialogState();
}

class _YedeklemeDialogState extends State<_YedeklemeDialog> {
  String _periyot = 'aylik';
  bool _loading = false;

  Future<void> _yedekle() async {
    setState(() => _loading = true);

    final db = await AppDatabase.instance.database;
    final cariler = await CariRepository(db).getAll();

    final now = DateTime.now();
    DateTime start, end;

    if (_periyot == 'aylik') {
      start = DateTime(now.year, now.month, 1);
      end = DateTime(now.year, now.month + 1, 0);
    } else {
      start = DateTime(now.year, 1, 1);
      end = DateTime(now.year, 12, 31);
    }

    final sutler = await SutRepository(db).getAllInRange(
      DateFormat('yyyy-MM-dd').format(start),
      DateFormat('yyyy-MM-dd').format(end),
    );

    final yemler = await YemRepository(db).getAllInRange(
      DateFormat('yyyy-MM-dd').format(start),
      DateFormat('yyyy-MM-dd').format(end),
    );

    final file = await ExcelYedekleme.exportSutVeYemRaporu(
      cariler: cariler,
      sutler: sutler,
      yemler: yemler,
      startDate: start,
      endDate: end,
      raporAdi: 'Cari_Yedek_${DateFormat('yyyy_MM_dd').format(DateTime.now())}',
    );

    await ExcelYedekleme.shareFile(file);

    setState(() => _loading = false);
    Navigator.pop(context);
  }

@override
Widget build(BuildContext context) {
  return AlertDialog(
    title: const Text('Excel Yedekleme'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RadioListTile<String>(
          title: const Text('Aylık'),
          value: 'aylik',
          groupValue: _periyot,
          onChanged: _loading
              ? null
              : (String? v) {
                  if (v != null) {
                    setState(() => _periyot = v);
                  }
                },
        ),
        RadioListTile<String>(
          title: const Text('Yıllık'),
          value: 'yillik',
          groupValue: _periyot,
          onChanged: _loading
              ? null
              : (String? v) {
                  if (v != null) {
                    setState(() => _periyot = v);
                  }
                },
        ),
        if (_loading) const Padding(
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
        child: const Text('Yedekle'),
      ),
    ],
  );
}
}
