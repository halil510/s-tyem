import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bluetooth/bluetooth_utils.dart';
import '../core/database/app_database.dart';
import '../core/providers/veri_surumu_provider.dart';
import '../data/repositories/veri_yonetimi_repository.dart';
import '../data/yedek/otomatik_yedek.dart';
import '../data/yedek/yedek_servisi.dart';

/// Telefonda otomatik tutulan güvenlik yedekleri: listele, paylaş, geri dön.
class OtomatikYedeklerEkrani extends StatefulWidget {
  const OtomatikYedeklerEkrani({super.key});

  @override
  State<OtomatikYedeklerEkrani> createState() => _OtomatikYedeklerEkraniState();
}

class _OtomatikYedeklerEkraniState extends State<OtomatikYedeklerEkrani> {
  late Future<List<GuvenlikYedegi>> _liste = _yukle();
  bool _calisiyor = false;
  static final _tarih = DateFormat('d MMMM yyyy, HH:mm', 'tr_TR');

  Future<List<GuvenlikYedegi>> _yukle() async => (await OtomatikYedek.uygulama()).listele();

  void _yenile() => setState(() => _liste = _yukle());

  void _mesaj(String m, {bool hata = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(m),
        backgroundColor: hata ? Colors.red[700] : Colors.green[700],
        behavior: SnackBarBehavior.floating,
      ));
  }

  Future<void> _calistir(Future<void> Function() islem) async {
    if (_calisiyor) return;
    setState(() => _calisiyor = true);
    try {
      await islem();
    } catch (e) {
      _mesaj('$e', hata: true);
    } finally {
      if (mounted) setState(() => _calisiyor = false);
      _yenile();
    }
  }

  Future<void> _simdiAl() => _calistir(() async {
        await (await OtomatikYedek.uygulama()).al(YedekSebebi.islemOncesi, aciklama: 'elle');
        _mesaj('Yedek alındı');
      });

  Future<void> _paylas(GuvenlikYedegi y) => _calistir(() async {
        await Share.shareXFiles([XFile(y.dosya.path)],
            subject: 'Süt Yem yedeği', text: 'Süt Yem yedeği — ${_tarih.format(y.tarih)}');
      });

  Future<void> _geriDon(GuvenlikYedegi y) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bu yedeğe dönülsün mü?'),
        content: Text(
          'Telefondaki TÜM kayıtlar ${_tarih.format(y.tarih)} tarihindeki haline döner.\n\n'
          'Bu tarihten SONRA girilen süt, yem ve ödeme kayıtları silinir.\n\n'
          'Şu anki hali önce ayrıca yedeklenir; vazgeçerseniz ona da dönebilirsiniz.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red[700]),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yedeğe Dön'),
          ),
        ],
      ),
    );
    if (onay != true || !mounted) return;
    if (!await _sifreDogru()) return;

    await _calistir(() async {
      // Dosya, yeni güvenlik yedeği eskileri temizlemeden ÖNCE okunur.
      final veri = YedekServisi.coz(await y.dosya.readAsString());
      if (!YedekServisi.tamYedekMi(veri)) throw const YedekHatasi('Bu yedek eksik; geri dönülemez.');
      await OtomatikYedek.islemOncesiAl('guvenlik_yedegi_donusu');
      final repo = VeriYonetimiRepository(await AppDatabase.instance.database);
      final ozet = await repo.yedekYukle(veri, tamamenDegistir: true);
      if (mounted) veriDegistiBildir(context);
      _mesaj('Yedeğe dönüldü: ${ozet.toplam} kayıt');
    });
  }

  Future<bool> _sifreDogru() async {
    final prefs = await SharedPreferences.getInstance();
    final kayitli = prefs.getString('veritabani_sifre') ?? '12345';
    if (!mounted) return false;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Şifre'),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Yedekleme şifresi'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim() == kayitli), child: const Text('Onayla')),
        ],
      ),
    );
    ctrl.dispose();
    if (ok == false) _mesaj('Hatalı şifre', hata: true);
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Otomatik Güvenlik Yedekleri')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _calisiyor ? null : _simdiAl,
        icon: const Icon(Icons.save_alt),
        label: const Text('Şimdi Yedek Al'),
      ),
      body: Column(
        children: [
          if (_calisiyor) const LinearProgressIndicator(),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Uygulama, açılırken ve arka plana geçerken (en çok 4 saatte bir) ve '
              'toplu silme / geri yükleme gibi riskli işlemlerden önce kendiliğinden yedek alır. '
              'Son ${OtomatikYedek.otomatikSakla} otomatik ve ${OtomatikYedek.islemOncesiSakla} işlem öncesi yedek saklanır.\n\n'
              '⚠️ Bu yedekler telefonun içindedir. Telefon kaybolur ya da uygulama silinirse onlar da gider: '
              'ara sıra "Paylaş" ile Drive / WhatsApp / bilgisayara gönderin.',
              style: TextStyle(fontSize: 13),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<GuvenlikYedegi>>(
              future: _liste,
              builder: (context, s) {
                if (s.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (s.hasError) return Center(child: Text('Yedekler okunamadı: ${s.error}'));
                final liste = s.data!;
                if (liste.isEmpty) return const Center(child: Text('Henüz otomatik yedek yok'));
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                  itemCount: liste.length,
                  itemBuilder: (context, i) {
                    final y = liste[i];
                    final otomatik = y.sebep == YedekSebebi.otomatik;
                    return Card(
                      child: ListTile(
                        leading: Icon(otomatik ? Icons.schedule : Icons.shield_outlined,
                            color: otomatik ? Colors.blue[700] : Colors.orange[800]),
                        title: Text(_tarih.format(y.tarih), style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '${otomatik ? 'Otomatik' : OtomatikYedek.islemEtiketi(y.aciklama)} · '
                          '${BluetoothUtils.formatBytes(y.boyut)}',
                        ),
                        trailing: PopupMenuButton<String>(
                          enabled: !_calisiyor,
                          onSelected: (v) => v == 'paylas' ? _paylas(y) : _geriDon(y),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'paylas', child: Text('Paylaş (telefon dışına kaydet)')),
                            PopupMenuItem(value: 'don', child: Text('Bu yedeğe geri dön')),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
