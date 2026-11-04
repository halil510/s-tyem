import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../theme/app_theme.dart';
import '../widgetlar/ortak_widgetlar.dart';
import '../features/dashboard/providers/dashboard_providers.dart';

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
              const SizedBox(height: 20),
              _buildKpiGrid(data),
              const SizedBox(height: 24),
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
                Text(ay, style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.8), fontFamily: 'Poppins')),
                const SizedBox(height: 4),
                const Text('Merhaba 👋', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white, fontFamily: 'Poppins')),
                const SizedBox(height: 6),
                Text(
                  '${data.toplamCari} aktif cari · Bugün ${data.bugunToplamSut.toStringAsFixed(1)} kg süt',
                  style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.85), fontFamily: 'Poppins'),
                ),
              ],
            ),
          ),
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
            child: const Icon(Icons.water_drop_rounded, color: Colors.white, size: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiGrid(DashboardData data) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: [
        KpiKarti(
          baslik: 'Bugün Süt',
          deger: '${data.bugunToplamSut.toStringAsFixed(1)} kg',
          altyazi: 'Tüm cariler toplamı',
          ikon: Icons.water_drop_rounded,
          renk: AppColors.primary,
        ),
        KpiKarti(
          baslik: 'Bugün Yem',
          deger: '${data.bugunToplamYem.toStringAsFixed(1)} kg',
          altyazi: 'Tüm çeşitler toplamı',
          ikon: Icons.grass_rounded,
          renk: AppColors.accent,
        ),
        KpiKarti(
          baslik: 'Aylık Süt',
          deger: '${(data.aylikToplamSut / 1000).toStringAsFixed(2)} ton',
          altyazi: 'Bu ay toplam',
          ikon: Icons.calendar_month_rounded,
          renk: AppColors.info,
        ),
        KpiKarti(
          baslik: 'Ödenecek (Alacaklı)',
          deger: '₺${data.odenecekTutar.toStringAsFixed(0)}',
          altyazi: data.odenecekTutar > 0 ? 'Carilere ödenecek' : 'Borç yok ✓',
          ikon: Icons.arrow_upward_rounded,
          renk: data.odenecekTutar > 0 ? AppColors.info : AppColors.success,
        ),
        KpiKarti(
          baslik: 'Tahsil Edilecek (Borçlu)',
          deger: '₺${data.tahsilEdilecekTutar.toStringAsFixed(0)}',
          altyazi: data.tahsilEdilecekTutar > 0 ? 'Carilerden tahsil edilecek' : 'Alacak yok ✓',
          ikon: Icons.arrow_downward_rounded,
          renk: data.tahsilEdilecekTutar > 0 ? AppColors.warning : AppColors.success,
        ),
      ],
    );
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
          labelStyle: TextStyle(fontSize: 11, fontFamily: 'Poppins', color: AppColors.textSecondary),
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
              textStyle: TextStyle(fontSize: 10, fontFamily: 'Poppins', color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnCokSutListesi(BuildContext context, DashboardData data) {
    final liste = data.enCokSutVerenCariler;
    final max = liste.isEmpty ? 1.0 : liste.first.miktar;
    final renkler = [AppColors.primary, AppColors.primaryLight, AppColors.accent, AppColors.info, AppColors.warning];

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
                    width: 24, height: 24,
                    decoration: BoxDecoration(color: renk.withOpacity(0.15), shape: BoxShape.circle),
                    child: Center(
                      child: Text('${i + 1}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: renk, fontFamily: 'Poppins')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(item.cariAdi, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, fontFamily: 'Poppins'))),
                  Text('${item.miktar.toStringAsFixed(1)} kg', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: renk, fontFamily: 'Poppins')),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: oran, backgroundColor: AppColors.border, color: renk, borderRadius: BorderRadius.circular(4), minHeight: 6),
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
                  pointColorMapper: (d, _) => _yemRenkleri[d.tur] ?? AppColors.textHint,
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
                final oran = toplam > 0 ? (p.miktar / toplam * 100).toStringAsFixed(0) : '0';
                final renk = _yemRenkleri[p.tur] ?? AppColors.textHint;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: renk, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text('${p.tur} $oran%', style: const TextStyle(fontSize: 12, fontFamily: 'Poppins', color: AppColors.textSecondary)),
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
