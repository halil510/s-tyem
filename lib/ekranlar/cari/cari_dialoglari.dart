import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../utils/sayi_format.dart';

/// Cari listesi ekranının diyalogları. Hepsi sonucu `Navigator.pop`
/// ile DÖNDÜRÜR; ekranı kapatma/yönlendirme kararı çağırana aittir.

// ─── Rapor tarih aralığı ─────────────────────────────────────────────

/// Bugün / Son 7 gün / Bu ay / Özel aralık seçtirir.
Future<DateTimeRange?> raporTarihAraligiSor(BuildContext context, String baslik) =>
    showDialog<DateTimeRange>(
      context: context,
      builder: (_) => _RaporTarihDialog(baslik: baslik),
    );

enum _Periyot { bugun, haftalik, aylik, ozel }

class _RaporTarihDialog extends StatefulWidget {
  final String baslik;
  const _RaporTarihDialog({required this.baslik});

  @override
  State<_RaporTarihDialog> createState() => _RaporTarihDialogState();
}

class _RaporTarihDialogState extends State<_RaporTarihDialog> {
  _Periyot _periyot = _Periyot.bugun;
  late DateTimeRange _aralik = _hesapla(_Periyot.bugun);

  static DateTime get _bugun {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  DateTimeRange _hesapla(_Periyot p) {
    final b = _bugun;
    return switch (p) {
      _Periyot.bugun => DateTimeRange(start: b, end: b),
      _Periyot.haftalik => DateTimeRange(start: DateTime(b.year, b.month, b.day - 6), end: b),
      _Periyot.aylik => DateTimeRange(start: DateTime(b.year, b.month, 1), end: b),
      _Periyot.ozel => _aralik,
    };
  }

  void _sec(_Periyot p) => setState(() {
        _periyot = p;
        _aralik = _hesapla(p);
      });

  Future<void> _ozelSec() async {
    final secilen = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: _bugun,
      initialDateRange: _aralik,
      locale: const Locale('tr', 'TR'),
    );
    if (secilen != null) {
      setState(() {
        _periyot = _Periyot.ozel;
        _aralik = secilen;
      });
    }
  }

  Widget _secenek(String etiket, _Periyot p, {VoidCallback? onTap}) => RadioListTile<_Periyot>(
        title: Text(etiket),
        value: p,
        groupValue: _periyot,
        dense: true,
        onChanged: (_) => onTap != null ? onTap() : _sec(p),
      );

  @override
  Widget build(BuildContext context) {
    final f = DateFormat('dd MMMM yyyy', 'tr_TR');
    return AlertDialog(
      title: Text(widget.baslik),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _secenek('Bugün', _Periyot.bugun),
          _secenek('Son 7 Gün', _Periyot.haftalik),
          _secenek('Bu Ay', _Periyot.aylik),
          _secenek('Tarih Aralığı Seç…', _Periyot.ozel, onTap: _ozelSec),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              '${f.format(_aralik.start)} – ${f.format(_aralik.end)}',
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
        FilledButton(onPressed: () => Navigator.pop(context, _aralik), child: const Text('Oluştur')),
      ],
    );
  }
}

// ─── WhatsApp seçenekleri ────────────────────────────────────────────

enum WhatsappSecenek { sutRaporu, yemRaporu, ozelMesaj, odemeBildirimi }

Future<WhatsappSecenek?> whatsappSecenekSor(BuildContext context, int kisiSayisi) =>
    showDialog<WhatsappSecenek>(
      context: context,
      builder: (ctx) {
        Widget satir(IconData ikon, Color renk, String metin, WhatsappSecenek s) => ListTile(
              leading: Icon(ikon, color: renk),
              title: Text(metin),
              onTap: () => Navigator.pop(ctx, s),
            );
        return AlertDialog(
          title: Text('WhatsApp Gönder ($kisiSayisi cari)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              satir(Icons.local_drink, Colors.blue, 'Süt Raporu Gönder', WhatsappSecenek.sutRaporu),
              satir(Icons.agriculture, Colors.green, 'Yem Raporu Gönder', WhatsappSecenek.yemRaporu),
              satir(Icons.message, Colors.green, 'Özel Mesaj Gönder', WhatsappSecenek.ozelMesaj),
              satir(Icons.payment, Colors.orange, 'Ödeme Bildirimi Gönder', WhatsappSecenek.odemeBildirimi),
            ],
          ),
        );
      },
    );

// ─── Özel mesaj ──────────────────────────────────────────────────────

Future<String?> ozelMesajSor(BuildContext context, int kisiSayisi) => showDialog<String>(
      context: context,
      builder: (_) => _OzelMesajDialog(kisiSayisi: kisiSayisi),
    );

class _OzelMesajDialog extends StatefulWidget {
  final int kisiSayisi;
  const _OzelMesajDialog({required this.kisiSayisi});

  @override
  State<_OzelMesajDialog> createState() => _OzelMesajDialogState();
}

class _OzelMesajDialogState extends State<_OzelMesajDialog> {
  final _ctrl = TextEditingController();
  String? _hata;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _gonder() {
    final metin = _ctrl.text.trim();
    if (metin.isEmpty) {
      setState(() => _hata = 'Lütfen mesaj yazın');
      return;
    }
    Navigator.pop(context, metin);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Özel Mesaj Gönder'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _ctrl,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: 'Mesajınız',
                border: const OutlineInputBorder(),
                errorText: _hata,
              ),
            ),
            const SizedBox(height: 10),
            Text('Mesaj ${widget.kisiSayisi} cariye gönderilecek',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
          FilledButton(onPressed: _gonder, child: const Text('Gönder')),
        ],
      );
}

// ─── Ödeme bildirimi ─────────────────────────────────────────────────

typedef OdemeBildirimi = ({double tutar, String donem});

Future<OdemeBildirimi?> odemeBildirimiSor(BuildContext context, int kisiSayisi) =>
    showDialog<OdemeBildirimi>(
      context: context,
      builder: (_) => _OdemeBildirimiDialog(kisiSayisi: kisiSayisi),
    );

class _OdemeBildirimiDialog extends StatefulWidget {
  final int kisiSayisi;
  const _OdemeBildirimiDialog({required this.kisiSayisi});

  @override
  State<_OdemeBildirimiDialog> createState() => _OdemeBildirimiDialogState();
}

class _OdemeBildirimiDialogState extends State<_OdemeBildirimiDialog> {
  final _tutar = TextEditingController();
  final _donem = TextEditingController(text: DateFormat('MMMM yyyy', 'tr_TR').format(DateTime.now()));
  String? _tutarHata, _donemHata;

  @override
  void dispose() {
    _tutar.dispose();
    _donem.dispose();
    super.dispose();
  }

  void _gonder() {
    final tutar = sayiCoz(_tutar.text);
    final donem = _donem.text.trim();
    setState(() {
      _tutarHata = (tutar == null || tutar <= 0) ? 'Geçerli bir tutar girin (ör. 1.250,50)' : null;
      _donemHata = donem.isEmpty ? 'Dönem boş olamaz' : null;
    });
    if (_tutarHata != null || _donemHata != null) return;
    Navigator.pop(context, (tutar: kurusaYuvarla(tutar!), donem: donem));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Ödeme Bildirimi Gönder'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _tutar,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Tutar (₺)',
                border: const OutlineInputBorder(),
                errorText: _tutarHata,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _donem,
              decoration: InputDecoration(
                labelText: 'Dönem',
                hintText: 'Örn: Mayıs 2026',
                border: const OutlineInputBorder(),
                errorText: _donemHata,
              ),
            ),
            const SizedBox(height: 10),
            Text('Aynı tutar ${widget.kisiSayisi} cariye gönderilecek',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
          FilledButton(onPressed: _gonder, child: const Text('Gönder')),
        ],
      );
}
