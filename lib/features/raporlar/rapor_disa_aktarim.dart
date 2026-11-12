import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../utils/excel_export.dart' show ExcelExport;
import 'rapor_modeli.dart';

/// ─────────────────────────────────────────────────────────────
/// RAPOR → EXCEL / PDF / YAZDIR / PAYLAŞ
/// Ekrandaki tabloyla AYNI [RaporTablosu] kullanılır (rakamlar ayrışmaz).
/// PDF yazı tipi uygulamanın içindeki DejaVu Sans: Türkçe harfli, internetsiz.
/// ─────────────────────────────────────────────────────────────
class RaporDisaAktarim {
  /// .xlsx baytları: sayılar sayı hücresi (Excel'de toplanabilir), para TL.
  static List<int> excelBaytlari(RaporTablosu t) {
    final excel = Excel.createExcel();
    const sayfa = 'Rapor';
    excel[sayfa];
    excel.setDefaultSheet(sayfa);
    if (excel.tables.containsKey('Sheet1')) excel.delete('Sheet1');
    final s = excel[sayfa];
    final baslikStil = CellStyle(bold: true, backgroundColorHex: ExcelColor.fromHexString('#B3E5FC'), horizontalAlign: HorizontalAlign.Center);
    final toplamStil = CellStyle(bold: true, backgroundColorHex: ExcelColor.fromHexString('#FFF59D'));
    void yaz(int c, int r, Object? v, [CellStyle? st]) {
      final h = s.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
      h.value = switch (v) {
        null => null,
        int i => IntCellValue(i),
        double d => DoubleCellValue(d),
        _ => TextCellValue(v.toString()),
      };
      if (st != null) h.cellStyle = st;
    }

    Object? deger(RaporSutun sut, Object? v) {
      if (v == null) return null;
      return switch (sut.tip) {
        SutunTipi.para || SutunTipi.miktar => (v as num).toDouble(),
        SutunTipi.sayi => v is num ? v.toInt() : v,
        _ => hucreMetni(sut, v),
      };
    }

    yaz(0, 0, t.baslik, CellStyle(bold: true, fontSize: 14));
    yaz(0, 1, t.altBaslik);
    for (var i = 0; i < t.sutunlar.length; i++) {
      yaz(i, 3, t.sutunlar[i].ad + (t.sutunlar[i].tip == SutunTipi.para ? ' (TL)' : ''), baslikStil);
    }
    var r = 4;
    for (final satir in t.satirlar) {
      for (var i = 0; i < t.sutunlar.length; i++) {
        yaz(i, r, deger(t.sutunlar[i], satir[i]));
      }
      r++;
    }
    if (t.toplamSatiri && t.satirlar.isNotEmpty) {
      final top = t.toplamlar;
      for (var i = 0; i < t.sutunlar.length; i++) {
        yaz(i, r, i == 0 ? 'TOPLAM' : deger(t.sutunlar[i], top[i]), toplamStil);
      }
      r++;
    }
    if (t.not != null) yaz(0, r + 1, t.not);
    for (var i = 0; i < t.sutunlar.length; i++) {
      s.setColumnWidth(i, t.sutunlar[i].sayisal ? 15 : 24);
    }
    final b = excel.save();
    if (b == null) throw Exception('Excel dosyası oluşturulamadı.');
    return b;
  }

  static Future<pw.ThemeData> _tema() async => pw.ThemeData.withFont(
        base: pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf')),
        bold: pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf')),
      );

  static Future<Uint8List> pdfBaytlari(RaporTablosu t) async {
    final doc = pw.Document(theme: await _tema());
    final yatay = t.sutunlar.length > 6;
    final veri = [
      for (final s in t.satirlar) [for (var i = 0; i < t.sutunlar.length; i++) hucreMetni(t.sutunlar[i], s[i])],
      if (t.toplamSatiri && t.satirlar.isNotEmpty)
        [for (var i = 0; i < t.sutunlar.length; i++) i == 0 ? 'TOPLAM' : hucreMetni(t.sutunlar[i], t.toplamlar[i])],
    ];
    final simdi = DateTime.now();
    String iki(int x) => x.toString().padLeft(2, '0');
    doc.addPage(pw.MultiPage(
      pageFormat: yatay ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      header: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(t.baslik, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.Text(t.altBaslik, style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 8),
      ]),
      footer: (c) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Sayfa ${c.pageNumber}/${c.pagesCount} · ${iki(simdi.day)}.${iki(simdi.month)}.${simdi.year} ${iki(simdi.hour)}:${iki(simdi.minute)}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      ),
      build: (_) => [
        if (veri.isEmpty)
          pw.Text('Seçilen dönemde kayıt yok.')
        else
          pw.TableHelper.fromTextArray(
            headers: t.sutunlar.map((s) => s.ad).toList(),
            data: veri,
            headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1A237E)),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignments: {
              for (var i = 0; i < t.sutunlar.length; i++) i: t.sutunlar[i].sayisal ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
            },
            oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF3F5F9)),
          ),
        if (t.not != null) pw.Padding(padding: const pw.EdgeInsets.only(top: 8), child: pw.Text(t.not!, style: const pw.TextStyle(fontSize: 8))),
      ],
    ));
    return doc.save();
  }

  static Future<File> _dosya(String ad, String uzanti, List<int> bayt) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}${Platform.pathSeparator}${ExcelExport.dosyaAdi(ad)}.$uzanti');
    await f.writeAsBytes(bayt, flush: true);
    return f;
  }

  static String _ad(RaporTablosu t) => '${t.baslik}_${t.altBaslik}';

  static Future<void> excelPaylas(RaporTablosu t) async {
    final f = await _dosya(_ad(t), 'xlsx', excelBaytlari(t));
    await Share.shareXFiles([XFile(f.path)], subject: t.baslik);
  }

  static Future<void> pdfPaylas(RaporTablosu t) async =>
      Printing.sharePdf(bytes: await pdfBaytlari(t), filename: '${ExcelExport.dosyaAdi(_ad(t))}.pdf');

  static Future<void> yazdir(RaporTablosu t) async => Printing.layoutPdf(name: t.baslik, onLayout: (_) => pdfBaytlari(t));
}
