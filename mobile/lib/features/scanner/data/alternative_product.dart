class AlternativeProduct {
  const AlternativeProduct({
    required this.productName,
    required this.imageUrl,
    required this.nutritionPer100g,
    this.brand,
    this.productUrl,
  });

  final String productName;
  final String? brand;
  final String imageUrl;
  final String? productUrl;
  final Map<String, String> nutritionPer100g;

  factory AlternativeProduct.fromJson(Map<String, dynamic> json) {
    final nutrition = json['nutrition_per_100g'] as Map<String, dynamic>;
    return AlternativeProduct(
      productName: json['product_name'] as String,
      brand: json['brand'] as String?,
      imageUrl: json['image_url'] as String,
      productUrl: json['product_url'] as String?,
      nutritionPer100g: nutrition.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
    );
  }
}
