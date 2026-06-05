class Equipment {
  final int id;
  final int companyId;
  final String code;
  final String name;
  final String? location;
  final String? brand;
  final String? model;

  Equipment({
    required this.id,
    required this.companyId,
    required this.code,
    required this.name,
    this.location,
    this.brand,
    this.model,
  });

  /// Crea un objeto `Equipment` a partir de JSON recibido del backend.
  factory Equipment.fromJson(Map<String, dynamic> json) {
    return Equipment(
      id: json['id'] as int,
      companyId: json['company_id'] is int
          ? json['company_id'] as int
          : int.tryParse(json['company_id']?.toString() ?? '') ?? 0,
      code: json['code'] as String,
      name: json['name'] as String,
      location: json['location'] as String?,
      brand: json['brand'] as String?,
      model: json['model'] as String?,
    );
  }
}
