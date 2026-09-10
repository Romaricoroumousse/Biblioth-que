import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../../models/document_model.dart';
import '../../models/domain_model.dart';
import 'default_taxonomies.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('smart_pdf_library.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // 1. Table des Domaines
    await db.execute('''
      CREATE TABLE domains (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        icon TEXT,
        color TEXT,
        is_custom INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // 2. Table des Sous-Domaines
    await db.execute('''
      CREATE TABLE subdomains (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        domain_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        FOREIGN KEY (domain_id) REFERENCES domains (id) ON DELETE CASCADE,
        UNIQUE (domain_id, name)
      )
    ''');

    // 3. Table des Documents PDF
    await db.execute('''
      CREATE TABLE documents (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_path TEXT NOT NULL UNIQUE,
        file_name TEXT NOT NULL,
        file_hash TEXT NOT NULL,
        file_size INTEGER NOT NULL,
        page_count INTEGER NOT NULL DEFAULT 0,
        modified_date INTEGER NOT NULL,
        domain_id INTEGER,
        subdomain_id INTEGER,
        summary TEXT,
        keywords TEXT,
        language TEXT,
        level TEXT,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        is_excluded INTEGER NOT NULL DEFAULT 0,
        ai_status TEXT NOT NULL DEFAULT 'pending',
        created_at INTEGER NOT NULL,
        last_opened_at INTEGER,
        FOREIGN KEY (domain_id) REFERENCES domains (id) ON DELETE SET NULL,
        FOREIGN KEY (subdomain_id) REFERENCES subdomains (id) ON DELETE SET NULL
      )
    ''');

    // Index pour accélérer les filtres et vérifications
    await db.execute('CREATE INDEX idx_docs_hash ON documents (file_hash)');
    await db.execute('CREATE INDEX idx_docs_domain ON documents (domain_id)');
    await db.execute('CREATE INDEX idx_docs_subdomain ON documents (subdomain_id)');
    await db.execute('CREATE INDEX idx_docs_favorite ON documents (is_favorite)');

    // 4. Table Virtuelle FTS5 pour la recherche plein texte intelligente
    await db.execute('''
      CREATE VIRTUAL TABLE documents_fts USING fts5(
        document_id UNINDEXED,
        file_name,
        summary,
        keywords,
        domain_name,
        subdomain_name,
        content=''
      )
    ''');

    // Pré-remplir les taxonomies de base
    await _seedDefaultTaxonomies(db);
  }

  Future<void> _seedDefaultTaxonomies(Database db) async {
    final batch = db.batch();
    for (var entry in DefaultTaxonomies.domainsWithSubdomains.entries) {
      final domainName = entry.key;
      final subdomains = entry.value;

      batch.insert(
        'domains',
        {'name': domainName, 'is_custom': 0},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);

    // Récupérer les IDs insérés pour lier les sous-domaines
    for (var entry in DefaultTaxonomies.domainsWithSubdomains.entries) {
      final domainName = entry.key;
      final List<Map<String, dynamic>> res = await db.query(
        'domains',
        columns: ['id'],
        where: 'name = ?',
        whereArgs: [domainName],
      );

      if (res.isNotEmpty) {
        final domainId = res.first['id'] as int;
        final subBatch = db.batch();
        for (var sub in entry.value) {
          subBatch.insert(
            'subdomains',
            {'domain_id': domainId, 'name': sub},
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
        await subBatch.commit(noResult: true);
      }
    }
  }

  // ==================== GESTION DES DOMAINES ====================

  Future<int> getOrCreateDomain(String name, {bool isCustom = false}) async {
    final db = await instance.database;
    final trimmed = name.trim();
    final res = await db.query(
      'domains',
      columns: ['id'],
      where: 'LOWER(name) = ?',
      whereArgs: [trimmed.toLowerCase()],
    );

    if (res.isNotEmpty) {
      return res.first['id'] as int;
    }

    return await db.insert('domains', {
      'name': trimmed,
      'is_custom': isCustom ? 1 : 0,
    });
  }

  Future<int> getOrCreateSubdomain(int domainId, String name) async {
    final db = await instance.database;
    final trimmed = name.trim();
    final res = await db.query(
      'subdomains',
      columns: ['id'],
      where: 'domain_id = ? AND LOWER(name) = ?',
      whereArgs: [domainId, trimmed.toLowerCase()],
    );

    if (res.isNotEmpty) {
      return res.first['id'] as int;
    }

    return await db.insert('subdomains', {
      'domain_id': domainId,
      'name': trimmed,
    });
  }

  Future<List<DomainModel>> getAllDomainsWithCounts() async {
    final db = await instance.database;
    final query = '''
      SELECT 
        d.id, d.name, d.icon, d.color, d.is_custom,
        COUNT(doc.id) as doc_count
      FROM domains d
      LEFT JOIN documents doc ON d.id = doc.domain_id AND doc.is_excluded = 0
      GROUP BY d.id
      ORDER BY doc_count DESC, d.name ASC
    ''';
    final result = await db.rawQuery(query);
    return result.map((row) => DomainModel.fromMap(row, docCount: row['doc_count'] as int? ?? 0)).toList();
  }

  Future<List<SubdomainModel>> getSubdomainsForDomain(int domainId) async {
    final db = await instance.database;
    final query = '''
      SELECT 
        s.id, s.domain_id, s.name,
        COUNT(doc.id) as doc_count
      FROM subdomains s
      LEFT JOIN documents doc ON s.id = doc.subdomain_id AND doc.is_excluded = 0
      WHERE s.domain_id = ?
      GROUP BY s.id
      ORDER BY doc_count DESC, s.name ASC
    ''';
    final result = await db.rawQuery(query, [domainId]);
    return result.map((row) => SubdomainModel.fromMap(row, docCount: row['doc_count'] as int? ?? 0)).toList();
  }

  // ==================== GESTION DES DOCUMENTS ====================

  Future<DocumentModel?> getDocumentByHash(String hash) async {
    final db = await instance.database;
    final res = await db.rawQuery('''
      SELECT doc.*, d.name as domain_name, s.name as subdomain_name
      FROM documents doc
      LEFT JOIN domains d ON doc.domain_id = d.id
      LEFT JOIN subdomains s ON doc.subdomain_id = s.id
      WHERE doc.file_hash = ?
    ''', [hash]);

    if (res.isEmpty) return null;
    return DocumentModel.fromMap(res.first);
  }

  Future<DocumentModel?> getDocumentByPath(String path) async {
    final db = await instance.database;
    final res = await db.rawQuery('''
      SELECT doc.*, d.name as domain_name, s.name as subdomain_name
      FROM documents doc
      LEFT JOIN domains d ON doc.domain_id = d.id
      LEFT JOIN subdomains s ON doc.subdomain_id = s.id
      WHERE doc.file_path = ?
    ''', [path]);

    if (res.isEmpty) return null;
    return DocumentModel.fromMap(res.first);
  }

  Future<int> insertDocument(DocumentModel doc) async {
    final db = await instance.database;
    final id = await db.insert(
      'documents',
      doc.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _indexDocumentFts(db, id, doc);
    return id;
  }

  Future<int> updateDocument(DocumentModel doc) async {
    final db = await instance.database;
    final count = await db.update(
      'documents',
      doc.toMap(),
      where: 'id = ?',
      whereArgs: [doc.id],
    );

    if (doc.id != null) {
      await _indexDocumentFts(db, doc.id!, doc);
    }
    return count;
  }

  Future<void> _indexDocumentFts(Database db, int documentId, DocumentModel doc) async {
    // Supprimer l'ancien index FTS pour ce document
    await db.delete('documents_fts', where: 'document_id = ?', whereArgs: [documentId]);

    // Récupérer les noms de domaine/sous-domaine si pas déjà dans l'objet
    String domainName = doc.domainName ?? '';
    String subdomainName = doc.subdomainName ?? '';

    if (domainName.isEmpty && doc.domainId != null) {
      final d = await db.query('domains', columns: ['name'], where: 'id = ?', whereArgs: [doc.domainId]);
      if (d.isNotEmpty) domainName = d.first['name'] as String;
    }
    if (subdomainName.isEmpty && doc.subdomainId != null) {
      final s = await db.query('subdomains', columns: ['name'], where: 'id = ?', whereArgs: [doc.subdomainId]);
      if (s.isNotEmpty) subdomainName = s.first['name'] as String;
    }

    // Insérer dans FTS5
    await db.insert('documents_fts', {
      'document_id': documentId,
      'file_name': doc.fileName,
      'summary': doc.summary ?? '',
      'keywords': doc.keywords.join(' '),
      'domain_name': domainName,
      'subdomain_name': subdomainName,
    });
  }

  Future<List<DocumentModel>> getDocumentsForDomain(int domainId, {int? subdomainId}) async {
    final db = await instance.database;
    String query = '''
      SELECT doc.*, d.name as domain_name, s.name as subdomain_name
      FROM documents doc
      LEFT JOIN domains d ON doc.domain_id = d.id
      LEFT JOIN subdomains s ON doc.subdomain_id = s.id
      WHERE doc.domain_id = ? AND doc.is_excluded = 0
    ''';
    List<dynamic> args = [domainId];

    if (subdomainId != null) {
      query += ' AND doc.subdomain_id = ?';
      args.add(subdomainId);
    }

    query += ' ORDER BY doc.file_name ASC';
    final result = await db.rawQuery(query, args);
    return result.map((m) => DocumentModel.fromMap(m)).toList();
  }

  Future<List<DocumentModel>> getFavoriteDocuments() async {
    final db = await instance.database;
    final res = await db.rawQuery('''
      SELECT doc.*, d.name as domain_name, s.name as subdomain_name
      FROM documents doc
      LEFT JOIN domains d ON doc.domain_id = d.id
      LEFT JOIN subdomains s ON doc.subdomain_id = s.id
      WHERE doc.is_favorite = 1 AND doc.is_excluded = 0
      ORDER BY doc.modified_date DESC
    ''');
    return res.map((m) => DocumentModel.fromMap(m)).toList();
  }

  Future<List<DocumentModel>> getRecentDocuments({int limit = 20}) async {
    final db = await instance.database;
    final res = await db.rawQuery('''
      SELECT doc.*, d.name as domain_name, s.name as subdomain_name
      FROM documents doc
      LEFT JOIN domains d ON doc.domain_id = d.id
      LEFT JOIN subdomains s ON doc.subdomain_id = s.id
      WHERE doc.is_excluded = 0
      ORDER BY COALESCE(doc.last_opened_at, doc.created_at) DESC
      LIMIT ?
    ''', [limit]);
    return res.map((m) => DocumentModel.fromMap(m)).toList();
  }

  Future<void> toggleFavorite(int docId, bool isFavorite) async {
    final db = await instance.database;
    await db.update(
      'documents',
      {'is_favorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [docId],
    );
  }

  Future<void> toggleExclude(int docId, bool isExcluded) async {
    final db = await instance.database;
    await db.update(
      'documents',
      {
        'is_excluded': isExcluded ? 1 : 0,
        if (isExcluded) 'ai_status': 'excluded',
      },
      where: 'id = ?',
      whereArgs: [docId],
    );
  }

  Future<void> recordDocumentOpened(int docId) async {
    final db = await instance.database;
    await db.update(
      'documents',
      {'last_opened_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [docId],
    );
  }

  // ==================== RECHERCHE INTELLIGENTE FTS5 ====================

  Future<List<DocumentModel>> searchDocuments({
    required String query,
    int? domainId,
    String? level,
    String? language,
    bool favoritesOnly = false,
  }) async {
    final db = await instance.database;
    final cleanQuery = query.trim();

    List<dynamic> args = [];
    String sql;

    if (cleanQuery.isEmpty) {
      sql = '''
        SELECT doc.*, d.name as domain_name, s.name as subdomain_name
        FROM documents doc
        LEFT JOIN domains d ON doc.domain_id = d.id
        LEFT JOIN subdomains s ON doc.subdomain_id = s.id
        WHERE doc.is_excluded = 0
      ''';
    } else {
      // Nettoyage pour FTS5
      final ftsQuery = cleanQuery.replaceAll('"', '""');
      sql = '''
        SELECT doc.*, d.name as domain_name, s.name as subdomain_name
        FROM documents_fts fts
        JOIN documents doc ON fts.document_id = doc.id
        LEFT JOIN domains d ON doc.domain_id = d.id
        LEFT JOIN subdomains s ON doc.subdomain_id = s.id
        WHERE documents_fts MATCH ? AND doc.is_excluded = 0
      ''';
      args.add('"$ftsQuery"*');
    }

    if (domainId != null) {
      sql += ' AND doc.domain_id = ?';
      args.add(domainId);
    }
    if (level != null && level.isNotEmpty) {
      sql += ' AND doc.level = ?';
      args.add(level);
    }
    if (language != null && language.isNotEmpty) {
      sql += ' AND doc.language = ?';
      args.add(language);
    }
    if (favoritesOnly) {
      sql += ' AND doc.is_favorite = 1';
    }

    sql += ' ORDER BY doc.modified_date DESC LIMIT 50';

    final result = await db.rawQuery(sql, args);
    return result.map((m) => DocumentModel.fromMap(m)).toList();
  }

  // ==================== STATISTIQUES GLOBALES ====================

  Future<Map<String, dynamic>> getLibraryStats() async {
    final db = await instance.database;
    final totalDocsRes = await db.rawQuery('SELECT COUNT(*) as count, SUM(file_size) as total_size FROM documents WHERE is_excluded = 0');
    final analyzedDocsRes = await db.rawQuery("SELECT COUNT(*) as count FROM documents WHERE ai_status = 'analyzed' AND is_excluded = 0");
    final totalDomainsRes = await db.rawQuery('SELECT COUNT(DISTINCT domain_id) as count FROM documents WHERE is_excluded = 0 AND domain_id IS NOT NULL');
    final totalFavoritesRes = await db.rawQuery('SELECT COUNT(*) as count FROM documents WHERE is_favorite = 1 AND is_excluded = 0');

    return {
      'totalDocs': totalDocsRes.first['count'] as int? ?? 0,
      'totalSize': totalDocsRes.first['total_size'] as int? ?? 0,
      'totalAnalyzed': analyzedDocsRes.first['count'] as int? ?? 0,
      'totalDomains': totalDomainsRes.first['count'] as int? ?? 0,
      'totalFavorites': totalFavoritesRes.first['count'] as int? ?? 0,
    };
  }

  Future<void> deleteDocument(int docId) async {
    final db = await instance.database;
    await db.delete('documents', where: 'id = ?', whereArgs: [docId]);
    await db.delete('documents_fts', where: 'document_id = ?', whereArgs: [docId]);
  }
}
