-- Recipes (GF-001-D10 phase 2, D-013/D-014): reads this character's learned
-- recipes from its own profession window, shares them as R<skillLineID>
-- records (Share.lua), and shows the guild's recipes on the 「配方」 page.
--
-- Reading (docs/research/recipe-sharing-design.md §0, §2a, §3d; GuildForge on
-- Forever): C_TradeSkillUI.GetAllRecipeIDs() lists learned AND unlearned
-- recipes, so only info.learned counts; the list loads after the window
-- opens (read again at 2 s and 5 s); window filters can hide recipes, so a
-- smaller subset never replaces the saved list; someone else's window
-- (linked / guild / guild member) is never read.

local _, ns = ...
local str = ns.str
local Share = ns.Share

local Recipes = {}
ns.Recipes = Recipes

-- Professions that have recipes (mining = its smelting window).
Recipes.CRAFTS = { [164] = true, [165] = true, [197] = true, [202] = true, [171] = true,
    [333] = true, [185] = true, [129] = true, [186] = true }
Recipes.READ_AGAIN = { 2, 5 }

-- Professions whose window had a filter on this session, so the saved list
-- was kept (GF-001-D19: no chat message; shown in 「同步與診斷」).
local skippedFiltered = {}

local function T() return C_TradeSkillUI end

-- Whose window is open: true only for this character's own profession window.
function Recipes.isOwnWindow()
    local t = T()
    if type(t) ~= "table" then return false end
    for _, fn in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsTradeSkillGuildMember" }) do
        if type(t[fn]) == "function" and ns.call(t[fn]) == true then return false end
    end
    if type(t.IsTradeSkillReady) == "function" and ns.call(t.IsTradeSkillReady) == false then return false end
    return true
end

-- skillLineID of the open window, or nil.
function Recipes.openSkillLine()
    local t = T()
    if type(t) ~= "table" or type(t.GetBaseProfessionInfo) ~= "function" then return nil end
    local info = ns.call(t.GetBaseProfessionInfo)
    local id = type(info) == "table" and ns.num(info.professionID) or nil
    if id and Recipes.CRAFTS[id] then return id end
    return nil
end

---------------------------------------------------------------------------
-- Which profession a recipe belongs to (GF-001-D21)
---------------------------------------------------------------------------
-- 0.9.5 in game: with 專業 = 烹飪 the page listed first aid and smelting
-- recipes too. GetAllRecipeIDs() in the open window also returns recipes of
-- the character's other professions, and every learned one was stored under
-- the open profession. Each recipe is now checked, when reading the window
-- and when building the page (records shared by 0.9.0 to 0.9.5 carry the
-- mixed lists). Unknown (the client does not say) = keep.

local recipeSkillCache = {}

local function craftOf(...)
    for i = 1, select("#", ...) do
        local id = ns.num((select(i, ...)))
        if id and Recipes.CRAFTS[id] then return id end
    end
    return nil
end

-- skillLineID of a recipe, or nil when the client does not say.
function Recipes.skillOfRecipe(id)
    local cached = recipeSkillCache[id]
    if cached then return cached end
    local t = T()
    if type(t) ~= "table" then return nil end
    local skill
    if type(t.GetProfessionInfoByRecipeID) == "function" then
        local info = ns.call(t.GetProfessionInfoByRecipeID, id)
        if type(info) == "table" then skill = craftOf(info.parentProfessionID, info.professionID) end
    end
    if not skill and type(t.GetTradeSkillLineForRecipe) == "function" then
        local ok, a, _, c = pcall(t.GetTradeSkillLineForRecipe, id)
        if ok then skill = craftOf(c, a) end
    end
    if skill then recipeSkillCache[id] = skill end
    return skill
end

-- true / false when the client can tell whether recipe id is in skill; nil
-- when it cannot.
function Recipes.inSkill(id, skill)
    local known = Recipes.skillOfRecipe(id)
    if known then return known == skill end
    local t = T()
    if type(t) == "table" and type(t.IsRecipeInSkillLine) == "function" then
        local r = ns.call(t.IsRecipeInSkillLine, id, skill)
        if type(r) == "boolean" then return r end
    end
    return nil
end

-- Can this client tell at all? (Checked once per index build.)
function Recipes.canTellSkill()
    local t = T()
    return type(t) == "table" and (type(t.GetProfessionInfoByRecipeID) == "function"
        or type(t.GetTradeSkillLineForRecipe) == "function" or type(t.IsRecipeInSkillLine) == "function")
end

-- ids without the ones the client says belong to another profession.
function Recipes.onlySkill(ids, skill)
    if not Recipes.canTellSkill() then return ids end
    local out = {}
    for _, id in ipairs(ids) do
        if Recipes.inSkill(id, skill) ~= false then out[#out + 1] = id end
    end
    return out
end

-- Learned recipe IDs in the open window (sorted), or nil when not readable.
function Recipes.readOpen()
    local t = T()
    if type(t) ~= "table" or type(t.GetAllRecipeIDs) ~= "function" or type(t.GetRecipeInfo) ~= "function" then
        return nil
    end
    local all = ns.call(t.GetAllRecipeIDs)
    if type(all) ~= "table" then return nil end
    local ids = {}
    for _, id in ipairs(all) do
        local info = ns.call(t.GetRecipeInfo, id)
        if type(info) == "table" and info.learned == true then
            local rid = ns.num(info.recipeID) or ns.num(id)
            if rid then ids[#ids + 1] = rid end
        end
    end
    table.sort(ids)
    return ids
end

local function isSubset(small, big)
    local set = {}
    for _, id in ipairs(big) do set[id] = true end
    for _, id in ipairs(small) do if not set[id] then return false end end
    return true
end

local reagentPass = {} -- [skill] = the list cacheOwn last went over (this session)

-- Read the open window now. Returns a result string (tests, diagnostics):
-- "stored", "same", "filtered", "not-own", "unknown", "empty", "combat", "no-api".
function Recipes.scan()
    if ns.inCombat() then return "combat" end
    if not Recipes.isOwnWindow() then return "not-own" end
    local skill = Recipes.openSkillLine()
    if not skill then return "unknown" end
    local ids = Recipes.readOpen()
    if not ids then return "no-api" end
    if #ids == 0 then return "empty" end -- not loaded yet
    ids = Recipes.onlySkill(ids, skill) -- D21: not the other professions' recipes
    if #ids == 0 then return "empty" end
    local a = Share.selfAuthor()
    if not a or not Share.store() then return "unknown" end
    local g = "R" .. skill
    local old = Share.get(a, g)
    local oldIDs = old and Share.decodeValue(g, old.v) or nil
    -- A list saved by 0.9.5 or older may hold other professions' recipes.
    local savedCount = oldIDs and #oldIDs or 0
    if oldIDs then oldIDs = Recipes.onlySkill(oldIDs, skill) end
    if oldIDs and #ids < #oldIDs and isSubset(ids, oldIDs) then
        skippedFiltered[skill] = true
        -- Keep the saved list, but without the mixed-in recipes.
        if #oldIDs < savedCount then Share.ownRecord(g, Share.encodeValue(g, oldIDs)) end
        return "filtered"
    end
    if oldIDs then
        -- Recipes are not forgotten: keep the union (a filter may hide some).
        local set = {}
        for _, id in ipairs(oldIDs) do set[id] = true end
        for _, id in ipairs(ids) do set[id] = true end
        ids = {}
        for id in pairs(set) do ids[#ids + 1] = id end
    end
    local value = Share.encodeValue(g, ids)
    local r = Share.ownRecord(g, value)
    -- GF-006-B (R-8.5): remember the reagent lists of our own recipes.
    -- GF-FIX-C (review low-16): once per list and session; a scan that
    -- found the same list does not start another pass over it.
    if ns.Prices and reagentPass[skill] ~= value then
        reagentPass[skill] = value
        ns.Prices.cacheOwn(ids)
    end
    return r
end

-- Names of the professions skipped because of a window filter (sorted).
function Recipes.skippedFiltered()
    local list = {}
    for skill in pairs(skippedFiltered) do list[#list + 1] = skill end
    table.sort(list)
    for i, skill in ipairs(list) do list[i] = ns.Data.skillName(nil, skill) or ("專業 " .. skill) end
    return list
end

-- GF-FIX-C: run fn now, unless it ran less than gap seconds ago; calls in
-- that gap make one more run at its end (with the state of then). The first
-- of a burst is never delayed and the last is at most gap late.
local held = {} -- [key] = false (held) / true (held, run again at the end)
function Recipes.soon(key, gap, fn)
    if held[key] ~= nil then held[key] = true; return false end
    held[key] = false
    ns.after(gap, function() -- first: an error in fn must not hold the key for good
        local again = held[key]
        held[key] = nil
        if again then Recipes.soon(key, gap, fn) end
    end)
    fn()
    return true
end

-- GF-FIX-C (review mid-27): TRADE_SKILL_SHOW / LIST_UPDATE / DATA_SOURCE_CHANGED
-- come in bursts (opening, crafting, typing in the window). The first one
-- reads at once, as before (the data shows right away); the ones within
-- SCAN_GAP after it make one more read at the end of the gap, not one each.
Recipes.SCAN_GAP = 0.3
Recipes.scanReads = 0 -- full reads started by window events (diagnostics, tests)
local readTimers = {}
local function scanNow()
    if not Recipes.isOwnWindow() then return end
    Recipes.scanReads = Recipes.scanReads + 1
    Recipes.scan()
end
function Recipes.scanSoon()
    if not Recipes.isOwnWindow() then return end
    local skill = Recipes.openSkillLine() or 0
    Recipes.soon("scan", Recipes.SCAN_GAP, scanNow)
    for _, delay in ipairs(Recipes.READ_AGAIN) do
        local key = skill .. ":" .. delay
        if not readTimers[key] then
            readTimers[key] = true
            ns.after(delay, function() readTimers[key] = nil; Recipes.scan() end)
        end
    end
end

---------------------------------------------------------------------------
-- The guild's recipes (pure over Share's store; covered by offline tests)
---------------------------------------------------------------------------

local nameCache = {}
function Recipes.name(id)
    if nameCache[id] then return nameCache[id] end
    local name
    if C_Spell and type(C_Spell.GetSpellName) == "function" then name = ns.call(C_Spell.GetSpellName, id) end
    name = str(name)
    if name == "" then return "配方 #" .. tostring(id) end -- not cached: the client may learn it later
    nameCache[id] = name
    return name
end

-- The client's name for a recipe, or nil while it does not know it.
function Recipes.knownName(id)
    local name = Recipes.name(id)
    if nameCache[id] then return name end
    return nil
end

-- Icon of a recipe (GF-001-D21): the crafted item's icon, else the one the
-- profession window gives, else the recipe spell's. nil when the client
-- knows none yet (not cached then: item data may arrive later).
local iconCache = {}
function Recipes.icon(id)
    local cached = iconCache[id]
    if cached then return cached end
    local icon
    local t = T()
    if type(t) == "table" and type(t.GetRecipeSchematic) == "function" then
        local sc = ns.call(t.GetRecipeSchematic, id, false)
        local item = type(sc) == "table" and ns.num(sc.outputItemID) or nil
        if item then
            if C_Item and type(C_Item.GetItemIconByID) == "function" then icon = ns.call(C_Item.GetItemIconByID, item) end
            if not icon and type(GetItemIcon) == "function" then icon = ns.call(GetItemIcon, item) end
        end
    end
    if not icon and type(t) == "table" and type(t.GetRecipeInfo) == "function" then
        local info = ns.call(t.GetRecipeInfo, id)
        icon = type(info) == "table" and info.icon or nil
    end
    if not icon and C_Spell and type(C_Spell.GetSpellTexture) == "function" then
        icon = ns.call(C_Spell.GetSpellTexture, id)
    end
    if type(icon) ~= "number" and type(icon) ~= "string" then icon = nil end
    if icon == "" or icon == 0 then icon = nil end
    if icon then iconCache[id] = icon end
    return icon
end

-- Put the recipe's icon on tex, or the profession's; hidden when neither.
function Recipes.setIcon(tex, id, skill)
    for _, path in ipairs({ Recipes.icon(id) or false, ns.Icons.professionIcon(skill) or false }) do
        if path and ns.Icons.set(tex, path) then
            tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            tex:Show()
            return path
        end
    end
    tex:Hide()
    return nil
end

-- "3 天前" / "5 小時前" / "12 分鐘前" / "剛剛" from a server time.
function Recipes.agoText(t)
    if type(t) ~= "number" then return "時間不明" end
    local d = Share.serverNow() - t
    if d < 60 then return "剛剛" end
    if d < 3600 then return math.floor(d / 60) .. " 分鐘前" end
    if d < 86400 then return math.floor(d / 3600) .. " 小時前" end
    return math.floor(d / 86400) .. " 天前"
end

-- Recipe record of a roster member for one profession: { ids, t, relayed } or nil.
function Recipes.of(guid, skill)
    local a = guid and Share.authorOf(guid)
    local rec = a and Share.get(a, "R" .. skill)
    if not rec then return nil end
    local ids = Share.decoded(a, "R" .. skill)
    if not ids then return nil end
    return { ids = ids, t = rec.t, relayed = not rec.fromAuthor and a ~= Share.selfAuthor() }
end

-- Everything known, per profession:
--   { [skill] = { crafters = { member... }, recipes = { [id] = { member... } } } }
-- member = { name, guid, online, t, relayed, self }
-- Built once per change of the shared data or the roster (GF-001-D11: a guild
-- of 115 with 300 recipes each is about 100 000 entries; 1,000 members about
-- 900 000). Members are visited online first, then by name, so every crafter
-- list is already in that order. GF-001-D14 (EVAL-1000 §3.5): the page builds
-- it over several frames (Recipes.STEP entries each), showing 整理中 only
-- the first time; afterwards the last finished index stays on screen while a
-- new one is built.
Recipes.STEP = 8000
local indexCache = {}
local building -- { version, roster, snap, ordered, pos, out, selfGuid }
-- GF-FIX-C (review high-3): the index is keyed on Share.version and
-- Roster.version (the roster's content), not on the snapshot object: a
-- roster scan that found nothing new keeps it, any real change rebuilds it.
Recipes.builds = 0 -- index builds started (diagnostics, tests)

local function startBuild(snap)
    local ordered = {}
    for _, m in ipairs(snap.members) do ordered[#ordered + 1] = { m = m, key = ns.keyName(m.name) } end
    table.sort(ordered, function(x, y)
        if (x.m.online == true) ~= (y.m.online == true) then return x.m.online == true end
        return x.key < y.key
    end)
    Recipes.builds = Recipes.builds + 1
    return { version = Share.version, roster = ns.Roster.version, snap = snap, ordered = ordered, pos = 1, out = {},
        selfGuid = ns.Data.player().guid, check = Recipes.canTellSkill() }
end

-- Work on the build until about budget entries were added. True when done.
local function work(b, budget)
    local done = 0
    while b.pos <= #b.ordered do
        local m = b.ordered[b.pos].m
        b.pos = b.pos + 1
        local a = m.guid and Share.authorOf(m.guid)
        local recs = a and Share.records(a)
        for g, rec in pairs(recs or {}) do
            local skill = tonumber(g:match("^R(%d+)$"))
            local ids = skill and Share.decoded(a, g)
            if ids and b.check then ids = Recipes.onlySkill(ids, skill) end -- D21
            if ids and #ids > 0 then
                local p = b.out[skill] or { crafters = {}, recipes = {} }
                b.out[skill] = p
                local who = { name = m.name, guid = m.guid, online = m.online == true, t = rec.t,
                    relayed = not rec.fromAuthor and m.guid ~= b.selfGuid, self = m.guid == b.selfGuid }
                p.crafters[#p.crafters + 1] = who
                for _, id in ipairs(ids) do
                    local list = p.recipes[id]
                    if not list then list = {}; p.recipes[id] = list end
                    list[#list + 1] = who
                end
                done = done + #ids
            end
        end
        if budget and done >= budget then return b.pos > #b.ordered end
    end
    return true
end

local function isFresh()
    return indexCache.out and indexCache.version == Share.version and indexCache.roster == ns.Roster.version
end

-- The whole index now (tests and callers that need it at once).
function Recipes.index()
    local snap = ns.Roster.current()
    if not snap then return {} end
    if isFresh() then return indexCache.out end
    local b = startBuild(snap)
    work(b, nil)
    indexCache = { version = b.version, roster = b.roster, out = b.out, at = ns.now(), steps = 1 }
    return b.out
end

-- The index for the page: the current one, or the last finished one while a
-- new one is built in steps (onDone runs when it is ready). nil only before
-- the first index is ready. A small guild is done in the first step, at once.
-- A big one is rebuilt at most every REBUILD_GAP seconds while data flows in,
-- and a build in progress is finished even if more data arrives meanwhile.
Recipes.REBUILD_GAP = 5
Recipes.steps = 0 -- frames used by step builds (diagnostics, tests)
local chainRunning = false

local function stepOnce()
    local b = building
    if not b then return true end
    Recipes.steps = Recipes.steps + 1
    b.steps = (b.steps or 0) + 1
    if not work(b, Recipes.STEP) then return false end
    building = nil
    indexCache = { version = b.version, roster = b.roster, out = b.out, at = ns.now(), steps = b.steps }
    return true
end

function Recipes.indexSoon(onDone)
    local snap = ns.Roster.current()
    if not snap then return {} end
    if isFresh() then return indexCache.out end
    if chainRunning then return indexCache.out end
    if indexCache.out and (indexCache.steps or 1) > 1 and ns.now() - (indexCache.at or 0) < Recipes.REBUILD_GAP then
        if onDone then ns.coalesce("recipes-rebuild", Recipes.REBUILD_GAP, onDone) end
        return indexCache.out
    end
    building = startBuild(snap)
    if stepOnce() then return indexCache.out end
    chainRunning = true
    local function step()
        if stepOnce() then
            chainRunning = false
            if onDone then onDone() end
        else
            ns.after(0, step)
        end
    end
    ns.after(0, step)
    return indexCache.out
end
function Recipes.isBuilding() return building ~= nil end
-- GF-009-10: the last finished index, never built here (nil before the first).
function Recipes.lastIndex() return indexCache.out end

-- Rows for one profession: { { id, name, crafters } }, filtered and sorted by name.
-- opts (GF-001-D19): online = only crafters who are online; who = "mine"
-- (only recipes I know) or "others" (only other members).
-- GF-002-E: active = only crafters taking orders (R-4.2); fee = "free" / "set"
-- / "max:<copper>" on the fee the row shows (Recipes.feeMatches).
-- GF-FIX-C (review mid-28): a recipe name is lower-cased once, and a row
-- the search leaves out is dropped before its crafters are sorted.
local searchKeys = {}
local function searchKey(name)
    local k = searchKeys[name]
    if not k then k = ns.keyName(name); searchKeys[name] = k end
    return k
end
function Recipes.rows(index, skill, query, onlyGuid, opts)
    local p = index[skill]
    local rows = {}
    if not p then return rows end
    opts = opts or {}
    if opts.who == "none" then return rows end
    local q = ns.keyName(query)
    for id, who in pairs(p.recipes) do
        local name = Recipes.name(id)
        if q == "" or searchKey(name):find(q, 1, true) then
            local list, mine = {}, false
            for _, m in ipairs(who) do
                if m.self then mine = true end
                local keep = (not onlyGuid or m.guid == onlyGuid)
                    and (not opts.online or m.online)
                    and (opts.who ~= "others" or not m.self)
                    and (not opts.active or (ns.Orders and ns.Orders.isActive(m.guid, skill)))
                if keep then list[#list + 1] = m end
            end
            if #list > 0 and (opts.who ~= "mine" or mine) then
                -- GF-006-B (R-4.2): active crafters first (active+online, active, online, others).
                if ns.Orders and #list > 1 then ns.Orders.sortCrafters(list, skill) end
                local row = { id = id, name = name, crafters = list, mine = mine, skill = skill } -- online first
                if not opts.fee or Recipes.feeMatches(Recipes.rowFee(row), opts.fee) then rows[#rows + 1] = row end
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return rows
end

-- GF-002-E: the fee a row shows (OrdersUI.rowFee): nil = nobody filled one in.
function Recipes.rowFee(row)
    if not (ns.OrdersUI and ns.OrdersUI.rowFee) then return nil end
    return ns.OrdersUI.rowFee(row, row.crafters)
end
function Recipes.feeMatches(fee, filter)
    if not filter then return true end
    if filter == "free" then return fee == 0 end
    if filter == "set" then return fee ~= nil end
    local max = tonumber(tostring(filter):match("^max:(%d+)$"))
    if max then return fee ~= nil and fee <= max end
    return true
end
Recipes.FEE_OPTIONS = {
    { value = nil, text = "工錢不限" },
    { value = "free", text = "免費" },
    { value = "set", text = "有填工錢" },
    { value = "max:10000", text = "1 金以內" },
    { value = "max:50000", text = "5 金以內" },
}
-- GF-UI-H (owner: 金額一律用金／銀／銅圖示): the amounts with the game's coin
-- icon, e.g. 「1[金] 以內」 (the plain words stay in FEE_PLAIN for the tests).
Recipes.FEE_PLAIN = {}
for _, o in ipairs(Recipes.FEE_OPTIONS) do
    local max = o.value and tonumber(tostring(o.value):match("^max:(%d+)$"))
    if max then
        Recipes.FEE_PLAIN[o.value] = o.text
        o.text = ns.Theme.coinText(max) .. " 以內"
    end
end

-- Rows of several professions in one list, by name (GF-001-D22).
function Recipes.rowsFor(index, skills, query, onlyGuid, opts)
    local out = {}
    for _, skill in ipairs(skills) do
        for _, r in ipairs(Recipes.rows(index, skill, query, onlyGuid, opts)) do out[#out + 1] = r end
    end
    if #skills > 1 then
        table.sort(out, function(a, b)
            if a.name ~= b.name then return a.name < b.name end
            return a.id < b.id
        end)
    end
    return out
end

-- "測試甲、測試乙 +2" (online first, at most 3 names). GF-006-B (R-4.2): a
-- gold hammer in front of crafters who are taking orders.
function Recipes.crafterText(list, skill)
    local names = {}
    for i = 1, math.min(3, #list) do
        local hammer = ns.Orders and skill and ns.Orders.isActive(list[i].guid, skill)
        names[i] = (hammer and (ns.OrdersUI.tex("hammer", 16) .. " ") or "") .. ns.shortName(list[i].name)
    end
    local text = table.concat(names, "、")
    if #list > 3 then text = text .. " +" .. (#list - 3) end
    return text
end

-- Online crafters other than this character (online first already).
function Recipes.onlineCrafters(list)
    local out = {}
    for _, m in ipairs(list or {}) do
        if m.online and not m.self then out[#out + 1] = m end
    end
    return out
end

-- First online crafter other than this character, or nil.
function Recipes.onlineCrafter(list)
    return Recipes.onlineCrafters(list)[1]
end

---------------------------------------------------------------------------
-- What a click on a recipe can do (GF-001-D19; docs/research/recipe-click.md)
---------------------------------------------------------------------------

-- Chat link of a recipe: the trade skill link when the client gives one,
-- else the spell link. nil when neither works.
function Recipes.link(id)
    local t = T()
    if type(t) == "table" and type(t.GetRecipeLink) == "function" then
        local link = ns.call(t.GetRecipeLink, id)
        if type(link) == "string" and link ~= "" then return link end
    end
    if C_Spell and type(C_Spell.GetSpellLink) == "function" then
        local link = ns.call(C_Spell.GetSpellLink, id)
        if type(link) == "string" and link ~= "" then return link end
    end
    return nil
end

local function chatUtil(modern, legacy)
    if type(ChatFrameUtil) == "table" and type(ChatFrameUtil[modern]) == "function" then return ChatFrameUtil[modern] end
    if type(_G[legacy]) == "function" then return _G[legacy] end
    return nil
end

-- Shift-click: put the link into the chat box (opening it when closed).
function Recipes.insertLink(id)
    local link = Recipes.link(id)
    if not link then return false end
    local insert = chatUtil("InsertLink", "ChatEdit_InsertLink")
    if insert and ns.call(insert, link) then return true end
    local open = chatUtil("OpenChat", "ChatFrame_OpenChat")
    if open then
        local ok = pcall(open, link)
        return ok
    end
    return false
end

-- Click: the recipe's own tooltip, pinned (as a chat link opens).
function Recipes.showDetail(id)
    local tip = ItemRefTooltip
    if type(tip) ~= "table" or type(tip.SetHyperlink) ~= "function" then return false end
    local link = Recipes.link(id)
    local hyperlink = link and link:match("|H(.-)|h") or ("spell:" .. id)
    if tip.SetOwner then pcall(tip.SetOwner, tip, UIParent, "ANCHOR_PRESERVE") end
    local ok = pcall(tip.SetHyperlink, tip, hyperlink)
    if ok and tip.Show then tip:Show() end
    return ok
end

-- 「密語」: open a whisper to an online crafter (m, or the first one), with
-- the recipe in it. The player still presses Enter; nothing is sent by the
-- toolkit.
function Recipes.whisper(data, m)
    m = m or (data and Recipes.onlineCrafter(data.crafters))
    if not m then return false end
    local link = Recipes.link(data.id) or data.name
    local withText = chatUtil("SendTellWithMessage", "ChatFrame_SendTellWithMessage")
    if withText and pcall(withText, m.name, "可以幫我做" .. link .. "嗎？") then return true end
    local tell = chatUtil("SendTell", "ChatFrame_SendTell")
    return tell ~= nil and pcall(tell, m.name) or false
end

-- This character's own recipe in its profession window (click on a row,
-- GF-001-D20). Only out of combat; false when the function is missing or
-- fails, and the caller then shows the pinned recipe instead.
function Recipes.openOwn(id)
    if ns.inCombat() then return false end
    local t = T()
    if type(t) ~= "table" or type(t.OpenRecipe) ~= "function" then return false end
    return (pcall(t.OpenRecipe, id))
end

---------------------------------------------------------------------------
-- GF-011-B 「製作」 (owner 0.16.5: 「接了訂單，按下去應該要可直接開啟對應專業，
-- 方便製作」): open this character's profession window, the order's recipe
-- selected when the client can. Only opening the window: nothing is crafted.
-- Forever's code (WoWBlzCode Forever 1.60.1): the profession window is the
-- LoadOnDemand Blizzard_Professions (ProfessionsFrame);
-- ProfessionsUtil.OpenProfessionFrameToRecipe(recipeID) is what the recipe
-- tracker uses (opens the profession and selects the recipe), then
-- C_TradeSkillUI.OpenRecipe(recipeID), then OpenProfessionUIToSkillLine /
-- C_TradeSkillUI.OpenTradeSkill(skillLineID) (the window, no recipe).
-- No GetNumTradeSkills / GetTradeSkillLine (they are not on Forever).
---------------------------------------------------------------------------

Recipes.CRAFT_LABEL = "製作"
Recipes.CRAFT_TIP = { noprof = "你沒有這個專業", combat = "戰鬥中不能開", noui = "這個用戶端開不了專業視窗" }

local function path(p)
    local t = _G
    for part in p:gmatch("[^%.]+") do
        if type(t) ~= "table" then return nil end
        t = t[part]
    end
    return type(t) == "function" and t or nil
end

-- Does this character have the profession (skillLineID)?
function Recipes.hasProfession(skill)
    skill = tonumber(skill)
    if not skill then return false end
    local list = ns.Data.ownProfessionsDetailed()
    for _, p in ipairs(list or {}) do
        if tonumber(p.skillLineID) == skill then return true end
    end
    return false
end

-- Can 「製作」 open it now? true, or false, why (Recipes.CRAFT_TIP key).
function Recipes.canCraft(skill)
    if not Recipes.hasProfession(skill) then return false, "noprof" end
    if ns.inCombat() then return false, "combat" end
    if not (path("ProfessionsUtil.OpenProfessionFrameToRecipe") or path("C_TradeSkillUI.OpenRecipe")
        or path("OpenProfessionUIToSkillLine") or path("C_TradeSkillUI.OpenTradeSkill")) then
        return false, "noui"
    end
    return true
end

-- Open it. Returns true, how ("recipe" = the recipe selected, "profession" =
-- the window only) or false, why.
function Recipes.openCraft(skill, recipe)
    local can, why = Recipes.canCraft(skill)
    if not can then return false, why end
    recipe = tonumber(recipe)
    if recipe then
        for _, p in ipairs({ "ProfessionsUtil.OpenProfessionFrameToRecipe", "C_TradeSkillUI.OpenRecipe" }) do
            local f = path(p)
            if f then
                local ok, r = pcall(f, recipe)
                if ok and r ~= false then return true, "recipe" end
            end
        end
    end
    for _, p in ipairs({ "OpenProfessionUIToSkillLine", "C_TradeSkillUI.OpenTradeSkill" }) do
        local f = path(p)
        if f then
            local ok, r = pcall(f, tonumber(skill))
            if ok and r ~= false then return true, "profession" end
        end
    end
    return false, "noui"
end

---------------------------------------------------------------------------
-- 「配方」 page
---------------------------------------------------------------------------

local ROW_HEIGHT, RECIPE_ICON, RECIPE_TIP_X = ns.PAGE_ROW, ns.ROW_ICON, 300 -- GF-002-F: 36 px rows, 28 px icons
local panel, scroll, content, search, emptyLine, filterLine, clearFilter
local rowWidgets = {}
local shownRows = {} -- all rows of the current list; only those in view have frames
local lastIndex = {} -- the index the page last drew (option lists use it)
local current = { skills = {}, guid = nil, query = "", online = false }
Recipes.state = current

local function professionName(skill)
    if not skill then return nil end
    return ns.Data.skillName(nil, skill) or ("專業 " .. skill)
end

-- Right-click: 「密語 名字」 for each online crafter (GF-001-D20).
function Recipes.whisperItems(data)
    local items = {}
    for _, m in ipairs(Recipes.onlineCrafters(data and data.crafters)) do
        items[#items + 1] = { text = "密語 " .. ns.shortName(m.name), fn = function() Recipes.whisper(data, m) end }
    end
    return items
end

-- A click on a row (GF-001-D20): Shift = link in chat; my own recipe =
-- open it in my profession window, else (or when that does not work) the
-- recipe pinned; right button = whisper menu.
function Recipes.click(row, button)
    local data = row and row.data
    if not data then return "none" end
    if button == "RightButton" then
        -- GF-006-B (R-5.1): 「下單」 and 「我的工錢」 first, then the whispers.
        local items = ns.OrdersUI and ns.OrdersUI.recipeMenuItems(data) or {}
        -- GF-009-10: 「尋找圖紙」 when the row shows its button.
        local RL = ns.RecipeLink
        if RL and RL.canFind(data) then items[#items + 1] = { text = RL.LABEL, fn = function() RL.find(data) end } end
        for _, it in ipairs(Recipes.whisperItems(data)) do items[#items + 1] = it end
        return ns.showMenu(row, items) and "menu" or "none"
    end
    if type(IsShiftKeyDown) == "function" and IsShiftKeyDown() then
        return Recipes.insertLink(data.id) and "link" or "none"
    end
    if data.mine and Recipes.openOwn(data.id) then return "open" end
    return Recipes.showDetail(data.id) and "detail" or "none"
end

Recipes.ROW_WIDTH = 1030 -- GF-002-E: the wider window
local function newRow(i)
    local row = CreateFrame("Button", nil, content)
    row:SetSize(Recipes.ROW_WIDTH, ROW_HEIGHT)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    -- Hover: a light highlight under the text; the row stays readable.
    if row.SetHighlightTexture then
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    end
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(RECIPE_ICON, RECIPE_ICON)
    row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.name = row:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)
    row.name:SetPoint("LEFT", row, "LEFT", 40, 0)
    row.name:SetWidth(300)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.who = row:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)
    row.who:SetPoint("LEFT", row, "LEFT", Recipes.COL_WHO, 0)
    row.who:SetWidth(Recipes.COL_FEE - Recipes.COL_WHO - 12)
    row.who:SetJustifyH("LEFT")
    row.who:SetWordWrap(false)
    -- GF-002-E: 工錢 (the crafter's quote, R-4.4) and a visible 下單 / 我的工錢 button.
    row.feeTex = row:CreateTexture(nil, "ARTWORK"); row.feeTex:SetSize(18, 18)
    row.feeTex:SetPoint("LEFT", row, "LEFT", Recipes.COL_FEE, 0)
    row.fee = ns.freeText(row:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
    row.fee:SetPoint("LEFT", row, "LEFT", Recipes.COL_FEE + 22, 0)
    row.fee:SetWidth(Recipes.COL_BUTTON - Recipes.COL_FEE - 22 - 12) -- GF-UI-C: never under 下單
    row.fee:SetJustifyH("LEFT")
    row.order = ns.OrdersUI.textButton(row, "我的工錢", function(self) Recipes.pressOrder(self:GetParent() or self.row) end, 104)
    row.order.row = row
    row.order:SetPoint("LEFT", row, "LEFT", Recipes.COL_BUTTON, 0)
    -- GF-009-10: 「尋找圖紙」 (a recipe-item icon after 下單), only when it applies.
    row.pattern = CreateFrame("Button", nil, row)
    row.pattern:SetSize(Recipes.PATTERN_SIZE, Recipes.PATTERN_SIZE)
    row.pattern:SetPoint("LEFT", row, "LEFT", Recipes.COL_PATTERN, 0)
    row.pattern.icon = row.pattern:CreateTexture(nil, "ARTWORK")
    row.pattern.icon:SetAllPoints()
    ns.Icons.set(row.pattern.icon, ns.RecipeLink and ns.RecipeLink.ICON or "Interface\\Icons\\INV_Scroll_03")
    if row.pattern.SetHighlightTexture then
        row.pattern:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    end
    row.pattern:SetScript("OnClick", function(self)
        local data = self:GetParent() and self:GetParent().data or row.data
        if data and ns.RecipeLink then ns.RecipeLink.find(data) end
    end)
    row.pattern:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ns.RecipeLink.LABEL, 1, 0.82, 0)
        GameTooltip:AddLine(ns.RecipeLink.TEXT.tip, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row.pattern:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.pattern:Hide()
    row:EnableMouse(true)
    if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    row:SetScript("OnEnter", function(self)
        local data = self.data
        if not data then return end
        ns.tooltipAbove(self, RECIPE_TIP_X) -- next to the name, not the screen corner
        local shown = false
        if type(GameTooltip.SetSpellByID) == "function" then
            shown = pcall(GameTooltip.SetSpellByID, GameTooltip, data.id)
        end
        if not shown then GameTooltip:AddLine(data.name) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("會做的人", 1, 0.82, 0)
        for _, m in ipairs(data.crafters) do
            local c = m.online and { 0.4, 1, 0.4 } or { 0.8, 0.8, 0.8 }
            GameTooltip:AddLine(ns.shortName(m.name), c[1], c[2], c[3])
        end
        if self.pattern and self.pattern:IsShown() then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("右鍵或圖紙鈕：" .. ns.RecipeLink.LABEL, 1, 0.82, 0)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self, button) Recipes.click(self, button) end)
    rowWidgets[i] = row
    return row
end
Recipes.COL_WHO, Recipes.COL_FEE, Recipes.COL_BUTTON = 350, 720, 900
Recipes.COL_PATTERN, Recipes.PATTERN_SIZE = 1006, 22 -- GF-009-10: after 下單 (900 + 104), inside ROW_WIDTH

-- The row button: 下單 when someone else can make it, else 我的工錢 for my own recipe.
-- GF-UI-B: in the order test mode (同步與診斷 → 測試) my own recipe can be ordered too.
function Recipes.rowAction(data)
    if not data then return nil end
    for _, m in ipairs(data.crafters or {}) do if not m.self then return "order" end end
    if data.mine and ns.Orders and ns.Orders.testOn() then return "order" end
    if data.mine then return "fee" end
    return nil
end
function Recipes.pressOrder(row)
    local data = row and row.data
    local action = Recipes.rowAction(data)
    if action == "order" then
        local pick = ns.OrdersUI.pendingCrafter
        ns.OrdersUI.pendingCrafter, ns.OrdersUI.pendingMark = nil, nil
        return ns.OrdersUI.openOrder({ recipe = data.id, skill = data.skill, crafters = data.crafters, crafter = pick })
    elseif action == "fee" then
        return ns.OrdersUI.editFee({ recipe = data.id, skill = data.skill })
    end
end

function Recipes.professionsInIndex(index)
    local list = {}
    for skill in pairs(index) do list[#list + 1] = skill end
    table.sort(list, function(a, b)
        local sa, sb = ns.Professions.isSecondary({ skillLineID = a }), ns.Professions.isSecondary({ skillLineID = b })
        if sa ~= sb then return not sa end
        return a < b
    end)
    return list
end

-- Professions on the page: the ones in the index (only the member's own
-- when the page is filtered to one member).
function Recipes.pageSkills(index)
    local skills = Recipes.professionsInIndex(index)
    if not current.guid then return skills end
    local mine = {}
    for _, s in ipairs(skills) do
        for _, c in ipairs(index[s].crafters) do if c.guid == current.guid then mine[#mine + 1] = s; break end end
    end
    return mine
end

function Recipes.skillOptions()
    local list = {}
    for _, s in ipairs(Recipes.pageSkills(lastIndex)) do
        list[#list + 1] = { value = s, text = professionName(s), icon = ns.Icons.professionIcon(s) }
    end
    return list
end

-- The ticked professions among those on the page (all by default).
function Recipes.selectedSkills(skills)
    local b = Recipes.skillChoice
    if not b then return skills end
    local out = {}
    for _, s in ipairs(skills) do if b.isOn(s) then out[#out + 1] = s end end
    return out
end

-- "全部專業" / "烹飪" / "3 個專業" / "未選" (GF-UI-B: 2-4 characters)
function Recipes.skillSummary(b)
    local list = b.options()
    if b.selected == nil then return "全部專業" end
    local on = {}
    for _, o in ipairs(list) do if b.isOn(o.value) then on[#on + 1] = o end end
    if #on == 0 then return "未選" end
    if #on == #list then return "全部專業" end
    if #on == 1 then return on[1].text end
    return #on .. " 個專業"
end

Recipes.WHO_OPTIONS = {
    { value = "me", text = "我" },
    { value = "others", text = "別人" },
}

-- 會做的人 as rows() wants it: nil (both), "mine", "others" or "none".
function Recipes.whoFilter()
    local b = Recipes.whoChoice
    if not b or b.selected == nil then return nil end
    local me, others = b.isOn("me"), b.isOn("others")
    if me and others then return nil end
    if me then return "mine" end
    if others then return "others" end
    return "none"
end

-- GF-UI-B: 2-4 characters on the button.
function Recipes.whoSummary()
    local w = Recipes.whoFilter()
    if w == "mine" then return "我的" end
    if w == "others" then return "別人的" end
    if w == "none" then return "未選" end
    return "所有人"
end

-- Fill the pooled rows with the recipes in view (GF-001-D14).
function Recipes.layoutRows()
    if not scroll then return end
    local offset = ns.num((scroll:GetVerticalScroll())) or 0
    local h = ns.num((scroll:GetHeight())) or 0
    if h <= 0 then h = 400 end
    local count = math.ceil(h / ROW_HEIGHT) + 1
    local first = math.max(1, math.floor(offset / ROW_HEIGHT) + 1)
    local RL = ns.RecipeLink
    local ctx = RL and RL.context() -- GF-009-10: one read of my professions per pass
    for k = 1, math.max(count, #rowWidgets) do
        local i = first + k - 1
        local data = k <= count and shownRows[i] or nil
        local row = rowWidgets[k] or (data and newRow(k)) or nil
        if row then
            if data then
                row.data = data
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
                ns.stripe(row.bg, i) -- GF-UI-B: the shared stripe
                Recipes.setIcon(row.icon, data.id, data.skill)
                row.name:SetText(data.name)
                row.who:SetText(Recipes.crafterText(data.crafters, data.skill))
                local online = data.crafters[1] and data.crafters[1].online
                if online then row.who:SetTextColor(0.4, 1, 0.4) else row.who:SetTextColor(0.8, 0.8, 0.8) end
                local fee = Recipes.rowFee(data)
                ns.OrdersUI.showFee(row.feeTex, row.fee, fee)
                row.fee:SetText(ns.OrdersUI.feeText(fee))
                local action = Recipes.rowAction(data)
                if action then
                    row.order:SetText(action == "order" and "下單" or "我的工錢")
                    row.order.action = action
                    row.order:Show()
                else
                    row.order:Hide(); row.order.action = nil
                end
                local pattern = RL and RL.canFind(data, ctx) or nil
                row.pattern.itemID = pattern
                if pattern then row.pattern:Show() else row.pattern:Hide() end
                row:Show()
            else
                row:Hide(); row.data = nil
            end
        end
    end
end
function Recipes.rowFrames() return rowWidgets end
-- All rows of the current list (offline tests).
function Recipes.shownRows() return shownRows end

-- GF-UI-B (GF-UI-A §2.3 item 2): short names in the middle of the list,
-- never sentences; with no profession ticked, a grey profession icon.
Recipes.BUILDING_TEXT = "整理中"
Recipes.EMPTY_TEXT = { none = "沒有配方", noSkill = "未選專業", noMatch = "找不到" }
local function setEmpty(text, icon)
    emptyLine:SetText(text or "")
    if Recipes.emptyIcon then
        if icon then
            ns.Icons.set(Recipes.emptyIcon, icon)
            if Recipes.emptyIcon.SetDesaturated then Recipes.emptyIcon:SetDesaturated(true) end
            Recipes.emptyIcon:Show()
        else
            Recipes.emptyIcon:Hide()
        end
    end
end

function Recipes.refresh()
    if not panel then return end
    local index = Recipes.indexSoon(function()
        if ns.Framework.isModuleShown("recipes") then Recipes.refresh() end
    end)
    if not index then
        shownRows = {}
        content:SetHeight(1)
        Recipes.layoutRows()
        setEmpty(Recipes.BUILDING_TEXT)
        filterLine:SetText("")
        clearFilter:Hide()
        return
    end
    lastIndex = index
    local skills = Recipes.pageSkills(index)
    local chosen = Recipes.selectedSkills(skills)
    current.skills = chosen
    if Recipes.skillChoice then Recipes.skillChoice.refreshText() end
    if Recipes.whoChoice then Recipes.whoChoice.refreshText() end
    local opts = { online = current.online, who = Recipes.whoFilter(), active = current.active, fee = current.fee }
    local rows = Recipes.rowsFor(index, chosen, current.query, current.guid, opts)
    shownRows = rows
    content:SetHeight(math.max(1, #rows * ROW_HEIGHT))
    Recipes.layoutRows()
    local filtered = current.query ~= "" or current.online or opts.who ~= nil or current.active or current.fee ~= nil
    if #skills == 0 then
        setEmpty(Recipes.EMPTY_TEXT.none)
    elseif #chosen == 0 then
        setEmpty(Recipes.EMPTY_TEXT.noSkill, ns.RECIPE_ICON or "Interface\\Icons\\INV_Scroll_04")
    elseif #rows == 0 then
        setEmpty(filtered and Recipes.EMPTY_TEXT.noMatch or Recipes.EMPTY_TEXT.none)
    else
        setEmpty("")
    end
    if current.guid then
        local name
        for _, m in ipairs((ns.Roster.current() or { members = {} }).members) do
            if m.guid == current.guid then name = m.name end
        end
        -- GF-UI-B: 「只看：名字」 and a short 「全部」 button (was 「看全部的人」).
        filterLine:SetText("只看：" .. ns.shortName(name or "?"))
        clearFilter:Show()
    else
        filterLine:SetText(#chosen > 0 and string.format("%d 個配方", #rows) or "")
        clearFilter:Hide()
    end
end

Recipes.SEARCH_DELAY = 0.15

-- Open the page, optionally on one member (GUID) and one profession (then
-- only that one is ticked).
function Recipes.show(guid, skill)
    current.guid = guid
    ns.Framework.open("recipes")
    if skill and Recipes.skillChoice then Recipes.skillChoice.selected = { [skill] = true } end
    Recipes.refresh()
end

-- GF-001-D20 layout: one filter line at the top, like the roster's:
-- 搜尋 [box]  專業 [v]  會做的人 [v]  [ ] 只看在線   N 個配方
local FILTER_Y = -44

local function label(p, text, x, y)
    local l = ns.freeText(p:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT))
    l:SetPoint("TOPLEFT", p, "TOPLEFT", x, (y or FILTER_Y) - 6)
    l:SetText(text)
    return l
end
local FILTER_Y2 = FILTER_Y - 38
-- GF-UI-C (owner: 「選項沒對齊」): one grid for both filter lines. Four
-- columns 250 px apart; a field name at the column's x, its control 80 px
-- further (room for 4 characters); check boxes at the column's x.
Recipes.COLS, Recipes.CONTROL_DX = { 22, 272, 522, 772 }, 80

local function build(p)
    local C, DX = Recipes.COLS, Recipes.CONTROL_DX
    label(p, "搜尋", C[1])
    search = ns.Theme.editBox(p)
    search:SetSize(150, 30)
    search:SetPoint("TOPLEFT", p, "TOPLEFT", C[1] + DX, FILTER_Y)
    search:SetAutoFocus(false)
    search:SetMaxLetters(60)
    -- GF-FIX-C (review mid-28): the first key redraws at once; keys within SEARCH_DELAY make one more redraw.
    search:SetScript("OnTextChanged", function(self)
        current.query = str(self:GetText())
        Recipes.soon("search", Recipes.SEARCH_DELAY, function() if panel then Recipes.refresh() end end)
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    Recipes.searchBox = search
    label(p, "專業", C[2])
    -- GF-001-D22: check boxes (several professions at once), with icons.
    Recipes.skillChoice = ns.multiChoiceButton(p, 130, C[2] + DX, FILTER_Y, Recipes.skillOptions,
        function() Recipes.refresh() end, Recipes.skillSummary)
    label(p, "會做的人", C[3])
    Recipes.whoChoice = ns.multiChoiceButton(p, 130, C[3] + DX, FILTER_Y, function() return Recipes.WHO_OPTIONS end,
        function() Recipes.refresh() end, Recipes.whoSummary)
    -- Second line: the check boxes under 搜尋 and 專業, 工錢 under 會做的人.
    Recipes.onlineCheck = ns.checkBox(p, "只看在線", C[1], FILTER_Y2, function(on) current.online = on; Recipes.refresh() end)
    -- GF-002-E (owner: 「工錢應直接顯示，且可篩選」): second line.
    -- GF-UI-B: a hammer and 「接單中」 (was the 5-character 「只看接單中」).
    Recipes.activeCheck = ns.checkBox(p, "接單中", C[2], FILTER_Y2,
        function(on) current.active = on; Recipes.refresh() end)
    label(p, "工錢", C[3], FILTER_Y2)
    Recipes.feeChoice = ns.choiceButton(p, 130, C[3] + DX, FILTER_Y2, function() return Recipes.FEE_OPTIONS end,
        function(v) current.fee = v; Recipes.refresh() end, "工錢不限")
    filterLine = ns.freeText(p:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT))
    filterLine:SetPoint("TOPLEFT", p, "TOPLEFT", C[4], FILTER_Y - 5)
    filterLine:SetJustifyH("LEFT")
    clearFilter = ns.OrdersUI.textButton(p, "全部", function() current.guid = nil; Recipes.refresh() end)
    clearFilter:SetPoint("TOPLEFT", p, "TOPLEFT", 960, FILTER_Y - 1)
    clearFilter:Hide()
    Recipes.clearFilterButton = clearFilter
    local HEAD_Y = -122
    for _, h in ipairs({ { "配方", 52 }, { "會做的人", 20 + Recipes.COL_WHO }, { "工錢", 20 + Recipes.COL_FEE } }) do
        local fs = ns.freeText(p:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT))
        fs:SetPoint("TOPLEFT", p, "TOPLEFT", h[2], HEAD_Y)
        fs:SetText(h[1])
    end
    scroll = ns.createFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -144)
    scroll:SetPoint("BOTTOMRIGHT", -40, 24)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(Recipes.ROW_WIDTH, 1)
    scroll:SetScrollChild(content)
    scroll:HookScript("OnVerticalScroll", function() Recipes.layoutRows() end)
    Recipes.emptyIcon = p:CreateTexture(nil, "ARTWORK")
    Recipes.emptyIcon:SetSize(48, 48)
    Recipes.emptyIcon:SetPoint("TOP", p, "TOP", 0, -170)
    Recipes.emptyIcon:Hide()
    emptyLine = p:CreateFontString(nil, "ARTWORK", ns.TITLE_FONT)
    emptyLine:SetPoint("TOP", p, "TOP", 0, -226)
    panel = p -- last: refresh() needs every widget above
end

ns.Framework.register({
    id = "recipes",
    title = "配方",
    order = 12,
    available = function() return ns.guildState() == "target" end,
    create = build,
    show = function() Recipes.refresh() end,
})

-- Redraw at most once a second while data arrives (GF-001-D11).
Share.onUpdate(function()
    if panel and ns.Framework.isModuleShown("recipes") then
        ns.coalesce("recipes-page", 1, function()
            if ns.Framework.isModuleShown("recipes") then Recipes.refresh() end
        end)
    end
end)
