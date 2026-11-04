import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/sayi_format.dart';

/// [OdemeAlBottomSheet]'in sonucu: tutar + işlem tarihi + açıklama.
class NakitHareketGirdisi {
  final double tutar;
  final DateTime tarih;
  final String? aciklama;
  const NakitHareketGirdisi({required this.tutar, required this.tarih, this.aciklama});
}

/// Ödeme / tahsilat girişi için bottom sheet.
///
/// Tutarın yanında işlem TARİHİ (geçmişe dönük kayıt için — ör. dün
/// yapılan ödemeyi bugün girmek) ve isteğe bağlı açıklama alır.
/// Pop edilen sonuç: [NakitHareketGirdisi] ya da iptal edilirse null.
class OdemeAlBottomSheet extends StatefulWidget {
  final String cariAdi;
  final double? maksimumTutar;
  final String? baslik;

  const OdemeAlBottomSheet({
    super.key,
    required this.cariAdi,
    this.maksimumTutar,
    this.baslik,
  });

  @override
  State<OdemeAlBottomSheet> createState() => _OdemeAlBottomSheetState();
}

class _OdemeAlBottomSheetState extends State<OdemeAlBottomSheet> {
  final _tutarCtrl = TextEditingController();
  final _aciklamaCtrl = TextEditingController();
  DateTime _tarih = DateUtils.dateOnly(DateTime.now());
  String? _hata;

  @override
  void dispose() {
    _tutarCtrl.dispose();
    _aciklamaCtrl.dispose();
    super.dispose();
  }

  Future<void> _tarihSec() async {
    final secilen = await showDatePicker(
      context: context,
      initialDate: _tarih,
      firstDate: DateTime(2020),
      lastDate: DateUtils.dateOnly(DateTime.now()),
    );
    if (secilen != null) setState(() => _tarih = DateUtils.dateOnly(secilen));
  }

  void _onayla() {
    final tutar = sayiCoz(_tutarCtrl.text);
    if (tutar == null || tutar <= 0) {
      setState(() => _hata = 'Geçerli bir tutar girin');
      return;
    }
    if (widget.maksimumTutar != null && tutar > widget.maksimumTutar!) {
      setState(() => _hata = 'Tutar kalan bakiyeden büyük olamaz');
      return;
    }
    final aciklama = _aciklamaCtrl.text.trim();
    Navigator.of(context).pop(NakitHareketGirdisi(
      tutar: kurusaYuvarla(tutar),
      tarih: _tarih,
      aciklama: aciklama.isEmpty ? null : aciklama,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.baslik ?? 'Ödeme Al',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(widget.cariAdi, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 20),
            TextField(
              controller: _tutarCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                prefixText: '₺ ',
                hintText: '0,00',
                errorText: _hata,
                filled: true,
                fillColor: AppColors.surfaceVar,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
              onChanged: (_) {
                if (_hata != null) setState(() => _hata = null);
              },
            ),
            if (widget.maksimumTutar != null) ...[
              const SizedBox(height: 8),
              Text(
                'Maksimum: ₺${widget.maksimumTutar!.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12, color: AppColors.textHint),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _tarihSec,
                    icon: const Icon(Icons.event_rounded, size: 18),
                    label: Text(DateFormat('dd MMMM yyyy', 'tr_TR').format(_tarih)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _aciklamaCtrl,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 120,
              decoration: InputDecoration(
                hintText: 'Açıklama (isteğe bağlı)',
                counterText: '',
                filled: true,
                fillColor: AppColors.surfaceVar,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
              onSubmitted: (_) => _onayla(),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _onayla,
                child: const Text('Onayla', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
