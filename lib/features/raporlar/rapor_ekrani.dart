import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/providers/veri_surumu_provider.dart';
import '../../features/cari/providers/cari_providers.dart' show butunCarilerProvider;
import '../../models/cari_model.dart';
import '../../utils/turkce.dart';
import 'rapor_disa_aktarim.dart';
import 'rapor_modeli.dart';
import 'rapor_servisi.dart';

final raporServisiProvider = FutureProvider<RaporServisi>((ref) async => RaporServisi(
      cariRepo: await ref.watch(cariRepositoryProvider.future),
      sutRepo: await ref.watch(sutRepositoryProvider.future),
      yemRepo: await ref.watch(yemRepositoryProvider.future),
      fiyatRepo: await ref.watch(cariFiyatRepositoryProvider.future),
      odemeRepo: await ref.watch(cariOdemeRepositoryProvider.future),
    ));

/// Veri değişince (süt/yem/ödeme/fiyat girişi) açık rapor kendiliğinden yenilenir.
final raporProvider = FutureProvider.autoDispose.family<RaporTablosu, (RaporTuru, String, String, int?)>((ref, a) async {
  ref.watch(veriSurumuProvider);
  final s = await ref.watch(raporServisiProvider.future);
  return s.olustur(a.$1, RaporFiltresi(bas: a.$2, bit: a.$3, cariId: a.$4));
});

const _lacivert = Color(0xFF1A237E);

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _goster(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

const _grupIkonu = {
  'sut': (Icons.water_drop, Colors.blue),
  'yem': (Icons.grass, Colors.green),
  'hesap': (Icons.account_balance_wallet_outlined, Colors.deepPurple),
  'kontrol': (Icons.fact_check_outlined, Colors.orange),
};

/// ─────────────────────────────────────────────────────────────
/// RAPORLAR — gruplu liste; her rapor tarih (ve gerekirse cari) seçilerek
/// açılır, Excel / PDF / Yazdır ile paylaşılır.
/// ─────────────────────────────────────────────────────────────
class RaporAnaEkrani extends StatelessWidget {
  const RaporAnaEkrani({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF8FAFF),
        appBar: AppBar(title: const Text('Raporlar', style: TextStyle(fontWeight: FontWeight.bold)), foregroundColor: _lacivert),
        body: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
          for (final g in raporGruplari.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
              child: Row(children: [
                Icon(_grupIkonu[g.key]!.$1, color: _grupIkonu[g.key]!.$2, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(g.value,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: _lacivert)),
                ),
              ]),
            ),
            Card(
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Column(children: [
                for (final r in RaporTuru.values.where((r) => r.grup == g.key))
                  ListTile(
                    key: ValueKey('rapor-${r.name}'),
                    leading: Icon(Icons.insert_chart_outlined, color: _grupIkonu[g.key]!.$2),
                    title: Text(r.baslik, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(r.aciklama, maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RaporEkrani(tur: r))),
                  ),
              ]),
            ),
          ],
        ]),
      );
}

class RaporEkrani extends ConsumerStatefulWidget {
  final RaporTuru tur;
  final int? cariId;
  const RaporEkrani({super.key, required this.tur, this.cariId});
  @override
  ConsumerState<RaporEkrani> createState() => _RaporEkraniState();
}

class _RaporEkraniState extends ConsumerState<RaporEkrani> {
  static DateTime get _bugun {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  late DateTimeRange _aralik = widget.tur.yillikVarsayilan
      ? DateTimeRange(start: DateTime(_bugun.year, 1, 1), end: _bugun)
      : DateTimeRange(start: DateTime(_bugun.year, _bugun.month, 1), end: _bugun);
  late int? _cari = widget.cariId;
  bool _aktariliyor = false;

  Future<void> _aktar(RaporTablosu t, Future<void> Function(RaporTablosu) is_) async {
    if (_aktariliyor) return;
    setState(() => _aktariliyor = true);
    try {
      await is_(t);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Dışa aktarılamadı: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _aktariliyor = false);
    }
  }

  void _hazirAralik(String k) {
    final b = _bugun;
    setState(() {
      _aralik = switch (k) {
        'bugun' => DateTimeRange(start: b, end: b),
        'buay' => DateTimeRange(start: DateTime(b.year, b.month, 1), end: b),
        'gecenay' => DateTimeRange(start: DateTime(b.year, b.month - 1, 1), end: DateTime(b.year, b.month, 0)),
        _ => DateTimeRange(start: DateTime(b.year, 1, 1), end: b),
      };
    });
  }

  Future<void> _ozelAralik() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(_bugun.year + 1, 12, 31),
      initialDateRange: _aralik,
      locale: const Locale('tr', 'TR'),
    );
    if (r != null) setState(() => _aralik = DateTimeRange(start: DateUtils.dateOnly(r.start), end: DateUtils.dateOnly(r.end)));
  }

  Future<void> _cariSec(List<Cari> cariler) async {
    final secim = await showModalBottomSheet<(bool, int?)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CariSecici(cariler: cariler, hepsiSecilebilir: !widget.tur.cariZorunlu),
    );
    if (secim != null) setState(() => _cari = secim.$2);
  }

  @override
  Widget build(BuildContext context) {
    final tur = widget.tur;
    final anahtar = (tur, _iso(_aralik.start), _iso(_aralik.end), tur.cariFiltresi ? _cari : null);
    final rapor = ref.watch(raporProvider(anahtar));
    final t = rapor.valueOrNull;
    final yalnizBitis = tur == RaporTuru.bakiyeListesi;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        title: Text(tur.baslik, maxLines: 1, overflow: TextOverflow.ellipsis),
        foregroundColor: _lacivert,
        actions: [
          if (_aktariliyor)
            const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
          else if (t != null && t.satirlar.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'Dışa aktar',
              icon: const Icon(Icons.ios_share),
              onSelected: (k) => _aktar(t, switch (k) {
                'excel' => RaporDisaAktarim.excelPaylas,
                'pdf' => RaporDisaAktarim.pdfPaylas,
                _ => RaporDisaAktarim.yazdir,
              }),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'excel', child: ListTile(leading: Icon(Icons.grid_on, color: Colors.green), title: Text('Excel olarak paylaş'))),
                PopupMenuItem(value: 'pdf', child: ListTile(leading: Icon(Icons.picture_as_pdf, color: Colors.red), title: Text('PDF olarak paylaş'))),
                PopupMenuItem(value: 'yazdir', child: ListTile(leading: Icon(Icons.print), title: Text('Yazdır'))),
              ],
            ),
        ],
      ),
      body: Column(children: [
        Material(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (!yalnizBitis) ...[
                  ActionChip(label: const Text('Bugün'), onPressed: () => _hazirAralik('bugun')),
                  ActionChip(label: const Text('Bu ay'), onPressed: () => _hazirAralik('buay')),
                  ActionChip(label: const Text('Geçen ay'), onPressed: () => _hazirAralik('gecenay')),
                  ActionChip(label: const Text('Bu yıl'), onPressed: () => _hazirAralik('buyil')),
                ],
                ActionChip(
                  key: const ValueKey('raporTarih'),
                  avatar: const Icon(Icons.date_range, size: 18),
                  label: Text(yalnizBitis
                      ? '${_goster(_aralik.end)} itibarıyla'
                      : (_aralik.start == _aralik.end ? _goster(_aralik.start) : '${_goster(_aralik.start)} – ${_goster(_aralik.end)}')),
                  onPressed: () async {
                    if (yalnizBitis) {
                      final d = await showDatePicker(
                          context: context, firstDate: DateTime(2020), lastDate: DateTime(_bugun.year + 1, 12, 31), initialDate: _aralik.end, locale: const Locale('tr', 'TR'));
                      if (d != null) setState(() => _aralik = DateTimeRange(start: DateUtils.dateOnly(d), end: DateUtils.dateOnly(d)));
                    } else {
                      await _ozelAralik();
                    }
                  },
                ),
              ]),
              if (tur.cariFiltresi)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: ref.watch(butunCarilerProvider).when(
                        loading: () => const LinearProgressIndicator(),
                        error: (e, _) => Text('Cariler okunamadı: $e'),
                        data: (cariler) {
                          final secili = cariler.where((c) => c.id == _cari).firstOrNull;
                          return OutlinedButton.icon(
                            key: const ValueKey('raporCari'),
                            icon: const Icon(Icons.person_search),
                            label: Text(secili?.tamAd ?? (tur.cariZorunlu ? 'Cari seçin' : 'Tüm cariler'), overflow: TextOverflow.ellipsis),
                            onPressed: () => _cariSec(cariler),
                          );
                        },
                      ),
                ),
            ]),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: rapor.when(
            skipLoadingOnReload: true,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Rapor hazırlanamadı: $e', textAlign: TextAlign.center))),
            data: (t) => tur.cariZorunlu && _cari == null
                ? const _Bos(ikon: Icons.person_search, mesaj: 'Ekstresi alınacak cariyi seçin')
                : RaporTablosuGorunumu(tablo: t),
          ),
        ),
      ]),
    );
  }
}

class _Bos extends StatelessWidget {
  final IconData ikon;
  final String mesaj;
  const _Bos({required this.ikon, required this.mesaj});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(ikon, size: 56, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text(mesaj, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600])),
          ]),
        ),
      );
}

/// Tablo: telefonda yatay kaydırılır; toplam satırı kalın ve sarı; altta not.
class RaporTablosuGorunumu extends StatelessWidget {
  final RaporTablosu tablo;
  const RaporTablosuGorunumu({super.key, required this.tablo});

  @override
  Widget build(BuildContext context) {
    final t = tablo;
    final not = t.not == null
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(t.not!, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          );
    if (t.satirlar.isEmpty) {
      return ListView(children: [const SizedBox(height: 40), const _Bos(ikon: Icons.inbox, mesaj: 'Seçilen dönemde kayıt yok'), if (not != null) not]);
    }
    DataCell hucre(int i, Object? v, {bool kalin = false}) => DataCell(Text(
          i == 0 && v == 'TOPLAM' ? 'TOPLAM' : hucreMetni(t.sutunlar[i], v),
          style: TextStyle(fontWeight: kalin ? FontWeight.w700 : null),
        ));
    return Scrollbar(
      child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Text('${t.altBaslik} · ${t.satirlar.length} satır', style: TextStyle(color: Colors.grey[700], fontSize: 12)),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(const Color(0xFFE3F2FD)),
            columnSpacing: 18,
            horizontalMargin: 12,
            dataRowMinHeight: 36,
            dataRowMaxHeight: 52,
            columns: [for (final s in t.sutunlar) DataColumn(label: Text(s.ad, style: const TextStyle(fontWeight: FontWeight.w700)), numeric: s.sayisal)],
            rows: [
              for (final r in t.satirlar) DataRow(cells: [for (var i = 0; i < t.sutunlar.length; i++) hucre(i, r[i])]),
              if (t.toplamSatiri)
                DataRow(
                  color: WidgetStateProperty.all(const Color(0xFFFFF9C4)),
                  cells: [for (var i = 0; i < t.sutunlar.length; i++) hucre(i, t.toplamlar[i], kalin: true)],
                ),
            ],
          ),
        ),
        if (not != null) not,
      ]),
    );
  }
}

/// Aranabilir cari seçici (pasifler de listede; ekstre geçmişe dönük alınabilsin).
class _CariSecici extends StatefulWidget {
  final List<Cari> cariler;
  final bool hepsiSecilebilir;
  const _CariSecici({required this.cariler, required this.hepsiSecilebilir});
  @override
  State<_CariSecici> createState() => _CariSeciciState();
}

class _CariSeciciState extends State<_CariSecici> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final l = raporCarileri(widget.cariler).where((c) => aramaEslesir('${c.tamAd} ${c.telefon ?? ''}', _q)).toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            autofocus: false,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Cari ara', isDense: true, border: OutlineInputBorder()),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        Expanded(
          child: ListView(children: [
            if (widget.hepsiSecilebilir)
              ListTile(leading: const Icon(Icons.groups), title: const Text('Tüm cariler'), onTap: () => Navigator.pop(context, (true, null))),
            for (final c in l)
              ListTile(
                title: Text(c.tamAd),
                subtitle: c.aktif ? null : const Text('Pasif'),
                onTap: () => Navigator.pop(context, (true, c.id)),
              ),
          ]),
        ),
      ]),
    );
  }
}
