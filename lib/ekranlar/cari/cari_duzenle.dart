import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/providers/veri_surumu_provider.dart';
import '../../models/cari_model.dart';
import '../../widgetlar/kaydedilmemis_koruma.dart';
import 'cari_form.dart';

/// Cari düzenleme (2026-11-05 yeniden tasarım).
///
/// Bölümler: özet başlık · kişisel bilgiler · hayvan türü · süt toplama sırası
/// · not · durum (aktif/pasif). Kaydet düğmesi altta sabit. Bilgiler, sıra ve
/// durum TEK transaction'da yazılır (`CariRepository.update`). Pasife alınan
/// cari rotadan çıkar ve listelerde görünmez; Cariler → Pasif Cariler'den geri
/// getirilir. Kaydedilmemiş değişiklikle geri çıkılırsa sorulur.
class CariDuzenle extends ConsumerStatefulWidget {
  final Cari cari;
  const CariDuzenle({required this.cari, super.key});

  @override
  ConsumerState<CariDuzenle> createState() => _CariDuzenleState();
}

class _CariDuzenleState extends ConsumerState<CariDuzenle> {
  final _formKey = GlobalKey<FormState>();
  late final _ad = TextEditingController(text: widget.cari.ad);
  late final _soyad = TextEditingController(text: widget.cari.soyad);
  late final _telefon = TextEditingController(text: widget.cari.telefon ?? '');
  late final _adres = TextEditingController(text: widget.cari.adres ?? '');
  late final _not = TextEditingController(text: widget.cari.notMetni ?? '');
  late final _sira = TextEditingController(text: widget.cari.aktif && widget.cari.sira != null ? '${widget.cari.sira}' : '');
  late String _hayvanTuru = widget.cari.hayvanTuru ?? 'İnek';
  late bool _aktif = widget.cari.aktif;
  final _secimDegisti = ValueNotifier<int>(0);
  bool _kaydediliyor = false;

  late final _dinle = Listenable.merge([_ad, _soyad, _telefon, _adres, _not, _sira, _secimDegisti]);

  @override
  void dispose() {
    for (final c in [_ad, _soyad, _telefon, _adres, _not, _sira]) {
      c.dispose();
    }
    _secimDegisti.dispose();
    super.dispose();
  }

  int? get _ilkSira => widget.cari.aktif ? widget.cari.sira : null;

  bool get _degisiklikVar {
    final c = widget.cari;
    return _ad.text.trim() != c.ad ||
        _soyad.text.trim() != c.soyad ||
        _telefon.text.trim() != (c.telefon ?? '') ||
        _adres.text.trim() != (c.adres ?? '') ||
        _not.text.trim() != (c.notMetni ?? '') ||
        _hayvanTuru != (c.hayvanTuru ?? 'İnek') ||
        _aktif != c.aktif ||
        RotaSirasiAlani.siraOku(_sira.text) != _ilkSira;
  }

  void _sec(VoidCallback f) {
    setState(f);
    _secimDegisti.value++;
  }

  Future<void> _kaydet() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_degisiklikVar) {
      Navigator.pop(context, false);
      return;
    }
    if (!_aktif && widget.cari.aktif && await _pasifOnayi() != true) return;

    setState(() => _kaydediliyor = true);
    try {
      final repo = await ref.read(cariRepositoryProvider.future);
      final ad = _ad.text.trim(), soyad = _soyad.text.trim();
      if (ad != widget.cari.ad || soyad != widget.cari.soyad) {
        final ayniIsim = await ayniIsimliCariler(repo, ad, soyad, haricId: widget.cari.id);
        if (ayniIsim.isNotEmpty) {
          if (!mounted) return;
          if (!await ayniIsimOnayi(context, '$ad $soyad', ayniIsim,
              soru: 'Bu isim yine de kaydedilsin mi?', dugme: 'Yine de Kaydet')) {
            if (mounted) setState(() => _kaydediliyor = false);
            return;
          }
        }
      }

      final yeniSira = RotaSirasiAlani.siraOku(_sira.text);
      await repo.update(
        Cari(
          id: widget.cari.id,
          ad: ad,
          soyad: soyad,
          adres: _adres.text.trim(),
          telefon: _telefon.text.trim(),
          hayvanTuru: _hayvanTuru,
          aktif: _aktif,
          notMetni: _not.text.trim().isEmpty ? null : _not.text.trim(),
        ),
        // Geri getirilen ya da sırası değişen cari rotaya yerleşir.
        siraGuncelle: _aktif && (yeniSira != _ilkSira || !widget.cari.aktif),
        sira: yeniSira,
      );
      ref.veriDegisti();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(!_aktif && widget.cari.aktif
            ? '${widget.cari.tamAd} pasife alındı. Geri getirmek için: Cariler → Pasif Cariler'
            : 'Cari güncellendi'),
        backgroundColor: Colors.green[700],
      ));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _kaydediliyor = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e'), backgroundColor: Colors.red));
    }
  }

  Future<bool?> _pasifOnayi() => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cari pasife alınsın mı?'),
          content: Text(
            '${widget.cari.tamAd}\n\n'
            '• Cariler, Süt, Yem listelerinde ve toplama rotasında görünmez.\n'
            '• Geçmiş süt, yem ve ödeme kayıtları SİLİNMEZ.\n'
            '• İstediğiniz zaman Cariler → Pasif Cariler\'den geri getirebilirsiniz.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Pasife Al')),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return KaydedilmemisKoruma(
      dinle: _dinle,
      degisiklikVar: () => !_kaydediliyor && _degisiklikVar,
      kaydet: _kaydet,
      baslik: 'Değişiklikler kaydedilmedi',
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFF),
        appBar: AppBar(
          title: const Text('Cari Düzenle'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.blue[800],
          elevation: 0,
        ),
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                children: [
                  _OzetBasligi(cari: widget.cari, aktif: _aktif),
                  const SizedBox(height: 14),
                  CariBolumKarti(
                    baslik: 'Kişisel Bilgiler',
                    ikon: Icons.person_outline,
                    child: Column(
                      children: [
                        CariMetinAlani(
                          controller: _ad,
                          etiket: 'Ad',
                          ikon: Icons.person_outline,
                          buyukHarf: TextCapitalization.characters,
                          dogrula: (v) => zorunlu(v, 'Ad'),
                        ),
                        const SizedBox(height: 12),
                        CariMetinAlani(
                          controller: _soyad,
                          etiket: 'Soyad',
                          ikon: Icons.badge_outlined,
                          buyukHarf: TextCapitalization.characters,
                          // Soyad isteğe bağlı: Excel'den tek kelimelik isimle gelen cari düzenlenebilmeli.
                        ),
                        const SizedBox(height: 12),
                        CariMetinAlani(
                          controller: _telefon,
                          etiket: 'Telefon',
                          ikon: Icons.phone_outlined,
                          klavye: TextInputType.phone,
                          ipucu: '05xx xxx xx xx',
                        ),
                        const SizedBox(height: 12),
                        CariMetinAlani(controller: _adres, etiket: 'Adres / Köy', ikon: Icons.location_on_outlined, satir: 2),
                      ],
                    ),
                  ),
                  CariBolumKarti(
                    baslik: 'Hayvan Türü',
                    ikon: Icons.pets_outlined,
                    child: HayvanTuruSecici(secili: _hayvanTuru, onSecildi: (v) => _sec(() => _hayvanTuru = v)),
                  ),
                  if (_aktif)
                    CariBolumKarti(
                      baslik: 'Süt Toplama Sırası',
                      ikon: Icons.route_outlined,
                      aciklama: 'Süt toplarken bu cariye kaçıncı sırada uğruyorsunuz? '
                          'Tüm rotayı sürükleyerek düzenlemek için: Cariler → ⋮ → Toplama Sırası.',
                      child: RotaSirasiAlani(controller: _sira, cariId: widget.cari.id),
                    ),
                  CariBolumKarti(
                    baslik: 'Not',
                    ikon: Icons.sticky_note_2_outlined,
                    child: CariMetinAlani(
                      controller: _not,
                      etiket: 'Not (isteğe bağlı)',
                      ikon: Icons.edit_note,
                      satir: 3,
                    ),
                  ),
                  CariBolumKarti(
                    baslik: 'Durum',
                    ikon: Icons.toggle_on_outlined,
                    child: SwitchListTile(
                      key: const ValueKey('aktifAnahtari'),
                      contentPadding: EdgeInsets.zero,
                      value: _aktif,
                      onChanged: (v) => _sec(() => _aktif = v),
                      title: Text(_aktif ? 'Aktif — süt alınıyor' : 'Pasif',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        _aktif
                            ? 'Kapatırsanız cari listelerden ve rotadan çıkar; geçmiş kayıtlar korunur.'
                            : 'Listelerde görünmez. Kaydettikten sonra Cariler → Pasif Cariler\'den geri getirilebilir.',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _kaydediliyor ? null : _kaydet,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: _kaydediliyor
                    ? const SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save),
                label: const Text('Kaydet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OzetBasligi extends StatelessWidget {
  final Cari cari;
  final bool aktif;
  const _OzetBasligi({required this.cari, required this.aktif});

  @override
  Widget build(BuildContext context) {
    final bas = [cari.ad, cari.soyad].where((s) => s.isNotEmpty).map((s) => s.characters.first).join();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.blue[700]!, Colors.blue[900]!]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: Colors.white24,
            child: Text(bas, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cari.tamAd,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _etiket(aktif ? 'Aktif' : 'Pasif', aktif ? Colors.greenAccent : Colors.orangeAccent),
                    if (cari.aktif && cari.sira != null) _etiket('Rota: ${cari.sira}. sıra', Colors.white),
                    if (cari.hayvanTuru != null) _etiket(cari.hayvanTuru!, Colors.white),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _etiket(String yazi, Color renk) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: renk.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: renk.withValues(alpha: 0.6)),
        ),
        child: Text(yazi, style: TextStyle(color: renk, fontSize: 11, fontWeight: FontWeight.w600)),
      );
}
