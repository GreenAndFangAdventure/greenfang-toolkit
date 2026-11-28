-- NotifyUI (GF-014, spec v2.0 §3 業務通知 共用入口): the bell on the main
-- window (the game's own icon, the short name 業務通知 and the unread count)
-- and its small list. The list is a menu-level frame: the X, ESC and a click
-- outside close it. A row opens its target (Notify.open); its buttons are the
-- module's actions. Nothing is added to the minimap. The switches (one per
-- module, and the chat line) sit in the same list under 設定, and
-- NotifyUI.buildSettings(parent) can draw them on a 事務設定 page later.
--
-- The window is built by Framework.lua when it first opens; the bell is put on
-- it right after (Framework.open is wrapped, nothing in Framework.lua changes).

local _, ns = ...
local str = ns.str

local UI = {}
ns.NotifyUI = UI
local N = ns.Notify
local Th, W = ns.Theme, ns.Widgets

UI.BUTTON_NAME = "GreenFangToolkit_NotifyButton"
UI.LIST_NAME = "GreenFangToolkit_NotifyList"
UI.NAME = "業務通知"
-- A bell-like game icon, with fallbacks every 1.x client ships (MANUAL GF-014).
UI.ICONS = { "Interface\\Icons\\INV_Misc_Bell_01", "Interface\\Icons\\INV_Misc_Horn_01", "Interface\\Icons\\INV_Letter_15" }
UI.ICON = 22
UI.W = 520
UI.ROWS = 6
UI.ROW_H = 66
UI.TOP = -44
-- GF-UI-P: the rows leave a column on the right for the scroll bar (Widgets.scrollBar).
UI.ROW_W = UI.W - 24 - ns.Widgets.SCROLL_W - ns.Widgets.SCROLL_GAP
UI.MODULE_SHORT = { supply = "調貨", radar = "雷達", adventure = "冒險", orders = "委託",
    order_new = "委託", order_status = "委託", adv_signup = "冒險", adv_result = "冒險", adv_final = "冒險", bank_keeper = "黑箱", recipe = "調貨" } -- GF-014-04
for k, v in pairs({ order_guild = "委託", order_remind = "委託", adv_update = "冒險", adv_remind = "冒險", adv_leader = "冒險" }) do
    UI.MODULE_SHORT[k] = v -- GF-014-05
end
UI.MODULE_SHORT.bank_request = "黑箱" -- GF-012-D

-- GF-UI-N (owner 0.16.12: 「未讀與已讀也應該要清楚辨識」): an unread row has the
-- game's small yellow light before its tag, a warm fill and gold words; a read
-- row has no light, no fill and dim words. Game files only, first one found.
UI.UNREAD_ICONS = { "Interface\\COMMON\\Indicator-Yellow", "Interface\\FriendsFrame\\StatusIcon-Online",
    "Interface\\GossipFrame\\AvailableQuestIcon" }
UI.UNREAD_ICON = 14
UI.READ_ALPHA = 0.55 -- the read words: the muted colour at this alpha
-- How a row looks: { mark, fill, text = { r, g, b, a }, tag = { r, g, b, a } }.
function UI.rowLook(unread)
    local C = Th.C
    if unread then
        return { mark = true, fill = true, text = { C.gold[1], C.gold[2], C.gold[3], 1 }, tag = { C.text[1], C.text[2], C.text[3], 1 } }
    end
    return { mark = false, fill = false, text = { C.muted[1], C.muted[2], C.muted[3], UI.READ_ALPHA },
        tag = { C.muted[1], C.muted[2], C.muted[3], UI.READ_ALPHA } }
end

local button, list
local state = { offset = 0, items = {}, settings = false }

local function label(parent, text, font)
    local fs = parent:CreateFontString(nil, "ARTWORK", font or ns.LABEL_FONT)
    fs:SetText(text or "")
    if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
    return fs
end

local function setIcon(tex)
    for _, path in ipairs(UI.ICONS) do
        if ns.Icons.set(tex, path) then
            if tex.SetTexCoord and ns.GameIcons and ns.GameIcons.ICON_CROP then
                local c = ns.GameIcons.ICON_CROP
                tex:SetTexCoord(c[1], c[2], c[3], c[4])
            end
            tex.gfPath = path
            return true
        end
    end
    return false
end

-- "剛剛" / "5 分鐘前" / "3 小時前" / "2 天前"
function UI.ago(t)
    local d = math.max(0, ns.now() - (t or 0))
    if d < 60 then return "剛剛" end
    if d < 3600 then return string.format("%d 分鐘前", math.floor(d / 60)) end
    if d < 86400 then return string.format("%d 小時前", math.floor(d / 3600)) end
    return string.format("%d 天前", math.floor(d / 86400))
end

---------------------------------------------------------------------------
-- The bell on the main window
---------------------------------------------------------------------------

function UI.updateButton()
    if not button then return end
    local n = N.unread()
    if n > 0 then
        button.count:SetText(n > 99 and "99+" or tostring(n))
        button.count:Show()
    else
        button.count:SetText("")
        button.count:Hide()
    end
    button.tip = n > 0 and string.format("業務通知：%d 則未讀", n) or "業務通知：沒有未讀"
end

function UI.attach()
    local F = ns.Framework
    local win = F and _G[F.WINDOW_NAME]
    if not win then return nil end
    if button then return button end
    local b = CreateFrame("Button", UI.BUTTON_NAME, win)
    local textW = ns.labelWidth(UI.NAME)
    b:SetSize(UI.ICON + 8 + textW + 30, 28)
    -- In the title line, left of the X.
    b:SetPoint("TOPRIGHT", win, "TOPRIGHT", -(Th.CLOSE_SIZE + 8), -1)
    b.gfHover = Th.fill(b, Th.C.hover, "HIGHLIGHT")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(UI.ICON, UI.ICON)
    b.icon:SetPoint("LEFT", b, "LEFT", 4, 0)
    setIcon(b.icon)
    b.tex = b.icon
    b.text = label(b, UI.NAME, ns.LABEL_FONT)
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
    b.label = b.text
    -- The unread count in gold next to the name (no coloured badge: theme rule).
    b.count = b:CreateFontString(nil, "OVERLAY", ns.FIELD_FONT)
    b.count:SetPoint("LEFT", b.text, "RIGHT", 4, 0)
    b:SetScript("OnClick", function() UI.toggle() end)
    b:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:AddLine(self.tip or UI.NAME, 1, 1, 1, true); GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    button = b
    UI.updateButton()
    return b
end
function UI.button() return button end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------

local function actionButton(parent)
    local a = Th.button(parent, "", 96, 26)
    a:SetScript("OnClick", function(self)
        local e = self.entry
        if not e then return end
        local res = N.action(e, self.key)
        if self.key ~= "ignore" and list then list:Hide() end
        UI.draw()
        return res
    end)
    return a
end

local function row(i)
    local r = list.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, list)
    r:SetSize(UI.ROW_W, UI.ROW_H - 4)
    r:SetPoint("TOPLEFT", list, "TOPLEFT", 12, UI.TOP - (i - 1) * UI.ROW_H)
    r.gfHover = Th.fill(r, Th.C.hover, "HIGHLIGHT")
    r.unreadFill = Th.fill(r, Th.C.selFill, "BACKGROUND") -- GF-UI-N
    r.unreadFill:Hide()
    r.mark = r:CreateTexture(nil, "OVERLAY")
    r.mark:SetSize(UI.UNREAD_ICON, UI.UNREAD_ICON)
    r.mark:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -7)
    for _, path in ipairs(UI.UNREAD_ICONS) do
        if ns.Icons.set(r.mark, path) then r.mark.gfPath = path; break end
    end
    r.mark:Hide()
    r.tag = label(r, "", ns.FIELD_FONT)
    r.tag:SetPoint("TOPLEFT", r, "TOPLEFT", 16, -4)
    r.text = label(r, "", ns.LABEL_FONT)
    r.text:SetPoint("TOPLEFT", r, "TOPLEFT", 52, -4)
    r.text:SetWidth(UI.ROW_W - 52 - 96)
    if r.text.SetWordWrap then r.text:SetWordWrap(false) end
    r.when = label(r, "", ns.LABEL_FONT)
    r.when:SetPoint("TOPRIGHT", r, "TOPRIGHT", -4, -4)
    if r.when.SetJustifyH then r.when:SetJustifyH("RIGHT") end
    r.actions = {}
    for k = 1, 3 do
        local a = actionButton(r)
        a:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 52 + (k - 1) * 104, 4)
        a:Hide()
        r.actions[k] = a
    end
    r.line = Th.hline(r, -(UI.ROW_H - 5), 0, 0)
    r:SetScript("OnClick", function(self)
        if not self.entry then return end
        list:Hide()
        N.open(self.entry)
    end)
    if r.EnableMouseWheel then r:EnableMouseWheel(true) end
    r:SetScript("OnMouseWheel", function(_, delta) UI.scroll(delta) end)
    list.rows[i] = r
    return r
end

local function settingsRows()
    local out = {}
    for _, m in ipairs(N.MODULES) do
        -- GF-014-02: a module may bring its own rows (per-character get / set, sub-options indented).
        if type(m.options) == "table" then
            for _, o in ipairs(m.options) do
                out[#out + 1] = { key = m.key .. "." .. o.key, text = o.text, tip = o.tip, get = o.get, set = o.set, sub = o.sub }
            end
        else
            out[#out + 1] = { key = m.key, text = m.text, tip = m.tip }
        end
    end
    out[#out + 1] = { key = "\1chat", text = "聊天框提示", tip = "有新通知時在聊天框留一行（最多每分鐘一次）" }
    return out
end

-- GF-014-04: 14 switches: the rows close up (36 px down to 30) so they stay
-- inside the list (UI.ROWS * UI.ROW_H + 76 high).
UI.SETTING_STEP, UI.SETTING_MIN = 36, 30
function UI.settingStep(n)
    local room = UI.ROWS * UI.ROW_H + 76 + UI.TOP - 16
    return math.max(UI.SETTING_MIN, math.min(UI.SETTING_STEP, math.floor(room / math.max(1, n))))
end

-- GF-014-05: more switches than one column holds at SETTING_MIN: two columns
-- (the second starts at a main row, never between a module and its sub rows).
-- Returns { [i] = { col = 0/1, line = 0.. } }, the step, the column width.
UI.SETTING_COL_W = math.floor((UI.W - 16) / 2)
function UI.settingLayout(rows)
    local n = #rows
    local room = UI.ROWS * UI.ROW_H + 76 + UI.TOP - 16
    local split = n + 1
    if math.floor(room / math.max(1, n)) < UI.SETTING_MIN then
        split = math.floor((n + 1) / 2) + 1
        while split <= n and rows[split].sub do split = split + 1 end
    end
    local out = {}
    for i = 1, n do
        if i < split then out[i] = { col = 0, line = i - 1 } else out[i] = { col = 1, line = i - split } end
    end
    return out, UI.settingStep(math.max(split - 1, n - split + 1)), split <= n and UI.SETTING_COL_W or UI.W
end

function UI.buildSettings(parent, x, y)
    local boxes = {}
    local sync
    local rows = settingsRows()
    local layout, step, colW = UI.settingLayout(rows)
    for i, m in ipairs(rows) do
        local c = Th.checkBox(parent, 28)
        local at = layout[i]
        c:SetPoint("TOPLEFT", parent, "TOPLEFT", (x or 12) + at.col * colW + (m.sub and 28 or 0), (y or UI.TOP) - at.line * step)
        c.col, c.line, c.step = at.col, at.line, step
        c.text = label(parent, m.text, ns.LABEL_FONT)
        c.text:SetPoint("LEFT", c, "RIGHT", 6, 0)
        c.tip = m.tip
        c.key = m.key
        c.get, c.set, c.sub = m.get, m.set, m.sub
        c:SetScript("OnClick", function(self)
            local on = self:GetChecked() and true or false
            if self.set then self.set(on); if sync then sync() end
            elseif self.key == "\1chat" then N.setChat(on) else N.setEnabled(self.key, on) end
        end)
        boxes[#boxes + 1] = c
    end
    sync = function()
        for _, c in ipairs(boxes) do
            if c.get then c.gfOn = c.get()
            elseif c.key == "\1chat" then c.gfOn = N.chatOn() else c.gfOn = N.enabled(c.key) end
            c:SetChecked(c.gfOn)
        end
    end
    sync()
    return boxes, sync
end

local function build()
    local f = CreateFrame("Frame", UI.LIST_NAME, UIParent)
    f:SetSize(UI.W, UI.ROWS * UI.ROW_H + 76)
    f:SetFrameStrata("TOOLTIP") -- above the click-outside blocker
    if f.SetFrameLevel then f:SetFrameLevel(100) end
    Th.panel(f)
    f:EnableMouse(true)
    f.title = label(f, UI.NAME, ns.FIELD_FONT)
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
    f.close = Th.closeButton(f)
    f.readAll = Th.button(f, "全部已讀", ns.labelWidth("全部已讀") + 24, 28)
    f.readAll:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(Th.CLOSE_SIZE + 8), -4)
    f.readAll:SetScript("OnClick", function() N.markAllRead(); UI.draw() end)
    f.setup = Th.button(f, "設定", ns.labelWidth("設定") + 24, 28)
    f.setup:SetPoint("RIGHT", f.readAll, "LEFT", -8, 0)
    f.setup:SetScript("OnClick", function() state.settings = not state.settings; UI.draw() end)
    f.empty = label(f, "", ns.LABEL_FONT)
    f.empty:SetPoint("TOPLEFT", f, "TOPLEFT", 16, UI.TOP - 8)
    f.more = label(f, "", ns.LABEL_FONT)
    f.more:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 10)
    f.rows = {}
    f.bar = ns.Widgets.scrollBar(f, UI.ROWS * UI.ROW_H, function(o) state.offset = o; UI.draw() end)
    f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", 12 + UI.ROW_W + ns.Widgets.SCROLL_GAP, UI.TOP)
    f.settings = CreateFrame("Frame", nil, f)
    f.settings:SetAllPoints(f)
    f.settings.boxes, f.settings.sync = UI.buildSettings(f.settings, 16, UI.TOP)
    f.settings:Hide()
    if f.EnableMouseWheel then f:EnableMouseWheel(true) end
    f:SetScript("OnMouseWheel", function(_, delta) UI.scroll(delta) end)
    f:SetScript("OnHide", function() state.settings = false end)
    f:Hide()
    ns.escRegister(f, ns.ESC_LEVEL.grid)
    list = f
    return f
end

function UI.scroll(delta)
    state.offset = math.max(0, math.min(math.max(0, #state.items - UI.ROWS), state.offset - (delta or 0)))
    UI.draw()
end

function UI.draw()
    UI.updateButton()
    if not (list and list:IsShown()) then return end
    if state.settings then
        for _, r in ipairs(list.rows) do r:Hide() end
        list.empty:SetText("")
        list.more:SetText("")
        list.bar:Hide()
        list.settings:Show()
        list.settings.sync()
        Th.setSelected(list.setup, true)
        W.setEnabled(list.readAll, false)
        return
    end
    list.settings:Hide()
    Th.setSelected(list.setup, false)
    state.items = N.list()
    state.offset = math.max(0, math.min(state.offset, math.max(0, #state.items - UI.ROWS)))
    list.bar:Show()
    list.bar.sync(state.offset, #state.items, UI.ROWS)
    W.setEnabled(list.readAll, N.unread() > 0)
    list.empty:SetText(#state.items == 0 and "目前沒有通知" or "")
    for i = 1, UI.ROWS do
        local e = state.items[state.offset + i]
        local r = row(i)
        if e then
            r.entry = e
            r.tag:SetText(UI.MODULE_SHORT[e.module] or "通知")
            r.text:SetText(e.text)
            local look = UI.rowLook(e.unread == true)
            r.unread = e.unread == true
            r.text:SetTextColor(unpack(look.text))
            r.tag:SetTextColor(unpack(look.tag))
            r.when:SetTextColor(unpack(look.tag))
            if look.mark and r.mark.gfPath then r.mark:Show() else r.mark:Hide() end
            if look.fill then r.unreadFill:Show() else r.unreadFill:Hide() end
            r.when:SetText(UI.ago(e.t))
            local acts = e.actions or {}
            for k, a in ipairs(r.actions) do
                local act = acts[k]
                if act then
                    a.entry, a.key = e, act.key
                    a:SetText(act.text)
                    a:Show()
                else
                    a.entry, a.key = nil, nil
                    a:Hide()
                end
            end
            r:Show()
        else
            r.entry = nil
            r:Hide()
        end
    end
    local rest = #state.items - state.offset - UI.ROWS
    list.more:SetText(rest > 0 and string.format("還有 %d 則（滾輪往下）", rest) or "")
end

function UI.open()
    local f = list or build()
    f:ClearAllPoints()
    if button and button:IsShown() then f:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -4)
    else f:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
    state.offset, state.settings = 0, false
    f:Show()
    UI.draw()
    return f
end

function UI.toggle()
    if list and list:IsShown() then list:Hide(); return nil end
    return UI.open()
end
function UI.list() return list end

N.onChange(function() UI.draw() end)

-- Put the bell on the main window the first time it opens.
local F = ns.Framework
local openWindow = F.open
F.open = function(...)
    local res = openWindow(...)
    if not button then UI.attach() end
    UI.updateButton()
    return res
end
