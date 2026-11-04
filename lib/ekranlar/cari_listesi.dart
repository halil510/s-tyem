import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/cari_model.dart';
import 'cari_ekle.dart';
import 'detay_ekrani.dart';
import '../core/router/app_router.dart';
import '../utils/excel_export.dart';
import '../services/whatsapp_service.dart';
import '../data/repositories/cari_repository.dart';
import '../data/repositories/sut_repository.dart';
import '../data/repositories/yem_repository.dart';
import '../core/providers/repository_providers.dart';
import '../core/providers/veri_surumu_provider.dart';
import 'package:intl/intl.dart';

class CariListesi extends ConsumerStatefulWidget {
  const CariListesi({super.key});

  @override
  ConsumerState<CariListesi> createState() => _CariListesiState();
}

class _CariListesiState extends ConsumerState<CariListesi> {
  late CariRepository _cariRepo;
  late SutRepository _sutRepo;
  late YemRepository _yemRepo;
  List<Cari> _cariler = [];
  List<Cari> _filtrelenen = [];
  final TextEditingController _aramaController = TextEditingController();
  bool _yukleniyor = true;
  List<int> _seciliCariler = [];
  
  // Ayın başı ve sonu
  DateTime get _ayBaslangic => DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime get _ayBitis => DateTime(DateTime.now().year, DateTime.now().month + 1, 0);
  
  // Her cari için bu ayki süt toplamlarını saklayan map
  Map<int, double> _aylikSutToplamlari = {};
  
  // Hayvan türlerine göre toplam süt miktarları
  Map<String, double> _hayvanTuruneGoreToplamSut = {
    'İnek': 0.0,
    'Koyun': 0.0,
    'Tavuk': 0.0,
  };

  @override
  void initState() {
    super.initState();
    _verileriYukle();
  }

  @override
  void dispose() {
    _aramaController.dispose();
    super.dispose();
  }

  Future<void> _verileriYukle() async {
    setState(() => _yukleniyor = true);
    
    try {
      // Repository'leri veritabanı hazır olduğunda al
      _cariRepo = await ref.read(cariRepositoryProvider.future);
      _sutRepo = await ref.read(sutRepositoryProvider.future);
      _yemRepo = await ref.read(yemRepositoryProvider.future);

      // Carileri getir
      final liste = await _cariRepo.getAll(sadeceAktif: true);
      
      // Her cari için bu ayki süt toplamını hesapla
      _aylikSutToplamlari = {};
      _hayvanTuruneGoreToplamSut = {
        'İnek': 0.0,
        'Koyun': 0.0,
        'Tavuk': 0.0,
      };
      
      for (var cari in liste) {
        double toplamSut = 0.0;
        
        if (cari.id != null) {
          // Bu ayki süt kayıtlarını getir
          final sutler = await _sutRepo.getByCari(
            cari.id!,
            DateFormat('yyyy-MM-dd').format(_ayBaslangic),
            DateFormat('yyyy-MM-dd').format(_ayBitis)
          );
          
          // Toplamı hesapla
          toplamSut = sutler.fold(0.0, (sum, sut) => sum + sut.toplam);
          
          // Hayvan türüne göre toplamı güncelle
          final hayvanTuru = cari.hayvanTuru ?? '';
          if (_hayvanTuruneGoreToplamSut.containsKey(hayvanTuru)) {
            _hayvanTuruneGoreToplamSut[hayvanTuru] = 
                (_hayvanTuruneGoreToplamSut[hayvanTuru] ?? 0.0) + toplamSut;
          }
        }
        
        _aylikSutToplamlari[cari.id!] = toplamSut;
      }
      
      setState(() {
        _cariler = liste;
        _filtrelenen = liste;
        _yukleniyor = false;
      });
      
    } catch (e) {
      print('Veri yükleme hatası: $e');
      setState(() => _yukleniyor = false);
    }
  }

  void _aramaYap(String sorgu) {
    final kucukSorgu = sorgu.toLowerCase();
    setState(() {
      _filtrelenen = _cariler.where((cari) {
        final tamAd = '${cari.ad} ${cari.soyad}'.toLowerCase();
        final hayvanTuru = cari.hayvanTuru?.toLowerCase() ?? '';
        return tamAd.contains(kucukSorgu) || hayvanTuru.contains(kucukSorgu);
      }).toList();
    });
  }

  void _cariSec(int cariId, bool secili) {
    setState(() {
      if (secili) {
        _seciliCariler.add(cariId);
      } else {
        _seciliCariler.remove(cariId);
      }
    });
  }

  void _tumunuSec(bool secili) {
    setState(() {
      if (secili) {
        _seciliCariler = _filtrelenen.map((c) => c.id!).toList();
      } else {
        _seciliCariler.clear();
      }
    });
  }

  Future<void> _cariSil(int cariId) async {
    // Kalıcı silme, carinin TÜM süt/yem/ödeme kayıtlarını da siler
    // (ON DELETE CASCADE). Hareketi olan cari için önce pasife almayı öner.
    final sayilar = await _cariRepo.hareketSayilari(cariId);
    final hareketVar = sayilar.sut + sayilar.yem + sayilar.odeme > 0;
    if (!mounted) return;

    final secim = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cari Sil'),
        content: Text(hareketVar
            ? 'Bu carinin ${sayilar.sut} süt, ${sayilar.yem} yem ve ${sayilar.odeme} ödeme/tahsilat kaydı var.\n\n'
                'Kalıcı silerseniz BU KAYITLARIN HEPSİ geri dönülmez şekilde silinir ve hesap geçmişi kaybolur.\n\n'
                'Önerilen: cariyi PASİFE ALIN — listelerden kalkar, kayıtları korunur, istediğiniz zaman geri açabilirsiniz.'
            : 'Bu carinin hiç kaydı yok. Silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'iptal'),
            child: const Text('İptal'),
          ),
          if (hareketVar)
            TextButton(
              onPressed: () => Navigator.pop(context, 'sil'),
              child: const Text('Kalıcı Sil', style: TextStyle(color: Colors.red)),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, hareketVar ? 'pasif' : 'sil'),
            child: Text(hareketVar ? 'Pasife Al' : 'Sil'),
          ),
        ],
      ),
    );

    if (secim == 'sil' && hareketVar && await _kaliciSilmeIkinciOnay() != true) return;

    if (secim == 'pasif') {
      await _cariRepo.pasifeAl(cariId);
    } else if (secim == 'sil') {
      await _cariRepo.delete(cariId);
    } else {
      return;
    }
    ref.veriDegisti();
    await _verileriYukle();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(secim == 'pasif' ? 'Cari pasife alındı, kayıtları korundu' : 'Cari silindi')),
    );
  }

  Future<bool?> _kaliciSilmeIkinciOnay() => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Son onay'),
          content: const Text('Carinin tüm hesap geçmişi kalıcı olarak silinecek. Bu işlem GERİ ALINAMAZ.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Evet, kalıcı sil', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

  /// Pasife alınmış carileri listeler ve yeniden aktif yapmayı sağlar.
  Future<void> _pasifCarileriGoster() async {
    final pasifler = (await _cariRepo.getAll()).where((c) => !c.aktif).toList();
    if (!mounted) return;
    final aktifEdilecek = await showModalBottomSheet<Cari>(
      context: context,
      builder: (ctx) => SafeArea(
        child: pasifler.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Text('Pasif cari yok', textAlign: TextAlign.center),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  const ListTile(title: Text('Pasif Cariler', style: TextStyle(fontWeight: FontWeight.bold))),
                  for (final c in pasifler)
                    ListTile(
                      leading: const Icon(Icons.person_off_outlined),
                      title: Text(c.tamAd),
                      trailing: TextButton(
                        onPressed: () => Navigator.pop(ctx, c),
                        child: const Text('Aktif Yap'),
                      ),
                    ),
                ],
              ),
      ),
    );
    if (aktifEdilecek == null) return;
    await _cariRepo.aktifYap(aktifEdilecek.id!);
    ref.veriDegisti();
    await _verileriYukle();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${aktifEdilecek.tamAd} yeniden aktif')),
    );
  }

  void _excelExportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excel\'e Aktar'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Süt Raporu'),
              onTap: () => _sutRaporuDialog(),
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Yem Raporu'),
              onTap: () => _yemRaporuDialog(),
            ),
          ],
        ),
      ),
    );
  }

  void _sutRaporuDialog() {
    Navigator.pop(context);
    showDialog(
      context: context,
      builder: (context) => _SutRaporDialog(onOlustur: _sutRaporuOlustur),
    );
  }

  void _yemRaporuDialog() {
    Navigator.pop(context);
    showDialog(
      context: context,
      builder: (context) => _YemRaporDialog(onOlustur: _yemRaporuOlustur),
    );
  }

  Future<void> _sutRaporuOlustur(DateTimeRange tarihAraligi) async {
    Navigator.pop(context);
    try {
      final sutler = await _sutRepo.getAllInRange(
        DateFormat('yyyy-MM-dd').format(tarihAraligi.start),
        DateFormat('yyyy-MM-dd').format(tarihAraligi.end),
      );

      final file = await ExcelExport.exportSutRaporu(
        cariler: _cariler,
        sutler: sutler,
        startDate: tarihAraligi.start,
        endDate: tarihAraligi.end,
        raporAdi: 'Sut_Raporu_${DateFormat('yyyy_MM_dd').format(DateTime.now())}',
      );

      await ExcelExport.shareFile(file);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Süt raporu başarıyla oluşturuldu')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
    }
  }

  Future<void> _yemRaporuOlustur(DateTimeRange tarihAraligi) async {
    Navigator.pop(context);
    try {
      final yemler = await _yemRepo.getAllInRange(
        DateFormat('yyyy-MM-dd').format(tarihAraligi.start),
        DateFormat('yyyy-MM-dd').format(tarihAraligi.end),
      );

      final file = await ExcelExport.exportYemRaporu(
        cariler: _cariler,
        yemler: yemler,
        startDate: tarihAraligi.start,
        endDate: tarihAraligi.end,
        raporAdi: 'Yem_Raporu_${DateFormat('yyyy_MM_dd').format(DateTime.now())}',
      );

      await ExcelExport.shareFile(file);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yem raporu başarıyla oluşturuldu')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
    }
  }

  Future<void> _whatsappGonder() async {
    if (_seciliCariler.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen en az bir cari seçin')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('WhatsApp Gönder'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.local_drink, color: Colors.blue),
              title: const Text('Süt Raporu Gönder'),
              onTap: () {
                Navigator.pop(context);
                _sutRaporuWhatsappGonder();
              },
            ),
            ListTile(
              leading: const Icon(Icons.agriculture, color: Colors.green),
              title: const Text('Yem Raporu Gönder'),
              onTap: () {
                Navigator.pop(context);
                _yemRaporuWhatsappGonder();
              },
            ),
            ListTile(
              leading: const Icon(Icons.message, color: Colors.green),
              title: const Text('Özel Mesaj Gönder'),
              onTap: () {
                Navigator.pop(context);
                _ozelMesajGonder();
              },
            ),
            ListTile(
              leading: const Icon(Icons.payment, color: Colors.orange),
              title: const Text('Ödeme Bildirimi Gönder'),
              onTap: () {
                Navigator.pop(context);
                _odemeBildirimiGonder();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sutRaporuWhatsappGonder() async {
    try {
      final now = DateTime.now();
      final bugun = DateFormat('dd MMMM yyyy', 'tr_TR').format(now);
      final haftaBaslangic = now.subtract(const Duration(days: 6));
      final ayBaslangic = DateTime(now.year, now.month, 1);

      int gonderilenSayisi = 0;
      int hataSayisi = 0;
      int telefonuOlmayanSayisi = 0;
      List<String> basarisizCariler = [];

      for (int cariId in _seciliCariler) {
        try {
          var cari = _cariler.firstWhere((c) => c.id == cariId);
          
          // Telefon numarası kontrolü
          if (cari.telefon == null || cari.telefon!.trim().isEmpty) {
            telefonuOlmayanSayisi++;
            basarisizCariler.add('${cari.ad} ${cari.soyad} (telefon yok)');
            continue;
          }

          // Telefon numarasını temizle
          String cleanPhone = _cleanPhoneNumber(cari.telefon!);
          if (cleanPhone.isEmpty) {
            telefonuOlmayanSayisi++;
            basarisizCariler.add('${cari.ad} ${cari.soyad} (geçersiz telefon)');
            continue;
          }

          // Süt verilerini getir
          final sutler = await _sutRepo.getByCari(
            cariId, 
            DateFormat('yyyy-MM-dd').format(ayBaslangic),
            DateFormat('yyyy-MM-dd').format(now)
          );

          // Toplamları hesapla
          double gunlukToplam = 0;
          double haftalikToplam = 0;
          double aylikToplam = 0;

          for (var sut in sutler) {
            final sutTarih = DateTime.parse(sut.tarih);
            aylikToplam += sut.toplam;
            
            if (sutTarih.isAfter(haftaBaslangic)) {
              haftalikToplam += sut.toplam;
            }
            
            if (sutTarih.day == now.day && sutTarih.month == now.month && sutTarih.year == now.year) {
              gunlukToplam += sut.toplam;
            }
          }

          // Mesaj oluştur
          final mesaj = WhatsAppService.createSutRaporuMessage(
            cariAd: '${cari.ad} ${cari.soyad}',
            gunlukToplam: gunlukToplam,
            haftalikToplam: haftalikToplam,
            aylikToplam: aylikToplam,
            tarih: bugun,
          );

          // WhatsApp'a gönder
          print('${cari.ad} ${cari.soyad} için WhatsApp gönderiliyor...');
          final success = await WhatsAppService.sendToWhatsApp(cleanPhone, mesaj);
          
          // Her gönderim arasında 3 saniye bekle
          await Future.delayed(const Duration(seconds: 3));
          
          if (success) {
            gonderilenSayisi++;
            print('✅ ${cari.ad} ${cari.soyad} - Başarılı');
          } else {
            hataSayisi++;
            basarisizCariler.add('${cari.ad} ${cari.soyad} (gönderim hatası)');
            print('❌ ${cari.ad} ${cari.soyad} - Başarısız');
          }
          
        } catch (e) {
          hataSayisi++;
          basarisizCariler.add('${_cariler.firstWhere((c) => c.id == cariId).ad} (hata: ${e.toString().substring(0, 50)})');
          print('${_cariler.firstWhere((c) => c.id == cariId).ad} için WhatsApp gönderim hatası: $e');
        }
      }

      // Sonuçları göster
      String sonucMesaji = '✅ $gonderilenSayisi cariye süt raporu gönderildi';
      if (hataSayisi > 0) sonucMesaji += '\n❌ $hataSayisi cariye gönderilemedi';
      if (telefonuOlmayanSayisi > 0) sonucMesaji += '\n📞 $telefonuOlmayanSayisi caride telefon numarası yok';
      
      if (basarisizCariler.isNotEmpty) {
        sonucMesaji += '\n\nBaşarısız Cariler:\n${basarisizCariler.join('\n')}';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: SingleChildScrollView(
            child: Text(sonucMesaji),
          ),
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: 'Tamam',
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            },
          ),
        ),
      );
      
    } catch (e) {
      print('Genel hata: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Genel hata: $e'),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _yemRaporuWhatsappGonder() async {
    try {
      final now = DateTime.now();
      final bugun = DateFormat('dd MMMM yyyy', 'tr_TR').format(now);
      final ayBaslangic = DateTime(now.year, now.month, 1);

      int gonderilenSayisi = 0;
      int hataSayisi = 0;
      int telefonuOlmayanSayisi = 0;

      for (int cariId in _seciliCariler) {
        try {
          var cari = _cariler.firstWhere((c) => c.id == cariId);

          if (cari.telefon == null || cari.telefon!.trim().isEmpty) {
            telefonuOlmayanSayisi++;
            continue;
          }

          String cleanPhone = _cleanPhoneNumber(cari.telefon!);
          if (cleanPhone.isEmpty) {
            telefonuOlmayanSayisi++;
            continue;
          }

          final yemler = await _yemRepo.getByCari(
            cariId,
            DateFormat('yyyy-MM-dd').format(ayBaslangic),
            DateFormat('yyyy-MM-dd').format(now)
          );

          double toplamYem = 0;
          String yemDetay = '';

          for (var yem in yemler) {
            toplamYem += yem.toplam;

            List<String> detaylar = [];
            if (yem.sutYemi > 0) detaylar.add('Süt Yemi: ${yem.sutYemi}kg');
            if (yem.besiYemi > 0) detaylar.add('Besi Yemi: ${yem.besiYemi}kg');
            if (yem.kuzuYemi > 0) detaylar.add('Kuzu Yemi: ${yem.kuzuYemi}kg');
            if (yem.tavukYemi > 0) detaylar.add('Tavuk Yemi: ${yem.tavukYemi}kg');

            if (detaylar.isNotEmpty) {
              yemDetay += '${DateFormat('dd.MM.yyyy').format(DateTime.parse(yem.tarih))}: ${detaylar.join(', ')}\n';
            }
          }

          final mesaj = WhatsAppService.createYemRaporuMessage(
            cariAd: '${cari.ad} ${cari.soyad}',
            toplamYem: toplamYem,
            yemDetay: yemDetay,
            tarih: bugun,
          );

          await WhatsAppService.sendToWhatsApp(cari.telefon!, mesaj);
          await Future.delayed(const Duration(seconds: 3));
          gonderilenSayisi++;
        } catch (e) {
          hataSayisi++;
          print('${_cariler.firstWhere((c) => c.id == cariId).ad} için WhatsApp gönderim hatası: $e');
        }
      }

      String sonucMesaji = '$gonderilenSayisi cariye yem raporu gönderildi';
      if (hataSayisi > 0) sonucMesaji += ', $hataSayisi cariye gönderilemedi';
      if (telefonuOlmayanSayisi > 0) sonucMesaji += ', $telefonuOlmayanSayisi caride telefon numarası yok';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sonucMesaji)),
      );
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Genel hata: $e')),
      );
    }
  }

  Future<void> _ozelMesajGonder() async {
    final messageController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Özel Mesaj Gönder'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: messageController,
              decoration: const InputDecoration(
                labelText: 'Mesajınız',
                border: OutlineInputBorder(),
                hintText: 'Mesajınızı buraya yazın...',
              ),
              maxLines: 5,
            ),
            const SizedBox(height: 10),
            Text(
              'Mesaj ${_seciliCariler.length} cariye gönderilecek',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () async {
              if (messageController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Lütfen mesaj giriniz')),
                );
                return;
              }
              Navigator.pop(context);
              await _ozelMesajlariGonder(messageController.text);
            },
            child: const Text('Gönder'),
          ),
        ],
      ),
    );
  }

  Future<void> _odemeBildirimiGonder() async {
    final tutarController = TextEditingController();
    final donemController = TextEditingController(
      text: DateFormat('MMMM yyyy', 'tr_TR').format(DateTime.now()),
    );
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ödeme Bildirimi Gönder'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: tutarController,
              decoration: const InputDecoration(
                labelText: 'Tutar (₺)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: donemController,
              decoration: const InputDecoration(
                labelText: 'Dönem',
                border: OutlineInputBorder(),
                hintText: 'Örn: Mayıs 2024',
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${_seciliCariler.length} cariye gönderilecek',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () async {
              if (tutarController.text.trim().isEmpty || donemController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Lütfen tüm alanları doldurun')),
                );
                return;
              }
              
              final tutar = double.tryParse(tutarController.text);
              if (tutar == null || tutar <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Lütfen geçerli bir tutar girin')),
                );
                return;
              }
              
              Navigator.pop(context);
              await _odemeBildirimleriniGonder(tutar, donemController.text);
            },
            child: const Text('Gönder'),
          ),
        ],
      ),
    );
  }

  Future<void> _ozelMesajlariGonder(String mesaj) async {
    try {
      int gonderilenSayisi = 0;
      int hataSayisi = 0;
      int telefonuOlmayanSayisi = 0;

      for (int cariId in _seciliCariler) {
        try {
          var cari = _cariler.firstWhere((c) => c.id == cariId);
          
          if (cari.telefon == null || cari.telefon!.isEmpty) {
            telefonuOlmayanSayisi++;
            continue;
          }

          String cleanPhone = _cleanPhoneNumber(cari.telefon!);
          if (cleanPhone.isEmpty) {
            telefonuOlmayanSayisi++;
            continue;
          }

          await WhatsAppService.sendToWhatsApp(cleanPhone, mesaj);
          await Future.delayed(const Duration(seconds: 3));
          gonderilenSayisi++;
        } catch (e) {
          hataSayisi++;
          print('${_cariler.firstWhere((c) => c.id == cariId).ad} için WhatsApp gönderim hatası: $e');
        }
      }

      String sonucMesaji = '$gonderilenSayisi cariye mesaj gönderildi';
      if (hataSayisi > 0) sonucMesaji += ', $hataSayisi cariye gönderilemedi';
      if (telefonuOlmayanSayisi > 0) sonucMesaji += ', $telefonuOlmayanSayisi caride telefon numarası yok';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sonucMesaji)),
      );
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
    }
  }

  Future<void> _odemeBildirimleriniGonder(double tutar, String donem) async {
    try {
      int gonderilenSayisi = 0;
      int hataSayisi = 0;
      int telefonuOlmayanSayisi = 0;

      for (int cariId in _seciliCariler) {
        try {
          var cari = _cariler.firstWhere((c) => c.id == cariId);
          
          if (cari.telefon == null || cari.telefon!.isEmpty) {
            telefonuOlmayanSayisi++;
            continue;
          }

          String cleanPhone = _cleanPhoneNumber(cari.telefon!);
          if (cleanPhone.isEmpty) {
            telefonuOlmayanSayisi++;
            continue;
          }

          final mesaj = WhatsAppService.createOdemeBildirimiMessage(
            cariAd: '${cari.ad} ${cari.soyad}',
            tutar: tutar,
            donem: donem,
          );

          await WhatsAppService.sendToWhatsApp(cleanPhone, mesaj);
          await Future.delayed(const Duration(seconds: 3));
          gonderilenSayisi++;
        } catch (e) {
          hataSayisi++;
          print('${_cariler.firstWhere((c) => c.id == cariId).ad} için WhatsApp gönderim hatası: $e');
        }
      }

      String sonucMesaji = '$gonderilenSayisi cariye ödeme bildirimi gönderildi';
      if (hataSayisi > 0) sonucMesaji += ', $hataSayisi cariye gönderilemedi';
      if (telefonuOlmayanSayisi > 0) sonucMesaji += ', $telefonuOlmayanSayisi caride telefon numarası yok';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sonucMesaji)),
      );
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
    }
  }

  String _cleanPhoneNumber(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.startsWith('0')) {
      cleaned = '90' + cleaned.substring(1);
    } else if (cleaned.length == 10) {
      cleaned = '90' + cleaned;
    } else if (cleaned.startsWith('90') && cleaned.length == 12) {
      // zaten doğru
    } else if (cleaned.length > 12) {
      cleaned = cleaned.substring(cleaned.length - 12);
    }
    return cleaned;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          _buildAramaCubugu(),
          if (_seciliCariler.isNotEmpty) _buildSecimAppBar(),
          _buildIstatistikKartlari(),
          _buildCariListesi(),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_seciliCariler.isNotEmpty)
            FloatingActionButton(
              onPressed: _whatsappGonder,
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              child: const Icon(Icons.message),
            ),
          const SizedBox(height: 16),
          FloatingActionButton(
            onPressed: () async {
              final sonuc = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CariEkle()),
              );
              if (sonuc == true) _verileriYukle();
            },
            backgroundColor: Colors.blue[700],
            foregroundColor: Colors.white,
            child: const Icon(Icons.person_add_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildAramaCubugu() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: TextField(
                controller: _aramaController,
                decoration: const InputDecoration(
                  hintText: 'Cari ara...',
                  border: InputBorder.none,
                  prefixIcon: Icon(Icons.search, color: Colors.grey),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16),
                ),
                onChanged: _aramaYap,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _pasifCarileriGoster,
            tooltip: 'Pasif Cariler',
            icon: const Icon(Icons.person_off_outlined, color: Colors.grey),
          ),
          const SizedBox(width: 4),
          Container(
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              onPressed: _excelExportDialog,
              icon: Image.asset(
                'assets/images/excel.png',
                width: 26,
                height: 26,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecimAppBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.blue[50],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${_seciliCariler.length} cari seçildi',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.select_all),
                tooltip: 'Tümünü Seç',
                onPressed: () => _tumunuSec(true),
              ),
              IconButton(
                icon: const Icon(Icons.deselect),
                tooltip: 'Seçimi Temizle',
                onPressed: () => _tumunuSec(false),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIstatistikKartlari() {
    final inekSayisi = _cariler.where((c) => c.hayvanTuru == 'İnek').length;
    final koyunSayisi = _cariler.where((c) => c.hayvanTuru == 'Koyun').length;
    final tavukSayisi = _cariler.where((c) => c.hayvanTuru == 'Tavuk').length;

    // Toplam süt miktarını hesapla
    final toplamSutMiktari = _hayvanTuruneGoreToplamSut.values.fold(
      0.0, 
      (sum, value) => sum + (value ?? 0.0)
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _istatistikKarti('Toplam', _cariler.length, Icons.people, Colors.blue, null),
          _istatistikKarti('İnek', inekSayisi, Icons.agriculture, Colors.green, _hayvanTuruneGoreToplamSut['İnek']),
          _istatistikKarti('Koyun', koyunSayisi, Icons.pets, Colors.orange, _hayvanTuruneGoreToplamSut['Koyun']),
          _istatistikKarti('Tavuk', tavukSayisi, Icons.egg, Colors.purple, _hayvanTuruneGoreToplamSut['Tavuk']),
          _istatistikKarti('Süt Toplam', null, Icons.local_drink, Colors.blue, toplamSutMiktari),
        ],
      ),
    );
  }

  Widget _istatistikKarti(String baslik, int? sayi, IconData ikon, Color renk, double? sutToplam) {
    return Container(
      width: 120,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: renk.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(ikon, color: renk, size: 20),
          ),
          const SizedBox(height: 12),
          
          // Sayı ve süt toplamını birlikte göster
          if (sayi != null)
            Text(
              sayi.toString(),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: renk,
              ),
            ),
          
          if (sutToplam != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (sayi != null) const SizedBox(height: 4),
                Text(
                  '${sutToplam.toStringAsFixed(1)} kg',
                  style: TextStyle(
                    fontSize: sayi != null ? 14 : 20,
                    color: sayi != null ? renk.withOpacity(0.8) : renk,
                    fontWeight: sayi != null ? FontWeight.w500 : FontWeight.bold,
                  ),
                ),
              ],
            ),
          
          const SizedBox(height: 4),
          Text(
            baslik,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCariListesi() {
    if (_yukleniyor) {
      return const Expanded(
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_filtrelenen.isEmpty) {
      return Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _aramaController.text.isEmpty ? 'Henüz cari kaydı yok' : 'Sonuç bulunamadı',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            if (_aramaController.text.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final sonuc = await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CariEkle()),
                    );
                    if (sonuc == true) _verileriYukle();
                  },
                  icon: const Icon(Icons.person_add),
                  label: const Text('İlk Cariyi Ekle'),
                ),
              ),
          ],
        ),
      );
    }

    return Expanded(
      child: RefreshIndicator(
        onRefresh: _verileriYukle,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          itemCount: _filtrelenen.length,
          itemBuilder: (context, index) {
            final cari = _filtrelenen[index];
            return _cariKarti(cari);
          },
        ),
      ),
    );
  }

  Widget _cariKarti(Cari cari) {
    final secili = _seciliCariler.contains(cari.id);
    final buAykiSutToplam = cari.id != null ? _aylikSutToplamlari[cari.id!] ?? 0.0 : 0.0;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_seciliCariler.isNotEmpty)
              Checkbox(
                value: secili,
                onChanged: (value) => _cariSec(cari.id!, value!),
              ),
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: _hayvanRengi(cari.hayvanTuru).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _hayvanIkonu(cari.hayvanTuru),
                color: _hayvanRengi(cari.hayvanTuru),
                size: 24,
              ),
            ),
          ],
        ),
        title: Text(
          '${cari.ad} ${cari.soyad}',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              cari.hayvanTuru ?? 'Belirtilmemiş',
              style: TextStyle(
                color: _hayvanRengi(cari.hayvanTuru),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                // Bu ayki süt toplamını göster
                if (buAykiSutToplam > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.local_drink, size: 12, color: Colors.blue),
                        const SizedBox(width: 4),
                        Text(
                          '${buAykiSutToplam.toStringAsFixed(1)} kg',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.blue,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (cari.telefon != null && cari.telefon!.isNotEmpty)
              Text(
                cari.telefon!,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'detay', child: Text('Detay')),
            const PopupMenuItem(value: 'ekstre', child: Text('Hesap Ekstresi')),
            const PopupMenuItem(value: 'duzenle', child: Text('Düzenle')),
            const PopupMenuItem(value: 'sil', child: Text('Sil')),
          ],
          onSelected: (value) {
            if (value == 'detay') {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => DetayEkrani(cari: cari)),
              );
            } else if (value == 'ekstre') {
              context.push(AppRoutes.cariHesap, extra: cari);
            } else if (value == 'duzenle') {
              _cariDuzenle(cari);
            } else if (value == 'sil') {
              _cariSil(cari.id!);
            }
          },
        ),
        onTap: () {
          if (_seciliCariler.isNotEmpty) {
            _cariSec(cari.id!, !secili);
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => DetayEkrani(cari: cari)),
            );
          }
        },
        onLongPress: () => _cariSec(cari.id!, !secili),
      ),
    );
  }

  Future<void> _cariDuzenle(Cari cari) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CariDuzenle(cari: cari)),
    );
    if (result == true) _verileriYukle();
  }

  IconData _hayvanIkonu(String? tur) {
    switch (tur) {
      case 'İnek': return Icons.agriculture;
      case 'Koyun': return Icons.pets;
      case 'Tavuk': return Icons.egg;
      default: return Icons.pets;
    }
  }

  Color _hayvanRengi(String? tur) {
    switch (tur) {
      case 'İnek': return Colors.blue;
      case 'Koyun': return Colors.green;
      case 'Tavuk': return Colors.orange;
      default: return Colors.grey;
    }
  }
}

// Dialog Widget'ları
class _SutRaporDialog extends StatefulWidget {
  final Function(DateTimeRange) onOlustur;
  const _SutRaporDialog({required this.onOlustur});

  @override
  State<_SutRaporDialog> createState() => _SutRaporDialogState();
}

class _SutRaporDialogState extends State<_SutRaporDialog> {
  DateTimeRange? _tarihAraligi;
  String _seciliPeriyot = 'bugun';

  @override
  void initState() {
    super.initState();
    _periyotSec('bugun');
  }

  void _periyotSec(String periyot) {
    setState(() {
      _seciliPeriyot = periyot;
      final now = DateTime.now();
      switch (periyot) {
        case 'bugun':
          _tarihAraligi = DateTimeRange(start: now, end: now);
          break;
        case 'haftalik':
          _tarihAraligi = DateTimeRange(
            start: now.subtract(const Duration(days: 6)),
            end: now
          );
          break;
        case 'aylik':
          _tarihAraligi = DateTimeRange(
            start: DateTime(now.year, now.month, 1),
            end: DateTime(now.year, now.month + 1, 0)
          );
          break;
        case 'ozel':
          if (_tarihAraligi == null) {
            _tarihAraligi = DateTimeRange(
              start: now.subtract(const Duration(days: 30)),
              end: now
            );
          }
          break;
      }
    });
  }

  Future<void> _tarihAraligiSec() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _tarihAraligi,
      builder: (context, child) {
        return Localizations.override(
          context: context,
          locale: const Locale('tr', 'TR'),
          child: child,
        );
      },
    );
    if (range != null) {
      setState(() {
        _tarihAraligi = range;
        _seciliPeriyot = 'ozel';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Süt Raporu Seçenekleri'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPeriyotSecim('Bugün', 'bugun'),
          _buildPeriyotSecim('Son 7 Gün', 'haftalik'),
          _buildPeriyotSecim('Bu Ay', 'aylik'),
          _buildTarihAraligiSecim(),
          if (_tarihAraligi != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                '${DateFormat('dd MMMM yyyy', 'tr_TR').format(_tarihAraligi!.start)} - ${DateFormat('dd MMMM yyyy', 'tr_TR').format(_tarihAraligi!.end)}',
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          onPressed: _tarihAraligi == null ? null : () {
            Navigator.pop(context);
            widget.onOlustur(_tarihAraligi!);
          },
          child: const Text('Oluştur'),
        ),
      ],
    );
  }

  Widget _buildPeriyotSecim(String title, String value) {
    return ListTile(
      title: Text(title),
      leading: Radio<String>(
        value: value,
        groupValue: _seciliPeriyot,
        onChanged: (value) => _periyotSec(value!),
      ),
    );
  }

  Widget _buildTarihAraligiSecim() {
    return ListTile(
      title: const Text('Tarih Aralığı'),
      leading: Radio<String>(
        value: 'ozel',
        groupValue: _seciliPeriyot,
        onChanged: (value) => _tarihAraligiSec(),
      ),
      onTap: _tarihAraligiSec,
    );
  }
}

class _YemRaporDialog extends StatefulWidget {
  final Function(DateTimeRange) onOlustur;
  const _YemRaporDialog({required this.onOlustur});

  @override
  State<_YemRaporDialog> createState() => _YemRaporDialogState();
}

class _YemRaporDialogState extends State<_YemRaporDialog> {
  DateTimeRange? _tarihAraligi;
  String _seciliPeriyot = 'bugun';

  @override
  void initState() {
    super.initState();
    _periyotSec('bugun');
  }

  void _periyotSec(String periyot) {
    setState(() {
      _seciliPeriyot = periyot;
      final now = DateTime.now();
      switch (periyot) {
        case 'bugun':
          _tarihAraligi = DateTimeRange(start: now, end: now);
          break;
        case 'haftalik':
          _tarihAraligi = DateTimeRange(
            start: now.subtract(const Duration(days: 6)),
            end: now
          );
          break;
        case 'aylik':
          _tarihAraligi = DateTimeRange(
            start: DateTime(now.year, now.month, 1),
            end: DateTime(now.year, now.month + 1, 0)
          );
          break;
        case 'ozel':
          if (_tarihAraligi == null) {
            _tarihAraligi = DateTimeRange(
              start: now.subtract(const Duration(days: 30)),
              end: now
            );
          }
          break;
      }
    });
  }

  Future<void> _tarihAraligiSec() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _tarihAraligi,
      builder: (context, child) {
        return Localizations.override(
          context: context,
          locale: const Locale('tr', 'TR'),
          child: child,
        );
      },
    );
    if (range != null) {
      setState(() {
        _tarihAraligi = range;
        _seciliPeriyot = 'ozel';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Yem Raporu Seçenekleri'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPeriyotSecim('Bugün', 'bugun'),
          _buildPeriyotSecim('Son 7 Gün', 'haftalik'),
          _buildPeriyotSecim('Bu Ay', 'aylik'),
          _buildTarihAraligiSecim(),
          if (_tarihAraligi != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                '${DateFormat('dd MMMM yyyy', 'tr_TR').format(_tarihAraligi!.start)} - ${DateFormat('dd MMMM yyyy', 'tr_TR').format(_tarihAraligi!.end)}',
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          onPressed: _tarihAraligi == null ? null : () {
            Navigator.pop(context);
            widget.onOlustur(_tarihAraligi!);
          },
          child: const Text('Oluştur'),
        ),
      ],
    );
  }

  Widget _buildPeriyotSecim(String title, String value) {
    return ListTile(
      title: Text(title),
      leading: Radio<String>(
        value: value,
        groupValue: _seciliPeriyot,
        onChanged: (value) => _periyotSec(value!),
      ),
    );
  }

  Widget _buildTarihAraligiSecim() {
    return ListTile(
      title: const Text('Tarih Aralığı'),
      leading: Radio<String>(
        value: 'ozel',
        groupValue: _seciliPeriyot,
        onChanged: (value) => _tarihAraligiSec(),
      ),
      onTap: _tarihAraligiSec,
    );
  }
}

// Cari Düzenleme Sayfası
class CariDuzenle extends ConsumerStatefulWidget {
  final Cari cari;
  const CariDuzenle({required this.cari, super.key});

  @override
  ConsumerState<CariDuzenle> createState() => _CariDuzenleState();
}

class _CariDuzenleState extends ConsumerState<CariDuzenle> {
  final _formKey = GlobalKey<FormState>();
  final _adController = TextEditingController();
  final _soyadController = TextEditingController();
  final _adresController = TextEditingController();
  final _telefonController = TextEditingController();
  String _hayvanTuru = 'İnek';
  bool _kaydediliyor = false;

  @override
  void initState() {
    super.initState();
    _adController.text = widget.cari.ad;
    _soyadController.text = widget.cari.soyad;
    _adresController.text = widget.cari.adres ?? '';
    _telefonController.text = widget.cari.telefon ?? '';
    _hayvanTuru = widget.cari.hayvanTuru ?? 'İnek';
  }

  @override
  void dispose() {
    _adController.dispose();
    _soyadController.dispose();
    _adresController.dispose();
    _telefonController.dispose();
    super.dispose();
  }

  Future<void> _cariGuncelle() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _kaydediliyor = true);

    try {
      final guncellenenCari = Cari(
        id: widget.cari.id,
        ad: _adController.text.trim(),
        soyad: _soyadController.text.trim(),
        adres: _adresController.text.trim(),
        telefon: _telefonController.text.trim(),
        hayvanTuru: _hayvanTuru,
        // Formda olmayan alanlar korunur; aksi halde her düzenlemede
        // carinin notu silinir ve pasif durumu sıfırlanırdı.
        aktif: widget.cari.aktif,
        notMetni: widget.cari.notMetni,
      );

      final repo = await ref.read(cariRepositoryProvider.future);
      await repo.update(guncellenenCari);
      ref.veriDegisti();

      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cari başarıyla güncellendi')),
      );

      Navigator.pop(context, true);
    } catch (error) {
      setState(() => _kaydediliyor = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cari Düzenle'),
        actions: [
          if (_kaydediliyor)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: CircularProgressIndicator(),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _adController,
                decoration: const InputDecoration(labelText: 'Ad'),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Ad zorunludur';
                  return null;
                },
              ),
              TextFormField(
                controller: _soyadController,
                decoration: const InputDecoration(labelText: 'Soyad'),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Soyad zorunludur';
                  return null;
                },
              ),
              TextFormField(
                controller: _telefonController,
                decoration: const InputDecoration(labelText: 'Telefon'),
              ),
              TextFormField(
                controller: _adresController,
                decoration: const InputDecoration(labelText: 'Adres'),
                maxLines: 3,
              ),
              DropdownButtonFormField<String>(
                value: _hayvanTuru,
                items: ['İnek', 'Koyun', 'Tavuk'].map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (value) => setState(() => _hayvanTuru = value!),
                decoration: const InputDecoration(labelText: 'Hayvan Türü'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _kaydediliyor ? null : _cariGuncelle,
                child: _kaydediliyor 
                    ? const CircularProgressIndicator()
                    : const Text('Güncelle'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}