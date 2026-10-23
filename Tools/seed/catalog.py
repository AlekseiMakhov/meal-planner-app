# The starting product base: what each product is called, where it sits in the shop, where its
# nutrition comes from and how its units convert. Tools/seed/build.py turns it into the app's seed.
#
# Nutrition sources:
#   usda(fdc)                — USDA FoodData Central, SR Legacy (public domain): values taken as published.
#   label(kcal, p, f, c)     — typical values printed on Russian packages (GOST products, common brands).
#   reference(kcal, p, f, c) — reference tables, for products with neither a USDA entry nor a label.
# Pieces and named units are grams of the edible part: an egg without its shell, a can drained.
# Spoons and cups follow USDA's level measures; the build derives density from them.

AISLES = [
    ("vegetables", "Овощи и зелень"),
    ("fruits", "Фрукты и ягоды"),
    ("bakery", "Хлеб и выпечка"),
    ("dairy", "Молочное и яйца"),
    ("cheese", "Сыры"),
    ("meat", "Мясо и птица"),
    ("deli", "Колбасы и копчёности"),
    ("fish", "Рыба и морепродукты"),
    ("grains", "Крупы, макароны и бобовые"),
    ("baking", "Мука, сахар и всё для выпечки"),
    ("sauces", "Масла, соусы и уксус"),
    ("spices", "Специи и приправы"),
    ("canned", "Консервы"),
    ("nuts", "Орехи, семена и сухофрукты"),
    ("frozen", "Замороженные продукты"),
    ("sweets", "Сладости"),
    ("drinks", "Напитки"),
    ("other", "Прочее"),
]


def usda(fdc, energy=None):
    return {"kind": "usda", "fdc": fdc, "energy": energy}


def label(kcal, protein, fat, carbs):
    return {"kind": "label", "values": (kcal, protein, fat, carbs)}


def reference(kcal, protein, fat, carbs):
    return {"kind": "reference", "values": (kcal, protein, fat, carbs)}


CATALOG = []


def p(key, name, aisle, source, aliases="", base="g", piece=None, units=None, density=None, staple=False):
    CATALOG.append({
        "key": key, "name": name, "aisle": aisle, "source": source,
        "aliases": [a.strip() for a in aliases.split(";") if a.strip()],
        "base": base, "piece": piece, "units": units or {}, "density": density, "staple": staple,
    })


# Овощи и зелень
p("potato", "Картофель", "vegetables", usda(170026), "картошка; картофелина", piece=150)
p("carrot", "Морковь", "vegetables", usda(170393), "морковка", piece=80)
p("onion", "Лук репчатый", "vegetables", usda(170000), "лук; луковица; репчатый лук", piece=110)
p("red-onion", "Лук красный", "vegetables", usda(170000), "красный лук; ялтинский лук", piece=110)
p("green-onion", "Лук зелёный", "vegetables", usda(170005), "зелёный лук; лук-перо", piece=15, units={"bunch": 60})
p("leek", "Лук-порей", "vegetables", usda(169246), "порей", piece=90)
p("garlic", "Чеснок", "vegetables", usda(169230), "чесночок", piece=40, units={"clove": 5, "head": 40})
p("cabbage", "Капуста белокочанная", "vegetables", usda(169975), "капуста; белокочанная капуста", base="pcs",
  piece=1500, units={"head": 1500})
p("red-cabbage", "Капуста краснокочанная", "vegetables", usda(169977), "красная капуста", base="pcs", piece=1000,
  units={"head": 1000})
p("chinese-cabbage", "Капуста пекинская", "vegetables", usda(169979), "пекинская капуста", base="pcs", piece=800,
  units={"head": 800})
p("broccoli", "Брокколи", "vegetables", usda(170379), "капуста брокколи", base="pcs", piece=350, units={"head": 350})
p("cauliflower", "Капуста цветная", "vegetables", usda(169986), "цветная капуста", base="pcs", piece=600,
  units={"head": 600})
p("brussels-sprouts", "Капуста брюссельская", "vegetables", usda(170383), "брюссельская капуста", piece=19)
p("zucchini", "Кабачок", "vegetables", usda(169291), "кабачки; цукини", piece=250)
p("eggplant", "Баклажан", "vegetables", usda(169228), "баклажаны; синенькие", piece=300)
p("pumpkin", "Тыква", "vegetables", usda(168448))
p("cucumber", "Огурец", "vegetables", usda(168409), "огурцы; огурчик", piece=120)
p("tomato", "Помидор", "vegetables", usda(170457), "помидоры; томат; томаты", piece=120)
p("cherry-tomato", "Помидоры черри", "vegetables", usda(170457), "черри; томаты черри", piece=17)
p("bell-pepper", "Перец болгарский", "vegetables", usda(170108), "болгарский перец; сладкий перец; перец сладкий",
  piece=150)
p("chili-pepper", "Перец чили", "vegetables", usda(170106), "чили; острый перец; перчик чили", piece=45)
p("beet", "Свёкла", "vegetables", usda(169145), "буряк", piece=200)
p("radish", "Редис", "vegetables", usda(169276), "редиска", piece=15)
p("daikon", "Дайкон", "vegetables", usda(168451), "редька белая", piece=340)
p("turnip", "Репа", "vegetables", usda(170465), piece=120)
p("celery", "Сельдерей черешковый", "vegetables", usda(169988), "стебель сельдерея", piece=40)
p("celeriac", "Сельдерей корневой", "vegetables", usda(170400), "корень сельдерея", piece=400)
p("spinach", "Шпинат", "vegetables", usda(168462), units={"bunch": 100})
p("lettuce", "Салат листовой", "vegetables", usda(169249), "листья салата; салат зелёный; латук",
  units={"bunch": 100, "leaf": 10})
p("iceberg", "Салат айсберг", "vegetables", usda(169248), "айсберг", base="pcs", piece=500, units={"head": 500})
p("arugula", "Руккола", "vegetables", usda(169387), "рукола", units={"bunch": 50, "leaf": 2})
p("sorrel", "Щавель", "vegetables", usda(170076), units={"bunch": 100})
p("parsley", "Петрушка", "vegetables", usda(170416), "зелень петрушки", units={"bunch": 50, "sprig": 2})
p("dill", "Укроп", "vegetables", usda(172233), "зелень укропа", units={"bunch": 50, "sprig": 2})
p("cilantro", "Кинза", "vegetables", usda(169997), "кориандр свежий; зелень кинзы", units={"bunch": 50, "sprig": 2})
p("basil", "Базилик", "vegetables", usda(172232), "базилик свежий", units={"bunch": 30, "sprig": 3, "leaf": 0.5})
p("mint", "Мята", "vegetables", usda(173475), "мята свежая; листья мяты", units={"bunch": 20, "sprig": 2, "leaf": 0.2})
p("rosemary", "Розмарин свежий", "vegetables", usda(173473), units={"sprig": 1.5})
p("thyme", "Тимьян свежий", "vegetables", usda(173470), units={"sprig": 0.5})
p("ginger", "Имбирь", "vegetables", usda(169231), "корень имбиря; имбирь свежий")
p("asparagus", "Спаржа", "vegetables", usda(168389), "спаржа зелёная", piece=16)
p("green-beans", "Фасоль стручковая", "vegetables", usda(169961), "стручковая фасоль; зелёная фасоль")
p("green-peas", "Горошек зелёный", "vegetables", usda(170419), "зелёный горошек свежий")
p("corn", "Кукуруза", "vegetables", usda(169998), "кукуруза сладкая; початок кукурузы", piece=150)
p("avocado", "Авокадо", "vegetables", usda(171705), base="pcs", piece=150)
p("champignon", "Шампиньоны", "vegetables", usda(169251), "грибы; шампиньон", piece=20)
p("oyster-mushroom", "Вешенки", "vegetables", usda(168580), "вешенка")
p("shiitake", "Шиитаке", "vegetables", usda(169242), "грибы шиитаке", piece=19)
p("chanterelle", "Лисички", "vegetables", usda(168422), "грибы лисички")
p("sweet-potato", "Батат", "vegetables", usda(168482), "сладкий картофель", piece=130)
p("fennel", "Фенхель", "vegetables", usda(169385), piece=234)
p("kale", "Кейл", "vegetables", usda(168421), "капуста кале; капуста кейл")
p("chard", "Мангольд", "vegetables", usda(169991))

# Фрукты и ягоды
p("apple", "Яблоко", "fruits", usda(171688), "яблоки", piece=180)
p("pear", "Груша", "fruits", usda(169118), "груши", piece=180)
p("banana", "Банан", "fruits", usda(173944), "бананы", piece=120)
p("orange", "Апельсин", "fruits", usda(169097), "апельсины", piece=140)
p("tangerine", "Мандарин", "fruits", usda(169105), "мандарины", piece=75)
p("lemon", "Лимон", "fruits", usda(167746), base="pcs", piece=85)
p("lime", "Лайм", "fruits", usda(168155), base="pcs", piece=67)
p("grapefruit", "Грейпфрут", "fruits", usda(174673), piece=250)
p("kiwi", "Киви", "fruits", usda(168153), piece=70)
p("grapes", "Виноград", "fruits", usda(174683))
p("pineapple", "Ананас", "fruits", usda(169124), base="pcs", piece=900)
p("mango", "Манго", "fruits", usda(169910), base="pcs", piece=200)
p("peach", "Персик", "fruits", usda(169928), "персики", piece=150)
p("nectarine", "Нектарин", "fruits", usda(169914), "нектарины", piece=140)
p("apricot", "Абрикос", "fruits", usda(171697), "абрикосы", piece=35)
p("plum", "Слива", "fruits", usda(169949), "сливы", piece=66)
p("sour-cherry", "Вишня", "fruits", usda(173954))
p("sweet-cherry", "Черешня", "fruits", usda(171719))
p("strawberry", "Клубника", "fruits", usda(167762), "земляника садовая", piece=12)
p("raspberry", "Малина", "fruits", usda(167755))
p("blueberry", "Черника", "fruits", usda(171711), "голубика")
p("blackberry", "Ежевика", "fruits", usda(173946))
p("blackcurrant", "Смородина чёрная", "fruits", usda(173963), "чёрная смородина")
p("redcurrant", "Смородина красная", "fruits", usda(173964), "красная смородина")
p("gooseberry", "Крыжовник", "fruits", usda(173030))
p("cranberry", "Клюква", "fruits", usda(171722))
p("lingonberry", "Брусника", "fruits", reference(46, 0.7, 0.5, 8.2))
p("sea-buckthorn", "Облепиха", "fruits", reference(82, 1.2, 5.4, 5.7))
p("watermelon", "Арбуз", "fruits", usda(167765))
p("melon", "Дыня", "fruits", usda(169911))
p("pomegranate", "Гранат", "fruits", usda(169134), base="pcs", piece=280)
p("persimmon", "Хурма", "fruits", usda(169941), piece=170)
p("fig", "Инжир свежий", "fruits", usda(173021), "инжир", piece=50)

# Хлеб и выпечка
p("white-bread", "Хлеб белый", "bakery", usda(174924), "батон; хлеб пшеничный; белый хлеб",
  units={"slice": 30})
p("rye-bread", "Хлеб ржаной", "bakery", usda(172684), "чёрный хлеб; ржаной хлеб", units={"slice": 32})
p("borodinsky-bread", "Хлеб бородинский", "bakery", label(208, 6.8, 1.3, 41.8), "бородинский",
  units={"slice": 30})
p("wholewheat-bread", "Хлеб цельнозерновой", "bakery", usda(172688), "цельнозерновой хлеб", units={"slice": 32})
p("lavash", "Лаваш", "bakery", usda(174915), "лаваш тонкий; лаваш армянский", piece=90)
p("tortilla", "Тортилья", "bakery", usda(167535), "пшеничная лепёшка", piece=49)
p("breadcrumbs", "Сухари панировочные", "bakery", usda(174928), "панировочные сухари; панировка")

# Молочное и яйца
p("egg", "Яйцо куриное", "dairy", usda(171287), "яйца; яиц; яйцо", base="pcs", piece=50)
p("quail-egg", "Яйцо перепелиное", "dairy", usda(172191), "перепелиные яйца", base="pcs", piece=9)
p("egg-white", "Белок яичный", "dairy", usda(172183), "яичный белок; белки", piece=33)
p("egg-yolk", "Желток яичный", "dairy", usda(172184), "яичный желток; желтки", piece=17)
p("milk-32", "Молоко 3,2%", "dairy", usda(171265), "молоко", base="ml")
p("milk-25", "Молоко 2,5%", "dairy", label(53, 2.8, 2.5, 4.7), base="ml", density=1.03)
p("milk-15", "Молоко 1,5%", "dairy", label(44, 2.8, 1.5, 4.7), base="ml", density=1.03)
p("skim-milk", "Молоко обезжиренное", "dairy", usda(171269), base="ml")
p("kefir-1", "Кефир 1%", "dairy", label(40, 3.0, 1.0, 4.0), base="ml", density=1.03)
p("kefir-25", "Кефир 2,5%", "dairy", label(53, 2.9, 2.5, 4.0), "кефир", base="ml", density=1.03)
p("kefir-32", "Кефир 3,2%", "dairy", label(59, 2.9, 3.2, 4.0), base="ml", density=1.03)
p("ryazhenka", "Ряженка 4%", "dairy", label(67, 2.8, 4.0, 4.2), "ряженка", base="ml", density=1.03)
p("yogurt", "Йогурт натуральный", "dairy", usda(171284), "йогурт; йогурт без добавок")
p("greek-yogurt", "Йогурт греческий", "dairy", usda(171304), "греческий йогурт")
p("tvorog-0", "Творог обезжиренный", "dairy", label(85, 18.0, 0.6, 1.8), "творог 0%")
p("tvorog-2", "Творог 2%", "dairy", label(103, 18.0, 2.0, 3.3))
p("tvorog-5", "Творог 5%", "dairy", label(121, 16.0, 5.0, 3.0), "творог")
p("tvorog-9", "Творог 9%", "dairy", label(159, 16.7, 9.0, 2.0))
p("cottage-cheese", "Творог зернёный", "dairy", usda(172179), "зерненый творог; зерновой творог; коттедж чиз")
p("sour-cream-10", "Сметана 10%", "dairy", label(115, 3.0, 10.0, 2.9), density=1.0)
p("sour-cream-15", "Сметана 15%", "dairy", label(160, 2.6, 15.0, 3.6), "сметана", density=1.0)
p("sour-cream-20", "Сметана 20%", "dairy", label(206, 2.5, 20.0, 3.4), density=1.0)
p("cream-10", "Сливки 10%", "dairy", label(118, 3.0, 10.0, 4.0), "сливки", base="ml", density=1.01)
p("cream-20", "Сливки 20%", "dairy", label(206, 2.8, 20.0, 3.7), base="ml", density=1.0)
p("cream-33", "Сливки 33%", "dairy", label(322, 2.2, 33.0, 3.0), "жирные сливки; сливки для взбивания",
  base="ml", density=0.99)
p("butter", "Масло сливочное", "dairy", usda(173430), "сливочное масло; масло 82,5%", units={"pack": 180})
p("ghee", "Масло топлёное", "dairy", usda(173412), "топлёное масло; гхи")
p("condensed-milk", "Молоко сгущённое", "dairy", usda(171275), "сгущёнка; сгущенное молоко", units={"can": 380})

# Сыры
p("gouda", "Сыр гауда", "cheese", usda(171241), "гауда", units={"slice": 20})
p("russian-cheese", "Сыр российский", "cheese", label(363, 23.4, 30.0, 0.0), "российский сыр; сыр твёрдый",
  units={"slice": 20})
p("cheddar", "Сыр чеддер", "cheese", usda(173414), "чеддер", units={"slice": 20})
p("emmental", "Сыр эмменталь", "cheese", usda(171251), "эмменталь; швейцарский сыр", units={"slice": 20})
p("parmesan", "Сыр пармезан", "cheese", usda(170848), "пармезан")
p("mozzarella", "Моцарелла", "cheese", usda(170845), "сыр моцарелла", piece=125)
p("feta", "Фета", "cheese", usda(173420), "сыр фета")
p("ricotta", "Рикотта", "cheese", usda(170851), "сыр рикотта")
p("mascarpone", "Маскарпоне", "cheese", label(412, 4.6, 42.0, 3.6), "сыр маскарпоне")
p("cream-cheese", "Сыр сливочный", "cheese", usda(173418), "творожный сыр; крем-чиз; сливочный сыр")
p("suluguni", "Сыр сулугуни", "cheese", label(290, 20.0, 24.0, 0.0), "сулугуни")
p("adyghe-cheese", "Сыр адыгейский", "cheese", label(205, 18.5, 14.0, 1.5), "адыгейский сыр")
p("brie", "Сыр бри", "cheese", usda(172177), "бри")
p("camembert", "Сыр камамбер", "cheese", usda(172178), "камамбер")

# Мясо и птица
p("chicken-breast", "Куриное филе", "meat", usda(171077), "куриная грудка; филе курицы; грудка куриная", piece=250)
p("chicken-thigh", "Куриное бедро без кожи", "meat", usda(173627), "куриные бёдра; филе бедра", piece=100)
p("chicken-drumstick", "Куриная голень", "meat", usda(172373), "голени куриные; куриные ножки", piece=90)
p("chicken-wing", "Куриное крыло", "meat", usda(172390), "куриные крылья; крылышки", piece=50)
p("chicken-whole", "Курица целая", "meat", usda(171447), "курица; цыплёнок; тушка курицы", piece=1500)
p("chicken-liver", "Печень куриная", "meat", usda(171060), "куриная печень; печёнка куриная")
p("chicken-heart", "Сердечки куриные", "meat", usda(171458), "куриные сердечки; сердца куриные")
p("chicken-gizzard", "Желудки куриные", "meat", usda(171456), "куриные желудки; пупки куриные")
p("ground-chicken", "Фарш куриный", "meat", usda(171116), "куриный фарш")
p("turkey-breast", "Индейка, филе грудки", "meat", usda(171098), "филе индейки; грудка индейки; индейка")
p("turkey-thigh", "Индейка, бедро", "meat", usda(174518), "бедро индейки")
p("ground-turkey", "Фарш из индейки", "meat", usda(171505), "фарш индейки")
p("beef-tenderloin", "Говядина, вырезка", "meat", usda(174762), "говяжья вырезка")
p("beef-stew", "Говядина для тушения", "meat", usda(171206), "говядина; говяжья лопатка")
p("beef-round", "Говядина, огузок", "meat", usda(171816), "огузок; говядина постная")
p("ground-beef", "Фарш говяжий", "meat", usda(171796), "говяжий фарш")
p("beef-liver", "Печень говяжья", "meat", usda(169451), "говяжья печень")
p("beef-tongue", "Язык говяжий", "meat", usda(170196), "говяжий язык")
p("beef-heart", "Сердце говяжье", "meat", usda(168625))
p("pork-loin", "Свинина, корейка", "meat", usda(167818), "корейка; свиная корейка; карбонад")
p("pork-tenderloin", "Свинина, вырезка", "meat", usda(168249), "свиная вырезка")
p("pork-shoulder", "Свинина, лопатка", "meat", usda(167843), "свиная лопатка; свинина")
p("ground-pork", "Фарш свиной", "meat", usda(168372), "свиной фарш")
p("pork-liver", "Печень свиная", "meat", usda(167862))
p("lamb-leg", "Баранина, нога", "meat", usda(174315), "баранина; баранья нога")
p("lamb-shoulder", "Баранина, лопатка", "meat", usda(172500), "баранья лопатка")
p("ground-lamb", "Фарш бараний", "meat", usda(174370), "бараний фарш")
p("veal", "Телятина", "meat", usda(173815))
p("duck", "Утка", "meat", usda(172408), "мясо утки")
p("rabbit", "Кролик", "meat", usda(172521), "крольчатина; мясо кролика")

# Колбасы и копчёности
p("doktorskaya", "Колбаса докторская", "deli", label(257, 12.8, 22.2, 1.5), "докторская колбаса; варёная колбаса",
  units={"slice": 20})
p("salami", "Колбаса сырокопчёная", "deli", usda(174582), "салями; сырокопчёная колбаса", units={"slice": 10})
p("frankfurters", "Сосиски", "deli", label(266, 11.0, 23.9, 1.6), "сосиски молочные; сосиска", piece=50)
p("ham", "Ветчина", "deli", usda(173864), units={"slice": 20})
p("bacon", "Бекон", "deli", usda(168277), units={"slice": 15})
p("pepperoni", "Пепперони", "deli", usda(174575))

# Рыба и морепродукты
p("salmon", "Сёмга", "fish", usda(175167), "лосось; лосось атлантический")
p("pink-salmon", "Горбуша", "fish", usda(175138))
p("chum-salmon", "Кета", "fish", usda(173689))
p("trout", "Форель", "fish", usda(173717), "форель радужная")
p("cod", "Треска", "fish", usda(171955), "филе трески")
p("pollock", "Минтай", "fish", usda(173725), "филе минтая")
p("haddock", "Пикша", "fish", usda(171964))
p("hake", "Хек", "fish", usda(173713), "мерлуза")
p("tilapia", "Тилапия", "fish", usda(175176))
p("sea-bass", "Сибас", "fish", usda(175142), "лаврак")
p("flounder", "Камбала", "fish", usda(174196))
p("mackerel", "Скумбрия", "fish", usda(175119))
p("herring", "Сельдь", "fish", usda(175116), "селёдка")
p("pickled-herring", "Сельдь маринованная", "fish", usda(175118), "селёдка маринованная")
p("tuna", "Тунец", "fish", usda(175159), "стейк тунца")
p("carp", "Карп", "fish", usda(171952))
p("pike", "Щука", "fish", usda(173680))
p("perch", "Окунь", "fish", usda(173678))
p("shrimp", "Креветки", "fish", usda(175179), "креветка")
p("squid", "Кальмар", "fish", usda(174223), "кальмары")
p("mussels", "Мидии", "fish", usda(174216))
p("crab-sticks", "Крабовые палочки", "fish", usda(174203), "крабовое мясо; сурими", piece=17)
p("red-caviar", "Икра красная", "fish", usda(174188), "красная икра; икра лососевая")

# Крупы, макароны и бобовые
p("buckwheat", "Гречка", "grains", usda(170685), "гречневая крупа; греча; ядрица")
p("rice", "Рис длиннозёрный", "grains", usda(168877), "рис; басмати; жасмин")
p("round-rice", "Рис круглозёрный", "grains", usda(168931), "рис для суши; круглый рис")
p("brown-rice", "Рис бурый", "grains", usda(169703), "бурый рис; коричневый рис")
p("wild-rice", "Рис дикий", "grains", usda(169726), "дикий рис")
p("oats", "Овсяные хлопья", "grains", usda(173904), "овсянка; геркулес")
p("semolina", "Манная крупа", "grains", usda(169715), "манка")
p("millet", "Пшено", "grains", usda(169702), "пшённая крупа")
p("pearl-barley", "Перловка", "grains", usda(170284), "перловая крупа")
p("bulgur", "Булгур", "grains", usda(170688))
p("couscous", "Кускус", "grains", usda(169699))
p("quinoa", "Киноа", "grains", usda(168874))
p("red-lentils", "Чечевица красная", "grains", usda(174284), "красная чечевица")
p("green-lentils", "Чечевица зелёная", "grains", usda(172420), "чечевица; зелёная чечевица")
p("chickpeas", "Нут", "grains", usda(173756), "турецкий горох")
p("kidney-beans", "Фасоль красная", "grains", usda(173744), "красная фасоль")
p("white-beans", "Фасоль белая", "grains", usda(175202), "белая фасоль")
p("split-peas", "Горох колотый", "grains", usda(172428), "горох; горох сушёный")
p("mung-beans", "Маш", "grains", usda(174256), "бобы мунг")
p("pasta", "Макароны", "grains", usda(169736), "паста; спагетти; рожки; перья; вермишель")
p("egg-noodles", "Лапша яичная", "grains", usda(169731), "яичная лапша")
p("rice-noodles", "Лапша рисовая", "grains", usda(169742), "рисовая лапша")
p("soba", "Лапша гречневая", "grains", usda(168906), "соба; гречневая лапша")
p("corn-flakes", "Хлопья кукурузные", "grains", usda(174648), "кукурузные хлопья")
p("granola", "Гранола", "grains", usda(171646), "мюсли запечённые")
p("oat-bran", "Отруби овсяные", "grains", usda(168872), "овсяные отруби")

# Мука, сахар и всё для выпечки
p("flour", "Мука пшеничная", "baking", usda(168894), "мука; мука высший сорт")
p("wholegrain-flour", "Мука цельнозерновая", "baking", usda(168893), "цельнозерновая мука")
p("rye-flour", "Мука ржаная", "baking", usda(168886), "ржаная мука")
p("buckwheat-flour", "Мука гречневая", "baking", usda(170687), "гречневая мука")
p("corn-flour", "Мука кукурузная", "baking", usda(169697), "кукурузная мука")
p("rice-flour", "Мука рисовая", "baking", usda(169714), "рисовая мука")
p("corn-starch", "Крахмал кукурузный", "baking", usda(169698), "кукурузный крахмал")
p("potato-starch", "Крахмал картофельный", "baking", label(313, 0.1, 0.0, 78.2), "крахмал; картофельный крахмал",
  density=0.65)
p("sugar", "Сахар", "baking", usda(169655), "сахар-песок; сахарный песок")
p("brown-sugar", "Сахар коричневый", "baking", usda(168833), "коричневый сахар; тростниковый сахар")
p("powdered-sugar", "Сахарная пудра", "baking", usda(169656), "пудра сахарная")
p("vanilla-sugar", "Сахар ванильный", "baking", label(398, 0.0, 0.0, 99.5), "ванильный сахар; ванилин",
  units={"pack": 10}, density=0.85)
p("honey", "Мёд", "baking", usda(169640))
p("baking-powder", "Разрыхлитель", "baking", usda(172803), "разрыхлитель теста", units={"pack": 10})
p("baking-soda", "Сода пищевая", "baking", usda(175040), "сода", staple=True)
p("dry-yeast", "Дрожжи сухие", "baking", usda(175043), "сухие дрожжи; быстродействующие дрожжи", units={"pack": 11})
p("fresh-yeast", "Дрожжи прессованные", "baking", usda(175042), "живые дрожжи; свежие дрожжи", units={"pack": 100})
p("cocoa", "Какао-порошок", "baking", usda(169593), "какао")
p("dark-chocolate", "Шоколад горький", "baking", usda(170273), "тёмный шоколад; горький шоколад", piece=100)
p("milk-chocolate", "Шоколад молочный", "baking", usda(167587), "молочный шоколад", piece=90)
p("gelatin", "Желатин", "baking", usda(169599), units={"pack": 10})
p("coconut-flakes", "Кокосовая стружка", "baking", usda(170170))
p("vanilla-extract", "Ванильный экстракт", "baking", usda(173471), "экстракт ванили", base="ml")

# Масла, соусы и уксус
p("sunflower-oil", "Масло подсолнечное", "sauces", usda(171025),
  "растительное масло; подсолнечное масло; масло растительное", base="ml", staple=True)
p("olive-oil", "Масло оливковое", "sauces", usda(171413), "оливковое масло", base="ml")
p("coconut-oil", "Масло кокосовое", "sauces", usda(171412), "кокосовое масло")
p("sesame-oil", "Масло кунжутное", "sauces", usda(171016), "кунжутное масло", base="ml")
p("mayonnaise", "Майонез", "sauces", label(615, 0.3, 67.0, 2.6), "майонез 67%", density=0.94)
p("ketchup", "Кетчуп", "sauces", usda(168556))
p("mustard", "Горчица", "sauces", reference(162, 5.7, 6.4, 22.0), "горчица столовая", density=1.05)
p("soy-sauce", "Соевый соус", "sauces", usda(174277), "соус соевый", base="ml")
p("vinegar", "Уксус столовый", "sauces", usda(172237, energy="acetic acid"), "уксус; уксус 9%", base="ml",
  staple=True)
p("apple-vinegar", "Уксус яблочный", "sauces", usda(173469, energy="acetic acid"), "яблочный уксус", base="ml")
p("balsamic", "Уксус бальзамический", "sauces", usda(172241, energy="acetic acid"), "бальзамический уксус; бальзамик",
  base="ml")
p("wine-vinegar", "Уксус винный", "sauces", usda(172240, energy="acetic acid"), "винный уксус", base="ml")
p("horseradish", "Хрен", "sauces", usda(173472), "хрен столовый; хрен тёртый")
p("worcestershire", "Соус вустерский", "sauces", usda(171610), "вустерский соус", base="ml")
p("teriyaki", "Соус терияки", "sauces", usda(171167), "терияки", base="ml")
p("pesto", "Соус песто", "sauces", usda(171579), "песто")

# Специи и приправы: они либо есть, либо нет — граммы не считаем
p("salt", "Соль", "spices", usda(173468), "соль поваренная", staple=True)
p("black-pepper", "Перец чёрный молотый", "spices", usda(170931), "перец чёрный; чёрный перец; перец молотый; перец",
  staple=True)
p("allspice", "Перец душистый", "spices", usda(171315), "душистый перец", staple=True)
p("paprika", "Паприка", "spices", usda(171329), "паприка молотая; сладкая паприка", staple=True)
p("cayenne", "Перец красный молотый", "spices", usda(170932), "кайенский перец; хлопья чили; острый перец молотый",
  staple=True)
p("turmeric", "Куркума", "spices", usda(172231), staple=True)
p("cinnamon", "Корица", "spices", usda(171320), "корица молотая", staple=True)
p("cumin", "Зира", "spices", usda(170923), "кумин", staple=True)
p("coriander-seed", "Кориандр", "spices", usda(170922), "кориандр молотый; кориандр семена", staple=True)
p("ground-ginger", "Имбирь молотый", "spices", usda(170926), "сушёный имбирь", staple=True)
p("garlic-powder", "Чеснок сушёный", "spices", usda(171325), "чесночный порошок; чеснок гранулированный", staple=True)
p("onion-powder", "Лук сушёный", "spices", usda(171327), "луковый порошок", staple=True)
p("oregano", "Орегано", "spices", usda(171328), "душица", staple=True)
p("dried-basil", "Базилик сушёный", "spices", usda(171317), staple=True)
p("dried-thyme", "Тимьян сушёный", "spices", usda(170938), "чабрец", staple=True)
p("dried-rosemary", "Розмарин сушёный", "spices", usda(171333), staple=True)
p("bay-leaf", "Лист лавровый", "spices", usda(170917), "лавровый лист; лаврушка", piece=0.2, units={"leaf": 0.2},
  staple=True)
p("nutmeg", "Мускатный орех", "spices", usda(171326), "мускат", staple=True)
p("cloves", "Гвоздика", "spices", usda(171321), "гвоздика молотая", staple=True)
p("dried-dill", "Укроп сушёный", "spices", usda(171322), staple=True)
p("dried-parsley", "Петрушка сушёная", "spices", usda(170930), staple=True)
p("cardamom", "Кардамон", "spices", usda(170919), staple=True)
p("curry", "Карри", "spices", usda(170924), "приправа карри", staple=True)
p("mustard-powder", "Горчица в порошке", "spices", usda(170929), "горчичный порошок; сухая горчица", staple=True)
p("marjoram", "Майоран", "spices", usda(170928), staple=True)

# Консервы
p("canned-peas", "Горошек консервированный", "canned", usda(170104), "зелёный горошек; горошек", units={"can": 240})
p("canned-corn", "Кукуруза консервированная", "canned", usda(169214), "консервированная кукуруза", units={"can": 220})
p("canned-kidney-beans", "Фасоль красная консервированная", "canned", usda(174285), "фасоль консервированная",
  units={"can": 240})
p("canned-white-beans", "Фасоль белая консервированная", "canned", usda(175204), units={"can": 240})
p("canned-chickpeas", "Нут консервированный", "canned", usda(173800), units={"can": 240})
p("canned-tomatoes", "Томаты в собственном соку", "canned", usda(170051), "помидоры консервированные",
  units={"can": 400})
p("tomato-paste", "Томатная паста", "canned", usda(170459), "паста томатная")
p("tomato-puree", "Томатное пюре", "canned", usda(170460), "пассата; протёртые томаты")
p("black-olives", "Маслины", "canned", usda(169094), "маслины чёрные", piece=4)
p("green-olives", "Оливки", "canned", usda(169096), "оливки зелёные", piece=3)
p("pickles", "Огурцы маринованные", "canned", usda(168558), "маринованные огурцы; корнишоны", piece=30)
p("salted-cucumbers", "Огурцы солёные", "canned", usda(169379), "солёные огурцы; огурцы квашеные", piece=80)
p("sauerkraut", "Капуста квашеная", "canned", usda(169279), "квашеная капуста")
p("capers", "Каперсы", "canned", usda(172238))
p("coconut-milk", "Кокосовое молоко", "canned", usda(170173), "молоко кокосовое", base="ml", units={"can": 400})
p("canned-tuna", "Тунец консервированный", "canned", usda(173709), "тунец в собственном соку", units={"can": 130})
p("sardines", "Сардины в масле", "canned", usda(175139), "сардины консервированные", units={"can": 180})
p("canned-mushrooms", "Шампиньоны консервированные", "canned", usda(169254), "грибы консервированные",
  units={"can": 230})
p("canned-pineapple", "Ананасы консервированные", "canned", usda(167767), units={"can": 340})

# Орехи, семена и сухофрукты
p("walnuts", "Грецкий орех", "nuts", usda(170187), "грецкие орехи; орехи грецкие")
p("almonds", "Миндаль", "nuts", usda(170567))
p("hazelnuts", "Фундук", "nuts", usda(170581), "лесной орех")
p("cashew", "Кешью", "nuts", usda(170162))
p("peanuts", "Арахис", "nuts", usda(172430), "земляной орех")
p("pistachios", "Фисташки", "nuts", usda(170184))
p("pine-nuts", "Кедровые орехи", "nuts", usda(170591), "кедровый орех")
p("sunflower-seeds", "Семечки подсолнечника", "nuts", usda(170562), "семечки; семена подсолнечника")
p("pumpkin-seeds", "Семечки тыквенные", "nuts", usda(170556), "тыквенные семечки; тыквенные семена")
p("sesame", "Кунжут", "nuts", usda(170150), "семена кунжута")
p("flax-seeds", "Семена льна", "nuts", usda(169414), "льняное семя")
p("chia", "Семена чиа", "nuts", usda(170554), "чиа")
p("poppy-seeds", "Мак", "nuts", usda(171330), "мак пищевой")
p("peanut-butter", "Арахисовая паста", "nuts", usda(172470), "арахисовое масло")
p("tahini", "Тахини", "nuts", usda(170189), "кунжутная паста")
p("raisins", "Изюм", "nuts", usda(168165))
p("dried-apricots", "Курага", "nuts", usda(173941))
p("prunes", "Чернослив", "nuts", usda(168162))
p("dates", "Финики", "nuts", usda(171726), piece=7)
p("dried-figs", "Инжир сушёный", "nuts", usda(174665), piece=8)
p("dried-cranberries", "Клюква сушёная", "nuts", usda(171723), "вяленая клюква")

# Замороженные продукты
p("frozen-vegetables", "Овощная смесь замороженная", "frozen", usda(170471), "замороженные овощи; смесь овощей")
p("frozen-peas", "Горошек замороженный", "frozen", usda(170016), "замороженный горошек")
p("frozen-spinach", "Шпинат замороженный", "frozen", usda(169287))
p("frozen-broccoli", "Брокколи замороженная", "frozen", usda(169968))
p("frozen-strawberries", "Клубника замороженная", "frozen", usda(168173))
p("frozen-blueberries", "Черника замороженная", "frozen", usda(173950))
p("frozen-cherries", "Вишня замороженная", "frozen", usda(171718))
p("frozen-raspberries", "Малина замороженная", "frozen", usda(168209))
p("puff-pastry", "Тесто слоёное", "frozen", usda(172790), "слоёное тесто", units={"pack": 500})
p("pelmeni", "Пельмени", "frozen", label(275, 11.9, 12.4, 29.0))
p("ice-cream", "Мороженое пломбир", "frozen", label(231, 3.2, 15.0, 20.8), "пломбир")

# Сладости
p("jam", "Варенье", "sweets", usda(169641), "джем; конфитюр")
p("maple-syrup", "Сироп кленовый", "sweets", usda(169661), "кленовый сироп", base="ml")
p("chocolate-spread", "Паста шоколадная", "sweets", usda(168000), "шоколадно-ореховая паста; нутелла")
p("marshmallow", "Маршмеллоу", "sweets", usda(167995))
p("zefir", "Зефир", "sweets", label(326, 0.8, 0.1, 79.8), piece=35)
p("halva", "Халва подсолнечная", "sweets", label(516, 11.6, 29.7, 54.0), "халва")
p("butter-cookies", "Печенье сливочное", "sweets", usda(174950), "печенье")

# Напитки
p("water", "Вода", "drinks", usda(173647), "вода питьевая", base="ml", density=1.0, staple=True)
p("orange-juice", "Сок апельсиновый", "drinks", usda(169098), "апельсиновый сок", base="ml")
p("apple-juice", "Сок яблочный", "drinks", usda(173933), "яблочный сок", base="ml")
p("red-wine", "Вино красное сухое", "drinks", usda(173190), "красное вино", base="ml")
p("white-wine", "Вино белое сухое", "drinks", usda(174837), "белое вино", base="ml")
p("chicken-stock", "Бульон куриный", "drinks", usda(172884), "куриный бульон", base="ml")
p("beef-stock", "Бульон говяжий", "drinks", usda(172883), "говяжий бульон; мясной бульон", base="ml")
p("almond-milk", "Молоко миндальное", "drinks", usda(174832), "миндальное молоко", base="ml")
p("soy-milk", "Молоко соевое", "drinks", usda(172446), "соевое молоко", base="ml")
p("oat-milk", "Молоко овсяное", "drinks", label(45, 1.0, 1.5, 6.5), "овсяное молоко", base="ml", density=1.03)
p("instant-coffee", "Кофе растворимый", "drinks", usda(171893))

# Прочее
p("tofu", "Тофу", "other", usda(172475), "сыр тофу")
