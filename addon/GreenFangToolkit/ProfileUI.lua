-- ProfileUI (GF-010, spec v2.0 §5.1, §5.2): the right half of the personnel
-- file page (Character.lua builds the page and calls ProfileUI.build):
--   職責定位  主職責 [坦克][治療][輸出][未設定]  可支援 [坦克][治療][輸出]  [ ]分享
--   我的業務  my orders and adventures (read-only; a click opens the record)
--   個人需求  only once GF-009 registers a provider (Profile.setNeedsProvider)
-- and the read-only card of another member (opened from the roster).
-- Game art only: the group finder's round role icons (GameIcons role_*),
-- 16 px text, a 2-4 character name next to every icon, no sentences or time
-- stamps (近期 / 稍早 / 過期 in the tooltip).

local _, ns = ...
local str = ns.str

local ProfileUI = {}
ns.ProfileUI = ProfileUI

local P = function() return ns.Profile end

ProfileUI.X, ProfileUI.W = 600, 470
ProfileUI.ROLE_ICON = 32
ProfileUI.ROLE_STEP = 108          -- icon + 4 + a 2-3 character name + gap
ProfileUI.Y = { head = -40, main = -76, can = -120, share = -162, bizHead = -208, biz = -240, needs = -520 }
ProfileUI.BIZ_ROWS, ProfileUI.BIZ_ROW = 7, 36
ProfileUI.CARD_NAME = "GreenFangToolkit_ProfileCard"
ProfileUI.CARD_W, ProfileUI.CARD_H = 460, 300
ProfileUI.GAME = { t = "role_t", h = "role_h", d = "role_d" }
ProfileUI.KIND = { order = { art = "INV_Hammer_20", name = "委託" }, adventure = { art = "INV_Misc_Map_01", name = "冒險" } }

local panel
local controls = {}

-- A round role icon with its name (OrdersUI.iconButton, the group finder art).
local function roleButton(parent, r, onClick)
    local O = ns.OrdersUI
    local b = O.iconButton(parent, ProfileUI.ROLE_ICON, "unknown", P().ROLE_NAME[r], onClick, P().ROLE_NAME[r])
    ns.GameIcons.set(b.tex, ProfileUI.GAME[r])
    b.role = r
    -- GF-016: the role's name, and 「此職業通常不擔任」 when the class does not usually take it.
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(P().ROLE_NAME[self.role])
        if self.gfSuggested == false then GameTooltip:AddLine(ProfileUI.notSuggestedText(), 1, 0.5, 0.25) end
        GameTooltip:Show()
    end)
    return b
end

-- The game's own words when the client has them (CLASS_ROLE_NOT_RECOMMENDED), else ours.
function ProfileUI.notSuggestedText()
    local g = rawget(_G, "CLASS_ROLE_NOT_RECOMMENDED")
    if type(g) == "string" and g ~= "" then return g end
    return P().NOT_SUGGESTED_TIP
end

-- A role the class does not usually take: the icon dimmer, still a switch (GF-016).
ProfileUI.NOT_SUGGESTED_ALPHA = 0.45

-- On / off look. enabled = false only before the character is known.
-- suggested = false: dimmer icon and name, the tooltip says so; it may still be chosen.
local function drawRole(b, on, enabled, suggested)
    ns.OrdersUI.setSelected(b, on)
    if enabled then
        if b.Enable then b:Enable() end
        if b.tex.SetDesaturated then b.tex:SetDesaturated(false) end
    else
        if b.Disable then b:Disable() end
        if b.tex.SetDesaturated then b.tex:SetDesaturated(true) end
        b.sel:Hide(); b.shine:Hide()
        if b.label then b.label:SetTextColor(0.5, 0.5, 0.5) end
    end
    b.gfSuggested = suggested ~= false
    if not b.gfSuggested and not on then
        b.tex:SetAlpha(ProfileUI.NOT_SUGGESTED_ALPHA)
        if b.label then b.label:SetAlpha(0.7) end
    end
    b.gfEnabled = enabled
end
ProfileUI.drawRole = drawRole

local function header(p, text, x, y)
    local h = p:CreateFontString(nil, "ARTWORK", ns.Theme.FONT.header)
    h:SetPoint("TOPLEFT", p, "TOPLEFT", x, y)
    h:SetText(text)
    return h
end

local function fieldLabel(p, text, x, y)
    local l = ns.freeText(p:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT))
    l:SetPoint("TOPLEFT", p, "TOPLEFT", x, y)
    l:SetText(text)
    return l
end

local function bizRow(p, i)
    local row = CreateFrame("Button", nil, p)
    row:SetSize(ProfileUI.W, ProfileUI.BIZ_ROW)
    row:SetPoint("TOPLEFT", p, "TOPLEFT", ProfileUI.X, ProfileUI.Y.biz - (i - 1) * ProfileUI.BIZ_ROW)
    row.bg = row:CreateTexture(nil, "BACKGROUND"); row.bg:SetAllPoints()
    ns.stripe(row.bg, i)
    row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(24, 24)
    row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    local function text(x, w, font, justify)
        local fs = row:CreateFontString(nil, "ARTWORK", font or ns.LABEL_FONT)
        fs:SetPoint("LEFT", row, "LEFT", x, 0); fs:SetWidth(w); fs:SetJustifyH(justify or "LEFT")
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        return fs
    end
    row.kind = text(32, 40)
    row.role = text(76, 40)
    row.title = text(120, 240)
    row.state = text(366, 100, ns.LABEL_FONT, "RIGHT")
    if row.SetHighlightTexture then row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD") end
    -- GF-016: a click opens the record itself; when its page no longer lists
    -- it, the personnel file stays and the tooltip says so.
    local function tip(self)
        if not self.item then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.item.title)
        GameTooltip:AddLine(ProfileUI.KIND[self.item.kind].name .. "｜" .. self.item.role .. "｜" .. self.item.stateName, 0.85, 0.85, 0.85)
        if self.missing == self.item.id then
            GameTooltip:AddLine(P().MISSING_TIP, 1, 0.82, 0)
            GameTooltip:AddLine(P().MISSING_DETAIL, 0.85, 0.85, 0.85)
        end
        GameTooltip:Show()
    end
    row:SetScript("OnClick", function(self)
        if not self.item then return end
        local opened, why = P().openBusiness(self.item)
        self.missing = (not opened and why == "missing") and self.item.id or nil
        if self.missing then tip(self) end
    end)
    row:SetScript("OnEnter", tip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

function ProfileUI.build(p)
    panel = p
    local X, Y = ProfileUI.X, ProfileUI.Y
    controls.head = header(p, "職責定位", X, Y.head)
    controls.mainLabel = fieldLabel(p, "主職責", X, Y.main - 6)
    controls.canLabel = fieldLabel(p, "可支援", X, Y.can - 6)
    controls.main, controls.can = {}, {}
    local x0 = X + 70
    for i, r in ipairs(P().ROLES) do
        local m = roleButton(p, r, function(self) if self.gfEnabled then P().setMain(r); ProfileUI.refresh() end end)
        m:SetPoint("TOPLEFT", p, "TOPLEFT", x0 + (i - 1) * ProfileUI.ROLE_STEP, Y.main)
        controls.main[r] = m
        local c = roleButton(p, r, function(self)
            if not self.gfEnabled then return end
            local own = P().own()
            P().setCan(r, not (own and own.can[r]))
            ProfileUI.refresh()
        end)
        c:SetPoint("TOPLEFT", p, "TOPLEFT", x0 + (i - 1) * ProfileUI.ROLE_STEP, Y.can)
        controls.can[r] = c
    end
    controls.unset = ns.OrdersUI.textButton(p, P().UNSET_NAME, function() P().setMain(nil); ProfileUI.refresh() end)
    controls.unset:SetPoint("TOPLEFT", p, "TOPLEFT", x0 + 3 * ProfileUI.ROLE_STEP, Y.main + 1)
    controls.share = ns.checkBox(p, "分享給公會", X, Y.share, function(on) P().setShare(on); ProfileUI.refresh() end)
    controls.bizHead = header(p, "我的業務", X, Y.bizHead)
    controls.rows = {}
    for i = 1, ProfileUI.BIZ_ROWS do controls.rows[i] = bizRow(p, i) end
    controls.bizEmpty = ns.freeText(p:CreateFontString(nil, "ARTWORK", ns.DISABLED_FONT))
    controls.bizEmpty:SetPoint("TOPLEFT", p, "TOPLEFT", X + 4, Y.biz - 8)
    controls.bizEmpty:SetText("沒有")
    controls.bizMore = ns.freeText(p:CreateFontString(nil, "ARTWORK", ns.DISABLED_FONT))
    controls.bizMore:SetPoint("TOPLEFT", p, "TOPLEFT", X + 4, Y.biz - ProfileUI.BIZ_ROWS * ProfileUI.BIZ_ROW - 4)
    -- 個人需求: the place is kept; shown once GF-009 registers (spec §5.1).
    controls.needsHead = header(p, "個人需求", X, Y.needs)
    controls.needsButton = ns.OrdersUI.textButton(p, "查看", function()
        local np = P().needsProvider
        if np and type(np.open) == "function" then pcall(np.open) end
    end)
    controls.needsButton:SetPoint("TOPLEFT", p, "TOPLEFT", X + 100, Y.needs + 4)
    ProfileUI.controls = controls
end

function ProfileUI.refresh()
    if not panel then return end
    local Pr = P()
    local own = Pr.own()
    local class = Pr.ownClass()
    for _, r in ipairs(Pr.ROLES) do
        local enabled = own ~= nil
        local suggested = Pr.suggested(class, r, true)
        drawRole(controls.main[r], own ~= nil and own.main == r, enabled, suggested)
        -- The main role is always in 可支援: shown on, not a switch.
        local isMain = own ~= nil and own.main == r
        drawRole(controls.can[r], own ~= nil and (own.can[r] == true or isMain), enabled and not isMain, suggested)
        if isMain then ns.OrdersUI.setSelected(controls.can[r], true) end
    end
    if own and own.main == nil then controls.unset:Disable() else controls.unset:Enable() end
    controls.share.set(own ~= nil and own.share == true)
    -- 我的業務
    local items = Pr.myBusiness()
    for i, row in ipairs(controls.rows) do
        local it = items[i]
        row.item = it
        if it then
            local k = ProfileUI.KIND[it.kind]
            ns.Icons.set(row.icon, "Interface\\Icons\\" .. k.art)
            if row.icon.SetTexCoord then row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
            row.kind:SetText(k.name)
            row.role:SetText(it.role)
            row.title:SetText(it.title)
            row.state:SetText(it.stateName)
            local c = it.closed and ns.COLOR.disabled or { 1, 1, 1 }
            row.title:SetTextColor(c[1], c[2], c[3])
            row.state:SetTextColor(c[1], c[2], c[3])
            row:Show()
        else
            row:Hide()
        end
    end
    if #items == 0 then controls.bizEmpty:Show() else controls.bizEmpty:Hide() end
    local extra = #items - ProfileUI.BIZ_ROWS
    controls.bizMore:SetText(extra > 0 and ("+" .. extra) or "")
    -- 個人需求
    local np = Pr.needsProvider
    if np then controls.needsHead:Show(); controls.needsButton:Show() else controls.needsHead:Hide(); controls.needsButton:Hide() end
end

---------------------------------------------------------------------------
-- Read-only card of a roster member (spec §5.1: 共用只讀角色卡)
---------------------------------------------------------------------------

-- Text for a member's roles: "坦克" / "未設定" / "未知", and 可支援 names.
function ProfileUI.rolesText(p)
    local Pr = P()
    local main = p.main and Pr.ROLE_NAME[p.main] or (p.state == "unknown" and Pr.UNKNOWN_NAME or Pr.UNSET_NAME)
    local can = {}
    for _, r in ipairs(Pr.ROLES) do if p.can[r] then can[#can + 1] = Pr.ROLE_NAME[r] end end
    return main, (#can > 0 and table.concat(can, "、") or (p.state == "unknown" and Pr.UNKNOWN_NAME or "無"))
end

function ProfileUI.openCard(m)
    if type(m) ~= "table" then return nil end
    local f = ProfileUI.card
    if not f then
        f = ns.popupWindow(ProfileUI.CARD_NAME, ProfileUI.CARD_W, ProfileUI.CARD_H)
        f:SetPoint("CENTER", 0, 60)
        f:EnableMouse(true)
        ns.exclusivePopup(f)
        f.classIcon = f:CreateTexture(nil, "ARTWORK"); f.classIcon:SetSize(40, 40)
        f.classIcon:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -48)
        f.name = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.TITLE_FONT))
        f.name:SetPoint("TOPLEFT", f, "TOPLEFT", 74, -50)
        f.info = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
        f.info:SetPoint("TOPLEFT", f, "TOPLEFT", 74, -74)
        fieldLabel(f, "主職責", 24, -118)
        f.mainIcon = f:CreateTexture(nil, "ARTWORK"); f.mainIcon:SetSize(28, 28)
        f.mainIcon:SetPoint("TOPLEFT", f, "TOPLEFT", 100, -112)
        f.mainText = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
        fieldLabel(f, "可支援", 24, -158)
        f.canIcons = {}
        for i = 1, 3 do
            local t = f:CreateTexture(nil, "ARTWORK"); t:SetSize(28, 28)
            t:SetPoint("TOPLEFT", f, "TOPLEFT", 100 + (i - 1) * 36, -152)
            f.canIcons[i] = t
        end
        f.canText = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
        f.canText:SetPoint("TOPLEFT", f, "TOPLEFT", 100 + 3 * 36 + 4, -158)
        fieldLabel(f, "專業", 24, -198)
        f.profs = {}
        for i = 1, 6 do
            local t = f:CreateTexture(nil, "ARTWORK"); t:SetSize(28, 28)
            t:SetPoint("TOPLEFT", f, "TOPLEFT", 100 + (i - 1) * 36, -192)
            f.profs[i] = t
        end
        f.profNone = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.DISABLED_FONT))
        f.profNone:SetPoint("TOPLEFT", f, "TOPLEFT", 100, -198)
        f.age = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.DISABLED_FONT))
        f.age:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 24, 22)
        f.close = ns.OrdersUI.textButton(f, "關閉", function() f:Hide() end, 96)
        f.close:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 18)
        f:Hide()
        ProfileUI.card = f
    end
    f.member = m
    if f.TitleText then f.TitleText:SetText("職工檔案") end
    local color = ns.Icons.classColor(m.classToken)
    ns.Icons.setClassIcon(f.classIcon, m.classToken)
    f.name:SetText(ns.shortName(m.name))
    f.name:SetTextColor(color[1], color[2], color[3])
    f.info:SetText(string.format("等級 %s　%s　%s", tostring(m.level or "?"), str(m.race), str(m.class)))
    local p = P().roles(m.guid)
    local mainName, canNames = ProfileUI.rolesText(p)
    if p.main then
        ns.GameIcons.set(f.mainIcon, ProfileUI.GAME[p.main])
        f.mainText:ClearAllPoints(); f.mainText:SetPoint("LEFT", f.mainIcon, "RIGHT", 6, 0)
    else
        f.mainIcon:Hide()
        f.mainText:ClearAllPoints(); f.mainText:SetPoint("TOPLEFT", f, "TOPLEFT", 100, -118)
    end
    f.mainText:SetText(mainName)
    local k = 0
    for _, r in ipairs(P().ROLES) do
        if p.can[r] then k = k + 1; ns.GameIcons.set(f.canIcons[k], ProfileUI.GAME[r]) end
    end
    for i = k + 1, 3 do f.canIcons[i]:Hide() end
    f.canText:ClearAllPoints()
    f.canText:SetPoint("TOPLEFT", f, "TOPLEFT", 100 + k * 36 + (k > 0 and 4 or 0), -158)
    f.canText:SetText(k > 0 and "" or canNames)
    -- Professions: the roster's shared detail (Recipes / Orders keep the real data).
    local detail = ns.UI and ns.UI.detailFor and ns.UI.detailFor(m)
    local list = detail and detail.professions or nil
    if not list then
        list = {}
        for _, name in ipairs(type(m.professions) == "table" and m.professions or {}) do list[#list + 1] = { name = str(name) } end
    end
    local shown = 0
    for i, t in ipairs(f.profs) do
        local prof = list[i]
        if prof and ns.Icons.setProfessionIcon(t, prof) then shown = shown + 1 else t:Hide() end
    end
    f.profNone:SetText(shown == 0 and "－" or "")
    f.age:SetText(P().ageText(p.at))
    f:Show()
    return f
end
