-- UI: the roster module (first module of the toolkit window) and the export
-- window. Layout and behaviour are unchanged from v0.3.1.

local _, ns = ...
local str, keyName = ns.str, ns.keyName
local Export = ns.Export
local Icons = ns.Icons

local UI = {}
ns.UI = UI

local ROW_HEIGHT = 23
local panel, exportWindow
local rowScroll, rowContent, searchBox, reportLine, summaryLine, statusLine
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
    level = true, zone = true, online = true }
-- Professions cell (GF-001-D18, was text since D8): one line, the
-- profession's built-in icon and its skill points ("[icon]300"), primary
-- first. Cooking / first aid / fishing follow only while they fit whole;
-- they are never counted, the tooltip has them. A primary that does not fit
-- is counted as "+N". Members known only from the guild roster (no points)
-- get the icon alone; a profession without an icon falls back to its name.
-- "－" (full-width, faint) means no data. Row height is unchanged.
-- GF-001-D19: icons 20 px (were 14), full colour for names-only members;
-- each icon has its own short tooltip, and a click filters the roster.
local LIST_SLOTS, LIST_GAP, GROUP_GAP = 6, 8, 6
local ICON_SIZE, ICON_GAP, MORE_WIDTH = 20, 2, 20
local NO_DATA = "－"
local SECONDARY_COLOR, NAMES_COLOR, TEXT_COLOR = { 0.72, 0.8, 0.74 }, { 0.6, 0.6, 0.6 }, { 1, 1, 1 }
local NO_DATA_COLOR = { 0.42, 0.42, 0.42 }
local NAMES_ALPHA, SECONDARY_ALPHA = 1, 0.85
local ONLINE_COLOR, OFFLINE_COLOR = { 0.4, 1, 0.4 }, { 0.55, 0.55, 0.55 }
local RANK_COLOR = { 0.85, 0.82, 0.65 }

-- Make each visible row from the stored snapshot, never from a stale chat printout.
local columns = {
    { name = "角色", key = "name", x = 5, w = 160 },
    { name = "會階", key = "rank", x = 168, w = 78 },
    { name = "種族", key = "race", x = 249, w = 76 },
    { name = "職業", key = "class", x = 328, w = 100, icon = true },
    { name = "專業技能", key = "professions", x = 431, w = 300 },
    { name = "等級", key = "level", x = 734, w = 40, firstDescending = true, center = true },
    { name = "位置", key = "zone", x = 777, w = 92 },
    { name = "狀態", key = "online", x = 872, w = 62, firstDescending = true },
}

---------------------------------------------------------------------------
-- Sorting and filtering (pure; covered by offline tests)
---------------------------------------------------------------------------

-- Sort only the visible list; never alter the captured report.
-- Missing values stay at the bottom in either direction.
local function sortValue(m, key)
    if key == "level" then return type(m.level) == "number" and m.level or 0 end
    if key == "online" then return m.online == true and 1 or 0 end
    if key == "rank" then return type(m.rankIndex) == "number" and m.rankIndex or nil end
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
UI.filters = { skill = nil, class = nil, online = false, minLevel = nil, active = false }

local function passes(m, f)
    if not f then return true end
    if f.online and m.online ~= true then return false end
    if f.class and m.classToken ~= f.class then return false end
    if f.minLevel and (type(m.level) ~= "number" or m.level < f.minLevel) then return false end
    if f.skill and not UI.memberSkills(m)[f.skill] then return false end
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
    local list = { { value = nil, text = "全部專業" } }
    for _, id in ipairs(PROFESSION_ORDER) do
        if have[id] then list[#list + 1] = { value = id, text = ns.Data.skillName(nil, id) or ("專業 " .. id) } end
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
    table.insert(list, 1, { value = nil, text = "全部職業" })
    return list
end

-- Set the profession filter (icon click: the same one again clears it).
function UI.setSkillFilter(id)
    UI.filters.skill = id
    if UI.skillChoice then UI.skillChoice.value = id; UI.skillChoice.refreshText() end
    UI.refresh(true)
end

function UI.loadSettings()
    local s = ns.settings()
    if UI.SORT_KEYS[s.sortKey] then UI.sortKey = s.sortKey end
    if type(s.sortAscending) == "boolean" then UI.sortAscending = s.sortAscending end
end

---------------------------------------------------------------------------
-- Main window
---------------------------------------------------------------------------

local function button(parent, text, w, h, x, y, callback)
    local b = ns.createFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", callback)
    return b
end

local function updateSortHeaders()
    for _, entry in ipairs(sortHeaders) do
        local active = entry.col.key == UI.sortKey
        entry.label:SetText(entry.col.name .. (active and (UI.sortAscending and " ▲" or " ▼") or ""))
        if active then
            entry.label:SetTextColor(0.53, 1.0, 0.68)
        else
            entry.label:SetTextColor(1, 0.82, 0)
        end
    end
end

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
    row:SetSize(936, ROW_HEIGHT)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.cells = {}
    for j, col in ipairs(columns) do
        local font = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        local x, w = col.x, col.w
        if col.icon then
            row.classIcon = row:CreateTexture(nil, "ARTWORK")
            row.classIcon:SetSize(16, 16)
            row.classIcon:SetPoint("LEFT", row, "LEFT", col.x, 0)
            x, w = col.x + 20, col.w - 20
        end
        font:SetPoint("LEFT", row, "LEFT", x, 0)
        font:SetWidth(w)
        font:SetHeight(ROW_HEIGHT)
        font:SetJustifyH(col.center and "CENTER" or "LEFT")
        font:SetWordWrap(false)
        row.cells[j] = font
        if col.key == "professions" then
            row.profX, row.profW = col.x, col.w
            row.profSlots = {}
            for k = 1, LIST_SLOTS do
                local icon = row:CreateTexture(nil, "ARTWORK")
                icon:SetSize(ICON_SIZE, ICON_SIZE)
                icon:Hide()
                local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                label:SetHeight(ROW_HEIGHT)
                label:SetJustifyH("LEFT")
                label:SetWordWrap(false)
                -- GF-006-B (R-4.2): gold hammer corner on an active profession.
                local badge = row:CreateTexture(nil, "OVERLAY")
                badge:SetSize(10, 10)
                badge:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 3, -3)
                badge:Hide()
                local slot = { icon = icon, label = label, badge = badge }
                row.profSlots[k] = slot
            end
            row.profMore = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
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
    -- Click on a profession: filter the roster by it (again: clear).
    -- Elsewhere: that member's recipes (D-013). A plain frame, nothing secure.
    row:SetScript("OnMouseUp", function(self, mouse)
        local slot = UI.slotAt(self, UI.cursorX(self))
        local id = slot and slot.entry.prof and ns.Professions.skillLineOf(slot.entry.prof)
        -- GF-006-B (R-5.1): right-click someone's profession = 「下單給〈名字〉」.
        if mouse == "RightButton" and id and ns.OrdersUI then
            local m = { guid = self.memberGuid, name = self.memberName }
            ns.showMenu(self, ns.OrdersUI.rosterMenuItems(m, id))
            return
        end
        if id then
            UI.setSkillFilter(UI.filters.skill ~= id and id or nil)
        elseif UI.hasRecipes(self.memberGuid) then
            ns.Recipes.show(self.memberGuid)
        end
    end)
    rowWidgets[i] = row
    return row
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
    if not detail and not (names and #names > 0) then
        GameTooltip:Hide()
        return
    end
    GameTooltip:AddLine(str(row.memberName))
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

-- "2026-11-20 21:05" (header): the scan time without seconds.
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

-- Message shown instead of the roster, or nil when the roster is available.
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
    if unavailable then
        reportLine:SetText(unavailable)
        summaryLine:SetText("睡袋路線等其他功能照常可以使用。")
        statusLine:SetText(ns.Sync.guildNote() or "")
    elseif s then
        -- D-014 point 6: only what players use; scan details are in 「同步與診斷」.
        reportLine:SetText(string.format("%s｜%d 位成員｜%s 更新",
            s.guild or "", s.total or #s.members, UI.shortTime(s)))
        summaryLine:SetText("")
        matching = UI.sortMembers(UI.filterMembers(s.members, searchBox and searchBox:GetText() or "", UI.filters),
            UI.sortKey, UI.sortAscending)
        statusLine:SetText(string.format("顯示 %d / %d 位", #matching, #s.members))
    else
        reportLine:SetText("尚無名冊；按「更新名冊」取得公會資料。")
        summaryLine:SetText("")
        statusLine:SetText("")
    end
    UI.refreshSyncIndicator()
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
    for k = 1, math.max(count, #rowWidgets) do
        local i = first + k - 1
        local m = k <= count and matching[i] or nil
        local row = rowWidgets[k] or (m and newRow(k)) or nil
        if row then
            if m then
                row.index = i
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", rowContent, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
                row.bg:SetColorTexture(0.17, 0.2, 0.18, i % 2 == 0 and 0.35 or 0.09)
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

-- One roster row: class icon and colour, rank, centred level, coloured status.
function UI.fillRow(row, m)
    local color = Icons.classColor(m.classToken)
    local cells = row.cells
    cells[1]:SetText(str(m.name))
    cells[1]:SetTextColor(color[1], color[2], color[3])
    cells[2]:SetText(str(m.guildRank))
    cells[2]:SetTextColor(RANK_COLOR[1], RANK_COLOR[2], RANK_COLOR[3])
    cells[3]:SetText(Export.raceText(m))
    Icons.setClassIcon(row.classIcon, m.classToken)
    cells[4]:SetText(str(m.class))
    cells[4]:SetTextColor(color[1], color[2], color[3])
    fillProfessions(row, cells[5], m)
    cells[6]:SetText(tostring(m.level or 0))
    cells[7]:SetText(str(m.zone) ~= "" and str(m.zone) or "未記錄")
    local status = m.online and ONLINE_COLOR or OFFLINE_COLOR
    cells[8]:SetText(m.online and "在線" or "離線")
    cells[8]:SetTextColor(status[1], status[2], status[3])
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
    summaryLine:SetText("名冊更新中，請稍候。")
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
    UI.filters.active = false
    if UI.activeCheck then UI.activeCheck.set(false) end
    if UI.skillChoice then UI.skillChoice.value = nil; UI.skillChoice.refreshText() end
    if UI.classChoice then UI.classChoice.value = nil; UI.classChoice.refreshText() end
    if UI.onlineCheck then UI.onlineCheck.set(false) end
    if UI.levelBox then UI.levelBox:SetText("") end
    if searchBox then searchBox:SetText("") end
    UI.refresh(true)
end

-- Build the roster page into the framework panel (same coordinates as the
-- old stand-alone window, which the panel replaces).
local function build(p)
    panel = p
    local f = p
    reportLine = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    reportLine:SetPoint("TOPLEFT", 22, -38)
    reportLine:SetWidth(955)
    reportLine:SetJustifyH("LEFT")
    summaryLine = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    summaryLine:SetPoint("TOPLEFT", 22, -58)
    summaryLine:SetWidth(940)
    summaryLine:SetJustifyH("LEFT")
    UI.updateButton = button(f, "更新名冊", 115, 26, 20, -80, manualUpdate)
    -- GF-001-D20: one filter line with room between every control:
    -- [更新名冊] 搜尋 [box]  [專業 ▼]  [職業 ▼]  [ ] 只看在線  等級 [  ] 以上  [清除]
    local function label(text, x)
        local l = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        l:SetPoint("TOPLEFT", f, "TOPLEFT", x, -87)
        l:SetText(text)
        return l
    end
    label("搜尋", 150)
    searchBox = ns.createFrame("EditBox", nil, f, "InputBoxTemplate")
    searchBox:SetSize(150, 24)
    searchBox:SetPoint("TOPLEFT", f, "TOPLEFT", 186, -80)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(100)
    searchBox:SetScript("OnTextChanged", function() UI.refresh(true) end)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    UI.searchBox = searchBox
    UI.skillChoice = ns.choiceButton(f, 110, 352, -80, UI.professionOptions,
        function(value) UI.filters.skill = value; UI.refresh(true) end, "全部專業",
        function(id) return ns.Data.skillName(nil, id) end)
    UI.classChoice = ns.choiceButton(f, 100, 474, -80, UI.classOptions,
        function(value) UI.filters.class = value; UI.refresh(true) end, "全部職業")
    UI.onlineCheck = ns.checkBox(f, "只看在線", 588, -80,
        function(on) UI.filters.online = on; UI.refresh(true) end)
    UI.levelLabel = label("等級", 684)
    UI.levelBox = ns.createFrame("EditBox", nil, f, "InputBoxTemplate")
    UI.levelBox:SetSize(40, 24)
    UI.levelBox:SetPoint("TOPLEFT", f, "TOPLEFT", 724, -80)
    UI.levelBox:SetAutoFocus(false)
    UI.levelBox:SetMaxLetters(2)
    if UI.levelBox.SetNumeric then UI.levelBox:SetNumeric(true) end
    UI.levelBox:SetScript("OnTextChanged", function(self)
        local n = tonumber(str(self:GetText()))
        UI.filters.minLevel = (n and n > 1) and n or nil
        UI.refresh(true)
    end)
    UI.levelBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    UI.levelSuffix = label("以上", 776)
    UI.clearButton = button(f, "清除", 60, 25, 816, -80, UI.clearFilters)
    -- GF-006-B (R-4.2): 只看接單中 (gold hammer).
    UI.activeCheck = ns.checkBox(f, (ns.OrdersUI and ns.OrdersUI.tex("hammer", 14) or "") .. " 接單中", 884, -80,
        function(on) UI.filters.active = on; UI.refresh(true) end)
    rosterControls = { UI.updateButton, searchBox, UI.clearButton, UI.skillChoice, UI.classChoice,
        UI.onlineCheck, UI.levelBox }
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -119)
    header:SetSize(937, 25)
    local bg = header:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.13, 0.37, 0.30, 0.4)
    for _, col in ipairs(columns) do
        local heading = CreateFrame("Button", nil, header)
        heading:SetPoint("LEFT", header, "LEFT", col.x, 0)
        heading:SetSize(col.w - 2, 25)
        local label = heading:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        label:SetAllPoints()
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        heading:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        heading:SetScript("OnClick", function() changeSort(col) end)
        rosterControls[#rosterControls + 1] = heading
        sortHeaders[#sortHeaders + 1] = { col = col, label = label }
    end
    updateSortHeaders()
    rowScroll = ns.createFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    rowScroll:SetPoint("TOPLEFT", 20, -149)
    rowScroll:SetPoint("BOTTOMRIGHT", -40, 51)
    rowContent = CreateFrame("Frame", nil, rowScroll)
    rowContent:SetSize(938, 1)
    rowScroll:SetScrollChild(rowContent)
    -- Rows are refilled while scrolling; own-profession buttons follow
    -- (hidden when the row is out of view).
    rowScroll:HookScript("OnVerticalScroll", function()
        UI.layoutRows()
        UI.placeOwnButtons()
    end)
    -- They live on UIParent: hide them with the page (in combat they already are).
    p:HookScript("OnHide", function() ns.Professions.hideFrom("roster", 1) end)
    statusLine = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    statusLine:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 22, 20)
    statusLine:SetWidth(700)
    syncIndicator = ns.Diag.smallButton(f, "BOTTOMRIGHT", -20, 14)
    UI.syncIndicator = syncIndicator
    statusLine:SetJustifyH("LEFT")
end

ns.Framework.register({
    id = "roster",
    title = "公會名冊",
    order = 10,
    create = build,
    show = function() UI.refresh(true) end,
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
    if UISpecialFrames then table.insert(UISpecialFrames, "GreenFangToolkit_ExportWindow") end
    exportWindow = f
    exportInfo = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    exportInfo:SetPoint("TOPLEFT", 20, -37)
    exportInfo:SetWidth(870)
    exportInfo:SetJustifyH("LEFT")
    local instruction = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
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
    partLabel = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    partLabel:SetPoint("TOPLEFT", 374, -85)
    partLabel:SetWidth(480)
    partLabel:SetJustifyH("LEFT")
    local scroll = ns.createFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -121)
    scroll:SetPoint("BOTTOMRIGHT", -37, 24)
    exportEdit = CreateFrame("EditBox", nil, scroll)
    exportEdit:SetMultiLine(true)
    exportEdit:SetAutoFocus(false)
    exportEdit:SetFontObject("ChatFontNormal")
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
