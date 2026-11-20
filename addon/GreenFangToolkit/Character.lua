-- Character module (GF-001-D6): the logged-in character at a glance, with a
-- class icon and one icon plus progress bar (current / max skill) per
-- profession. Uses only built-in textures (Icons.lua). Works in any guild.
-- GF-001-D8: clicking a profession that has a window opens it (a secure
-- spell button laid over the row, Professions.lua); not in combat.

local _, ns = ...
local str = ns.str
local Icons = ns.Icons

local Character = {}
ns.Character = Character

local MAX_ROWS = 6
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local panel, classIcon, nameLine, infoLine, guildLine, locationLine, profTitle, emptyLine
local profRows = {}

-- "151 / 225", or just the current value when the maximum is unknown.
function Character.skillText(p)
    if type(p.rank) ~= "number" then return "未知" end
    if type(p.max) == "number" and p.max > 0 then return string.format("%d / %d", p.rank, p.max) end
    return tostring(p.rank)
end

-- 0..1 fill of the bar, or nil when there is no maximum to compare with.
function Character.skillFraction(p)
    if type(p.rank) ~= "number" or type(p.max) ~= "number" or p.max <= 0 then return nil end
    return math.max(0, math.min(1, p.rank / p.max))
end

-- "配方 120 個", or "" (GF-001-D19: no times, no hints).
function Character.recipeText(prof)
    local id = ns.Professions.skillLineOf(prof)
    if not (id and ns.Recipes and ns.Recipes.CRAFTS[id]) then return "" end
    local r = ns.Recipes.of(ns.Data.player().guid, id)
    if not r then return "" end
    return string.format("配方 %d 個", #r.ids)
end

function Character.locationText()
    local loc = ns.Data.location()
    if not loc then return "所在地：目前無法取得" end
    local text = loc.subZone and (loc.zone .. "，" .. loc.subZone) or loc.zone
    return "所在地：" .. text
end

local function newProfRow(i)
    local row = CreateFrame("Frame", nil, panel)
    row:SetSize(560, 40)
    row:SetPoint("TOPLEFT", panel, "TOPLEFT", 22, -176 - (i - 1) * 46)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(36, 36)
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 46, -2)
    row.name:SetWidth(200)
    row.name:SetJustifyH("LEFT")
    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetSize(380, 14)
    row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 46, 4)
    row.bar:SetStatusBarTexture(BAR_TEXTURE)
    row.bar:SetStatusBarColor(0.33, 0.78, 0.55)
    row.bar:SetMinMaxValues(0, 1)
    row.barBg = row.bar:CreateTexture(nil, "BACKGROUND")
    row.barBg:SetAllPoints()
    row.barBg:SetColorTexture(0, 0, 0, 0.45)
    row.value = row.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.value:SetPoint("CENTER", row.bar, "CENTER", 0, 0)
    row.recipes = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    row.recipes:SetPoint("TOPLEFT", row, "TOPLEFT", 250, -4)
    row.recipes:SetWidth(300)
    row.recipes:SetJustifyH("LEFT")
    row.valueOnly = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.valueOnly:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 46, 4)
    profRows[i] = row
    return row
end

function Character.refresh()
    if not panel then return end
    local p = ns.Sync.player()
    local color = Icons.classColor(p.classToken)
    Icons.setClassIcon(classIcon, p.classToken)
    nameLine:SetText(str(p.name) ~= "" and p.name or "未知角色")
    nameLine:SetTextColor(color[1], color[2], color[3])
    infoLine:SetText(string.format("等級 %s　%s　%s",
        p.level and tostring(p.level) or "?", str(p.race), str(p.class)))
    if p.guild then
        guildLine:SetText(string.format("公會：%s　會階：%s", p.guild, str(p.guildRank) ~= "" and p.guildRank or "未知"))
    else
        guildLine:SetText("公會：無")
    end
    locationLine:SetText(Character.locationText())
    local profs = ns.Professions.ordered((ns.Data.ownProfessionsDetailed()))
    emptyLine:SetText(#profs == 0 and "還沒有學專業技能。" or "")
    for i = 1, math.min(#profs, MAX_ROWS) do
        local prof = profs[i]
        local row = profRows[i] or newProfRow(i)
        local hasIcon = Icons.setProfessionIcon(row.icon, prof)
        row.name:ClearAllPoints()
        row.name:SetPoint("TOPLEFT", row, "TOPLEFT", hasIcon and 46 or 0, -2)
        row.name:SetText(prof.name)
        local fraction = Character.skillFraction(prof)
        row.bar:ClearAllPoints()
        row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", hasIcon and 46 or 0, 4)
        if fraction then
            row.bar:SetMinMaxValues(0, prof.max)
            row.bar:SetValue(prof.rank)
            row.value:SetText(Character.skillText(prof))
            row.bar:Show()
            row.valueOnly:SetText("")
        else
            row.bar:Hide()
            row.valueOnly:SetText("技能點：" .. Character.skillText(prof))
        end
        row.recipes:SetText(Character.recipeText(prof))
        row:Show()
        -- Secure spell button over the row (only professions with a window).
        ns.Professions.bind("character", i, row, prof, 0, 0, 560, 40)
    end
    for i = #profs + 1, #profRows do profRows[i]:Hide() end
    ns.Professions.hideFrom("character", math.min(#profs, MAX_ROWS) + 1)
end

local function build(p)
    panel = p
    classIcon = p:CreateTexture(nil, "ARTWORK")
    classIcon:SetSize(52, 52)
    classIcon:SetPoint("TOPLEFT", p, "TOPLEFT", 22, -40)
    nameLine = p:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    nameLine:SetPoint("TOPLEFT", p, "TOPLEFT", 86, -42)
    nameLine:SetJustifyH("LEFT")
    infoLine = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    infoLine:SetPoint("TOPLEFT", p, "TOPLEFT", 86, -66)
    infoLine:SetJustifyH("LEFT")
    guildLine = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    guildLine:SetPoint("TOPLEFT", p, "TOPLEFT", 22, -104)
    guildLine:SetWidth(900)
    guildLine:SetJustifyH("LEFT")
    locationLine = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    locationLine:SetPoint("TOPLEFT", p, "TOPLEFT", 22, -124)
    locationLine:SetWidth(900)
    locationLine:SetJustifyH("LEFT")
    profTitle = p:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    profTitle:SetPoint("TOPLEFT", p, "TOPLEFT", 22, -152)
    profTitle:SetText("專業技能")
    emptyLine = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    emptyLine:SetPoint("TOPLEFT", p, "TOPLEFT", 22, -176)
    -- The buttons live on UIParent: hide them with the page (out of combat;
    -- in combat they are already hidden).
    p:HookScript("OnHide", function() ns.Professions.hideFrom("character", 1) end)
end

ns.Sync.onChange(function()
    if panel and ns.Framework.isModuleShown("character") then Character.refresh() end
end)
ns.Share.onUpdate(function(a)
    if a == ns.Share.selfAuthor() and panel and ns.Framework.isModuleShown("character") then
        Character.refresh()
    end
end)

ns.Framework.register({
    id = "character",
    title = "我的角色",
    order = 15,
    create = build,
    show = Character.refresh,
})
