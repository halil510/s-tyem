/// Terazi bağlantısının anlık durumu.
/// Eski servis sadece `bool isConnected` sunuyordu; profesyonel bir
/// arayüz için "bağlanıyor", "yeniden bağlanıyor" ve "hata" ara
/// durumlarının da ayırt edilebilmesi gerekir.
enum TeraziBaglantiDurumu {
  bagliDegil,
  taraniyor,
  baglaniyor,
  bagli,
  yenidenBaglaniyor,
  hata,
}

extension TeraziBaglantiDurumuX on TeraziBaglantiDurumu {
  String get gorunenMetin => switch (this) {
    TeraziBaglantiDurumu.bagliDegil => 'Bağlı değil',
    TeraziBaglantiDurumu.taraniyor => 'Cihazlar taranıyor...',
    TeraziBaglantiDurumu.baglaniyor => 'Bağlanıyor...',
    TeraziBaglantiDurumu.bagli => 'Bağlı',
    TeraziBaglantiDurumu.yenidenBaglaniyor => 'Bağlantı koptu, yeniden deneniyor...',
    TeraziBaglantiDurumu.hata => 'Bağlantı hatası',
  };

  bool get aktifBaglanti => this == TeraziBaglantiDurumu.bagli;
  bool get mesgul =>
      this == TeraziBaglantiDurumu.taraniyor ||
      this == TeraziBaglantiDurumu.baglaniyor ||
      this == TeraziBaglantiDurumu.yenidenBaglaniyor;
}
