"""Public category seed and Agent guidance; no database writes at import time."""
import hashlib
import json

from app.core.catalog import normalize_catalog_name


# Classification follows product identity, not packaging or storage temperature.
_ROWS = [
    ("Vegetables & Mushrooms", "Vegetables, mushrooms and plain preserved vegetables.", ["carrot / 胡萝卜", "canned tomatoes", "frozen peas"], "Exclude tomato sauce, prepared meals and dried legumes."),
    ("Fruit", "Whole, cut, dried or plain preserved fruit.", ["apple / 苹果", "frozen berries", "raisins"], "Exclude juice, jam and fruit desserts."),
    ("Fresh Herbs", "Fresh culinary herbs.", ["coriander / 香菜", "fresh basil"], "Dried herbs belong to Dried Herbs & Spices."),
    ("Meat & Poultry", "Raw meat and poultry, including frozen or marinated cuts.", ["chicken breast / 鸡胸肉", "beef steak"], "Exclude sausages, cured meats and prepared meals."),
    ("Fish & Seafood", "Fish and seafood, including plain canned, smoked or frozen products.", ["salmon / 三文鱼", "canned tuna", "prawns"], "Exclude complete prepared meals and seafood sauces."),
    ("Eggs", "Shell eggs and liquid egg products.", ["chicken eggs / 鸡蛋", "egg whites"], "Exclude egg dishes and mayonnaise."),
    ("Processed & Deli Meats", "Processed, cured and deli meat products.", ["ham / 火腿", "bacon", "sausages"], "Exclude raw meat cuts, seafood and complete meals."),
    ("Milk & Plant-Based Milk", "Dairy milk and plant-based drinks intended as milk substitutes.", ["Anchor milk", "oat milk / 燕麦奶", "drinking coconut milk"], "Cooking coconut milk belongs to Sauces, Condiments & Spreads; ask intended use if unclear."),
    ("Yoghurt", "Dairy and plant-based yoghurt.", ["Greek yoghurt / 希腊酸奶", "coconut yoghurt"], "Exclude milk drinks, ice cream and frozen yoghurt."),
    ("Cheese", "Dairy and plant-based cheese.", ["cheddar / 切达奶酪", "vegan cheese"], "Exclude butter, cream and cheese sauces."),
    ("Butter & Cream", "Butter, margarine and dairy or plant-based cream.", ["butter / 黄油", "whipping cream", "margarine"], "Exclude cooking oils and cooking coconut milk."),
    ("Tofu & Meat Alternatives", "Tofu, tempeh and plant-based meat substitutes.", ["tofu / 豆腐", "vegan mince"], "Exclude plant milk, cheese, dried legumes and complete meals."),
    ("Rice, Pasta & Grains", "Unprepared rice, noodles, pasta, grains and breakfast cereals.", ["rice / 大米", "spaghetti", "oats"], "Exclude bread, flour, filled dumplings and complete meals."),
    ("Bread & Bakery", "Baked bread, wraps, buns and pastries.", ["toast bread / 吐司", "croissant", "tortilla"], "Exclude baking ingredients, biscuits and packaged cakes or desserts."),
    ("Dried Legumes, Nuts & Seeds", "Dried pulses, plain preserved beans, nuts and edible seeds.", ["lentils / 小扁豆", "canned chickpeas", "almonds"], "Exclude fresh green beans, tofu, nut spreads and confectionery-coated nuts."),
    ("Baking Ingredients", "Ingredients primarily used for baking.", ["flour / 面粉", "sugar", "yeast", "baking cocoa"], "Eggs, milk, butter and oils retain their own categories."),
    ("Sauces, Condiments & Spreads", "Sauces, stocks, condiments, jams and spreads; coconut milk for cooking.", ["Lao Gan Ma / 老干妈", "tomato sauce", "peanut butter", "cooking coconut milk"], "Exclude plain vegetables, oils, vinegar and dry spice powders."),
    ("Oils & Vinegars", "Edible oils and culinary vinegars.", ["olive oil / 橄榄油", "rice vinegar"], "Exclude butter and prepared salad dressings."),
    ("Dried Herbs & Spices", "Dried herbs, spices, salt and dry seasoning blends.", ["cumin / 孜然", "dried basil", "salt"], "Exclude fresh herbs, sugar and liquid sauces."),
    ("Prepared Meals & Leftovers", "Prepared dishes, soups, meal kits and leftovers; includes filled dumplings and pizza.", ["frozen pizza / 冷冻披萨", "leftover curry", "dumplings"], "Plain single ingredients retain their own category regardless of storage."),
    ("Snacks & Desserts", "Snack foods, confectionery and non-frozen desserts.", ["chips / 薯片", "biscuits", "chocolate", "cake"], "Exclude plain nuts, fruit, yoghurt, pastries and frozen desserts."),
    ("Ice Cream & Frozen Desserts", "Ice cream, frozen yoghurt, sorbet and ice pops.", ["ice cream / 冰淇淋", "sorbet"], "Other frozen foods retain their product category."),
    ("Drinks, Tea & Coffee", "Water, juice, soft drinks, alcohol, tea and coffee.", ["coffee / 咖啡", "orange juice", "beer"], "Milk and plant-based milk drinks retain their own category."),
    ("Household Supplies", "Non-food household consumables.", ["dish soap / 洗洁精", "paper towels", "shampoo"], "Do not classify human food here; ask about unrecognized products."),
    ("Other", "No suitable catalog category after clarification; requires user confirmation.", ["an identified product outside the listed categories"], "Never silently use Other for unreadable names or uncertain product identity."),
]

CATEGORIES = tuple(
    {"name": name, "normalized_name": normalize_catalog_name(name), "sort_order": index * 10,
     "description": description, "examples": examples, "exclusions": exclusions}
    for index, (name, description, examples, exclusions) in enumerate(_ROWS, 1)
)
_GUIDANCE = {row["normalized_name"]: row for row in CATEGORIES}


def category_seed_version(rows=CATEGORIES) -> str:
    """Return a stable, content-addressed version for category seed evidence."""

    payload = [
        {
            "name": row["name"],
            "normalized_name": row["normalized_name"],
            "sort_order": row["sort_order"],
        }
        for row in rows
    ]
    encoded = json.dumps(
        payload,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    return "sha256:" + hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def category_guidance(name: str) -> dict:
    row = _GUIDANCE.get(normalize_catalog_name(name))
    return ({key: row[key] for key in ("description", "examples", "exclusions")} if row else
            {"description": "No maintained guidance; clarify the category meaning if needed.",
             "examples": [], "exclusions": "Do not infer rules from an unfamiliar name."})
