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
    local r = Share.ownRecord(g, Share.encodeValue(g, ids))
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

local readTimers = {}
function Recipes.scanSoon()
    if not Recipes.isOwnWindow() then return end
    local skill = Recipes.openSkillLine() or 0
    Recipes.scan()
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
local building -- { version, snap, ordered, pos, out, selfGuid }

local function startBuild(snap)
    local ordered = {}
    for _, m in ipairs(snap.members) do ordered[#ordered + 1] = { m = m, key = ns.keyName(m.name) } end
    table.sort(ordered, function(x, y)
        if (x.m.online == true) ~= (y.m.online == true) then return x.m.online == true end
        return x.key < y.key
    end)
    return { version = Share.version, snap = snap, ordered = ordered, pos = 1, out = {},
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

local function isFresh(snap)
    return indexCache.out and indexCache.version == Share.version and indexCache.snap == snap
end

-- The whole index now (tests and callers that need it at once).
function Recipes.index()
    local snap = ns.Roster.current()
    if not snap then return {} end
    if isFresh(snap) then return indexCache.out end
    local b = startBuild(snap)
    work(b, nil)
    indexCache = { version = b.version, snap = snap, out = b.out, at = ns.now(), steps = 1 }
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
    indexCache = { version = b.version, snap = b.snap, out = b.out, at = ns.now(), steps = b.steps }
    return true
end

function Recipes.indexSoon(onDone)
    local snap = ns.Roster.current()
    if not snap then return {} end
    if isFresh(snap) then return indexCache.out end
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

-- Rows for one profession: { { id, name, crafters } }, filtered and sorted by name.
-- opts (GF-001-D19): online = only crafters who are online; who = "mine"
-- (only recipes I know) or "others" (only other members).
function Recipes.rows(index, skill, query, onlyGuid, opts)
    local p = index[skill]
    local rows = {}
    if not p then return rows end
    opts = opts or {}
    local q = ns.keyName(query)
    for id, who in pairs(p.recipes) do
        local list, mine = {}, false
        for _, m in ipairs(who) do
            if m.self then mine = true end
            local keep = (not onlyGuid or m.guid == onlyGuid)
                and (not opts.online or m.online)
                and (opts.who ~= "others" or not m.self)
            if keep then list[#list + 1] = m end
        end
        if #list > 0 and (opts.who ~= "mine" or mine) then
            local name = Recipes.name(id)
            if q == "" or ns.keyName(name):find(q, 1, true) then
                rows[#rows + 1] = { id = id, name = name, crafters = list, mine = mine } -- already online first
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return rows
end

-- "測試甲、測試乙 +2" (online first, at most 3 names).
function Recipes.crafterText(list)
    local names = {}
    for i = 1, math.min(3, #list) do names[i] = ns.shortName(list[i].name) end
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
-- 「配方」 page
---------------------------------------------------------------------------

local ROW_HEIGHT, RECIPE_ICON, RECIPE_TIP_X = 22, 20, 300
local panel, scroll, content, search, emptyLine, filterLine, clearFilter
local rowWidgets = {}
local shownRows = {} -- all rows of the current list; only those in view have frames
local lastIndex = {} -- the index the page last drew (option lists use it)
local current = { skill = nil, guid = nil, query = "", online = false, who = nil }
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
        return ns.showMenu(row, Recipes.whisperItems(data)) and "menu" or "none"
    end
    if type(IsShiftKeyDown) == "function" and IsShiftKeyDown() then
        return Recipes.insertLink(data.id) and "link" or "none"
    end
    if data.mine and Recipes.openOwn(data.id) then return "open" end
    return Recipes.showDetail(data.id) and "detail" or "none"
end

local function newRow(i)
    local row = CreateFrame("Button", nil, content)
    row:SetSize(930, ROW_HEIGHT)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    -- Hover: a light highlight under the text; the row stays readable.
    if row.SetHighlightTexture then
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    end
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(RECIPE_ICON, RECIPE_ICON)
    row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.name:SetPoint("LEFT", row, "LEFT", 32, 0)
    row.name:SetWidth(396)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.who = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.who:SetPoint("LEFT", row, "LEFT", 440, 0)
    row.who:SetWidth(480)
    row.who:SetJustifyH("LEFT")
    row.who:SetWordWrap(false)
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
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self, button) Recipes.click(self, button) end)
    rowWidgets[i] = row
    return row
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
        list[#list + 1] = { value = s, text = professionName(s) }
    end
    if #list == 0 then list[1] = { value = nil, text = "專業" } end
    return list
end

-- Fill the pooled rows with the recipes in view (GF-001-D14).
function Recipes.layoutRows()
    if not scroll then return end
    local offset = ns.num((scroll:GetVerticalScroll())) or 0
    local h = ns.num((scroll:GetHeight())) or 0
    if h <= 0 then h = 400 end
    local count = math.ceil(h / ROW_HEIGHT) + 1
    local first = math.max(1, math.floor(offset / ROW_HEIGHT) + 1)
    for k = 1, math.max(count, #rowWidgets) do
        local i = first + k - 1
        local data = k <= count and shownRows[i] or nil
        local row = rowWidgets[k] or (data and newRow(k)) or nil
        if row then
            if data then
                row.data = data
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
                row.bg:SetColorTexture(0.17, 0.2, 0.18, i % 2 == 0 and 0.35 or 0.09)
                Recipes.setIcon(row.icon, data.id, current.skill)
                row.name:SetText(data.name)
                row.who:SetText(Recipes.crafterText(data.crafters))
                local online = data.crafters[1] and data.crafters[1].online
                if online then row.who:SetTextColor(0.4, 1, 0.4) else row.who:SetTextColor(0.8, 0.8, 0.8) end
                row:Show()
            else
                row:Hide(); row.data = nil
            end
        end
    end
end
function Recipes.rowFrames() return rowWidgets end

Recipes.BUILDING_TEXT = "配方整理中，請稍候。"

function Recipes.refresh()
    if not panel then return end
    local index = Recipes.indexSoon(function()
        if ns.Framework.isModuleShown("recipes") then Recipes.refresh() end
    end)
    if not index then
        shownRows = {}
        content:SetHeight(1)
        Recipes.layoutRows()
        emptyLine:SetText(Recipes.BUILDING_TEXT)
        filterLine:SetText("")
        clearFilter:Hide()
        return
    end
    lastIndex = index
    local skills = Recipes.pageSkills(index)
    local found = false
    for _, s in ipairs(skills) do if s == current.skill then found = true end end
    if not found then current.skill = skills[1] end
    if Recipes.skillChoice then
        Recipes.skillChoice.value = current.skill
        Recipes.skillChoice.refreshText()
    end
    local opts = { online = current.online, who = current.who }
    local rows = current.skill and Recipes.rows(index, current.skill, current.query, current.guid, opts) or {}
    shownRows = rows
    content:SetHeight(math.max(1, #rows * ROW_HEIGHT))
    Recipes.layoutRows()
    local filtered = current.query ~= "" or current.online or current.who ~= nil
    if #skills == 0 then
        emptyLine:SetText(current.guid and "這位成員還沒有分享配方。" or "還沒有人分享配方。")
    elseif #rows == 0 then
        emptyLine:SetText(filtered and "找不到符合的配方。" or "這個專業還沒有配方資料。")
    else
        emptyLine:SetText("")
    end
    if current.guid then
        local name
        for _, m in ipairs((ns.Roster.current() or { members = {} }).members) do
            if m.guid == current.guid then name = m.name end
        end
        filterLine:SetText("只看：" .. ns.shortName(name or "?"))
        clearFilter:Show()
    else
        filterLine:SetText(current.skill and string.format("%d 個配方", #rows) or "")
        clearFilter:Hide()
    end
end

-- Open the page, optionally on one member (GUID) and one profession.
function Recipes.show(guid, skill)
    current.guid = guid
    if skill then current.skill = skill end
    ns.Framework.open("recipes")
    Recipes.refresh()
end

Recipes.WHO_OPTIONS = {
    { value = nil, text = "所有人" },
    { value = "mine", text = "只看我的" },
    { value = "others", text = "只看別人的" },
}

-- GF-001-D20 layout: one filter line at the top, like the roster's:
-- 搜尋 [box]  專業 [▼]  會做的人 [▼]  [ ] 只看在線   N 個配方
local FILTER_Y = -44

local function label(p, text, x)
    local l = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    l:SetPoint("TOPLEFT", p, "TOPLEFT", x, FILTER_Y - 6)
    l:SetText(text)
    return l
end

local function build(p)
    label(p, "搜尋", 22)
    search = ns.createFrame("EditBox", nil, p, "InputBoxTemplate")
    search:SetSize(180, 24)
    search:SetPoint("TOPLEFT", p, "TOPLEFT", 62, FILTER_Y)
    search:SetAutoFocus(false)
    search:SetMaxLetters(60)
    search:SetScript("OnTextChanged", function(self) current.query = str(self:GetText()); Recipes.refresh() end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    Recipes.searchBox = search
    label(p, "專業", 262)
    Recipes.skillChoice = ns.choiceButton(p, 120, 300, FILTER_Y, Recipes.skillOptions,
        function(value) if value then current.skill = value end; Recipes.refresh() end, nil, professionName)
    label(p, "會做的人", 440)
    Recipes.whoChoice = ns.choiceButton(p, 110, 500, FILTER_Y, function() return Recipes.WHO_OPTIONS end,
        function(value) current.who = value; Recipes.refresh() end, "所有人")
    Recipes.onlineCheck = ns.checkBox(p, "只看在線", 628, FILTER_Y, function(on) current.online = on; Recipes.refresh() end)
    filterLine = p:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    filterLine:SetPoint("TOPLEFT", p, "TOPLEFT", 724, FILTER_Y - 5)
    filterLine:SetJustifyH("LEFT")
    clearFilter = ns.createFrame("Button", nil, p, "UIPanelButtonTemplate")
    clearFilter:SetSize(100, 22)
    clearFilter:SetPoint("TOPLEFT", p, "TOPLEFT", 840, FILTER_Y - 1)
    clearFilter:SetText("看全部的人")
    clearFilter:SetScript("OnClick", function() current.guid = nil; Recipes.refresh() end)
    clearFilter:Hide()
    Recipes.clearFilterButton = clearFilter
    local header = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", p, "TOPLEFT", 52, -82)
    header:SetText("配方")
    local header2 = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    header2:SetPoint("TOPLEFT", p, "TOPLEFT", 460, -82)
    header2:SetText("會做的人")
    scroll = ns.createFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -100)
    scroll:SetPoint("BOTTOMRIGHT", -40, 24)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(930, 1)
    scroll:SetScrollChild(content)
    scroll:HookScript("OnVerticalScroll", function() Recipes.layoutRows() end)
    emptyLine = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    emptyLine:SetPoint("TOP", p, "TOP", 0, -150)
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
