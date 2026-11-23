import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/providers/veri_surumu_provider.dart';
import '../../data/repositories/fabrika_repository.dart';
import '../../models/fabrika_model.dart';
import '../../utils/app_theme.dart';
import 'fabrika_dialoglari.dart';
import 'fabrika_hesap.dart';
import 'fabrika_providers.dart';
import 'fabrikalar_ekrani.dart';

final _para = NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2);
final _kgBicim = NumberFormat('#,##0.###', 'tr_TR');
final _fiyatBicim = NumberFormat('#,##0.00##', 'tr_TR');
final _gunKisa = DateFormat('d MMM EEE', 'tr_TR');
final _gunUzun = DateFormat('d MMMM yyyy', 'tr_TR');

String _kg(double v) => '${_kgBicim.format(v)} kg';
String _gun(String t) => _gunKisa.format(DateTime.parse(t));

Color _durumRengi(FireDurumu d) => switch (d) {
      FireDurumu.normal => AppRenkler.basari,
      FireDurumu.fire => AppRenkler.hata,
      FireDurumu.fazlaSevk => AppRenkler.uyari,
      FireDurumu.suruyor => AppRenkler.metinUcuncul,
      FireDurumu.tankGirilmemis => AppRenkler.bilgi,
    };

String _durumYazisi(FireDurumu d) => switch (d) {
      FireDurumu.normal => 'Normal',
      FireDurumu.fire => 'Fire yüksek',
      FireDurumu.fazlaSevk => 'Fazla sevk',
      FireDurumu.suruyor => 'Gün sürüyor',
      FireDurumu.tankGirilmemis => 'Tank girilmemiş?',
    };

/// ─────────────────────────────────────────────────────────────
/// TANK & FABRİKA SEVKİYATI
/// ─────────────────────────────────────────────────────────────
/// • Tank / Fire: her gün toplanan süt ile fabrikaya sevk edilen karşılaştırılır
///   (tankta kalan dahil). Fark yüksekse ya da sevk toplanandan fazlaysa uyarır →
///   eksik/yanlış süt girişi ay sonunu beklemeden o gün fark edilir.
/// • Sevkiyat: fabrikaya her teslim (kg, fabrika fiyatı, fiş no).
/// • Fabrika Hesabı: sevk tutarı, fabrikadan alınan ödemeler, kesinti/prim, yürüyen bakiye.
class SevkiyatEkrani extends ConsumerStatefulWidget {
  /// 0: Tank / Fire · 1: Sevkiyat · 2: Fabrika hesabı.
  final int baslangicSekmesi;
  const SevkiyatEkrani({super.key, this.baslangicSekmesi = 0});

  @override
  ConsumerState<SevkiyatEkrani> createState() => _SevkiyatEkraniState();
}

class _SevkiyatEkraniState extends ConsumerState<SevkiyatEkrani> with SingleTickerProviderStateMixin {
  late final TabController _sekme =
      TabController(length: 3, vsync: this, initialIndex: widget.baslangicSekmesi.clamp(0, 2))..addListener(_sekmeDegisti);
  DateTime _ay = DateTime(DateTime.now().year, DateTime.now().month);
  int? _fabrikaId;
  bool _islem = false;

  String get _ayAnahtari => DateFormat('yyyy-MM').format(_ay);
  String get _ayAdi => DateFormat('MMMM yyyy', 'tr_TR').format(_ay);
  bool get _buAy {
    final n = DateTime.now();
    return _ay.year == n.year && _ay.month == n.month;
  }

  void _sekmeDegisti() {
    if (!_sekme.indexIsChanging) setState(() {});
  }

  @override
  void dispose() {
    _sekme.dispose();
    super.dispose();
  }

  void _mesaj(String m, {bool hata = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: hata ? AppRenkler.hata : AppRenkler.basari,
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// Pencere/işlem çalıştırır; kaydedildiyse ekranları yeniler. Aynı anda tek işlem.
  Future<void> _calistir(Future<bool> Function(FabrikaRepository repo) islem, {String? basariMesaji}) async {
    if (_islem) return;
    setState(() => _islem = true);
    try {
      final repo = await ref.read(fabrikaRepositoryProvider.future);
      if (!mounted) return;
      final degisti = await islem(repo);
      if (degisti) {
        ref.veriDegisti();
        if (basariMesaji != null) _mesaj(basariMesaji);
      }
    } catch (e) {
      _mesaj(e is FabrikaKayitHatasi ? e.mesaj : 'İşlem yapılamadı: $e', hata: true);
    } finally {
      if (mounted) setState(() => _islem = false);
    }
  }

  /// Fabrika yoksa önce fabrika tanımlatır. Dönüş: güncel fabrika listesi (boşsa vazgeçildi).
  Future<List<Fabrika>> _fabrikalarHazir(FabrikaRepository repo) async {
    var liste = await repo.fabrikalar();
    if (liste.where((f) => f.aktif).isEmpty && mounted) {
      _mesaj('Önce sütü teslim ettiğiniz fabrikayı ekleyin.');
      final eklendi = await fabrikaPenceresi(context, repo: repo);
      if (eklendi != true) return const [];
      ref.veriDegisti();
      liste = await repo.fabrikalar();
    }
    return liste.where((f) => f.aktif).isEmpty ? const [] : liste;
  }

  Future<void> _sevkiyatEkle({DateTime? tarih}) => _calistir((repo) async {
        final fabrikalar = await _fabrikalarHazir(repo);
        if (fabrikalar.isEmpty || !mounted) return false;
        return await sevkiyatPenceresi(context, repo: repo, fabrikalar: fabrikalar, tarih: tarih) == true;
      }, basariMesaji: 'Sevkiyat kaydedildi ✓');

  Future<void> _sevkiyatDuzenle(Sevkiyat s) => _calistir((repo) async {
        final fabrikalar = await repo.fabrikalar();
        if (!mounted) return false;
        return await sevkiyatPenceresi(context, repo: repo, fabrikalar: fabrikalar, mevcut: s) == true;
      }, basariMesaji: 'Sevkiyat güncellendi ✓');

  Future<void> _sevkiyatSil(Sevkiyat s, String fabrikaAdi) => _calistir((repo) async {
        final onay = await silmeOnayi(context, 'Sevkiyat silinsin mi?',
            '$fabrikaAdi · ${_gunUzun.format(DateTime.parse(s.tarih))}${s.saat != null ? ' ${s.saat}' : ''}\n${_kg(s.kg)}'
                '${s.fiyatsiz ? '' : ' · ${_para.format(s.tutar)}'}\n\nFabrika hesabı ve fire hesabı değişir.');
        if (!onay) return false;
        await repo.sevkiyatSil(s.id!);
        return true;
      }, basariMesaji: 'Sevkiyat silindi');

  Future<void> _tank({DateTime? tarih}) =>
      _calistir((repo) async => await tankPenceresi(context, repo: repo, tarih: tarih) == true, basariMesaji: 'Tank kaydedildi ✓');

  Future<void> _hareketEkle(Fabrika f, FabrikaHareketTuru tur) =>
      _calistir((repo) async => await hareketPenceresi(context, repo: repo, fabrika: f, tur: tur) == true,
          basariMesaji: 'Kaydedildi ✓');

  Future<void> _hareketDuzenle(Fabrika f, FabrikaHareketi h) =>
      _calistir((repo) async => await hareketPenceresi(context, repo: repo, fabrika: f, mevcut: h) == true,
          basariMesaji: 'Güncellendi ✓');

  Future<void> _hareketSil(FabrikaHareketi h) => _calistir((repo) async {
        final onay = await silmeOnayi(context, '${h.tur.ad} silinsin mi?',
            '${_gunUzun.format(DateTime.parse(h.tarih))} · ${_para.format(h.tutar)}${h.aciklama != null ? '\n${h.aciklama}' : ''}');
        if (!onay) return false;
        await repo.hareketSil(h.id!);
        return true;
      }, basariMesaji: 'Silindi');

  Future<void> _fiyatUygula(Fabrika f) async {
    final (bas, son) = ayAraligi(_ayAnahtari);
    await _calistir((repo) async {
      final n = await fiyatUygulaPenceresi(context,
          repo: repo, fabrika: f, bas: gunAnahtari(bas), son: gunAnahtari(son), ayAdi: _ayAdi);
      if (n == null) return false;
      _mesaj(n == 0 ? 'Değişen sevkiyat olmadı.' : '$n sevkiyatın fiyatı güncellendi ✓');
      return n > 0;
    });
  }

  Future<void> _fabrikalariYonet() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const FabrikalarEkrani()));
  }

  @override
  Widget build(BuildContext context) {
    final fabrikalar = ref.watch(fabrikalarProvider).valueOrNull ?? const <Fabrika>[];
    // Seçili fabrika silinmişse / hiç seçilmemişse ilk (aktif) fabrika.
    if (fabrikalar.isNotEmpty && !fabrikalar.any((f) => f.id == _fabrikaId)) _fabrikaId = fabrikalar.first.id;

    return Scaffold(
      backgroundColor: AppRenkler.arkaplan,
      appBar: AppBar(
        title: const Text('Tank & Fabrika Sevkiyatı', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Fabrikalar',
            icon: const Icon(Icons.factory_outlined),
            onPressed: _islem ? null : _fabrikalariYonet,
          ),
        ],
        bottom: TabBar(
          controller: _sekme,
          tabs: const [
            Tab(text: 'Tank / Fire'),
            Tab(text: 'Sevkiyat'),
            Tab(text: 'Fabrika'),
          ],
        ),
      ),
      body: Column(children: [
        _ayKutusu(),
        Expanded(
          child: TabBarView(controller: _sekme, children: [
            _FireSekmesi(ay: _ayAnahtari, buAy: _buAy, tankGir: (t) => _tank(tarih: t)),
            _SevkiyatSekmesi(
              ay: _ayAnahtari,
              fabrikalar: fabrikalar,
              duzenle: _sevkiyatDuzenle,
              sil: _sevkiyatSil,
            ),
            _FabrikaSekmesi(
              ay: _ayAnahtari,
              ayAdi: _ayAdi,
              fabrikalar: fabrikalar,
              seciliId: _fabrikaId,
              sec: (id) => setState(() => _fabrikaId = id),
              hareketEkle: _hareketEkle,
              hareketDuzenle: _hareketDuzenle,
              hareketSil: _hareketSil,
              sevkiyatDuzenle: _sevkiyatDuzenle,
              fiyatUygula: _fiyatUygula,
              fabrikaEkle: () => _calistir((repo) async => await fabrikaPenceresi(context, repo: repo) == true,
                  basariMesaji: 'Fabrika eklendi ✓'),
            ),
          ]),
        ),
      ]),
      floatingActionButton: _fab(fabrikalar),
    );
  }

  Widget? _fab(List<Fabrika> fabrikalar) {
    switch (_sekme.index) {
      case 0:
        return FloatingActionButton.extended(
          heroTag: 'fab_tank',
          onPressed: _islem ? null : () => _tank(),
          icon: const Icon(Icons.propane_tank_outlined),
          label: const Text('Gün sonu tank'),
        );
      case 1:
        return FloatingActionButton.extended(
          heroTag: 'fab_sevk',
          onPressed: _islem ? null : () => _sevkiyatEkle(),
          icon: const Icon(Icons.local_shipping_outlined),
          label: const Text('Sevkiyat ekle'),
        );
      default:
        final f = fabrikalar.where((x) => x.id == _fabrikaId).firstOrNull;
        if (f == null) return null;
        return FloatingActionButton.extended(
          heroTag: 'fab_tahsilat',
          onPressed: _islem ? null : () => _hareketEkle(f, FabrikaHareketTuru.tahsilat),
          icon: const Icon(Icons.payments_outlined),
          label: const Text('Ödeme alındı'),
        );
    }
  }

  Widget _ayKutusu() => Material(
        color: AppRenkler.yuzey,
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'Önceki ay',
            onPressed: () => setState(() => _ay = DateTime(_ay.year, _ay.month - 1)),
          ),
          Expanded(
            child: Text(_ayAdi,
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: 'Sonraki ay',
            onPressed: _buAy ? null : () => setState(() => _ay = DateTime(_ay.year, _ay.month + 1)),
          ),
        ]),
      );
}

// ───────────────────────────── ORTAK PARÇALAR ─────────────────────────────

Widget _yukleniyorYaDaHata<T>(AsyncValue<T> v, Widget Function(T) veri) => v.when(
      data: veri,
      loading: () => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
      error: (e, _) => Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Yüklenemedi: $e', style: const TextStyle(color: AppRenkler.hata)))),
    );

class _Bilgi extends StatelessWidget {
  final IconData ikon;
  final String metin;
  const _Bilgi(this.ikon, this.metin);
  static const renk = AppRenkler.metinIkincil;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(ikon, color: renk),
            const SizedBox(width: 10),
            Expanded(child: Text(metin, style: TextStyle(color: renk))),
          ]),
        ),
      );
}

/// Etiket + değer satırı (dar ekranda değer alta kayabilir).
class _Satir extends StatelessWidget {
  final String etiket;
  final String deger;
  final Color? renk;
  final bool kalin;
  const _Satir(this.etiket, this.deger, {this.renk, this.kalin = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Wrap(alignment: WrapAlignment.spaceBetween, spacing: 12, children: [
          Text(etiket, style: const TextStyle(color: AppRenkler.metinIkincil)),
          Text(deger, style: TextStyle(fontWeight: kalin ? FontWeight.w800 : FontWeight.w600, color: renk)),
        ]),
      );
}

// ───────────────────────────── TANK / FİRE ─────────────────────────────

class _FireSekmesi extends ConsumerWidget {
  final String ay;
  final bool buAy;
  final void Function(DateTime) tankGir;
  const _FireSekmesi({required this.ay, required this.buAy, required this.tankGir});

  @override
  Widget build(BuildContext context, WidgetRef ref) => _yukleniyorYaDaHata(ref.watch(fireAyiProvider(ay)), (FireAyi f) {
        if (f.gunler.isEmpty) {
          return ListView(padding: const EdgeInsets.all(16), children: const [
            _Bilgi(Icons.inbox_outlined, 'Bu ay için süt ya da sevkiyat kaydı yok.'),
            _Aciklama(),
          ]);
        }
        final gunler = f.gunler.reversed.toList(); // en yeni üstte
        return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
          _FireOzetKarti(ozet: f.kesinOzet, bugunHaric: buAy && f.gunler.any((g) => g.bugun)),
          const SizedBox(height: 8),
          for (final g in gunler) _FireGunKarti(g, onTap: () => tankGir(DateTime.parse(g.tarih))),
          const SizedBox(height: 8),
          const _Aciklama(),
        ]);
      });
}

class _FireOzetKarti extends StatelessWidget {
  final FireOzeti ozet;
  final bool bugunHaric;
  const _FireOzetKarti({required this.ozet, required this.bugunHaric});

  @override
  Widget build(BuildContext context) {
    final renk = _durumRengi(ozet.durum);
    final y = ozet.yuzde;
    final String yorum = ozet.gunSayisi == 0 ? 'Bugün sürüyor; kesinleşmiş gün yok.' : switch (ozet.durum) {
      FireDurumu.fire => 'Kayıp yüksek: sevkiyat ya da tank girilmemiş olabilir, tartıları kontrol edin.',
      FireDurumu.fazlaSevk => 'Toplanandan fazla süt sevk edilmiş: bazı üreticilerin süt girişi EKSİK olabilir.',
      _ => 'Toplanan ile sevk edilen uyumlu.',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(bugunHaric ? 'Ay özeti (bugün hariç)' : 'Ay özeti', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          _Satir('Üreticilerden toplanan', _kg(ozet.toplanan)),
          if (ozet.tankBaslangic > 0) _Satir('Önceki aydan tankta', _kg(ozet.tankBaslangic)),
          _Satir('Fabrikaya sevk edilen', _kg(ozet.sevk)),
          if (ozet.tankSon > 0) _Satir('Tankta kalan', _kg(ozet.tankSon)),
          const Divider(),
          _Satir('Fark', '${_kg(ozet.fark)}${y == null ? '' : '  (%${y.toStringAsFixed(2).replaceAll('.', ',')})'}',
              renk: renk, kalin: true),
          const SizedBox(height: 4),
          Text(yorum, style: TextStyle(color: renk, fontSize: 13)),
        ]),
      ),
    );
  }
}

class _FireGunKarti extends StatelessWidget {
  final FireGunu g;
  final VoidCallback onTap;
  const _FireGunKarti(this.g, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = g.durum;
    final renk = _durumRengi(d);
    final y = g.yuzde;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text(g.bugun ? '${_gun(g.tarih)} · bugün' : _gun(g.tarih),
                    style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: renk.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: Text(_durumYazisi(d), style: TextStyle(color: renk, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 4),
            Wrap(spacing: 14, runSpacing: 2, children: [
              if (g.tankOnceki > 0) Text('Devir ${_kg(g.tankOnceki)}', style: const TextStyle(fontSize: 13)),
              Text('Toplanan ${_kg(g.toplanan)}', style: const TextStyle(fontSize: 13)),
              Text('Sevk ${_kg(g.sevk)}', style: const TextStyle(fontSize: 13)),
              if (g.tankSonu > 0) Text('Tankta ${_kg(g.tankSonu)}', style: const TextStyle(fontSize: 13)),
              Text('Fark ${_kg(g.fark)}${y == null ? '' : ' (%${y.toStringAsFixed(1).replaceAll('.', ',')})'}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: renk)),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _Aciklama extends StatelessWidget {
  const _Aciklama();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          'Fark = (önceki gün tankta kalan + toplanan) − (sevk + gün sonu tankta kalan).\n'
          '• Süt ertesi güne kaldıysa güne dokunup "gün sonu tank" girin; yoksa kayıp gibi görünür.\n'
          '• "Fazla sevk": toplanandan fazla süt gitmiş → bir üreticinin sütü girilmemiş olabilir.\n'
          '• "Tank girilmemiş?": bir gün eksik, ertesi gün fazla → süt gece tankta kalmış; o güne tank girin.\n'
          '• Uyarı: %${_kgBicim.format(fireUyariYuzde)} üzeri kayıp ya da ${_kgBicim.format(farkToleransKg)} kg üzeri fazla sevk '
          '(${_kgBicim.format(farkToleransKg)} kg\'a kadar fark tartı payı sayılır).',
          style: const TextStyle(fontSize: 12, color: AppRenkler.metinUcuncul),
        ),
      );
}

// ───────────────────────────── SEVKİYATLAR ─────────────────────────────

class _SevkiyatSekmesi extends ConsumerWidget {
  final String ay;
  final List<Fabrika> fabrikalar;
  final void Function(Sevkiyat) duzenle;
  final void Function(Sevkiyat, String fabrikaAdi) sil;
  const _SevkiyatSekmesi({required this.ay, required this.fabrikalar, required this.duzenle, required this.sil});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _yukleniyorYaDaHata(ref.watch(ayinSevkiyatlariProvider(ay)), (List<Sevkiyat> liste) {
        if (liste.isEmpty) {
          return ListView(padding: const EdgeInsets.all(16), children: [
            _Bilgi(Icons.local_shipping_outlined,
                fabrikalar.isEmpty
                    ? 'Henüz fabrika yok. "Sevkiyat ekle" ile önce fabrikayı, sonra ilk sevkiyatı girin.'
                    : 'Bu ay sevkiyat yok. Aşağıdaki "Sevkiyat ekle" ile girin.'),
          ]);
        }
        final adlar = {for (final f in fabrikalar) f.id: f.ad};
        final toplamKg = liste.fold(0.0, (t, s) => t + s.kg);
        final toplamTutar = liste.fold(0.0, (t, s) => t + s.tutar);
        final fiyatsiz = liste.where((s) => s.fiyatsiz).length;
        return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _Satir('Sevkiyat sayısı', '${liste.length}'),
                _Satir('Toplam sevk', _kg(toplamKg), kalin: true),
                _Satir('Toplam tutar', _para.format(toplamTutar), kalin: true),
                if (fiyatsiz > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('$fiyatsiz sevkiyatın fiyatı girilmemiş (tutarı 0 sayıldı). Fabrika sekmesinden "Fiyat uygula".',
                        style: const TextStyle(color: AppRenkler.uyari, fontSize: 13)),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          for (final s in liste.reversed)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 3),
              child: ListTile(
                onTap: () => duzenle(s),
                leading: const Icon(Icons.local_shipping_outlined, color: AppRenkler.birincil),
                title: Text('${_kg(s.kg)} · ${adlar[s.fabrikaId] ?? 'Fabrika #${s.fabrikaId}'}',
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  [
                    '${_gun(s.tarih)}${s.saat != null ? ' ${s.saat}' : ''}',
                    s.fiyatsiz ? 'fiyat girilmedi' : '${_fiyatBicim.format(s.birimFiyat)} ₺/kg = ${_para.format(s.tutar)}',
                    if (s.fisNo != null) 'Fiş ${s.fisNo}',
                    if (s.plaka != null) s.plaka!,
                    if (s.aciklama != null) s.aciklama!,
                  ].join(' · '),
                  style: TextStyle(color: s.fiyatsiz ? AppRenkler.uyari : null),
                ),
                trailing: IconButton(
                  tooltip: 'Sil',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => sil(s, adlar[s.fabrikaId] ?? 'Fabrika'),
                ),
              ),
            ),
        ]);
      });
}

// ───────────────────────────── FABRİKA HESABI ─────────────────────────────

class _FabrikaSekmesi extends ConsumerWidget {
  final String ay;
  final String ayAdi;
  final List<Fabrika> fabrikalar;
  final int? seciliId;
  final ValueChanged<int> sec;
  final void Function(Fabrika, FabrikaHareketTuru) hareketEkle;
  final void Function(Fabrika, FabrikaHareketi) hareketDuzenle;
  final void Function(FabrikaHareketi) hareketSil;
  final void Function(Sevkiyat) sevkiyatDuzenle;
  final void Function(Fabrika) fiyatUygula;
  final VoidCallback fabrikaEkle;

  const _FabrikaSekmesi({
    required this.ay,
    required this.ayAdi,
    required this.fabrikalar,
    required this.seciliId,
    required this.sec,
    required this.hareketEkle,
    required this.hareketDuzenle,
    required this.hareketSil,
    required this.sevkiyatDuzenle,
    required this.fiyatUygula,
    required this.fabrikaEkle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = fabrikalar.where((x) => x.id == seciliId).firstOrNull;
    if (f == null) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        const _Bilgi(Icons.factory_outlined, 'Henüz fabrika yok. Sütü teslim ettiğiniz fabrikayı ekleyin.'),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: fabrikaEkle, icon: const Icon(Icons.add_business_outlined), label: const Text('Fabrika ekle')),
      ]);
    }
    final bakiye = ref.watch(fabrikaBakiyeleriProvider).valueOrNull?[f.id] ?? 0;
    final ekstre = ref.watch(fabrikaEkstresiProvider((fabrikaId: f.id!, ay: ay)));
    return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
      if (fabrikalar.length > 1)
        DropdownButtonFormField<int>(
          key: ValueKey('fabrika_sec_${f.id}'),
          initialValue: f.id,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Fabrika', prefixIcon: Icon(Icons.factory_outlined), isDense: true),
          items: [
            for (final x in fabrikalar)
              DropdownMenuItem(value: x.id, child: Text(x.aktif ? x.ad : '${x.ad} (pasif)', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) {
            if (v != null) sec(v);
          },
        )
      else
        Text(f.ad, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
      const SizedBox(height: 8),
      _BakiyeKarti(bakiye),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 4, children: [
        OutlinedButton.icon(
          onPressed: () => hareketEkle(f, FabrikaHareketTuru.kesinti),
          icon: const Icon(Icons.remove_circle_outline, size: 18),
          label: const Text('Kesinti'),
        ),
        OutlinedButton.icon(
          onPressed: () => hareketEkle(f, FabrikaHareketTuru.ek),
          icon: const Icon(Icons.add_circle_outline, size: 18),
          label: const Text('Prim / ek'),
        ),
        OutlinedButton.icon(
          onPressed: () => fiyatUygula(f),
          icon: const Icon(Icons.price_change_outlined, size: 18),
          label: const Text('Fiyat uygula'),
        ),
      ]),
      const SizedBox(height: 8),
      _yukleniyorYaDaHata(ekstre, (FabrikaEkstresi e) => _ekstre(context, f, e)),
    ]);
  }

  Widget _ekstre(BuildContext context, Fabrika f, FabrikaEkstresi e) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('$ayAdi hesabı', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            _Satir('Önceki aydan devir', _para.format(e.devir)),
            _Satir('Sevk (${_kg(e.sevkKg)})', '+ ${_para.format(e.sevkTutar)}'),
            if (e.ek > 0) _Satir('Prim / ek', '+ ${_para.format(e.ek)}'),
            if (e.kesinti > 0) _Satir('Kesinti', '− ${_para.format(e.kesinti)}'),
            _Satir('Alınan ödeme', '− ${_para.format(e.tahsilat)}'),
            const Divider(),
            _Satir('Ay sonu bakiye', _para.format(e.sonBakiye),
                kalin: true, renk: e.sonBakiye >= 0 ? AppRenkler.basari : AppRenkler.hata),
            if (e.fiyatsizSayisi > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${e.fiyatsizSayisi} sevkiyatın fiyatı girilmemiş; tutarı 0 sayıldı. '
                  'Fabrika fiyatı açıklayınca "Fiyat uygula".',
                  style: const TextStyle(color: AppRenkler.uyari, fontSize: 13),
                ),
              ),
          ]),
        ),
      ),
      const SizedBox(height: 6),
      if (e.satirlar.isEmpty)
        const _Bilgi(Icons.inbox_outlined, 'Bu ay hareket yok.')
      else
        for (final s in e.satirlar.reversed) _ekstreSatiri(f, s),
    ]);
  }

  Widget _ekstreSatiri(Fabrika f, FabrikaEkstreSatiri s) {
    final sv = s.sevkiyat, h = s.hareket;
    final arti = s.etki >= 0;
    final String baslik;
    final String alt;
    final IconData ikon;
    if (sv != null) {
      baslik = 'Sevkiyat ${_kg(sv.kg)}';
      alt = [
        '${_gun(s.tarih)}${sv.saat != null ? ' ${sv.saat}' : ''}',
        sv.fiyatsiz ? 'fiyat girilmedi' : '${_fiyatBicim.format(sv.birimFiyat)} ₺/kg',
        if (sv.fisNo != null) 'Fiş ${sv.fisNo}',
      ].join(' · ');
      ikon = Icons.local_shipping_outlined;
    } else {
      baslik = h!.tur.ad;
      alt = [_gun(s.tarih), if (h.aciklama != null) h.aciklama!].join(' · ');
      ikon = switch (h.tur) {
        FabrikaHareketTuru.tahsilat => Icons.payments_outlined,
        FabrikaHareketTuru.kesinti => Icons.remove_circle_outline,
        FabrikaHareketTuru.ek => Icons.add_circle_outline,
      };
    }
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        onTap: () => sv != null ? sevkiyatDuzenle(sv) : hareketDuzenle(f, h!),
        onLongPress: h == null ? null : () => hareketSil(h),
        leading: Icon(ikon, color: arti ? AppRenkler.basari : AppRenkler.hata),
        title: Text(baslik, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('$alt\nBakiye: ${_para.format(s.bakiye)}'),
        isThreeLine: true,
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${arti ? '+' : '−'} ${_para.format(s.etki.abs())}',
              style: TextStyle(fontWeight: FontWeight.w700, color: arti ? AppRenkler.basari : AppRenkler.hata)),
          if (h != null)
            InkWell(
              onTap: () => hareketSil(h),
              child: const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Icon(Icons.delete_outline_rounded, size: 20, color: AppRenkler.metinUcuncul),
              ),
            ),
        ]),
      ),
    );
  }
}

class _BakiyeKarti extends StatelessWidget {
  final double bakiye;
  const _BakiyeKarti(this.bakiye);

  @override
  Widget build(BuildContext context) {
    final String baslik;
    final Color renk;
    if (bakiye > 0.004) {
      baslik = 'Fabrikanın size borcu (güncel)';
      renk = AppRenkler.basari;
    } else if (bakiye < -0.004) {
      baslik = 'Fabrikadan fazla ödeme alınmış';
      renk = AppRenkler.hata;
    } else {
      baslik = 'Fabrika hesabı kapalı';
      renk = AppRenkler.metinIkincil;
    }
    return Card(
      color: renk.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(baslik, style: TextStyle(color: renk, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(_para.format(bakiye.abs()), style: TextStyle(color: renk, fontSize: 24, fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
    );
  }
}
