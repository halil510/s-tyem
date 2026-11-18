import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import '../utils/excel_yedekleme.dart';
import '../core/database/app_database.dart';
import '../data/repositories/veri_yonetimi_repository.dart';
import '../bluetooth/bluetooth_cihaz_secme.dart';
import '../bluetooth/wifi_transfer_service.dart';
import '../utils/app_locker.dart';
import '../data/yedek/yedek_servisi.dart';
import '../data/yedek/otomatik_yedek.dart';
import 'otomatik_yedekler_ekrani.dart';
import '../core/providers/veri_surumu_provider.dart';
import '../core/providers/database_provider.dart';
import '../senkron/senkron_yoneticisi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class YedeklemeEkrani extends StatefulWidget {
  const YedeklemeEkrani({super.key});

  @override
  State<YedeklemeEkrani> createState() => _YedeklemeEkraniState();
}

class _YedeklemeEkraniState extends State<YedeklemeEkrani> {
  bool _isProcessing = false;
  String _kayitliSifre = '12345';
  int _selectedIndex = 0;
  final AppLocker _appLocker = AppLocker();
  Map<String, String> _deviceInfo = {};

  // Başlıktaki sayılar ve sahip bilgisi BİR KEZ okunur (eskiden her yeniden
  // çizimde yeni sorgu atılıyor, sayılar bir an 0 görünüp titriyordu).
  // Veri değişince [_istatistikYenile] ile tazelenir.
  late Future<Map<String, int>> _istatistik = _getStatistics();
  late final Future<String> _sahipBilgisi = _appLocker.getOwnerInfo();
  late final Future<String> _kullanilanSifre = _appLocker.getUsedPassword();

  void _istatistikYenile() {
    if (mounted) setState(() => _istatistik = _getStatistics());
  }

  @override
  void initState() {
    super.initState();
    _loadPassword();
    _loadDeviceInfo();
  }

  Future<void> _loadPassword() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _kayitliSifre = prefs.getString('veritabani_sifre') ?? '12345';
    });
  }

  Future<void> _loadDeviceInfo() async {
    final info = await _appLocker.getDeviceInfo();
    if (!mounted) return;
    setState(() {
      _deviceInfo = info;
    });
  }

  Future<void> _savePassword(String yeniSifre) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('veritabani_sifre', yeniSifre);
    setState(() {
      _kayitliSifre = yeniSifre;
    });
    _showSnack('✅ Şifre güncellendi');
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    // Önceki mesaj kuyrukta bekletmesin (art arda "SİL yazın" / "Hatalı şifre").
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      )
    );
  }

  /// Toplu veri işlemleri repository üzerinden (ekran SQL yazmaz).
  Future<VeriYonetimiRepository> get _veriRepo async =>
      VeriYonetimiRepository(await AppDatabase.instance.database);

  Future<Map<String, int>> _getStatistics() async {
    try {
      final s = await (await _veriRepo).kayitSayilari();
      return {'sut': s.sut, 'yem': s.yem, 'cari': s.cari};
    } catch (e) {
      return {'sut': 0, 'yem': 0, 'cari': 0};
    }
  }

  Future<void> _excelYedekle() async {
    setState(() => _isProcessing = true);
    try {
      await ExcelYedekleme.showYedeklemeDialog(context);
    } catch (e) {
      _showSnack('❌ Excel yedekleme hatası: $e');
    }
    setState(() => _isProcessing = false);
  }

  Future<void> _dbYedekle() async {
    setState(() => _isProcessing = true);
    // Kullanıcı isteği (2026-11-19): WhatsApp'a paylaşma değil, telefonda sakla.
    // Android: İndirilenler/SutYem_Yedekleri (uygulama silinse de kalır, 20 gün).
    // Tutarlı kopya + kopyanın sağlam olduğu kaydetmeden ÖNCE denetlenir.
    Future<File> al() => OtomatikYedek.veritabaniYedekAl(
          kopyala: AppDatabase.instance.tutarliKopyala,
          dogrula: VeriYonetimiRepository.dbDosyasiniDogrula,
        );
    try {
      File dosya;
      try {
        dosya = await al();
      } on FileSystemException {
        // Android 9 ve altı: ortak klasöre yazmak için depolama izni gerekir.
        if (!Platform.isAndroid || !(await Permission.storage.request()).isGranted) rethrow;
        dosya = await al();
      }
      final yer = Platform.isAndroid
          ? 'İndirilenler/${OtomatikYedek.disKlasorAdi}/${p.basename(dosya.path)}'
          : dosya.path;
      _showSnack('✅ Veritabanı yedeği telefona kaydedildi: $yer');
    } catch (e) {
      _showSnack('❌ Yedek kaydedilemedi: $e');
    }
    setState(() => _isProcessing = false);
  }

  Future<void> _wifiIleYedekle() async {
    setState(() => _isProcessing = true);
    try {
      await WiFiTransferService.sendViaWiFiDirect(context);
      _showSnack('✅ Wi-Fi yedekleme başlatıldı');
    } catch (e) {
      _showSnack('❌ Wi-Fi yedekleme hatası: $e');
    }
    setState(() => _isProcessing = false);
  }

  Future<void> _dbIceriAl() async {
    setState(() => _isProcessing = true);

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('⚠️ Dikkat'),
          content: const Text(
            'Mevcut veriler SEÇTİĞİNİZ dosya ile değiştirilecektir.\n\n'
            'Devam etmeden önce mutlaka yedek alınız.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Devam Et'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
      if (!mounted) return;

      final sifreCtrl = TextEditingController();
      final sifreOk = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('🔒 Şifre Doğrulama'),
          content: TextField(
            controller: sifreCtrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Şifre'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () {
                if (sifreCtrl.text == _kayitliSifre) {
                  Navigator.pop(context, true);
                } else {
                  _showSnack('❌ Hatalı şifre');
                  Navigator.pop(context, false);
                }
              },
              child: const Text('Onayla'),
            ),
          ],
        ),
      );

      if (sifreOk != true) return;
      if (!mounted) return;

      // Dosya tipi seçimi
      final dosyaTipi = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Dosya Türü Seçin'),
          content: const Text('Hangi tür dosyayı içeri almak istiyorsunuz?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'json'),
              child: const Text('JSON Dosyası (.json)'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'db'),
              child: const Text('Veritabanı (.db)'),
            ),
          ],
        ),
      );

      if (dosyaTipi == null) {
        _showSnack('❌ Dosya türü seçilmedi');
        return;
      }

      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: dosyaTipi == 'json' ? FileType.custom : FileType.any,
        allowedExtensions: dosyaTipi == 'json' ? ['json'] : null,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        _showSnack('❌ Dosya seçilmedi');
        return;
      }

      final filePath = result.files.single.path;
      if (filePath == null) {
        _showSnack('❌ Dosya yolu alınamadı');
        return;
      }

      final selectedFile = File(filePath);
      final size = await selectedFile.length();
      if (size < 100) {
        _showSnack('❌ Dosya geçersiz veya bozuk');
        return;
      }

      if (dosyaTipi == 'json') {
        // JSON dosyası import et
        await _importJsonFile(selectedFile);
      } else {
        // DB dosyası import et
        await _importDbFile(selectedFile);
      }

    } catch (e) {
      _showSnack('❌ Hata: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  /// JSON yedeğini geri yükler (bkz. [YedekServisi.iceAktar]): kullanıcı
  /// "yedekteki hale getir" ya da "birleştir" seçer. Hata olursa hiçbir
  /// değişiklik yazılmaz.
  Future<void> _importJsonFile(File jsonFile) async {
    _showSnack('JSON dosyası okunuyor...');
    final veri = YedekServisi.coz(await jsonFile.readAsString());

    // Güvenlik kontrolü
    final isAppLocked = await _appLocker.isAppActivated();
    if (isAppLocked) {
      final canImport = await _checkImportPermission();
      if (!canImport) {
        throw Exception('İçeri alma izni reddedildi');
      }
    }

    // Yükleme biçimi: tam yedekte varsayılan "yedekteki hale getir". Birleştirmede
    // yedekten sonra silinen kayıtlar geri gelir, yedekten sonra girilenler kalır.
    var tamamen = false;
    if (YedekServisi.tamYedekMi(veri)) {
      if (!mounted) return;
      final secim = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Nasıl yüklensin?'),
          content: const Text(
            'Yedekteki hale getir: telefondaki TÜM kayıtlar yedektekiyle değiştirilir '
            '(yedekten sonra girilenler silinir). Elle aldığınız yedeği geri almak için bunu seçin.\n\n'
            'Birleştir: yedekteki kayıtlar eklenir/güncellenir, telefonda olup yedekte olmayanlar kalır.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Birleştir')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yedekteki hale getir')),
          ],
        ),
      );
      if (secim == null) return;
      tamamen = secim;
    }

    await OtomatikYedek.islemOncesiAl('json_geri_yukleme');
    _showSnack('Veritabanına uygulanıyor...');
    final ozet = await (await _veriRepo).yedekYukle(veri, tamamenDegistir: tamamen);
    if (mounted) {
      veriDegistiBildir(context);
      _istatistikYenile();
    }
    _showSnack('✅ Yedek geri yüklendi: ${ozet.toplam} kayıt');
  }

  Future<void> _importDbFile(File dbFile) async {
    if (!dbFile.path.toLowerCase().endsWith('.db')) {
      throw Exception('Sadece .db uzantılı dosyalar kabul edilir');
    }

    // Canlı veritabanının üzerine yazmadan ÖNCE dosyanın gerçekten bu
    // uygulamanın veritabanı olduğunu doğrula. Aksi halde yanlış bir .db
    // seçildiğinde uygulama açılışta onu "bozuk" sayıp boş veritabanıyla
    // başlar ve kullanıcı tüm verilerinin gittiğini sanır.
    await VeriYonetimiRepository.dbDosyasiniDogrula(dbFile.path);

    // 0) Mevcut verinin güvenlik yedeği (Otomatik Yedekler listesinden geri
    //    alınabilir). Alınamazsa geri yükleme YAPILMAZ.
    await OtomatikYedek.islemOncesiAl('db_geri_yukleme');

    final docDir = await getApplicationDocumentsDirectory();
    try {
      await _dosyayiDegistir(dbFile, docDir);
    } catch (_) {
      _veritabaniniYenidenAc(); // eski dosya yerinde; bağlantıyı tazele
      rethrow;
    }

    // 4) Uygulama yeni veritabanını hemen kullansın (eskiden kapalı
    //    veritabanıyla devam edip her ekranda hata veriyordu).
    _veritabaniniYenidenAc();
    _showSnack('✅ Veritabanı başarıyla geri yüklendi');
    _showRestartDialog();
  }

  Future<void> _dosyayiDegistir(File dbFile, Directory docDir) =>
      AppDatabase.instance.dosyayiDegistir((yol) async {
      final mevcutDb = File(yol);

      // 1) Yeni dosya ÖNCE yanına geçici kopyalanır ve diskte tamamlanır.
      final gecici = File('$yol.geri_yukleme');
      if (await gecici.exists()) await gecici.delete();
      await dbFile.copy(gecici.path);

      // 2) Mevcut veritabanının ham kopyası (bağlantı kapalı, tutarlı).
      if (await mevcutDb.exists()) {
        await mevcutDb.copy('${docDir.path}/sut_yem_backup_${DateTime.now().millisecondsSinceEpoch}.db');
      }

      // 3) Tek adımda yer değiştir. Eskiden önce eski dosya SİLİNİP sonra yeni
      //    dosya taşınıyordu: arada şarj biterse uygulama BOŞ açılıyordu.
      try {
        await AppDatabase.dosyayiYerineKoy(gecici, yol);
      } catch (_) {
        if (await gecici.exists()) await gecici.delete();
        rethrow;
      }
    });

  /// Açık ekranların ve servislerin yeni / geri konan veritabanını
  /// kullanması için veritabanı sağlayıcısını yeniler.
  void _veritabaniniYenidenAc() {
    if (!mounted) return;
    final kap = ProviderScope.containerOf(context, listen: false);
    kap.invalidate(databaseProvider);
    veriDegistiBildir(context);
    _istatistikYenile();
    // Çoklu cihaz: senkron yeni dosyayla (günlük tabandan kurularak) yeniden başlar.
    SenkronYoneticisi().veritabaniDegisti();
    kap.read(databaseProvider.future).then(SenkronYoneticisi().baslat).catchError((_) {});
  }

  Future<bool> _checkImportPermission() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ Güvenlik Uyarısı'),
        content: const Text(
          'Uygulama kilitli durumda. Dışarıdan veri içeri almak uygulama güvenliğini riske atabilir.\n\n'
          'Devam etmek için master şifreyi girin:',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Devam'),
          ),
        ],
      ),
    );
    
    if (result != true) return false;
    if (!mounted) return false;
    
    final sifreCtrl = TextEditingController();
    final sifreOk = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Master Şifre'),
        content: TextField(
          controller: sifreCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Master Şifre'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              final verification = await _appLocker.verifyPassword(sifreCtrl.text);
              if (context.mounted) Navigator.pop(context, verification['success'] == true);
            },
            child: const Text('Doğrula'),
          ),
        ],
      ),
    );
    
    return sifreOk == true;
  }

  /// Fırın ERP ile aynı: "Yalnız hareketler" ya da "Her şey (sıfırdan başla)".
  /// Ayarlar (şifre, aktivasyon, yazıcı, terazi, eşitleme) her iki durumda da kalır.
  Future<void> _veritabaniTemizle() async {
    KayitSayilari? sayilar;
    try {
      sayilar = await (await _veriRepo).kayitSayilari();
    } catch (_) {} // sayılar yalnız bilgi; okunamasa da temizlik penceresi açılır
    if (!mounted) return;
    final sifreController = TextEditingController();
    final onayController = TextEditingController();
    var tur = TemizlikTuru.hareketler;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.orange),
              SizedBox(width: 8),
              Expanded(child: Text('Veritabanını temizle')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (sayilar != null)
                Text(
                  'Şu an: ${sayilar.cari} cari, ${sayilar.sut} süt, ${sayilar.yem} yem, ${sayilar.odeme} ödeme/tahsilat',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 8),
                RadioGroup<TemizlikTuru>(
                  groupValue: tur,
                  onChanged: (x) => setD(() => tur = x!),
                  child: const Column(children: [
                    RadioListTile(
                      contentPadding: EdgeInsets.zero,
                      value: TemizlikTuru.hareketler,
                      title: Text('Yalnız hareketler'),
                      subtitle: Text('Süt, yem, ödeme/tahsilat ve dönem kapanışları silinir.\n'
                          'Cariler ve fiyatlar KORUNUR.'),
                    ),
                    RadioListTile(
                      contentPadding: EdgeInsets.zero,
                      value: TemizlikTuru.hepsi,
                      title: Text('Her şey (sıfırdan başla)'),
                      subtitle: Text('Hareketler + cariler ve tüm fiyatlar silinir.\n'
                          'Şifre, aktivasyon, yazıcı, terazi ve ayarlar KALIR.'),
                    ),
                  ]),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Bu işlem geri alınamaz! Önce otomatik güvenlik yedeği alınır (Otomatik Yedekler\'den geri dönülebilir). '
                  'Bulut / yerel ağ eşitlemesi açıksa silme BAĞLI TÜM TELEFONLARA da yansır.',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.deepOrange),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: onayController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Onay için SİL yazın', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: sifreController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Şifre',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final onay = onayController.text.trim().replaceAll('i', 'İ').toUpperCase();
                if (onay != 'SİL' && onay != 'SIL') {
                  _showSnack('❌ Onay için SİL yazın.');
                } else if (sifreController.text.trim() != _kayitliSifre) {
                  _showSnack('❌ Hatalı şifre!');
                } else {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('SİL'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      await _temizlemeIslemi(tur);
    }
  }

  Future<void> _temizlemeIslemi(TemizlikTuru tur) async {
    setState(() => _isProcessing = true);
    try {
      await OtomatikYedek.islemOncesiAl('sut_yem_silme');
      final s = await (await _veriRepo).temizle(tur);
      if (mounted) {
        veriDegistiBildir(context);
        _istatistikYenile();
      }
      _showSnack('✅ Temizlendi: ${s['sutler']} süt, ${s['yemler']} yem, ${s['cari_odemeler']} ödeme/tahsilat'
          '${tur == TemizlikTuru.hepsi ? ', ${s['cariler']} cari' : ' (cariler korundu)'}');
    } catch (e) {
      _showSnack('❌ Hata oluştu, hiçbir kayıt silinmedi: $e');
    }
    if (mounted) setState(() => _isProcessing = false);
  }

  Future<void> _sifreDegistir() async {
    final TextEditingController eskiController = TextEditingController();
    final TextEditingController yeniController = TextEditingController();
    final TextEditingController yeniTekrarController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.password),
            SizedBox(width: 8),
            Text('Şifreyi Değiştir'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: eskiController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Mevcut Şifre',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: yeniController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Yeni Şifre',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: yeniTekrarController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Yeni Şifre (Tekrar)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock_reset),
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
            onPressed: () async {
              if (eskiController.text.trim() != _kayitliSifre) {
                _showSnack('❌ Mevcut şifre hatalı!');
              } else if (yeniController.text.trim().isEmpty) {
                _showSnack('❌ Yeni şifre boş olamaz!');
              } else if (yeniController.text.trim() != yeniTekrarController.text.trim()) {
                _showSnack('❌ Yeni şifreler uyuşmuyor!');
              } else {
                await _savePassword(yeniController.text.trim());
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  void _showRestartDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Başarılı'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Veritabanı başarıyla geri yüklendi!'),
            SizedBox(height: 16),
            Text(
              '⚠️ UYARI:',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
            ),
            SizedBox(height: 8),
            Text(
              'Değişikliklerin etkili olması için uygulamayı KAPATIP TEKRAR AÇMANIZ gerekiyor.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('TAMAM'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return FutureBuilder<Map<String, int>>(
      future: _istatistik,
      builder: (context, snapshot) {
        final stats = snapshot.data ?? {'sut': 0, 'yem': 0, 'cari': 0};
        
        return FutureBuilder<String>(
          future: _sahipBilgisi,
          builder: (context, ownerSnapshot) {
            return FutureBuilder<String>(
              future: _kullanilanSifre,
              builder: (context, passSnapshot) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.blue[700]!, Colors.blue[800]!],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.backup, color: Colors.white, size: 28),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Veri Yönetimi',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
                            Text(
                              ownerSnapshot.data ?? 'Kayıtlı Değil',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Şifre: ${passSnapshot.data ?? 'Yok'}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Expanded(child: _buildStatItem('Süt Kaydı', stats['sut']!, Icons.local_drink)),
                          Expanded(child: _buildStatItem('Yem Kaydı', stats['yem']!, Icons.grass)),
                          Expanded(child: _buildStatItem('Cari', stats['cari']!, Icons.people)),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildStatItem(String title, int count, IconData icon) {
    return FittedBox(fit: BoxFit.scaleDown, child: Column(
      children: [
        Icon(icon, color: Colors.white, size: 24),
        const SizedBox(height: 4),
        Text(
          count.toString(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
      ],
    ));
  }

  Widget _buildActionButton({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool isDanger = false,
  }) {
    return Card(
      elevation: 2,
      child: ListTile(
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isDanger ? Colors.red : null,
          ),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }

  Widget _buildYedeklemeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            'Yedekleme Seçenekleri',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
        ),
        _buildActionButton(
          title: 'Otomatik Güvenlik Yedekleri',
          subtitle: 'Telefonda kendiliğinden alınan yedekler — geri dön / paylaş',
          icon: Icons.shield_outlined,
          color: Colors.teal,
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const OtomatikYedeklerEkrani()));
            _istatistikYenile();
          },
        ),
        const SizedBox(height: 8),
        _buildActionButton(
          title: 'Bluetooth ile Yedekle',
          subtitle: 'Diğer cihazlarla veri paylaşımı',
          icon: Icons.bluetooth,
          color: Colors.blue,
          onTap: () {
            Navigator.push(
              context, 
              MaterialPageRoute(
                builder: (_) => const BluetoothCihazSecmeEkrani()
              )
            );
          },
        ),
        const SizedBox(height: 8),
        _buildActionButton(
          title: 'Wi-Fi ile Yedekle',
          subtitle: 'Hızlı ve büyük dosyalar için',
          icon: Icons.wifi,
          color: Colors.orange,
          onTap: _wifiIleYedekle,
        ),
        const SizedBox(height: 8),
        _buildActionButton(
          title: 'Excel ile Yedekle',
          subtitle: 'Aylık/Yıllık raporlar oluştur',
          icon: Icons.table_chart,
          color: Colors.green,
          onTap: _excelYedekle,
        ),
        const SizedBox(height: 8),
        _buildActionButton(
          title: 'DB ile Yedekle',
          subtitle: 'Tam veritabanı yedeği telefona kaydet (İndirilenler/SutYem_Yedekleri)',
          icon: Icons.backup,
          color: Colors.purple,
          onTap: _dbYedekle,
        ),
        const SizedBox(height: 8),
        _buildActionButton(
          title: 'DB/JSON İçeri Al',
          subtitle: 'Yedeklenmiş DB/JSON dosyasını yükle',
          icon: Icons.restore,
          color: Colors.indigo,
          onTap: _dbIceriAl,
        ),
      ],
    );
  }

  Widget _buildGuvenlikSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            'Güvenlik & Bakım',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
        ),
        _buildActionButton(
          title: 'Veritabanını Temizle',
          subtitle: 'Yalnız hareketler ya da her şey — ayarlar kalır (şifre gerekli)',
          icon: Icons.cleaning_services,
          color: Colors.red,
          isDanger: true,
          onTap: _veritabaniTemizle,
        ),
        const SizedBox(height: 8),
        _buildActionButton(
          title: 'Şifreyi Değiştir',
          subtitle: 'Güvenlik şifresini güncelle',
          icon: Icons.lock_reset,
          color: Colors.purple,
          onTap: _sifreDegistir,
        ),
      ],
    );
  }

  Widget _buildLicenseInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.verified, color: Colors.green),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  'LİSANS BİLGİLERİ',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_deviceInfo.isNotEmpty) ...[
            Text('Cihaz: ${_deviceInfo['platform']}'),
            const SizedBox(height: 4),
            Text('Hash: ${_deviceInfo['device_hash']?.substring(0, 12)}...'),
            const SizedBox(height: 4),
            FutureBuilder<String>(
              future: _sahipBilgisi,
              builder: (context, snapshot) {
                return Text('Sahip: ${snapshot.data ?? "Belirtilmemiş"}');
              },
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'Bu uygulama sadece bu cihazda çalışabilir.',
            style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info, color: Colors.blue, size: 20),
              SizedBox(width: 8),
              Text(
                'Bilgi',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '• Bluetooth: Yakın mesafe için\n'
            '• Wi-Fi: Hızlı ve büyük dosyalar için\n'
            '• Excel: Detaylı raporlar ve analizler\n'
            '• DB Yedekle: Tam yedek telefona kaydedilir (20 gün saklanır)\n'
            '• DB/JSON İçeri Al: Yedekten geri yükleme\n'
            '• Temizleme: Güvenlik şifresi gerektirir',
            style: TextStyle(fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 8),
          Text(
            'Son güncelleme: ${DateTime.now().day}.${DateTime.now().month}.${DateTime.now().year}',
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yedekleme ve Veri Yönetimi'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_isProcessing)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                strokeWidth: 2,
              ),
            ),
        ],
      ),
      body: _isProcessing
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('İşlem yapılıyor...'),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildHeader(),
                  const SizedBox(height: 24),
                  _buildYedeklemeSection(),
                  const SizedBox(height: 24),
                  _buildGuvenlikSection(),
                  const SizedBox(height: 24),
                  _buildLicenseInfoCard(),
                  const SizedBox(height: 16),
                  _buildInfoCard(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() => _selectedIndex = index);
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.backup),
            label: 'Yedekleme',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.local_drink),
            label: 'Süt',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.grass),
            label: 'Yem',
          ),
        ],
      ),
    );
  }
}