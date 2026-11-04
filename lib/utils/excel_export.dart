import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../models/cari_model.dart';
import '../models/sut_model.dart';
import '../models/yem_model.dart';
import '../features/cari_hesap/providers/cari_hesap_providers.dart' show AylikCariOzet;
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart';

class ExcelExport {
  // 🥛 SÜT EXCEL RAPORU
  static Future<File> exportSutRaporu({
    required List<Cari> cariler,
    required List<Sut> sutler,
    required DateTime startDate,
    required DateTime endDate,
    required String raporAdi,
  }) async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Süt Raporu'];

      // 🔹 Stil tanımları
      final headerStyle = CellStyle(
        backgroundColorHex: '#B3E5FC',
        bold: true,
        fontSize: 12,
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );

      final nameStyle = CellStyle(
        backgroundColorHex: '#E0E0E0',
        bold: true,
        horizontalAlign: HorizontalAlign.Left,
      );

      final totalStyle = CellStyle(
        backgroundColorHex: '#FFF59D',
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
      );

      // Başlıklar
      final headers = ['İsim Soyisim / Günler'];
      final daysCount = endDate.difference(startDate).inDays + 1;
      for (int i = 0; i < daysCount; i++) {
        final currentDay = startDate.add(Duration(days: i));
        final day = DateFormat('dd MMM', 'tr_TR').format(currentDay);
        headers.add('$day S');
        headers.add('$day A');
      }
      headers.add('TOPLAM');

      // Başlık satırı
      for (int i = 0; i < headers.length; i++) {
        final cell = sheet.cell(CellIndex.indexByString("${_columnLetter(i)}1"));
        cell.value = headers[i];
        cell.cellStyle = headerStyle;
      }

      // Satırlar
      int row = 2;
      for (final cari in cariler) {
        final nameCell = sheet.cell(CellIndex.indexByString("A$row"));
        nameCell.value = '${cari.ad} ${cari.soyad}';
        nameCell.cellStyle = nameStyle;

        double toplam = 0;
        int col = 1;

        for (int i = 0; i < daysCount; i++) {
          final currentDay = startDate.add(Duration(days: i));
          final cariSutler = sutler.where((s) =>
              s.cariId == cari.id &&
              DateTime.parse(s.tarih).year == currentDay.year &&
              DateTime.parse(s.tarih).month == currentDay.month &&
              DateTime.parse(s.tarih).day == currentDay.day);

          double sabah = 0;
          double aksam = 0;
          for (final sut in cariSutler) {
            sabah += sut.sabah ?? 0;
            aksam += sut.aksam ?? 0;
          }

          final sabahCell =
              sheet.cell(CellIndex.indexByString("${_columnLetter(col)}$row"));
          sabahCell.value = sabah;

          final aksamCell =
              sheet.cell(CellIndex.indexByString("${_columnLetter(col + 1)}$row"));
          aksamCell.value = aksam;

          toplam += sabah + aksam;
          col += 2;
        }

        final totalCell =
            sheet.cell(CellIndex.indexByString("${_columnLetter(col)}$row"));
        totalCell.value = toplam;
        totalCell.cellStyle = totalStyle;
        row++;
      }

      // Genel toplam satırı
      sheet.cell(CellIndex.indexByString("A$row"))
        ..value = 'GENEL TOPLAM'
        ..cellStyle = totalStyle;

      int col = 1;
      double genelToplam = 0;
      for (int i = 0; i < daysCount; i++) {
        final currentDay = startDate.add(Duration(days: i));
        double sabahToplam = 0;
        double aksamToplam = 0;

        for (final cari in cariler) {
          final cariSutler = sutler.where((s) =>
              s.cariId == cari.id &&
              DateTime.parse(s.tarih).year == currentDay.year &&
              DateTime.parse(s.tarih).month == currentDay.month &&
              DateTime.parse(s.tarih).day == currentDay.day);
          for (final sut in cariSutler) {
            sabahToplam += sut.sabah ?? 0;
            aksamToplam += sut.aksam ?? 0;
          }
        }

        sheet.cell(CellIndex.indexByString("${_columnLetter(col)}$row"))
          ..value = sabahToplam
          ..cellStyle = totalStyle;
        sheet.cell(CellIndex.indexByString("${_columnLetter(col + 1)}$row"))
          ..value = aksamToplam
          ..cellStyle = totalStyle;

        genelToplam += sabahToplam + aksamToplam;
        col += 2;
      }

      sheet.cell(CellIndex.indexByString("${_columnLetter(col)}$row"))
        ..value = genelToplam
        ..cellStyle = totalStyle;

      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/$raporAdi.xlsx';
      final bytes = excel.save();
      if (bytes == null) throw Exception('Excel encode başarısız.');

      final file = File(path);
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (e, st) {
      debugPrint('❌ Süt raporu hatası: $e\n$st');
      rethrow;
    }
  }

  // 🧮 AYLIK HESAPLAMA RAPORU (fiyat_hesaplama_ekrani.dart için)
  static Future<File> exportHesaplamaRaporu({
    required List<({Cari cari, AylikCariOzet ozet})> satirlar,
    required String ayAdi,
  }) async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Aylık Hesaplama'];

      final headerStyle = CellStyle(
        backgroundColorHex: '#B3E5FC',
        bold: true,
        fontSize: 12,
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );
      final nameStyle = CellStyle(
        backgroundColorHex: '#E0E0E0',
        bold: true,
        horizontalAlign: HorizontalAlign.Left,
      );
      final totalStyle = CellStyle(
        backgroundColorHex: '#FFF59D',
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
      );

      // Bakiye işareti: + cari alacaklı (işletme ödeyecek), − cari borçlu.
      const headers = [
        'İsim Soyisim',
        'Süt (kg)',
        'Süt Fiyatı (₺/kg)',
        'Süt Tutarı (₺)',
        'Yem (kg)',
        'Yem Tutarı (₺)',
        'Ödenen (₺)',
        'Tahsil Edilen (₺)',
        'Bu Ay Net (₺)',
        'Genel Bakiye (₺)',
      ];
      for (int i = 0; i < headers.length; i++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          ..value = headers[i]
          ..cellStyle = headerStyle;
      }

      final toplam = List<double>.filled(headers.length, 0);
      int row = 1;
      for (final s in satirlar) {
        final o = s.ozet;
        final degerler = <double>[
          o.sutKg, o.sutFiyat, o.sutTutar, o.yemKg, o.yemTutar,
          o.odeme, o.tahsilat, o.ayNet, o.genelBakiye,
        ];
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          ..value = '${s.cari.ad} ${s.cari.soyad}'
          ..cellStyle = nameStyle;
        for (int i = 0; i < degerler.length; i++) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i + 1, rowIndex: row)).value = degerler[i];
          toplam[i + 1] += degerler[i];
        }
        row++;
      }

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        ..value = 'GENEL TOPLAM'
        ..cellStyle = totalStyle;
      for (int i = 1; i < headers.length; i++) {
        // Fiyat sütunu toplanmaz.
        if (i == 2) continue;
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row))
          ..value = double.parse(toplam[i].toStringAsFixed(2))
          ..cellStyle = totalStyle;
      }

      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/Hesaplama_$ayAdi.xlsx';
      final bytes = excel.save();
      if (bytes == null) throw Exception('Excel encode başarısız.');

      final file = File(path);
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (e, st) {
      debugPrint('❌ Hesaplama raporu hatası: $e\n$st');
      rethrow;
    }
  }

  // 🐮 YEM EXCEL RAPORU
  static Future<File> exportYemRaporu({
    required List<Cari> cariler,
    required List<Yem> yemler,
    required DateTime startDate,
    required DateTime endDate,
    required String raporAdi,
  }) async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Yem Raporu'];

      final headerStyle = CellStyle(
        backgroundColorHex: '#C5E1A5',
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
      );

      const headers = [
        'İsim Soyisim',
        'Tarih',
        'Süt Yemi (kg)',
        'Besi Yemi (kg)',
        'B. Başlangıç (kg)',
        'B. Büyütme (kg)',
        'Kuzu Yemi (kg)',
        'Tavuk Yemi (kg)',
        'TOPLAM (kg)'
      ];

      for (int i = 0; i < headers.length; i++) {
        final cell = sheet.cell(CellIndex.indexByString("${_columnLetter(i)}1"));
        cell.value = headers[i];
        cell.cellStyle = headerStyle;
      }

      yemler.sort((a, b) => a.tarih.compareTo(b.tarih));

      int row = 2;
      for (final yem in yemler) {
        final cari = cariler.firstWhere(
          (c) => c.id == yem.cariId,
          orElse: () => Cari(ad: 'Bilinmeyen', soyad: 'Cari'),
        );

        sheet.cell(CellIndex.indexByString("A$row")).value = '${cari.ad} ${cari.soyad}';

        try {
          final tarih = DateTime.parse(yem.tarih);
          sheet.cell(CellIndex.indexByString("B$row")).value =
              DateFormat('dd MMMM yyyy', 'tr_TR').format(tarih);
        } catch (_) {
          sheet.cell(CellIndex.indexByString("B$row")).value = yem.tarih;
        }

        sheet.cell(CellIndex.indexByString("C$row")).value = yem.sutYemi;
        sheet.cell(CellIndex.indexByString("D$row")).value = yem.besiYemi;
        sheet.cell(CellIndex.indexByString("E$row")).value = yem.bBaslangic;
        sheet.cell(CellIndex.indexByString("F$row")).value = yem.bBuyutme;
        sheet.cell(CellIndex.indexByString("G$row")).value = yem.kuzuYemi;
        sheet.cell(CellIndex.indexByString("H$row")).value = yem.tavukYemi;
        sheet.cell(CellIndex.indexByString("I$row")).value = yem.toplam;
        row++;
      }

      final totalCell = sheet.cell(CellIndex.indexByString("A$row"));
      totalCell.value = 'GENEL TOPLAM';
      totalCell.cellStyle = CellStyle(
        backgroundColorHex: '#FFF59D',
        bold: true,
      );

      double genelToplam = yemler.fold(0, (sum, yem) => sum + (yem.toplam ?? 0));
      final totalValueCell = sheet.cell(CellIndex.indexByString("I$row"));
      totalValueCell.value = genelToplam;
      totalValueCell.cellStyle = CellStyle(
        backgroundColorHex: '#FFF59D',
        bold: true,
      );

      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/$raporAdi.xlsx';
      final bytes = excel.save();
      if (bytes == null) throw Exception('Excel encode başarısız.');

      final file = File(path);
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (e, st) {
      debugPrint('❌ Yem raporu hatası: $e\n$st');
      rethrow;
    }
  }

  static String _columnLetter(int index) {
    const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    if (index < letters.length) return letters[index];
    int first = (index ~/ letters.length) - 1;
    int second = index % letters.length;
    return '${letters[first]}${letters[second]}';
  }

  // 📋 CARİ HESAP EKSTRESİ (cari_hesap_ekstresi_ekrani.dart için)
  static Future<File> exportCariHesapEkstresi({
    required String cariAdi,
    required List<Map<String, dynamic>> hareketler, // {tarih, islemAdi, kredi(bool), tutar, aciklama}
    required double toplamSut,
    required double toplamYem,
    required double toplamOdeme,
    required double toplamTahsilat,
    required double kalanBakiye,
  }) async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Hesap Ekstresi'];

      final baslikStyle = CellStyle(bold: true, fontSize: 14);
      final headerStyle = CellStyle(
        backgroundColorHex: '#B3E5FC',
        bold: true,
        fontSize: 12,
        horizontalAlign: HorizontalAlign.Center,
      );
      final krediStyle = CellStyle(fontColorHex: '#0D47A1');
      final borcStyle = CellStyle(fontColorHex: '#E65100');
      final totalStyle = CellStyle(backgroundColorHex: '#FFF59D', bold: true);

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
        ..value = 'Cari Hesap Ekstresi — $cariAdi'
        ..cellStyle = baslikStyle;

      final headers = ['Tarih', 'İşlem', 'Açıklama', 'Tutar (₺)'];
      for (int i = 0; i < headers.length; i++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 2));
        cell.value = headers[i];
        cell.cellStyle = headerStyle;
      }

      int row = 3;
      for (final h in hareketler) {
        final kredi = h['kredi'] as bool;
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = h['tarih'] as String;
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = h['islemAdi'] as String;
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value = h['aciklama'] as String? ?? '';
        final tutarCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row));
        tutarCell.value = (kredi ? 1 : -1) * (h['tutar'] as num).toDouble();
        tutarCell.cellStyle = kredi ? krediStyle : borcStyle;
        row++;
      }

      row += 1;
      final ozetSatirlari = [
        ['Toplam Süt (Alacak)', toplamSut],
        ['Toplam Yem (Borç)', toplamYem],
        ['Toplam Ödeme', toplamOdeme],
        ['Toplam Tahsilat', toplamTahsilat],
        ['NET BAKİYE', kalanBakiye],
      ];
      for (final s in ozetSatirlari) {
        final adCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
        adCell.value = s[0] as String;
        final degerCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row));
        degerCell.value = s[1] as double;
        if (s[0] == 'NET BAKİYE') {
          adCell.cellStyle = totalStyle;
          degerCell.cellStyle = totalStyle;
        }
        row++;
      }

      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/Hesap_Ekstresi_${cariAdi.replaceAll(' ', '_')}.xlsx';
      final bytes = excel.save();
      if (bytes == null) throw Exception('Excel encode başarısız.');
      final file = File(path);
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (e, st) {
      debugPrint('❌ Hesap ekstresi export hatası: $e\n$st');
      rethrow;
    }
  }

  // 📤 PAYLAŞ
  static Future<void> shareFile(File file) async {
    try {
      if (await file.exists()) {
       await Future.delayed(const Duration(seconds: 2));
        await Share.shareXFiles(
          [XFile(file.path)],
          subject: 'Süt Yem Takip Raporu',
          text: 'Süt Yem Takip Sistemi tarafından oluşturulan rapor',
        );
      } else {
        throw Exception('Paylaşılacak dosya bulunamadı');
      }
    } catch (e, st) {
      debugPrint('❌ Paylaşım hatası: $e\n$st');
      rethrow;
    }
  }
}
