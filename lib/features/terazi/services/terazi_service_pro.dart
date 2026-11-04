import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../../services/terazi_service.dart' as legacy;
import '../../../data/repositories/terazi_cihaz_repository.dart';
import '../../../models/terazi_cihaz_model.dart';
import 'terazi_baglanti_durumu.dart';

/// ─────────────────────────────────────────────────────────────
/// TERAZİ SERVİSİ (PRO)
/// ─────────────────────────────────────────────────────────────
///
/// Mevcut düşük seviyeli `legacy.TeraziService` (BLE / Classic
/// Bluetooth / Wi-Fi aktarımını zaten yönetiyor) üzerine profesyonel
/// bir katman ekler:
///
/// - Ayrıntılı bağlantı durumu (`TeraziBaglantiDurumu`) — sadece
///   bağlı/değil değil, "bağlanıyor", "yeniden bağlanıyor" gibi ara
///   durumları da UI'a bildirir.
/// - Beklenmedik kopmalarda **otomatik yeniden bağlanma** (üstel
///   geri çekilme ile — 2sn, 4sn, 8sn).
/// - Başarılı bağlantıları [TeraziCihazRepository] üzerinden kalıcı
///   hale getirme, böylece uygulama yeniden açıldığında en son / en
///   çok tercih edilen teraziye otomatik bağlanmayı deneyebilme.
/// - Kullanıcı elle "bağlantıyı kes" dediğinde otomatik yeniden
///   bağlanma denemelerinin tamamen durdurulması (istenmeyen
///   yeniden bağlanmaları önler).
class TeraziServicePro {
  TeraziServicePro(this._cihazRepository);

  final TeraziCihazRepository _cihazRepository;
  final legacy.TeraziService _legacy = legacy.TeraziService();

  final _durumController = StreamController<TeraziBaglantiDurumu>.broadcast();
  TeraziBaglantiDurumu _durum = TeraziBaglantiDurumu.bagliDegil;

  Stream<TeraziBaglantiDurumu> get durumStream => _durumController.stream;
  TeraziBaglantiDurumu get durum => _durum;

  Stream<String> get agirlikStream => _legacy.weightStream;

  StreamSubscription<bool>? _baglantiSub;
  TeraziCihazi? _sonBaglanilanCihaz;
  int _yenidenDenemeSayaci = 0;
  static const int _maxYenidenDeneme = 3;
  bool _kullaniciBaglantiyiKesti = false;
  Timer? _yenidenBaglanTimer;

  void _durumGuncelle(TeraziBaglantiDurumu yeni) {
    _durum = yeni;
    _durumController.add(yeni);
  }

  void _dinlemeyeBasla() {
    _baglantiSub?.cancel();
    _baglantiSub = _legacy.connectionStream.listen((bagli) {
      if (bagli) {
        _yenidenDenemeSayaci = 0;
        _durumGuncelle(TeraziBaglantiDurumu.bagli);
        if (_sonBaglanilanCihaz != null) {
          _cihazRepository.kaydetVeyaGuncelle(_sonBaglanilanCihaz!);
        }
      } else {
        if (!_kullaniciBaglantiyiKesti && _sonBaglanilanCihaz != null) {
          _otomatikYenidenBaglan();
        } else {
          _durumGuncelle(TeraziBaglantiDurumu.bagliDegil);
        }
      }
    });
  }

  Future<void> _otomatikYenidenBaglan() async {
    if (_yenidenDenemeSayaci >= _maxYenidenDeneme || _sonBaglanilanCihaz == null) {
      _durumGuncelle(TeraziBaglantiDurumu.hata);
      return;
    }
    _yenidenDenemeSayaci++;
    _durumGuncelle(TeraziBaglantiDurumu.yenidenBaglaniyor);

    final bekleme = Duration(seconds: 2 * _yenidenDenemeSayaci); // 2s, 4s, 6s
    _yenidenBaglanTimer?.cancel();
    _yenidenBaglanTimer = Timer(bekleme, () async {
      final cihaz = _sonBaglanilanCihaz;
      if (cihaz == null || _kullaniciBaglantiyiKesti) return;
      try {
        await _cihazaBagla(cihaz, kaydet: false);
      } catch (e) {
        if (kDebugMode) debugPrint('[TeraziServicePro] Yeniden bağlanma başarısız: $e');
        _otomatikYenidenBaglan();
      }
    });
  }

  /// Cihazla eşleşmiş (paired) Classic Bluetooth cihazlarını listeler.
  Future<List<Map<String, dynamic>>> classicEslenmisCihazlar() =>
      _legacy.classicService.getPairedDevices();

  /// BLE terazi tarama (izin kontrolü dahil).
  Future<List<BluetoothDevice>> bleTara({Duration timeout = const Duration(seconds: 8)}) async {
    _durumGuncelle(TeraziBaglantiDurumu.taraniyor);
    try {
      final sonuc = await _legacy.scanBLEDevices(timeout: timeout);
      _durumGuncelle(_durum == TeraziBaglantiDurumu.bagli
          ? TeraziBaglantiDurumu.bagli
          : TeraziBaglantiDurumu.bagliDegil);
      return sonuc;
    } catch (e) {
      _durumGuncelle(TeraziBaglantiDurumu.hata);
      rethrow;
    }
  }

  Future<void> bleyeBagla(BluetoothDevice device, {String? cihazAdi}) => _cihazaBagla(
        TeraziCihazi(
          cihazAdi: cihazAdi ?? device.platformName,
          cihazAdresi: device.remoteId.str,
          baglantiTuru: TeraziBaglantiTuru.ble,
        ),
        bleDevice: device,
      );

  Future<void> classicBagla(String address, {String? cihazAdi}) => _cihazaBagla(
        TeraziCihazi(
          cihazAdi: cihazAdi ?? address,
          cihazAdresi: address,
          baglantiTuru: TeraziBaglantiTuru.classic,
        ),
      );

  Future<void> wifiBagla(String ip, int port, {String? cihazAdi}) => _cihazaBagla(
        TeraziCihazi(
          cihazAdi: cihazAdi ?? '$ip:$port',
          cihazAdresi: ip,
          baglantiTuru: TeraziBaglantiTuru.wifi,
          port: port,
        ),
      );

  Future<void> _cihazaBagla(
    TeraziCihazi cihaz, {
    BluetoothDevice? bleDevice,
    bool kaydet = true,
  }) async {
    _kullaniciBaglantiyiKesti = false;
    _dinlemeyeBasla();
    _durumGuncelle(TeraziBaglantiDurumu.baglaniyor);
    _sonBaglanilanCihaz = cihaz;

    try {
      switch (cihaz.baglantiTuru) {
        case TeraziBaglantiTuru.ble:
          // Cihaz referansı verilmemişse (ör. otomatik yeniden bağlanma),
          // kaydedilmiş MAC/UUID adresinden yeniden oluşturuyoruz — bu,
          // flutter_blue_plus'ta yeniden tarama yapmadan bilinen bir
          // cihaza bağlanmanın standart yoludur.
          final hedefCihaz = bleDevice ?? BluetoothDevice.fromId(cihaz.cihazAdresi);
          await _legacy.connectToBLETerazi(hedefCihaz);
          break;
        case TeraziBaglantiTuru.classic:
          await _legacy.connectToClassic(cihaz.cihazAdresi);
          break;
        case TeraziBaglantiTuru.wifi:
          await _legacy.connectWifi(cihaz.cihazAdresi, cihaz.port ?? 8080);
          break;
      }

      if (kaydet) {
        await _cihazRepository.kaydetVeyaGuncelle(cihaz);
      }
    } catch (e) {
      _durumGuncelle(TeraziBaglantiDurumu.hata);
      rethrow;
    }
  }

  /// Uygulama açılışında, daha önce kaydedilmiş varsayılan cihaza
  /// otomatik bağlanmayı dener (BLE dahil — `BluetoothDevice.fromId`
  /// sayesinde yeniden tarama yapmadan bağlanabiliyoruz; yalnızca
  /// Bluetooth kapalıysa veya cihaz menzil dışındaysa başarısız olur).
  Future<bool> baslangicOtomatikBaglan() async {
    final varsayilan = await _cihazRepository.getVarsayilan();
    if (varsayilan == null) return false;
    try {
      await _cihazaBagla(varsayilan, kaydet: false);
      return true;
    } catch (_) {
      // Bu, kullanıcının başlatmadığı sessiz bir deneme — başarısız
      // olursa "hata" durumu göstermek yerine nötr "bağlı değil"e
      // dönülür, kullanıcı manuel "Bağlan" ile tekrar deneyebilir.
      _durumGuncelle(TeraziBaglantiDurumu.bagliDegil);
      return false;
    }
  }

  Future<void> baglantiyiKes() async {
    _kullaniciBaglantiyiKesti = true;
    _yenidenBaglanTimer?.cancel();
    _yenidenDenemeSayaci = 0;
    await _legacy.disconnect();
    _durumGuncelle(TeraziBaglantiDurumu.bagliDegil);
  }

  void dispose() {
    _yenidenBaglanTimer?.cancel();
    _baglantiSub?.cancel();
    _durumController.close();
    _legacy.dispose();
  }
}
