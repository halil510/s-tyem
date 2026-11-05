import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

import 'ekstre_satirlari.dart';
import 'excel_export.dart' show ExcelExport;

/// Cari hesap ekstresini PDF olarak dışa aktarır.
///
/// 2026-11-05 düzeltmeleri:
/// * Yazı tipi uygulamanın içindeki DejaVu Sans'tan yüklenir (Türkçe harfli,
///   İNTERNETSİZ çalışır). Eskiden her PDF'te Google Fonts'tan indiriliyordu →
///   internet yoksa PDF hiç oluşmuyordu.
/// * Türkçe harfler ("Süt", "Borçlu") ve Türkçe para biçimi (1.234,50 TL).
/// * Tarih filtresi varsa dönem yazılır ve rakam "DÖNEM NETİ" olarak gösterilir
///   (tüm zamanların bakiyesi sanılmasın). Satırlar eskiden yeniye, yürüyen
///   bakiyeyle — Excel ekstresiyle aynı [ekstreSatirlari] hesabı.
class PdfExport {
  static const _fontNormal = 'assets/fonts/DejaVuSans.ttf';
  static const _fontKalin = 'assets/fonts/DejaVuSans-Bold.ttf';

  static final _para = NumberFormat('#,##0.00', 'tr_TR');
  static String _tl(num v) => '${_para.format(v)} TL'; // 1.250,10 TL

  static Future<pw.Font> _font(String yol) async =>
      pw.Font.ttf(await rootBundle.load(yol));

  static Future<File> exportCariHesapEkstresi({
    required String cariAdi,
    required String? cariTelefon,
    required List<Map<String, dynamic>> hareketler, // {tarih, islemAdi, kredi(bool), tutar, aciklama}
    required double toplamSut,
    required double toplamYem,
    required double toplamOdeme,
    required double toplamTahsilat,
    required double kalanBakiye,
    DateTime? baslangic,
    DateTime? bitis,
  }) async {
    final bytes = await ekstreBelgesi(
      cariAdi: cariAdi,
      cariTelefon: cariTelefon,
      hareketler: hareketler,
      toplamSut: toplamSut,
      toplamYem: toplamYem,
      toplamOdeme: toplamOdeme,
      toplamTahsilat: toplamTahsilat,
      kalanBakiye: kalanBakiye,
      baslangic: baslangic,
      bitis: bitis,
    );
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}${ExcelExport.dosyaAdi('Hesap_Ekstresi_$cariAdi')}.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// PDF baytları (test edilebilsin diye dosyadan ayrı).
  static Future<Uint8List> ekstreBelgesi({
    required String cariAdi,
    String? cariTelefon,
    required List<Map<String, dynamic>> hareketler,
    required double toplamSut,
    required double toplamYem,
    required double toplamOdeme,
    required double toplamTahsilat,
    required double kalanBakiye,
    DateTime? baslangic,
    DateTime? bitis,
  }) async {
    final font = await _font(_fontNormal);
    final fontBold = await _font(_fontKalin);
    final filtreli = baslangic != null || bitis != null;
    final satirlar = ekstreSatirlari(hareketler);

    final kapaliMi = kalanBakiye.abs() <= 0.005;
    final alacakliMi = kalanBakiye > 0.005;
    final durumRengi = kapaliMi ? PdfColors.grey700 : (alacakliMi ? PdfColors.blue800 : PdfColors.orange800);
    final durumMetni = kapaliMi ? 'Hesap kapalı' : (alacakliMi ? 'Cari alacaklı' : 'Cari borçlu');
    final bakiyeBasligi = filtreli
        ? 'DÖNEM NETİ — $durumMetni'
        : durumMetni;

    final doc = pw.Document();
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
            pw.Text(ekstreDonemYazisi(baslangic, bitis),
                style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey700)),
            pw.SizedBox(height: 8),
            pw.Divider(),
          ],
        ),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Süt Yem Takip Sistemi', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey500)),
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
                pw.Text(bakiyeBasligi, style: pw.TextStyle(font: fontBold, fontSize: 12, color: durumRengi)),
                pw.SizedBox(height: 4),
                pw.Text(_tl(kalanBakiye.abs()),
                    style: pw.TextStyle(font: fontBold, fontSize: 22, color: durumRengi)),
                if (filtreli)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 4),
                    child: pw.Text(ekstreDonemNotu,
                        style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey700)),
                  ),
                pw.SizedBox(height: 10),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _ozetKalemi('Süt (Alacak)', _tl(toplamSut), font, fontBold),
                    _ozetKalemi('Tahsilat (Alacak)', _tl(toplamTahsilat), font, fontBold),
                    _ozetKalemi('Yem (Borç)', _tl(toplamYem), font, fontBold),
                    _ozetKalemi('Ödeme (Borç)', _tl(toplamOdeme), font, fontBold),
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
              0: pw.FlexColumnWidth(1.6),
              1: pw.FlexColumnWidth(1.8),
              2: pw.FlexColumnWidth(2.6),
              3: pw.FlexColumnWidth(1.7),
              4: pw.FlexColumnWidth(1.7),
              5: pw.FlexColumnWidth(1.8),
            },
            children: [
              pw.TableRow(
                repeat: true,
                decoration: const pw.BoxDecoration(color: PdfColors.blue50),
                children: [
                  _hucre('Tarih', fontBold),
                  _hucre('İşlem', fontBold),
                  _hucre('Açıklama', fontBold),
                  _hucre('Alacak', fontBold, sag: true),
                  _hucre('Borç', fontBold, sag: true),
                  _hucre('Bakiye', fontBold, sag: true),
                ],
              ),
              for (final s in satirlar)
                pw.TableRow(children: [
                  _hucre(s.tarih, font),
                  _hucre(s.islemAdi, font),
                  _hucre(s.aciklama, font),
                  _hucre(s.alacak != null ? _tl(s.alacak!) : '', font, sag: true, renk: PdfColors.blue800),
                  _hucre(s.borc != null ? _tl(s.borc!) : '', font, sag: true, renk: PdfColors.orange800),
                  _hucre(_tl(s.bakiye), font, sag: true),
                ]),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Text('Bakiye: + cari alacaklı (işletme ödeyecek), − cari borçlu.',
              style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
        ],
      ),
    );
    return doc.save();
  }

  static pw.Widget _ozetKalemi(String baslik, String deger, pw.Font font, pw.Font fontBold) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(baslik, style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
        pw.SizedBox(height: 2),
        pw.Text(deger, style: pw.TextStyle(font: fontBold, fontSize: 10)),
      ],
    );
  }

  static pw.Widget _hucre(String metin, pw.Font font, {bool sag = false, PdfColor? renk}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: pw.Text(
        metin,
        style: pw.TextStyle(font: font, fontSize: 8.5, color: renk ?? PdfColors.black),
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
