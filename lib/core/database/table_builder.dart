import 'package:sqflite/sqflite.dart';

/// ─────────────────────────────────────────────────────────────
/// TABLE BUILDER — Profesyonel, fluent (zincirlenebilir) tablo DSL'i
/// ─────────────────────────────────────────────────────────────
///
/// Amaç: Ham SQL string'leri elle yazmak yerine, okunabilir ve
/// hatasız bir şekilde tablo şemaları tanımlamak.
///
/// Kullanım:
/// ```dart
/// await TableBuilder('cariler')
///   .id()
///   .text('ad', notNull: true)
///   .text('soyad', notNull: true)
///   .text('adres')
///   .real('bakiye', defaultValue: '0')
///   .boolean('aktif', defaultValue: true)
///   .timestamps()
///   .create(db);
/// ```
class ColumnDef {
  final String name;
  final String type;
  final bool notNull;
  final String? defaultValue;
  final bool primaryKey;
  final bool autoIncrement;

  const ColumnDef(
    this.name, {
    required this.type,
    this.notNull = false,
    this.defaultValue,
    this.primaryKey = false,
    this.autoIncrement = false,
  });

  String toSql() {
    final parts = <String>[name, type];
    if (primaryKey) {
      parts.add('PRIMARY KEY');
      if (autoIncrement) parts.add('AUTOINCREMENT');
    }
    if (notNull) parts.add('NOT NULL');
    if (defaultValue != null) parts.add('DEFAULT $defaultValue');
    return parts.join(' ');
  }
}

class ForeignKeyDef {
  final String column;
  final String refTable;
  final String refColumn;
  final String onDelete;

  const ForeignKeyDef(
    this.column, {
    required this.refTable,
    this.refColumn = 'id',
    this.onDelete = 'CASCADE',
  });

  String toSql() =>
      'FOREIGN KEY ($column) REFERENCES $refTable($refColumn) ON DELETE $onDelete';
}

class TableBuilder {
  final String tableName;
  final List<ColumnDef> _columns = [];
  final List<ForeignKeyDef> _foreignKeys = [];
  final List<String> _uniqueGroups = [];
  bool _ifNotExists = true;

  TableBuilder(this.tableName);

  /// Otomatik artan birincil anahtar (id INTEGER PRIMARY KEY AUTOINCREMENT)
  TableBuilder id({String name = 'id'}) {
    _columns.add(ColumnDef(name, type: 'INTEGER', primaryKey: true, autoIncrement: true));
    return this;
  }

  TableBuilder text(String name, {bool notNull = false, String? defaultValue}) {
    _columns.add(ColumnDef(
      name,
      type: 'TEXT',
      notNull: notNull,
      defaultValue: defaultValue != null ? "'$defaultValue'" : null,
    ));
    return this;
  }

  TableBuilder integer(String name, {bool notNull = false, String? defaultValue}) {
    _columns.add(ColumnDef(name, type: 'INTEGER', notNull: notNull, defaultValue: defaultValue));
    return this;
  }

  TableBuilder real(String name, {bool notNull = false, String defaultValue = '0'}) {
    _columns.add(ColumnDef(name, type: 'REAL', notNull: notNull, defaultValue: defaultValue));
    return this;
  }

  /// SQLite'ta boolean yoktur; 0/1 INTEGER olarak tutulur.
  TableBuilder boolean(String name, {bool defaultValue = false}) {
    _columns.add(ColumnDef(name, type: 'INTEGER', defaultValue: defaultValue ? '1' : '0'));
    return this;
  }

  /// created_at / updated_at sütunlarını otomatik ekler.
  TableBuilder timestamps() {
    _columns.add(const ColumnDef('created_at', type: 'TEXT', defaultValue: "(datetime('now'))"));
    _columns.add(const ColumnDef('updated_at', type: 'TEXT', defaultValue: "(datetime('now'))"));
    return this;
  }

  /// Serbest metin sütun tanımı (özel durumlar için escape hatch).
  TableBuilder raw(String columnSql) {
    _rawColumns.add(columnSql);
    return this;
  }

  final List<String> _rawColumns = [];

  TableBuilder foreignKey(
    String column, {
    required String refTable,
    String refColumn = 'id',
    String onDelete = 'CASCADE',
  }) {
    _foreignKeys.add(ForeignKeyDef(column, refTable: refTable, refColumn: refColumn, onDelete: onDelete));
    return this;
  }

  TableBuilder unique(List<String> columns) {
    _uniqueGroups.add('UNIQUE(${columns.join(', ')})');
    return this;
  }

  TableBuilder ifNotExists([bool value = true]) {
    _ifNotExists = value;
    return this;
  }

  String buildSql() {
    final defs = <String>[
      ..._columns.where((c) => c.name.isNotEmpty).map((c) => c.toSql()),
      ..._rawColumns,
      ..._uniqueGroups,
      ..._foreignKeys.map((f) => f.toSql()),
    ];
    final exists = _ifNotExists ? 'IF NOT EXISTS ' : '';
    return 'CREATE TABLE $exists$tableName (\n  ${defs.join(',\n  ')}\n)';
  }

  Future<void> create(DatabaseExecutor db) async {
    await db.execute(buildSql());
  }
}

/// ─────────────────────────────────────────────────────────────
/// COLUMN PATCHER — mevcut tablolara güvenli (idempotent) değişiklik
/// ─────────────────────────────────────────────────────────────
///
/// Uygulama her açıldığında çağrılabilir; sütun/tablo/index zaten
/// varsa hiçbir şey yapmaz, hata fırlatmaz.
class SchemaInspector {
  static Future<bool> addColumnIfMissing(
    DatabaseExecutor db,
    String table,
    String column,
    String definition,
  ) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    final exists = cols.any((c) => c['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
      return true;
    }
    return false;
  }

  static Future<bool> tableExists(DatabaseExecutor db, String table) async {
    final res = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [table],
    );
    return res.isNotEmpty;
  }

  static Future<bool> indexExists(DatabaseExecutor db, String index) async {
    final res = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index' AND name=?",
      [index],
    );
    return res.isNotEmpty;
  }

  static Future<void> createIndexIfMissing(
    DatabaseExecutor db,
    String indexName,
    String table,
    List<String> columns, {
    bool unique = false,
  }) async {
    if (!await indexExists(db, indexName)) {
      final uniqueKw = unique ? 'UNIQUE ' : '';
      await db.execute(
        'CREATE ${uniqueKw}INDEX IF NOT EXISTS $indexName ON $table (${columns.join(', ')})',
      );
    }
  }
}
