-- GF-DIGEST-01: /gftkdev traits, the IDs of this character's talent tree as
-- copyable text, so claude-pm and the website can tell which C_Traits ID
-- (node, entry, definition, spell) matches the Blizzard API's talent ID and
-- the site catalog's node ID (guild-digest.md §4b tn / ti, §9-8).
-- Dev AddOn only; members never see it.
--
--   /gftkdev traits        read the tree now and show part 1
--   /gftkdev traits <n>    show part n of the last read (no new read)
--
-- Runs only on the command: no events, no timers, no OnUpdate. Refused in
-- combat. The text has no character name, account name, GUID or loadout name
-- (the class token, build, IDs, spec and spell names only).
--
-- Output, one line per node, ASCII except spec and spell names:
--   GF-TRAITDUMP v1 lines=<all lines> parts=<n>
--   H <key>=<value> ...                 header (class, build, config, tree)
--   S <index> id=<specID> name=<name> active=<0|1>       specializations
--   G <tab> id=<groupID> name=<name> spent=<points>     tabs (game order)
--   N <nodeID> tab=<k|-> grp=<groupID,...|-> rank=<cur>/<max> ... E=<entry>:<def>:<spell>:<name>;... by=<how>
--     grp = every groupID of the node (GF-011-C); tab = the tab the toolkit
--     counts it in (Talents.assignTabs when the toolkit is loaded), by = how:
--     group (a tab's own group), sub (a sub-group shared with such a node),
--     pos (posX between the tabs), - (未分組), direct (toolkit not loaded:
--     a tab's own group only)
--   ! MISSING <api> / ! EMPTY <api> n=<count> first=<args>
-- A value the client did not give is "?". Not checked in the Forever client:
-- the field names follow Talents.lua / Probe.lua and the retail C_Traits docs.
local _, D = ...
local T = {}
D.TraitDump = T

T.VERSION = 1
T.MAX_NODES = 1500
T.PART_LIMIT = 14000 -- characters per copyable part (Export.PART_LIMIT is 14500)
T.WINDOW_NAME = "GreenFangToolkitDev_TraitWindow"

local function say(text)
    if D.CatalogScan and D.CatalogScan.say then return D.CatalogScan.say(text) end
    print("|cff7fbf3fGF Dev|r " .. tostring(text))
end

local function num(v)
    if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end

local function resolve(path)
    local t = _G
    for part in path:gmatch("[^%.]+") do
        if type(t) ~= "table" then return nil end
        t = t[part]
    end
    return type(t) == "function" and t or nil
end

-- Text for one value: numbers as integers when whole, "?" for nothing,
-- strings without line breaks, tabs, "=" or ";" (they separate fields).
local function v(x)
    if x == nil then return "?" end
    if type(x) == "boolean" then return x and "1" or "0" end
    if type(x) == "number" then
        if x == math.floor(x) then return string.format("%d", x) end
        return string.format("%.3f", x)
    end
    local s = tostring(x):gsub("[\r\n\t]", " "):gsub("[=;]", "_")
    if s == "" then return "?" end
    return s
end

---------------------------------------------------------------------------
-- Reading (one pass; every call through pcall, every gap written down)
---------------------------------------------------------------------------

local function newReader()
    local r = { missing = {}, missingOrder = {}, empty = {}, emptyOrder = {} }
    -- Call the API at path: its values, or nothing (and noted as MISSING when
    -- the function does not exist, EMPTY when it errors or gives nil).
    function r.call(path, ...)
        local f = resolve(path)
        if not f then
            if not r.missing[path] then r.missing[path] = true; r.missingOrder[#r.missingOrder + 1] = path end
            return nil
        end
        local res = { pcall(f, ...) }
        if not res[1] or res[2] == nil then
            local e = r.empty[path]
            if not e then
                local args = {}
                for i = 1, select("#", ...) do
                    local a = select(i, ...)
                    args[#args + 1] = type(a) == "table" and "{}" or v(a)
                end
                e = { n = 0, first = table.concat(args, ","), err = not res[1] }
                r.empty[path] = e
                r.emptyOrder[#r.emptyOrder + 1] = path
            end
            e.n = e.n + 1
            return nil
        end
        return unpack(res, 2, table.maxn(res))
    end
    return r
end

local function spellName(r, id)
    if not id or id <= 0 then return nil end
    if resolve("C_Spell.GetSpellName") then
        local name = r.call("C_Spell.GetSpellName", id)
        if type(name) == "string" and name ~= "" then return name end
        return nil
    end
    if resolve("C_Spell.GetSpellInfo") then
        local info = r.call("C_Spell.GetSpellInfo", id)
        return type(info) == "table" and type(info.name) == "string" and info.name or nil
    end
    local name = r.call("GetSpellInfo", id)
    return type(name) == "string" and name or nil
end

local function activeConfig(r)
    local cfg = num((r.call("C_ClassTalents.GetActiveConfigID")))
    local how = "C_ClassTalents.GetActiveConfigID"
    if not cfg then
        local group = num((r.call("C_SpecializationInfo.GetActiveSpecGroup")))
        if group then
            cfg = num((r.call("C_SpecializationInfo.GetCombatConfigIDForSpecGroup", group)))
            how = "C_SpecializationInfo.GetCombatConfigIDForSpecGroup"
        end
    end
    return cfg, cfg and how or nil
end

-- Specializations the client lists: { { index, id, name, active } }.
local function specs(r)
    local out = {}
    local active = num((r.call("C_SpecializationInfo.GetSpecialization")))
    local n = num((r.call("GetNumSpecializations")))
    if not n then
        local _, _, classID = r.call("UnitClass", "player")
        if num(classID) then n = num((r.call("C_SpecializationInfo.GetNumSpecializationsForClassID", classID))) end
    end
    for i = 1, math.min(n or 0, 6) do
        local id, name = r.call("C_SpecializationInfo.GetSpecializationInfo", i)
        out[#out + 1] = { index = i, id = num(id), name = type(name) == "string" and name or nil, active = active == i }
    end
    return out, active, n
end

-- Read the whole tree. Returns a table of lines (without the first line).
function T.collect()
    local r = newReader()
    local L = {}
    local function add(s) L[#L + 1] = s end

    local _, classToken, classID = r.call("UnitClass", "player")
    local version, build, _, toc = r.call("GetBuildInfo")
    add(string.format("H class=%s classID=%s version=%s build=%s toc=%s", v(classToken), v(num(classID)),
        v(version), v(build), v(num(toc))))

    local specList, activeSpec, specCount = specs(r)
    add(string.format("H specCount=%s activeSpecIndex=%s", v(specCount), v(activeSpec)))
    for _, s in ipairs(specList) do
        add(string.format("S %d id=%s name=%s active=%s", s.index, v(s.id), v(s.name), v(s.active)))
    end

    local cfg, how = activeConfig(r)
    local info = cfg and r.call("C_Traits.GetConfigInfo", cfg) or nil
    local trees = type(info) == "table" and type(info.treeIDs) == "table" and info.treeIDs or {}
    local tree = num(trees[1])
    local treeIDs = {}
    for _, t in ipairs(trees) do treeIDs[#treeIDs + 1] = v(num(t)) end
    add(string.format("H configID=%s configFrom=%s configType=%s treeID=%s treeIDs=%s", v(cfg), v(how),
        v(type(info) == "table" and num(info.type) or nil), v(tree), #treeIDs > 0 and table.concat(treeIDs, ",") or "?"))
    if activeSpec then
        local specID = specList[activeSpec] and specList[activeSpec].id
        if specID then
            add(string.format("H specTree=%s", v(num((r.call("C_ClassTalents.GetTraitTreeForSpec", specID))))))
        end
    end

    local nodes = tree and r.call("C_Traits.GetTreeNodes", tree) or nil
    if type(nodes) ~= "table" then nodes = {} end

    -- Tabs (the game's three talent tabs are the groups of the tree).
    local groups = tree and r.call("C_Traits.GetGroupDisplayInfoByTreeID", tree) or nil
    local tabs, tabOf = {}, {}
    if type(groups) == "table" then
        for _, g in ipairs(groups) do
            if type(g) == "table" then
                local id = num(g.groupID) or num(g.ID)
                tabs[#tabs + 1] = { id = id, name = type(g.displayName) == "string" and g.displayName or nil, spent = 0,
                    order = num(g.orderIndex) }
                if id then tabOf[id] = #tabs end
            end
        end
    end

    -- GF-011-C: the toolkit's own tab rule, so this text shows what the roster counts.
    local core = type(GreenFangToolkit_DevAccess) == "function" and select(2, pcall(GreenFangToolkit_DevAccess)) or nil
    local Tl = type(core) == "table" and type(core.Talents) == "table" and type(core.Talents.assignTabs) == "function"
        and core.Talents or nil

    -- Nodes first (the tab totals come from their ranks), lines after.
    local infos = {}
    for i = 1, math.min(#nodes, T.MAX_NODES) do
        local nodeID = num(nodes[i])
        infos[i] = { id = nodeID, ni = nodeID and r.call("C_Traits.GetNodeInfo", cfg, nodeID) or nil }
    end
    local assigned
    if Tl then
        local facts = {}
        for _, it in ipairs(infos) do
            if it.id and type(it.ni) == "table" then facts[#facts + 1] = Tl.nodeFacts(it.id, it.ni) end
        end
        local order = {}
        for k, t in ipairs(tabs) do order[k] = { id = t.id, order = t.order } end
        local okA, res = pcall(Tl.assignTabs, order, facts)
        assigned = okA and type(res) == "table" and res or nil
    end
    add(string.format("H assign=%s", assigned and "toolkit" or "direct"))
    local rows, other = {}, 0
    for _, it in ipairs(infos) do
        local nodeID, ni = it.id, it.ni
        if type(ni) ~= "table" then
            rows[#rows + 1] = string.format("N %s ! EMPTY C_Traits.GetNodeInfo", v(nodeID))
        else
            local gids = {}
            for _, g in ipairs(type(ni.groupIDs) == "table" and ni.groupIDs or {}) do
                if num(g) then gids[#gids + 1] = v(num(g)) end
            end
            local tab, by
            if assigned then
                tab, by = assigned.tab[nodeID], assigned.by[nodeID]
            else
                for _, g in ipairs(type(ni.groupIDs) == "table" and ni.groupIDs or {}) do
                    if num(g) and tabOf[num(g)] then tab, by = tabOf[num(g)], "direct"; break end
                end
            end
            local rank = num(ni.ranksPurchased) or num(ni.activeRank) or num(ni.currentRank)
            if rank and rank > 0 then
                if tab then tabs[tab].spent = tabs[tab].spent + rank else other = other + rank end
            end
            local active = type(ni.activeEntry) == "table" and num(ni.activeEntry.entryID) or nil
            local entries = {}
            for _, entryID in ipairs(type(ni.entryIDs) == "table" and ni.entryIDs or {}) do
                entryID = num(entryID)
                local ei = entryID and r.call("C_Traits.GetEntryInfo", cfg, entryID) or nil
                local def = type(ei) == "table" and num(ei.definitionID) or nil
                local di = def and r.call("C_Traits.GetDefinitionInfo", def) or nil
                local spell = type(di) == "table" and (num(di.spellID) or num(di.overriddenSpellID)) or nil
                local name = type(di) == "table" and type(di.overrideName) == "string" and di.overrideName ~= "" and di.overrideName
                    or spellName(r, spell)
                entries[#entries + 1] = string.format("%s:%s:%s:%s%s", v(entryID), v(def), v(spell), v(name),
                    (active and entryID == active) and ":*" or "")
            end
            rows[#rows + 1] = string.format("N %s tab=%s grp=%s rank=%s/%s cur=%s active=%s vis=%s type=%s pos=%s,%s sub=%s E=%s by=%s",
                v(nodeID), tab and tostring(tab) or "-", #gids > 0 and table.concat(gids, ",") or "-", v(rank), v(num(ni.maxRanks)),
                v(num(ni.currentRank)), v(num(ni.activeRank)), v(ni.isVisible), v(num(ni.type)), v(num(ni.posX)),
                v(num(ni.posY)), v(num(ni.subTreeID)), #entries > 0 and table.concat(entries, ";") or "?", by or "-")
        end
    end

    for k, t in ipairs(tabs) do add(string.format("G %d id=%s name=%s spent=%d", k, v(t.id), v(t.name), t.spent)) end
    add(string.format("H nodes=%d listed=%d tabs=%d ungroupedSpent=%d", #nodes, #rows, #tabs, other))
    add("H format: N nodeID tab grp(all groupIDs) rank=spent/max cur active vis type pos sub E=entryID:definitionID:spellID:name[:* active];... by=group|sub|pos|direct|-")
    for _, row in ipairs(rows) do add(row) end

    for _, path in ipairs(r.missingOrder) do add("! MISSING " .. path) end
    for _, path in ipairs(r.emptyOrder) do
        local e = r.empty[path]
        add(string.format("! EMPTY %s n=%d first=%s%s", path, e.n, e.first, e.err and " error" or ""))
    end
    if #r.missingOrder == 0 and #r.emptyOrder == 0 then add("! none: every API answered") end
    return L
end

-- Split into parts of at most PART_LIMIT characters; line 1 of part 1 is the
-- total line count, each later part opens with its own "# part" line.
function T.build()
    local body = T.collect()
    local parts, this, length = {}, {}, 0
    for _, line in ipairs(body) do
        if #this > 0 and length + #line + 1 > T.PART_LIMIT then
            parts[#parts + 1] = this
            this, length = {}, 0
        end
        this[#this + 1] = line
        length = length + #line + 1
    end
    if #this > 0 then parts[#parts + 1] = this end
    -- Every line counts: the first line, a "# part" line per part, the body.
    local total = 1 + #parts + #body
    local out, at = {}, 2
    for i, p in ipairs(parts) do
        local head = string.format("# part %d/%d lines %d-%d of %d", i, #parts, at, at + #p, total)
        at = at + #p + 1
        local text = head .. "\n" .. table.concat(p, "\n")
        if i == 1 then text = string.format("GF-TRAITDUMP v%d lines=%d parts=%d", T.VERSION, total, #parts) .. "\n" .. text end
        out[i] = text
    end
    return out, total
end

---------------------------------------------------------------------------
-- Copy window (made on the first command; like /gftk probe copy)
---------------------------------------------------------------------------

local window, edit, title
T.parts, T.shown = nil, nil

local function frame(kind, name, parent, template)
    if template then
        local ok, f = pcall(CreateFrame, kind, name, parent, template)
        if ok and f then return f end
    end
    return CreateFrame(kind, name, parent)
end

local function makeWindow()
    local f = frame("Frame", T.WINDOW_NAME, UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(780, 540)
    f:SetPoint("CENTER", 0, 10)
    if f.SetFrameStrata then f:SetFrameStrata("FULLSCREEN_DIALOG") end
    if f.SetMovable then f:SetMovable(true) end
    if f.EnableMouse then f:EnableMouse(true) end
    if f.RegisterForDrag then f:RegisterForDrag("LeftButton") end
    if f.StartMoving then f:SetScript("OnDragStart", f.StartMoving) end
    if f.StopMovingOrSizing then f:SetScript("OnDragStop", f.StopMovingOrSizing) end
    title = f.TitleText or f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    if not f.TitleText then title:SetPoint("TOP", 0, -6) end
    local tip = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    tip:SetPoint("TOPLEFT", 16, -34)
    tip:SetText("按 Ctrl+A 全選、Ctrl+C 複製，整段貼給 claude-pm。分好幾段時每段都要貼。")
    local nextBtn = frame("Button", nil, f, "UIPanelButtonTemplate")
    nextBtn:SetSize(90, 22)
    nextBtn:SetPoint("TOPRIGHT", -16, -30)
    nextBtn:SetText("下一段")
    nextBtn:SetScript("OnClick", function()
        if T.parts then T.show(T.shown and (T.shown % #T.parts) + 1 or 1) end
    end)
    f.nextButton = nextBtn
    local scroll = frame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -60)
    scroll:SetPoint("BOTTOMRIGHT", -34, 16)
    edit = CreateFrame("EditBox", nil, scroll)
    if edit.SetMultiLine then edit:SetMultiLine(true) end
    if edit.SetAutoFocus then edit:SetAutoFocus(false) end
    if edit.SetFontObject then edit:SetFontObject("ChatFontNormal") end
    edit:SetWidth(720)
    edit:SetHeight(440)
    if edit.SetMaxLetters then edit:SetMaxLetters(0) end
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
    if scroll.SetScrollChild then scroll:SetScrollChild(edit) end
    window = f
end

function T.show(i)
    if not T.parts then return false end
    i = math.max(1, math.min(#T.parts, i or 1))
    if not window then makeWindow() end
    local text = T.parts[i]
    T.shown = i
    title:SetText(string.format("綠皮冒險工具箱（開發用）｜天賦樹 ID｜第 %d／%d 段", i, #T.parts))
    edit:SetText(text)
    local lines = 1
    for _ in text:gmatch("\n") do lines = lines + 1 end
    edit:SetHeight(math.max(440, lines * 14))
    if window.nextButton then
        if #T.parts > 1 then window.nextButton:Show() else window.nextButton:Hide() end
    end
    window:Show()
    if edit.SetFocus then edit:SetFocus() end
    if edit.HighlightText then edit:HighlightText() end
    return true
end
function T.copyText() return edit and edit:GetText() or nil end
function T.window() return window end

function T.command(rest)
    local ok, combat = pcall(InCombatLockdown)
    if ok and combat then
        say("天賦樹匯出：戰鬥中不執行，脫離戰鬥再打一次 /gftkdev traits。")
        return false
    end
    local page = tonumber(tostring(rest or ""):match("^%s*(%d+)"))
    if page and T.parts then return T.show(page) end
    local okB, parts, total = pcall(T.build)
    if not okB then say("天賦樹匯出失敗：" .. tostring(parts)); return false end
    T.parts = parts
    say(string.format("天賦樹匯出：共 %d 行、%d 段。%s", total, #parts,
        #parts > 1 and "按「下一段」或 /gftkdev traits 2 看下一段。" or ""))
    return T.show(page or 1)
end
