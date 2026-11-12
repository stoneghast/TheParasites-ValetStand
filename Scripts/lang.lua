-- =============================================================================
-- ValetStand: the mod's text in the game's 22 languages, picked from the game's current language.
--
-- The text a player sees: the name (notebook entry, build prompt, panel title), the 16 slot hints and the two button tooltips.
-- Slot words follow the game's own text (its ST_Menu entries) where that is right, and fix it where it is not: the game's machine
-- translation turned "Hat" into the verb "has" and "Bra" into "good" in some languages. AI-translated; corrections welcome.
-- Seen drawn in game: Russian, Japanese, Arabic, Thai (name, hints), Korean and Chinese (tooltips).
-- Only displayed text lives here. The slots' container names, which pair the stand's slots with the player's, never change.
-- =============================================================================
local M = {}

local SLOT_ORDER = { "HEAD", "EYE", "EARWEAR", "MASK", "ARMOR", "UPPER", "BRA", "BACKPACK", "BELT", "LOWER", "PANTS", "PANTIES",
    "GARTER_BELT", "STOCKINGS", "BOOTS", "ACCESSORIES" }

-- language -> { name, undress tooltip, dress tooltip, slot hints in SLOT_ORDER }
local T = {
    en = { "Valet Stand", "Undress: put what you are wearing on the stand", "Dress: wear what is on the stand",
        { "Headwear", "Glasses", "Earrings", "Mask", "Armor", "Jacket", "Bra", "Backpack", "Belt", "Top", "Pants", "Panties",
          "Garter belt", "Stockings", "Boots", "Accessories" } },
    ar = { "حامل الملابس", "خلع الملابس: ضع ما ترتديه على الحامل", "ارتداء الملابس: ارتدِ ما على الحامل",
        { "غطاء الرأس", "نظارات", "أقراط", "قناع", "درع", "سترة", "حمالة صدر", "حقيبة ظهر", "حزام", "بلوزة", "بنطال", "سروال داخلي",
          "حزام الجوارب", "جوارب طويلة", "أحذية", "إكسسوارات" } },
    cs = { "Stojan na oblečení", "Svléknout: odložit, co máte na sobě, na stojan", "Obléknout: obléknout, co je na stojanu",
        { "Pokrývka hlavy", "Brýle", "Náušnice", "Maska", "Brnění", "Bunda", "Podprsenka", "Batoh", "Pásek", "Top", "Kalhoty", "Kalhotky",
          "Podvazkový pás", "Punčochy", "Boty", "Doplňky" } },
    de = { "Kleiderständer", "Ausziehen: Getragenes auf den Ständer legen", "Anziehen: tragen, was auf dem Ständer ist",
        { "Kopfbedeckung", "Brille", "Ohrringe", "Maske", "Rüstung", "Jacke", "BH", "Rucksack", "Gürtel", "Oberteil", "Hose", "Höschen",
          "Strumpfhalter", "Strümpfe", "Stiefel", "Accessoires" } },
    es = { "Galán de noche", "Desvestirse: dejar en el galán lo que llevas puesto", "Vestirse: ponerte lo que hay en el galán",
        { "Gorro", "Gafas", "Pendientes", "Máscara", "Armadura", "Chaqueta", "Sujetador", "Mochila", "Cinturón", "Camiseta", "Pantalones",
          "Bragas", "Liguero", "Medias", "Botas", "Accesorios" } },
    fi = { "Vaateteline", "Riisuudu: laita päällä olevat vaatteet telineeseen", "Pukeudu: pue telineessä olevat vaatteet",
        { "Päähine", "Lasit", "Korvakorut", "Naamari", "Haarniska", "Takki", "Rintaliivit", "Reppu", "Vyö", "Toppi", "Housut",
          "Pikkuhousut", "Sukkanauhaliivi", "Sukat", "Saappaat", "Asusteet" } },
    fr = { "Valet de nuit", "Se déshabiller : poser ce que vous portez sur le valet", "S'habiller : porter ce qui est sur le valet",
        { "Couvre-chef", "Lunettes", "Boucles d'oreilles", "Masque", "Armure", "Veste", "Soutien-gorge", "Sac à dos", "Ceinture", "Haut",
          "Pantalon", "Culotte", "Porte-jarretelles", "Bas", "Bottes", "Accessoires" } },
    hu = { "Ruhaállvány", "Levetkőzés: amit viselsz, tedd az állványra", "Felöltözés: vedd fel, ami az állványon van",
        { "Fejfedő", "Szemüveg", "Fülbevaló", "Maszk", "Páncél", "Kabát", "Melltartó", "Hátizsák", "Öv", "Felső", "Nadrág", "Bugyi",
          "Harisnyatartó", "Harisnya", "Csizma", "Kiegészítők" } },
    it = { "Servomuto", "Svestirsi: metti sul servomuto ciò che indossi", "Vestirsi: indossa ciò che è sul servomuto",
        { "Copricapo", "Occhiali", "Orecchini", "Maschera", "Armatura", "Giacca", "Reggiseno", "Zaino", "Cintura", "Top", "Pantaloni",
          "Mutandine", "Reggicalze", "Calze", "Stivali", "Accessori" } },
    ja = { "衣装トルソー", "脱ぐ：着ている服をトルソーに掛ける", "着る：トルソーの服を着る",
        { "帽子", "メガネ", "イヤリング", "マスク", "防具", "ジャケット", "ブラジャー", "バックパック", "ベルト", "トップス", "ズボン", "ショーツ",
          "ガーターベルト", "ストッキング", "ブーツ", "アクセサリー" } },
    ko = { "옷걸이 마네킹", "옷 벗기: 입고 있는 옷을 마네킹에 걸기", "옷 입기: 마네킹에 걸린 옷 입기",
        { "모자", "안경", "귀걸이", "마스크", "갑옷", "재킷", "브라", "배낭", "벨트", "상의", "바지", "팬티", "가터벨트", "스타킹", "부츠", "액세서리" } },
    nl = { "Dressboy", "Uitkleden: leg wat je draagt op de dressboy", "Aankleden: trek aan wat op de dressboy ligt",
        { "Hoofddeksel", "Bril", "Oorbellen", "Masker", "Harnas", "Jas", "Beha", "Rugzak", "Riem", "Top", "Broek", "Slipje",
          "Jarretellegordel", "Kousen", "Laarzen", "Accessoires" } },
    pl = { "Stojak na ubrania", "Rozbierz się: odłóż na stojak to, co masz na sobie", "Ubierz się: załóż to, co jest na stojaku",
        { "Nakrycie głowy", "Okulary", "Kolczyki", "Maska", "Zbroja", "Kurtka", "Biustonosz", "Plecak", "Pasek", "Top", "Spodnie", "Majtki",
          "Pas do pończoch", "Pończochy", "Buty", "Akcesoria" } },
    pt = { "Cabide de pé", "Despir: pôr no cabide o que tem vestido", "Vestir: vestir o que está no cabide",
        { "Chapéu", "Óculos", "Brincos", "Máscara", "Armadura", "Casaco", "Soutien", "Mochila", "Cinto", "Top", "Calças", "Cuecas",
          "Cinta-liga", "Meias", "Botas", "Acessórios" } },
    ["pt-BR"] = { "Cabideiro", "Despir: colocar no cabideiro o que você está vestindo", "Vestir: vestir o que está no cabideiro",
        { "Chapéu", "Óculos", "Brincos", "Máscara", "Armadura", "Jaqueta", "Sutiã", "Mochila", "Cinto", "Blusa", "Calça", "Calcinha",
          "Cinta-liga", "Meias", "Botas", "Acessórios" } },
    ru = { "Вешалка-манекен", "Раздеться: повесить надетое на манекен", "Одеться: надеть то, что на манекене",
        { "Головной убор", "Очки", "Серьги", "Маска", "Броня", "Куртка", "Лифчик", "Рюкзак", "Пояс", "Майка", "Штаны", "Трусики",
          "Пояс для чулок", "Чулки", "Ботинки", "Аксессуары" } },
    sv = { "Herrbetjänt", "Klä av: lägg det du har på dig på herrbetjänten", "Klä på: ta på det som finns på herrbetjänten",
        { "Huvudbonad", "Glasögon", "Örhängen", "Mask", "Rustning", "Jacka", "Behå", "Ryggsäck", "Bälte", "Topp", "Byxor", "Trosor",
          "Strumpebandshållare", "Strumpor", "Stövlar", "Accessoarer" } },
    -- The two button tooltips stay English in Thai: they use the engine's default tooltip font, which has no Thai letters and
    -- draws boxes (seen in game). The name and slot hints use the game's fonts, which have them.
    th = { "หุ่นแขวนเสื้อผ้า", "Undress: put what you are wearing on the stand", "Dress: wear what is on the stand",
        { "หมวก", "แว่นตา", "ต่างหู", "หน้ากาก", "เกราะ", "แจ็คเก็ต", "บรา", "กระเป๋าเป้", "เข็มขัด", "เสื้อ", "กางเกง", "กางเกงชั้นใน",
          "สายรัดถุงน่อง", "ถุงน่อง", "รองเท้าบูท", "เครื่องประดับ" } },
    tr = { "Elbise askılığı", "Soyun: üzerindekileri askılığa koy", "Giyin: askılıktakileri giy",
        { "Başlık", "Gözlük", "Küpe", "Maske", "Zırh", "Ceket", "Sütyen", "Sırt çantası", "Kemer", "Üst", "Pantolon", "Külot",
          "Jartiyer", "Çorap", "Bot", "Aksesuarlar" } },
    uk = { "Вішак-манекен", "Роздягнутися: повісити вдягнене на манекен", "Одягнутися: вдягнути те, що на манекені",
        { "Головний убір", "Окуляри", "Сережки", "Маска", "Броня", "Куртка", "Бюстгальтер", "Рюкзак", "Пояс", "Топ", "Штани", "Трусики",
          "Підв'язковий пояс", "Панчохи", "Черевики", "Аксесуари" } },
    ["zh-Hans"] = { "人台衣架", "脱衣：把身上穿的挂到衣架上", "穿衣：穿上衣架上的衣物",
        { "帽子", "眼镜", "耳环", "面罩", "盔甲", "夹克", "胸罩", "背包", "腰带", "上衣", "裤子", "内裤", "吊袜带", "长筒袜", "靴子", "饰品" } },
}
T.zh = T["zh-Hans"]   -- the game's "zh" text is Simplified Chinese too

local I18N = "/Script/Engine.Default__KismetInternationalizationLibrary"

-- The game's current language as one of T's keys: exact (pt-BR), then the base language (pt-PT -> pt), else English.
local function current()
    local code = "en"
    pcall(function() code = StaticFindObject(I18N):GetCurrentLanguage():ToString() end)
    if T[code] then return code end
    local base = code:match("^(%a+)")
    if base and T[base] then return base end
    return "en"
end
M.current = current

local function row() return T[current()] end
function M.name() return row()[1] end
function M.undress() return row()[2] end
function M.dress() return row()[3] end

local HINT = {}
for i, slot in ipairs(SLOT_ORDER) do HINT[slot] = i end
function M.hint(slot) local i = HINT[slot]; return i and row()[4][i] or nil end

-- every language has every text (checked at load: a gap would show English silently)
for code, r in pairs(T) do
    assert(#r == 4 and #r[4] == #SLOT_ORDER, "lang.lua: incomplete row for " .. code)
end

return M
