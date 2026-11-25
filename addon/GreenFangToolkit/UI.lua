-- UI: the roster module (first module of the toolkit window) and the export
-- window. GF-UI-B (0.13.1, GF-UI-A §2.2): 16 px text, 36 px rows, 24 px class
-- and 28 px profession icons, a 40 px tool bar, a 28 px header with arrow
-- textures, no sentences or time stamps on the page (the scan time is in
-- 同步與診斷), race in the tooltip.

local _, ns = ...
local str, keyName = ns.str, ns.keyName
local Export = ns.Export
local Icons = ns.Icons

local UI = {}
ns.UI = UI

local ROW_HEIGHT = ns.PAGE_ROW -- GF-UI-B: 36 (was 23)
local panel, exportWindow
local rowScroll, rowContent, searchBox
-- Only the rows in view exist (GF-001-D14, EVAL-1000 §3.5): a small pool is
-- refilled while scrolling. matching is the sorted, filtered member list.
local rowWidgets = {}
local matching = {}
local rosterControls = {} -- disabled when the roster is not available
local exportEdit, exportInfo, partLabel, prevPart, nextPart
local exportParts, exportPartIndex, exportFormat = {}, 1, ""
local sortHeaders = {}
local manualScan = false

UI.sortKey, UI.sortAscending = "name", true
UI.SORT_KEYS = { name = true, rank = true, race = true, class = true, professions = true,
    level = true, zone = true, online = true, roles = true }
-- Professions cell (GF-001-D18, was text since D8): one line, the
-- profession's built-in icon and its skill points ("[icon]300"), primary
-- first. Cooking / first aid / fishing follow only while they fit whole;
-- they are never counted, the tooltip has them. A primary that does not fit
-- is counted as "+N". Members known only from the guild roster (no points)
-- get the icon alone; a profession without an icon falls back to its name.
-- "－" (full-width, faint) means no data. Row height is unchanged.
-- GF-001-D19: icons 20 px (were 14), full colour for names-only members;
-- each icon has its own short tooltip, and a click filters the roster.
-- GF-UI-B: profession icons 28 px (were 20), the hammer 16 px (was 10).
local LIST_SLOTS, LIST_GAP, GROUP_GAP = 6, 8, 6
local ICON_SIZE, ICON_GAP, MORE_WIDTH = ns.ROW_ICON, 2, 24
local CLASS_ICON, BADGE_SIZE, STATUS_ICON = 24, 16, 16
UI.ICON_SIZE, UI.CLASS_ICON, UI.BADGE_SIZE, UI.STATUS_ICON = ICON_SIZE, CLASS_ICON, BADGE_SIZE, STATUS_ICON
UI.ROLE_MAIN, UI.ROLE_CAN = 24, 16 -- GF-010
local NO_DATA = "－"
local SECONDARY_COLOR, NAMES_COLOR, TEXT_COLOR = { 0.72, 0.8, 0.74 }, { 0.6, 0.6, 0.6 }, { 1, 1, 1 }
local NO_DATA_COLOR = { 0.42, 0.42, 0.42 }
local NAMES_ALPHA, SECONDARY_ALPHA = 1, 0.85
local ONLINE_COLOR, OFFLINE_COLOR = ns.COLOR.good, ns.COLOR.disabled
local RANK_COLOR = { 0.85, 0.82, 0.65 }

-- Make each visible row from the stored snapshot, never from a stale chat printout.
-- GF-001-Q: two note columns on the right (公會註記 for everyone, 幹部註記
-- only for those the game lets see it).
-- GF-UI-B (GF-UI-A §2.2 item 1): reflowed for the 16 px font; 種族 moved to
-- the tooltip. 4 px between columns; the notes share the last 124 px when
-- the officer column is shown (each 60), else 公會註記 takes all of it.
local columns = {
    -- GF-010: 職責 (round role icons) between 職業 and 專業; 角色, 會階, 職業,
    -- 位置 and 狀態 gave the room (專業 keeps 300 for five icons with points).
    { name = "角色", key = "name", x = 4, w = 140 },
    { name = "會階", key = "rank", x = 148, w = 72 },
    { name = "職業", key = "class", x = 224, w = 104, icon = true },
    { name = "職責", key = "roles", x = 332, w = 64, roles = true },
    { name = "專業", key = "professions", x = 400, w = 300 },
    { name = "等級", key = "level", x = 704, w = 44, firstDescending = true, center = true },
    { name = "位置", key = "zone", x = 752, w = 90 },
    { name = "狀態", key = "online", x = 846, w = 66, firstDescending = true, status = true },
    { name = "公會註記", key = "note", x = 916, w = 124, noSort = true, wSplit = 60 },
    { name = "幹部註記", key = "officerNote", x = 980, w = 60, noSort = true, officer = true },
}
UI.columns = columns
UI.ROW_WIDTH = 1040
UI.CELL = {}
for j, col in ipairs(columns) do UI.CELL[col.key] = j end

---------------------------------------------------------------------------
-- Sorting and filtering (pure; covered by offline tests)
---------------------------------------------------------------------------

-- Sort only the visible list; never alter the captured report.
-- Missing values stay at the bottom in either direction.
local function sortValue(m, key)
    if key == "level" then return type(m.level) == "number" and m.level or 0 end
    if key == "online" then return m.online == true and 1 or 0 end
    if key == "rank" then return type(m.rankIndex) == "number" and m.rankIndex or nil end
    if key == "roles" then -- GF-010: by main role (坦克, 治療, 輸出), 未設定 / 未知 last
        local main = ns.Profile and ns.Profile.roles(m.guid).main
        return main and ({ t = 1, h = 2, d = 3 })[main] or nil
    end
    if key == "professions" then
        if type(m.professions) ~= "table" or #m.professions == 0 then return nil end
        return keyName(table.concat(m.professions, "、"))
    end
    local value = m[key]
    if type(value) ~= "string" or value == "" then return nil end
    return keyName(value)
end

function UI.sortMembers(list, key, ascending)
    table.sort(list, function(a, b)
        local va, vb = sortValue(a, key), sortValue(b, key)
        if va == nil and vb ~= nil then return false end
        if vb == nil and va ~= nil then return true end
        if va ~= vb then
            if ascending then return va < vb end
            return va > vb
        end
        return keyName(a.name) < keyName(b.name)
    end)
    return list
end

-- skillLineIDs a member is known to have: shared or own skill points, and
-- the names from the guild roster. { [id] = true }
function UI.memberSkills(m)
    local set = {}
    local detail = UI.detailFor(m)
    for _, prof in ipairs(detail and detail.professions or {}) do
        local id = ns.Professions.skillLineOf(prof)
        if id then set[id] = true end
    end
    for _, name in ipairs(type(m.professions) == "table" and m.professions or {}) do
        local id = ns.Data.skillLineIDFor(str(name))
        if id then set[id] = true end
    end
    return set
end

-- Roster filters (GF-001-D19): skill (skillLineID), class (class token),
-- online (true = only online), minLevel (number). All optional.
-- GF-UI-C (owner): 專業 and 職業 are multi-select lists: skills / classes are
-- sets { [value] = true } (nil = everything; an empty set = nothing).
-- GF-010: roles = { t, h, d, unknown } (nil = everything): anyone who can fill a ticked role.
UI.filters = { skill = nil, class = nil, skills = nil, classes = nil, roles = nil, online = false, minLevel = nil, active = false }

local function passes(m, f)
    if not f then return true end
    if f.online and m.online ~= true then return false end
    if f.class and m.classToken ~= f.class then return false end
    if f.classes and not f.classes[str(m.classToken)] then return false end
    if f.roles and not (ns.Profile and ns.Profile.matches(m.guid, f.roles)) then return false end
    if f.minLevel and (type(m.level) ~= "number" or m.level < f.minLevel) then return false end
    if f.skill and not UI.memberSkills(m)[f.skill] then return false end
    if f.skills then
        local any = false
        for id in pairs(UI.memberSkills(m)) do if f.skills[id] then any = true end end
        if not any then return false end
    end
    -- GF-006-B (R-4.2): only crafters taking orders.
    if f.active and not (ns.Orders and ns.Orders.isActiveAny(m.guid)) then return false end
    return true
end

function UI.filterMembers(members, query, filters)
    local q = keyName(query)
    local out = {}
    for _, m in ipairs(members or {}) do
        local blob = keyName(table.concat({
            str(m.name), str(m.race), str(m.class), Export.professionText(m),
            str(m.zone), str(m.guildRank)
        }, " "))
        if (q == "" or blob:find(q, 1, true)) and passes(m, filters) then out[#out + 1] = m end
    end
    return out
end

-- Options for the filter buttons: what the current roster has.
local PROFESSION_ORDER = { 164, 165, 171, 182, 186, 197, 202, 333, 393, 755, 773, 185, 129, 356 }

function UI.professionOptions()
    local s = ns.Roster.current()
    local have = {}
    for _, m in ipairs(s and s.members or {}) do
        for id in pairs(UI.memberSkills(m)) do have[id] = true end
    end
    local list = {}
    for _, id in ipairs(PROFESSION_ORDER) do
        if have[id] then
            list[#list + 1] = { value = id, text = ns.Data.skillName(nil, id) or ("專業 " .. id), icon = ns.Icons.professionIcon(id) }
        end
    end
    return list
end

function UI.classOptions()
    local s = ns.Roster.current()
    local seen, list = {}, {}
    for _, m in ipairs(s and s.members or {}) do
        local token = str(m.classToken)
        if token ~= "" and not seen[token] then
            seen[token] = true
            list[#list + 1] = { value = token, text = str(m.class) ~= "" and m.class or token }
        end
    end
    table.sort(list, function(a, b) return keyName(a.text) < keyName(b.text) end)
    return list
end

-- The button text of a multi-select filter: 全部專業 / one name / N 個專業 / 未選.
function UI.choiceSummary(allText, unit)
    return function(b)
        if b.selected == nil then return allText end
        local on = {}
        for _, o in ipairs(b.options()) do if b.isOn(o.value) then on[#on + 1] = o end end
        if #on == 0 then return "未選" end
        if #on == 1 then return on[1].text end
        return #on .. " 個" .. unit
    end
end
-- The filters follow the two lists (a copy of what is ticked).
function UI.syncChoiceFilters()
    local function copy(set) if not set then return nil end local o = {} for k, v in pairs(set) do o[k] = v end return o end
    UI.filters.skills = UI.skillChoice and copy(UI.skillChoice.selected) or nil
    UI.filters.classes = UI.classChoice and copy(UI.classChoice.selected) or nil
end

-- Only one profession ticked (offline tests and other pages).
function UI.setSkillFilter(id)
    if UI.skillChoice then
        if id then UI.skillChoice.setOnly(id) else UI.skillChoice.selectAll() end
    else
        UI.filters.skills = id and { [id] = true } or nil
        UI.refresh(true)
    end
end

function UI.loadSettings()
    local s = ns.settings()
    if UI.SORT_KEYS[s.sortKey] then UI.sortKey = s.sortKey end
    if type(s.sortAscending) == "boolean" then UI.sortAscending = s.sortAscending end
end

---------------------------------------------------------------------------
-- Main window
---------------------------------------------------------------------------

-- GF-UI-B: every text button is the toolkit's 30 px textButton (GF-UI-A §1.3).
local function button(parent, text, w, h, x, y, callback)
    local b = ns.OrdersUI.textButton(parent, text, callback, w)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    return b
end

-- GF-UI-B (GF-UI-A §2.2 item 8): the column being sorted is white with an
-- arrow texture (never arrow characters); the others stay gold.
local function updateSortHeaders()
    for _, entry in ipairs(sortHeaders) do
        local active = entry.col.key == UI.sortKey
        entry.label:SetText(entry.col.name)
        if active then
            ns.setTextColor(entry.label, "white")
            ns.GameIcons.set(entry.arrow, UI.sortAscending and "sort_up" or "sort_down")
            entry.arrow:ClearAllPoints()
            entry.arrow:SetPoint("LEFT", entry.heading, "LEFT", ns.measure(entry.label) + 4, 0)
            entry.arrow:Show()
        else
            ns.setTextColor(entry.label, "gold")
            entry.arrow:Hide()
        end
        entry.heading.sortDir = active and (UI.sortAscending and "up" or "down") or nil
    end
end
UI.sortHeaders = function() return sortHeaders end

local function changeSort(col)
    if UI.sortKey == col.key then
        UI.sortAscending = not UI.sortAscending
    else
        UI.sortKey = col.key
        UI.sortAscending = not col.firstDescending
    end
    local s = ns.settings()
    s.sortKey, s.sortAscending = UI.sortKey, UI.sortAscending
    UI.refresh(true)
end

local function newRow(i)
    local row = CreateFrame("Frame", nil, rowContent)
    row.index = i
    row:SetSize(UI.ROW_WIDTH, ROW_HEIGHT)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    -- GF-001-Q: the selected member (its actions are in the bar under the list).
    -- GF-UI-B: the shared list-row selection (gold glow + a 3 px bar).
    row.selected = ns.rowSelect(row)
    row.cells, row.cell = {}, {}
    for j, col in ipairs(columns) do
        local font = row:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)
        local x, w = col.x, col.w
        if col.icon then
            row.classIcon = row:CreateTexture(nil, "ARTWORK")
            row.classIcon:SetSize(CLASS_ICON, CLASS_ICON)
            row.classIcon:SetPoint("LEFT", row, "LEFT", col.x, 0)
            x, w = col.x + CLASS_ICON + 4, col.w - CLASS_ICON - 4
        end
        if col.roles then
            -- GF-010: the main role 24 px, then the others it can fill 16 px.
            row.roleMain = row:CreateTexture(nil, "ARTWORK")
            row.roleMain:SetSize(UI.ROLE_MAIN, UI.ROLE_MAIN)
            row.roleMain:SetPoint("LEFT", row, "LEFT", col.x, 0)
            row.roleMain:Hide()
            row.roleCan = {}
            for k = 1, 2 do
                local t = row:CreateTexture(nil, "ARTWORK")
                t:SetSize(UI.ROLE_CAN, UI.ROLE_CAN)
                t:SetPoint("LEFT", row, "LEFT", col.x + UI.ROLE_MAIN + 4 + (k - 1) * (UI.ROLE_CAN + 2), 0)
                t:Hide()
                row.roleCan[k] = t
            end
        end
        if col.status then
            row.statusIcon = row:CreateTexture(nil, "ARTWORK")
            row.statusIcon:SetSize(STATUS_ICON, STATUS_ICON)
            row.statusIcon:SetPoint("LEFT", row, "LEFT", col.x, 0)
            x, w = col.x + STATUS_ICON + 4, col.w - STATUS_ICON - 4
        end
        font:SetPoint("LEFT", row, "LEFT", x, 0)
        font:SetWidth(w)
        font:SetHeight(ROW_HEIGHT)
        font:SetJustifyH(col.center and "CENTER" or "LEFT")
        font:SetWordWrap(false)
        font.colX, font.colW = x, w
        row.cells[j] = font
        row.cell[col.key] = font
        if col.key == "professions" then
            row.profX, row.profW = col.x, col.w
            row.profSlots = {}
            for k = 1, LIST_SLOTS do
                local icon = row:CreateTexture(nil, "ARTWORK")
                icon:SetSize(ICON_SIZE, ICON_SIZE)
                icon:Hide()
                local label = row:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)
                label:SetHeight(ROW_HEIGHT)
                label:SetJustifyH("LEFT")
                label:SetWordWrap(false)
                -- GF-006-B (R-4.2): gold hammer corner on an active profession.
                local badge = row:CreateTexture(nil, "OVERLAY")
                badge:SetSize(BADGE_SIZE, BADGE_SIZE)
                badge:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 4, -4)
                badge:Hide()
                local slot = { icon = icon, label = label, badge = badge }
                row.profSlots[k] = slot
            end
            row.profMore = row:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)
            row.profMore:SetHeight(ROW_HEIGHT)
        end
    end
    -- Hover: over a profession, only that profession; elsewhere, the
    -- member and each profession, short (GF-001-D19). No frame per icon: the
    -- row follows the cursor while it is over it (a roster can have hundreds
    -- of rows).
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        self.hoverSlot = false
        UI.hoverRow(self)
        self:SetScript("OnUpdate", UI.hoverRow)
    end)
    row:SetScript("OnLeave", function(self)
        self:SetScript("OnUpdate", nil)
        self.hoverSlot = nil
        GameTooltip:Hide()
    end)
    row:SetScript("OnMouseUp", function(self, mouse)
        local x = UI.cursorX(self)
        UI.rowClick(self, mouse, UI.slotAt(self, x), x)
    end)
    rowWidgets[i] = row
    return row
end

-- GF-UI-B (owner): a left click on a member's profession icon opens that
-- member's recipes of that profession (filtering stays on the 專業 filter);
-- a left click anywhere else selects the member. Right-click is unchanged:
-- on a profession 「下單給〈名字〉」, elsewhere the member menu.
-- A plain frame, nothing secure. Returns what it did (offline tests).
-- GF-010: a left click on the 職責 cell opens the member's read-only card
-- (職工檔案); x is the cursor from the row's left edge.
function UI.onRolesCell(x)
    local col = columns[UI.CELL.roles]
    return type(x) == "number" and col ~= nil and x >= col.x and x < col.x + col.w
end
function UI.rowClick(row, mouse, slot, x)
    if mouse ~= "RightButton" and UI.onRolesCell(x) and row.member and ns.ProfileUI then
        UI.select(row.member)
        ns.ProfileUI.openCard(row.member)
        return "profile"
    end
    local id = slot and slot.entry and slot.entry.prof and ns.Professions.skillLineOf(slot.entry.prof)
    if mouse == "RightButton" and id and ns.OrdersUI then
        local m = { guid = row.memberGuid, name = row.memberName }
        ns.showMenu(row, ns.OrdersUI.rosterMenuItems(m, id))
        return "order-menu"
    end
    if mouse == "RightButton" then
        UI.select(row.member)
        local items = UI.memberMenuItems(row.member)
        if #items > 0 then ns.showMenu(row, items) end
        return "member-menu"
    end
    if id and row.memberGuid and ns.Recipes then
        ns.Recipes.show(row.memberGuid, id)
        return "recipes"
    end
    UI.select(row.member)
    return "select"
end

-- Cursor x from the row's left edge, or nil (offline tests: no cursor).
function UI.cursorX(row)
    if type(GetCursorPosition) ~= "function" or not row.GetLeft then return nil end
    local x = ns.num((GetCursorPosition()))
    local left = ns.num((row:GetLeft()))
    local scale = ns.num((row:GetEffectiveScale())) or 1
    if not (x and left and scale > 0) then return nil end
    return x / scale - left
end

-- The profession slot at x (from the row's left edge), or nil.
function UI.slotAt(row, x)
    if not x then return nil end
    for _, s in ipairs(row.profSlots or {}) do
        if s.entry and s.x0 and x >= s.x0 and x <= s.x1 then return s end
    end
    return nil
end

-- Tooltip for a row: one profession when slot is given, else the member.
function UI.showRowTooltip(row, slot)
    if slot then
        ns.tooltipAbove(row, slot.x0 or 0) -- right above that icon (GF-001-D21)
    else
        GameTooltip:SetOwner(row, "ANCHOR_TOP")
    end
    if slot then
        ns.Professions.addTooltipLines(GameTooltip, slot.entry.prof, row.memberGuid)
        GameTooltip:Show()
        return
    end
    local detail, names = row.detail, row.rosterNames
    -- GF-UI-B (GF-UI-A §2.2 item 10): a small card: name, level, race, class,
    -- rank (種族 left the columns), then each profession.
    local m = row.member or {}
    local c = Icons.classColor(m.classToken)
    GameTooltip:AddLine(str(row.memberName), c[1], c[2], c[3])
    local facts = {}
    if type(m.level) == "number" and m.level > 0 then facts[#facts + 1] = tostring(m.level) end
    local race = Export.raceText(m)
    if str(race) ~= "" then facts[#facts + 1] = race end
    if str(m.class) ~= "" then facts[#facts + 1] = m.class end
    if str(m.guildRank) ~= "" then facts[#facts + 1] = m.guildRank end
    if #facts > 0 then GameTooltip:AddLine(table.concat(facts, "  "), 0.9, 0.9, 0.9) end
    -- GF-010: 主職責 / 可支援, and how fresh it is (近期 / 稍早 / 過期).
    if ns.Profile and ns.ProfileUI then
        local p = ns.Profile.roles(m.guid)
        local main, can = ns.ProfileUI.rolesText(p)
        local age = ns.Profile.ageText(p.at)
        GameTooltip:AddLine("主職責 " .. main .. "　可支援 " .. can .. (age ~= "" and ("　" .. age) or ""), 0.9, 0.9, 0.9)
    end
    if detail then
        for _, prof in ipairs(detail.professions) do
            local c = ns.Professions.isSecondary(prof) and SECONDARY_COLOR or { 0.9, 0.9, 0.9 }
            local note = UI.recipeNote(row.memberGuid, prof)
            GameTooltip:AddLine(UI.skillLabel(prof) .. (note and ("　" .. note) or ""), c[1], c[2], c[3])
        end
    else
        for _, name in ipairs(names) do GameTooltip:AddLine(str(name), 0.9, 0.9, 0.9) end
    end
    GameTooltip:Show()
end

-- While the cursor is over a row: redraw the tooltip when it moves onto
-- another profession (or off them).
function UI.hoverRow(row)
    local slot = UI.slotAt(row, UI.cursorX(row)) or nil
    if slot == row.hoverSlot then return end
    row.hoverSlot = slot
    UI.showRowTooltip(row, slot)
end

-- "鍛造 34/75" (roster cell); just the name when the points are unknown.
function UI.shortLabel(prof)
    local name = str(prof.name)
    if type(prof.rank) ~= "number" then return name end
    if type(prof.max) == "number" and prof.max > 0 then
        return string.format("%s %d/%d", name, prof.rank, prof.max)
    end
    return string.format("%s %d", name, prof.rank)
end

-- "配方 120 個" for a member's profession, or nil.
function UI.recipeNote(guid, prof)
    local id = ns.Professions.skillLineOf(prof)
    local r = id and ns.Recipes and ns.Recipes.of(guid, id)
    if not r then return nil end
    return string.format("配方 %d 個", #r.ids)
end

function UI.hasRecipes(guid)
    local a = guid and ns.Share.authorOf(guid)
    for g in pairs(a and ns.Share.records(a) or {}) do
        if g:match("^R%d+$") then return true end
    end
    return false
end

-- "釣魚 150 / 225" (tooltip); just the name when the points are unknown.
function UI.skillLabel(prof)
    local value = ns.Professions.valueText(prof)
    return value and (str(prof.name) .. " " .. value) or str(prof.name)
end

-- "2026-11-20 21:05": the scan time without seconds (同步與診斷 only).
function UI.shortTime(s)
    local t = Export.timestampText(s)
    return (t:gsub("^(%d+%-%d+%-%d+ %d+:%d+):%d+$", "%1"))
end

-- Detailed professions for a roster member: the player's own character, or
-- what that member shared in game (D-011). nil = names only, as before.
function UI.detailFor(m)
    local own = ns.Sync.player()
    if own.guid and m.guid == own.guid then
        local profs = ns.Data.ownProfessionsDetailed()
        if #profs > 0 then
            return { professions = ns.Professions.ordered(profs), source = "本人", at = ns.now() }
        end
        return nil
    end
    local peer = ns.Comm and ns.Comm.peerFor(m.name)
    if peer and type(peer.professions) == "table" and #peer.professions > 0 then
        return { professions = ns.Professions.ordered(peer.professions), source = "公會成員分享",
            at = peer.reportedAt }
    end
    return nil
end

local syncIndicator

function UI.syncLine()
    return "下線後由 GF Sync 上傳（名冊不含位置與在線狀態）"
end
local syncLine = UI.syncLine

-- The small 「同步與診斷」 button at the bottom right of the roster page
-- (D-014 point 6). Clicking opens that window; it never switches sync.
function UI.refreshSyncIndicator()
    if not syncIndicator then return end
    local c = ns.Sync.statusColor()
    if syncIndicator.label then syncIndicator.label:SetTextColor(c[1], c[2], c[3]) end
end

-- Outbox writes and shared data can come in bursts: redraw at most once a
-- second (GF-001-D11).
local function refreshSoon()
    if panel and panel:IsShown() and ns.Framework.current() == "roster" then
        ns.coalesce("roster-page", 1, function()
            if panel and panel:IsShown() and ns.Framework.current() == "roster" then UI.refresh(false) end
        end)
    end
end
ns.Sync.onChange(function()
    UI.refreshSyncIndicator()
    refreshSoon()
end)
ns.Share.onUpdate(refreshSoon)

-- GF-UI-B (GF-UI-A §2.2 item 3): what the middle of the list shows instead
-- of rows: a 48 px icon and a 2-4 character name, never a sentence.
-- nil when there are rows to show.
UI.EMPTY = {
    loading = { art = "loading", text = "讀取中" },
    none = { art = "noguild", text = "未入會" },
    other = { art = "tabard", text = "非本會", grey = true },
    noRoster = { art = "refresh", text = "" }, -- the 更新 button itself sits under the icon
    noMatch = { art = "person", text = "沒有", grey = true },
}
function UI.emptyState(s)
    local state = ns.guildState()
    if state ~= "target" then return state end
    if not s then return "noRoster" end
    if #matching == 0 then return "noMatch" end
    return nil
end

-- Message for chat and 同步與診斷 when the roster is not available, or nil.
function UI.unavailableText()
    local state = ns.guildState()
    if state == "target" then return nil end
    if state == "loading" then return "公會資料讀取中，請稍候。" end
    if state == "none" then
        return string.format("這個角色沒有加入公會。公會名冊只提供給%s的成員使用。", ns.targetGuildName())
    end
    return string.format("這個角色不在%s，無法使用公會名冊。", ns.targetGuildName())
end

local function setEnabled(w, on)
    if w.SetEnabled then
        w:SetEnabled(on)
    elseif on and w.Enable then
        w:Enable()
    elseif not on and w.Disable then
        w:Disable()
    end
end

function UI.refresh(resetScroll)
    if not panel then return end
    local unavailable = UI.unavailableText()
    for _, w in ipairs(rosterControls) do setEnabled(w, unavailable == nil) end
    if unavailable and searchBox and searchBox.ClearFocus then searchBox:ClearFocus() end
    local s = not unavailable and ns.Roster.current() or nil
    matching = {}
    if s then
        -- D-014 point 6, GF-UI-B: only what players use. The guild name is in the
        -- window title, the count on the tool bar; the scan time is in 同步與診斷.
        matching = UI.sortMembers(UI.filterMembers(s.members, searchBox and searchBox:GetText() or "", UI.filters),
            UI.sortKey, UI.sortAscending)
        UI.countText:SetText(string.format("%d/%d", #matching, #s.members))
    else
        UI.countText:SetText("")
    end
    UI.placeCount()
    UI.drawEmpty(UI.emptyState(s))
    ns.Framework.refreshTitle()
    UI.refreshSyncIndicator()
    UI.refreshAdminButtons()
    if UI.selected then
        local still
        for _, m in ipairs(matching) do if m.name == UI.selected.name then still = m end end
        UI.selected = still
    end
    UI.drawActionBar()
    UI.drawCensus(s and matching or nil)
    updateSortHeaders()
    rowContent:SetHeight(math.max(1, #matching * ROW_HEIGHT))
    if resetScroll and rowScroll then rowScroll:SetVerticalScroll(0) end
    UI.layoutRows()
    UI.placeOwnButtons()
end

-- Rows that fit in the scroll frame, plus one partly shown.
function UI.visibleRowCount()
    local h = rowScroll and ns.num((rowScroll:GetHeight())) or 0
    if not h or h <= 0 then h = 400 end
    return math.ceil(h / ROW_HEIGHT) + 1
end

-- Fill the pooled rows with the members in view.
function UI.layoutRows()
    if not rowScroll then return end
    local offset = ns.num((rowScroll:GetVerticalScroll())) or 0
    local first = math.max(1, math.floor(offset / ROW_HEIGHT) + 1)
    local count = UI.visibleRowCount()
    UI.officerLayout()
    for k = 1, math.max(count, #rowWidgets) do
        local i = first + k - 1
        local m = k <= count and matching[i] or nil
        local row = rowWidgets[k] or (m and newRow(k)) or nil
        if row then
            if m then
                row.index = i
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", rowContent, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
                ns.stripe(row.bg, i) -- GF-UI-B: the shared stripe
                UI.fillRow(row, m)
                row:Show()
            else
                row:Hide(); row.ownList = nil
            end
        end
    end
end

-- Professions cell (D18): icon + skill points per profession (own record or
-- what the member shared, D-011), primary first; secondary ones only while
-- they fit. Members without that data: dimmed icons of the names in the
-- guild roster, or a faint "－". Own row: remember where each profession is
-- so UI.placeOwnButtons can put a secure button on it.
--
-- Every label is measured with SetWidth(0) first. Before D18 a reused label
-- kept the fixed width of what it showed last, and the client measures text
-- within that width, so a longer name came out as "剝…" or only "…".
local function hideSlot(s)
    s.icon:Hide()
    if s.badge then s.badge:Hide() end
    s.label:SetText("")
    s.label:Hide()
    s.entry, s.x0, s.x1 = nil, nil, nil
end

-- Put one entry into slot s at x; returns its width, or nil when it does not
-- fit in `room`. `first` may be cut to the cell (the cell is never empty).
local function placeEntry(row, s, e, x, room, first)
    local hasIcon = e.prof and Icons.setProfessionIcon(s.icon, e.prof) or false
    local text
    if hasIcon then
        text = e.points or ""
    else
        text = e.points and (e.name .. " " .. e.points) or e.name
    end
    s.label:SetWidth(0)
    s.label:SetText(text)
    local textW = text ~= "" and (ns.num((s.label:GetStringWidth())) or 30) or 0
    local iconW = hasIcon and (ICON_SIZE + (textW > 0 and ICON_GAP or 0)) or 0
    local w = iconW + textW
    if w > room and not first then
        hideSlot(s)
        return nil
    end
    local left = row.profX + x
    if hasIcon then
        s.icon:ClearAllPoints()
        s.icon:SetPoint("LEFT", row, "LEFT", left, 0)
        s.icon:SetAlpha(e.alpha)
        s.icon:Show()
    end
    if s.badge then
        local skill = e.prof and ns.Professions.skillLineOf(e.prof)
        if hasIcon and skill and ns.Orders and ns.Orders.isActive(row.memberGuid, skill) and ns.OrdersUI then
            ns.OrdersUI.setIcon(s.badge, "hammer")
        else
            s.badge:Hide()
        end
    end
    if textW > 0 then
        s.label:ClearAllPoints()
        s.label:SetPoint("LEFT", row, "LEFT", left + iconW, 0)
        if w > room then s.label:SetWidth(math.max(1, room - iconW)) end
        s.label:SetTextColor(e.color[1], e.color[2], e.color[3])
        s.label:Show()
    else
        s.label:Hide()
    end
    -- Where this profession is, for its tooltip and click (not the "－").
    s.entry = e.prof and e or nil
    s.x0, s.x1 = left, left + math.min(w, room)
    return math.min(w, room)
end

local function fillProfessions(row, cell, m)
    local detail = UI.detailFor(m)
    local Prof = ns.Professions
    row.detail, row.memberName, row.memberGuid = detail, m.name, m.guid
    row.rosterNames = nil
    row.ownList = nil
    cell:SetText("")
    local entries = {}
    if detail then
        for _, prof in ipairs(detail.professions) do
            local secondary = Prof.isSecondary(prof)
            entries[#entries + 1] = { prof = prof, name = str(prof.name), secondary = secondary,
                points = type(prof.rank) == "number" and tostring(prof.rank) or nil,
                color = secondary and SECONDARY_COLOR or TEXT_COLOR,
                alpha = secondary and SECONDARY_ALPHA or 1 }
        end
    elseif type(m.professions) == "table" and #m.professions > 0 then
        row.rosterNames = m.professions
        local list = {}
        for _, name in ipairs(m.professions) do list[#list + 1] = { name = str(name) } end
        for _, prof in ipairs(Prof.ordered(list)) do
            entries[#entries + 1] = { prof = prof, name = prof.name, secondary = Prof.isSecondary(prof),
                color = NAMES_COLOR, alpha = NAMES_ALPHA }
        end
    end
    local own = detail and detail.source == "本人"
    if own then row.ownList = {} end
    row.profMore:SetText("")
    row.profMore:Hide()
    local slots = row.profSlots
    if #entries == 0 then
        for k = 2, #slots do hideSlot(slots[k]) end
        placeEntry(row, slots[1], { name = NO_DATA, color = NO_DATA_COLOR }, 0, row.profW, true)
        return
    end
    -- Primaries left after entry i (room is kept for "+N" while there are).
    local primariesAfter, count = {}, 0
    for i = #entries, 1, -1 do
        primariesAfter[i] = count
        if not entries[i].secondary then count = count + 1 end
    end
    local x, used, hiddenPrimary, full = 0, 0, 0, false
    local lastSecondary = false
    for i, e in ipairs(entries) do
        local s = slots[used + 1]
        local w
        if s and not full then
            local gap = 0
            if used > 0 then gap = LIST_GAP + ((e.secondary and not lastSecondary) and GROUP_GAP or 0) end
            local reserve = primariesAfter[i] > 0 and MORE_WIDTH or 0
            w = placeEntry(row, s, e, x + gap, row.profW - x - gap - reserve, used == 0)
            if w then
                if own and e.prof then
                    row.ownList[#row.ownList + 1] = { prof = e.prof, x = row.profX + x + gap, w = w }
                end
                x = x + gap + w
                used = used + 1
                lastSecondary = e.secondary
            end
        end
        if not w then
            full = true
            if not e.secondary then hiddenPrimary = hiddenPrimary + 1 end
        end
    end
    for k = used + 1, #slots do hideSlot(slots[k]) end
    if hiddenPrimary > 0 then
        row.profMore:ClearAllPoints()
        row.profMore:SetPoint("LEFT", row, "LEFT", row.profX + x + 4, 0)
        row.profMore:SetText("+" .. hiddenPrimary)
        row.profMore:Show()
    end
end
UI.NO_DATA = NO_DATA
-- Row frames and the scroll frame (offline tests).
function UI.rows() return rowWidgets end
function UI.scrollFrame() return rowScroll end

-- Secure buttons over the player's own professions in the roster (only
-- professions with a window, out of combat, while the own row is in view).
function UI.placeOwnButtons()
    if ns.inCombat() then return end
    local Prof = ns.Professions
    local ownRow
    -- The page, not the window: the window is shown right after the page.
    if panel and panel:IsShown() and ns.Framework.current() == "roster" then
        for _, row in ipairs(rowWidgets) do
            if row:IsShown() and row.ownList then ownRow = row end
        end
    end
    local n = 0
    if ownRow and rowScroll then
        local offset = ns.num((rowScroll:GetVerticalScroll())) or 0
        local height = ns.num((rowScroll:GetHeight())) or 0
        local top = (ownRow.index - 1) * ROW_HEIGHT
        if top >= offset - 0.5 and top + ROW_HEIGHT <= offset + height + 0.5 then
            for _, e in ipairs(ownRow.ownList) do
                if Prof.windowSpell(e.prof) then
                    n = n + 1
                    Prof.bind("roster", n, ownRow, e.prof, e.x, 0, e.w, ROW_HEIGHT)
                end
            end
        end
    end
    Prof.hideFrom("roster", n + 1)
end

-- GF-UI-B: 公會註記 takes the officer column's room while that one is hidden.
function UI.officerLayout()
    local noteCol = columns[UI.CELL.note]
    local w = UI.officerVisible and noteCol.wSplit or noteCol.w
    for _, row in ipairs(rowWidgets) do row.cell.note:SetWidth(w); row.cell.note.colW = w end
    for _, entry in ipairs(sortHeaders) do
        if entry.col.key == "note" then entry.heading:SetSize(w - 2, UI.HEADER_H) end
    end
end

-- GF-010: 職責 cell: main role icon, then the other roles it can fill; a
-- faint 未設定 / 未知 when there is no main role (spec §5.2).
function UI.fillRoles(row, m)
    local cell = row.cell.roles
    if not (cell and row.roleMain) then return end
    local p = ns.Profile and ns.Profile.roles(m.guid) or { can = {}, state = "unknown" }
    row.roles = p
    for _, t in ipairs(row.roleCan) do t:Hide() end
    if p.main then
        ns.GameIcons.set(row.roleMain, "role_" .. p.main)
        local k = 0
        for _, r in ipairs(ns.Profile.ROLES) do
            if r ~= p.main and p.can[r] and k < #row.roleCan then
                k = k + 1
                ns.GameIcons.set(row.roleCan[k], "role_" .. r)
            end
        end
        cell:SetText("")
    else
        row.roleMain:Hide()
        cell:SetText(p.state == "unknown" and ns.Profile.UNKNOWN_NAME or ns.Profile.UNSET_NAME)
        cell:SetTextColor(NO_DATA_COLOR[1], NO_DATA_COLOR[2], NO_DATA_COLOR[3])
    end
end

---------------------------------------------------------------------------
-- GF-010 (spec §5.2): 人力盤點 on the bottom row, left: per role its round
-- icon with 主 N 可 N (main role / can fill), then 未知 N and 在線 N; the
-- total is the member count on the tool bar (each member once). Counts are
-- over the list as filtered. A click on a role (or 未知) filters the list
-- to members who can fill it, like the profession icons; 清除 resets it.
---------------------------------------------------------------------------
UI.CENSUS_ICON, UI.CENSUS_STEP = 24, 128 -- room for 主999 可999
function UI.toggleRoleFilter(key)
    local set = UI.filters.roles or {}
    if set[key] then set[key] = nil else set[key] = true end
    UI.filters.roles = next(set) and set or nil
    UI.refresh(true)
end
function UI.buildCensus(f)
    local O = ns.OrdersUI
    local c = { roles = {} }
    local x = 20
    local keys = { "t", "h", "d" }
    for _, r in ipairs(keys) do
        local b = O.iconButton(f, UI.CENSUS_ICON, "unknown", nil, function() UI.toggleRoleFilter(r) end, "")
        ns.GameIcons.set(b.tex, "role_" .. r)
        b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, UI.BOTTOM_Y + 3)
        b.role = r
        c.roles[r] = b
        x = x + UI.CENSUS_STEP
    end
    c.unknown = O.textButton(f, "未知", function() UI.toggleRoleFilter("unknown") end)
    c.unknown:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, UI.BOTTOM_Y)
    c.unknownX = x
    c.onlineIcon = f:CreateTexture(nil, "ARTWORK")
    c.onlineIcon:SetSize(16, 16)
    ns.GameIcons.set(c.onlineIcon, "online")
    c.online = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
    UI.census = c
end
function UI.drawCensus(list)
    local c = UI.census
    if not (c and ns.Profile) then return end
    local n = ns.Profile.census(list or {})
    UI.censusCounts = n
    local P = ns.Profile
    local on = UI.filters.roles or {}
    for _, r in ipairs(P.ROLES) do
        local b = c.roles[r]
        ns.OrdersUI.setLabel(b, string.format("主%d 可%d", n.main[r], n.can[r]))
        ns.OrdersUI.setSelected(b, on[r] == true)
        b.tip = string.format("%s：主職責 %d 位，可支援 %d 位", P.ROLE_NAME[r], n.main[r], n.can[r])
        if list then b:Show() else b:Hide() end
    end
    local unknown = n.main.unknown + n.main.unset
    c.unknown:SetText(string.format("未知 %d", unknown))
    c.unknown.gfWidth = ns.labelWidth(c.unknown:GetText()) + 28
    c.unknown:SetWidth(c.unknown.gfWidth)
    c.unknown.tip = string.format("未知 %d 位、未設定 %d 位", n.main.unknown, n.main.unset)
    ns.Theme.setSelected(c.unknown, on.unknown == true)
    c.online:SetText(string.format("在線 %d", n.online))
    local x = c.unknownX + c.unknown.gfWidth + 16
    c.onlineIcon:ClearAllPoints(); c.onlineIcon:SetPoint("BOTTOMLEFT", UI.census.unknown:GetParent(), "BOTTOMLEFT", x, UI.BOTTOM_Y + 7)
    c.online:ClearAllPoints(); c.online:SetPoint("BOTTOMLEFT", UI.census.unknown:GetParent(), "BOTTOMLEFT", x + 20, UI.BOTTOM_Y + 7)
    if list then c.unknown:Show(); c.onlineIcon:Show(); c.online:Show()
    else c.unknown:Hide(); c.onlineIcon:Hide(); c.online:Hide() end
end

-- One roster row: class icon and colour, rank, centred level, coloured status.
function UI.fillRow(row, m)
    local color = Icons.classColor(m.classToken)
    local cells = row.cells
    row.member = m
    if UI.selected and m.name == UI.selected.name then row.selected:Show() else row.selected:Hide() end
    local cell = row.cell
    cell.name:SetText(str(m.name))
    cell.name:SetTextColor(color[1], color[2], color[3])
    cell.rank:SetText(str(m.guildRank))
    cell.rank:SetTextColor(RANK_COLOR[1], RANK_COLOR[2], RANK_COLOR[3])
    Icons.setClassIcon(row.classIcon, m.classToken)
    cell.class:SetText(str(m.class))
    cell.class:SetTextColor(color[1], color[2], color[3])
    UI.fillRoles(row, m)
    fillProfessions(row, cell.professions, m)
    cell.level:SetText(tostring(m.level or 0))
    -- GF-UI-B (GF-UI-A §2.2 items 6, 7): a faint "－" for no zone; a 16 px
    -- online / offline icon in front of the status.
    if str(m.zone) ~= "" then
        cell.zone:SetText(str(m.zone)); cell.zone:SetTextColor(1, 1, 1)
    else
        cell.zone:SetText(NO_DATA); cell.zone:SetTextColor(NO_DATA_COLOR[1], NO_DATA_COLOR[2], NO_DATA_COLOR[3])
    end
    local status = m.online and ONLINE_COLOR or OFFLINE_COLOR
    ns.GameIcons.set(row.statusIcon, m.online and "online" or "offline")
    cell.online:SetText(m.online and "在線" or "離線")
    cell.online:SetTextColor(status[1], status[2], status[3])
    -- GF-001-Q: notes straight from the game's roster (memory only, never saved).
    local note, officer = "", nil
    if ns.GuildAdmin then note, officer = ns.GuildAdmin.notes(m.name) end
    cell.note:SetText(note)
    cell.note:SetTextColor(0.9, 0.9, 0.9)
    if UI.officerVisible then
        cell.officerNote:SetText(officer or "")
        cell.officerNote:SetTextColor(0.6, 1, 0.6)
        cell.officerNote:Show()
    else
        cell.officerNote:SetText("")
        cell.officerNote:Hide()
    end
end

---------------------------------------------------------------------------
-- GF-001-Q: guild management on the roster (ns.GuildAdmin does the work)
---------------------------------------------------------------------------

-- Right-click menu: the current rank (a header), 配方, then every action the
-- character may do (GF-UI-C: text only; the officer tools are only here).
UI.RECIPE_ICON = "Interface\\Icons\\INV_Scroll_04"
function UI.memberMenuItems(m)
    if not m or not ns.GuildAdmin then return {} end
    local items = {}
    local rest = ns.GuildAdmin.menuItems(m)
    local k = 1
    if rest[1] and rest[1].header then items[1] = rest[1]; k = 2 end
    if UI.hasRecipes(m.guid) then
        items[#items + 1] = { text = "配方", key = "recipes", fn = function() ns.Recipes.show(m.guid) end }
    end
    for i = k, #rest do items[#items + 1] = rest[i] end
    return items
end

function UI.select(m)
    UI.selected = m
    UI.drawActionBar()
    UI.layoutRows()
end

function UI.drawActionBar()
    local bar = UI.actionBar
    if not bar then return end
    local m = UI.selected
    local G = ns.GuildAdmin
    -- GF-UI-B (GF-UI-A §2.2 item 3): nobody chosen = an empty bar, no hint.
    if not (m and G) then
        bar.name:SetText("")
        for _, b in ipairs(bar.buttons) do b:Hide() end
        return
    end
    local c = Icons.classColor(m.classToken)
    bar.name:SetText(ns.shortName(m.name))
    bar.name:SetTextColor(c[1], c[2], c[3])
    -- GF-UI-C (owner): only the everyday actions (密語, 組隊, 查看 when the
    -- game can inspect this member), as 30 px text buttons. Officer tools
    -- are in the right-click menu.
    local list = G.barActions(m)
    local shown = {}
    for i = 1, UI.BAR_MAX do
        local b = bar.buttons[i]
        local a = list[i]
        if not b then
            b = ns.OrdersUI.textButton(bar, "查看", nil)
            bar.buttons[i] = b
        end
        if a then
            b:SetText(a.text)
            b.tip, b.action = nil, a.key
            local fn = a.fn
            b:SetScript("OnClick", function() fn(m); UI.drawActionBar() end)
            b:Show()
            shown[#shown + 1] = b
        else
            b:Hide(); b.action = nil
        end
    end
    local x = bar.nameWidth
    for _, b in ipairs(shown) do
        b:ClearAllPoints()
        b:SetPoint("LEFT", bar, "LEFT", x, 0)
        b.flowX = x
        x = x + b.gfWidth + 10
    end
end
UI.BAR_MAX = 3

-- 公會資訊: the message of the day and the guild info, with 編輯 where allowed.
-- GF-UI-C (owner: the info was cut off): the info sits in a scroll frame and
-- takes the height its text needs; 編輯 opens a large multi-line editor.
UI.GUILD_INFO_NAME = "GreenFangToolkit_GuildInfo"
UI.INFO_W, UI.INFO_H = 640, 480
function UI.openGuildInfo()
    local G = ns.GuildAdmin
    if not UI.guildInfo then
        local f = ns.popupWindow(UI.GUILD_INFO_NAME, UI.INFO_W, UI.INFO_H)
        f:SetPoint("CENTER", 0, 40)
        f:EnableMouse(true)
        ns.exclusivePopup(f)
        if f.TitleText then f.TitleText:SetText("公會資訊") end
        local O = ns.OrdersUI
        local X, W = O.FIELD_X, UI.INFO_W - 2 * O.FIELD_X - 24
        O.fieldLabel(f, "今日訊息", X, -52)
        f.editMotd = O.textButton(f, "編輯", function() G.editMOTD() end)
        f.editMotd:SetPoint("TOPRIGHT", f, "TOPRIGHT", -24, -44)
        f.motd = f:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)
        f.motd:SetPoint("TOPLEFT", f, "TOPLEFT", X, -84)
        f.motd:SetWidth(W + 24); f.motd:SetJustifyH("LEFT")
        if f.motd.SetWordWrap then f.motd:SetWordWrap(true) end
        O.fieldLabel(f, "公會資訊", X, -140)
        f.editInfo = O.textButton(f, "編輯", function() G.editInfo() end)
        f.editInfo:SetPoint("TOPRIGHT", f, "TOPRIGHT", -24, -132)
        local scroll = ns.createFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", f, "TOPLEFT", X, -172)
        scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -44, 60)
        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(W, 1)
        scroll:SetScrollChild(content)
        f.infoScroll, f.infoContent, f.infoWidth = scroll, content, W
        f.info = content:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)
        f.info:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        f.info:SetWidth(W); f.info:SetJustifyH("LEFT"); f.info:SetJustifyV("TOP")
        if f.info.SetWordWrap then f.info:SetWordWrap(true) end
        f.close = O.textButton(f, "完成", function() f:Hide() end, 110)
        f.close:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 18)
        f:Hide()
        UI.guildInfo = f
    end
    local f = UI.guildInfo
    f:Show()
    UI.drawGuildInfo()
    return f
end

-- The guild info editor (GF-UI-C): a multi-line edit box in a scroll frame,
-- several lines in view, 儲存 / 取消. ESC and a click on 取消 drop the edit.
UI.INFO_EDIT_NAME = "GreenFangToolkit_GuildInfoEdit"
function UI.openInfoEditor()
    local G = ns.GuildAdmin
    if not (G and G.can("info")) then return nil end
    if not UI.infoEditor then
        local f = ns.popupWindow(UI.INFO_EDIT_NAME, UI.INFO_W, UI.INFO_H)
        f:SetPoint("CENTER", 0, 40)
        f:EnableMouse(true)
        ns.exclusivePopup(f)
        if f.TitleText then f.TitleText:SetText("公會資訊") end
        local O = ns.OrdersUI
        local X, W = O.FIELD_X, UI.INFO_W - 2 * O.FIELD_X - 24
        f.count = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.DISABLED_FONT))
        f.count:SetPoint("TOPLEFT", f, "TOPLEFT", X, -44)
        local scroll = ns.createFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", f, "TOPLEFT", X, -72)
        scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -44, 60)
        local bg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
        bg:SetPoint("TOPLEFT", scroll, "TOPLEFT", -4, 4)
        bg:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 4, -4)
        bg:SetColorTexture(0, 0, 0, 0.45)
        local box = CreateFrame("EditBox", nil, scroll)
        box:SetMultiLine(true)
        box:SetAutoFocus(false)
        box:SetFontObject(ns.LABEL_FONT)
        box:SetWidth(W)
        box:SetHeight(UI.INFO_H - 140)
        if box.SetTextInsets then box:SetTextInsets(4, 4, 4, 4) end
        box:SetMaxLetters(G.INFO_MAX)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
        box:SetScript("OnTextChanged", function(self)
            f.count:SetText(string.format("%d/%d", #str(self:GetText()), G.INFO_MAX))
        end)
        scroll:SetScrollChild(box)
        f.box, f.scroll = box, scroll
        f.save = O.textButton(f, "儲存", function() UI.saveInfoEditor() end, 96)
        f.save:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 18)
        -- 取消: back to the info window (only one popup is open at a time).
        f.cancel = O.textButton(f, "取消", function() f:Hide(); UI.openGuildInfo() end, 96)
        f.cancel:SetPoint("RIGHT", f.save, "LEFT", -10, 0)
        f:Hide()
        UI.infoEditor = f
    end
    local f = UI.infoEditor
    f.box:SetText(G.infoText())
    f.count:SetText(string.format("%d/%d", #G.infoText(), G.INFO_MAX))
    f:Show()
    if f.box.SetFocus then f.box:SetFocus() end
    return f
end
function UI.saveInfoEditor()
    local f = UI.infoEditor
    if not f then return false end
    local ok = ns.GuildAdmin.saveInfo(f.box:GetText())
    f:Hide()
    UI.openGuildInfo()
    return ok
end
function UI.drawGuildInfo()
    local f, G = UI.guildInfo, ns.GuildAdmin
    if not (f and G) then return end
    local motd, info = G.motd(), G.infoText()
    -- GF-UI-B (GF-UI-A §2.10 item 4): a faint "－" for nothing, no brackets.
    f.motd:SetText(motd ~= "" and motd or NO_DATA)
    f.info:SetText(info ~= "" and info or NO_DATA)
    local faint = NO_DATA_COLOR
    if motd ~= "" then f.motd:SetTextColor(1, 1, 1) else f.motd:SetTextColor(faint[1], faint[2], faint[3]) end
    if info ~= "" then f.info:SetTextColor(1, 1, 1) else f.info:SetTextColor(faint[1], faint[2], faint[3]) end
    -- The whole text: as high as it needs, the scroll frame shows the rest.
    local h = ns.textHeight(f.info, f.infoWidth)
    f.info:SetHeight(h)
    f.infoContent:SetHeight(math.max(1, h))
    if G.can("motd") then f.editMotd:Show() else f.editMotd:Hide() end
    if G.can("info") then f.editInfo:Show() else f.editInfo:Hide() end
end

-- Buttons of the bottom row (GF-UI-B, GF-UI-A §2.2 item 9): only what this
-- character may use, right-aligned left of 診斷.
UI.BOTTOM_Y = 12
function UI.refreshAdminButtons()
    local G = ns.GuildAdmin
    if not (G and UI.inviteButton) then return end
    local list = {}
    if G.can("invite") then UI.inviteButton:Show(); list[#list + 1] = UI.inviteButton else UI.inviteButton:Hide() end
    if G.has("GetGuildRosterMOTD") or G.has("GetGuildInfoText") then UI.infoButton:Show(); list[#list + 1] = UI.infoButton else UI.infoButton:Hide() end
    local x = UI.diagLeft or (UI.ROW_WIDTH + 20)
    for i = #list, 1, -1 do
        local b = list[i]
        x = x - 10 - b.gfWidth
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", x, UI.BOTTOM_Y)
    end
    UI.adminLeft = x
    local view = G.can("viewOfficer")
    UI.officerVisible = view
    for _, entry in ipairs(sortHeaders) do
        if entry.col.officer then if view then entry.heading:Show() else entry.heading:Hide() end end
    end
    if UI.guildInfo and UI.guildInfo:IsShown() then UI.drawGuildInfo() end
end

local function scanResult(ok, countOrReason)
    if ok then ns.say(string.format("名冊已更新：%d 位角色。", countOrReason)) end
    return ok
end

local function manualUpdate()
    local unavailable = UI.unavailableText()
    if unavailable then
        ns.say(unavailable)
        return
    end
    if not ns.Roster.request() then
        ns.say("遊戲未提供可用的公會名冊 API。")
        return
    end
    manualScan = true
    -- GF-UI-B: no sentence on the page; the 更新 button waits instead.
    if UI.updateButton and UI.updateButton.Disable then UI.updateButton:Disable() end
    ns.after(6.5, function() if UI.updateButton and UI.updateButton.Enable then UI.updateButton:Enable() end end)
    -- Club info and guild roster can arrive separately.
    ns.after(2, function()
        if not manualScan then return end
        if scanResult(ns.Roster.collect()) then
            manualScan = false
            UI.refresh(true)
        end
    end)
    ns.after(6, function()
        if not manualScan then return end
        local ok, countOrReason = ns.Roster.collect()
        if not scanResult(ok, countOrReason) then ns.say(countOrReason .. "，可稍後重按更新。") end
        manualScan = false
        UI.refresh(true)
    end)
end

-- Called by Init after an automatic scan; announces it if the player asked.
function UI.afterAutoScan(count)
    if manualScan then
        ns.say(string.format("名冊已更新：%d 位角色。", count))
        manualScan = false
    end
    if ns.Framework.isModuleShown("roster") then UI.refresh(true) end
end

-- 「清除」: search text and every filter.
function UI.clearFilters()
    UI.filters.skill, UI.filters.class, UI.filters.online, UI.filters.minLevel = nil, nil, false, nil
    UI.filters.skills, UI.filters.classes, UI.filters.roles = nil, nil, nil
    UI.filters.active = false

    if UI.activeCheck then UI.activeCheck.set(false) end
    if UI.skillChoice then UI.skillChoice.selected = nil; UI.skillChoice.refreshText() end
    if UI.classChoice then UI.classChoice.selected = nil; UI.classChoice.refreshText() end
    if UI.onlineCheck then UI.onlineCheck.set(false) end
    if UI.levelBox then UI.levelBox:SetText("") end
    if searchBox then searchBox:SetText("") end
    UI.refresh(true)
end

-- GF-UI-B (GF-UI-A §1.2, §2.2): the page from top to bottom:
--   tool bar (y -36, 30 px controls):
--     [更新] 搜尋 [box] [專業][職業] [ ]在線 [ ]接單中 等級 [  ] 以上 [清除]   [人頭] 12/80
--   column header (y -76, 28 px, gold, arrow textures)
--   the list (36 px rows)
--   the chosen member's buttons (44 px bar)
--   bottom row: [邀請] [公會] [遊戲公會] [診斷] on the right
UI.TOOLBAR_Y, UI.HEADER_Y, UI.HEADER_H, UI.LIST_TOP, UI.LIST_BOTTOM = -36, -76, 28, -106, 100
UI.TOOLBAR_GAP = 8
UI.EMPTY_ICON = 48

-- The middle of the list when there are no rows (UI.EMPTY).
function UI.drawEmpty(state)
    local e = state and UI.EMPTY[state]
    UI.emptyKey = state
    if not e then
        UI.emptyIcon:Hide(); UI.emptyLabel:SetText(""); UI.emptyLabel:Hide(); UI.emptyUpdate:Hide()
        return
    end
    ns.GameIcons.set(UI.emptyIcon, e.art)
    if UI.emptyIcon.SetDesaturated then UI.emptyIcon:SetDesaturated(e.grey == true) end
    UI.emptyLabel:SetText(e.text)
    if e.text ~= "" then UI.emptyLabel:Show() else UI.emptyLabel:Hide() end
    if state == "noRoster" then UI.emptyUpdate:Show() else UI.emptyUpdate:Hide() end
end

-- The member count, right-aligned on the tool bar: [人頭] shown/all.
function UI.placeCount()
    local w = ns.measure(UI.countText)
    local right = UI.ROW_WIDTH + 20
    UI.countText:ClearAllPoints()
    UI.countText:SetPoint("TOPLEFT", panel, "TOPLEFT", right - w, UI.TOOLBAR_Y - 6)
    UI.countIcon:ClearAllPoints()
    UI.countIcon:SetPoint("TOPLEFT", panel, "TOPLEFT", right - w - 24, UI.TOOLBAR_Y - 5)
    if UI.countText:GetText() ~= "" then UI.countIcon:Show() else UI.countIcon:Hide() end
end

local function build(p)
    panel = p
    local f = p
    local G = ns.GuildAdmin
    local O = ns.OrdersUI
    local GI = ns.GameIcons
    local Y = UI.TOOLBAR_Y
    local x = 20
    local function after(w) x = x + w + UI.TOOLBAR_GAP end
    local function label(text)
        local l = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT))
        l:SetPoint("TOPLEFT", f, "TOPLEFT", x, Y - 6)
        l:SetText(text)
        x = x + ns.labelWidth(text) + 2
        return l
    end
    -- GF-UI-C (item 12): text buttons in words only.
    UI.updateButton = button(f, "更新", nil, nil, x, Y, manualUpdate)
    after(UI.updateButton.gfWidth)
    label("搜尋")
    searchBox = ns.Theme.editBox(f)
    searchBox:SetSize(120, ns.BUTTON_H)
    searchBox:SetPoint("TOPLEFT", f, "TOPLEFT", x + 4, Y)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(100)
    searchBox:SetScript("OnTextChanged", function() UI.refresh(true) end)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    UI.searchBox = searchBox
    after(124)
    -- GF-UI-C (owner): multi-select lists with check boxes.
    UI.skillChoice = ns.multiChoiceButton(f, 110, x, Y, UI.professionOptions,
        function() UI.syncChoiceFilters(); UI.refresh(true) end, UI.choiceSummary("全部專業", "專業"))
    after(110)
    UI.classChoice = ns.multiChoiceButton(f, 110, x, Y, UI.classOptions,
        function() UI.syncChoiceFilters(); UI.refresh(true) end, UI.choiceSummary("全部職業", "職業"))
    after(110)
    UI.onlineCheck = ns.checkBox(f, "在線", x, Y - 1,
        function(on) UI.filters.online = on; UI.refresh(true) end)
    after(28 + ns.labelWidth("在線"))
    -- GF-006-B (R-4.2): 只看接單中 (GF-UI-C: the words are enough).
    local hammer = "接單中"
    UI.activeCheck = ns.checkBox(f, hammer, x, Y - 1,
        function(on) UI.filters.active = on; UI.refresh(true) end)
    after(28 + ns.labelWidth(hammer))
    UI.levelLabel = label("等級")
    UI.levelBox = ns.Theme.editBox(f)
    UI.levelBox:SetSize(40, ns.BUTTON_H)
    UI.levelBox:SetPoint("TOPLEFT", f, "TOPLEFT", x + 4, Y)
    UI.levelBox:SetAutoFocus(false)
    UI.levelBox:SetMaxLetters(2)
    if UI.levelBox.SetNumeric then UI.levelBox:SetNumeric(true) end
    UI.levelBox:SetScript("OnTextChanged", function(self)
        local n = tonumber(str(self:GetText()))
        UI.filters.minLevel = (n and n > 1) and n or nil
        UI.refresh(true)
    end)
    UI.levelBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    x = x + 4 + 40 + 8 -- the box border is drawn ~6 px outside it
    UI.levelSuffix = label("以上")
    x = x + UI.TOOLBAR_GAP - 2
    UI.clearButton = button(f, "清除", nil, nil, x, Y, UI.clearFilters)
    after(UI.clearButton.gfWidth)
    UI.toolbarRight = x
    UI.countIcon = f:CreateTexture(nil, "ARTWORK")
    UI.countIcon:SetSize(20, 20)
    GI.set(UI.countIcon, "person")
    UI.countText = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
    UI.countText:SetText("")
    rosterControls = { UI.updateButton, searchBox, UI.clearButton, UI.skillChoice, UI.classChoice,
        UI.onlineCheck, UI.levelBox }
    -- Column header: 28 px, a faint bar with a line (GF-UI-D), gold names; the sorted one white with an arrow.
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 20, UI.HEADER_Y)
    header:SetSize(UI.ROW_WIDTH, UI.HEADER_H)
    ns.Theme.headerBar(header) -- GF-UI-D: a faint bar and a 1 px line under it
    UI.header = header
    for _, col in ipairs(columns) do
        local heading = CreateFrame("Button", nil, header)
        heading:SetPoint("LEFT", header, "LEFT", col.x, 0)
        heading:SetSize(col.w - 2, UI.HEADER_H)
        local text = heading:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT)
        text:SetPoint("LEFT", heading, "LEFT", 0, 0)
        text:SetJustifyH("LEFT")
        text:SetWordWrap(false)
        local arrow = heading:CreateTexture(nil, "ARTWORK")
        arrow:SetSize(16, 16)
        arrow:Hide()
        if not col.noSort then
            heading:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            heading:SetScript("OnClick", function() changeSort(col) end)
            rosterControls[#rosterControls + 1] = heading
        end
        heading.fieldNamed = col.name
        sortHeaders[#sortHeaders + 1] = { col = col, label = text, heading = heading, arrow = arrow }
    end
    updateSortHeaders()
    rowScroll = ns.createFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    rowScroll:SetPoint("TOPLEFT", 20, UI.LIST_TOP)
    rowScroll:SetPoint("BOTTOMRIGHT", -40, UI.LIST_BOTTOM)
    rowContent = CreateFrame("Frame", nil, rowScroll)
    rowContent:SetSize(UI.ROW_WIDTH, 1)
    -- No rows: a 48 px icon and a short name in the middle (GF-UI-A §2.2 item 3).
    UI.emptyIcon = f:CreateTexture(nil, "ARTWORK")
    UI.emptyIcon:SetSize(UI.EMPTY_ICON, UI.EMPTY_ICON)
    UI.emptyIcon:SetPoint("TOP", f, "TOP", -20, UI.LIST_TOP - 80)
    UI.emptyIcon:Hide()
    UI.emptyLabel = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.TITLE_FONT))
    UI.emptyLabel:SetPoint("TOP", UI.emptyIcon, "BOTTOM", 0, -10)
    UI.emptyLabel:Hide()
    UI.emptyUpdate = O.textButton(f, "更新", manualUpdate)
    UI.emptyUpdate:SetPoint("TOP", UI.emptyIcon, "BOTTOM", 0, -10)
    UI.emptyUpdate:Hide()
    -- GF-001-Q: the selected member's actions (the same as the right-click menu).
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 20, UI.LIST_BOTTOM - 6)
    bar:SetSize(UI.ROW_WIDTH, 44)
    ns.Theme.barPanel(bar) -- GF-UI-D: a faint panel with a line on top
    bar.name = ns.freeText(bar:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT))
    bar.name:SetPoint("LEFT", bar, "LEFT", 10, 0)
    bar.nameWidth = 170
    bar.buttons = {}
    UI.actionBar = bar
    rowScroll:SetScrollChild(rowContent)
    -- Rows are refilled while scrolling; own-profession buttons follow
    -- (hidden when the row is out of view).
    rowScroll:HookScript("OnVerticalScroll", function()
        UI.layoutRows()
        UI.placeOwnButtons()
    end)
    -- They live on UIParent: hide them with the page (in combat they already are).
    p:HookScript("OnHide", function() ns.Professions.hideFrom("roster", 1) end)
    -- Bottom row: 診斷 on the right; the guild buttons left of it (refreshAdminButtons).
    syncIndicator = ns.Diag.smallButton(f, "BOTTOMRIGHT", -20, UI.BOTTOM_Y)
    UI.syncIndicator = syncIndicator
    UI.diagLeft = ns.Framework.PANEL_WIDTH - 20 - (syncIndicator.gfWidth or 0)
    -- GF-001-Q, GF-UI-C (owner): 邀請 / 公會, text only (遊戲公會 is gone).
    UI.inviteButton = O.textButton(f, "邀請", function() G.inviteGuild() end)
    UI.infoButton = O.textButton(f, "公會", function() UI.openGuildInfo() end)
    UI.buildCensus(f)
end

ns.Framework.register({
    id = "roster",
    title = "公會名冊",
    order = 10,
    create = build,
    -- GF-UI-B: the guild's name in the window title (it left the page).
    windowTitle = function()
        local s = ns.guildState() == "target" and ns.Roster.current() or nil
        return s and str(s.guild) ~= "" and s.guild or nil
    end,
    show = function() if ns.GuildAdmin then ns.GuildAdmin.invalidate() end UI.refresh(true) end,
})

function UI.toggle() return ns.Framework.toggle("roster") end
function UI.isShown() return ns.Framework.isModuleShown("roster") end

---------------------------------------------------------------------------
-- Export window
---------------------------------------------------------------------------

local function refreshExport()
    if not exportWindow then return end
    local s = ns.Roster.current()
    local part = exportParts[exportPartIndex] or ""
    exportInfo:SetText(string.format("%s｜公會：%s｜掃描：%s（本機）",
        exportFormat == "json" and "JSON（供網站匯入）" or "TSV（供試算表使用）",
        str(s and s.guild), Export.timestampText(s)))
    partLabel:SetText(string.format("第 %d / %d 段（每段均需個別複製）", exportPartIndex, #exportParts))
    prevPart:SetEnabled(exportPartIndex > 1)
    nextPart:SetEnabled(exportPartIndex < #exportParts)
    exportEdit:SetText(part)
    exportEdit:SetHeight(math.max(400, math.ceil(#part / 70) * 18 + 60))
    exportWindow.scroll:SetVerticalScroll(0)
    exportEdit:SetFocus()
    exportEdit:HighlightText()
end

local function createExport()
    if exportWindow then return end
    local f = ns.popupWindow("GreenFangToolkit_ExportWindow", 920, 560)
    f:SetPoint("CENTER", 0, 10)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    if f.TitleText then f.TitleText:SetText("綠皮冒險工具箱｜報告匯出") end
    exportWindow = f
    exportInfo = f:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)
    exportInfo:SetPoint("TOPLEFT", 20, -37)
    exportInfo:SetWidth(870)
    exportInfo:SetJustifyH("LEFT")
    local instruction = f:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT)
    instruction:SetPoint("TOPLEFT", 20, -58)
    instruction:SetWidth(870)
    instruction:SetJustifyH("LEFT")
    instruction:SetText("點「全選內容」，按 Ctrl+C 複製；JSON 每段都是有效 JSON，網站匯入時按 part 合併。")
    button(f, "全選內容", 120, 26, 20, -79, function()
        exportEdit:SetFocus()
        exportEdit:HighlightText()
    end)
    prevPart = button(f, "上一段", 99, 26, 148, -79, function()
        if exportPartIndex > 1 then exportPartIndex = exportPartIndex - 1; refreshExport() end
    end)
    nextPart = button(f, "下一段", 99, 26, 255, -79, function()
        if exportPartIndex < #exportParts then exportPartIndex = exportPartIndex + 1; refreshExport() end
    end)
    partLabel = f:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)
    partLabel:SetPoint("TOPLEFT", 374, -85)
    partLabel:SetWidth(480)
    partLabel:SetJustifyH("LEFT")
    local scroll = ns.createFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -121)
    scroll:SetPoint("BOTTOMRIGHT", -37, 24)
    exportEdit = CreateFrame("EditBox", nil, scroll)
    exportEdit:SetMultiLine(true)
    exportEdit:SetAutoFocus(false)
    exportEdit:SetFontObject(ns.LABEL_FONT)
    exportEdit:SetWidth(836)
    exportEdit:SetHeight(405)
    exportEdit:SetTextInsets(4, 4, 4, 4)
    exportEdit:SetMaxLetters(0)
    exportEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
    scroll:SetScrollChild(exportEdit)
    f.scroll = scroll
    f:Hide()
end

function UI.startExport(format)
    local unavailable = UI.unavailableText()
    if unavailable then ns.say(unavailable); return end
    local s = ns.Roster.current()
    if not s then ns.say("尚無名冊；先按「更新名冊」取得公會資料。"); return end
    exportFormat = format == "json" and "json" or "tsv"
    exportParts = exportFormat == "json" and Export.jsonParts(s) or Export.tsvParts(s)
    exportPartIndex = 1
    createExport()
    refreshExport()
    exportWindow:Show()
end
