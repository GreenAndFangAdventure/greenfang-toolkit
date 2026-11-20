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

local filterWarned = {}

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
    local a = Share.selfAuthor()
    if not a or not Share.store() then return "unknown" end
    local g = "R" .. skill
    local old = Share.get(a, g)
    local oldIDs = old and Share.decodeValue(g, old.v) or nil
    if oldIDs and #ids < #oldIDs and isSubset(ids, oldIDs) then
        if not filterWarned[skill] then
            filterWarned[skill] = true
            ns.say(string.format("%s視窗目前有篩選，配方清單沒有更新（取消篩選後再開一次即可）。",
                ns.Data.skillName(nil, skill) or "專業"))
        end
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
        selfGuid = ns.Data.player().guid }
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
function Recipes.rows(index, skill, query, onlyGuid)
    local p = index[skill]
    local rows = {}
    if not p then return rows end
    local q = ns.keyName(query)
    for id, who in pairs(p.recipes) do
        local list = {}
        for _, m in ipairs(who) do
            if not onlyGuid or m.guid == onlyGuid then list[#list + 1] = m end
        end
        if #list > 0 then
            local name = Recipes.name(id)
            if q == "" or ns.keyName(name):find(q, 1, true) then
                rows[#rows + 1] = { id = id, name = name, crafters = list } -- already online first
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

---------------------------------------------------------------------------
-- 「配方」 page
---------------------------------------------------------------------------

local ROW_HEIGHT, MAX_TABS = 22, 9
local panel, scroll, content, search, emptyLine, filterLine, clearFilter, footer
local tabs, rowWidgets = {}, {}
local shownRows = {} -- all rows of the current list; only those in view have frames
local current = { skill = nil, guid = nil, query = "" }
Recipes.state = current

local function professionName(skill) return ns.Data.skillName(nil, skill) or ("專業 " .. skill) end

local function newRow(i)
    local row = CreateFrame("Frame", nil, content)
    row:SetSize(930, ROW_HEIGHT)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.name:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.name:SetWidth(420)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.who = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.who:SetPoint("LEFT", row, "LEFT", 440, 0)
    row.who:SetWidth(480)
    row.who:SetJustifyH("LEFT")
    row.who:SetWordWrap(false)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        local data = self.data
        if not data then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local shown = false
        if type(GameTooltip.SetSpellByID) == "function" then
            shown = pcall(GameTooltip.SetSpellByID, GameTooltip, data.id)
        end
        if not shown then GameTooltip:AddLine(data.name) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("會做的人", 1, 0.82, 0)
        for _, m in ipairs(data.crafters) do
            local c = m.online and { 0.4, 1, 0.4 } or { 0.8, 0.8, 0.8 }
            local note = Recipes.agoText(m.t) .. "記錄" .. (m.relayed and "，公會成員轉傳" or "")
            GameTooltip:AddLine(string.format("%s（%s）", ns.shortName(m.name), note), c[1], c[2], c[3])
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rowWidgets[i] = row
    return row
end

local function newTab(i)
    local b = ns.createFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(100, 24)
    b:SetPoint("TOPLEFT", panel, "TOPLEFT", 20 + (i - 1) * 104, -40)
    tabs[i] = b
    return b
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
        for _, b in ipairs(tabs) do b:Hide() end
        shownRows = {}
        content:SetHeight(1)
        Recipes.layoutRows()
        emptyLine:SetText(Recipes.BUILDING_TEXT)
        filterLine:SetText("")
        clearFilter:Hide()
        return
    end
    local skills = Recipes.professionsInIndex(index)
    if current.guid then
        -- Filtered to one member: only professions that member shared.
        local mine = {}
        for _, s in ipairs(skills) do
            for _, c in ipairs(index[s].crafters) do if c.guid == current.guid then mine[#mine + 1] = s; break end end
        end
        skills = mine
    end
    local found = false
    for _, s in ipairs(skills) do if s == current.skill then found = true end end
    if not found then current.skill = skills[1] end
    for i = 1, math.max(#skills, #tabs) do
        local s = skills[i]
        local b = tabs[i] or (i <= MAX_TABS and s and newTab(i)) or nil
        if b then
            if s and i <= MAX_TABS then
                b:SetText(professionName(s))
                b:SetScript("OnClick", function() current.skill = s; Recipes.refresh() end)
                if b.SetEnabled then b:SetEnabled(s ~= current.skill) end
                b.skill = s
                b:Show()
            else
                b:Hide()
            end
        end
    end
    local rows = current.skill and Recipes.rows(index, current.skill, current.query, current.guid) or {}
    shownRows = rows
    content:SetHeight(math.max(1, #rows * ROW_HEIGHT))
    Recipes.layoutRows()
    if #skills == 0 then
        emptyLine:SetText(current.guid and "這位成員還沒有分享配方。"
            or "還沒有人分享配方。打開自己的專業視窗，就會分享你的配方。")
    elseif #rows == 0 then
        emptyLine:SetText(current.query ~= "" and "找不到符合的配方。" or "這個專業還沒有配方資料。")
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
        filterLine:SetText(current.skill and string.format("%s｜%d 個配方", professionName(current.skill), #rows) or "")
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

local function build(p)
    panel = p
    search = ns.createFrame("EditBox", nil, p, "InputBoxTemplate")
    search:SetSize(260, 24)
    search:SetPoint("TOPLEFT", p, "TOPLEFT", 70, -74)
    search:SetAutoFocus(false)
    search:SetMaxLetters(60)
    search:SetScript("OnTextChanged", function(self) current.query = str(self:GetText()); Recipes.refresh() end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    Recipes.searchBox = search
    local label = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", p, "TOPLEFT", 22, -80)
    label:SetText("搜尋")
    filterLine = p:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    filterLine:SetPoint("TOPLEFT", p, "TOPLEFT", 350, -80)
    filterLine:SetJustifyH("LEFT")
    clearFilter = ns.createFrame("Button", nil, p, "UIPanelButtonTemplate")
    clearFilter:SetSize(110, 22)
    clearFilter:SetPoint("TOPLEFT", p, "TOPLEFT", 560, -75)
    clearFilter:SetText("看全部的人")
    clearFilter:SetScript("OnClick", function() current.guid = nil; Recipes.refresh() end)
    clearFilter:Hide()
    Recipes.clearFilterButton = clearFilter
    local header = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", p, "TOPLEFT", 28, -108)
    header:SetText("配方")
    local header2 = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    header2:SetPoint("TOPLEFT", p, "TOPLEFT", 460, -108)
    header2:SetText("會做的人（在線的在前）")
    scroll = ns.createFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -126)
    scroll:SetPoint("BOTTOMRIGHT", -40, 44)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(930, 1)
    scroll:SetScrollChild(content)
    scroll:HookScript("OnVerticalScroll", function() Recipes.layoutRows() end)
    emptyLine = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    emptyLine:SetPoint("TOP", p, "TOP", 0, -170)
    footer = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    footer:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 22, 18)
    footer:SetWidth(940)
    footer:SetJustifyH("LEFT")
    footer:SetText("配方由公會內有裝工具箱的人分享與轉傳；打開自己的專業視窗就會更新。你的配方也會分享給公會成員。")
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
