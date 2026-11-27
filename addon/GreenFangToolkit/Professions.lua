-- Professions (GF-001-D8): click your own profession to open its window.
--
-- Opening a profession window is a protected action, so every clickable spot
-- is a SecureActionButtonTemplate button with type="spell". Rules:
--   * Only professions that have a window: 鍛造、製皮、裁縫、工程學、鍊金術、
--     附魔、烹飪、急救, and 採礦 through its 熔煉 window.
--   * 草藥學、剝皮、釣魚 have no window and get no button. Fishing above all:
--     its spell starts fishing, so it must never be bound.
--   * The spell name comes from the client (C_Spell.GetSpellName and
--     fallbacks) via the skillLineID below; no localised text is hard-coded.
--   * Attributes, Show, Hide and anchors are only touched out of combat.
--     PLAYER_REGEN_DISABLED (fired just before the lockdown) hides and
--     unanchors every button, so nothing is clickable in combat.
--   * Buttons are parented to UIParent, not to the toolkit window, so the
--     window itself never becomes protected and still opens/closes in combat.
--   * Other members' professions never get a button (tooltip only).

local _, ns = ...
local str = ns.str

local Prof = {}
ns.Professions = Prof

-- skillLineID -> spell ID whose name (in the client's language) opens the
-- window. These are the first-rank spell IDs; casting by name uses the rank
-- the character knows.
Prof.WINDOW_SPELL = {
    [164] = 2018, -- 鍛造 Blacksmithing
    [165] = 2108, -- 製皮 Leatherworking
    [197] = 3908, -- 裁縫 Tailoring
    [202] = 4036, -- 工程學 Engineering
    [171] = 2259, -- 鍊金術 Alchemy
    [333] = 7411, -- 附魔 Enchanting
    [185] = 2550, -- 烹飪 Cooking
    [129] = 3273, -- 急救 First Aid
    [186] = 2656, -- 採礦 Mining -> 熔煉 Smelting
}
-- No window: never bound. 356 = fishing (its spell casts the line).
Prof.NO_WINDOW = { [182] = true, [393] = true, [356] = true }
-- Secondary professions (listed after the primary ones).
Prof.SECONDARY = { [185] = true, [129] = true, [356] = true }

function Prof.skillLineOf(prof)
    if type(prof) ~= "table" then return nil end
    return ns.num(prof.skillLineID) or ns.Data.skillLineIDFor(str(prof.name))
end

function Prof.isSecondary(prof)
    local id = Prof.skillLineOf(prof)
    return id ~= nil and Prof.SECONDARY[id] == true
end

-- The spell's name as the client spells it, or nil.
function Prof.spellName(spellID)
    if C_Spell and type(C_Spell.GetSpellName) == "function" then
        local name = str((ns.call(C_Spell.GetSpellName, spellID)))
        if name ~= "" then return name end
    end
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local info = ns.call(C_Spell.GetSpellInfo, spellID)
        if type(info) == "table" and str(info.name) ~= "" then return str(info.name) end
    end
    if type(GetSpellInfo) == "function" then -- old global (gone on 16001)
        local name = str((ns.call(GetSpellInfo, spellID)))
        if name ~= "" then return name end
    end
    return nil
end

-- Spell to cast for a profession's window, or nil (no window / unknown).
function Prof.windowSpell(prof)
    local id = Prof.skillLineOf(prof)
    if not id or Prof.NO_WINDOW[id] then return nil end
    local spellID = Prof.WINDOW_SPELL[id]
    if not spellID then return nil end
    return Prof.spellName(spellID)
end

-- Primary professions first, then secondary; order kept within each group.
function Prof.ordered(list)
    local primary, secondary = {}, {}
    for _, p in ipairs(type(list) == "table" and list or {}) do
        if Prof.isSecondary(p) then secondary[#secondary + 1] = p else primary[#primary + 1] = p end
    end
    for _, p in ipairs(secondary) do primary[#primary + 1] = p end
    return primary
end

---------------------------------------------------------------------------
-- Secure button pool, one set per owner ("character", "roster")
---------------------------------------------------------------------------

local sets = {}
Prof.sets = sets

-- One profession in a tooltip: its name, "rank / max" and the number of
-- recipes when known (GF-001-D19; roster icons and own-profession buttons).
function Prof.valueText(p)
    if type(p.rank) ~= "number" then return nil end
    if type(p.max) == "number" and p.max > 0 then return p.rank .. " / " .. p.max end
    return tostring(p.rank)
end

function Prof.addTooltipLines(tip, p, guid)
    tip:AddLine(str(p.name))
    local value = Prof.valueText(p)
    if value then tip:AddLine(value, 0.9, 0.9, 0.9) end
    local id = Prof.skillLineOf(p)
    local r = id and guid and ns.Recipes and ns.Recipes.of(guid, id)
    if r then tip:AddLine(string.format("配方 %d 個", #r.ids), 0.9, 0.9, 0.9) end
end

local function showTooltip(self)
    local p = self.gfProf
    if not p then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    -- GF-001-D19: the profession only, no hints.
    Prof.addTooltipLines(GameTooltip, p, ns.Data.player().guid)
    GameTooltip:Show()
end

local function newButton()
    local b = ns.createFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    if b.gfNoTemplate then -- client without the template: never clickable
        b:Hide()
        return b
    end
    -- Both so the click works whatever ActionButtonUseKeyDown is set to.
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetFrameStrata("DIALOG")
    b:SetAttribute("type", "spell")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
    b:SetScript("OnEnter", showTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    return b
end

-- Put button i of owner over region (x, y from its TOPLEFT, size w x h) for
-- prof. Returns true when a clickable button is shown. Out of combat only.
function Prof.bind(owner, i, region, prof, x, y, w, h)
    if ns.inCombat() then return false end
    local set = sets[owner]
    if not set then set = {}; sets[owner] = set end
    local b = set[i]
    if not b then b = newButton(); set[i] = b end
    local spell = Prof.windowSpell(prof)
    if not spell or b.gfNoTemplate then
        b.gfProf, b.gfSpell = nil, nil
        b:Hide()
        b:ClearAllPoints()
        return false
    end
    b:SetAttribute("spell", spell)
    b.gfProf, b.gfSpell = prof, spell
    -- GF-FIX-B: the button lives on UIParent; with the window scaled down
    -- (Theme.fit, 4:3 screens) it takes the region's scale, so x, y, w, h
    -- still cover the region's icon.
    local rs = region.GetEffectiveScale and ns.num((ns.call(region.GetEffectiveScale, region)))
    local us = UIParent.GetEffectiveScale and ns.num((ns.call(UIParent.GetEffectiveScale, UIParent)))
    if b.SetScale and rs and us and rs > 0 and us > 0 then b:SetScale(rs / us) end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", region, "TOPLEFT", x, y)
    b:SetSize(w, h)
    if region.GetFrameLevel then
        local level = ns.num((ns.call(region.GetFrameLevel, region)))
        if level then b:SetFrameLevel(level + 5) end
    end
    b:Show()
    return true
end

-- Hide owner's buttons from index i on. Out of combat only.
function Prof.hideFrom(owner, i)
    if ns.inCombat() then return end
    local set = sets[owner] or {}
    for k = i or 1, #set do
        ns.hideTooltipOf(set[k])
        set[k]:Hide()
        set[k]:ClearAllPoints()
    end
end

-- PLAYER_REGEN_DISABLED: the last moment protected frames may be changed.
-- Hide and unanchor everything so nothing is clickable during combat.
function Prof.hideAll()
    for _, set in pairs(sets) do
        for _, b in ipairs(set) do
            b:Hide()
            b:ClearAllPoints()
        end
    end
end

-- Buttons currently shown (tests and the manual check).
function Prof.shown(owner)
    local list = {}
    for _, b in ipairs(sets[owner] or {}) do
        if b:IsShown() then list[#list + 1] = b end
    end
    return list
end
