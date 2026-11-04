import 'package:sqflite/sqflite.dart';

/// ─────────────────────────────────────────────────────────────
/// MIGRATION — Tek bir şema değişikliğini temsil eden temel sınıf
/// ─────────────────────────────────────────────────────────────
///
/// Her yeni şema değişikliği (yeni tablo, yeni sütun, yeni index vb.)
/// kendi migration dosyasında, artan bir `version` numarasıyla tanımlanır.
/// [MigrationRunner] bu migration'ları sırayla, veritabanının mevcut
/// `PRAGMA user_version` değerine göre uygular.
///
/// Kurallar:
/// - Bir migration'ın `version` numarası SABİTTİR, yayınlandıktan sonra
///   asla değiştirilmez (kullanıcı cihazlarında zaten uygulanmış olabilir).
/// - `up` metodu **idempotent** yazılmalıdır (mümkünse `IF NOT EXISTS`
///   kullanılmalı) — bu sayede aynı migration yanlışlıkla iki kez
///   çalışsa bile veri bozulmaz.
abstract class Migration {
  /// Bu migration'ın hedef versiyon numarası (1, 2, 3, ...).
  int get version;

  /// Migration'ın ne yaptığına dair kısa, insan-okur açıklama.
  /// Migration günlüğünde (audit log) saklanır.
  String get description;

  /// Şema değişikliğini uygular.
  ///
  /// NOT: Bu metod [MigrationRunner] tarafından bir transaction İÇİNDE
  /// çağrılır ve parametre olarak transaction'ın kendisini (`txn`) alır.
  /// Buraya asla dışarıdaki `Database` nesnesi geçilmemelidir — aynı
  /// bağlantı üzerinde açık bir transaction varken o bağlantının kendisini
  /// kullanmak (txn yerine) sqflite'ta KİLİTLENMEYE (deadlock) yol açar:
  /// transaction, içindeki işlemin bitmesini bekler; o işlem de
  /// transaction'ın bıraktığı kilidin açılmasını bekler.
  Future<void> up(DatabaseExecutor db);

  /// Migration'ı geri alır (opsiyonel). SQLite'ta çoğu yapısal
  /// değişikliği geri almak riskli/karmaşık olduğundan varsayılan
  /// olarak desteklenmez; gerekiyorsa alt sınıfta override edilir.
  Future<void> down(DatabaseExecutor db) async {
    throw UnsupportedError(
      'Migration v$version ($description) geri alma işlemini desteklemiyor.',
    );
  }

  @override
  String toString() => 'Migration(v$version: $description)';
}
