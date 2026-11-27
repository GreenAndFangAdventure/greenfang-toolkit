-- RecipeLink (GF-009-10, spec v2.0 §6, §7.2, §7.4 圖紙連動): 「尋找圖紙」 on
-- the 配方 page, and 「教：配方｜專業」 on the 調貨所's recipe listings.
--
-- Where the link comes from (docs: GF-009-10 notes). The repo has no table of
-- recipe (spell) ID -> recipe item ID. What it has is the item catalog
-- (SupplyCatalogData.lua, DB2 Item / ItemSparse): every TRADEABLE item
-- (拾取綁定 and quest items are not in it), with ClassID 9 (配方) and the
-- subclass = the profession, named 「圖樣：亞麻斗篷」, 「公式：附魔護腕 - 次級精神」…
-- So a recipe is linked to a recipe item only when:
--   * the client knows the recipe's name (C_Spell.GetSpellName) and its
--     profession (the page's own skillLineID);
--   * exactly ONE catalog item of ClassID 9 with that profession's subclass is
--     named 「<prefix>：<recipe name>」 (two or more: no link, never a guess);
--   * when the client already has the item's data (never asked here): it is
--     still ClassID 9, the same subclass, not 拾取綁定 / quest, and its name
--     still teaches that name.
-- The crafted item's ID (GetRecipeSchematic().outputItemID) and the recipe
-- (spell) ID are never used as the recipe item's ID. Trainer recipes have no
-- item and so no link; recipes of a recipe item that binds on pickup are not
-- in the catalog and so have no link either.
--
-- Own state: a recipe counts as learned when this character's own shared list
-- (R<skillLineID>, Recipes.scan) has it; with no list yet for that profession
-- (window never opened) or no profession data, nothing is decided and no
-- button is shown. Learning the recipe of my own 圖紙 徵求 later only leaves
-- a notice (通知中心, module "recipe"): 「結束徵求」 is the player's click.
-- Nothing here is sent anywhere; no new event, timer or OnUpdate.

local _, ns = ...
local str = ns.str

local RL = {}
ns.RecipeLink = RL

-- Recipe item subclass (Enum.ItemRecipeSubclass) <-> skillLineID.
RL.SUBCLASS_SKILL = { [1] = 165, [2] = 197, [3] = 202, [4] = 164, [5] = 185, [6] = 171, [7] = 129, [8] = 333, [9] = 356 }
RL.SKILL_SUBCLASS = {}
for sub, skill in pairs(RL.SUBCLASS_SKILL) do RL.SKILL_SUBCLASS[skill] = sub end
RL.RECIPE_CLASS = 9

RL.LABEL = "尋找圖紙"
RL.ICON = "Interface\\Icons\\INV_Scroll_03"
RL.TEXT = {
    tip = "到綠皮調貨所徵求這張圖紙（不會自動送出）",
    combat = "戰鬥中不能開刊登",
    off = "手動刊登已關閉（在綠皮調貨所打開「手動刊登」）",
    busy = "刊登視窗裡還有沒送出的內容，請先送出或取消",
    existing = "已經有這張圖紙的徵求，已帶到那一筆",
}
RL.NOTIFY_MODULE = "recipe"
RL.END_ACTION = { key = "end", text = "結束徵求" }

local stats = { mapBuilds = 0, links = 0, finds = 0, prompts = 0 }
RL.stats = stats

---------------------------------------------------------------------------
-- Names (pure)
---------------------------------------------------------------------------

local FULL_COLON = "\239\188\154" -- 「：」
-- 「圖樣：亞麻斗篷」 -> 「亞麻斗篷」; nil when the name has no 「前綴：」.
function RL.taughtName(name)
    name = str(name)
    local p = name:find(FULL_COLON, 1, true)
    local rest
    if p and p > 1 then
        rest = name:sub(p + #FULL_COLON)
    else
        p = name:find(":", 1, true)
        if p and p > 1 then rest = name:sub(p + 1) end
    end
    if not rest then return nil end
    rest = rest:gsub("^%s+", ""):gsub("%s+$", "")
    if rest == "" then return nil end
    return rest
end

---------------------------------------------------------------------------
-- The catalog's recipe items, by profession and taught name (built once)
---------------------------------------------------------------------------

local map -- { bySkill = { [skill] = { [taught] = itemID | false } }, byItem = { [itemID] = { skill, taught } }, n }
function RL.patternMap()
    if map then return map end
    local Cat = ns.SupplyCatalog
    if not (Cat and Cat.load()) then return nil end
    local bySkill, byItem, n, dup = {}, {}, 0, 0
    for i = 1, Cat.count() do
        local c, s = Cat.kindOf(i)
        local skill = c == RL.RECIPE_CLASS and RL.SUBCLASS_SKILL[s] or nil
        local taught = skill and RL.taughtName(Cat.gameName(i) or Cat.nameOf(i))
        if taught then
            local id = Cat.idOf(i)
            local t = bySkill[skill] or {}
            bySkill[skill] = t
            if t[taught] == nil then
                t[taught] = id
            elseif t[taught] ~= false then
                byItem[t[taught]] = nil
                t[taught] = false -- two items teach the same name: no link
                dup = dup + 1
            end
            if t[taught] then byItem[id] = { skill = skill, taught = taught } end
        end
    end
    for _ in pairs(byItem) do n = n + 1 end
    stats.mapBuilds = stats.mapBuilds + 1
    map = { bySkill = bySkill, byItem = byItem, n = n, dup = dup }
    return map
end

-- The client's data of an item only when it already has it (nothing asked).
local function clientInfo(itemID)
    local L = ns.SupplyListings
    return L and L.cachedInfo(itemID) or nil
end

-- true when the client's own data (when it has any) still agrees.
local function clientAgrees(itemID, skill, taught)
    local info = clientInfo(itemID)
    if not info then return true end
    if info.classID ~= RL.RECIPE_CLASS or RL.SUBCLASS_SKILL[info.subclassID or -1] ~= skill then return false, "client-class" end
    if not ns.SupplyListings.tradeable(info) then return false, "untradeable" end
    if RL.taughtName(info.name) ~= taught then return false, "client-name" end
    return true
end

-- The recipe item that teaches recipe (spell) ID `recipe` of profession
-- `skill`: itemID, or nil and why ("noskill", "noname", "nocatalog", "none",
-- "ambiguous", "client-class", "client-name", "untradeable").
function RL.patternFor(recipe, skill)
    recipe, skill = tonumber(recipe), tonumber(skill)
    if not recipe or not skill or not RL.SKILL_SUBCLASS[skill] then return nil, "noskill" end
    local name = ns.Recipes.knownName(recipe)
    if not name then return nil, "noname" end
    local m = RL.patternMap()
    if not m then return nil, "nocatalog" end
    local id = m.bySkill[skill] and m.bySkill[skill][name]
    if id == false then return nil, "ambiguous" end
    if not id then return nil, "none" end
    local agree, why = clientAgrees(id, skill, name)
    if not agree then return nil, why end
    return id
end

---------------------------------------------------------------------------
-- This character: profession data and learned recipes
---------------------------------------------------------------------------

-- One read of the own professions per redraw (the page's layout pass).
function RL.context()
    local list = ns.Data.ownProfessionsDetailed()
    local profs
    if type(list) == "table" and #list > 0 then
        profs = {}
        for _, p in ipairs(list) do
            local id = tonumber(p.skillLineID)
            if id then profs[id] = true end
        end
    end
    return { profs = profs }
end

local learnedMemo = {} -- [skill] = { list = decoded list, set = { [id] = true } }
local function ownList(skill)
    local Share = ns.Share
    local a = Share.selfAuthor()
    if not a or not Share.store() then return nil end
    return Share.decoded(a, "R" .. skill)
end
local function learnedSet(skill)
    local list = ownList(skill)
    if type(list) ~= "table" then return nil end
    local m = learnedMemo[skill]
    if m and m.list == list then return m.set end
    local set = {}
    for _, id in ipairs(list) do set[id] = true end
    learnedMemo[skill] = { list = list, set = set }
    return set
end

-- "learned", "unlearned", "noprof" (this character has no such profession) or
-- "unknown" (profession data or the own recipe list not there yet: never
-- taken as 沒學).
function RL.ownState(recipe, skill, ctx)
    ctx = ctx or RL.context()
    if not ctx.profs then return "unknown" end
    if not ctx.profs[skill] then return "noprof" end
    local set = learnedSet(skill)
    if not set then return "unknown" end
    if set[recipe] then return "learned" end
    return "unlearned"
end

-- The 配方 page's row: the recipe item's ID when 「尋找圖紙」 applies, else
-- nil and why.
function RL.canFind(data, ctx)
    if type(data) ~= "table" or not data.id or not data.skill then return nil, "nodata" end
    if data.mine then return nil, "learned" end
    local state = RL.ownState(data.id, data.skill, ctx)
    if state ~= "unlearned" then return nil, state end
    return RL.patternFor(data.id, data.skill)
end

---------------------------------------------------------------------------
-- 「尋找圖紙」: the 調貨所's form, 徵求, the recipe item, 1; nothing sent
---------------------------------------------------------------------------

-- Returns "new" (form filled in), "existing" (my active 徵求 of it opened for
-- editing) or nil and why ("combat", "off", "busy", "nopage", a canFind reason).
function RL.find(data)
    if ns.inCombat() then ns.say(RL.TEXT.combat); return nil, "combat" end
    local id, why = RL.canFind(data)
    if not id then return nil, why end
    local UI, L, Supply = ns.SupplyUI, ns.SupplyListings, ns.Supply
    if not (UI and L and Supply and ns.Framework.get(UI.ID)) then return nil, "nopage" end
    if not Supply.manualOn() then ns.say(RL.TEXT.off); return nil, "off" end
    if UI.formDirty() then
        local f = UI.form()
        if f and f.Raise then f:Raise() end
        ns.say(RL.TEXT.busy)
        return nil, "busy"
    end
    ns.Framework.open(UI.ID)
    stats.finds = stats.finds + 1
    local dup = L.duplicateOf(id, "need")
    if dup then
        UI.openForm(dup, true)
        ns.say(RL.TEXT.existing)
        return "existing", dup
    end
    local okFill, fillWhy = UI.prefill(id, "recipe")
    if not okFill then return nil, fillWhy end
    return "new", id
end

---------------------------------------------------------------------------
-- What a recipe item teaches (the 調貨所's rows and tooltips)
---------------------------------------------------------------------------

-- Recipe (spell) IDs of a profession by name: the last finished guild index
-- (Recipes, never built here) and my own list. Rebuilt when either changes.
local nameMemo = {} -- [skill] = { index, own, names }
local function recipeByName(skill)
    local idx = ns.Recipes.lastIndex()
    local p = idx and idx[skill]
    local own = ownList(skill)
    local m = nameMemo[skill]
    if m and m.index == p and m.own == own then return m.names end
    local names, seen = {}, {}
    local function add(id)
        if seen[id] then return end
        seen[id] = true
        local name = ns.Recipes.knownName(id)
        if not name then return end
        if names[name] == nil then names[name] = id elseif names[name] ~= id then names[name] = false end
    end
    for id in pairs(p and p.recipes or {}) do add(id) end
    for _, id in ipairs(type(own) == "table" and own or {}) do add(id) end
    nameMemo[skill] = { index = p, own = own, names = names }
    return names
end

local classMemo = {} -- [itemID] = classID once known (an item's class never changes)
-- { recipe, skill, name, profession } or nil (not a recipe item, or the
-- recipe is not known by its ID to this client / the guild's lists).
function RL.teachOf(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    if classMemo[itemID] and classMemo[itemID] ~= RL.RECIPE_CLASS then return nil end
    local skill, taught
    -- The item's class without its data (no server request) when the client
    -- has GetItemInfoInstant (Mainline: 6th value = classID): anything that is
    -- not a recipe item stops here, before the catalog is opened.
    if classMemo[itemID] == nil and type(C_Item) == "table" and type(C_Item.GetItemInfoInstant) == "function" then
        local okCall, _, _, _, _, _, classID = pcall(C_Item.GetItemInfoInstant, itemID)
        classID = okCall and tonumber(classID) or nil
        if classID then
            classMemo[itemID] = classID
            if classID ~= RL.RECIPE_CLASS then return nil end
        end
    end
    local info = clientInfo(itemID)
    if info then
        classMemo[itemID] = info.classID
        if info.classID ~= RL.RECIPE_CLASS or not ns.SupplyListings.tradeable(info) then return nil end
        skill, taught = RL.SUBCLASS_SKILL[info.subclassID or -1], RL.taughtName(info.name)
    end
    local m = RL.patternMap()
    local e = m and m.byItem[itemID]
    if not info then
        if not e then return nil end
        skill, taught = e.skill, e.taught
    end
    if not skill or not taught then return nil end
    local recipe = recipeByName(skill)[taught]
    if not recipe then return nil end
    -- Both ways: the recipe's own link must lead back to this item.
    if RL.patternFor(recipe, skill) ~= itemID then return nil end
    stats.links = stats.links + 1
    return { recipe = recipe, skill = skill, name = ns.Recipes.name(recipe),
        profession = ns.Data.skillName(nil, skill) or ("專業 " .. skill) }
end

-- 「教：亞麻斗篷｜裁縫」 or nil.
function RL.teachText(itemID)
    local t = RL.teachOf(itemID)
    if not t then return nil end
    return "教：" .. t.name .. "｜" .. t.profession
end

---------------------------------------------------------------------------
-- Learned it: a notice, never an automatic end (owner 2026-11-25)
---------------------------------------------------------------------------

local function memory()
    local N = ns.Notify
    local mem = N and N.memory and N.memory(RL.NOTIFY_MODULE)
    if type(mem) ~= "table" then return nil end
    if type(mem.prompted) ~= "table" then mem.prompted = {} end
    return mem
end

-- My active 圖紙 徵求 whose recipe I have now learned: one notice each
-- (once per listing). Returns how many were pushed.
function RL.checkLearned()
    local N, L = ns.Notify, ns.SupplyListings
    if not (N and L) or ns.inCombat() then return 0 end
    local mem = memory()
    local pushed = 0
    if mem then -- forget listings that are gone from 我的刊登
        local kept = {}
        for _, l in ipairs(L.own()) do kept[l.id] = true end
        for id in pairs(mem.prompted) do if not kept[id] then mem.prompted[id] = nil end end
    end
    for _, l in ipairs(L.ownActive()) do
        if l.direction == "need" and not (mem and mem.prompted[l.id]) then
            local t = RL.teachOf(l.itemID)
            local set = t and learnedSet(t.skill)
            if set and set[t.recipe] then
                local r = N.push({ module = RL.NOTIFY_MODULE, key = "learned:" .. l.id,
                    text = "已學會「" .. t.name .. "」，要不要結束這筆圖紙徵求？",
                    target = { page = "supply", id = l.itemID, tab = "mine" },
                    actions = { RL.END_ACTION } })
                if r ~= "bad" and r ~= "off" and r ~= "burst" then
                    if mem then mem.prompted[l.id] = true end
                    pushed = pushed + 1
                    stats.prompts = stats.prompts + 1
                end
            end
        end
    end
    return pushed
end

if ns.Notify and ns.Notify.register then
    ns.Notify.register(RL.NOTIFY_MODULE, {
        onAction = function(e, key)
            if key ~= RL.END_ACTION.key then return nil end
            local id = tonumber(tostring(e.key):match("^learned:(%d+)$"))
            if not id or not ns.SupplyListings.finish(id, "closed") then return "none" end
            if ns.SupplyUI and ns.SupplyUI.refresh then pcall(ns.SupplyUI.refresh) end
            if ns.Notify.dismiss then ns.Notify.dismiss(e) end
            return "ended"
        end,
    })
end

-- My own recipe list changed (Recipes.scan; never in combat).
ns.Share.onUpdate(function(a)
    if a ~= nil and a == ns.Share.selfAuthor() then RL.checkLearned() end
end)

function RL.diagText()
    local m = map
    return string.format("圖紙連動：目錄圖紙 %s 筆（重名不連 %s）｜這次登入尋找 %d 次、提示 %d 則",
        m and tostring(m.n) or "未載入", m and tostring(m.dup) or "-", stats.finds, stats.prompts)
end

function RL.resetSession()
    map = nil
    learnedMemo, nameMemo, classMemo = {}, {}, {}
    for k in pairs(stats) do stats[k] = 0 end
end
