-- Icons: built-in game textures for professions and classes, plus class
-- colours. Nothing is packaged with the AddOn; every path is a texture the
-- client already ships. Each lookup has a fallback, and a texture the client
-- does not have (SetTexture returns false) falls back to plain text.
--
-- 16001 notes (docs/research/forever-api-16001.md, GF-001-D6):
--   * C_ClassColor.GetClassColor is verified in ForeverAPI; RAID_CLASS_COLORS
--     and CLASS_ICON_TCOORDS are FrameXML tables that ForeverAPI does not list,
--     so both have built-in copies below.
--   * StatusBar is a verified widget type.

local _, ns = ...

local Icons = {}
ns.Icons = Icons

-- skillLineID -> built-in icon. Used for roster members, where only the
-- profession name (or club skillLineID) is known. The logged-in character's
-- own professions use the icon GetProfessionInfo returns.
Icons.PROFESSION = {
    [164] = "Interface\\Icons\\Trade_BlackSmithing",
    [165] = "Interface\\Icons\\Trade_LeatherWorking",
    [171] = "Interface\\Icons\\Trade_Alchemy",
    [182] = "Interface\\Icons\\Trade_Herbalism",
    [186] = "Interface\\Icons\\Trade_Mining",
    [197] = "Interface\\Icons\\Trade_Tailoring",
    [202] = "Interface\\Icons\\Trade_Engineering",
    [333] = "Interface\\Icons\\Trade_Engraving",
    [393] = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
    [129] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
    [185] = "Interface\\Icons\\INV_Misc_Food_15",
    [356] = "Interface\\Icons\\Trade_Fishing",
    [755] = "Interface\\Icons\\INV_Misc_Gem_01",
    [773] = "Interface\\Icons\\INV_Inscription_Tradeskill01",
}

-- Profession icon from a skillLineID or a (zhTW or English) name; nil if unknown.
function Icons.professionIcon(nameOrID)
    local id = ns.num(nameOrID)
    if not id then id = ns.Data.skillLineIDFor(ns.str(nameOrID)) end
    return id and Icons.PROFESSION[id] or nil
end

-- One icon per class (Mainline ships these); the character-creation sheet
-- with texture coordinates is the fallback.
Icons.CLASS_FILE = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue",
    PRIEST = "Priest", DEATHKNIGHT = "DeathKnight", SHAMAN = "Shaman", MAGE = "Mage",
    WARLOCK = "Warlock", MONK = "Monk", DRUID = "Druid", DEMONHUNTER = "DemonHunter",
    EVOKER = "Evoker",
}
Icons.CLASS_SHEET = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
Icons.CLASS_TCOORDS = {
    WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.49609375, 0, 0.25 },
    ROGUE = { 0.49609375, 0.7421875, 0, 0.25 }, DRUID = { 0.7421875, 0.98828125, 0, 0.25 },
    HUNTER = { 0, 0.25, 0.25, 0.5 }, SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
    PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 }, WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 },
    PALADIN = { 0, 0.25, 0.5, 0.75 }, DEATHKNIGHT = { 0.25, 0.49609375, 0.5, 0.75 },
    MONK = { 0.49609375, 0.7421875, 0.5, 0.75 }, DEMONHUNTER = { 0.7421875, 0.98828125, 0.5, 0.75 },
}

-- Standard class colours, used when the client provides none.
Icons.CLASS_COLOR = {
    WARRIOR = { 0.78, 0.61, 0.43 }, PALADIN = { 0.96, 0.55, 0.73 }, HUNTER = { 0.67, 0.83, 0.45 },
    ROGUE = { 1.00, 0.96, 0.41 }, PRIEST = { 1.00, 1.00, 1.00 }, DEATHKNIGHT = { 0.77, 0.12, 0.23 },
    SHAMAN = { 0.00, 0.44, 0.87 }, MAGE = { 0.25, 0.78, 0.92 }, WARLOCK = { 0.53, 0.53, 0.93 },
    MONK = { 0.00, 1.00, 0.60 }, DRUID = { 1.00, 0.49, 0.04 }, DEMONHUNTER = { 0.64, 0.19, 0.79 },
    EVOKER = { 0.20, 0.58, 0.50 },
}
Icons.DEFAULT_COLOR = { 0.9, 0.9, 0.9 }

local function rgb(c)
    if type(c) ~= "table" then return nil end
    local r, g, b = ns.num(c.r), ns.num(c.g), ns.num(c.b)
    if r and g and b then return { r, g, b } end
    return nil
end

-- { r, g, b } for a class token.
function Icons.classColor(token)
    token = ns.str(token)
    if token == "" then return Icons.DEFAULT_COLOR end
    if C_ClassColor and type(C_ClassColor.GetClassColor) == "function" then
        local c = rgb((ns.call(C_ClassColor.GetClassColor, token)))
        if c then return c end
    end
    if type(RAID_CLASS_COLORS) == "table" then
        local c = rgb(RAID_CLASS_COLORS[token])
        if c then return c end
    end
    return Icons.CLASS_COLOR[token] or Icons.DEFAULT_COLOR
end

-- SetTexture that reports whether the client has the file.
function Icons.set(tex, path)
    if not tex or path == nil then return false end
    local ok, result = pcall(tex.SetTexture, tex, path)
    return ok and result ~= false
end

-- Put a class icon on a texture; returns false (and hides it) if none works.
function Icons.setClassIcon(tex, token)
    token = ns.str(token)
    if not tex then return false end
    local file = Icons.CLASS_FILE[token]
    if file and Icons.set(tex, "Interface\\Icons\\ClassIcon_" .. file) then
        tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        tex:Show()
        return true
    end
    local coords = (type(CLASS_ICON_TCOORDS) == "table" and type(CLASS_ICON_TCOORDS[token]) == "table"
        and CLASS_ICON_TCOORDS[token]) or Icons.CLASS_TCOORDS[token]
    if coords and Icons.set(tex, Icons.CLASS_SHEET) then
        tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        tex:Show()
        return true
    end
    tex:Hide()
    return false
end

---------------------------------------------------------------------------
-- GF-UI-K (owner, 0.16.6): the personnel file's picture is the game's own race
-- head: a male character gets the orc (then goblin) head, a female character
-- the 天裔精靈 head (Forever's new race). Only atlases the client ships; each
-- is checked with C_Texture.GetAtlasInfo and the class icon stays otherwise.
-- 天裔精靈's internal race file is not known offline: the guild roster data has
-- raceID 96 (塑風者天裔精靈) and 95 (高天盟天裔精靈), and the client gives
-- the file name (C_CreatureInfo.GetRaceInfo(id).clientFileString) at run time.
-- Not verified in game (MANUAL GF-UI-K); /gftk probe lists what exists.
---------------------------------------------------------------------------

Icons.PORTRAIT_MALE = { "raceicon128-orc-male", "raceicon-orc-male", "raceicon128-goblin-male", "raceicon-goblin-male" }
Icons.PORTRAIT_FEMALE_RACES = { 96, 95 }
Icons.SEX_MALE, Icons.SEX_FEMALE = 2, 3 -- UnitSex

function Icons.atlasExists(name)
    local ct = rawget(_G, "C_Texture")
    if type(name) ~= "string" or type(ct) ~= "table" or type(ct.GetAtlasInfo) ~= "function" then return false end
    local ok, info = pcall(ct.GetAtlasInfo, name)
    return ok and info ~= nil and info ~= false
end

-- The race file of a raceID (lower case), or nil.
function Icons.raceFile(raceID)
    local ci = rawget(_G, "C_CreatureInfo")
    if type(ci) ~= "table" or type(ci.GetRaceInfo) ~= "function" then return nil end
    local ok, info = pcall(ci.GetRaceInfo, raceID)
    local file = ok and type(info) == "table" and info.clientFileString or nil
    return type(file) == "string" and file ~= "" and file:lower() or nil
end

-- The atlas names to try for a sex (UnitSex: 2 male, 3 female), in order.
function Icons.portraitAtlases(sex)
    if sex == Icons.SEX_MALE then return Icons.PORTRAIT_MALE end
    local out = {}
    if sex == Icons.SEX_FEMALE then
        for _, id in ipairs(Icons.PORTRAIT_FEMALE_RACES) do
            local file = Icons.raceFile(id)
            if file then
                out[#out + 1] = "raceicon128-" .. file .. "-female"
                out[#out + 1] = "raceicon-" .. file .. "-female"
            end
        end
    end
    return out
end

-- The race head for sex, else the class icon. Returns "atlas", name / "class".
function Icons.setPortrait(tex, sex, classToken)
    if not tex then return nil end
    if tex.SetAtlas then
        for _, name in ipairs(Icons.portraitAtlases(sex)) do
            if Icons.atlasExists(name) and pcall(tex.SetAtlas, tex, name) then
                tex:Show()
                return "atlas", name
            end
        end
    end
    if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
    Icons.setClassIcon(tex, classToken)
    return "class"
end

-- Put a profession icon on a texture: the client's own icon first (file ID or
-- path from GetProfessionInfo), else the built-in table. False = use text.
function Icons.setProfessionIcon(tex, prof)
    if not tex then return false end
    local name = type(prof) == "table" and prof.name or prof
    local candidates = {}
    if type(prof) == "table" and (type(prof.icon) == "number" or type(prof.icon) == "string") then
        candidates[#candidates + 1] = prof.icon
    end
    local fromTable = Icons.professionIcon(type(prof) == "table" and (prof.skillLineID or name) or name)
    if fromTable then candidates[#candidates + 1] = fromTable end
    for _, path in ipairs(candidates) do
        if Icons.set(tex, path) then
            tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            tex:Show()
            return true
        end
    end
    tex:Hide()
    return false
end
