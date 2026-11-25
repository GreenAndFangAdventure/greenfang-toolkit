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
UI.DETAIL_X, UI.DETAIL_W = 586, 492
UI.DETAIL_ROWS = 9
UI.TOP = -96
UI.FORM_NAME = "GreenFangToolkit_SupplyForm"
UI.PICKER_NAME = "GreenFangToolkit_SupplyBagPicker"
UI.PLACEHOLDER = "Interface\\Icons\\INV_Misc_QuestionMark"
UI.FOOT = "僅供資訊媒合，交換條件由雙方自行協議"

UI.TABS = {
    { key = "need", text = "我缺的" },
    { key = "offer", text = "我可能有多的" },
    { key = "guild", text = "公會供需" },
    { key = "mine", text = "我的刊登" },
}
UI.EMPTY = {
    need = "目前沒有缺的物品",
    offer = "目前沒有可能多的物品",
    guild = "目前沒有可配對的公會物資",
    mine = "還沒有刊登",
}

local panel, tabs, emptyLine, footLine, autoBox, manualBox, postButton
local rows, detailRows = {}, {}
local detail = {}
local state = { tab = "need", offset = 0, selected = nil, items = {} }
UI.state = state

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

-- One person line in the detail list.
function UI.personText(e)
    local name = e.member and ns.shortName(e.member.name) or "未知"
    local what = e.direction == "need" and ("缺 " .. e.qty) or ("可能有 " .. e.qty)
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
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local shown = false
    if itemID and type(GameTooltip.SetItemByID) == "function" then shown = pcall(GameTooltip.SetItemByID, GameTooltip, itemID) end
    if not shown then GameTooltip:AddLine((Supply.itemLabel(itemID))) end
    for _, line in ipairs(extra or {}) do GameTooltip:AddLine(line, 0.8, 0.8, 0.8) end
    GameTooltip:Show()
end

local function newRow(i)
    local r = CreateFrame("Button", nil, panel)
    r:SetSize(UI.LIST_W, UI.ROW_H - 4)
    r:SetPoint("TOPLEFT", panel, "TOPLEFT", UI.LIST_X, UI.TOP - (i - 1) * UI.ROW_H)
    r.bg = Th.fill(r, Th.C.fill, "BACKGROUND")
    r.sel = W.rowSelect(r)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(UI.ICON, UI.ICON)
    r.icon:SetPoint("LEFT", r, "LEFT", 4, 0)
    r.name = r:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)
    r.name:SetPoint("LEFT", r, "LEFT", UI.ICON + 12, 0)
    r.name:SetWidth(220)
    r.name:SetJustifyH("LEFT")
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end
    r.qty = r:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT)
    r.qty:SetPoint("LEFT", r, "LEFT", 276, 0)
    r.qty:SetWidth(120)
    r.qty:SetJustifyH("LEFT")
    if r.qty.SetWordWrap then r.qty:SetWordWrap(false) end
    r.match = r:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)
    r.match:SetPoint("RIGHT", r, "RIGHT", -8, 0)
    r.match:SetWidth(136)
    r.match:SetJustifyH("RIGHT")
    if r.match.SetWordWrap then r.match:SetWordWrap(false) end
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
            out[#out + 1] = { itemID = l.itemID, listing = l,
                qty = L.DIRECTION_TEXT[l.direction] .. " " .. l.quantity,
                match = L.STATUS_TEXT[l.status] or "",
                tip = { L.categoryText(l.category), l.note ~= "" and l.note or nil } }
        end
        return out
    end
    for _, it in ipairs(Supply.view(kind)) do
        local tip = {}
        if it.mine then tip[#tip + 1] = "來源：" .. sourceText(it.mine) end
        out[#out + 1] = { itemID = it.itemID, item = it, qty = UI.qtyText(kind, it), match = UI.matchText(kind, it), tip = tip }
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
            r.qty:SetText(data.qty or "")
            r.match:SetText(data.match or "")
            r.sel.set(state.selected == state.offset + i)
            r:Show()
        elseif r then
            r:Hide()
        end
    end
    emptyLine:SetText(#list == 0 and UI.EMPTY[state.tab] or "")
end

---------------------------------------------------------------------------
-- Detail (the selected item)
---------------------------------------------------------------------------

local function newDetailRow(i)
    local r = CreateFrame("Frame", nil, panel)
    r:SetSize(UI.DETAIL_W, 40)
    r:SetPoint("TOPLEFT", panel, "TOPLEFT", UI.DETAIL_X, UI.TOP - 60 - (i - 1) * 44)
    r.name = r:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)
    r.name:SetPoint("LEFT", r, "LEFT", 4, 0)
    r.name:SetWidth(130)
    r.name:SetJustifyH("LEFT")
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end
    r.what = r:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT)
    r.what:SetPoint("LEFT", r, "LEFT", 138, 0)
    r.what:SetWidth(96)
    r.what:SetJustifyH("LEFT")
    r.on = r:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)
    r.on:SetPoint("LEFT", r, "LEFT", 238, 0)
    r.on:SetWidth(44)
    r.fresh = r:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)
    r.fresh:SetPoint("LEFT", r, "LEFT", 286, 0)
    r.fresh:SetWidth(44)
    r.src = r:CreateFontString(nil, "ARTWORK", ns.DISABLED_FONT)
    r.src:SetPoint("LEFT", r, "LEFT", 334, 0)
    r.src:SetWidth(76)
    r.contact = Th.button(r, "聯絡", 72, ns.BUTTON_H)
    r.contact:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r.contact:SetScript("OnClick", function(self) if self.entry then Supply.contact(self.entry) end end)
    detailRows[i] = r
    return r
end

local function hideDetailRows(from)
    for i = from, #detailRows do detailRows[i]:Hide() end
end

-- Buttons under a listing of my own: 修改, 續期, 結束.
local function shown(f, on) if on then f:Show() else f:Hide() end end
local function listingButtons(l)
    local on = l ~= nil and l.status == "active"
    shown(detail.edit, on); shown(detail.renew, on); shown(detail.finish, on)
    detail.edit.listing, detail.renew.listing, detail.finish.listing = l, l, l
end

function UI.drawDetail()
    if not panel then return end
    local data = state.selected and state.items[state.selected]
    if not data then
        detail.icon:Hide()
        detail.name:SetText("")
        detail.sub:SetText(#state.items > 0 and "選一個物品查看" or "")
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
        hideDetailRows(1)
        if l.note and l.note ~= "" then
            local r = detailRows[1] or newDetailRow(1)
            r.name:SetText("備註")
            r.what:SetText("")
            r.on:SetText(""); r.fresh:SetText(""); r.src:SetText("")
            r.what:SetWidth(330)
            r.what:SetText(l.note)
            r.contact:Hide()
            r:Show()
        end
        return
    end
    listingButtons(nil)
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
            r.src:SetText(sourceText(e))
            r.contact.entry = e
            r.contact:Show()
            W.setEnabled(r.contact, Supply.canContact(e))
            r:Show()
        elseif r then
            r:Hide()
        end
    end
end

function UI.select(index)
    state.selected = index
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
    state.items = UI.listFor(state.tab)
    state.selected = nil
    for i, d in ipairs(state.items) do
        if (keepListing and d.listing and d.listing.id == keepListing.id) or (not keepListing and keepItem and d.itemID == keepItem) then
            state.selected = i
        end
    end
    if not state.selected and #state.items > 0 then state.selected = 1 end
    state.offset = math.max(0, math.min(state.offset, #state.items - UI.ROWS))
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

-- f.tip under the mouse (check boxes, buttons, edit boxes of this page).
local function withTip(f)
    if not f or not f.HookScript then return f end
    f:HookScript("OnEnter", function(self)
        if self.tip and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(self.tip, 1, 1, 1, true); GameTooltip:Show()
        end
    end)
    f:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return f
end
UI.withTip = withTip

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
    local title = label(p, "綠皮調貨所", ns.TITLE_FONT)
    title:SetPoint("TOPLEFT", p, "TOPLEFT", 22, -16)
    local sub = label(p, "公會物資供需", ns.DISABLED_FONT)
    sub:SetPoint("LEFT", title, "RIGHT", 12, 0)
    autoBox = checkWithLabel(p, "自動集料", 660, -12, function(on) Supply.setAuto(on); UI.refresh() end)
    autoBox.tip = "試用：荊棘谷書頁，依任務與背包自動算出缺的和可能多的（規則尚未實機確認）"
    manualBox = checkWithLabel(p, "手動刊登", 840, -12, function(on) Supply.setManual(on); UI.refresh() end)
    manualBox.tip = "關掉後不再分享我的刊登，也不顯示別人的刊登"
    withTip(autoBox); withTip(manualBox)
    tabs = Th.tabStrip(p, (function()
        local items = {}
        for _, t in ipairs(UI.TABS) do items[#items + 1] = { key = t.key, text = t.text } end
        return items
    end)(), 22, -50, function(key) UI.setTab(key) end)
    tabs.select(state.tab)
    postButton = Th.button(p, "刊登", 96, ns.BUTTON_H)
    postButton:SetPoint("TOPLEFT", p, "TOPLEFT", UI.LIST_X + UI.LIST_W - 96, -50)
    postButton:SetScript("OnClick", function() UI.openForm() end)
    emptyLine = label(p, "", ns.LABEL_FONT)
    emptyLine:SetPoint("TOPLEFT", p, "TOPLEFT", UI.LIST_X + 8, UI.TOP - 12)
    Th.vline(p, UI.DETAIL_X - 16, UI.TOP, UI.TOP - UI.ROWS * UI.ROW_H)
    detail.icon = p:CreateTexture(nil, "ARTWORK")
    detail.icon:SetSize(40, 40)
    detail.icon:SetPoint("TOPLEFT", p, "TOPLEFT", UI.DETAIL_X, UI.TOP)
    detail.name = label(p, "", ns.TITLE_FONT)
    detail.name:SetPoint("TOPLEFT", p, "TOPLEFT", UI.DETAIL_X + 50, UI.TOP - 2)
    detail.name:SetWidth(UI.DETAIL_W - 50)
    if detail.name.SetWordWrap then detail.name:SetWordWrap(false) end
    detail.sub = label(p, "", ns.LABEL_FONT)
    detail.sub:SetPoint("TOPLEFT", p, "TOPLEFT", UI.DETAIL_X + 50, UI.TOP - 26)
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
    listingButtons(nil)
    footLine = label(p, UI.FOOT, ns.DISABLED_FONT)
    footLine:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 22, 18)
end

---------------------------------------------------------------------------
-- The listing form (one window; ESC and X close it, a click outside does
-- not: it may hold what the player typed)
---------------------------------------------------------------------------

local form
local formState = {}
UI.formState = formState

local function formMessage(text) if form then form.msg:SetText(text or "") end end

local function setFormItem(itemID, bagInfo)
    formState.itemID, formState.bagInfo = itemID, bagInfo
    if not form then return end
    if itemID then
        setItemIcon(form.itemIcon, itemID)
        form.itemName:SetText((Supply.itemLabel(itemID)))
        local info = L.itemInfo(itemID)
        local cat = info and info.classID and L.CLASS_CATEGORY[info.classID]
        if cat and not formState.categoryTouched then formState.category = cat; form.cats.select(cat) end
        local problem = not formState.editing and L.itemProblem(itemID, bagInfo) or nil
        formMessage(problem)
    else
        form.itemIcon:Hide()
        form.itemName:SetText("把物品拖到這裡、按住 Shift 點物品，或從背包選")
    end
end
UI.setFormItem = setFormItem

function UI.formFromText(text)
    local id = L.itemFromText(text)
    if id then setFormItem(id) end
    return id
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
        end
    end
    if type(ChatEdit_InsertLink) == "function" then pcall(hooksecurefunc, "ChatEdit_InsertLink", onLink) end
    if type(ChatFrameUtil) == "table" and type(ChatFrameUtil.InsertLink) == "function" then
        pcall(hooksecurefunc, ChatFrameUtil, "InsertLink", onLink)
    end
end

-- An item held on the cursor (dragged from the bags).
local function takeCursorItem()
    if type(GetCursorInfo) ~= "function" then return false end
    local kind, itemID = GetCursorInfo()
    if kind ~= "item" or type(itemID) ~= "number" then return false end
    if type(ClearCursor) == "function" then ClearCursor() end
    setFormItem(itemID)
    return true
end

local function buildForm()
    local f = ns.popupWindow(UI.FORM_NAME, 600, 470)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    f.TitleText:SetText("刊登")
    local x, y = 24, -48
    local function row(text)
        local fs = label(f, text, ns.FIELD_FONT)
        fs:SetPoint("TOPLEFT", f, "TOPLEFT", x, y - 6)
        return fs
    end
    row("方向")
    f.dirs = Th.tabStrip(f, { { key = "need", text = "徵求" }, { key = "offer", text = "供應" } }, 104, y,
        function(key) formState.direction = key end)
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
    f.itemBox = Th.editBox(f, 300, 30)
    f.itemBox:SetPoint("TOPLEFT", f, "TOPLEFT", 104, y)
    f.itemBox:SetScript("OnTextChanged", function(self) UI.formFromText(self:GetText()) end)
    f.itemBox.tip = "貼上物品連結，或游標在這裡時按住 Shift 點物品"
    withTip(f.itemBox)
    f.pick = Th.button(f, "從背包選", 110, ns.BUTTON_H)
    f.pick:SetPoint("LEFT", f.itemBox, "RIGHT", 10, 0)
    f.pick:SetScript("OnClick", function() UI.openPicker() end)
    y = y - 50
    row("分類")
    local cats = {}
    for _, c in ipairs(L.CATEGORIES) do cats[#cats + 1] = { key = c.key, text = c.text, w = 72 } end
    f.cats = Th.tabStrip(f, cats, 104, y, function(key) formState.category = key; formState.categoryTouched = true end)
    y = y - 50
    row("數量")
    f.qty = Th.editBox(f, 80, 30)
    f.qty:SetPoint("TOPLEFT", f, "TOPLEFT", 104, y)
    if f.qty.SetNumeric then f.qty:SetNumeric(true) end
    if f.qty.SetMaxLetters then f.qty:SetMaxLetters(3) end
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
    f.cancel:SetScript("OnClick", function() f:Hide() end)
    f:Hide()
    form = f
    hookLinks()
    return f
end

-- listing: edit that one (direction and item stay); nil: a new one.
function UI.openForm(listing)
    if not Supply.manualOn() then return false end
    local f = form or buildForm()
    for k in pairs(formState) do formState[k] = nil end
    formState.editing = listing
    formState.direction = listing and listing.direction or "need"
    formState.category = listing and listing.category or "other"
    formState.categoryTouched = listing ~= nil
    formState.days = listing and listing.days or L.DEFAULT_DAYS
    f.TitleText:SetText(listing and "修改刊登" or "刊登")
    f.save:SetText(listing and "儲存" or "刊登")
    f.dirs.select(formState.direction)
    f.cats.select(formState.category)
    f.days.select(formState.days)
    f.itemBox:SetText("")
    f.qty:SetText(tostring(listing and listing.quantity or 1))
    f.note:SetText(listing and listing.note or "")
    W.setEnabled(f.pick, listing == nil)
    for _, b in ipairs(f.dirs.buttons) do W.setEnabled(b, listing == nil) end
    if listing then f.itemBox:Hide() else f.itemBox:Show() end
    setFormItem(listing and listing.itemID or nil)
    formMessage("")
    f:Show()
    return true
end

function UI.submitForm()
    if not form then return nil end
    local fields = { direction = formState.direction, itemID = formState.itemID, bagInfo = formState.bagInfo,
        category = formState.category, quantity = tonumber(form.qty:GetText()), days = formState.days,
        note = form.note:GetText() }
    local l, why, dup
    if formState.editing then l, why = L.update(formState.editing.id, fields)
    else l, why, dup = L.create(fields) end
    if not l then
        formMessage(why)
        if dup then
            -- An active listing of the same item: edit that one instead.
            ns.after(0, function() UI.openForm(dup); formMessage(why) end)
        end
        return nil, why
    end
    form:Hide()
    if not formState.editing then state.tab = "mine"; if tabs then tabs.select("mine") end end
    UI.refresh()
    return l
end

function UI.form() return form end

---------------------------------------------------------------------------
-- The bag picker (a list: ESC and a click outside close it)
---------------------------------------------------------------------------

local picker
UI.PICK_ROWS = 10
local pickState = { offset = 0, items = {} }

local function drawPicker()
    for i = 1, UI.PICK_ROWS do
        local b = picker.rows[i]
        local it = pickState.items[pickState.offset + i]
        if it then
            setItemIcon(b.icon, it.itemID)
            b.name:SetText((Supply.itemLabel(it.itemID)))
            b.count:SetText("x" .. it.count)
            b.item = it
            b:Show()
        else
            b:Hide()
        end
    end
    picker.empty:SetText(#pickState.items == 0 and "背包裡沒有可交易的物品" or "")
end

function UI.openPicker()
    if not picker then
        local f = CreateFrame("Frame", UI.PICKER_NAME, UIParent)
        f:SetSize(360, UI.PICK_ROWS * 40 + 56)
        f:SetFrameStrata("TOOLTIP")
        if f.SetFrameLevel then f:SetFrameLevel(100) end
        Th.panel(f)
        f:EnableMouse(true)
        f.title = label(f, "從背包選", ns.FIELD_FONT)
        f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
        f.close = Th.closeButton(f)
        f.empty = label(f, "", ns.LABEL_FONT)
        f.empty:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -48)
        f.rows = {}
        for i = 1, UI.PICK_ROWS do
            local b = CreateFrame("Button", nil, f)
            b:SetSize(336, 38)
            b:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -42 - (i - 1) * 40)
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetSize(32, 32)
            b.icon:SetPoint("LEFT", b, "LEFT", 2, 0)
            b.name = label(b, "", ns.LABEL_FONT)
            b.name:SetPoint("LEFT", b, "LEFT", 42, 0)
            b.name:SetWidth(230)
            if b.name.SetWordWrap then b.name:SetWordWrap(false) end
            b.count = label(b, "", ns.LABEL_FONT)
            b.count:SetPoint("RIGHT", b, "RIGHT", -6, 0)
            b:SetScript("OnClick", function(self)
                if self.item then setFormItem(self.item.itemID, { isBound = false }) end
                f:Hide()
            end)
            b:SetScript("OnEnter", function(self) if self.item then itemTooltip(self, self.item.itemID) end end)
            b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
            if b.EnableMouseWheel then b:EnableMouseWheel(true) end
            b:SetScript("OnMouseWheel", function(_, delta)
                pickState.offset = math.max(0, math.min(math.max(0, #pickState.items - UI.PICK_ROWS), pickState.offset - delta))
                drawPicker()
            end)
            f.rows[i] = b
        end
        f:Hide()
        ns.escRegister(f, ns.ESC_LEVEL.grid)
        picker = f
    end
    picker:ClearAllPoints()
    if form and form:IsShown() then picker:SetPoint("TOPLEFT", form, "TOPRIGHT", 4, 0)
    else picker:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
    pickState.items, pickState.offset = L.bagItems() or {}, 0
    drawPicker()
    picker:Show()
    return picker
end
function UI.picker() return picker end

---------------------------------------------------------------------------

Supply.onChanged = UI.refreshSoon
Supply.onItemInfo = UI.refreshSoon
ns.Share.onUpdate(function() Supply.invalidate(); UI.refreshSoon() end)

local regen = CreateFrame("Frame")
pcall(regen.RegisterEvent, regen, "PLAYER_REGEN_ENABLED")
regen:SetScript("OnEvent", function() ns.after(0, function() if UI.pending then UI.refreshSoon() end end) end)

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
