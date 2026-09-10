import 'dart:convert';
import 'package:intl/intl.dart';

class DocumentModel {
  final int? id;
  final String filePath;
  final String fileName;
  final String fileHash;
  final int fileSize;
  final int pageCount;
  final int modifiedDate; // Millisecondes depuis l'époque Unix
  final int? domainId;
  final int? subdomainId;
  final String? domainName;
  final String? subdomainName;
  final String? summary;
  final List<String> keywords;
  final String? language;
  final String? level; // débutant, intermédiaire, avancé, recherche
  final bool isFavorite;
  final bool isExcluded;
  final String aiStatus; // 'pending', 'analyzed', 'failed', 'excluded'
  final int createdAt;
  final int? lastOpenedAt;

  DocumentModel({
    this.id,
    required this.filePath,
    required this.fileName,
    required this.fileHash,
    required this.fileSize,
    this.pageCount = 0,
    required this.modifiedDate,
    this.domainId,
    this.subdomainId,
    this.domainName,
    this.subdomainName,
    this.summary,
    this.keywords = const [],
    this.language,
    this.level,
    this.isFavorite = false,
    this.isExcluded = false,
    this.aiStatus = 'pending',
    required this.createdAt,
    this.lastOpenedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'file_path': filePath,
      'file_name': fileName,
      'file_hash': fileHash,
      'file_size': fileSize,
      'page_count': pageCount,
      'modified_date': modifiedDate,
      'domain_id': domainId,
      'subdomain_id': subdomainId,
      'summary': summary,
      'keywords': jsonEncode(keywords),
      'language': language,
      'level': level,
      'is_favorite': isFavorite ? 1 : 0,
      'is_excluded': isExcluded ? 1 : 0,
      'ai_status': aiStatus,
      'created_at': createdAt,
      'last_opened_at': lastOpenedAt,
    };
  }

  factory DocumentModel.fromMap(Map<String, dynamic> map) {
    List<String> parsedKeywords = [];
    if (map['keywords'] != null && (map['keywords'] as String).isNotEmpty) {
      try {
        final decoded = jsonDecode(map['keywords'] as String);
        if (decoded is List) {
          parsedKeywords = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }

    return DocumentModel(
      id: map['id'] as int?,
      filePath: map['file_path'] as String,
      fileName: map['file_name'] as String,
      fileHash: map['file_hash'] as String,
      fileSize: map['file_size'] as int,
      pageCount: (map['page_count'] as int?) ?? 0,
      modifiedDate: map['modified_date'] as int,
      domainId: map['domain_id'] as int?,
      subdomainId: map['subdomain_id'] as int?,
      domainName: map['domain_name'] as String?,
      subdomainName: map['subdomain_name'] as String?,
      summary: map['summary'] as String?,
      keywords: parsedKeywords,
      language: map['language'] as String?,
      level: map['level'] as String?,
      isFavorite: (map['is_favorite'] as int? ?? 0) == 1,
      isExcluded: (map['is_excluded'] as int? ?? 0) == 1,
      aiStatus: (map['ai_status'] as String?) ?? 'pending',
      createdAt: map['created_at'] as int,
      lastOpenedAt: map['last_opened_at'] as int?,
    );
  }

  String get formattedFileSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} Ko';
    }
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }

  String get formattedModifiedDate {
    final date = DateTime.fromMillisecondsSinceEpoch(modifiedDate);
    return DateFormat('dd/MM/yyyy HH:mm').format(date);
  }

  DocumentModel copyWith({
    int? id,
    String? filePath,
    String? fileName,
    String? fileHash,
    int? fileSize,
    int? pageCount,
    int? modifiedDate,
    int? domainId,
    int? subdomainId,
    String? domainName,
    String? subdomainName,
    String? summary,
    List<String>? keywords,
    String? language,
    String? level,
    bool? isFavorite,
    bool? isExcluded,
    String? aiStatus,
    int? createdAt,
    int? lastOpenedAt,
  }) {
    return DocumentModel(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      fileHash: fileHash ?? this.fileHash,
      fileSize: fileSize ?? this.fileSize,
      pageCount: pageCount ?? this.pageCount,
      modifiedDate: modifiedDate ?? this.modifiedDate,
      domainId: domainId ?? this.domainId,
      subdomainId: subdomainId ?? this.subdomainId,
      domainName: domainName ?? this.domainName,
      subdomainName: subdomainName ?? this.subdomainName,
      summary: summary ?? this.summary,
      keywords: keywords ?? this.keywords,
      language: language ?? this.language,
      level: level ?? this.level,
      isFavorite: isFavorite ?? this.isFavorite,
      isExcluded: isExcluded ?? this.isExcluded,
      aiStatus: aiStatus ?? this.aiStatus,
      createdAt: createdAt ?? this.createdAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    );
  }
}
