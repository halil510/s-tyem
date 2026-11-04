import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../theme/app_theme.dart';
import '../widgetlar/ortak_widgetlar.dart';
import '../features/dashboard/providers/dashboard_providers.dart';
import '../features/donem/donem_ekrani.dart';
import '../models/cari_model.dart';
import 'sut_ekrani.dart';

/// Ana KPI / özet ekranı (dashboard).
///
/// Faz 1 modernizasyonu: Artık `DBHelper` ile N+1 sorgu yerine tek bir
/// `dashboardDataProvider` (bkz. `lib/features/dashboard/providers/`)
/// üzerinden besleniyor. Bu provider tüm hesaplamaları az sayıda,
/// verimli sorguyla yapıp bir `DashboardData` nesnesi döner.
class DashboardEkrani extends ConsumerWidget {
  const DashboardEkrani({super.key});

  static const _yemRenkleri = {
    'Süt': AppColors.primary,
    'Besi': AppColors.accent,
    'Buzağı': AppColors.primaryLight,
    'Kuzu': AppColors.info,
    'Tavuk': AppColors.warning,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(dashboardDataProvider);

    return dataAsync.when(
      loading: () => const YukleniyorEkrani(mesaj: 'Veriler hazırlanıyor...'),
      error: (e, _) => Center(child: Text('Hata: $e')),
      data: (data) {
        final ay = DateFormat('MMMM yyyy', 'tr_TR').format(DateTime.now());
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(dashboardDataProvider),
          color: AppColors.primary,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _buildBanner(ay, data),
              if (data.kapanmamisGecenAy != null) ...[
                const SizedBox(height: 12),
                _DonemHatirlatma(ay: data.kapanmamisGecenAy!),
              ],
              const SizedBox(height: 20),
              _buildKpiGrid(data),
              const SizedBox(height: 24),
              if (data.gelmeyenler.isNotEmpty) ...[
                BolumBasligi(
                    baslik: 'BUGÜN GELMEYENLER (${data.gelmeyenler.length})'),
                const SizedBox(height: 8),
                _GelmeyenlerListesi(gelmeyenler: data.gelmeyenler),
                const SizedBox(height: 24),
              ],
              const BolumBasligi(baslik: 'SON 7 GÜNLÜK SÜT (KG)'),
              const SizedBox(height: 8),
              _buildSutGrafik(context, data),
              const SizedBox(height: 24),
              if (data.enCokSutVerenCariler.isNotEmpty) ...[
                const BolumBasligi(baslik: 'BU AY EN ÇOK SÜT'),
                const SizedBox(height: 8),
                _buildEnCokSutListesi(context, data),
                const SizedBox(height: 24),
              ],
              if (data.yemDagilimi.isNotEmpty) ...[
                const BolumBasligi(baslik: 'YEM DAĞILIMI (BU AY)'),
                const SizedBox(height: 8),
                _buildYemPie(context, data),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildBanner(String ay, DashboardData data) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ay,
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withOpacity(0.8),
                        fontFamily: 'Poppins')),
                const SizedBox(height: 4),
                const Text('Merhaba 👋',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        fontFamily: 'Poppins')),
                const SizedBox(height: 6),
                Text(
                  'Bugün ${data.bugunGelenSayisi} üretici · ${_kg(data.bugunToplamSut)}\n'
                  'Dün ${_kg(data.dunToplamSut)} · ${data.toplamCari} aktif cari',
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withOpacity(0.85),
                      fontFamily: 'Poppins'),
                ),
              ],
            ),
          ),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
            child: const Icon(Icons.water_drop_rounded,
                color: Colors.white, size: 28),
          ),
        ],
      ),
    );
  }

  /// İkişerli satırlar; kart yüksekliği içerikten gelir (dar ekranda ya da
  /// büyük sistem yazı boyutunda taşmaz — sabit en-boy oranı taşıyordu).
  Widget _buildKpiGrid(DashboardData data) {
    final kartlar = <Widget>[
      KpiKarti(
        baslik: 'Bugün Süt',
        deger: _kg(data.bugunToplamSut),
        altyazi:
            'Sabah ${_kg(data.bugunSabah)} · Akşam ${_kg(data.bugunAksam)}',
        ikon: Icons.water_drop_rounded,
        renk: AppColors.primary,
      ),
      KpiKarti(
        baslik: 'Bugün Yem',
        deger: _kg(data.bugunToplamYem),
        altyazi: 'Tüm çeşitler toplamı',
        ikon: Icons.grass_rounded,
        renk: AppColors.accent,
      ),
      KpiKarti(
        baslik: 'Aylık Süt',
        deger: _kg(data.aylikToplamSut),
        altyazi: 'Bu ay toplam',
        ikon: Icons.calendar_month_rounded,
        renk: AppColors.info,
      ),
      KpiKarti(
        baslik: 'Ödenecek (Alacaklı)',
        deger: _tl(data.odenecekTutar),
        altyazi: data.odenecekTutar > 0 ? 'Carilere ödenecek' : 'Borç yok ✓',
        ikon: Icons.arrow_upward_rounded,
        renk: data.odenecekTutar > 0 ? AppColors.info : AppColors.success,
      ),
      KpiKarti(
        baslik: 'Tahsil Edilecek (Borçlu)',
        deger: _tl(data.tahsilEdilecekTutar),
        altyazi: data.tahsilEdilecekTutar > 0
            ? 'Carilerden tahsil edilecek'
            : 'Alacak yok ✓',
        ikon: Icons.arrow_downward_rounded,
        renk: data.tahsilEdilecekTutar > 0
            ? AppColors.warning
            : AppColors.success,
      ),
    ];
    return Column(children: [
      for (var i = 0; i < kartlar.length; i += 2) ...[
        if (i > 0) const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: kartlar[i]),
            const SizedBox(width: 12),
            Expanded(
                child:
                    i + 1 < kartlar.length ? kartlar[i + 1] : const SizedBox()),
          ]),
        ),
      ],
    ]);
  }

  Widget _buildSutGrafik(BuildContext context, DashboardData data) {
    if (data.haftalikSutGrafik.isEmpty) {
      return const SizedBox(height: 60, child: Center(child: Text('Veri yok')));
    }
    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: SfCartesianChart(
        plotAreaBorderWidth: 0,
        primaryXAxis: const CategoryAxis(
          majorGridLines: MajorGridLines(width: 0),
          axisLine: AxisLine(width: 0),
          labelStyle: TextStyle(
              fontSize: 11,
              fontFamily: 'Poppins',
              color: AppColors.textSecondary),
        ),
        primaryYAxis: const NumericAxis(isVisible: false, minimum: 0),
        series: <CartesianSeries>[
          SplineAreaSeries<GunlukSutVerisi, String>(
            dataSource: data.haftalikSutGrafik,
            xValueMapper: (d, _) => d.gunEtiketi,
            yValueMapper: (d, _) => d.miktar,
            color: AppColors.primary.withOpacity(0.15),
            borderColor: AppColors.primary,
            borderWidth: 2.5,
            splineType: SplineType.natural,
            dataLabelSettings: const DataLabelSettings(
              isVisible: true,
              textStyle: TextStyle(
                  fontSize: 10,
                  fontFamily: 'Poppins',
                  color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnCokSutListesi(BuildContext context, DashboardData data) {
    final liste = data.enCokSutVerenCariler;
    final max = liste.isEmpty ? 1.0 : liste.first.miktar;
    final renkler = [
      AppColors.primary,
      AppColors.primaryLight,
      AppColors.accent,
      AppColors.info,
      AppColors.warning
    ];

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: liste.length,
        separatorBuilder: (_, __) => const Divider(height: 20),
        itemBuilder: (ctx, i) {
          final item = liste[i];
          final oran = item.miktar / max;
          final renk = renkler[i % renkler.length];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                        color: renk.withOpacity(0.15), shape: BoxShape.circle),
                    child: Center(
                      child: Text('${i + 1}',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: renk,
                              fontFamily: 'Poppins')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(item.cariAdi,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              fontFamily: 'Poppins'))),
                  Text(_kg(item.miktar),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: renk,
                          fontFamily: 'Poppins')),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                  value: oran,
                  backgroundColor: AppColors.border,
                  color: renk,
                  borderRadius: BorderRadius.circular(4),
                  minHeight: 6),
            ],
          );
        },
      ),
    );
  }

  Widget _buildYemPie(BuildContext context, DashboardData data) {
    final toplam = data.yemDagilimi.fold(0.0, (s, e) => s + e.miktar);
    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: SfCircularChart(
              series: <CircularSeries>[
                DoughnutSeries<YemTuruVerisi, String>(
                  dataSource: data.yemDagilimi,
                  xValueMapper: (d, _) => d.tur,
                  yValueMapper: (d, _) => d.miktar,
                  pointColorMapper: (d, _) =>
                      _yemRenkleri[d.tur] ?? AppColors.textHint,
                  innerRadius: '55%',
                  dataLabelSettings: const DataLabelSettings(isVisible: false),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: data.yemDagilimi.map((p) {
                final oran = toplam > 0
                    ? (p.miktar / toplam * 100).toStringAsFixed(0)
                    : '0';
                final renk = _yemRenkleri[p.tur] ?? AppColors.textHint;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                              color: renk, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text('${p.tur} $oran%',
                          style: const TextStyle(
                              fontSize: 12,
                              fontFamily: 'Poppins',
                              color: AppColors.textSecondary)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// Kusurat KESİLMEZ: 47,8 + 30,54 = 78,34 kg (eskiden tek haneye
// yuvarlanıp 78,3 görünüyordu; aylık süt "0,08 ton" çıkıyordu).
final _kgFormat = NumberFormat('#,##0.##', 'tr_TR');
String _kg(double v) => '${_kgFormat.format(v)} kg';

final _tlTam = NumberFormat('#,##0', 'tr_TR');
final _tlKurus = NumberFormat('#,##0.00', 'tr_TR');

/// Para: kuruşu varsa gösterilir (₺5.374,40), yoksa tam (₺5.374).
String _tl(double v) {
  final kurus = (v * 100).round();
  return '₺${kurus % 100 == 0 ? _tlTam.format(kurus / 100) : _tlKurus.format(kurus / 100)}';
}

/// Geçen ayın dönemi kapatılmamışsa hatırlatır.
class _DonemHatirlatma extends StatelessWidget {
  final String ay; // yyyy-MM
  const _DonemHatirlatma({required this.ay});

  @override
  Widget build(BuildContext context) {
    final ayAdi = DateFormat('MMMM yyyy', 'tr_TR')
        .format(DateFormat('yyyy-MM').parse(ay));
    return Material(
      color: Colors.orange.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.orange.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const DonemEkrani())),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Icon(Icons.lock_clock_outlined, color: Colors.orange.shade800),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$ayAdi dönemi henüz kapatılmadı. Hakedişleri kontrol edip dönemi kapatın.',
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.orange.shade900,
                    fontFamily: 'Poppins'),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.orange.shade800),
          ]),
        ),
      ),
    );
  }
}

/// Düzenli süt getirip bugün henüz kaydı olmayan üreticiler; dokununca
/// o üreticinin süt girişi açılır.
class _GelmeyenlerListesi extends StatefulWidget {
  final List<Cari> gelmeyenler;
  const _GelmeyenlerListesi({required this.gelmeyenler});

  @override
  State<_GelmeyenlerListesi> createState() => _GelmeyenlerListesiState();
}

class _GelmeyenlerListesiState extends State<_GelmeyenlerListesi> {
  static const _ilkGosterilen = 6;
  bool _hepsi = false;

  @override
  Widget build(BuildContext context) {
    final liste = widget.gelmeyenler;
    final gosterilen = _hepsi ? liste : liste.take(_ilkGosterilen).toList();
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: [
        for (final c in gosterilen)
          ListTile(
            dense: true,
            leading: const CircleAvatar(
              radius: 16,
              backgroundColor: Color(0xFFFFF3E0),
              child: Icon(Icons.schedule_rounded,
                  size: 18, color: AppColors.warning),
            ),
            title: Text(c.tamAd,
                style: const TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w500)),
            subtitle: c.telefon != null && c.telefon!.isNotEmpty
                ? Text(c.telefon!)
                : null,
            trailing: const Icon(Icons.add_circle_outline_rounded,
                color: AppColors.primary),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SutGirisSayfasi(cari: c)),
            ),
          ),
        if (liste.length > _ilkGosterilen)
          TextButton(
            onPressed: () => setState(() => _hepsi = !_hepsi),
            child: Text(
                _hepsi ? 'Daha az göster' : 'Tümünü göster (${liste.length})'),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Text(
            'Son 14 günde süt getirip bugün kaydı olmayan aktif üreticiler.',
            style: TextStyle(
                fontSize: 11, color: Colors.grey[600], fontFamily: 'Poppins'),
          ),
        ),
      ]),
    );
  }
}
