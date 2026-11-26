-- SupplyUI (GF-009-05/08, v2.0 §7, 附錄 A §7): the 綠皮調貨所 page and the
-- listing form. Built from the theme (Theme.lua) and the toolkit's widgets
-- only; every item row is the game's own item icon + name + quantity. Only
-- the visible rows have frames; the page reads local results and never sends
-- anything by itself. 聯絡 only fills the whisper box; the player sends it.

local _, ns = ...
local str = ns.str

local UI = {}
ns.SupplyUI = UI
local Supply, L = ns.Supply, ns.SupplyListings
local Th, W = ns.Theme, ns.Widgets

UI.ID = "supply"
UI.ROW_H, UI.ICON = 44, 36
UI.ROWS = 11
UI.LIST_X, UI.LIST_W = 22, 540
-- GF-UI-I (owner 0.16.2: 中間一條直線、右半邊空著): with nothing to show on
-- the right (no row chosen, or a row without matches) the list takes the
-- whole width and the divider goes away; the extra width goes to 物品.
UI.LIST_W_WIDE = 1056
function UI.listWidth() return UI.state and UI.state.wide and UI.LIST_W_WIDE or UI.LIST_W end
UI.DETAIL_X, UI.DETAIL_W = 586, 492
UI.DETAIL_ROWS = 9
-- GF-UI-F: a column header over the list (物品 / 數量 / 可能提供 or 需要 / 時效),
-- the rows under it; the detail on the right starts at the header too.
-- GF-UI-H (owner 0.16.0: 分頁「調貨所」壓在標題上、「我的刊登」和「刊登」貼在一起、
-- 「手動刊登」貼右邊界): no page title of its own (the window title and the
-- sub-tab already name it); under the sub-tab row (its line ends 29 px into
-- the page) come two rows: BAR_Y the tabs + the two check boxes over the
-- detail column; TOOL_Y 收集組 on the left and 刊登 at the list's right edge.
UI.BAR_Y, UI.TOOL_Y = -40, -84
UI.CHECK_X = { auto = 586, manual = 786 }
UI.POST_W = 96
UI.POST_TEXT = "＋刊登"
UI.HEAD_Y, UI.HEAD_H = -128, 28
UI.TOP = UI.HEAD_Y - UI.HEAD_H - 4
UI.EXPAND = 16
-- Row columns (x inside a row, width); the quantity is right-aligned.
UI.COL = {
    expand = { x = 4, w = 16 },
    icon = { x = 24, w = 36 },
    name = { x = 66, w = 180 },
    qty = { x = 252, w = 92 },
    match = { x = 356, w = 96 },
    fresh = { x = 460, w = 72 },
}
-- The detail list: who, how many, online, how fresh, where from, 聯絡.
UI.DETAIL_HEAD_Y = UI.HEAD_Y - 52
UI.DETAIL_TOP = UI.DETAIL_HEAD_Y - UI.HEAD_H - 4
UI.DCOL = {
    name = { x = 4, w = 130 }, what = { x = 138, w = 96 }, on = { x = 238, w = 44 },
    fresh = { x = 286, w = 44 }, src = { x = 334, w = 84 },
}
UI.FORM_NAME = "GreenFangToolkit_SupplyForm"
UI.PICKER_NAME = "GreenFangToolkit_SupplyBagPicker"
UI.FINDER_NAME = "GreenFangToolkit_SupplyItemFinder"
UI.PLACEHOLDER = "Interface\\Icons\\INV_Misc_QuestionMark"
-- GF-UI-F: no sentence under the list; the same words are the 聯絡 tooltip.
UI.CONTACT_TIP = "僅供資訊媒合，交換條件由雙方自行協議"
UI.POPUP_DISCARD = "GREENFANGTOOLKIT_SUPPLY_DISCARD"
UI.DISCARD_TEXT = "放棄未儲存的修改？"

-- Column names per tab (GF-UI-F).
UI.HEADINGS = {
    need = { "物品", "數量", "可能提供", "時效" },
    offer = { "物品", "數量", "需要", "時效" },
    guild = { "物品", "徵求／供應", "在線", "時效" },
    mine = { "物品", "數量", "狀態", "時效" },
}
UI.DETAIL_HEADINGS = { "成員", "數量", "在線", "時效", "條件" } -- GF-009-14 B: 來源 → 交易條件 (自動 rows say 自動)
UI.NOTE_ICON = "Interface\\Buttons\\UI-GuildButton-PublicNote-Up" -- shown only when there is a note
UI.NOTE_ICON_SIZE = 14
-- 收集組 only where the lists come from the collection rules.
UI.GROUP_TABS = { need = true, offer = true }
UI.GROUP_X, UI.GROUP_W = 22, 170
UI.EXPAND_CLOSED = "Interface\\Buttons\\UI-PlusButton-Up"
UI.EXPAND_OPEN = "Interface\\Buttons\\UI-MinusButton-Up"

UI.TABS = {
    { key = "need", text = "我缺的" },
    { key = "offer", text = "我可能有多的" },
    { key = "guild", text = "調貨看板" }, -- GF-UI-H: owner named it (was 公會供需); the key stays
    { key = "mine", text = "我的刊登" },
}
UI.EMPTY = {
    need = "目前沒有缺的物品",
    offer = "目前沒有可能多的物品",
    guild = "目前沒有可配對的公會物資",
    mine = "還沒有刊登",
}

local panel, tabs, statePanel, autoBox, manualBox, postButton, header, detailHeader
local groupLabel, groupButton
local rows, detailRows = {}, {}
local detail = {}
local state = { tab = "need", offset = 0, selected = nil, items = {}, group = nil }
UI.state = state

-- f.tip under the mouse (check boxes, buttons, edit boxes of this page).
local function withTip(f)
    if not f or not f.HookScript then return f end
    f:HookScript("OnEnter", function(self)
        if self.tip and GameTooltip then
            self.gfSupplyTip = true -- GF-009-13: hidden with its window (UI.hideTip)
            GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(self.tip, 1, 1, 1, true); GameTooltip:Show()
        end
    end)
    f:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return f
end
UI.withTip = withTip

---------------------------------------------------------------------------
-- Texts (pure, tested offline)
---------------------------------------------------------------------------

local function sourceText(e)
    if e.auto and e.manual then return "自動＋手動" end
    if e.manual then return "手動" end
    return "自動"
end
UI.sourceText = sourceText

-- The quantity next to an item: 「缺 1」「可能多 2」「徵求 3」「供應 1」.
function UI.qtyText(kind, it)
    if kind == "need" then return "缺 " .. it.qty end
    if kind == "offer" then
        if it.mine and it.mine.manual and not it.mine.auto then return "供應 " .. it.qty end
        return "可能多 " .. it.qty
    end
    if kind == "guild" then
        local parts = {}
        if #it.needs > 0 then parts[#parts + 1] = "徵求 " .. #it.needs .. " 位" end
        if #it.offers > 0 then parts[#parts + 1] = "供應 " .. #it.offers .. " 位" end
        return table.concat(parts, "　")
    end
    return ""
end

-- The right side of a row: who matches.
function UI.matchText(kind, it)
    local n = #it.others
    if kind == "need" then return n > 0 and ("可能提供 " .. n .. " 位") or "暫無提供者" end
    if kind == "offer" then return n > 0 and ("需要的 " .. n .. " 位") or "暫無需要者" end
    if kind == "guild" then return it.onlineCount > 0 and ("在線 " .. it.onlineCount .. " 位") or "都不在線" end
    return ""
end

-- The short cells under the column header (GF-UI-F): 「2 位」「暫無」.
function UI.matchShort(kind, it)
    if kind == "guild" then return it.onlineCount > 0 and (it.onlineCount .. " 位") or "離線" end
    local n = #it.others
    return n > 0 and (n .. " 位") or "暫無"
end
function UI.qtyShort(kind, it)
    if kind == "guild" then return #it.needs .. "／" .. #it.offers end
    return UI.qtyText(kind, it)
end
-- 時效 of a row: the best match's, else my own entry's.
function UI.freshShort(it)
    local e = it.others and it.others[1] or it.mine
    return e and (Supply.FRESH_TEXT[e.fresh or "unknown"] or "未知") or ""
end

-- One person line in the detail list.
-- GF-009-14 B: the manual listing behind a person row (the largest one).
function UI.manualOf(e) return e and e.manual or nil end
-- Its tooltip lines: terms, the full note, the source.
function UI.listingTipLines(e, withName)
    local m = UI.manualOf(e)
    local out = {}
    local who = withName and e.member and (ns.shortName(e.member.name) .. "：") or ""
    if m then
        out[#out + 1] = who .. L.DIRECTION_TEXT[e.direction] .. " " .. (m.quantity or e.qty) .. "｜交易條件："
            .. L.termsText(m.terms, m.price)
        if m.note and m.note ~= "" then out[#out + 1] = (withName and "　" or "") .. "備註：" .. m.note end
    end
    if e.auto and not withName then out[#out + 1] = "來源：" .. sourceText(e) end
    return out
end
function UI.condText(e)
    local m = UI.manualOf(e)
    if not m then return "自動" end
    return L.termsText(m.terms, m.price, true)
end

function UI.personText(e)
    local name = e.member and ns.shortName(e.member.name) or "未知"
    -- GF-UI-H: automatic candidates read 可能提供 (manual ones 徵求／供應, below).
    local what = e.direction == "need" and ("缺 " .. e.qty) or ("可能提供 " .. e.qty)
    if e.manual and not e.auto then what = (e.direction == "need" and "徵求 " or "供應 ") .. e.qty end
    local on = e.member and e.member.online and "在線" or "離線"
    return name, what, on, Supply.FRESH_TEXT[e.fresh or "unknown"] or "未知"
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

local function setItemIcon(tex, itemID)
    local icon = itemID and Supply.itemIcon(itemID)
    local okSet = icon and ns.Icons.set(tex, icon)
    if not okSet then ns.Icons.set(tex, UI.PLACEHOLDER) end
    if tex.SetTexCoord then tex:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
    tex:Show()
    return okSet and true or false
end
UI.setItemIcon = setItemIcon

local function itemTooltip(owner, itemID, extra)
    if not GameTooltip then return end
    owner.gfSupplyTip = true
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local shown = false
    if itemID and type(GameTooltip.SetItemByID) == "function" then shown = pcall(GameTooltip.SetItemByID, GameTooltip, itemID) end
    if not shown then GameTooltip:AddLine((Supply.itemLabel(itemID))) end
    for _, line in ipairs(extra or {}) do GameTooltip:AddLine(line, 0.8, 0.8, 0.8) end
    GameTooltip:Show()
end

-- Move a row's (or the header's) cells for list width w: 物品 grows, the
-- other columns keep their width and move right.
local COL_KEYS = { "name", "qty", "match", "fresh" }
function UI.placeCells(owner, cells, w)
    local d = w - UI.LIST_W
    local C = UI.COL
    for i, key in ipairs(COL_KEYS) do
        local fs = cells[i]
        if fs then
            local x = key == "name" and (fs.gfHeadX or C.name.x) or (C[key].x + d)
            local cw = key == "name" and ((fs.gfHeadW or C.name.w) + d) or C[key].w
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", owner, "LEFT", x, 0)
            fs:SetWidth(cw)
        end
    end
end
function UI.placeRow(r, w)
    r:SetWidth(w)
    UI.placeCells(r, { r.name, r.qty, r.match, r.fresh }, w)
end

local function newRow(i)
    local r = CreateFrame("Button", nil, panel)
    r:SetSize(UI.LIST_W, UI.ROW_H - 4)
    r:SetPoint("TOPLEFT", panel, "TOPLEFT", UI.LIST_X, UI.TOP - (i - 1) * UI.ROW_H)
    r.bg = Th.fill(r, Th.C.fill, "BACKGROUND")
    r.sel = W.rowSelect(r)
    local C = UI.COL
    -- GF-UI-F: the game's + / - in front of a row that opens a detail.
    r.expand = r:CreateTexture(nil, "ARTWORK")
    r.expand:SetSize(UI.EXPAND, UI.EXPAND)
    r.expand:SetPoint("LEFT", r, "LEFT", C.expand.x, 0)
    r.expand:Hide()
    r.noteIcon = r:CreateTexture(nil, "OVERLAY") -- GF-009-14 B: only when there is a note
    r.noteIcon:SetSize(UI.NOTE_ICON_SIZE, UI.NOTE_ICON_SIZE)
    r.noteIcon:SetTexture(UI.NOTE_ICON)
    r.noteIcon:Hide()
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(UI.ICON, UI.ICON)
    r.icon:SetPoint("LEFT", r, "LEFT", C.icon.x, 0)
    local function cell(key, font, justify)
        local fs = r:CreateFontString(nil, "ARTWORK", font)
        fs:SetPoint("LEFT", r, "LEFT", C[key].x, 0)
        fs:SetWidth(C[key].w)
        fs:SetJustifyH(justify or "LEFT")
        fs.gfAlign = justify or "LEFT"
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        return fs
    end
    r.name = cell("name", ns.LABEL_FONT)
    r.qty = cell("qty", ns.FIELD_FONT, "RIGHT")
    r.match = cell("match", ns.LABEL_FONT)
    r.fresh = cell("fresh", ns.LABEL_FONT)
    UI.placeRow(r, UI.listWidth())
    r:SetScript("OnClick", function(self) UI.select(self.index) end)
    r:SetScript("OnEnter", function(self)
        if self.itemID then itemTooltip(self, self.itemID, self.tipLines) end
    end)
    r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    if r.EnableMouseWheel then r:EnableMouseWheel(true) end
    r:SetScript("OnMouseWheel", function(_, delta) UI.scroll(delta) end)
    rows[i] = r
    return r
end

-- The rows of the current tab: { itemID, qtyText, matchText, tip, ref }.
function UI.listFor(kind)
    local out = {}
    if kind == "mine" then
        for _, l in ipairs(L.own()) do
            local left = (l.expiresAt or 0) - ns.Share.serverNow()
            local days = left > 0 and math.max(1, math.ceil(left / 86400)) or 0
            local q = L.DIRECTION_TEXT[l.direction] .. " " .. l.quantity
            local st = L.STATUS_TEXT[l.status] or ""
            local tip = { L.categoryText(l.category), "交易條件：" .. L.termsText(l.terms, l.price) }
            if (l.note or "") ~= "" then tip[#tip + 1] = "備註：" .. l.note end
            out[#out + 1] = { itemID = l.itemID, listing = l, qty = q, qtyShort = q, match = st, matchShort = st,
                fresh = l.status == "active" and ("剩 " .. days .. " 天") or "", expandable = true,
                tip = tip, hasNote = (l.note or "") ~= "" }
        end
        return out
    end
    local rule = UI.GROUP_TABS[kind] and UI.groupRule() or nil
    for _, it in ipairs(Supply.view(kind)) do
        if not rule or (rule.items and rule.items[it.itemID]) then
            local tip = {}
            if it.mine then tip[#tip + 1] = "來源：" .. sourceText(it.mine) end
            -- GF-009-14 B: every viewable manual listing: terms and the full note.
            local hasNote = false
            for _, e in ipairs(it.others or {}) do
                if UI.manualOf(e) then
                    for _, line in ipairs(UI.listingTipLines(e, true)) do tip[#tip + 1] = line end
                    if (UI.manualOf(e).note or "") ~= "" then hasNote = true end
                end
            end
            out[#out + 1] = { itemID = it.itemID, item = it, qty = UI.qtyText(kind, it), match = UI.matchText(kind, it),
                qtyShort = UI.qtyShort(kind, it), matchShort = UI.matchShort(kind, it), fresh = UI.freshShort(it),
                expandable = #it.others > 0, tip = tip, hasNote = hasNote }
        end
    end
    return out
end

function UI.scroll(delta)
    local maxOffset = math.max(0, #state.items - UI.ROWS)
    state.offset = math.max(0, math.min(maxOffset, state.offset - (delta or 0)))
    UI.drawList()
end

function UI.drawList()
    if not panel then return end
    local list = state.items
    for i = 1, UI.ROWS do
        local data = list[state.offset + i]
        local r = rows[i]
        if data then
            r = r or newRow(i)
            r.index, r.itemID, r.tipLines = state.offset + i, data.itemID, data.tip
            setItemIcon(r.icon, data.itemID)
            local name = Supply.itemLabel(data.itemID)
            r.name:SetText(name)
            r.qty:SetText(data.qtyShort or data.qty or "")
            r.match:SetText(data.matchShort or data.match or "")
            r.fresh:SetText(data.fresh or "")
            r.noteIcon:ClearAllPoints()
            r.noteIcon:SetPoint("BOTTOMRIGHT", r.icon, "BOTTOMRIGHT", 4, -4)
            if data.hasNote then r.noteIcon:Show() else r.noteIcon:Hide() end
            local open = state.selected == state.offset + i
            r.sel.set(open)
            if data.expandable then
                r.expandFile = open and UI.EXPAND_OPEN or UI.EXPAND_CLOSED
                ns.Icons.set(r.expand, r.expandFile)
                r.expand:Show()
            else
                r.expandFile = nil
                r.expand:Hide()
            end
            r:Show()
        elseif r then
            r:Hide()
        end
    end
    UI.drawState()
end

-- GF-UI-F: the list's state panel (W.statePanel): 空 / 載入中 / 資料過期 /
-- 暫時無法讀取. Only when the list has no rows (or reading it failed).
function UI.pageState()
    if state.preview then return state.preview end
    if state.failed then return "error" end
    if #state.items > 0 then return nil end
    local tab = state.tab
    if UI.GROUP_TABS[tab] and Supply.autoOn() then
        local last = Supply.last or {}
        if last.questOK == false or last.bagOK == false then return "error" end
        if not last.scanAt then return "loading" end
    end
    if tab ~= "mine" then
        local okCount, counts = pcall(Supply.snapshotCounts)
        if okCount and counts and (counts.expired or 0) > 0 then return "stale" end
    end
    return "empty"
end
function UI.drawState()
    if not statePanel then return end
    local kind = UI.pageState()
    statePanel.set(kind, kind == "empty" and UI.EMPTY[state.tab] or nil)
end
-- /gftk supply state <empty|loading|stale|error|off>: show one state for a
-- screenshot (MANUAL §3uif); nothing is read or changed.
UI.PREVIEW_KINDS = { empty = true, loading = true, stale = true, error = true }
function UI.previewState(kind)
    if kind == "off" or kind == "" then kind = nil end
    if kind and not UI.PREVIEW_KINDS[kind] then return false end
    state.preview = kind
    UI.refresh()
    return true
end

---------------------------------------------------------------------------
-- 收集組 (spec v2.0 附錄 A §7.2): only the active rules; 全部 = no filter.
---------------------------------------------------------------------------

function UI.groupOptions()
    local list = { { value = nil, text = "全部" } }
    for _, r in ipairs(Supply.activeRules()) do list[#list + 1] = { value = r.collectionID, text = r.title } end
    return list
end
function UI.groupRule()
    if not state.group then return nil end
    for _, r in ipairs(Supply.activeRules()) do if r.collectionID == state.group then return r end end
    return nil
end
function UI.setGroup(id)
    state.group, state.offset, state.selected = id, 0, nil
    if groupButton then groupButton.value = id; groupButton.refreshText() end
    UI.refresh()
end
local function drawGroup()
    if not groupButton then return end
    if state.group and not UI.groupRule() then state.group = nil; groupButton.value = nil end
    groupButton.refreshText()
    local on = UI.GROUP_TABS[state.tab] == true
    if on then groupLabel:Show(); groupButton:Show() else groupLabel:Hide(); groupButton:Hide() end
    W.setEnabled(groupButton, #Supply.activeRules() > 0)
end

-- Column header texts of the current tab.
local function drawHeader()
    if not header then return end
    local names = UI.HEADINGS[state.tab] or UI.HEADINGS.need
    for i, fs in ipairs(header.cells) do fs:SetText(names[i] or "") end
end

---------------------------------------------------------------------------
-- Detail (the selected item)
---------------------------------------------------------------------------

local function newDetailRow(i)
    local r = CreateFrame("Frame", nil, panel)
    r:SetSize(UI.DETAIL_W, 40)
    r:SetPoint("TOPLEFT", panel, "TOPLEFT", UI.DETAIL_X, UI.DETAIL_TOP - (i - 1) * 44)
    local function cell(key, font)
        local fs = r:CreateFontString(nil, "ARTWORK", font)
        fs:SetPoint("LEFT", r, "LEFT", UI.DCOL[key].x, 0)
        fs:SetWidth(UI.DCOL[key].w)
        fs:SetJustifyH("LEFT")
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        return fs
    end
    r.name = cell("name", ns.LABEL_FONT)
    r.what = cell("what", ns.FIELD_FONT)
    r.on = cell("on", ns.LABEL_FONT)
    r.fresh = cell("fresh", ns.LABEL_FONT)
    r.src = cell("src", ns.DISABLED_FONT)
    -- GF-009-14 B: the note icon before the terms; the whole row's tooltip
    -- shows the terms and the full note.
    r.noteIcon = r:CreateTexture(nil, "OVERLAY")
    r.noteIcon:SetSize(UI.NOTE_ICON_SIZE, UI.NOTE_ICON_SIZE)
    r.noteIcon:SetTexture(UI.NOTE_ICON)
    r.noteIcon:SetPoint("RIGHT", r.src, "LEFT", -2, 0)
    r.noteIcon:Hide()
    if r.EnableMouse then r:EnableMouse(true) end
    r:SetScript("OnEnter", function(self)
        if not (self.tipLines and #self.tipLines > 0 and GameTooltip) then return end
        self.gfSupplyTip = true
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        for i, line in ipairs(self.tipLines) do
            if i == 1 then GameTooltip:AddLine(line, 1, 0.82, 0) else GameTooltip:AddLine(line, 1, 1, 1, true) end
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    r.contact = Th.button(r, "聯絡", 72, ns.BUTTON_H)
    r.contact:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r.contact:SetScript("OnClick", function(self) if self.entry then Supply.contact(self.entry) end end)
    -- GF-UI-F: the page's one sentence lives here now (no footer line).
    r.contact.tip = UI.CONTACT_TIP
    withTip(r.contact)
    detailRows[i] = r
    return r
end

function UI.detailRowList() return detailRows end
local function hideDetailRows(from)
    for i = from, #detailRows do detailRows[i]:Hide() end
end

-- Buttons under a listing of my own: 修改, 續期, 結束 while it is active;
-- GF-UI-H: 刪除 once it has ended (已結束／已取消／已過期).
local function shown(f, on) if on then f:Show() else f:Hide() end end
local function listingButtons(l)
    local on = l ~= nil and l.status == "active"
    shown(detail.edit, on); shown(detail.renew, on); shown(detail.finish, on)
    shown(detail.delete, l ~= nil and l.status ~= "active")
    detail.edit.listing, detail.renew.listing, detail.finish.listing, detail.delete.listing = l, l, l, l
end

-- A row has something for the right side: my listing (its buttons) or matches.
function UI.hasDetail(data)
    return data ~= nil and (data.listing ~= nil or (data.item ~= nil and #data.item.others > 0))
end

-- Narrow (list + detail) or wide (list only); also moves 刊登 and the divider.
function UI.applyLayout()
    local data = state.selected and state.items[state.selected]
    state.wide = not UI.hasDetail(data)
    local w = UI.listWidth()
    for _, r in pairs(rows) do UI.placeRow(r, w) end
    if header then
        header:SetWidth(w)
        UI.placeCells(header, header.cells, w)
    end
    if statePanel then statePanel:SetWidth(w) end
    if postButton then
        postButton:ClearAllPoints()
        postButton:SetPoint("TOPLEFT", panel, "TOPLEFT", UI.LIST_X + w - UI.POST_W, UI.TOOL_Y)
    end
    if UI.divider then if state.wide then UI.divider:Hide() else UI.divider:Show() end end
    return state.wide
end

function UI.drawDetail()
    if not panel then return end
    local data = state.selected and state.items[state.selected]
    if not UI.hasDetail(data) then data = nil end
    if not data then
        detail.icon:Hide()
        detail.name:SetText("")
        detail.sub:SetText("")
        if detailHeader then detailHeader:Hide() end
        listingButtons(nil)
        hideDetailRows(1)
        return
    end
    setItemIcon(detail.icon, data.itemID)
    detail.name:SetText((Supply.itemLabel(data.itemID)))
    if data.listing then
        local l = data.listing
        local left = l.expiresAt - ns.Share.serverNow()
        local days = left > 0 and math.max(1, math.ceil(left / 86400)) or 0
        detail.sub:SetText(string.format("%s %d｜%s｜%s%s", L.DIRECTION_TEXT[l.direction], l.quantity, L.categoryText(l.category),
            L.STATUS_TEXT[l.status] or "", l.status == "active" and ("，剩 " .. days .. " 天") or ""))
        listingButtons(l)
        if detailHeader then detailHeader:Hide() end
        hideDetailRows(1)
        -- GF-009-14 B: 交易條件, then the full note (when there is one).
        local lines = { { "交易條件", L.termsText(l.terms, l.price) } }
        if l.note and l.note ~= "" then lines[#lines + 1] = { "備註", l.note } end
        for i, ln in ipairs(lines) do
            local r = detailRows[i] or newDetailRow(i)
            r.name:SetText(ln[1])
            r.on:SetText(""); r.fresh:SetText(""); r.src:SetText("")
            r.noteIcon:Hide()
            r.what:SetWidth(330)
            r.what:SetText(ln[2])
            r.tipLines = { ln[1], ln[2] }
            r.contact:Hide()
            r:Show()
        end
        return
    end
    listingButtons(nil)
    if detailHeader then if #data.item.others > 0 then detailHeader:Show() else detailHeader:Hide() end end
    local it = data.item
    detail.sub:SetText(data.qty .. (data.match ~= "" and ("｜" .. data.match) or ""))
    local list = it.others
    for i = 1, UI.DETAIL_ROWS do
        local e = list[i]
        local r = detailRows[i]
        if e then
            r = r or newDetailRow(i)
            local name, what, on, fresh = UI.personText(e)
            r.name:SetText(name)
            r.what:SetWidth(96)
            r.what:SetText(what)
            r.on:SetText(on)
            r.fresh:SetText(fresh)
            r.src:SetText(UI.condText(e))
            local m = UI.manualOf(e)
            if m and (m.note or "") ~= "" then r.noteIcon:Show() else r.noteIcon:Hide() end
            r.tipLines = UI.listingTipLines(e, false)
            r.contact.entry = e
            r.contact:Show()
            W.setEnabled(r.contact, Supply.canContact(e))
            r:Show()
        elseif r then
            r:Hide()
        end
    end
end

-- GF-UI-H: remove an ended listing of mine from 我的刊登 (it never comes back).
function UI.deleteListing(id)
    local okDel, why = L.remove(id)
    if okDel then state.selected = nil end
    UI.refresh()
    return okDel, why
end

function UI.select(index)
    state.selected = index
    UI.applyLayout()
    UI.drawList()
    UI.drawDetail()
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

function UI.refresh()
    if not panel then return end
    if ns.inCombat() then UI.pending = true; return end
    UI.pending = false
    autoBox:SetChecked(Supply.autoOn())
    manualBox:SetChecked(Supply.manualOn())
    W.setEnabled(postButton, Supply.manualOn())
    local keepItem = state.selected and state.items[state.selected] and state.items[state.selected].itemID
    local keepListing = state.selected and state.items[state.selected] and state.items[state.selected].listing
    drawGroup()
    drawHeader()
    -- GF-UI-F: a failed read shows 暫時無法讀取 instead of breaking the page;
    -- a screenshot preview (UI.previewState) shows its state with no rows.
    local okList, list = pcall(UI.listFor, state.tab)
    state.failed = not okList
    if not okList and Supply.note then pcall(Supply.note, "調貨所列表讀取失敗：" .. tostring(list)) end
    state.items = (okList and not state.preview) and list or {}
    state.selected = nil
    for i, d in ipairs(state.items) do
        if (keepListing and d.listing and d.listing.id == keepListing.id) or (not keepListing and keepItem and d.itemID == keepItem) then
            state.selected = i
        end
    end
    if not state.selected and #state.items > 0 then state.selected = 1 end
    state.offset = math.max(0, math.min(state.offset, #state.items - UI.ROWS))
    UI.applyLayout()
    UI.drawList()
    UI.drawDetail()
end

local refreshTimer = false
function UI.refreshSoon()
    if not panel or not ns.Framework.isModuleShown(UI.ID) then return end
    if refreshTimer then return end
    refreshTimer = true
    ns.after(0.5, function() refreshTimer = false; if ns.Framework.isModuleShown(UI.ID) then UI.refresh() end end)
end

function UI.setTab(key)
    state.tab, state.offset, state.selected = key, 0, nil
    if tabs then tabs.select(key) end
    UI.refresh()
end


local function label(parent, text, font)
    local fs = parent:CreateFontString(nil, "ARTWORK", font or ns.LABEL_FONT)
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    return fs
end

local function checkWithLabel(parent, text, x, y, onClick)
    local c = Th.checkBox(parent)
    c:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    c.label = label(c, text)
    c.label:SetPoint("LEFT", c, "RIGHT", 2, 0)
    c:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    return c
end

local function build(p)
    panel = p
    -- GF-UI-H: no title line (it sat under the sub-tab row); see UI.BAR_Y.
    autoBox = checkWithLabel(p, "自動集料", UI.CHECK_X.auto, UI.BAR_Y, function(on) Supply.setAuto(on); UI.refresh() end)
    autoBox.tip = "試用：荊棘谷書頁，依任務與背包自動算出缺的和可能多的（規則尚未實機確認）"
    manualBox = checkWithLabel(p, "手動刊登", UI.CHECK_X.manual, UI.BAR_Y, function(on) Supply.setManual(on); UI.refresh() end)
    manualBox.tip = "關掉後不再分享我的刊登，也不顯示別人的刊登"
    withTip(autoBox); withTip(manualBox)
    tabs = Th.tabStrip(p, (function()
        local items = {}
        for _, t in ipairs(UI.TABS) do items[#items + 1] = { key = t.key, text = t.text } end
        return items
    end)(), UI.LIST_X, UI.BAR_Y, function(key) UI.setTab(key) end)
    tabs.select(state.tab)
    UI.tabs = tabs
    postButton = Th.button(p, UI.POST_TEXT, UI.POST_W, ns.BUTTON_H)
    postButton:SetPoint("TOPLEFT", p, "TOPLEFT", UI.LIST_X + UI.LIST_W - UI.POST_W, UI.TOOL_Y)
    UI.postButton = postButton
    postButton:SetScript("OnClick", function() UI.openForm() end)
    -- GF-UI-F: 收集組, shown on 我缺的 / 我可能有多的 only (GF-UI-H: on the tool row).
    groupLabel = label(p, "收集組", ns.FIELD_FONT)
    groupLabel:SetPoint("TOPLEFT", p, "TOPLEFT", UI.GROUP_X, UI.TOOL_Y - 6)
    groupButton = ns.choiceButton(p, UI.GROUP_W, UI.GROUP_X + 56, UI.TOOL_Y, UI.groupOptions,
        function(value) UI.setGroup(value) end, "全部")
    UI.groupLabel, UI.groupButton, UI.autoBox, UI.manualBox = groupLabel, groupButton, autoBox, manualBox
    -- The list's column header: a faint bar, gold names; the quantity right-aligned.
    header = CreateFrame("Frame", nil, p)
    header:SetPoint("TOPLEFT", p, "TOPLEFT", UI.LIST_X, UI.HEAD_Y)
    header:SetSize(UI.LIST_W, UI.HEAD_H)
    Th.headerBar(header)
    header.cells = {}
    local C = UI.COL
    local cols = { { x = C.icon.x, w = C.name.x + C.name.w - C.icon.x }, { x = C.qty.x, w = C.qty.w, right = true },
        { x = C.match.x, w = C.match.w }, { x = C.fresh.x, w = C.fresh.w } }
    for i, c in ipairs(cols) do
        local fs = header:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT)
        fs:SetPoint("LEFT", header, "LEFT", c.x, 0)
        fs:SetWidth(c.w)
        fs:SetJustifyH(c.right and "RIGHT" or "LEFT")
        fs.gfAlign = c.right and "RIGHT" or "LEFT"
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        header.cells[i] = fs
    end
    header.cells[1].gfHeadX, header.cells[1].gfHeadW = cols[1].x, cols[1].w
    UI.header = header
    -- Empty / loading / stale / error: the shared state panel in the list area.
    statePanel = W.statePanel(p, UI.LIST_W, 120)
    statePanel:SetPoint("TOPLEFT", p, "TOPLEFT", UI.LIST_X, UI.TOP - 24)
    UI.statePanel = statePanel
    -- A screenshot preview never outlives the page.
    if p.HookScript then p:HookScript("OnHide", function() state.preview = nil end) end
    -- GF-009-13: the form and the finder never outlive the page (the window's
    -- X, another module, /gftk); an unsaved form is kept as a draft.
    if p.HookScript then p:HookScript("OnHide", function() UI.closeWithPage() end) end
    -- GF-UI-I: Th.vline's second y counts from the page's bottom; the old call
    -- gave the list's bottom from the top, so the line ran out of the window.
    -- Anchor the top and give the height instead.
    UI.divider = Th.vline(p, UI.DETAIL_X - 16, -UI.HEAD_Y, 0)
    UI.divider:ClearAllPoints()
    UI.divider:SetPoint("TOPLEFT", p, "TOPLEFT", UI.DETAIL_X - 16, UI.HEAD_Y)
    UI.divider:SetHeight(UI.HEAD_Y - (UI.TOP - UI.ROWS * UI.ROW_H))
    detail.icon = p:CreateTexture(nil, "ARTWORK")
    detail.icon:SetSize(40, 40)
    detail.icon:SetPoint("TOPLEFT", p, "TOPLEFT", UI.DETAIL_X, UI.HEAD_Y)
    detail.name = label(p, "", ns.TITLE_FONT)
    detail.name:SetPoint("TOPLEFT", p, "TOPLEFT", UI.DETAIL_X + 50, UI.HEAD_Y - 2)
    detail.name:SetWidth(UI.DETAIL_W - 50)
    if detail.name.SetWordWrap then detail.name:SetWordWrap(false) end
    -- The detail's own column header (成員 / 數量 / 在線 / 時效 / 來源).
    detailHeader = CreateFrame("Frame", nil, p)
    detailHeader:SetPoint("TOPLEFT", p, "TOPLEFT", UI.DETAIL_X, UI.DETAIL_HEAD_Y)
    detailHeader:SetSize(UI.DETAIL_W, UI.HEAD_H)
    Th.headerBar(detailHeader)
    detailHeader.cells = {}
    for i, key in ipairs({ "name", "what", "on", "fresh", "src" }) do
        local fs = detailHeader:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT)
        fs:SetPoint("LEFT", detailHeader, "LEFT", UI.DCOL[key].x, 0)
        fs:SetWidth(UI.DCOL[key].w)
        fs:SetJustifyH("LEFT")
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        fs:SetText(UI.DETAIL_HEADINGS[i])
        detailHeader.cells[i] = fs
    end
    detailHeader:Hide()
    UI.detailHeader = detailHeader
    detail.sub = label(p, "", ns.LABEL_FONT)
    detail.sub:SetPoint("TOPLEFT", p, "TOPLEFT", UI.DETAIL_X + 50, UI.HEAD_Y - 26)
    detail.sub:SetWidth(UI.DETAIL_W - 50)
    if detail.sub.SetWordWrap then detail.sub:SetWordWrap(false) end
    local by = UI.TOP - UI.ROWS * UI.ROW_H + 40
    detail.edit = Th.button(p, "修改", 80, ns.BUTTON_H)
    detail.edit:SetPoint("TOPLEFT", p, "TOPLEFT", UI.DETAIL_X, by)
    detail.edit:SetScript("OnClick", function(self) if self.listing then UI.openForm(self.listing) end end)
    detail.renew = Th.button(p, "續期", 80, ns.BUTTON_H)
    detail.renew:SetPoint("LEFT", detail.edit, "RIGHT", 8, 0)
    detail.renew:SetScript("OnClick", function(self)
        if self.listing then L.renew(self.listing.id); UI.refresh() end
    end)
    detail.renew.tip = "從今天起重新計算有效期"
    withTip(detail.renew)
    detail.finish = Th.button(p, "結束", 80, ns.BUTTON_H)
    detail.finish:SetPoint("LEFT", detail.renew, "RIGHT", 8, 0)
    detail.finish:SetScript("OnClick", function(self)
        local l = self.listing
        if not l then return end
        W.confirm("結束這筆" .. L.DIRECTION_TEXT[l.direction] .. "？公會成員之後不會再看到它。", function()
            L.finish(l.id, "closed"); UI.refresh()
        end)
    end)
    -- GF-UI-H: 刪除 an ended listing of mine (in place of the three above).
    detail.delete = Th.button(p, "刪除", 80, ns.BUTTON_H)
    detail.delete:SetPoint("TOPLEFT", p, "TOPLEFT", UI.DETAIL_X, by)
    detail.delete:SetScript("OnClick", function(self)
        local l = self.listing
        if not l then return end
        W.confirm("刪除這筆已結束的" .. L.DIRECTION_TEXT[l.direction] .. "？", function()
            UI.deleteListing(l.id)
        end)
    end)
    UI.detail = detail
    listingButtons(nil)
end

---------------------------------------------------------------------------
-- The listing form (one window; ESC and X close it, a click outside does
-- not: it may hold what the player typed). GF-UI-F: with unsaved changes,
-- X / ESC / 取消 first ask with the game's own confirm box (StaticPopup);
-- with none they close at once.
---------------------------------------------------------------------------

local form
local formState = {}
UI.formState = formState

local function formMessage(text) if form then form.msg:SetText(text or "") end end

-- What the form holds now, as one string (compared with the one at opening).
local function formSnapshot()
    if not form then return nil end
    return table.concat({ tostring(formState.direction), tostring(formState.itemID), tostring(formState.category),
        tostring(formState.days), tostring(form.qty:GetText() or ""), tostring(form.note:GetText() or ""),
        tostring(formState.terms), tostring(form.gold:GetText() or ""), tostring(form.silver:GetText() or ""),
        tostring(form.copper:GetText() or "") }, "|")
end
function UI.formDirty()
    return form ~= nil and form:IsShown() and formState.initial ~= nil and formSnapshot() ~= formState.initial
end

-- Close the form; force skips the question (after 放棄, or after saving).
function UI.closeForm(force)
    if not form then return true end
    if not force and UI.formDirty() then UI.askDiscard(); return false end
    formState.initial = nil
    if force then UI.draft = nil end
    form.gfRawHide(form)
    UI.afterFormHide()
    return true
end

---------------------------------------------------------------------------
-- GF-009-13: windows, ESC and drafts. ESC closes the finder, then the form
-- (asking first when it changed), then the window. When the page goes away
-- first (the window's X, another module), the form closes without asking and
-- its contents are kept: the next 「＋刊登」 (or the same 修改) gets them back.
---------------------------------------------------------------------------

function UI.hideTip()
    if GameTooltip and GameTooltip.GetOwner then
        local o = GameTooltip:GetOwner()
        if o and o.gfSupplyTip and GameTooltip.Hide then GameTooltip:Hide() end
    end
end
function UI.afterFormHide()
    local p = UI.picker and UI.picker()
    if p and p:IsShown() then p:Hide() end
    UI.hideTip()
end
local function draftOf()
    return { editingID = formState.editing and formState.editing.id or nil, direction = formState.direction,
        itemID = formState.itemID, bagInfo = formState.bagInfo, days = formState.days,
        qty = form.qty:GetText(), note = form.note:GetText(), itemText = form.itemBox:GetText(),
        pickPos = formState.pickPos, terms = formState.terms,
        gold = form.gold:GetText(), silver = form.silver:GetText(), copper = form.copper:GetText() }
end
function UI.closeWithPage()
    local p = UI.picker and UI.picker()
    if p and p:IsShown() then p:Hide() end
    if form and form:IsShown() then
        if UI.formDirty() then UI.draft = draftOf() end
        formState.initial = nil
        form.gfRawHide(form)
    end
    UI.hideTip()
end
local function draftFits(d, listing)
    if not d then return false end
    if listing then return d.editingID == listing.id end
    return d.editingID == nil
end
UI.DRAFT_BACK = "已還原上次沒送出的內容"

-- Where the form and the finder go (UIParent units from the bottom left):
-- the finder right of the form, else left of it; when neither fits, the form
-- moves so both fit side by side; on a screen narrower than both, the finder
-- covers the form's right side. Nothing is placed off screen.
UI.FORM_W, UI.FORM_H, UI.FORM_Y = 600, 570, 40 -- GF-009-14 B: +交易條件, +每個 price row
UI.EDIT_STRATA, UI.FORM_LEVEL, UI.PICK_LEVEL = "DIALOG", 100, 140 -- GF-009-14: IME above edit-box windows
UI.PICK_GAP, UI.SCREEN_EDGE = 4, 8
function UI.layoutPair(sw, sh, fw, fh, pw, ph, formLeft, formTop)
    local E, gap = UI.SCREEN_EDGE, UI.PICK_GAP
    local function clampX(x, w) return math.max(E, math.min(x, sw - w - E)) end
    local function clampTop(t, h) return math.max(math.min(t, sh - E), math.min(sh - E, h + E)) end
    formLeft, formTop = clampX(formLeft, fw), clampTop(formTop, fh)
    local px
    if formLeft + fw + gap + pw <= sw - E then
        px = formLeft + fw + gap
    elseif formLeft - gap - pw >= E then
        px = formLeft - gap - pw
    elseif fw + gap + pw <= sw - 2 * E then
        formLeft = math.floor((sw - (fw + gap + pw)) / 2)
        px = formLeft + fw + gap
    else
        px = clampX(sw - pw - E, pw)
    end
    return formLeft, formTop, px, clampTop(formTop, ph)
end
-- GF-009-14 A: a dragged-to place, kept inside the screen (left, top).
function UI.clampPos(sw, sh, w, h, left, top)
    local E = UI.SCREEN_EDGE
    left = math.max(E, math.min(left, sw - w - E))
    top = math.max(math.min(top, sh - E), math.min(sh - E, h + E))
    return left, top
end
function UI.screenSize()
    local w = UIParent and UIParent.GetWidth and tonumber((UIParent:GetWidth())) or nil
    local h = UIParent and UIParent.GetHeight and tonumber((UIParent:GetHeight())) or nil
    if not w or w <= 0 or not h or h <= 0 then return 1365, 768 end
    return w, h
end
-- The form's left / top: the client's when it has laid the form out, else
-- where we put it.
function UI.formRect(sw, sh)
    local l = form and form.GetLeft and tonumber((form:GetLeft())) or nil
    local t = form and form.GetTop and tonumber((form:GetTop())) or nil
    if l and t then return l, t end
    if UI.formAt then return UI.formAt[1], UI.formAt[2] end
    return (sw - UI.FORM_W) / 2, sh / 2 + UI.FORM_Y + UI.FORM_H / 2
end

local function discardDialog()
    if type(StaticPopupDialogs) ~= "table" or type(StaticPopup_Show) ~= "function" then return false end
    if not StaticPopupDialogs[UI.POPUP_DISCARD] then
        StaticPopupDialogs[UI.POPUP_DISCARD] = {
            text = UI.DISCARD_TEXT, button1 = "放棄", button2 = "繼續編輯",
            OnAccept = function() UI.closeForm(true) end,
            -- The form sits in FULLSCREEN_DIALOG: lift the box above it while it is open.
            OnShow = function(self)
                if self and self.SetFrameStrata and self.GetFrameStrata then
                    self.gfOldStrata = self:GetFrameStrata()
                    self:SetFrameStrata("FULLSCREEN_DIALOG")
                    if self.Raise then self:Raise() end
                end
            end,
            OnHide = function(self)
                if self and self.gfOldStrata and self.SetFrameStrata then self:SetFrameStrata(self.gfOldStrata); self.gfOldStrata = nil end
            end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
    end
    return true
end
function UI.askDiscard()
    if discardDialog() then return StaticPopup_Show(UI.POPUP_DISCARD) end
    return W.confirm(UI.DISCARD_TEXT, function() UI.closeForm(true) end)
end

UI.PREVIEW_TEXT = { loading = "物品資料載入中", missing = "找不到這個物品", bad = "請貼物品連結或輸入物品編號",
    timeout = "物品資料逾時，請稍後再試" } -- GF-009-13: timeout / missing / blocked are three messages
local loadToken = 0
local function setFormItem(itemID, bagInfo, waited)
    formState.itemID, formState.bagInfo = itemID, bagInfo
    if not form then return end
    if itemID then
        -- GF-UI-I: a preview that knows the item may still be loading.
        local pv = L.preview(itemID, waited)
        formState.preview = pv.state
        setItemIcon(form.itemIcon, itemID)
        form.itemName:SetText(pv.name or ((pv.state == "missing" or pv.state == "timeout") and UI.PREVIEW_TEXT[pv.state])
            or (Supply.itemLabel(itemID)))
        -- GF-UI-H: the type comes from the item (classID / subclassID), never a pick.
        formState.category = L.categoryFor(pv.info, formState.editing and formState.editing.category or "other")
        form.typeText:SetText(pv.typeText or "")
        local problem = not formState.editing and L.itemProblem(itemID, bagInfo, formState.direction) or nil
        if (pv.state == "missing" or pv.state == "timeout") and not formState.editing then problem = UI.PREVIEW_TEXT[pv.state] end
        formMessage(problem)
        if pv.state == "loading" then
            loadToken = loadToken + 1
            local token = loadToken
            ns.after(L.LOAD_WAIT, function()
                if token == loadToken and formState.itemID == itemID and formState.preview == "loading" then
                    setFormItem(itemID, bagInfo, true)
                end
            end)
        end
    else
        formState.preview = nil
        form.itemIcon:Hide()
        form.typeText:SetText("")
        form.itemName:SetText("把物品拖到這裡、按住 Shift 點物品，或從背包選")
    end
end
UI.setFormItem = setFormItem

-- Item data arrived: a form still waiting for its item shows it now.
function UI.formItemInfo()
    -- GF-009-13 fix: a late answer also clears 逾時.
    if form and form:IsShown() and formState.itemID and (formState.preview == "loading" or formState.preview == "timeout") then
        setFormItem(formState.itemID, formState.bagInfo)
    end
end

-- GF-UI-I: a link, item:123 or an ItemID typed as digits.
function UI.formFromText(text)
    local id, kind = L.parseItemInput(text)
    if id then setFormItem(id)
    elseif kind == "bad" and form then formMessage(UI.PREVIEW_TEXT.bad) end
    return id, kind
end

-- Shift-click on an item while the item box has focus (the game puts links
-- into the chat box; we copy the ItemID only).
local hooked = false
local function hookLinks()
    if hooked or type(hooksecurefunc) ~= "function" then return end
    hooked = true
    local function onLink(link)
        if form and form:IsShown() and form.itemBox and form.itemBox.HasFocus and form.itemBox:HasFocus() then
            UI.formFromText(link)
        elseif UI.pickLink then
            UI.pickLink(link)
        end
    end
    if type(ChatEdit_InsertLink) == "function" then pcall(hooksecurefunc, "ChatEdit_InsertLink", onLink) end
    if type(ChatFrameUtil) == "table" and type(ChatFrameUtil.InsertLink) == "function" then
        pcall(hooksecurefunc, ChatFrameUtil, "InsertLink", onLink)
    end
end

-- An item held on the cursor (dragged from the bags or another window). The
-- form's slot and the finder share it (GF-009-13: one resolve path).
local function takeCursorItem()
    if type(GetCursorInfo) ~= "function" then return false end
    local kind, itemID = GetCursorInfo()
    if kind ~= "item" or type(itemID) ~= "number" then return false end
    if type(ClearCursor) == "function" then ClearCursor() end
    setFormItem(itemID)
    return true
end
UI.takeCursorItem = takeCursorItem
-- GF-009-13: 方向 changed: 供應 looks at the bag stacks again.
function UI.formRecheck()
    if form and form:IsShown() and formState.itemID and not formState.editing then
        setFormItem(formState.itemID, formState.bagInfo, formState.preview == "timeout")
    end
end

local function buildForm()
    local f = ns.popupWindow(UI.FORM_NAME, UI.FORM_W, UI.FORM_H)
    -- GF-009-14 (Forever: the 注音 candidate list was hidden under the
    -- finder): windows with edit boxes stay in DIALOG, so the client's IME
    -- candidates draw above them; a high frame level keeps them above the
    -- toolkit window (also DIALOG). Menus and tooltips stay in TOOLTIP.
    f:SetFrameStrata(UI.EDIT_STRATA)
    if f.SetFrameLevel then f:SetFrameLevel(UI.FORM_LEVEL) end
    f:SetPoint("CENTER", UIParent, "CENTER", 0, UI.FORM_Y)
    if f.SetClampedToScreen then f:SetClampedToScreen(true) end
    f.TitleText:SetText("刊登")
    local x, y = 24, -48
    local function row(text)
        local fs = label(f, text, ns.FIELD_FONT)
        fs:SetPoint("TOPLEFT", f, "TOPLEFT", x, y - 6)
        return fs
    end
    row("方向")
    f.dirs = Th.tabStrip(f, { { key = "need", text = "徵求" }, { key = "offer", text = "供應" } }, 104, y,
        function(key) formState.direction = key; UI.formRecheck() end)
    y = y - 50
    row("物品")
    f.slot = CreateFrame("Button", nil, f)
    f.slot:SetSize(40, 40)
    f.slot:SetPoint("TOPLEFT", f, "TOPLEFT", 104, y + 4)
    Th.border(f.slot, Th.C.line, "BORDER")
    f.itemIcon = f.slot:CreateTexture(nil, "ARTWORK")
    f.itemIcon:SetAllPoints()
    f.slot:SetScript("OnReceiveDrag", takeCursorItem)
    f.slot:SetScript("OnClick", function() if not takeCursorItem() then UI.openPicker() end end)
    f.slot.tip = "拖入物品，或按一下從背包選"
    withTip(f.slot)
    f.itemName = label(f, "", ns.LABEL_FONT)
    f.itemName:SetPoint("LEFT", f.slot, "RIGHT", 10, 0)
    f.itemName:SetWidth(430)
    if f.itemName.SetWordWrap then f.itemName:SetWordWrap(false) end
    y = y - 50
    f.itemBox = Th.editBox(f, 230, 30)
    f.itemBox:SetPoint("TOPLEFT", f, "TOPLEFT", 104, y)
    f.itemBox:SetScript("OnTextChanged", function(self) UI.formFromText(self:GetText()) end)
    f.itemBox.tip = "貼上物品連結或輸入物品編號"
    withTip(f.itemBox)
    f.pick = Th.button(f, "從背包選", 110, ns.BUTTON_H)
    f.pick:SetPoint("LEFT", f.itemBox, "RIGHT", 10, 0)
    f.pick:SetScript("OnClick", function() UI.openPicker("bag") end)
    -- GF-UI-H: 找物品 — every item the client knows (also what is not in my bags).
    f.find = Th.button(f, "找物品", 110, ns.BUTTON_H)
    f.find:SetPoint("LEFT", f.pick, "RIGHT", 8, 0)
    f.find:SetScript("OnClick", function() UI.openPicker("all") end)
    y = y - 50
    -- GF-UI-H: 類型 is read from the item (classID / subclassID); nothing to choose.
    row("類型")
    f.typeText = label(f, "", ns.LABEL_FONT)
    f.typeText:SetPoint("TOPLEFT", f, "TOPLEFT", 104, y - 6)
    f.typeText:SetWidth(460)
    if f.typeText.SetWordWrap then f.typeText:SetWordWrap(false) end
    y = y - 50
    row("數量")
    f.qty = Th.editBox(f, 80, 30)
    f.qty:SetPoint("TOPLEFT", f, "TOPLEFT", 104, y)
    if f.qty.SetNumeric then f.qty:SetNumeric(true) end
    if f.qty.SetMaxLetters then f.qty:SetMaxLetters(3) end
    y = y - 50
    -- GF-009-14 B: 交易條件 (面議 for a new listing); only 訂價 opens the price.
    row("交易條件")
    local terms = {}
    for _, t in ipairs(L.TERMS) do terms[#terms + 1] = { key = t.key, text = t.text, w = 76 } end
    f.terms = Th.tabStrip(f, terms, 104, y, function(key) UI.setFormTerms(key) end)
    y = y - 50
    f.priceRow = CreateFrame("Frame", nil, f)
    f.priceRow:SetPoint("TOPLEFT", f, "TOPLEFT", 24, y)
    f.priceRow:SetSize(552, 34)
    local pr = f.priceRow
    pr.label = label(pr, "價格", ns.FIELD_FONT)
    pr.label:SetPoint("TOPLEFT", pr, "TOPLEFT", 0, -6)
    pr.each = label(pr, "每個", ns.LABEL_FONT)
    pr.each:SetPoint("TOPLEFT", pr, "TOPLEFT", 80, -6)
    local px = 124
    local function coin(w, letters, unit)
        local box = Th.editBox(pr, w, 30)
        box:SetPoint("TOPLEFT", pr, "TOPLEFT", px, 0)
        if box.SetNumeric then box:SetNumeric(true) end
        if box.SetMaxLetters then box:SetMaxLetters(letters) end
        local u = label(pr, unit, ns.LABEL_FONT)
        u:SetPoint("LEFT", box, "RIGHT", 4, 0)
        px = px + w + 30
        return box
    end
    f.gold = coin(80, 6, "金")
    f.silver = coin(44, 2, "銀")
    f.copper = coin(44, 2, "銅")
    pr.hint = label(pr, "", ns.DISABLED_FONT)
    pr.hint:SetPoint("TOPLEFT", pr, "TOPLEFT", px + 4, -6)
    pr.hint:SetText(UI.PRICE_HINT_TEXT)
    f.priceRow:Hide()
    y = y - 50
    row("有效期")
    local days = {}
    for _, d in ipairs(L.DAYS) do days[#days + 1] = { key = d, text = d .. " 天", w = 76 } end
    f.days = Th.tabStrip(f, days, 104, y, function(key) formState.days = key end)
    y = y - 50
    row("備註")
    f.note = Th.editBox(f, 460, 30)
    f.note:SetPoint("TOPLEFT", f, "TOPLEFT", 104, y)
    if f.note.SetMaxLetters then f.note:SetMaxLetters(L.NOTE_MAX) end
    f.note.tip = "選填，最多 " .. L.NOTE_MAX .. " 字，例如想交換的東西"
    withTip(f.note)
    y = y - 44
    f.msg = label(f, "", ns.FIELD_FONT)
    f.msg:SetPoint("TOPLEFT", f, "TOPLEFT", 24, y)
    f.msg:SetWidth(552)
    f.save = Th.button(f, "刊登", 110, ns.BUTTON_H)
    f.save:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -138, 16)
    f.save:SetScript("OnClick", function() UI.submitForm() end)
    f.cancel = Th.button(f, "取消", 110, ns.BUTTON_H)
    f.cancel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 16)
    f.cancel:SetScript("OnClick", function() UI.closeForm() end)
    f:Hide()
    -- X and ESC (ns.escape) both call f:Hide(): ask first when something changed.
    f.gfRawHide = f.Hide
    f.Hide = function(self) return UI.closeForm() end
    form = f
    hookLinks()
    return f
end

-- listing: edit that one (direction and item stay); nil: a new one.
-- GF-UI-F: an open form with unsaved changes is kept (force replaces it).
function UI.openForm(listing, force)
    if not Supply.manualOn() then return false end
    if not force and UI.formDirty() then
        if form.Raise then form:Raise() end
        return false
    end
    local f = form or buildForm()
    for k in pairs(formState) do formState[k] = nil end
    formState.editing = listing
    formState.direction = listing and listing.direction or "need"
    formState.category = listing and listing.category or "other"
    formState.days = listing and listing.days or L.DEFAULT_DAYS
    f.TitleText:SetText(listing and "修改刊登" or "刊登")
    f.save:SetText(listing and "儲存" or "刊登")
    f.dirs.select(formState.direction)
    f.days.select(formState.days)
    f.itemBox:SetText("")
    f.qty:SetText(tostring(listing and listing.quantity or 1))
    f.note:SetText(listing and listing.note or "")
    -- GF-009-14 B: a new listing 面議; an old one keeps its terms (or none: 未標示).
    UI.setFormTerms(listing and listing.terms or (not listing and L.DEFAULT_TERMS) or nil, listing and listing.price or nil)
    W.setEnabled(f.pick, listing == nil)
    W.setEnabled(f.find, listing == nil)
    for _, b in ipairs(f.dirs.buttons) do W.setEnabled(b, listing == nil) end
    if listing then f.itemBox:Hide() else f.itemBox:Show() end
    setFormItem(listing and listing.itemID or nil)
    formMessage("")
    -- GF-009-13: back in the middle (the finder may have moved it aside).
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, UI.FORM_Y)
    UI.formAt = nil
    f:Show()
    formState.initial = formSnapshot()
    -- GF-009-13: what was in it when the page closed comes back (still unsaved).
    local d = UI.draft
    if not force and draftFits(d, listing) then
        UI.draft = nil
        formState.direction, formState.days = d.direction, d.days
        f.dirs.select(d.direction)
        f.days.select(d.days)
        f.qty:SetText(d.qty or "")
        f.note:SetText(d.note or "")
        if not listing then f.itemBox:SetText(d.itemText or "") end
        setFormItem(d.itemID, d.bagInfo)
        formState.pickPos = d.pickPos
        UI.setFormTerms(d.terms, nil)
        f.gold:SetText(d.gold or ""); f.silver:SetText(d.silver or ""); f.copper:SetText(d.copper or "")
        if (f.msg:GetText() or "") == "" then formMessage(UI.DRAFT_BACK) end
    end
    return true
end

function UI.submitForm()
    if not form then return nil end
    local price, priceWhy
    if formState.terms == "price" then price, priceWhy = UI.formPrice() end
    if priceWhy then formMessage(priceWhy); return nil, priceWhy end
    local fields = { direction = formState.direction, itemID = formState.itemID, bagInfo = formState.bagInfo,
        category = formState.category, quantity = tonumber(form.qty:GetText()), days = formState.days,
        note = form.note:GetText(), terms = formState.terms, price = price }
    local l, why, dup
    if formState.editing then l, why = L.update(formState.editing.id, fields)
    else l, why, dup = L.create(fields) end
    if not l then
        formMessage(why)
        if dup then
            -- An active listing of the same item: edit that one instead.
            ns.after(0, function() UI.openForm(dup, true); formMessage(why) end)
        end
        return nil, why
    end
    UI.closeForm(true)
    if not formState.editing then state.tab = "mine"; if tabs then tabs.select("mine") end end
    UI.refresh()
    return l
end

function UI.form() return form end

-- GF-009-14 B: the form's 交易條件 and price (gold / silver / copper, per item).
UI.PRICE_HINT = { offer = "我的開價", need = "我願意付" }
UI.PRICE_HINT_TEXT = "供應＝開價，徵求＝願付"
UI.SILVER_MAX_TEXT = "銀和銅各最多 99"
function UI.setFormTerms(key, price)
    formState.terms = key
    if not form then return end
    form.terms.select(key)
    if price ~= nil then
        price = math.floor(tonumber(price) or 0)
        local g, s, c = math.floor(price / 10000), math.floor(price / 100) % 100, price % 100
        form.gold:SetText(g > 0 and tostring(g) or ""); form.silver:SetText(s > 0 and tostring(s) or "")
        form.copper:SetText(c > 0 and tostring(c) or "")
    elseif key ~= "price" then
        form.gold:SetText(""); form.silver:SetText(""); form.copper:SetText("")
    end
    if key == "price" then form.priceRow:Show() else form.priceRow:Hide() end
end
-- Copper per item from the three boxes, or nil and why (empty: nil).
function UI.formPrice()
    if not form then return nil end
    local function n(box) return tonumber(box:GetText() or "") or 0 end
    local g, s, c = n(form.gold), n(form.silver), n(form.copper)
    if s > 99 or c > 99 then return nil, UI.SILVER_MAX_TEXT end
    local total = g * 10000 + s * 100 + c
    if total <= 0 then return nil, "訂價請填每個的價格" end
    if total > L.PRICE_MAX then return nil, "每個最多 " .. L.priceText(L.PRICE_MAX) end
    return total
end

---------------------------------------------------------------------------
-- The item picker (GF-009-14: a window: ESC, X, a pick or closing the form close it).
-- GF-UI-H: two sources: 背包 (unbound bag items, as before) and 全部 (every
-- item the client knows: L.catalog); a name / ItemID search; 類型 and 子類
-- filters from the item's classID / subclassID. Untradeable items are never
-- in the list.
---------------------------------------------------------------------------

local picker
UI.PICK_ROWS = 10
UI.PICK_W = 500
function UI.pickHeight() return UI.PICK_ROWS * 40 + 160 end
UI.PICK_BAR_W = 22   -- GF-009-14 A: the scroll bar right of the rows
UI.PICK_TITLE = "找物品" -- one title for both sources
UI.PICK_DRAG_H = 34
UI.PICK_SOURCES = { { key = "bag", text = "背包", w = 80 }, { key = "all", text = "全部", w = 80 } }
UI.PICK_EMPTY = { bag = "背包裡沒有可交易的物品", all = "找不到可交易的物品" }
-- GF-009-12: 全部 with a damaged catalog file (links, IDs and drops still work).
UI.PICK_NO_CATALOG = "沒有物品目錄"
UI.PICK_POS = "%d-%d／共 %d"
UI.PICK_COL = { icon = 2, name = 42, nameW = 230, type = 280, typeW = 140 }
UI.PICK_FILTER = { searchLabel = 12, search = 56, searchW = 150, class = 216, sub = 356, filterW = 130 }
local pickState = { offset = 0, items = {}, base = {}, source = "bag", text = "", class = nil, subclass = nil }
UI.pickState = pickState

local function pickFiltered()
    local out = {}
    for _, e in ipairs(pickState.base) do
        local c, s = L.rowKind(e)
        if (pickState.class == nil or c == pickState.class)
            and (pickState.subclass == nil or s == pickState.subclass) then
            out[#out + 1] = e
        end
    end
    return out
end

local function drawPicker()
    if not picker then return end
    pickState.items = pickFiltered()
    pickState.offset = math.max(0, math.min(pickState.offset, #pickState.items - UI.PICK_ROWS))
    for i = 1, UI.PICK_ROWS do
        local b = picker.rows[i]
        local it = pickState.items[pickState.offset + i]
        if it then
            -- GF-009-12: catalog rows show the catalog's name and icon until
            -- the client knows the item (no server request per row).
            if not (it.info.icon and ns.Icons.set(b.icon, it.info.icon)) then setItemIcon(b.icon, it.itemID) end
            if b.icon.SetTexCoord then b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
            b.icon:Show()
            b.name:SetText(it.info.name or (Supply.itemLabel(it.itemID)))
            b.kind:SetText(L.typeText(it.info))
            b.count:SetText(it.count and ("x" .. it.count) or "")
            b.item = it
            b:Show()
        else
            b.item = nil
            b:Hide()
        end
    end
    local empty = UI.PICK_EMPTY[pickState.source] or ""
    local Cat = ns.SupplyCatalog
    local catStatus = Cat and Cat.status()
    if pickState.source == "all" and catStatus == "bad" then empty = UI.PICK_NO_CATALOG end
    picker.empty:SetText(#pickState.items == 0 and empty or "")
    picker.pos:SetText(UI.pickPosText())
    UI.syncPickBar()
    picker.sources.select(pickState.source)
    picker.class.value, picker.sub.value = pickState.class, pickState.subclass
    picker.class.refreshText(); picker.sub.refreshText()
    W.setEnabled(picker.sub, pickState.class ~= nil)
end

-- GF-009-14 A: the scroll bar follows the list (the wheel, the arrows, a
-- new search); dragging its thumb only moves the offset, the 10 rows are
-- reused.
local syncing = false
function UI.pickMaxOffset() return math.max(0, #pickState.items - UI.PICK_ROWS) end
function UI.syncPickBar()
    local bar = picker and picker.bar
    if not bar then return end
    local max = UI.pickMaxOffset()
    syncing = true
    bar:SetMinMaxValues(0, max)
    bar:SetValue(pickState.offset)
    syncing = false
    bar.gfMax, bar.gfValue = max, pickState.offset
    W.setEnabled(picker.up, pickState.offset > 0)
    W.setEnabled(picker.down, pickState.offset < max)
    if max == 0 then bar:Hide() else bar:Show() end
end
function UI.pickScrollTo(offset)
    offset = math.max(0, math.min(UI.pickMaxOffset(), math.floor((tonumber(offset) or 0) + 0.5)))
    if offset == pickState.offset then UI.syncPickBar(); return offset end
    pickState.offset = offset
    drawPicker()
    return offset
end
function UI.pickScrollBy(rows) return UI.pickScrollTo(pickState.offset + rows) end
function UI.pickBarChanged(value)
    if syncing then return end
    UI.pickScrollTo(value)
end

-- GF-009-14 A: where the player dragged the finder (kept for this draft).
function UI.pickRemember()
    if not picker then return nil end
    local l = picker.GetLeft and tonumber((picker:GetLeft())) or nil
    local t = picker.GetTop and tonumber((picker:GetTop())) or nil
    if not (l and t) then return nil end
    formState.pickPos = { l, t }
    UI.pickAt = { l, t }
    return formState.pickPos
end

-- 「1-10／共 5414」: which rows are shown (the list is never cut short).
function UI.pickPosText()
    local n = #pickState.items
    if n == 0 then return "" end
    return string.format(UI.PICK_POS, pickState.offset + 1, math.min(n, pickState.offset + UI.PICK_ROWS), n)
end

-- Read the list again (source or search changed); the class filter stays
-- while it still has items.
function UI.pickReload()
    local Cat = ns.SupplyCatalog
    local t0 = Cat and Cat.clock()
    pickState.base = L.catalog({ source = pickState.source, text = pickState.text })
    local hasClass = false
    for _, c in ipairs(L.catalogClasses(pickState.base)) do if c.value == pickState.class then hasClass = true end end
    if not hasClass then pickState.class, pickState.subclass = nil, nil end
    drawPicker()
    if t0 and pickState.source == "all" then Cat.noteList(Cat.clock() - t0) end
    return pickState.items
end

function UI.pickSource(key)
    pickState.source, pickState.offset = key == "all" and "all" or "bag", 0
    return UI.pickReload()
end
function UI.pickSearch(text)
    pickState.text, pickState.offset = ns.str(text), 0
    if picker and picker.search and picker.search:GetText() ~= pickState.text then picker.search:SetText(pickState.text) end
    return UI.pickReload()
end
function UI.pickClass(classID)
    pickState.class, pickState.subclass, pickState.offset = classID, nil, 0
    drawPicker()
    return pickState.items
end
function UI.pickSubclass(subclassID)
    pickState.subclass, pickState.offset = subclassID, 0
    drawPicker()
    return pickState.items
end
UI.PICK_ID_LINE = "物品編號 %d"
-- GF-009-12: the item on the cursor (bags, or any game window that can put an
-- item on the cursor) into the form, the same path as 拖到物品欄.
function UI.pickDrop()
    if not takeCursorItem() then return false end
    if picker then picker:Hide() end
    return true
end

-- Row i of the visible list into the form.
function UI.pickChoose(i)
    local it = pickState.items[pickState.offset + i]
    if not it then return false end
    -- GF-009-13: no made-up bag info; 供應 checks the real bag stacks.
    setFormItem(it.itemID, it.bag and { isBound = false } or nil)
    if picker then picker:Hide() end
    return true
end

local searchToken = 0
local function buildPicker()
    local f = CreateFrame("Frame", UI.PICKER_NAME, UIParent)
    f:SetSize(UI.PICK_W, UI.pickHeight())
    if f.SetClampedToScreen then f:SetClampedToScreen(true) end
    if f.HookScript then f:HookScript("OnHide", function() UI.hideTip() end) end
    -- GF-009-14: DIALOG, not TOOLTIP (the IME candidates were hidden under
    -- it); above the form; the filters' drop-down lists (TOOLTIP) stay above.
    f:SetFrameStrata(UI.EDIT_STRATA)
    if f.SetFrameLevel then f:SetFrameLevel(UI.PICK_LEVEL) end
    if f.SetToplevel then f:SetToplevel(true) end
    Th.panel(f)
    f:EnableMouse(true)
    f.title = label(f, UI.PICK_TITLE, ns.FIELD_FONT)
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
    -- GF-009-14 A: drag by the title bar; the client keeps it on screen
    -- (SetClampedToScreen); not saved in the game's layout file.
    if f.SetMovable then f:SetMovable(true) end
    f.drag = CreateFrame("Frame", nil, f)
    f.drag:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.drag:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(Th.CLOSE_SIZE or 28) - 4, 0)
    f.drag:SetHeight(UI.PICK_DRAG_H)
    f.drag:EnableMouse(true)
    if f.drag.RegisterForDrag then f.drag:RegisterForDrag("LeftButton") end
    f.drag:SetScript("OnDragStart", function() if f.StartMoving then f:StartMoving() end end)
    f.drag:SetScript("OnDragStop", function()
        if f.StopMovingOrSizing then f:StopMovingOrSizing() end
        if f.SetUserPlaced then f:SetUserPlaced(false) end
        UI.pickRemember()
    end)
    f.close = Th.closeButton(f)
    f.sources = Th.tabStrip(f, UI.PICK_SOURCES, 12, -40, function(key) UI.pickSource(key) end)
    local P = UI.PICK_FILTER
    f.searchLabel = label(f, "搜尋", ns.FIELD_FONT)
    f.searchLabel:SetPoint("TOPLEFT", f, "TOPLEFT", P.searchLabel, -86)
    f.search = Th.editBox(f, P.searchW, 30)
    f.search:SetPoint("TOPLEFT", f, "TOPLEFT", P.search, -80)
    f.search.tip = "名字或物品編號"
    withTip(f.search)
    f.search:SetScript("OnTextChanged", function(self)
        searchToken = searchToken + 1
        local token, text = searchToken, self:GetText()
        ns.after(0.25, function() if token == searchToken and text ~= pickState.text then UI.pickSearch(text) end end)
    end)
    f.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.search:SetScript("OnEnterPressed", function(self) self:ClearFocus(); UI.pickSearch(self:GetText()) end)
    f.class = ns.choiceButton(f, P.filterW, P.class, -80, function()
        local list = { { value = nil, text = "全部類型" } }
        for _, c in ipairs(L.catalogClasses(pickState.base)) do list[#list + 1] = c end
        return list
    end, function(value) UI.pickClass(value) end, "全部類型")
    f.sub = ns.choiceButton(f, P.filterW, P.sub, -80, function()
        local list = { { value = nil, text = "全部子類" } }
        for _, c in ipairs(L.catalogSubclasses(pickState.base, pickState.class)) do list[#list + 1] = c end
        return list
    end, function(value) UI.pickSubclass(value) end, "全部子類")
    f.empty = label(f, "", ns.LABEL_FONT)
    f.empty:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -126)
    f.pos = label(f, "", ns.DISABLED_FONT)
    f.pos:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 12)
    -- GF-009-12: an item dropped on the finder is chosen like a row.
    f:SetScript("OnReceiveDrag", function() UI.pickDrop() end)
    -- GF-009-14 A: a scroll bar like the game's (arrows, a thumb to drag),
    -- right of the rows; the wheel anywhere on the finder scrolls too.
    local rowsTop, rowsH = -120, UI.PICK_ROWS * 40
    local function arrow(dir, y)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(18, 18)
        b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, y)
        local base = "Interface\\Buttons\\UI-ScrollBar-Scroll" .. dir .. "Button-"
        if b.SetNormalTexture then
            b:SetNormalTexture(base .. "Up"); b:SetPushedTexture(base .. "Down")
            b:SetDisabledTexture(base .. "Disabled"); b:SetHighlightTexture(base .. "Highlight")
        end
        return b
    end
    f.up = arrow("Up", rowsTop)
    f.up:SetScript("OnClick", function() UI.pickScrollBy(-1) end)
    f.down = arrow("Down", rowsTop - rowsH + 18)
    f.down:SetScript("OnClick", function() UI.pickScrollBy(1) end)
    f.bar = CreateFrame("Slider", nil, f)
    f.bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -9, rowsTop - 18)
    f.bar:SetSize(16, rowsH - 36)
    if f.bar.SetOrientation then f.bar:SetOrientation("VERTICAL") end
    if f.bar.SetThumbTexture then f.bar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob") end
    if f.bar.SetValueStep then f.bar:SetValueStep(1) end
    if f.bar.SetObeyStepOnDrag then f.bar:SetObeyStepOnDrag(true) end
    f.bar.track = f.bar:CreateTexture(nil, "BACKGROUND")
    f.bar.track:SetAllPoints()
    f.bar.track:SetColorTexture(0, 0, 0, 0.35)
    f.bar:SetMinMaxValues(0, 0)
    f.bar:SetValue(0)
    f.bar:SetScript("OnValueChanged", function(_, value) UI.pickBarChanged(value) end)
    if f.EnableMouseWheel then f:EnableMouseWheel(true) end
    f:SetScript("OnMouseWheel", function(_, delta) UI.pickScrollBy(-delta) end)
    f.rows = {}
    local C = UI.PICK_COL
    for i = 1, UI.PICK_ROWS do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(UI.PICK_W - 24 - UI.PICK_BAR_W, 38)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -120 - (i - 1) * 40)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(32, 32)
        b.icon:SetPoint("LEFT", b, "LEFT", C.icon, 0)
        b.name = label(b, "", ns.LABEL_FONT)
        b.name:SetPoint("LEFT", b, "LEFT", C.name, 0)
        b.name:SetWidth(C.nameW)
        if b.name.SetWordWrap then b.name:SetWordWrap(false) end
        b.kind = label(b, "", ns.DISABLED_FONT)
        b.kind:SetPoint("LEFT", b, "LEFT", C.type, 0)
        b.kind:SetWidth(C.typeW)
        if b.kind.SetWordWrap then b.kind:SetWordWrap(false) end
        b.count = label(b, "", ns.LABEL_FONT)
        b.count:SetPoint("RIGHT", b, "RIGHT", -6, 0)
        b:SetScript("OnClick", function() UI.pickChoose(i) end)
        b:SetScript("OnEnter", function(self)
            if self.item then itemTooltip(self, self.item.itemID, { string.format(UI.PICK_ID_LINE, self.item.itemID) }) end
        end)
        b:SetScript("OnReceiveDrag", function() UI.pickDrop() end)
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        if b.EnableMouseWheel then b:EnableMouseWheel(true) end
        b:SetScript("OnMouseWheel", function(_, delta) UI.pickScrollBy(-delta) end)
        f.rows[i] = b
    end
    f:Hide()
    -- GF-009-14: a window (above the form for ESC), not a menu: no
    -- click-outside layer (TOOLTIP) over it. ESC, X, a pick or closing the
    -- form close it.
    ns.escRegister(f, ns.ESC_LEVEL.popup)
    picker = f
    return f
end

-- source: "bag" (從背包選, the default) or "all" (找物品).
function UI.openPicker(source)
    if not picker then buildPicker() end
    picker:ClearAllPoints()
    -- GF-009-13: placed from the screen size, so it never runs off a narrow
    -- screen or a large UI scale (UI.layoutPair).
    local sw, sh = UI.screenSize()
    local ph = UI.pickHeight()
    if form and form:IsShown() and formState.pickPos then
        -- GF-009-14 A: dragged before in this draft: there (still on screen).
        local px, pt = UI.clampPos(sw, sh, UI.PICK_W, ph, formState.pickPos[1], formState.pickPos[2])
        picker:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", px, pt)
        UI.pickAt = { px, pt }
    elseif form and form:IsShown() then
        local fl, ft = UI.formRect(sw, sh)
        local nl, nt, px, pt = UI.layoutPair(sw, sh, UI.FORM_W, UI.FORM_H, UI.PICK_W, ph, fl, ft)
        if math.abs(nl - fl) > 0.5 or math.abs(nt - ft) > 0.5 then
            form:ClearAllPoints()
            form:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", nl, nt)
            UI.formAt = { nl, nt }
        end
        picker:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", px, pt)
        UI.pickAt = { px, pt }
    else
        picker:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        UI.pickAt = { (sw - UI.PICK_W) / 2, (sh + ph) / 2 }
    end
    pickState.source = source == "all" and "all" or "bag"
    pickState.text, pickState.class, pickState.subclass, pickState.offset = "", nil, nil, 0
    picker.search:SetText("")
    picker.title:SetText(UI.PICK_TITLE) -- GF-009-14 A: always 找物品 (背包 / 全部 are the tabs)
    UI.pickReload()
    picker:Show()
    return picker
end
function UI.picker() return picker end
-- GF-009-12: Shift-click on an item while the finder's search box has focus:
-- the link goes into the search (one row: that item).
function UI.pickLink(link)
    if not (picker and picker:IsShown() and picker.search.HasFocus and picker.search:HasFocus()) then return false end
    if not L.itemFromText(link) then return false end
    picker.search:SetText(link)
    UI.pickSearch(link)
    return true
end
-- Item data arrived: the open picker shows the newly known items (once per half second).
function UI.pickerItemInfo()
    if picker and picker:IsShown() then UI.pickReload() end
end
local pickTimer = false
function UI.pickerItemInfoSoon()
    if pickTimer or not (picker and picker:IsShown()) then return end
    pickTimer = true
    ns.after(0.5, function() pickTimer = false; UI.pickerItemInfo() end)
end

---------------------------------------------------------------------------

Supply.onChanged = UI.refreshSoon
Supply.onItemInfo = function() UI.refreshSoon(); UI.pickerItemInfoSoon(); UI.formItemInfo() end
ns.Share.onUpdate(function() Supply.invalidate(); UI.refreshSoon() end)

local regen = CreateFrame("Frame")
pcall(regen.RegisterEvent, regen, "PLAYER_REGEN_ENABLED")
pcall(regen.RegisterEvent, regen, "ADDON_LOADED")
-- GF-UI-F (MANUAL §3uif): /gftk supply state <empty|loading|stale|error|off>
-- opens the page showing that state, for the owner's screenshots. Init.lua
-- sets the slash handler while loading; it is wrapped once all files are in.
local slashWrapped = false
function UI.command(rest)
    local kind = ns.str(rest):match("^state%s*(%a*)")
    if not kind then return false end
    ns.Framework.open(UI.ID)
    if not UI.previewState(kind:lower()) then ns.say("/gftk supply state empty｜loading｜stale｜error｜off") end
    return true
end
local function wrapSlash()
    if slashWrapped or type(SlashCmdList) ~= "table" or type(SlashCmdList.GREENFANGTOOLKIT) ~= "function" then return end
    slashWrapped = true
    local orig = SlashCmdList.GREENFANGTOOLKIT
    SlashCmdList.GREENFANGTOOLKIT = function(msg, ...)
        local rest = ns.str(msg):gsub("^%s+", ""):match("^[Ss][Uu][Pp][Pp][Ll][Yy]%s+(.+)$")
        if rest and UI.command(rest) then return end
        return orig(msg, ...)
    end
end
regen:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == "GreenFangToolkit" then wrapSlash() end
        return
    end
    ns.after(0, function() if UI.pending then UI.refreshSoon() end end)
end)

ns.Framework.register({
    id = UI.ID,
    title = "綠皮調貨所",
    short = "調貨",
    group = "logistics", -- 物資調度 (GF-UI-E places it)
    order = 16,
    create = build,
    show = UI.refresh,
})

-- 0.16.0 (spec v2.0 §5.1, §7.1): 職工檔案「個人需求」opens this page on 我的刊登
-- (the same records; nothing is copied into the personnel file).
if ns.Profile and ns.Profile.setNeedsProvider then
    ns.Profile.setNeedsProvider({
        open = function()
            ns.Framework.open(UI.ID)
            UI.setTab("mine")
        end,
    })
end
