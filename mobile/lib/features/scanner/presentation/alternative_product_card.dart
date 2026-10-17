import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/alternative_product.dart';

class AlternativeProductCard extends StatelessWidget {
  const AlternativeProductCard({required this.product, super.key});

  final AlternativeProduct product;

  @override
  Widget build(BuildContext context) {
    String valueFor(String nutrient) {
      final value = product.nutritionPer100g[nutrient];
      return value == null ? '—' : _format(value);
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 112,
                height: 132,
                child: Image.network(
                  product.imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const ColoredBox(
                    color: AppTheme.sage,
                    child: Icon(
                      Icons.inventory_2_outlined,
                      size: 40,
                      color: AppTheme.green,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.productName,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (product.brand case final brand?
                          when brand.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          brand,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 10),
                      Text(
                        '${valueFor('energy_kcal')} kcal / 100 g',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                _MacroValue(label: 'Protein', value: valueFor('protein_g')),
                _MacroValue(
                  label: 'Carbs',
                  value: valueFor('carbohydrates_g'),
                ),
                _MacroValue(label: 'Fat', value: valueFor('fat_g')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
            child: Text(
              'Per 100 g · Open Food Facts data. Check the package label; '
              'product information may be incomplete or outdated.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  String _format(String value) {
    final number = num.tryParse(value);
    if (number == null) return value;
    return number % 1 == 0 ? number.toInt().toString() : number.toStringAsFixed(1);
  }
}

class _MacroValue extends StatelessWidget {
  const _MacroValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text('$label $value g');
  }
}
