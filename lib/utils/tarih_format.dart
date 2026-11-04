import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Türkçe lokalizasyonu başlatır.
/// Bu fonksiyon uygulama açılışında `main()` içinde çağrılmalıdır.
Future<void> initializeTurkishLocale() async {
  await initializeDateFormatting('tr_TR', null);
  Intl.defaultLocale = 'tr_TR'; // 🔹 Varsayılan dili Türkçe yap
}

/// ISO format (örnek: 2025-11-12)
String toIsoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// Okunabilir format (örnek: 12 Kasım 2025)
String readable(DateTime d) => DateFormat('dd MMMM yyyy').format(d);

/// Kısa format (örnek: 12.11.2025)
String readableShort(DateTime d) => DateFormat('dd.MM.yyyy').format(d);

/// Gün ve Ay (örnek: 12 Kasım)
String readableDayMonth(DateTime d) => DateFormat('dd MMMM').format(d);

/// Ay ve Yıl (örnek: Kasım 2025)
String readableMonthYear(DateTime d) => DateFormat('MMMM yyyy').format(d);

/// Excel dosyaları için tarih (örnek: 12/11/2025)
String excelDateFormat(DateTime d) => DateFormat('dd/MM/yyyy').format(d);
