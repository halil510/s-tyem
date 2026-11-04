/// Bağlantı türleri: BLE (Bluetooth Low Energy), Classic Bluetooth (SPP),
/// veya Wi-Fi (TCP socket).
enum TeraziBaglantiTuru { ble, classic, wifi }

extension TeraziBaglantiTuruX on TeraziBaglantiTuru {
  String get kod => switch (this) {
    TeraziBaglantiTuru.ble => 'ble',
    TeraziBaglantiTuru.classic => 'classic',
    TeraziBaglantiTuru.wifi => 'wifi',
  };

  static TeraziBaglantiTuru fromKod(String kod) => switch (kod) {
    'ble' => TeraziBaglantiTuru.ble,
    'classic' => TeraziBaglantiTuru.classic,
    'wifi' => TeraziBaglantiTuru.wifi,
    _ => TeraziBaglantiTuru.classic,
  };

  String get gorunenAd => switch (this) {
    TeraziBaglantiTuru.ble => 'Bluetooth LE',
    TeraziBaglantiTuru.classic => 'Bluetooth (Klasik)',
    TeraziBaglantiTuru.wifi => 'Wi-Fi',
  };
}

class TeraziCihazi {
  int? id;
  String cihazAdi;
  String cihazAdresi; // MAC adresi ya da IP
  TeraziBaglantiTuru baglantiTuru;
  int? port; // sadece Wi-Fi için
  bool varsayilan;
  String? sonBaglantiTarihi;

  TeraziCihazi({
    this.id,
    required this.cihazAdi,
    required this.cihazAdresi,
    required this.baglantiTuru,
    this.port,
    this.varsayilan = false,
    this.sonBaglantiTarihi,
  });

  factory TeraziCihazi.fromMap(Map<String, dynamic> m) => TeraziCihazi(
    id: m['id'] as int?,
    cihazAdi: m['cihaz_adi'] ?? '',
    cihazAdresi: m['cihaz_adresi'] ?? '',
    baglantiTuru: TeraziBaglantiTuruX.fromKod(m['baglanti_turu'] ?? 'classic'),
    port: m['port'] as int?,
    varsayilan: (m['varsayilan'] as int?) == 1,
    sonBaglantiTarihi: m['son_baglanti_tarihi'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'cihaz_adi': cihazAdi,
    'cihaz_adresi': cihazAdresi,
    'baglanti_turu': baglantiTuru.kod,
    'port': port,
    'varsayilan': varsayilan ? 1 : 0,
    'son_baglanti_tarihi': sonBaglantiTarihi,
  };
}
