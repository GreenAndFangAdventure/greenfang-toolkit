-- GameIcons (GF-002-C, 0.12.1): the game's own art for roles, dungeons,
-- time and paging, each with a fallback (as Icons.lua): a file the client
-- does not have (SetTexture returns false) falls through to the next
-- candidate, and the last one is an icon every 1.x client ships. Nothing
-- is packaged with the AddOn and nothing comes from other addons.
--
-- 16001 (ForeverAPI) has no texture list, so none of the group finder
-- files below is verified; the client does ship Blizzard_GroupFinder
-- (LFGFrame/LFDFrame), so they are likely there. tests/addon/MANUAL.md §3x.

local _, ns = ...
local str = ns.str

local G = {}
ns.GameIcons = G

local ROLES_FILE = "Interface\\LFGFrame\\UI-LFG-ICON-ROLES"
-- Pixel boxes in the 64x64 role sheet (the same as the game's GetTexCoordsForRole).
local ROLE_BOX = { t = { 0, 19, 22, 41 }, h = { 20, 39, 1, 20 }, d = { 20, 39, 22, 41 } }

-- Each entry: a list of candidates { file, box = { l, r, t, b } in 64ths } tried in order.
G.ART = {
    -- GF-002-F: whole spell icons first (the role sheet came out dark and cut in
    -- half on 16001: its layout differs), the role sheet as a fallback.
    role_t = { { "Interface\\Icons\\Ability_Warrior_DefensiveStance" }, { "Interface\\Icons\\Ability_Defend" },
        { ROLES_FILE, box = ROLE_BOX.t } },
    role_h = { { "Interface\\Icons\\Spell_Holy_FlashHeal" }, { "Interface\\Icons\\Spell_Holy_Heal" },
        { ROLES_FILE, box = ROLE_BOX.h } },
    role_d = { { "Interface\\Icons\\Ability_DualWield" }, { "Interface\\Icons\\INV_Sword_04" },
        { ROLES_FILE, box = ROLE_BOX.d } },
    -- GF-002-G (owner: 「組隊與人數的圖標，採用社交那種人頭或多人頭」): the
    -- social window's portraits: one head for a person / the number of people,
    -- several heads for forming a group.
    person = { { "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon" }, { "Interface\\Icons\\INV_Misc_GroupLooking" },
        { "Interface\\Icons\\INV_Misc_Head_Human_01" } },
    group = { { "Interface\\Icons\\INV_Misc_GroupNeedMore" }, { "Interface\\FriendsFrame\\UI-Toast-ChatInviteIcon" },
        { "Interface\\Icons\\Ability_Warrior_BattleShout" } },
    quest = { { "Interface\\Icons\\INV_Misc_Note_01" } },
    now = { { "Interface\\Icons\\Spell_Nature_TimeStop" } },
    today = { { "Interface\\Icons\\INV_Misc_PocketWatch_01" }, { "Interface\\Icons\\Spell_Nature_TimeStop" } },
    -- GF-002-F: the calendar button art came out as a stretched pill; a book (an agenda).
    future = { { "Interface\\Icons\\INV_Misc_Book_09" }, { "Interface\\Icons\\INV_Misc_Note_01" } },
    key = { { "Interface\\Icons\\INV_Misc_Key_03" } },
    prev = { { "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up" } },
    next = { { "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up" } },
    yes = { { "Interface\\RaidFrame\\ReadyCheck-Ready" } },
    no = { { "Interface\\RaidFrame\\ReadyCheck-NotReady" } },
    paste = { { "Interface\\Icons\\INV_Scroll_03" } },
    received = { { "Interface\\Icons\\INV_Letter_15" } },
    placed = { { "Interface\\Icons\\INV_Misc_Note_02" } },
    -- GF-002-E (owner: 「有些圖示與主題不合」): each picked for its meaning;
    -- the table with the reasons is tests/addon/MANUAL.md §3z.
    -- 職工單 = "I want to join": a raised open hand.
    worker = { { "Interface\\Icons\\Spell_Holy_SealOfSalvation" }, { "Interface\\Icons\\INV_Scroll_05" },
        { "Interface\\Icons\\INV_Misc_Note_01" } },
    -- 冒險單 = going on an adventure: a map.
    adventure = { { "Interface\\Icons\\INV_Misc_Map_01" }, { "Interface\\Icons\\INV_Sword_04" } },
    -- 調整 (the number of people): the group finder's "need more" group.
    adjust = { { "Interface\\Icons\\INV_Misc_GroupLooking" }, { "Interface\\Buttons\\UI-PlusButton-Up" } },
    -- The game's group finder (尋求組隊).
    lfg = { { "Interface\\LFGFrame\\BattlenetWorking0" }, { "Interface\\Icons\\INV_Misc_Spyglass_02" },
        { "Interface\\Icons\\INV_Misc_GroupLooking" } },
    -- 直接錄取 = in at once: the green check; 團長同意 = the leader decides: the leader's crown.
    direct = { { "Interface\\RaidFrame\\ReadyCheck-Ready" } },
    consent = { { "Interface\\GroupFrame\\UI-Group-LeaderIcon" }, { "Interface\\RaidFrame\\ReadyCheck-Waiting" } },
    -- Tags: 解任務 the quest "!", 連刷 the round arrows (again and again), 慢慢打 a turtle,
    -- 速刷 a running boot (Sprint), 語音 a shout.
    tag_quest = { { "Interface\\GossipFrame\\AvailableQuestIcon" }, { "Interface\\Icons\\INV_Misc_Note_01" } },
    tag_farm = { { "Interface\\Buttons\\UI-RefreshButton" }, { "Interface\\Icons\\Spell_Nature_Reincarnation" } },
    tag_slow = { { "Interface\\Icons\\Ability_Hunter_Pet_Turtle" }, { "Interface\\Icons\\Spell_Nature_Sleep" } },
    tag_fast = { { "Interface\\Icons\\Ability_Rogue_Sprint" }, { "Interface\\Icons\\INV_Gauntlets_04" } },
    tag_voice = { { "Interface\\Icons\\Ability_Warrior_BattleShout" }, { "Interface\\Icons\\INV_Misc_Horn_01" } },
    -- 我的服務 (crafter settings): the smith's hammer.
    services = { { "Interface\\Icons\\Trade_BlackSmithing" }, { "Interface\\Icons\\INV_Hammer_20" } },
    -- ＋下單 (place an order): a letter (an order sent to a crafter).
    order = { { "Interface\\Icons\\INV_Letter_15" }, { "Interface\\Icons\\INV_Misc_Note_02" } },
}

-- Group finder dungeon art (LFGIcon-<name>), the key when the client has none.
local LFG = "Interface\\LFGFrame\\LFGIcon-"
G.DUNGEON_FILE = {
    rfc = "RagefireChasm", wc = "WailingCaverns", dm = "Deadmines", sfk = "ShadowFangKeep",
    bfd = "BlackfathomDeeps", stk = "StormwindStockades", gnr = "Gnomeregan", rfk = "RazorfenKraul",
    smg = "ScarletMonastery", sml = "ScarletMonastery", sma = "ScarletMonastery", smc = "ScarletMonastery",
    rfd = "RazorfenDowns", ul = "Uldaman", zf = "ZulFarak", mar = "Maraudon", st = "SunkenTemple",
    brd = "BlackrockDepths", lbrs = "BlackrockSpire", ubrs = "BlackrockSpire",
    dme = "DireMaul", dmw = "DireMaul", dmn = "DireMaul", strat = "Stratholme", scholo = "Scholomance",
}
for id, name in pairs(G.DUNGEON_FILE) do
    G.ART["dungeon_" .. id] = { { LFG .. name }, { "Interface\\Icons\\INV_Misc_Key_03" } }
end

local function coords(box)
    if not box then return 0, 1, 0, 1 end
    return box[1] / 64, box[2] / 64, box[3] / 64, box[4] / 64
end

-- Does the client have this file? One hidden probe texture, results cached.
local probe, known = nil, {}
function G.has(file)
    if known[file] ~= nil then return known[file] end
    if not probe then
        local f = CreateFrame("Frame")
        probe = f:CreateTexture(nil, "ARTWORK")
    end
    known[file] = ns.Icons.set(probe, file)
    return known[file]
end
function G.reset() known = {} end

-- The first candidate the client has: candidate, index. nil for an unknown key.
function G.pick(key)
    local list = G.ART[key]
    if not list then return nil end
    for i, c in ipairs(list) do
        if G.has(c[1]) then return c, i end
    end
    return list[#list], #list
end

-- Put art on a texture: true when one of the candidates worked.
function G.set(tex, key)
    if not tex then return false end
    local list = G.ART[key]
    if not list then tex:Hide(); return false end
    for _, c in ipairs(list) do
        if ns.Icons.set(tex, c[1]) then
            if tex.SetTexCoord then tex:SetTexCoord(coords(c.box)) end
            tex:Show()
            return true
        end
    end
    tex:Hide()
    return false
end

-- Inline markup for a FontString ("|T...|t"), using the first file the client has.
function G.markup(key, size)
    size = size or 14
    local c = G.pick(key)
    if not c then return "" end
    if c.box then
        return string.format("|T%s:%d:%d:0:0:64:64:%d:%d:%d:%d|t", c[1], size, size, c.box[1], c.box[2], c.box[3], c.box[4])
    end
    return "|T" .. c[1] .. ":" .. size .. "|t"
end

function G.dungeonKey(id) return G.ART["dungeon_" .. str(id)] and ("dungeon_" .. id) or "key" end

-- Level colour for a dungeon (R-4.1, GF-002-C item 8): fits = white, too low
-- for me = grey (I out-level it), too high = red. r, g, b.
function G.levelColor(id, level)
    local d = ns.AdventureData.byId[id]
    if not d or type(level) ~= "number" then return 1, 1, 1 end
    if level > d.max + ns.AdventureData.LEVEL_SLACK then return 0.55, 0.55, 0.55 end
    if level < d.min - ns.AdventureData.LEVEL_SLACK then return 1, 0.3, 0.3 end
    return 1, 1, 1
end
