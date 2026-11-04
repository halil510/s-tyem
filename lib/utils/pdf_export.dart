import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

/// Cari hesap ekstresini PDF olarak dışa aktaran yardımcı sınıf.
///
/// `pdf` paketi Türkçe karakterleri (ş, ğ, ı, ö, ü, ç) varsayılan
/// fontla düzgün göstermeyebileceğinden, Google Fonts'tan (Roboto)
/// gömülü bir font yüklenir.
class PdfExport {
  static Future<File> exportCariHesapEkstresi({
    required String cariAdi,
    required String? cariTelefon,
    required List<Map<String, dynamic>> hareketler, // {tarih, islemAdi, kredi(bool), tutar, aciklama}
    required double toplamSut,
    required double toplamYem,
    required double toplamOdeme,
    required double toplamTahsilat,
    required double kalanBakiye,
  }) async {
    final doc = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    final paraFormat = (num v) => '${v.toStringAsFixed(2)} TL';
    final alacakliMi = kalanBakiye > 0.01;
    final kapaliMi = kalanBakiye.abs() <= 0.01;
    final durumMetni = kapaliMi ? 'Hesap Kapali' : (alacakliMi ? 'Cari Alacakli' : 'Cari Borclu');
    final durumRengi = kapaliMi ? PdfColors.grey700 : (alacakliMi ? PdfColors.blue800 : PdfColors.orange800);

    doc.addPage(
      pw.MultiPage(
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        pageFormat: PdfPageFormat.a4,
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Cari Hesap Ekstresi', style: pw.TextStyle(font: fontBold, fontSize: 20)),
            pw.SizedBox(height: 4),
            pw.Text(cariAdi, style: pw.TextStyle(font: fontBold, fontSize: 14)),
            if (cariTelefon != null && cariTelefon.isNotEmpty)
              pw.Text(cariTelefon, style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey600)),
            pw.SizedBox(height: 12),
            pw.Divider(),
          ],
        ),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Sut Yem Takip Sistemi', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey500)),
            pw.Text('Sayfa ${context.pageNumber}/${context.pagesCount}',
                style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey500)),
          ],
        ),
        build: (context) => [
          // Bakiye özet kutusu
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(durumMetni, style: pw.TextStyle(font: fontBold, fontSize: 12, color: durumRengi)),
                pw.SizedBox(height: 4),
                pw.Text(paraFormat(kalanBakiye.abs()),
                    style: pw.TextStyle(font: fontBold, fontSize: 22, color: durumRengi)),
                pw.SizedBox(height: 10),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _ozetKalemi('Sut (Alacak)', paraFormat(toplamSut), font, fontBold),
                    _ozetKalemi('Yem (Borc)', paraFormat(toplamYem), font, fontBold),
                    _ozetKalemi('Odeme', paraFormat(toplamOdeme), font, fontBold),
                    _ozetKalemi('Tahsilat', paraFormat(toplamTahsilat), font, fontBold),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Text('Hareketler', style: pw.TextStyle(font: fontBold, fontSize: 13)),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(2),
              1: pw.FlexColumnWidth(2),
              2: pw.FlexColumnWidth(3),
              3: pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.blue50),
                children: [
                  _hucre('Tarih', font, bold: true),
                  _hucre('Islem', font, bold: true),
                  _hucre('Aciklama', font, bold: true),
                  _hucre('Tutar', font, bold: true, sag: true),
                ],
              ),
              ...hareketler.map((h) {
                final kredi = h['kredi'] as bool;
                final tutar = (h['tutar'] as num).toDouble();
                return pw.TableRow(children: [
                  _hucre(h['tarih'] as String, font),
                  _hucre(h['islemAdi'] as String, font),
                  _hucre(h['aciklama'] as String? ?? '', font),
                  _hucre(
                    '${kredi ? '+' : '-'}${paraFormat(tutar)}',
                    font,
                    sag: true,
                    renk: kredi ? PdfColors.blue800 : PdfColors.orange800,
                  ),
                ]);
              }),
            ],
          ),
        ],
      ),
    );

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/Hesap_Ekstresi_${cariAdi.replaceAll(' ', '_')}.pdf';
    final file = File(path);
    await file.writeAsBytes(await doc.save());
    return file;
  }

  static pw.Widget _ozetKalemi(String baslik, String deger, pw.Font font, pw.Font fontBold) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(baslik, style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
        pw.SizedBox(height: 2),
        pw.Text(deger, style: pw.TextStyle(font: fontBold, fontSize: 11)),
      ],
    );
  }

  static pw.Widget _hucre(String metin, pw.Font font, {bool bold = false, bool sag = false, PdfColor? renk}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        metin,
        style: pw.TextStyle(font: font, fontSize: 9, color: renk ?? PdfColors.black),
        textAlign: sag ? pw.TextAlign.right : pw.TextAlign.left,
      ),
    );
  }

  /// PDF'i sistem paylaşım menüsüyle paylaşır (WhatsApp, e-posta, vb.).
  static Future<void> paylas(File file) async {
    try {
      await Printing.sharePdf(bytes: await file.readAsBytes(), filename: file.uri.pathSegments.last);
    } catch (e, st) {
      debugPrint('❌ PDF paylaşım hatası: $e\n$st');
      rethrow;
    }
  }
}
