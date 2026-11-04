import 'package:sqflite/sqflite.dart';

/// Kapalı bir döneme yazma denendi; veritabanı tetikleyicisi engelledi
/// (bkz. migration v9).
class DonemKapaliHatasi implements Exception {
  const DonemKapaliHatasi();

  @override
  String toString() =>
      'Bu tarih kapatılmış bir döneme ait; kayıt eklenemez, değiştirilemez '
      'veya silinemez. Gerekirse Menü → Dönem Kapanışı ekranından dönemi '
      'yeniden açın.';
}

bool donemKapaliHatasiMi(Object e) =>
    e is DonemKapaliHatasi || (e is DatabaseException && e.toString().contains('DONEM_KAPALI'));

/// Veritabanının "DONEM_KAPALI" hatasını kullanıcıya okunur hataya çevirir.
Future<T> donemKilidiyle<T>(Future<T> Function() islem) async {
  try {
    return await islem();
  } on DatabaseException catch (e) {
    if (donemKapaliHatasiMi(e)) throw const DonemKapaliHatasi();
    rethrow;
  }
}
