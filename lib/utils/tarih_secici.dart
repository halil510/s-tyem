import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TarihSecici extends StatefulWidget {
  const TarihSecici({
    Key? key,
    this.baslangicTarihi,
    this.bitisTarihi,
    this.labelBaslangic = 'Başlangıç',
    this.labelBitis = 'Bitiş',
    this.showRange = false,
    this.sonTarih,
    required this.onTarihSecildi,
  }) : super(key: key);

  final DateTime? baslangicTarihi;
  final DateTime? bitisTarihi;
  final String labelBaslangic;
  final String labelBitis;
  final bool showRange;

  /// Seçilebilecek en ileri tarih (ör. süt girişinde bugün — gelecek
  /// tarihe yanlışlıkla kayıt yapılmasın). Verilmezse sınırsız.
  final DateTime? sonTarih;
  final Function(DateTime baslangic, DateTime? bitis) onTarihSecildi;

  @override
  _TarihSeciciState createState() => _TarihSeciciState();
}

class _TarihSeciciState extends State<TarihSecici> {
  late DateTime _baslangicTarihi;
  late DateTime _bitisTarihi;
  final DateFormat _formatter = DateFormat('dd.MM.yyyy', 'tr_TR');

  @override
  void initState() {
    super.initState();
    _baslangicTarihi = widget.baslangicTarihi ?? DateTime.now();
    _bitisTarihi = widget.bitisTarihi ?? DateTime.now();
  }

  Future<void> _tarihSec(BuildContext context, bool isStart) async {
    final initial = isStart ? _baslangicTarihi : _bitisTarihi;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: widget.sonTarih ?? DateTime(2100),
      locale: const Locale('tr', 'TR'),
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _baslangicTarihi = picked;
          if (_baslangicTarihi.isAfter(_bitisTarihi)) {
            _bitisTarihi = _baslangicTarihi;
          }
        } else {
          _bitisTarihi = picked;
          if (_bitisTarihi.isBefore(_baslangicTarihi)) {
            _baslangicTarihi = _bitisTarihi;
          }
        }
      });
      widget.onTarihSecildi(
          _baslangicTarihi, widget.showRange ? _bitisTarihi : null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextButton.icon(
            onPressed: () => _tarihSec(context, true),
            icon: const Icon(Icons.calendar_today),
            label: Text('${widget.labelBaslangic}: ${_formatter.format(_baslangicTarihi)}'),
          ),
        ),
        if (widget.showRange) const Text(' - '),
        if (widget.showRange)
          Expanded(
            child: TextButton.icon(
              onPressed: () => _tarihSec(context, false),
              icon: const Icon(Icons.calendar_today),
              label: Text('${widget.labelBitis}: ${_formatter.format(_bitisTarihi)}'),
            ),
          ),
      ],
    );
  }
}
