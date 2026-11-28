-- OrdersUI (GF-006-B, spec §10): the 「訂單」 page, the order popup, the fee
-- popup, the strip next to the trade window, the ⚖ scan button next to the
-- auction house, and the number on the minimap button.
--
-- R-10.1/R-10.2: icons first; no explanation lines, no time stamps; tooltips
-- are a name, a number or a very short line. Technical details are only in
-- 同步與診斷 (Diag.ordersText / Diag.pricesText).

local _, ns = ...
local str = ns.str

local UI = {}
ns.OrdersUI = UI

UI.ICON = {
    waiting = "Interface\\RaidFrame\\ReadyCheck-Waiting",
    making = "Interface\\Icons\\Trade_BlackSmithing",
    checking = "Interface\\Icons\\INV_Crate_01",
    deal = "Interface\\RaidFrame\\ReadyCheck-Ready",
    cancel = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    attention = "Interface\\GossipFrame\\AvailableQuestIcon",
    hammer = "Interface\\Icons\\INV_Hammer_20",
    hammerFallback = "Interface\\Icons\\Trade_BlackSmithing",
    guild = "Interface\\Icons\\INV_Shirt_GuildTabard_01",
    gold = "Interface\\MoneyFrame\\UI-GoldIcon",
    free = "Interface\\Icons\\INV_Misc_Gift_01",
    mail = "Interface\\Icons\\INV_Letter_15",
    back = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up",
    undo = "Interface\\Buttons\\UI-RefreshButton",
    scan = "Interface\\Icons\\INV_Misc_Coin_02",
    history = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    paste = "Interface\\Icons\\INV_Scroll_03",
    bag = "Interface\\Icons\\INV_Misc_Bag_08",
    online = "Interface\\FriendsFrame\\StatusIcon-Online",
    unknown = "Interface\\Icons\\INV_Misc_QuestionMark",
}
-- GF-FIX-B (owner, spec v2.0 §3): 待受理／已接單／待交付／已成交; 已取消 apart
-- from 已成交. Display names only: the state keys (saved, wire) are unchanged.
UI.STATE_NAME = { waiting = "待受理", making = "已接單", checking = "待交付", deal = "已成交", cancel = "已取消" }
UI.BUTTON = {
    accept = { icon = "deal", tip = "接單" }, decline = { icon = "cancel", tip = "不接" },
    cancel = { icon = "cancel", tip = "取消" }, deal = { icon = "deal", tip = "成交" },
    ["return"] = { icon = "back", tip = "退回" }, deliver = { icon = "mail", tip = "已交付" },
    release = { icon = "cancel", tip = "退單" }, close = { icon = "deal", tip = "工匠結案", hammer = true },
    craft = { icon = "making", tip = "製作" }, -- GF-011-B: opens the profession window (Recipes.openCraft)
}
-- Buttons that cancel something wait 5 seconds and can be undone (R-6.7).
UI.DELAYED = { cancel = true, decline = true, release = true }

local function S() return ns.Share end
local function O() return ns.Orders end
local function P() return ns.Prices end
local Icons = ns.Icons

---------------------------------------------------------------------------
-- Pure helpers (offline tests)
---------------------------------------------------------------------------

-- 12345 -> 1[金] 23[銀] 45[銅]: the numbers with the game's coin icons.
-- GF-UI-H (owner: 金額一律用金／銀／銅圖示): always the icons, also where the
-- client has no GetCoinTextureString (the Forever client showed "1g 23s 45c");
-- the icons are plain |T textures (Interface\\MoneyFrame), no client function.
UI.COIN_TEX = { gold = "Interface\\MoneyFrame\\UI-GoldIcon", silver = "Interface\\MoneyFrame\\UI-SilverIcon",
    copper = "Interface\\MoneyFrame\\UI-CopperIcon" }
function UI.money(c, size)
    c = math.floor(tonumber(c) or 0)
    if ns.Theme and ns.Theme.coinText then return ns.Theme.coinText(c, size) end
    local g, s, cu = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local n = tostring(size or 0)
    local out = {}
    local function part(v, tex) out[#out + 1] = v .. "|T" .. tex .. ":" .. n .. ":" .. n .. ":2:0|t" end
    if g > 0 then part(g, UI.COIN_TEX.gold) end
    if s > 0 then part(s, UI.COIN_TEX.silver) end
    if cu > 0 or #out == 0 then part(cu, UI.COIN_TEX.copper) end
    return table.concat(out, " ")
end

-- R-4.4: how a fee shows: "unset" (grey coin + ?), "free" (gift), "amount".
function UI.feeKind(fee)
    if fee == nil then return "unset" end
    if fee == 0 then return "free" end
    return "amount"
end

-- GF-UI-T: true when the estimate has no price at all for what must be bought
-- (every material bought lacks one): then there is nothing to show but words.
function UI.noEstimate(est)
    if not (est and est.unknown) or est.noList then return false end
    if (est.total or 0) > 0 then return false end
    for _, row in ipairs(est.mats or {}) do if row.total then return false end end
    return true
end

-- Text next to the estimate: "≥" when a price is missing (R-8.2.4).
function UI.totalText(est, fee)
    -- GF-UI-T: no price at all: words, never 「＞0 銅」 (with a fee: the fee, then the words).
    if UI.noEstimate(est) then
        if (fee or 0) > 0 then return UI.money(fee) .. "  " .. UI.TEXT.noEstimateFee end
        return UI.TEXT.noEstimate
    end
    local t = (est and est.total or 0) + (fee or 0)
    local s = UI.money(t)
    -- GF-006-D: also while the material list is not known yet (only the fee is in it).
    if est and (est.unknown or est.noList) then s = "＞" .. s end
    return s
end

---------------------------------------------------------------------------
-- Small widgets
---------------------------------------------------------------------------

-- Inline texture for menus and strings (the game fonts have no emoji).
-- GF-UI-B (GF-UI-A §1.3): 18 px by default, never under 16 next to 16 px text.
UI.INLINE = 18
function UI.tex(key, size)
    return "|T" .. (UI.ICON[key] or key) .. ":" .. tostring(math.max(16, size or UI.INLINE)) .. "|t"
end

local function setIcon(tex, key)
    local path = UI.ICON[key] or key
    if Icons.set(tex, path) then tex:Show(); return true end
    if key == "hammer" and Icons.set(tex, UI.ICON.hammerFallback) then tex:Show(); return true end
    tex:Hide()
    return false
end
UI.setIcon = setIcon

local function itemIcon(tex, itemID, skill)
    local icon
    if itemID and type(C_Item) == "table" and type(C_Item.GetItemIconByID) == "function" then
        icon = ns.call(C_Item.GetItemIconByID, itemID)
    end
    if icon and Icons.set(tex, icon) then tex:Show(); return end
    if skill and Icons.setProfessionIcon(tex, { skillLineID = skill }) then return end
    setIcon(tex, "unknown")
end
UI.itemIcon = itemIcon

-- GF-002-D: label = the short name shown right of the icon (owner: icons
-- alone cannot be understood). b.label is that FontString.
local function setLabel(b, text)
    if not text then if b.label then b.label:SetText(""); b.label:Hide() end return end
    if not b.label then
        -- GF-002-E: the normal font, no fixed width, one line (0.12.2 wrapped 「調/整」).
        -- GF-002-G: the name belongs to the button itself, so it hides with it even
        -- when the page was never shown (0.12.4 left 「邀請下一位」 on the page).
        b.label = ns.freeText(b:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
        b.label:SetPoint("LEFT", b, "RIGHT", 4, 0)
        b.label:SetJustifyH("LEFT")
    end
    b.label:SetText(text)
    b.label:Show()
end
UI.setLabel = setLabel

-- Width of an icon button with its name (for laying buttons out in a row).
function UI.buttonSpan(b)
    local w = b.gfWidth or ns.num((b:GetWidth())) or 0
    if b.label and b.label:IsShown() and str(b.label:GetText()) ~= "" then w = w + 4 + ns.measure(b.label) end
    return w
end
-- Put buttons one after another from x (TOPLEFT of parent, or LEFT of a row), gap px apart.
function UI.flow(parent, list, x, y, gap, point)
    for _, b in ipairs(list) do
        b:ClearAllPoints()
        if point == "LEFT" then b:SetPoint("LEFT", parent, "LEFT", x, y or 0)
        else b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y) end
        b.flowX = x
        x = x + UI.buttonSpan(b) + (gap or 14)
    end
    return x
end

local function iconButton(parent, size, key, tip, onClick, label)
    local b = CreateFrame("Button", nil, parent)
    b.labelParent = parent
    b:SetSize(size, size)
    b.gfWidth = size
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    setIcon(b.tex, key)
    b.badge = b:CreateTexture(nil, "OVERLAY")
    b.badge:SetSize(math.floor(size / 2), math.floor(size / 2))
    b.badge:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
    b.badge:Hide()
    -- GF-002-G (owner: 「選取的圖標，請要用有質感的發亮，不是很俗氣全黃而已」):
    -- chosen = the action bar's glow ring (ADD blend) and a soft inner shine;
    -- not chosen = a little darker, still clear (UI.setSelected).
    b.sel = b:CreateTexture(nil, "OVERLAY")
    b.sel:SetSize(math.floor(size * 1.75), math.floor(size * 1.75))
    b.sel:SetPoint("CENTER", b, "CENTER", 0, 0)
    if not Icons.set(b.sel, UI.GLOW) then b.sel:SetColorTexture(1, 0.85, 0.4, 0.35) end
    if b.sel.SetBlendMode then b.sel:SetBlendMode("ADD") end
    if b.sel.SetVertexColor then b.sel:SetVertexColor(1, 0.85, 0.45) end
    b.sel:Hide()
    b.shine = b:CreateTexture(nil, "OVERLAY")
    b.shine:SetAllPoints()
    if Icons.set(b.shine, UI.SHINE) then
        if b.shine.SetBlendMode then b.shine:SetBlendMode("ADD") end
        b.shine:SetAlpha(0.45)
    end
    b.shine:Hide()
    -- GF-UI-D2: the hover square is the button's own HIGHLIGHT-layer texture, so the
    -- theme can keep it dark when the icon cannot be pressed (Theme.guardHover).
    b.gfHover = b:CreateTexture(nil, "HIGHLIGHT")
    b.gfHover:SetAllPoints(b)
    Icons.set(b.gfHover, "Interface\\Buttons\\ButtonHilight-Square")
    if b.gfHover.SetBlendMode then b.gfHover:SetBlendMode("ADD") end
    if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    b.tip = tip
    b:SetScript("OnEnter", function(self)
        if not self.tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(self.tip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if onClick then b:SetScript("OnClick", onClick) end
    -- GF-UI-D2: lights up only when it can be pressed (no light on a state or an item icon).
    ns.Theme.guardHover(b)
    if label then setLabel(b, label) end
    b:HookScript("OnShow", function(self) if self.label and self.label:GetText() ~= "" then self.label:Show() end end)
    b:HookScript("OnHide", function(self) if self.label then self.label:Hide() end end)
    return b
end
UI.iconButton = iconButton

UI.GLOW = "Interface\\Buttons\\UI-ActionButton-Border"
UI.SHINE = "Interface\\Buttons\\CheckButtonHilight"
UI.DIM = 0.62 -- not chosen: the icon a little darker, never grey
function UI.setSelected(b, on)
    b.selected = on and true or false
    if on then b.sel:Show(); b.shine:Show() else b.sel:Hide(); b.shine:Hide() end
    if b.tex.SetDesaturated then b.tex:SetDesaturated(false) end
    local c = on and 1 or UI.DIM
    if b.tex.SetVertexColor then b.tex:SetVertexColor(c, c, c) end
    b.tex:SetAlpha(1)
    b.dimmed = not on
    if b.label then
        b.label:SetAlpha(1)
        if on then b.label:SetTextColor(1, 0.95, 0.75) else b.label:SetTextColor(0.72, 0.72, 0.72) end
    end
end

-- GF-UI-C (owner: icons on the red buttons too big, with a black square):
-- an icon inside a text button is at most the button's height - 8 px, and a
-- square spell / item icon (Interface\Icons) has its dark border cropped
-- (texture coordinates 0.08 - 0.92). Applied to every text a text button
-- gets, also later ones (SetText).
UI.BUTTON_ICON_MAX = ns.BUTTON_H - 8
local CROP = { 5, 59 } -- of 64: 0.08 - 0.92
function UI.buttonText(text)
    return (tostring(text or ""):gsub("|T([^:|]+):?([^|]*)|t", function(path, rest)
        local n = tonumber(rest:match("^(%d+)")) or UI.BUTTON_ICON_MAX
        n = math.min(n, UI.BUTTON_ICON_MAX)
        if path:lower():find("^interface\\icons\\") then
            return string.format("|T%s:%d:%d:0:0:64:64:%d:%d:%d:%d|t", path, n, n, CROP[1], CROP[2], CROP[1], CROP[2])
        end
        local box = rest:match("^%d+:%d+:%-?%d+:%-?%d+:(%d+:%d+:%d+:%d+:%d+:%d+)$")
        if box then return string.format("|T%s:%d:%d:0:0:%s|t", path, n, n, box) end
        return string.format("|T%s:%d|t", path, n)
    end))
end

-- GF-002-E: a text button as wide as its text (an icon markup counts as one).
-- GF-UI-D: the theme's outlined button (no red UIPanelButton).
function UI.textButton(parent, text, onClick, minWidth, exactWidth)
    local w = exactWidth or math.max(minWidth or 0, ns.labelWidth(text) + 28)
    local b = ns.Theme.button(parent, nil, w, ns.BUTTON_H)
    b.gfWidth, b.gfHeight = w, ns.BUTTON_H
    local set = b.SetText
    b.SetText = function(self, t) return set(self, UI.buttonText(t)) end
    b:SetText(text)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

local function itemTooltip(owner, itemID)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local shown = false
    if itemID and type(GameTooltip.SetItemByID) == "function" then
        shown = pcall(GameTooltip.SetItemByID, GameTooltip, itemID)
    end
    if not shown then GameTooltip:AddLine("#" .. tostring(itemID or "?")) end
    GameTooltip:Show()
end

-- GF-006-D: the count on a material icon of an order row (the customer brings
-- part of it), in the game's item-count font at the bottom right; nil hides it.
function UI.matCount(b, text)
    if not b.countText then
        if not text then return end
        b.countText = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        b.countText:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    end
    b.countText:SetText(text or "")
    if text then b.countText:Show() else b.countText:Hide() end
end

-- GF-006-D: a material icon on an order row: the item, then who brings how many.
function UI.matTip(b)
    if ns.Widgets.rowTip then ns.Widgets.rowTip(b) else GameTooltip:SetOwner(b, "ANCHOR_RIGHT") end
    local shown = b.itemID and type(GameTooltip.SetItemByID) == "function" and pcall(GameTooltip.SetItemByID, GameTooltip, b.itemID)
    if not shown then GameTooltip:AddLine("#" .. tostring(b.itemID or "?")) end
    local need, own = b.need or 0, b.own or 0
    local line
    if own >= need and need > 0 then line = "下單人全部自帶（" .. need .. " 個）"
    elseif own > 0 then line = "下單人自帶 " .. own .. " 個，工匠準備 " .. (need - own) .. " 個（共需 " .. need .. " 個）"
    else line = "工匠準備（共需 " .. need .. " 個）" end
    GameTooltip:AddLine(line, 1, 0.82, 0, true)
    GameTooltip:AddLine("打勾＝下單人全部自帶；角落數字＝下單人自帶的個數；沒有記號＝工匠準備", 0.85, 0.85, 0.85, true)
    GameTooltip:Show()
    b.matLine = line
end

local function memberOf(a) return a and S().memberFor(a) or nil end
local function shortOf(a)
    local m = memberOf(a)
    return m and ns.shortName(m.name) or "?"
end

-- Coin icon for a fee: amount, free or not filled in (grey + "?").
local function showFee(tex, label, fee)
    local kind = UI.feeKind(fee)
    if kind == "free" then
        setIcon(tex, "free"); if tex.SetDesaturated then tex:SetDesaturated(false) end
        label:SetText("")
    elseif kind == "unset" then
        setIcon(tex, "gold"); if tex.SetDesaturated then tex:SetDesaturated(true) end
        label:SetText("?")
    else
        tex:Hide()
        label:SetText(UI.money(fee))
    end
    return kind
end
UI.showFee = showFee

---------------------------------------------------------------------------
-- The orders page
---------------------------------------------------------------------------

local ROW_HEIGHT = ns.PAGE_ROW -- GF-002-F: 36
UI.ROW_WIDTH = 1030 -- GF-002-E: the wider window
local panel, scroll, content, profBar
local rowWidgets, shownRows, profButtons = {}, {}, {}
local pendingPress = {} -- [id .. button] = true while a delayed press can be undone

function UI.ownCraftSkills()
    local a = S().selfAuthor()
    local list = {}
    local profs = a and S().decoded(a, "P") or nil
    for _, p in ipairs(type(profs) == "table" and profs or {}) do
        local id = ns.num(p.skillLineID)
        if id and ns.Recipes.CRAFTS[id] then list[#list + 1] = id end
    end
    return list
end

-- The list the page draws: header rows and order rows (R-10.3: only rows in view get frames).
function UI.pageRows()
    local me = S().selfAuthor()
    if not me then return {} end
    local received, placed = O().rowsFor(me, ns.Data.player().guid)
    local out = {}
    if #received > 0 then
        out[#out + 1] = { header = ns.GameIcons.markup("received", 16) .. " 收到的", count = #received } -- GF-002-C
        for _, r in ipairs(received) do out[#out + 1] = r end
    end
    if #placed > 0 then
        out[#out + 1] = { header = ns.GameIcons.markup("placed", 16) .. " 我下的", count = #placed }
        for _, r in ipairs(placed) do out[#out + 1] = r end
    end
    return out
end

-- GF-UI-B (GF-UI-A §2.9 item 3): the clock the undo swirl runs on.
local function clock() return ns.num((ns.call(GetTime))) or ns.now() end
UI.clock = clock

local function press(row, button)
    local v = row.view
    local key = v.id .. "|" .. button
    if UI.DELAYED[button] then
        if pendingPress[key] then pendingPress[key] = nil; UI.refresh(); return "undone" end
        pendingPress[key] = clock() -- when it started (the swirl on the button)
        UI.refresh()
        ns.after(O().UNDO, function()
            if not pendingPress[key] then return end
            pendingPress[key] = nil
            O().press(v, button)
            UI.refresh()
        end)
        return "delayed"
    end
    local ok = O().press(v, button)
    UI.refresh()
    return ok and "done" or "failed"
end
UI.press = press
UI.pendingPress = pendingPress

local function newRow(i)
    local row = CreateFrame("Frame", nil, content)
    row:SetSize(UI.ROW_WIDTH, ROW_HEIGHT)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.att = row:CreateTexture(nil, "ARTWORK"); row.att:SetSize(20, 20); row.att:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.item = iconButton(row, 32, "unknown", nil)
    row.item:SetPoint("LEFT", row, "LEFT", 24, 0)
    row.item:SetScript("OnEnter", function(self) itemTooltip(self, self:GetParent().view and self:GetParent().view.item) end)
    ns.Theme.infoOnly(row.item) -- GF-002-D: shows the item on hover, nothing to click; GF-UI-D2: no light
    row.qty = row:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)
    row.qty:SetPoint("LEFT", row, "LEFT", 62, 0); row.qty:SetWidth(84); row.qty:SetJustifyH("LEFT"); row.qty:SetWordWrap(false)
    row.cls = row:CreateTexture(nil, "ARTWORK"); row.cls:SetSize(22, 22); row.cls:SetPoint("LEFT", row, "LEFT", 150, 0)
    row.who = row:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)
    row.who:SetPoint("LEFT", row, "LEFT", 176, 0); row.who:SetWidth(130); row.who:SetJustifyH("LEFT"); row.who:SetWordWrap(false)
    -- GF-UI-B (GF-UI-A §2.9 item 2): materials 28 px, the coin 20 px.
    row.mats = {}
    for k = 1, 5 do
        local m = iconButton(row, ns.ROW_ICON, "unknown", nil)
        m:SetPoint("LEFT", row, "LEFT", 312 + (k - 1) * 30, 0)
        m:SetScript("OnEnter", function(self) UI.matTip(self) end)
        ns.Theme.infoOnly(m)
        row.mats[k] = m
    end
    row.coin = row:CreateTexture(nil, "ARTWORK"); row.coin:SetSize(20, 20); row.coin:SetPoint("LEFT", row, "LEFT", 466, 0)
    row.fee = row:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)
    row.fee:SetPoint("LEFT", row, "LEFT", 490, 0); row.fee:SetWidth(108); row.fee:SetJustifyH("LEFT"); row.fee:SetWordWrap(false)
    row.state = iconButton(row, ns.ROW_ICON, "waiting", nil)
    ns.Theme.infoOnly(row.state) -- GF-UI-D2: the state (取消, 成交...) only shows a tooltip: no light
    row.state:SetPoint("LEFT", row, "LEFT", 604, 0)
    row.buttons = {}
    -- GF-002-E: the buttons follow each other by their measured names.
    UI.ROW_BUTTON_X = 700
    for k = 1, 3 do
        local b = iconButton(row, ns.ROW_ICON, "deal", nil)
        b:SetPoint("LEFT", row, "LEFT", UI.ROW_BUTTON_X, 0)
        -- GF-UI-B: the action bar's cooldown swirl while a press can be undone (5 s).
        b.cd = ns.createFrame("Cooldown", nil, b, "CooldownFrameTemplate")
        b.cd:SetAllPoints(b)
        if b.cd.SetReverse then pcall(b.cd.SetReverse, b.cd, false) end
        b.cd:Hide()
        -- GF-FIX-C (review mid-9): one handler per button, made here; it reads the
        -- button's action when clicked (no new closure on every fill or scroll).
        b.pressClick = function(self) if self.action and self.action ~= "craft" then press(row, self.action) end end
        row.buttons[k] = b
    end
    row.head = row:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT)
    row.head:SetPoint("LEFT", row, "LEFT", 6, 0)
    -- GF-016: the row 我的業務 opened (UI.focus), lit with the quest log's highlight.
    row.focusMark = row:CreateTexture(nil, "BORDER")
    row.focusMark:SetAllPoints()
    -- GF-FIX-C (review mid-25): two backslashes (one was eaten by Lua: the mark never showed).
    Icons.set(row.focusMark, "Interface\\QuestFrame\\UI-QuestTitleHighlight")
    if row.focusMark.SetBlendMode then row.focusMark:SetBlendMode("ADD") end
    row.focusMark:Hide()
    rowWidgets[i] = row
    return row
end

-- The swirl on a row button: started at `at` (UI.clock), O().UNDO seconds long.
function UI.setSwirl(b, at)
    local cd = b.cd
    if not cd then return end
    if at and type(cd.SetCooldown) == "function" then
        cd:Show()
        pcall(cd.SetCooldown, cd, at, O().UNDO)
        cd.gfStart, cd.gfDuration = at, O().UNDO
    else
        cd.gfStart, cd.gfDuration = nil, nil
        cd:Hide()
    end
end

local function fillRow(row, data, i)
    ns.stripe(row.bg, i) -- GF-UI-B: the shared stripe
    local parts = { row.att, row.item, row.qty, row.cls, row.who, row.coin, row.fee, row.state }
    if data.header then
        for _, w in ipairs(parts) do w:Hide() end
        for _, m in ipairs(row.mats) do m:Hide() end
        for _, b in ipairs(row.buttons) do b:Hide() end
        row.head:SetText(data.header)
        row.head:Show()
        row.view = nil
        return
    end
    row.head:Hide()
    for _, w in ipairs(parts) do w:Show() end
    local v = data.view
    row.view = v
    local me = S().selfAuthor()
    if data.attention then setIcon(row.att, "attention") else row.att:Hide() end
    itemIcon(row.item.tex, v.item, v.skill)
    local qty = "x" .. v.qty
    if v.progress > 0 and v.progress < v.qty then qty = qty .. "  " .. v.progress .. "/" .. v.qty end
    row.qty:SetText(qty)
    -- The other side: the customer (for my jobs) or the crafter (for my orders).
    local other = v.customer == me and v.crafter or v.customer
    if v.test then
        -- GF-UI-B: a test order (to myself, local only): the test icon and 測試.
        if not ns.GameIcons.set(row.cls, "test") then row.cls:Hide() end
        row.who:SetText("測試")
        ns.setTextColor(row.who, "warn")
    elseif v.customer == me and v.guild and not v.crafter then
        setIcon(row.cls, "guild")
        row.who:SetText("公會")
        row.who:SetTextColor(0.9, 0.9, 0.9)
    else
        local m = memberOf(other)
        if m and Icons.setClassIcon(row.cls, m.classToken) then row.cls:Show() else row.cls:Hide() end
        row.who:SetText(m and ns.shortName(m.name) or "?")
        local c = Icons.classColor(m and m.classToken)
        row.who:SetTextColor(c[1], c[2], c[3])
        if m and m.online then row.who:SetText(row.who:GetText() .. " " .. UI.tex("online", 16)) end
    end
    -- Materials the customer gives (ticked) and the ones the crafter gives.
    local r = v.recipe and P().cachedReagents(v.recipe)
    local k = 0
    local crafts = r and math.ceil(v.qty / math.max(1, r.yield or 1)) or 1
    for _, x in ipairs(r and r.list or {}) do
        k = k + 1
        local m = row.mats[k]
        if not m then break end
        itemIcon(m.tex, x.id)
        m.itemID = x.id
        -- GF-006-D: ✓ = the customer brings all of it; a number = brings that many
        -- (part of it); nothing = the crafter provides it. Old orders wrote the
        -- whole need, so they still show ✓.
        local need, own = x.n * crafts, v.mats[x.id] or 0
        m.need, m.own = need, own
        if own >= need then setIcon(m.badge, "deal") else m.badge:Hide() end
        UI.matCount(m, own > 0 and own < need and tostring(own) or nil)
        m:Show()
    end
    for j = k + 1, #row.mats do row.mats[j]:Hide() end
    -- Review 5-3: the fee the customer wrote; at 0 the quote only says free / not filled in.
    showFee(row.coin, row.fee, v.fee > 0 and v.fee or (v.feeQuoted == nil and nil or 0))
    if v.paid then row.fee:SetText(row.fee:GetText() .. " " .. UI.tex("deal", 16)) end
    -- State icon; a crafter's close carries a small hammer, a cancel the canceller's class.
    setIcon(row.state.tex, v.state)
    row.state.badge:Hide()
    if v.state == "deal" and v.closedBy == "crafter" then setIcon(row.state.badge, "hammer") end
    if v.state == "cancel" then
        local who = v.closedBy == "crafter" and v.crafter or v.customer
        local m = memberOf(who)
        if m and Icons.setClassIcon(row.state.badge, m.classToken) then row.state.badge:Show() end
    end
    if v.uncertain and v.state == "checking" then setIcon(row.state.badge, "unknown") end
    local red = data.attention and data.attention.red
    if row.state.tex.SetVertexColor then
        if red then row.state.tex:SetVertexColor(1, 0.3, 0.3) else row.state.tex:SetVertexColor(1, 1, 1) end
    end
    local days = math.floor((S().serverNow() - (v.since or 0)) / 86400)
    row.state.tip = UI.STATE_NAME[v.state] .. (days >= 1 and ("  " .. days .. " 天") or "")
    setLabel(row.state, UI.STATE_NAME[v.state]) -- GF-002-D
    -- Buttons this viewer may press (R-6.2).
    local list = O().buttons(v, me)
    if UI.showsCraft(v, me) and #list < #row.buttons then list[#list + 1] = "craft" end
    for j, b in ipairs(row.buttons) do
        local name = list[j]
        if b.tex.SetTexCoord then b.tex:SetTexCoord(0, 1, 0, 1) end
        if b.tex.SetDesaturated then b.tex:SetDesaturated(false) end
        if b.SetEnabled then b:SetEnabled(true) end
        if b.label and b.label.SetFontObject then b.label:SetFontObject(ns.LABEL_FONT) end
        if name == "craft" then
            UI.fillCraftButton(b, v)
        elseif name then
            local spec = UI.BUTTON[name]
            local key = v.id .. "|" .. name
            if pendingPress[key] then setIcon(b.tex, "undo"); b.tip = "復原"
            else setIcon(b.tex, spec.icon); b.tip = spec.tip end
            UI.setSwirl(b, pendingPress[key] and (type(pendingPress[key]) == "number" and pendingPress[key] or clock()) or nil)
            setLabel(b, b.tip)
            if spec.hammer then setIcon(b.badge, "hammer") else b.badge:Hide() end
            if b.onClick ~= b.pressClick then b:SetScript("OnClick", b.pressClick); b.onClick = b.pressClick end
            b.action = name
            b:Show()
        else
            b:Hide(); b.action = nil
            UI.setSwirl(b, nil)
        end
    end
    local shown = {}
    for _, b in ipairs(row.buttons) do if b:IsShown() then shown[#shown + 1] = b end end
    UI.flow(row, shown, UI.ROW_BUTTON_X, 0, 16, "LEFT")
end

-- GF-011-B 「製作」: on an order I accepted (製作中, I am the crafter; a test
-- order to myself too). Opens my profession window, the recipe selected
-- when the client can; nothing is crafted for the player.
function UI.showsCraft(v, me)
    return v.state == "making" and v.skill ~= nil and (v.crafter == me or v.test == true)
end
local function craftClick(self)
    local v = self.craftView
    if not v then return end
    self.lastCraft = ns.Recipes.openCraft(v.skill, v.recipe)
end
function UI.fillCraftButton(b, v)
    local R = ns.Recipes
    local can, why = R.canCraft(v.skill)
    if not Icons.setProfessionIcon(b.tex, { skillLineID = v.skill }) then setIcon(b.tex, "making") end
    if b.tex.SetDesaturated then b.tex:SetDesaturated(not can) end
    b.tip = can and R.CRAFT_LABEL or (R.CRAFT_LABEL .. "：" .. (R.CRAFT_TIP[why] or ""))
    UI.setSwirl(b, nil)
    setLabel(b, R.CRAFT_LABEL)
    if b.label and b.label.SetFontObject then b.label:SetFontObject(can and ns.LABEL_FONT or ns.DISABLED_FONT) end
    b.badge:Hide()
    b.craftView = v
    if b.onClick ~= craftClick then b:SetScript("OnClick", craftClick); b.onClick = craftClick end
    if b.SetEnabled then b:SetEnabled(can) end
    b.action = "craft"
    b:Show()
end

-- GF-FIX-C (review mid-9): scrolling within the same rows redraws nothing
-- (rows sit at fixed places on the scroll child); refresh() and focus redraw all.
local laid = {}
function UI.layoutRows(onlyIfMoved)
    if not scroll then return end
    local offset = ns.num((scroll:GetVerticalScroll())) or 0
    local h = ns.num((scroll:GetHeight())) or 0
    if h <= 0 then h = 420 end
    local count = math.ceil(h / ROW_HEIGHT) + 1
    local first = math.max(1, math.floor(offset / ROW_HEIGHT) + 1)
    if onlyIfMoved and laid.first == first and laid.count == count and laid.rows == shownRows then return false end
    laid.first, laid.count, laid.rows = first, count, shownRows
    for k = 1, math.max(count, #rowWidgets) do
        local i = first + k - 1
        local data = k <= count and shownRows[i] or nil
        local row = rowWidgets[k] or (data and newRow(k)) or nil
        if row then
            if data then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
                fillRow(row, data, i)
                if data.view and UI.focusId ~= nil and data.view.id == UI.focusId then row.focusMark:Show() else row.focusMark:Hide() end
                row:Show()
            else
                row:Hide(); row.view = nil
            end
        end
    end
end
function UI.rowFrames() return rowWidgets end
function UI.shownRows() return shownRows end
function UI.scrollFrame() return scroll end

---------------------------------------------------------------------------
-- GF-016 (GPT review): 我的業務 opens the order itself. locate(id) says
-- whether this page lists it (pure: no frames needed); focus(id) scrolls to
-- it and lights it. A missing id changes nothing and returns false, "missing".
---------------------------------------------------------------------------

UI.focusId = nil
function UI.locate(id)
    if id == nil then return false end
    for _, r in ipairs(UI.pageRows()) do if r.view and r.view.id == id then return true end end
    return false
end

-- Scroll so row i (1-based) sits in view, about in the middle.
function UI.scrollToRow(i)
    if not (scroll and i) then return end
    local h = ns.num((scroll:GetHeight())) or 0
    if h <= 0 then h = 420 end
    local total = #shownRows * ROW_HEIGHT
    local y = (i - 1) * ROW_HEIGHT - math.floor((h - ROW_HEIGHT) / 2)
    y = math.max(0, math.min(y, math.max(0, total - h)))
    scroll:SetVerticalScroll(y)
    UI.layoutRows()
end

function UI.focus(id)
    if not UI.locate(id) then
        UI.focusId = nil
        if panel then UI.layoutRows() end
        return false, "missing"
    end
    UI.focusId = id
    if not panel then return true end
    UI.refresh()
    for i, r in ipairs(shownRows) do
        if r.view and r.view.id == id then UI.scrollToRow(i); return true end
    end
    return true
end

-- GF-UI-C (owner: 「不接 / 工錢 / ?」 ran into each other): every profession
-- is one group [icon] 接單/不接 [工錢] coin amount; groups sit in even columns
-- as wide as the widest group (measured), so a long amount never reaches the
-- next profession. The label column is as wide as the longer of 接單 / 不接.
UI.PROF_GAP = 24
function UI.profGroupWidth(b)
    local labelW = math.max(ns.labelWidth("接單"), ns.labelWidth("不接"))
    local feeX = ns.ICON + 4 + labelW + 8
    local textX = feeX + b.feeButton.gfWidth + (b.feeTex:IsShown() and 26 or 6)
    return textX + ns.measure(b.feeText), feeX, textX
end
local function refreshProfBar()
    if not profBar then return end
    local skills = UI.ownCraftSkills()
    local sv = O().services(S().selfAuthor())
    for i, skill in ipairs(skills) do
        local b = profButtons[i]
        if not b then
            -- GF-002-D: [icon] 接單／不接   [工錢] coin — a click on the icon toggles, on 工錢 edits.
            b = iconButton(profBar, ns.ICON, "unknown", nil, nil, "不接")
            b.feeButton = UI.textButton(profBar, "工錢")
            b.feeTex = profBar:CreateTexture(nil, "ARTWORK"); b.feeTex:SetSize(20, 20)
            b.feeText = ns.freeText(profBar:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
            b.feeText:SetJustifyH("LEFT")
            profButtons[i] = b
        end
        Icons.setProfessionIcon(b.tex, { skillLineID = skill })
        local on = sv.active[skill] == true
        if on then setIcon(b.badge, "hammer") else b.badge:Hide() end
        if b.tex.SetDesaturated then b.tex:SetDesaturated(not on) end
        b.skill = skill
        b.tip = (ns.Data.skillName(nil, skill) or "") .. (on and "  接單中" or "  不接單")
        setLabel(b, on and "接單" or "不接")
        if b.label.SetTextColor then if on then b.label:SetTextColor(1, 0.82, 0) else b.label:SetTextColor(0.6, 0.6, 0.6) end end
        showFee(b.feeTex, b.feeText, sv.fees[skill])
        if UI.feeKind(sv.fees[skill]) == "free" then b.feeText:SetText("免費") end
        b.feeButton.skill = skill
        b.feeButton:SetScript("OnClick", function(self) UI.editFee({ skill = self.skill }) end)
        b.feeButton:Show()
        b:SetScript("OnClick", function(self, mouse)
            if mouse == "RightButton" then UI.editFee({ skill = self.skill })
            else O().setActive(self.skill, not O().isActive(ns.Data.player().guid, self.skill)); UI.refresh() end
        end)
        b:Show()
    end
    for i = #skills + 1, #profButtons do
        profButtons[i]:Hide(); profButtons[i].feeButton:Hide(); profButtons[i].feeTex:Hide(); profButtons[i].feeText:SetText("")
    end
    -- Place the groups: one column width for all (the widest group + a gap).
    local step = 0
    for i = 1, #skills do step = math.max(step, (UI.profGroupWidth(profButtons[i]))) end
    step = step + UI.PROF_GAP
    UI.profStep = step
    for i = 1, #skills do
        local b = profButtons[i]
        local _, feeX, textX = UI.profGroupWidth(b)
        local x = UI.PROF_X + (i - 1) * step
        b:ClearAllPoints(); b:SetPoint("LEFT", profBar, "LEFT", x, 0)
        b.feeButton:ClearAllPoints(); b.feeButton:SetPoint("LEFT", profBar, "LEFT", x + feeX, 0)
        b.feeTex:ClearAllPoints(); b.feeTex:SetPoint("LEFT", profBar, "LEFT", x + feeX + b.feeButton.gfWidth + 4, 0)
        b.feeText:ClearAllPoints(); b.feeText:SetPoint("LEFT", profBar, "LEFT", x + textX, 0)
        b.groupX, b.groupW = x, (UI.profGroupWidth(b))
    end
    if UI.profField then if #skills > 0 then UI.profField:Show() else UI.profField:Hide() end end
end
UI.profButtons = function() return profButtons end
UI.PROF_X = 60

function UI.refresh()
    if not panel then UI.updateBadge(); return end
    refreshProfBar()
    shownRows = UI.pageRows()
    -- GF-FIX-C (review low-26): the badge counts the rows just made (one rowsFor, not two).
    local n = 0
    for _, r in ipairs(shownRows) do if r.attention then n = n + 1 end end
    UI.updateBadge(n)
    content:SetHeight(math.max(1, #shownRows * ROW_HEIGHT))
    UI.layoutRows()
    UI.emptyLine:SetText(#shownRows == 0 and "沒有委託" or "") -- GF-002-D; GF-UI-K: 訂單 = 委託
    if UI.servicesPopup and UI.servicesPopup:IsShown() then UI.drawServices() end
end

local function build(p)
    -- GF-002-E (owner: 「我看不出來如何下單」「工匠設定要按右鍵不明顯」): two plain buttons on top.
    -- GF-UI-C (item 12): text buttons say it in words; no icon.
    UI.orderButton = UI.textButton(p, "＋下單", function(self) UI.startOrder() end)
    UI.orderButton:SetPoint("TOPLEFT", p, "TOPLEFT", 24, -40)
    UI.servicesButton = UI.textButton(p, "我的服務", function() UI.openServices() end)
    UI.servicesButton:SetPoint("LEFT", UI.orderButton, "RIGHT", 12, 0)
    profBar = CreateFrame("Frame", nil, p)
    profBar:SetSize(1040, 40)
    profBar:SetPoint("TOPLEFT", p, "TOPLEFT", 24, -80)
    UI.profField = ns.freeText(profBar:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT))
    UI.profField:SetPoint("LEFT", profBar, "LEFT", 0, 0)
    UI.profField:SetText("專業")
    UI.emptyLine = p:CreateFontString(nil, "ARTWORK", ns.DISABLED_FONT)
    UI.emptyLine:SetPoint("TOP", p, "TOP", 0, -200)
    scroll = ns.createFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -128)
    scroll:SetPoint("BOTTOMRIGHT", -40, 52)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(UI.ROW_WIDTH, 1)
    scroll:SetScrollChild(content)
    scroll:HookScript("OnVerticalScroll", function() UI.layoutRows(true) end)
    UI.historyButton = iconButton(p, ns.ICON, "history", "歷史", function() UI.showHistory() end, "歷史")
    UI.historyButton:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -250, 10)
    -- GF-006-C (R-9.4): paste a web order's import code.
    UI.pasteButton = iconButton(p, ns.ICON, "paste", "匯入碼", function() UI.openPaste() end, "匯入")
    UI.pasteButton:SetPoint("RIGHT", UI.historyButton, "LEFT", -(ns.labelWidth("匯入") + 28), 0)
    panel = p
end

ns.Framework.register({
    id = "orders",
    title = "訂單",
    order = 13,
    available = function() return ns.guildState() == "target" end,
    create = build,
    show = function() UI.focusId = nil; O().markSeen(); UI.refresh() end,
    -- GF-014 / GF-016: 業務通知 opens this page, then focus(id) finds the row.
    focus = function(id) return UI.focus(id) end,
})

---------------------------------------------------------------------------
-- Import code (GF-006-C, R-9.4): the same string as the Inbox, pasted.
---------------------------------------------------------------------------

UI.PASTE_NAME = "GreenFangToolkit_PastePopup"
local pastePopup

function UI.openPaste()
    if not pastePopup then
        local f = ns.popupWindow(UI.PASTE_NAME, 620, 230)
        f:SetPoint("CENTER", 0, 80)
        f:EnableMouse(true)
        ns.exclusivePopup(f)
        if f.TitleText then f.TitleText:SetText("匯入") end
        UI.fieldLabel(f, "匯入碼", UI.FIELD_X, -50)
        local X = UI.controlX({ "匯入碼" })
        f.icon = f:CreateTexture(nil, "ARTWORK"); f.icon:SetSize(ns.ICON, ns.ICON)
        f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", X, -42)
        Icons.set(f.icon, UI.ICON.paste)
        local box = ns.Theme.editBox(f)
        box:SetSize(400, 30)
        box:SetPoint("TOPLEFT", f, "TOPLEFT", X + 44, -44)
        box:SetAutoFocus(true)
        if box.SetMaxLetters then box:SetMaxLetters(0) end
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
        box:SetScript("OnEnterPressed", function() UI.pasteImport() end)
        f.box = box
        f.result = ns.freeText(f:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge"))
        f.result:SetPoint("TOPLEFT", f, "TOPLEFT", X, -96)
        f.go = UI.textButton(f, "匯入", function() UI.pasteImport() end, 110)
        f.go:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
        f:Hide()
        pastePopup = f
    end
    pastePopup.box:SetText("")
    pastePopup.result:SetText("")
    pastePopup:Show()
    return pastePopup
end

-- Result as icons and numbers only (R-10.2): ✓ imported, ✗ skipped.
function UI.pasteImport(text)
    local f = pastePopup
    text = text or (f and f.box:GetText()) or ""
    local res = ns.WebOrders.import(text, "paste")
    local skipped = 0
    for _, n in pairs(res.skipped or {}) do skipped = skipped + n end
    if f then
        if res.ok then
            f.result:SetText(UI.tex("deal", 16) .. " " .. ((res.imported or 0) + (res.same or 0))
                .. (skipped > 0 and ("   " .. UI.tex("cancel", 16) .. " " .. skipped) or ""))
        else
            f.result:SetText(UI.tex("cancel", 16))
        end
    end
    UI.refresh()
    return res
end

---------------------------------------------------------------------------
-- History (R-6.10): closed orders, newest first; right-click = order again.
---------------------------------------------------------------------------

function UI.showHistory()
    local key = ns.Data.player().guid or "?"
    local list = O().local_().history[key] or {}
    local items = {}
    for i = 1, math.min(#list, 15) do
        local h = list[i]
        local name = (h.recipe and ns.Recipes.name(h.recipe)) or ("#" .. tostring(h.item or "?"))
        local mark = UI.tex(h.close == "deal" and "deal" or "cancel") .. " "
        items[#items + 1] = { text = mark .. name .. " x" .. tostring(h.qty or 1), fn = function()
            if h.recipe then UI.openOrder({ recipe = h.recipe, skill = h.skill }) end
        end }
    end
    if #items == 0 then return nil end
    return ns.showMenu(UI.historyButton, items)
end

---------------------------------------------------------------------------
-- The order popup (R-5.2)
---------------------------------------------------------------------------

UI.POPUP_NAME = "GreenFangToolkit_OrderPopup"
local popup
-- draft = { recipe, skill, item, qty, crafter (author or "*"), crafters, reagents,
--   mats = { [itemID] = true (I bring all) | count (GF-006-D: I bring that many) },
--   fee, feeQuoted, feeEdited }
local draft

---------------------------------------------------------------------------
-- GF-006-D (owner, 0.16.19: 「每種材料應該是要可以設定 是否自帶多少數量」
-- 「目前的圖示看不出作用，應該要有滑鼠放上的輔助說明」「材料費的計算與行情
-- 功能看起來有問題」): the order form has one row per material (icon, name,
-- needed, in my bags, 「自帶」 count, the cost of the rest); every icon has a
-- hint by the mouse (Widgets.rowTip); 材料費 names the materials without a
-- price, 行情 says when there is no market data yet and how to get it.
---------------------------------------------------------------------------

UI.MAT_ROWS = 4      -- material rows in view; more scroll (a recipe has at most 12)
UI.MAT_ROW_H = 34
UI.TEXT = {
    productLoading = "物品資料載入中",
    noList = "還不知道要哪些材料：已向線上會友詢問，有人回答就會自動補上",
    noPrice = "沒有價格",
    bringAll = "自帶",
    missing = "沒有價格：",
    lowerBound = "（＞＝至少：有材料沒有價格，沒算進去）",
    noMarket = "還沒有行情：找拍賣師打開拍賣場，按右上角旁的「掃描行情」",
    namedActive = "（接單中）",
    -- GF-UI-T (owner: 材料費「＞0 銅」很怪): no price for any material bought.
    noEstimate = "無法估價（沒有行情）",
    noEstimateFee = "（材料無法估價）",
    marketSingle = "只有 1 位會友回報過，僅供參考",
    marketOld = "天前的價格",
    scanName = "掃描行情",
}
UI.HINT = {
    product = { "成品", "這張單要做的東西。滑鼠移上去看物品說明。" },
    guild = { "公會單", "所有會做這個配方的會友都看得到，最先接單的人負責做。點一下改成公會單。" },
    named = { "指定工匠", "只有你選的那位工匠會收到這張單。點一下從會做的人裡選一位。",
        "名字後面寫「接單中」＝這位工匠目前有開接單。" },
    mat = { "點圖示：全部自帶／全部不帶，切換。", "「自帶」填你自己準備、交易時交給工匠的數量；沒自帶的部分由工匠準備，算進材料費。" },
    matsCost = { "材料費", "沒自帶的材料，照價格估的費用（給工匠的材料錢）。",
        "價格依序從這裡找：1. 商人賣的價格（你逛過賣它的商人）；2. 拍賣插件；3. 拍賣場的「掃描行情」（你或會友 7 天內掃的）。",
        "前面有「＞」＝有材料查不到價格，沒算進去，實際會更多；全部都查不到時寫「無法估價」。" },
    fee = { "工錢", "給工匠的手工費，可以自己改。",
        "紅色問號＝工匠沒填工錢；禮物＝工匠寫免費。" },
    total = { "合計", "材料費＋工錢。前面有「＞」＝有材料沒有價格，實際會更多；材料全部沒有價格時寫「無法估價」。" },
    scan = { "掃描行情", "按一下，工具箱就記下目前拍賣場所有物品的價格，用來估下單時的材料費和行情；掃完會自動分享給公會。",
        "掃描時遊戲不會卡，可以繼續逛；按右鍵停止。" },
    market = { "行情", "這個成品在拍賣場最近的價格，用來和合計比較，看自己做划不划算。",
        "怎麼有行情：找拍賣師、打開拍賣場視窗，視窗右上角旁邊會多一顆「掃描行情」按鈕，按一下，工具箱就記下目前拍賣場的價格，用來估材料費和行情；公會裡有人掃過也會自動分享給你。",
        "裝了拍賣插件的話，也會用插件的價格。" },
}

-- A tooltip by the mouse (Widgets.rowTip) with a white first line and wrapped lines under it.
function UI.hint(owner, lines, extra)
    if not (owner and lines) then return end
    if ns.Widgets and ns.Widgets.rowTip then ns.Widgets.rowTip(owner) else GameTooltip:SetOwner(owner, "ANCHOR_TOP") end
    for i, l in ipairs(lines) do
        if i == 1 then GameTooltip:AddLine(l, 1, 1, 1) else GameTooltip:AddLine(l, 0.85, 0.85, 0.85, true) end
    end
    for _, l in ipairs(extra or {}) do GameTooltip:AddLine(l, 1, 0.82, 0, true) end
    GameTooltip:Show()
    owner.hintShown = lines
end

-- An icon that only explains (no click): a small button holding the texture.
function UI.hintIcon(parent, size, lines)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.hintLines = lines
    b:SetScript("OnEnter", function(self) UI.hint(self, self.hintLines, self.hintExtra) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ns.Theme.infoOnly(b)
    return b
end

-- The item's name in the client's language, or nil while it is loading (it is asked for).
function UI.itemName(id)
    if not id then return nil end
    local info = ns.Widgets.itemInfo(id)
    return info.name
end

-- How many of a material I bring: true = all of need, a count (at most need), nil = none.
function UI.bringOf(d, id, need)
    local m = d.mats[id]
    if m == true then return need end
    return math.max(0, math.min(need, math.floor(tonumber(m) or 0)))
end
-- Set it: need or more = all (true, it follows the quantity), 0 = none (nil).
function UI.setBring(d, id, n, need)
    n = math.floor(tonumber(n) or 0)
    if n <= 0 then d.mats[id] = nil
    elseif need and n >= need then d.mats[id] = true
    else d.mats[id] = n end
end

-- Prefilled draft (pure): crafters = members who know the recipe (sorted active first).
function UI.newDraft(opts)
    local recipe, skill = opts.recipe, opts.skill
    -- GF-UI-B: in the test mode I am in the list too (an order to myself is a test order).
    local test = O().testOn()
    local crafters = {}
    for _, m in ipairs(opts.crafters or {}) do if test or not m.self then crafters[#crafters + 1] = m end end
    O().sortCrafters(crafters, skill)
    local target = opts.crafter
    if not target then
        -- Never myself by default: a test order is always chosen by hand.
        for _, m in ipairs(crafters) do
            if not m.self then
                if O().isActive(m.guid, skill) then target = S().authorOf(m.guid) end
                break
            end
        end
    end
    -- My own recipe and nobody else: the test order is the only choice.
    if not target and test and #crafters > 0 then
        local others = false
        for _, m in ipairs(crafters) do if not m.self then others = true end end
        if not others then target = S().selfAuthor() end
    end
    local d = { recipe = recipe, skill = skill, qty = 1, crafter = target or "*", mats = {}, crafters = crafters }
    local r = P().reagents(recipe)
    d.item = opts.item
    UI.fillReagents(d, r)
    UI.applyFee(d)
    return d
end

-- The reagent list is known (at once, or when a member answered): the
-- product and the materials I already have enough of are ticked (R-5.2).
function UI.fillReagents(d, r)
    d.reagents = r
    if not r then return end
    d.item = r.output or d.item
    for _, x in ipairs(r.list or {}) do
        local have = ns.Delivery.countOf(x.id) or 0
        if have >= x.n then d.mats[x.id] = true end
    end
end

-- Orders.onCustom stored a list a member sent: the open window waiting for it fills in.
function UI.reagentsArrived(recipe)
    if not (draft and draft.recipe == recipe and not draft.reagents) then return false end
    UI.fillReagents(draft, P().cachedReagents(recipe))
    if popup and popup:IsShown() then UI.drawPopup() end
    return true
end

-- The fee field follows the chosen crafter's quote (R-4.5): nil -> 0, marked unset.
function UI.applyFee(d)
    if d.crafter == "*" then
        d.feeQuoted = O().lowestFee(d.crafters, d.skill, d.recipe)
    else
        d.feeQuoted = O().feeFor(S().guidOf(d.crafter), d.skill, d.recipe)
    end
    d.fee = d.feeQuoted or 0
    d.feeEdited = false
end

function UI.estimateOf(d)
    local rk = P().homeKey()
    return P().estimate(d.reagents, d.qty, d.mats, function(id) return (P().priceOf(id, rk)) end)
end

-- Place the draft. Returns the order id.
function UI.submit(d)
    d = d or draft
    if not d then return nil end
    -- GF-006-D: the count I bring of each material (all, or part of it) in the
    -- order's mats (itemID -> count, the contract's field); none = not written.
    local mats = {}
    local crafts = d.reagents and math.ceil(d.qty / math.max(1, d.reagents.yield or 1)) or 1
    for _, x in ipairs(d.reagents and d.reagents.list or {}) do
        local n = UI.bringOf(d, x.id, x.n * crafts)
        if n > 0 then mats[x.id] = n end
    end
    local est = UI.estimateOf(d)
    -- Review 5-1 (contract): no quote when it cannot be computed (no list, or a price missing).
    local quote = (not est.noList and not est.unknown) and est.total or nil
    local id, why = O().place({ recipe = d.recipe, item = d.item, skill = d.skill, qty = d.qty, crafter = d.crafter,
        mats = mats, fee = d.fee or 0, feeQuoted = d.feeQuoted, quote = quote })
    if not id then
        -- Review 1-2: never pretend; the popup stays open with a red cross.
        if popup and popup.total then popup.total:SetText(UI.tex("cancel", 16)) end
        return nil, why
    end
    if popup then popup:Hide() end
    UI.refresh()
    return id
end

-- An arrow button: the game's page arrow art, else a small text button.
function UI.arrowButton(parent, which, fallbackText)
    local up = "Interface\\Buttons\\UI-SpellbookIcon-" .. (which == "prev" and "Prev" or "Next") .. "Page-"
    if ns.GameIcons.has(up .. "Up") then
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(26, 26)
        if b.SetNormalTexture then b:SetNormalTexture(up .. "Up") end
        if b.SetPushedTexture then b:SetPushedTexture(up .. "Down") end
        if b.SetDisabledTexture then b:SetDisabledTexture(up .. "Disabled") end
        if b.SetHighlightTexture then b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD") end
        ns.Theme.guardHover(b) -- GF-UI-D2: a disabled arrow stays dark
        b.art = up .. "Up"
        return b
    end
    return ns.Theme.button(parent, fallbackText, 26, 26)
end

local function moneyBoxes(parent, x, y, onChange)
    local boxes = {}
    for i, unit in ipairs({ "gold", "silver", "copper" }) do
        local e = ns.Theme.editBox(parent)
        e:SetSize(i == 1 and 60 or 36, 30)
        e:SetPoint("TOPLEFT", parent, "TOPLEFT", x + (i - 1) * 84, y)
        e:SetAutoFocus(false)
        if e.SetNumeric then e:SetNumeric(true) end
        e:SetMaxLetters(i == 1 and 5 or 2)
        local coin = parent:CreateTexture(nil, "ARTWORK")
        coin:SetSize(18, 18)
        coin:SetPoint("LEFT", e, "RIGHT", 3, 0)
        Icons.set(coin, "Interface\\MoneyFrame\\UI-" .. (unit == "gold" and "Gold" or unit == "silver" and "Silver" or "Copper") .. "Icon")
        e:SetScript("OnTextChanged", function(_, user) if user ~= false then onChange() end end)
        e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        boxes[i] = e
    end
    -- Review 5-2: all three empty = nothing entered (nil), so 「確定」 keeps "not filled in".
    function boxes.get()
        local a, b, c = str(boxes[1]:GetText()), str(boxes[2]:GetText()), str(boxes[3]:GetText())
        if a == "" and b == "" and c == "" then return nil end
        return (tonumber(a) or 0) * 10000 + (tonumber(b) or 0) * 100 + (tonumber(c) or 0)
    end
    function boxes.set(c)
        c = math.floor(c or 0)
        boxes[1]:SetText(c >= 10000 and tostring(math.floor(c / 10000)) or "")
        boxes[2]:SetText((c % 10000) >= 100 and tostring(math.floor(c / 100) % 100) or "")
        boxes[3]:SetText(c % 100 > 0 and tostring(c % 100) or "")
    end
    function boxes.clear() for i = 1, 3 do boxes[i]:SetText("") end end
    return boxes
end
UI.moneyBoxes = moneyBoxes

-- 材料費: the amount ("＞" when a price is missing) and which materials have none.
function UI.matsCostText(est)
    if est.noList then return UI.TEXT.noList end
    -- GF-UI-T: no price at all: 「無法估價（沒有行情）」 and which materials, no 「＞0」.
    local s = UI.noEstimate(est) and UI.TEXT.noEstimate or ((est.unknown and "＞" or "") .. UI.money(est.total))
    if est.unknown then
        local names = {}
        for _, id in ipairs(est.missing or {}) do names[#names + 1] = UI.itemName(id) or ("#" .. tostring(id)) end
        s = s .. "   " .. UI.TEXT.missing .. table.concat(names, "、")
    end
    return s
end

-- 行情 of the product: the text, and how it was found ("addon", "scan", "single", "none").
function UI.marketText(item)
    if not item then return UI.TEXT.noMarket, "none" end
    local m = P().marketOf(item)
    if m then
        local s = UI.money(m.price)
        local r = m.source == "scan" and P().reference(P().homeKey(), item) or nil
        if m.grey and r and r.newestDay then
            s = s .. "   （" .. (P().today() - r.newestDay) .. " " .. UI.TEXT.marketOld .. "）"
        end
        return s, m.source
    end
    local r = P().reference(P().homeKey(), item)
    if r and r.single then return UI.money(r.price) .. "   （" .. UI.TEXT.marketSingle .. "）", "single" end
    return UI.TEXT.noMarket, "none"
end

-- One material row of the form (made once, reused while scrolling).
local function matRow(f, i)
    local r = CreateFrame("Frame", nil, f.matBox)
    r:SetSize(f.matW, UI.MAT_ROW_H)
    r:SetPoint("TOPLEFT", f.matBox, "TOPLEFT", 0, -(i - 1) * UI.MAT_ROW_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
    r.icon = iconButton(r, ns.ROW_ICON, "unknown", nil, function()
        local row = r
        if not (draft and row.id) then return end
        local all = UI.bringOf(draft, row.id, row.need) >= row.need
        UI.setBring(draft, row.id, all and 0 or row.need, row.need)
        UI.drawPopup()
    end)
    r.icon:SetPoint("LEFT", r, "LEFT", 2, 0)
    r.icon:SetScript("OnEnter", function(self)
        local row = r
        if ns.Widgets.rowTip then ns.Widgets.rowTip(self) end
        local shown = row.id and type(GameTooltip.SetItemByID) == "function" and pcall(GameTooltip.SetItemByID, GameTooltip, row.id)
        if not shown then GameTooltip:AddLine(UI.itemName(row.id) or UI.TEXT.productLoading, 1, 1, 1) end
        GameTooltip:AddLine("需要 " .. tostring(row.need or 0) .. " 個，你背包有 " .. tostring(row.have or 0) .. " 個", 1, 0.82, 0)
        for _, l in ipairs(UI.HINT.mat) do GameTooltip:AddLine(l, 0.85, 0.85, 0.85, true) end
        GameTooltip:Show()
        self.hintShown = UI.HINT.mat
    end)
    r.name = r:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)
    r.name:SetPoint("LEFT", r, "LEFT", 36, 0); r.name:SetWidth(168); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
    r.needText = r:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)
    r.needText:SetPoint("LEFT", r, "LEFT", f.matCol.need, 0); r.needText:SetWidth(50); r.needText:SetJustifyH("LEFT")
    r.haveText = r:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)
    r.haveText:SetPoint("LEFT", r, "LEFT", f.matCol.have, 0); r.haveText:SetWidth(54); r.haveText:SetJustifyH("LEFT")
    r.box = ns.Theme.editBox(r, 48, 26)
    r.box:SetPoint("LEFT", r, "LEFT", f.matCol.bring, 0)
    if r.box.SetNumeric then r.box:SetNumeric(true) end
    r.box:SetMaxLetters(4)
    r.box.fieldNamed = "自帶"
    r.box:SetScript("OnTextChanged", function(self, user)
        if f.filling or user == false or not (draft and r.id) then return end
        local n = tonumber(str(self:GetText())) or 0
        if n > r.need then n = r.need; f.filling = true; self:SetText(tostring(n)); f.filling = false end
        UI.setBring(draft, r.id, n, r.need)
        UI.drawPopup(true)
    end)
    r.box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    r.box:SetScript("OnEnter", function(self)
        UI.hint(self, { "自帶", "你自己準備、交易時交給工匠的數量（0 到 " .. tostring(r.need or 0) .. "）。", "沒自帶的部分由工匠準備，算進材料費。" })
    end)
    r.box:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.cost = ns.freeText(r:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
    r.cost:SetPoint("LEFT", r, "LEFT", f.matCol.cost, 0); r.cost:SetJustifyH("LEFT")
    f.matRows[i] = r
    return r
end

local function drawMats(f, d, est, keepBoxes)
    local list = est.mats or {}
    local n = UI.MAT_ROWS
    f.matOffset = math.max(0, math.min(f.matOffset or 0, math.max(0, #list - n)))
    for i = 1, n do
        local row = list[f.matOffset + i]
        local r = f.matRows[i] or (row and matRow(f, i)) or nil
        if r then
            if row then
                ns.stripe(r.bg, f.matOffset + i)
                r.id, r.need = row.id, row.need
                r.have = ns.Delivery.countOf(row.id) or 0
                itemIcon(r.icon.tex, row.id)
                r.name:SetText(UI.itemName(row.id) or UI.TEXT.productLoading)
                r.needText:SetText("x" .. row.need)
                r.haveText:SetText(tostring(r.have))
                if not (keepBoxes and r.box.HasFocus and r.box:HasFocus()) then
                    f.filling = true
                    r.box:SetText(tostring(row.own or 0))
                    f.filling = false
                end
                if row.buy == 0 then r.cost:SetText(UI.TEXT.bringAll); ns.setTextColor(r.cost, "good")
                elseif row.unknown then r.cost:SetText(UI.TEXT.noPrice); ns.setTextColor(r.cost, "warn")
                else r.cost:SetText(UI.money(row.total)); r.cost:SetTextColor(0.9, 0.9, 0.9) end
                r:Show()
            else
                r:Hide(); r.id = nil
            end
        end
    end
    f.matBar.sync(f.matOffset, #list, n)
    if #list > n then f.matBar:Show() else f.matBar:Hide() end
    f.matEmpty:SetText(est.noList and UI.TEXT.noList or "")
end

local function drawPopup(keepBoxes)
    if not (popup and draft) then return end
    local d = draft
    if not d.reagents then UI.fillReagents(d, P().cachedReagents(d.recipe)) end
    -- 成品: the icon and the item's name (the recipe's name until the item is known).
    itemIcon(popup.item.tex, d.item, d.skill)
    local name = d.item and UI.itemName(d.item) or nil
    if not name then name = d.item and UI.TEXT.productLoading or ns.Recipes.name(d.recipe) end
    setLabel(popup.item, name)
    popup.qty:SetText(tostring(d.qty))
    -- 對象: the chosen one glows, the other is dimmed (UI.setSelected).
    popup.guild.badge:Hide(); popup.named.badge:Hide()
    UI.setSelected(popup.guild, d.crafter == "*")
    UI.setSelected(popup.named, d.crafter ~= "*")
    local m = d.crafter ~= "*" and memberOf(d.crafter) or nil
    if m and Icons.setClassIcon(popup.named.tex, m.classToken) then popup.named.tex:Show() else setIcon(popup.named.tex, "unknown") end
    -- GF-UI-T (owner: 「指定工匠有個標記重疊？」): the small hammer that sat on the
    -- icon's corner is gone; 「接單中」 after the name says the same in words.
    local active = m and O().isActive(m.guid, d.skill)
    setLabel(popup.named, m and ("指定工匠：" .. ns.shortName(m.name) .. (active and UI.TEXT.namedActive or "")) or "指定工匠")
    if popup.named.label then popup.named.label:SetAlpha(1) end
    popup.guild.hintExtra = d.crafter == "*" and { "目前選的是這個" } or nil
    popup.named.hintExtra = m and { "目前選的是：" .. ns.shortName(m.name) } or nil
    local est = UI.estimateOf(d)
    drawMats(popup, d, est, keepBoxes)
    popup.matsCost:SetText(UI.matsCostText(est))
    popup.matsIcon.hintExtra = est.unknown and { UI.TEXT.lowerBound } or nil
    if not d.feeEdited then popup.fee.set(d.fee) end
    if not Icons.setProfessionIcon(popup.feeIcon.tex, { skillLineID = d.skill }) then setIcon(popup.feeIcon.tex, "making") end
    local kind = UI.feeKind(d.feeEdited and d.fee or d.feeQuoted)
    popup.feeKind:Hide()
    popup.feeIcon.hintExtra = nil
    if kind == "unset" and not d.feeEdited then
        setIcon(popup.feeKind, "unknown"); popup.feeKind.tip = "工匠沒有填工錢"
        popup.feeIcon.hintExtra = { "這位工匠沒填工錢：先和工匠談好再填。" }
    elseif kind == "free" and not d.feeEdited then
        setIcon(popup.feeKind, "free"); popup.feeKind.tip = "免費"
        popup.feeIcon.hintExtra = { "工匠寫了免費。" }
    end
    popup.total:SetText(UI.totalText(est, d.fee))
    local text, source = UI.marketText(d.item)
    popup.market:SetText(text)
    popup.marketSource = source
    if source == "none" or source == "single" then ns.setTextColor(popup.market, "muted") else popup.market:SetTextColor(1, 1, 1) end
end
UI.drawPopup = drawPopup

-- GF-002-D: a field name in front of every row (owner: icons alone are not understood).
-- GF-002-E: the normal font, no fixed width, one line.
function UI.fieldLabel(parent, text, x, y)
    local l = ns.freeText(parent:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT))
    l:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    l:SetJustifyH("LEFT")
    l:SetText(text)
    parent.fields = parent.fields or {}
    parent.fields[#parent.fields + 1] = text
    parent.fieldStrings = parent.fieldStrings or {}
    parent.fieldStrings[text] = l
    return l
end

-- Where the controls start: after the widest field name of the window.
UI.FIELD_X, UI.ROW_STEP = 24, ns.WINDOW_ROW -- GF-002-F: 52
function UI.controlX(names)
    local w = 0
    for _, n in ipairs(names) do w = math.max(w, ns.labelWidth(n)) end
    return UI.FIELD_X + w + 18
end

-- GF-UI-C (owner: one grid): 行情 has its own row under 合計 (it is compared with it),
-- every field name at FIELD_X, every control at the same X.
-- GF-006-D: 材料 is a small table (one row per material) between 對象 and 材料費.
UI.ORDER_FIELDS = { "成品", "數量", "對象", "材料", "材料費", "工錢", "合計", "行情" }
UI.POPUP_W = 720
local function createPopup()
    if popup then return popup end
    local f = ns.popupWindow(UI.POPUP_NAME, UI.POPUP_W, 640)
    f:SetPoint("CENTER", 0, 40)
    f:EnableMouse(true)
    ns.exclusivePopup(f)
    if f.TitleText then f.TitleText:SetText("下單") end
    local X = UI.controlX(UI.ORDER_FIELDS) -- where the controls start, after the field names
    f.controlX = X
    local MAT_Y = -44 - 3 * UI.ROW_STEP          -- 材料: the column names
    local LIST_Y = MAT_Y - 26                     -- the material rows
    local AFTER = LIST_Y - UI.MAT_ROWS * UI.MAT_ROW_H - 12
    local function y(i)
        if i <= 3 then return -44 - (i - 1) * UI.ROW_STEP end
        return AFTER - (i - 5) * UI.ROW_STEP
    end
    UI.fieldLabel(f, "成品", UI.FIELD_X, y(1) - 8)
    f.item = iconButton(f, ns.ICON, "unknown", nil, nil, "成品")
    f.item:SetPoint("TOPLEFT", f, "TOPLEFT", X, y(1))
    f.item:SetScript("OnEnter", function(self)
        if ns.Widgets.rowTip then ns.Widgets.rowTip(self) end
        local id = draft and draft.item
        local shown = id and type(GameTooltip.SetItemByID) == "function" and pcall(GameTooltip.SetItemByID, GameTooltip, id)
        if not shown then GameTooltip:AddLine(UI.HINT.product[1], 1, 1, 1) end
        GameTooltip:AddLine(UI.HINT.product[2], 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
        self.hintShown = UI.HINT.product
    end)
    ns.Theme.infoOnly(f.item)
    -- Quantity: the game's previous / next page arrows (GF-002-C).
    UI.fieldLabel(f, "數量", UI.FIELD_X, y(2) - 8)
    f.minus = UI.arrowButton(f, "prev", "－"); f.minus:SetPoint("TOPLEFT", f, "TOPLEFT", X, y(2)); f.minus.fieldNamed = "數量"
    f.qty = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge"); f.qty:SetPoint("LEFT", f.minus, "RIGHT", 12, 0)
    f.plus = UI.arrowButton(f, "next", "＋"); f.plus:SetPoint("LEFT", f.minus, "RIGHT", 52, 0); f.plus.fieldNamed = "數量"
    local function step(n)
        local yd = draft.reagents and draft.reagents.yield or 1
        draft.qty = math.max(yd, math.min(200, draft.qty + n * yd))
        drawPopup()
    end
    f.minus:SetScript("OnClick", function() step(-1) end)
    f.plus:SetScript("OnClick", function() step(1) end)
    for _, b in ipairs({ f.minus, f.plus }) do
        b.hintLines = { "數量", b == f.minus and "少做一份。" or "多做一份。", "一次做出好幾個的配方，一格就是一次做出的數量。" }
        b:SetScript("OnEnter", function(self) UI.hint(self, self.hintLines) end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    -- Guild order or a named crafter.
    UI.fieldLabel(f, "對象", UI.FIELD_X, y(3) - 8)
    f.guild = iconButton(f, ns.ICON, "guild", nil, function() draft.crafter = "*"; UI.applyFee(draft); drawPopup() end, "公會單")
    f.named = iconButton(f, ns.ICON, "unknown", nil, function(self) UI.pickCrafter(self) end, "指定工匠")
    UI.flow(f, { f.guild, f.named }, X, y(3), 28)
    f.guild.hintLines, f.named.hintLines = UI.HINT.guild, UI.HINT.named
    for _, b in ipairs({ f.guild, f.named }) do
        b:SetScript("OnEnter", function(self) UI.hint(self, self.hintLines, self.hintExtra) end)
    end
    -- 材料: one row per material; the column names above them.
    UI.fieldLabel(f, "材料", UI.FIELD_X, MAT_Y - 4)
    f.matW = UI.POPUP_W - X - 24 - ns.Widgets.SCROLL_W - ns.Widgets.SCROLL_GAP
    f.matCol = { need = 212, have = 266, bring = 324, cost = 386 }
    f.matHead = {}
    for key, text in pairs({ need = "需要", have = "背包", bring = "自帶", cost = "材料費" }) do
        local h = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.DISABLED_FONT))
        h:SetPoint("TOPLEFT", f, "TOPLEFT", X + f.matCol[key], MAT_Y)
        h:SetText(text)
        f.matHead[key] = h
    end
    f.matBox = CreateFrame("Frame", nil, f)
    f.matBox:SetSize(f.matW, UI.MAT_ROWS * UI.MAT_ROW_H)
    f.matBox:SetPoint("TOPLEFT", f, "TOPLEFT", X, LIST_Y)
    f.matRows, f.matOffset = {}, 0
    f.matBar = ns.Widgets.scrollBar(f, UI.MAT_ROWS * UI.MAT_ROW_H, function(o) f.matOffset = o; drawPopup(true) end)
    f.matBar:SetPoint("TOPLEFT", f.matBox, "TOPRIGHT", ns.Widgets.SCROLL_GAP, 0)
    f.matBar:Hide()
    if f.matBox.EnableMouseWheel then f.matBox:EnableMouseWheel(true) end
    f.matBox:SetScript("OnMouseWheel", function(_, delta) f.matBar.scrollBy(-(tonumber(delta) or 0)) end)
    f.matEmpty = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.DISABLED_FONT))
    f.matEmpty:SetPoint("TOPLEFT", f.matBox, "TOPLEFT", 4, -8)
    UI.fieldLabel(f, "材料費", UI.FIELD_X, y(5) - 8)
    f.matsIcon = UI.hintIcon(f, 22, UI.HINT.matsCost)
    f.matsIcon:SetPoint("TOPLEFT", f, "TOPLEFT", X, y(5) - 6)
    Icons.set(f.matsIcon.tex, UI.ICON.bag)
    f.matsCost = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
    f.matsCost:SetPoint("LEFT", f.matsIcon, "RIGHT", 6, 0)
    UI.fieldLabel(f, "工錢", UI.FIELD_X, y(6) - 8)
    f.feeIcon = UI.hintIcon(f, 22, UI.HINT.fee)
    f.feeIcon:SetPoint("TOPLEFT", f, "TOPLEFT", X, y(6) - 6)
    f.fee = UI.moneyBoxes(f, X + 54, y(6) - 2, function()
        if not draft then return end
        draft.fee, draft.feeEdited = f.fee.get() or 0, true
        popup.total:SetText(UI.totalText(UI.estimateOf(draft), draft.fee))
    end)
    f.feeKind = f:CreateTexture(nil, "OVERLAY"); f.feeKind:SetSize(16, 16)
    f.feeKind:SetPoint("LEFT", f.feeIcon, "RIGHT", 4, 0)
    UI.fieldLabel(f, "合計", UI.FIELD_X, y(7) - 8)
    f.sumIcon = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    f.sumIcon:SetPoint("TOPLEFT", f, "TOPLEFT", X, y(7) - 6); f.sumIcon:SetText("")
    f.total = ns.freeText(f:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge"))
    f.total:SetPoint("TOPLEFT", f, "TOPLEFT", X, y(7) - 6)
    UI.fieldLabel(f, "行情", UI.FIELD_X, y(8) - 8)
    f.marketIcon = UI.hintIcon(f, 20, UI.HINT.market)
    f.marketIcon:SetPoint("TOPLEFT", f, "TOPLEFT", X, y(8) - 6)
    Icons.set(f.marketIcon.tex, UI.ICON.gold)
    f.market = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
    f.market:SetPoint("LEFT", f.marketIcon, "RIGHT", 6, 0)
    f.send = UI.textButton(f, "下單", function() UI.submit() end, 110)
    f.send:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
    f:SetHeight(-y(8) + 30 + 16 + ns.BUTTON_H + 16)
    -- An item's name arrived (Widgets asked the client for it): redraw the open form.
    -- (Registered here: Widgets.lua loads after this file.)
    ns.Widgets.onItemAnswer(function()
        if popup and popup:IsShown() and draft then drawPopup(true) end
    end)
    f:Hide()
    popup = f
    return f
end


-- Choose a crafter: active ones first (R-4.2), each with their fee.
function UI.pickCrafter(owner)
    if not draft then return end
    local items = {}
    for _, m in ipairs(draft.crafters) do
        local a = S().authorOf(m.guid)
        local fee = O().feeFor(m.guid, draft.skill, draft.recipe)
        local mark = O().isActive(m.guid, draft.skill) and (UI.tex("hammer") .. " ") or ""
        local feeText = fee == nil and "  ?" or (fee == 0 and "  免費" or ("  " .. UI.money(fee)))
        if m.self then mark = ns.GameIcons.markup("test", 18) .. " 測試 " end
        items[#items + 1] = { text = mark .. ns.shortName(m.name) .. (m.online and (" " .. UI.tex("online", 16)) or "") .. feeText,
            fn = function() draft.crafter = a; UI.applyFee(draft); drawPopup() end }
        if #items >= 12 then break end
    end
    return ns.showMenu(owner, items)
end

-- opts = { recipe, skill, crafters = { member... }, crafter = author or nil }.
function UI.openOrder(opts)
    if not opts or not opts.recipe then return nil end
    if not opts.crafters and ns.Recipes then
        local index = ns.Recipes.index()
        local p = index and opts.skill and index[opts.skill]
        opts.crafters = p and p.recipes[opts.recipe] or {}
    end
    draft = UI.newDraft(opts)
    createPopup():Show()
    popup.matOffset = 0
    drawPopup()
    return draft
end
function UI.draft() return draft end

---------------------------------------------------------------------------
-- Fee popup (R-4.3): profession default or one recipe; 「清除」 = not filled in.
---------------------------------------------------------------------------

UI.FEE_NAME = "GreenFangToolkit_FeePopup"
local feePopup, feeTarget

function UI.editFee(target)
    feeTarget = target
    if not feePopup then
        local f = ns.popupWindow(UI.FEE_NAME, 480, 200)
        f:SetPoint("CENTER", 0, 120)
        f:EnableMouse(true)
        ns.exclusivePopup(f)
        if f.TitleText then f.TitleText:SetText("工錢") end
        UI.fieldLabel(f, "工錢", UI.FIELD_X, -52)
        local X = UI.controlX({ "工錢" })
        f.icon = f:CreateTexture(nil, "ARTWORK"); f.icon:SetSize(ns.ICON, ns.ICON)
        f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", X, -44)
        f.boxes = moneyBoxes(f, X + 46, -46, function() end)
        f.save = UI.textButton(f, "確定", function() UI.saveFee(f.boxes.get()) end, 96)
        f.save:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
        f.free = UI.textButton(f, "免費", function() UI.saveFee(0) end, 96)
        f.free:SetPoint("RIGHT", f.save, "LEFT", -10, 0)
        f.clear = UI.textButton(f, "清除", function() UI.saveFee(nil) end, 96)
        f.clear:SetPoint("RIGHT", f.free, "LEFT", -10, 0)
        f:Hide()
        feePopup = f
    end
    local sv = O().services(S().selfAuthor())
    local current
    if target.recipe then
        current = sv.recipeFees[target.recipe]
        ns.Recipes.setIcon(feePopup.icon, target.recipe, target.skill)
    else
        current = sv.fees[target.skill]
        Icons.setProfessionIcon(feePopup.icon, { skillLineID = target.skill })
    end
    feePopup.boxes.set(current or 0)
    feePopup:Show()
    return feePopup
end

-- fee nil = not filled in (R-4.4).
function UI.saveFee(fee)
    local t = feeTarget
    if not t then return end
    if t.recipe then O().setRecipeFee(t.recipe, fee, t.skill) else O().setFee(t.skill, fee) end
    if feePopup then feePopup:Hide() end
    UI.refresh()
    if t.back == "services" then UI.openServices() end
    if ns.Recipes and ns.Framework.isModuleShown("recipes") then ns.Recipes.refresh() end
end

---------------------------------------------------------------------------
-- 我的服務 (GF-002-E, owner: 「工匠設定要按右鍵不明顯」): one window with every
-- profession I can craft for: 接單 on/off and the default fee, plus the way
-- to the per-recipe fees (the recipe page, only my recipes, 「我的工錢」).
---------------------------------------------------------------------------

UI.SERVICES_NAME = "GreenFangToolkit_ServicesPopup"
UI.SERVICES_FIELDS = { "專業", "接單", "工錢" }

function UI.feeText(fee)
    local kind = UI.feeKind(fee)
    if kind == "unset" then return "沒填" end
    if kind == "free" then return "免費" end
    return UI.money(fee)
end

function UI.drawServices()
    local f = UI.servicesPopup
    if not f then return end
    local skills = UI.ownCraftSkills()
    local sv = O().services(S().selfAuthor())
    for i, skill in ipairs(skills) do
        local r = f.rows[i]
        if not r then
            local y = -84 - (i - 1) * ns.WINDOW_ROW
            r = {}
            r.icon = f:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(ns.ICON, ns.ICON)
            r.icon:SetPoint("TOPLEFT", f, "TOPLEFT", UI.FIELD_X, y + 6)
            r.name = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
            r.name:SetPoint("TOPLEFT", f, "TOPLEFT", UI.FIELD_X + 40, y - 2)
            r.active = ns.checkBox(f, "接單", f.colActive, y, function(on) O().setActive(r.skill, on); UI.refresh() end)
            r.feeTex = f:CreateTexture(nil, "ARTWORK"); r.feeTex:SetSize(18, 18)
            r.feeTex:SetPoint("TOPLEFT", f, "TOPLEFT", f.colFee, y - 4)
            r.fee = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
            r.fee:SetPoint("TOPLEFT", f, "TOPLEFT", f.colFee + 24, y - 2)
            r.edit = UI.textButton(f, "工錢", function() UI.editFee({ skill = r.skill, back = "services" }) end)
            r.edit:SetPoint("TOPLEFT", f, "TOPLEFT", f.colFee + 150, y + 4)
            f.rows[i] = r
        end
        r.skill = skill
        Icons.setProfessionIcon(r.icon, { skillLineID = skill })
        r.name:SetText(ns.Data.skillName(nil, skill) or tostring(skill))
        r.active.set(sv.active[skill] == true)
        showFee(r.feeTex, r.fee, sv.fees[skill])
        r.fee:SetText(UI.feeText(sv.fees[skill]))
        for _, w in ipairs({ r.icon, r.name, r.active, r.active.label, r.fee, r.edit }) do w:Show() end
    end
    for i = #skills + 1, #f.rows do
        local r = f.rows[i]
        for _, w in ipairs({ r.icon, r.name, r.active, r.active.label, r.feeTex, r.fee, r.edit }) do w:Hide() end
    end
    f.none:SetText(#skills == 0 and "沒有可以接單的專業" or "")
    f:SetHeight(160 + math.max(1, #skills) * ns.WINDOW_ROW)
end

function UI.openServices()
    if not UI.servicesPopup then
        local f = ns.popupWindow(UI.SERVICES_NAME, 620, 260)
        f:SetPoint("CENTER", 0, 80)
        f:EnableMouse(true)
        ns.exclusivePopup(f)
        if f.TitleText then f.TitleText:SetText("我的服務") end
        f.colActive, f.colFee = 230, 340
        UI.fieldLabel(f, "專業", UI.FIELD_X, -46)
        UI.fieldLabel(f, "接單", f.colActive, -46)
        UI.fieldLabel(f, "工錢", f.colFee, -46)
        f.rows = {}
        f.none = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.DISABLED_FONT))
        f.none:SetPoint("TOPLEFT", f, "TOPLEFT", UI.FIELD_X, -90)
        -- Per-recipe fees: the recipe page with only my recipes, each row has 「我的工錢」.
        f.recipeFees = UI.textButton(f, "配方工錢", function()
            f:Hide()
            UI.showMyRecipes()
        end, 120)
        f.recipeFees:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", UI.FIELD_X, 16)
        f.close = UI.textButton(f, "完成", function() f:Hide() end, 96)
        f.close:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
        f:Hide()
        UI.servicesPopup = f
    end
    UI.servicesPopup:Show()
    UI.drawServices()
    return UI.servicesPopup
end

-- The recipe page on my own recipes (their fee column and 「我的工錢」 buttons).
function UI.showMyRecipes()
    local me = ns.Data.player().guid
    if not ns.Recipes then return end
    ns.Recipes.show(me)
end

---------------------------------------------------------------------------
-- ＋下單 (GF-002-E, owner: 「我看不出來如何下單」). GF-UI-S (owner 2026-11-28):
-- the 「下單：選配方」 window is gone; ＋下單 switches to 工匠配方 (one list,
-- one set of filters: 搜尋, 專業, 會做的人, 只看在線, 接單中, 工錢, scrolling),
-- where a row's 「下單」 (or 下單 on its right-click menu) opens the order popup.
---------------------------------------------------------------------------

function UI.startOrder()
    if ns.Recipes and ns.Recipes.forOrder then return ns.Recipes.forOrder() end
    return nil
end

-- The fee a recipe row shows (GF-002-E, R-4.4): mine for my own recipe, else
-- the lowest of the crafters in the list (other members). nil = nobody filled it in.
function UI.rowFee(data, crafters)
    if data.mine and not crafters then
        return O().feeFor(ns.Data.player().guid, data.skill, data.id)
    end
    local others = {}
    for _, m in ipairs(crafters or data.crafters or {}) do if not m.self then others[#others + 1] = m end end
    if #others == 0 then return O().feeFor(ns.Data.player().guid, data.skill, data.id) end
    return O().lowestFee(others, data.skill, data.id)
end

---------------------------------------------------------------------------
-- Recipe page and roster hooks (R-4.2, R-5.1)
---------------------------------------------------------------------------

-- Extra right-click items on a recipe row.
function UI.recipeMenuItems(data)
    local items = {}
    if not data then return items end
    local others = {}
    for _, m in ipairs(data.crafters or {}) do if not m.self then others[#others + 1] = m end end
    if #others > 0 or (data.mine and O().testOn()) then
        items[#items + 1] = { text = "下單", fn = function()
            local pick = UI.pendingCrafter
        UI.pendingCrafter, UI.pendingMark = nil, nil
        UI.openOrder({ recipe = data.id, skill = data.skill, crafters = data.crafters, crafter = pick })
        end }
    end
    if data.mine then
        items[#items + 1] = { text = "我的工錢", fn = function() UI.editFee({ recipe = data.id, skill = data.skill }) end }
    end
    return items
end

-- Right-click on someone's profession icon on the roster.
function UI.rosterMenuItems(member, skill)
    if not (member and member.guid and skill) then return {} end
    if member.guid == ns.Data.player().guid then return {} end
    return { { text = "下單給 " .. ns.shortName(member.name), fn = function()
        local a = S().authorOf(member.guid)
        ns.Recipes.show(member.guid, skill)
        -- Review 7-6: used by the next 下單 only, and forgotten after two minutes.
        UI.pendingCrafter = a
        local mark = {}
        UI.pendingMark = mark
        ns.after(120, function() if UI.pendingMark == mark then UI.pendingCrafter = nil end end)
    end } }
end

---------------------------------------------------------------------------
-- Trade strip (R-7.2): only while trading with the other side of an open order.
---------------------------------------------------------------------------

local strip
function UI.tradeChanged()
    local t = ns.Delivery.current()
    if not t then if strip then strip:Hide() end return end
    if not strip then
        strip = CreateFrame("Frame", "GreenFangToolkit_TradeStrip", UIParent)
        strip:SetSize(300, 30)
        ns.makeOpaque(strip, 0)
        strip.rows = {}
    end
    local anchor = _G.TradeFrame or UIParent
    strip:ClearAllPoints()
    strip:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    local me = S().selfAuthor()
    local list = O().between(me, t.other)
    local got = ns.Delivery.sum(t.snap.theirs)
    local gave = ns.Delivery.sum(t.snap.mine)
    for i, v in ipairs(list) do
        local r = strip.rows[i]
        if not r then
            r = CreateFrame("Frame", nil, strip)
            r:SetSize(296, 26)
            r:SetPoint("TOPLEFT", strip, "TOPLEFT", 2, -2 - (i - 1) * 26)
            r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(22, 22); r.icon:SetPoint("LEFT", r, "LEFT", 2, 0)
            r.text = r:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT); r.text:SetPoint("LEFT", r, "LEFT", 30, 0)
            r.state = r:CreateTexture(nil, "ARTWORK"); r.state:SetSize(18, 18); r.state:SetPoint("RIGHT", r, "RIGHT", -4, 0)
            strip.rows[i] = r
        end
        itemIcon(r.icon, v.item, v.skill)
        local moving = (v.customer == me and got[v.item] or gave[v.item]) or 0
        local done = math.min(v.qty, v.progress + moving)
        r.text:SetText("x" .. v.qty .. "  " .. done .. "/" .. v.qty .. "   " .. UI.money(v.fee))
        setIcon(r.state, done >= v.qty and "deal" or "waiting")
        r:Show()
    end
    for i = #list + 1, #strip.rows do strip.rows[i]:Hide() end
    strip:SetHeight(math.max(30, #list * 26 + 4))
    strip:Show()
end
function UI.tradeHidden() if strip then strip:Hide() end end
function UI.strip() return strip end

---------------------------------------------------------------------------
-- 「掃描行情」 next to the auction house (R-8.4; GF-UI-T: the icon has its name)
---------------------------------------------------------------------------

local scanButton
function UI.auctionShown()
    local anchor = _G.AuctionHouseFrame or _G.AuctionFrame
    if not anchor then return end
    if not scanButton then
        scanButton = iconButton(UIParent, 32, "scan", UI.TEXT.scanName, function(_, mouse)
            if mouse == "RightButton" then P().stopScan() else P().startScan() end
            UI.scanChanged()
        end, UI.TEXT.scanName)
        -- GF-UI-T: a hint in words (what it does, where the prices go).
        scanButton:SetScript("OnEnter", function(self) UI.hint(self, UI.HINT.scan, self.hintExtra) end)
        scanButton:SetFrameStrata("HIGH")
        scanButton.ring = scanButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        scanButton.ring:SetPoint("CENTER")
    end
    scanButton:ClearAllPoints()
    scanButton:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, -30)
    scanButton:Show()
    UI.scanChanged()
end
function UI.auctionHidden() if scanButton then scanButton:Hide() end end

function UI.scanChanged()
    if not scanButton then return end
    local s = P().scanState()
    local last = P().db().scan.last
    if s.state == "running" then
        local pct = s.total and s.total > 0 and math.floor((s.done or 0) * 100 / s.total) or nil
        scanButton.ring:SetText(pct and (pct .. "%") or "...")
    elseif s.state == "done" then
        scanButton.ring:SetText(UI.tex("deal", 16))
    else
        scanButton.ring:SetText("")
    end
    local ago = last and last.at and math.floor((S().serverNow() - last.at) / 3600)
    scanButton.tip = UI.TEXT.scanName .. (ago and ("  " .. ago .. " 小時前") or "")
    scanButton.hintExtra = { ago and ("上次掃描：" .. ago .. " 小時前") or "還沒掃描過" }
end
function UI.scanButton() return scanButton end

---------------------------------------------------------------------------
-- Minimap number (R-6.8)
---------------------------------------------------------------------------

function UI.updateBadge(count)
    local b = ns.Framework.minimapButton
    if not b then return end
    if not b.ordersBadge then
        b.ordersBadge = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.ordersBadge:SetPoint("TOPRIGHT", b, "TOPRIGHT", 2, 2)
        b.ordersBadge:SetTextColor(1, 0.82, 0)
        -- GF-UI-B (GF-UI-A §2.12): a 1 px black outline, so it does not blur into the map.
        local fs = b.ordersBadge
        if fs.GetFont and fs.SetFont then
            local path, size = fs:GetFont()
            if path then pcall(fs.SetFont, fs, path, size, "OUTLINE") end
        end
    end
    local n = ns.guildState() ~= "target" and 0 or count or O().attentionCount()
    b.ordersBadge:SetText(n > 0 and tostring(n) or "")
    UI.badgeCount = n
end

O().onChanged = function()
    ns.coalesce("orders-page", 1, function()
        UI.updateBadge()
        if ns.Framework.isModuleShown("orders") then UI.refresh() end
    end)
end
