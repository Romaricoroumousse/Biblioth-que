class DomainModel {
  final int? id;
  final String name;
  final String? icon;
  final String? color;
  final bool isCustom;
  final int documentCount;

  DomainModel({
    this.id,
    required this.name,
    this.icon,
    this.color,
    this.isCustom = false,
    this.documentCount = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'icon': icon,
      'color': color,
      'is_custom': isCustom ? 1 : 0,
    };
  }

  factory DomainModel.fromMap(Map<String, dynamic> map, {int docCount = 0}) {
    return DomainModel(
      id: map['id'] as int?,
      name: map['name'] as String,
      icon: map['icon'] as String?,
      color: map['color'] as String?,
      isCustom: (map['is_custom'] as int? ?? 0) == 1,
      documentCount: docCount,
    );
  }

  DomainModel copyWith({
    int? id,
    String? name,
    String? icon,
    String? color,
    bool? isCustom,
    int? documentCount,
  }) {
    return DomainModel(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      isCustom: isCustom ?? this.isCustom,
      documentCount: documentCount ?? this.documentCount,
    );
  }
}

class SubdomainModel {
  final int? id;
  final int domainId;
  final String name;
  final int documentCount;

  SubdomainModel({
    this.id,
    required this.domainId,
    required this.name,
    this.documentCount = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'domain_id': domainId,
      'name': name,
    };
  }

  factory SubdomainModel.fromMap(Map<String, dynamic> map, {int docCount = 0}) {
    return SubdomainModel(
      id: map['id'] as int?,
      domainId: map['domain_id'] as int,
      name: map['name'] as String,
      documentCount: docCount,
    );
  }
}
