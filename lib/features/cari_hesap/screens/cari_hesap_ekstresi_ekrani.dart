import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../models/cari_model.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/excel_export.dart';
import '../../../utils/pdf_export.dart';
import '../../fis/fis_ekranlari.dart';
import '../../fis/fis_servisi.dart';
import '../../fis/odeme_fisi.dart';
import '../models/cari_hareket.dart';
import '../providers/cari_hesap_providers.dart';
import '../widgets/odeme_al_bottom_sheet.dart';
import '../widgets/hareket_karti.dart';

enum _EkstreFiltre { tumu, sut, yem, odemeler }

/// Profesyonel, CANLI cari hesap ekstresi ekranı.
///
/// ─────────────────────────────────────────────────────────────
/// İŞ MANTIĞI (süt toplama işletmesi — normal "veresiye" mantığının
/// TERSİ): süt aldıkça işletme cariye borçlanır (cari ALACAKLI), yem
/// verdikçe / nakit ödedikçe cari işletmeye borçlanır (cari BORÇLU).
///
///   bakiye = (toplam süt + toplam tahsilat) - (toplam yem + toplam ödeme)
///
/// Süt/yem hareketleri manuel bir "kapatma" işlemi GEREKTİRMEZ —
/// Süt/Yem sekmelerinde girilen her kayıt, ilgili ayın tanımlı
/// fiyatıyla ANINDA hesaba yansır. Tarih filtresi uygulanırsa, hem
/// hareket listesi hem de bakiye YALNIZCA o aralığa göre hesaplanır.
/// ─────────────────────────────────────────────────────────────
class CariHesapEkstresiEkrani extends ConsumerStatefulWidget {
  final Cari cari;
  const CariHesapEkstresiEkrani({super.key, required this.cari});

  @override
  ConsumerState<CariHesapEkstresiEkrani> createState() => _CariHesapEkstresiEkraniState();
}

class _CariHesapEkstresiEkraniState extends ConsumerState<CariHesapEkstresiEkrani> {
  _EkstreFiltre _filtre = _EkstreFiltre.tumu;
  final _paraFormat = NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2);
  bool _disaAktariliyor = false;

  // Tarih filtresi — null ise "Tüm Zamanlar". Her zaman gün
  // hassasiyetinde (saat/dakika/saniye sıfırlanmış) tutulur; aksi
  // halde family provider parametre kararlılığı bozulur (bkz.
  // cari_hesap_providers.dart doc yorumu).
  DateTime? _baslangic;
  DateTime? _bitis;

  int get cariId => widget.cari.id!;

  CariEkstreParam get _param => (cariId: cariId, baslangic: _baslangic, bitis: _bitis);

  @override
  Widget build(BuildContext context) {
    final ekstreAsync = ref.watch(cariEkstreProvider(_param));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.cari.tamAd, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          _disaAktariliyor
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : PopupMenuButton<String>(
                  icon: const Icon(Icons.ios_share_rounded),
                  onSelected: (v) {
                    if (v == 'excel') _excelDisaAktar(ekstreAsync.valueOrNull);
                    if (v == 'pdf') _pdfDisaAktar(ekstreAsync.valueOrNull);
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(value: 'excel', child: Row(children: [
                      Icon(Icons.grid_on_rounded, size: 18, color: Colors.green), SizedBox(width: 10), Text('Excel Olarak Aktar'),
                    ])),
                    const PopupMenuItem(value: 'pdf', child: Row(children: [
                      Icon(Icons.picture_as_pdf_rounded, size: 18, color: Colors.red), SizedBox(width: 10), Text('PDF Olarak Aktar'),
                    ])),
                  ],
                ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(cariEkstreProvider(_param)),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _TarihFiltreCubugu(
              baslangic: _baslangic,
              bitis: _bitis,
              onFiltreSec: _tarihFiltreSec,
              onTemizle: () {
                setState(() { _baslangic = null; _bitis = null; });
              },
            ),
            const SizedBox(height: 12),
            ekstreAsync.when(
              data: (ekstre) => _BakiyeOzetKarti(ekstre: ekstre, paraFormat: _paraFormat),
              loading: () => const _OzetIskeleti(),
              error: (e, _) => _HataKutusu(mesaj: '$e'),
            ),
            const SizedBox(height: 16),
            _FiltreCubugu(
              secili: _filtre,
              onSecim: (f) => setState(() => _filtre = f),
            ),
            const SizedBox(height: 8),
            ekstreAsync.when(
              data: (ekstre) {
                final filtreli = _turFiltresiUygula(ekstre.hareketler);
                if (filtreli.isEmpty) {
                  return const _BosDurum();
                }
                return Column(
                  children: filtreli
                      .map((h) => HareketKarti(
                            hareket: h,
                            paraFormat: _paraFormat,
                            onSil: h.silinebilir ? () => _silmeyiOnayla(h) : null,
                            onFis: h.silinebilir && (h.tur == 'odeme' || h.tur == 'tahsilat')
                                ? () => _odemeFisiGoster(h.kayitId!)
                                : null,
                          ))
                      .toList(),
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => _HataKutusu(mesaj: '$e'),
            ),
            const SizedBox(height: 90),
          ],
        ),
      ),
      // İki düğme ekranı ikiye böler: dar telefonda (360 px) yan yana sığmıyor, taşıyordu.
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: FloatingActionButton.extended(
                heroTag: 'tahsilat',
            onPressed: _tahsilatAlDialogGoster,
            backgroundColor: AppColors.success,
            icon: const Icon(Icons.arrow_downward_rounded),
            label: const Text('Tahsilat Al'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FloatingActionButton.extended(
                heroTag: 'odeme',
            onPressed: _odemeYapDialogGoster,
            backgroundColor: AppColors.primary,
            icon: const Icon(Icons.arrow_upward_rounded),
            label: const Text('Ödeme Yap'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<CariHareket> _turFiltresiUygula(List<CariHareket> hepsi) {
    switch (_filtre) {
      case _EkstreFiltre.tumu:
        return hepsi;
      case _EkstreFiltre.sut:
        return hepsi.where((h) => h.tur == 'sut').toList();
      case _EkstreFiltre.yem:
        return hepsi.where((h) => h.tur == 'yem').toList();
      case _EkstreFiltre.odemeler:
        return hepsi.where((h) => h.tur == 'odeme' || h.tur == 'tahsilat').toList();
    }
  }

  Future<void> _tarihFiltreSec() async {
    final simdi = DateTime.now();
    final secilen = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(simdi.year, simdi.month, simdi.day),
      initialDateRange: (_baslangic != null && _bitis != null)
          ? DateTimeRange(start: _baslangic!, end: _bitis!)
          : DateTimeRange(start: DateTime(simdi.year, simdi.month, 1), end: DateTime(simdi.year, simdi.month, simdi.day)),
      helpText: 'Tarih Aralığı Seçin',
    );
    if (secilen != null) {
      setState(() {
        // Gün hassasiyetine normalize et (bkz. provider doc yorumu).
        _baslangic = DateTime(secilen.start.year, secilen.start.month, secilen.start.day);
        _bitis = DateTime(secilen.end.year, secilen.end.month, secilen.end.day);
      });
    }
  }

  /// İşletmenin cariye nakit ödemesi — bakiye AZALIR (fazla ödenirse
  /// negatife döner, yani cari işletmeye borçlanır).
  Future<void> _odemeYapDialogGoster() => _nakitHareketGir(tahsilatMi: false);

  /// İşletmenin cariden nakit tahsil etmesi — bakiye ARTAR (cari borcu azalır).
  Future<void> _tahsilatAlDialogGoster() => _nakitHareketGir(tahsilatMi: true);

  Future<void> _nakitHareketGir({required bool tahsilatMi}) async {
    final girdi = await showModalBottomSheet<NakitHareketGirdisi>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => OdemeAlBottomSheet(
        cariAdi: widget.cari.tamAd,
        baslik: tahsilatMi ? 'Tahsilat Al (Cariden)' : 'Ödeme Yap (Cariye)',
      ),
    );
    if (girdi == null) return;

    final notifier = ref.read(cariHesapNotifierProvider.notifier);
    final int kayitId;
    try {
      if (tahsilatMi) {
        kayitId = await notifier.tahsilatAl(
            cariId: cariId, tutar: girdi.tutar, tarih: girdi.tarih, aciklama: girdi.aciklama);
      } else {
        kayitId = await notifier.odemeYap(
            cariId: cariId, tutar: girdi.tutar, tarih: girdi.tarih, aciklama: girdi.aciklama);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Kayıt yapılamadı: $e'),
        backgroundColor: AppColors.danger,
      ));
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${_paraFormat.format(girdi.tutar)} ${tahsilatMi ? 'tahsilat' : 'ödeme'} kaydedildi'),
      action: girdi.fisVer ? null : SnackBarAction(label: 'FİŞ', onPressed: () => _odemeFisiGoster(kayitId)),
    ));
    // Kayıt yapıldı; fiş hazırlanamasa bile kayıt geçerli (fiş sonradan hareket menüsünden verilebilir).
    if (girdi.fisVer) await _odemeFisiGoster(kayitId, yeniKayit: true);
  }

  /// Ödeme/tahsilat fişi: önceki bakiye, tutar, kalan bakiye. Bakiye, ekrandaki
  /// tarih filtresinden BAĞIMSIZ olarak tüm hareketlerden hesaplanır.
  Future<void> _odemeFisiGoster(int kayitId, {bool yeniKayit = false}) async {
    // autoDispose: tarih filtresi açıkken bu (filtresiz) ekstreyi izleyen yok; okuma
    // bitene kadar dinleyici tutulur, yoksa hesaplama yarıda atılabilir.
    final tumu = cariEkstreProvider((cariId: cariId, baslangic: null, bitis: null));
    final dinleyici = ref.listenManual(tumu, (_, __) {});
    try {
      final ekstre = await ref.read(tumu.future);
      final ayar = await FisAyarlari.yukle();
      final fis = odemeFisiOlustur(
        tumHareketler: ekstre.hareketler,
        kayitId: kayitId,
        ureticiAdi: widget.cari.tamAd,
        isletmeAdi: ayar.isletmeAdi,
        isletmeTelefon: ayar.isletmeTelefon,
        isletmeAdres: ayar.isletmeAdres,
        altYazi: ayar.altYazi,
      );
      if (!mounted) return;
      if (fis == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kayıt bulunamadı (silinmiş olabilir).')));
        return;
      }
      await fisGoster(context, fis: fis, telefon: widget.cari.telefon, otomatikYazdir: yeniKayit);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Fiş hazırlanamadı: $e'),
        backgroundColor: AppColors.danger,
      ));
    } finally {
      dinleyici.close();
    }
  }

  Future<void> _silmeyiOnayla(CariHareket hareket) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hareketi sil'),
        content: Text(
          '${DateFormat('dd.MM.yyyy').format(hareket.tarih)} tarihli '
          '${_paraFormat.format(hareket.tutar)} tutarındaki ${hareket.baslik} kaydı silinsin mi?\n\n'
          'Silinen kayıt işlem geçmişinde saklanır.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (onay == true && hareket.kayitId != null) {
      // Kapalı döneme ait hareket silinemez; eskiden hata yakalanmıyor,
      // kullanıcı hiçbir mesaj görmüyordu.
      try {
        await ref.read(cariHesapNotifierProvider.notifier).sil(hareket.kayitId!);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hareket silindi')));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Silinemedi: $e'),
          backgroundColor: AppColors.danger,
        ));
      }
    }
  }

  List<Map<String, dynamic>> _hareketMaplerineDonustur(List<CariHareket> hareketler) {
    return hareketler
        .map((h) => {
              'tarih': DateFormat('yyyy-MM-dd').format(h.tarih),
              'islemAdi': h.baslik,
              'kredi': h.kredi,
              'tutar': h.tutar,
              'aciklama': h.aciklama ?? '',
            })
        .toList();
  }

  Future<void> _excelDisaAktar(CariEkstreSonucu? ekstre) async {
    if (ekstre == null) return;
    setState(() => _disaAktariliyor = true);
    try {
      final file = await ExcelExport.exportCariHesapEkstresi(
        cariAdi: widget.cari.tamAd,
        hareketler: _hareketMaplerineDonustur(ekstre.hareketler),
        toplamSut: ekstre.toplamSut,
        toplamYem: ekstre.toplamYem,
        toplamOdeme: ekstre.toplamOdeme,
        toplamTahsilat: ekstre.toplamTahsilat,
        kalanBakiye: ekstre.bakiye,
        baslangic: ekstre.filtreBaslangic,
        bitis: ekstre.filtreBitis,
      );
      await ExcelExport.shareFile(file);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Excel hatası: $e'), backgroundColor: AppColors.danger));
      }
    } finally {
      if (mounted) setState(() => _disaAktariliyor = false);
    }
  }

  Future<void> _pdfDisaAktar(CariEkstreSonucu? ekstre) async {
    if (ekstre == null) return;
    setState(() => _disaAktariliyor = true);
    try {
      final file = await PdfExport.exportCariHesapEkstresi(
        cariAdi: widget.cari.tamAd,
        cariTelefon: widget.cari.telefon,
        hareketler: _hareketMaplerineDonustur(ekstre.hareketler),
        toplamSut: ekstre.toplamSut,
        toplamYem: ekstre.toplamYem,
        toplamOdeme: ekstre.toplamOdeme,
        toplamTahsilat: ekstre.toplamTahsilat,
        kalanBakiye: ekstre.bakiye,
        baslangic: ekstre.filtreBaslangic,
        bitis: ekstre.filtreBitis,
      );
      await PdfExport.paylas(file);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF hatası: $e'), backgroundColor: AppColors.danger));
      }
    } finally {
      if (mounted) setState(() => _disaAktariliyor = false);
    }
  }
}

class _TarihFiltreCubugu extends StatelessWidget {
  final DateTime? baslangic;
  final DateTime? bitis;
  final VoidCallback onFiltreSec;
  final VoidCallback onTemizle;

  const _TarihFiltreCubugu({
    required this.baslangic,
    required this.bitis,
    required this.onFiltreSec,
    required this.onTemizle,
  });

  @override
  Widget build(BuildContext context) {
    final filtreli = baslangic != null && bitis != null;
    final df = DateFormat('d MMM yyyy', 'tr_TR');
    return InkWell(
      onTap: onFiltreSec,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: filtreli ? AppColors.primary.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: filtreli ? AppColors.primary.withOpacity(0.4) : AppColors.border),
        ),
        child: Row(
          children: [
            Icon(Icons.date_range_rounded, size: 18, color: filtreli ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                filtreli ? '${df.format(baslangic!)} — ${df.format(bitis!)}' : 'Tüm Zamanlar',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: filtreli ? AppColors.primary : AppColors.textPrimary,
                ),
              ),
            ),
            if (filtreli)
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: onTemizle,
                color: AppColors.textSecondary,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              )
            else
              Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}

class _BakiyeOzetKarti extends StatelessWidget {
  final CariEkstreSonucu ekstre;
  final NumberFormat paraFormat;
  const _BakiyeOzetKarti({required this.ekstre, required this.paraFormat});

  @override
  Widget build(BuildContext context) {
    final alacakliMi = ekstre.alacakliMi;
    final kapaliMi = ekstre.hesapKapaliMi;
    final renk = kapaliMi ? AppColors.textHint : (alacakliMi ? AppColors.info : AppColors.warning);
    // Tarih filtreliyken rakam DÖNEM NETİDİR; "Ödenecek / Tahsil Edilecek" demek cari genelde
    // tersi durumdayken yanıltıyordu → filtrede tarafsız dönem ifadesi.
    final etiket = ekstre.filtreliMi
        ? (kapaliMi ? 'Dönemde Net Hareket Yok' : (alacakliMi ? 'Dönemde Cari Lehine' : 'Dönemde Cari Aleyhine'))
        : kapaliMi
            ? 'Hesap Kapalı'
            : (alacakliMi ? 'Cari Alacaklı — Ödenecek' : 'Cari Borçlu — Tahsil Edilecek');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withOpacity(0.25), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: renk, borderRadius: BorderRadius.circular(20)),
                child: Text(etiket, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
              if (ekstre.filtreliMi) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                  child: const Text('Dönem Neti', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              paraFormat.format(ekstre.bakiye.abs()),
              style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _MiniIstatistik(baslik: 'Süt (Alacak)', deger: paraFormat.format(ekstre.toplamSut))),
              Container(width: 1, height: 32, color: Colors.white24),
              Expanded(child: _MiniIstatistik(baslik: 'Yem (Borç)', deger: paraFormat.format(ekstre.toplamYem))),
              Container(width: 1, height: 32, color: Colors.white24),
              Expanded(child: _MiniIstatistik(baslik: 'Ödeme', deger: paraFormat.format(ekstre.toplamOdeme))),
              Container(width: 1, height: 32, color: Colors.white24),
              Expanded(child: _MiniIstatistik(baslik: 'Tahsilat', deger: paraFormat.format(ekstre.toplamTahsilat))),
            ],
          ),
          if (ekstre.herhangiFiyatEksikMi) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
              child: const Row(
                children: [
                  Icon(Icons.error_outline, size: 16, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bazı süt/yem kayıtları için fiyat tanımlı değil (0 ₺ hesaplandı) — Süt/Yem Fiyatları ekranından fiyat girin.',
                      style: TextStyle(fontSize: 11, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniIstatistik extends StatelessWidget {
  final String baslik;
  final String deger;
  const _MiniIstatistik({required this.baslik, required this.deger});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(deger,
              maxLines: 1, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
        ),
        const SizedBox(height: 2),
        Text(baslik, style: const TextStyle(color: Colors.white70, fontSize: 10)),
      ],
    );
  }
}

class _FiltreCubugu extends StatelessWidget {
  final _EkstreFiltre secili;
  final ValueChanged<_EkstreFiltre> onSecim;
  const _FiltreCubugu({required this.secili, required this.onSecim});

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, _EkstreFiltre f) {
      final aktif = secili == f;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: aktif,
          onSelected: (_) => onSecim(f),
          selectedColor: AppColors.primary,
          labelStyle: TextStyle(color: aktif ? Colors.white : AppColors.textPrimary, fontWeight: FontWeight.w600),
          backgroundColor: Colors.white,
          side: BorderSide(color: AppColors.border),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip('Tümü', _EkstreFiltre.tumu),
          chip('Süt', _EkstreFiltre.sut),
          chip('Yem', _EkstreFiltre.yem),
          chip('Ödeme/Tahsilat', _EkstreFiltre.odemeler),
        ],
      ),
    );
  }
}

class _BosDurum extends StatelessWidget {
  const _BosDurum();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined, size: 48, color: AppColors.textHint),
          const SizedBox(height: 12),
          Text('Bu filtreye uygun hareket yok', style: TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _OzetIskeleti extends StatelessWidget {
  const _OzetIskeleti();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      decoration: BoxDecoration(color: AppColors.surfaceVar, borderRadius: BorderRadius.circular(20)),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _HataKutusu extends StatelessWidget {
  final String mesaj;
  const _HataKutusu({required this.mesaj});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.danger.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: AppColors.danger),
          const SizedBox(width: 8),
          Expanded(child: Text(mesaj, style: TextStyle(color: AppColors.danger, fontSize: 12))),
        ],
      ),
    );
  }
}
