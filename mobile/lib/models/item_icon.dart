/// Bundled artwork shared by automatic matching and the item icon library.
class ItemIcon {
  const ItemIcon(this.id, this.label, this.keywords);

  final String id;
  final String label;
  final List<String> keywords;
  String get asset => 'assets/icons/inventory/$id.png';

  static const defaultAsset = 'assets/icons/inventory/default_item.png';
  static const library = [
    ItemIcon('apple', 'Apple', ['apple', 'apples', '苹果']),
    ItemIcon('avocado', 'Avocado', ['avocado', 'avocados', '牛油果']),
    ItemIcon('bacon', 'Bacon', ['bacon', '培根']),
    ItemIcon('banana', 'Banana', ['banana', 'bananas', '香蕉']),
    ItemIcon('basa_fillet', 'Basa', ['basa', '巴沙鱼']),
    ItemIcon('beef_tenderloin', 'Beef', ['beef', '牛肉']),
    ItemIcon('bell_pepper', 'Bell pepper', [
      'bell pepper',
      'peppers',
      'capsicum',
      '彩椒',
    ]),
    ItemIcon('broccoli', 'Broccoli', ['broccoli', '西兰花']),
    ItemIcon('button_mushroom', 'Mushroom', ['mushroom', 'mushrooms', '蘑菇']),
    ItemIcon('carrot', 'Carrot', ['carrot', 'carrots', '胡萝卜']),
    ItemIcon('cheese', 'Cheese', ['cheese', '奶酪', '芝士']),
    ItemIcon('chicken_breast', 'Chicken breast', ['chicken breast', '鸡胸']),
    ItemIcon('chicken_drumstick', 'Chicken thigh', [
      'chicken thigh',
      'chicken drumstick',
      'chicken',
      '鸡腿',
      '鸡肉',
    ]),
    ItemIcon('crab', 'Crab', ['crab', 'crabs', '螃蟹']),
    ItemIcon('cucumber', 'Cucumber', ['cucumber', 'cucumbers', '黄瓜']),
    ItemIcon('eggplant', 'Eggplant', [
      'eggplant',
      'eggplants',
      'aubergine',
      '茄子',
    ]),
    ItemIcon('eggs', 'Eggs', [
      'egg',
      'eggs',
      'chicken egg',
      'chicken eggs',
      '鸡蛋',
    ]),
    ItemIcon('lamb_chop', 'Lamb', ['lamb', '羊肉']),
    ItemIcon('lemon', 'Lemon', ['lemon', 'lemons', '柠檬']),
    ItemIcon('lettuce', 'Lettuce', ['lettuce', '生菜']),
    ItemIcon('milk', 'Milk', ['milk', '牛奶']),
    ItemIcon('onion', 'Onion', ['onion', 'onions', '洋葱']),
    ItemIcon('orange', 'Orange', ['orange', 'oranges', '橙子']),
    ItemIcon('pork_chop', 'Pork', ['pork', '猪肉']),
    ItemIcon('potato', 'Potato', ['potato', 'potatoes', '土豆', '马铃薯']),
    ItemIcon('salmon_fillet', 'Salmon', ['salmon', '三文鱼']),
    ItemIcon('shrimp', 'Shrimp', ['shrimp', 'shrimps', 'prawn', 'prawns', '虾']),
    ItemIcon('spinach', 'Spinach', ['spinach', '菠菜']),
    ItemIcon('strawberry', 'Strawberry', ['strawberry', 'strawberries', '草莓']),
    ItemIcon('tomato', 'Tomato', ['tomato', 'tomatoes', '番茄', '西红柿']),
    ItemIcon('tuna_steak', 'Tuna', ['tuna', '金枪鱼']),
    ItemIcon('yogurt', 'Yogurt', ['yogurt', 'yoghurt', '酸奶']),
  ];

  static String forName(String value) {
    final name = value.trim().toLowerCase();
    // Match whole English words, and prefer the most specific phrase.
    // "Pineapple" must not match "apple", nor "eggplant" match "egg".
    ItemIcon? match;
    var longest = 0;
    for (final icon in library) {
      for (final keyword in icon.keywords) {
        final found = RegExp(r'^[a-z ]+$').hasMatch(keyword)
            ? RegExp(
                '(^|[^a-z])${RegExp.escape(keyword)}(?=\$|[^a-z])',
              ).hasMatch(name)
            : name.contains(keyword);
        if (found && keyword.length > longest) {
          match = icon;
          longest = keyword.length;
        }
      }
    }
    return match?.asset ?? defaultAsset;
  }

  static bool isValidAsset(String? asset) =>
      asset == defaultAsset || library.any((icon) => icon.asset == asset);
}
