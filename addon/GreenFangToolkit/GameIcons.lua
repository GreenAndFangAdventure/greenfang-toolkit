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
-- GF-002-J: the group finder's round role portraits (same layout as the sheet above)
-- and the LFG role strip (four icons side by side: leader, dps, tank, healer).
local PORTRAIT_FILE = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local LFGROLE_FILE = "Interface\\LFGFrame\\LFGRole"
local LFGROLE_BOX = { t = { 32, 48, 0, 64 }, h = { 48, 64, 0, 64 }, d = { 16, 32, 0, 64 } }
-- Square spell / item icons: cut the dark border (GF-UI-A §1.4 item 5; owner 0.14.0:
-- no black square on the buttons): 0.08 - 0.92, in 64ths 5 - 59.
G.ICON_CROP = { 0.08, 0.92, 0.08, 0.92 }

-- Each entry: a list of candidates { file, box = { l, r, t, b } in 64ths } tried in order.
G.ART = {
    -- GF-002-F: whole spell icons first (the role sheet came out dark and cut in
    -- half on 16001: its layout differs), the role sheet as a fallback.
    -- GF-002-J (owner 0.14.0: 「職責用遊戲同款圓形圖示、不要文字」): the round role
    -- icons of the group finder first (their place in the sheet from the client's own
    -- GetTexCoordsForRoleSmallCircle when it has it), the LFG role strip next, then
    -- the whole spell icons (GF-002-F) and the old sheet.
    role_t = { { PORTRAIT_FILE, box = ROLE_BOX.t, role = "TANK" }, { LFGROLE_FILE, box = LFGROLE_BOX.t },
        { "Interface\\Icons\\Ability_Warrior_DefensiveStance" }, { "Interface\\Icons\\Ability_Defend" },
        { ROLES_FILE, box = ROLE_BOX.t } },
    role_h = { { PORTRAIT_FILE, box = ROLE_BOX.h, role = "HEALER" }, { LFGROLE_FILE, box = LFGROLE_BOX.h },
        { "Interface\\Icons\\Spell_Holy_FlashHeal" }, { "Interface\\Icons\\Spell_Holy_Heal" },
        { ROLES_FILE, box = ROLE_BOX.h } },
    role_d = { { PORTRAIT_FILE, box = ROLE_BOX.d, role = "DAMAGER" }, { LFGROLE_FILE, box = LFGROLE_BOX.d },
        { "Interface\\Icons\\Ability_DualWield" }, { "Interface\\Icons\\INV_Sword_04" },
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
    wait = { { "Interface\\RaidFrame\\ReadyCheck-Waiting" } }, -- GF-002-I: ⏳ in the checklists
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
    -- GF-002-H: 定案 = the date is sealed: a rolled scroll; 行事曆 = an agenda book.
    final = { { "Interface\\Icons\\INV_Scroll_04" }, { "Interface\\Icons\\INV_Scroll_03" }, { "Interface\\RaidFrame\\ReadyCheck-Ready" } },
    calendar = { { "Interface\\Icons\\INV_Misc_Book_11" }, { "Interface\\Icons\\INV_Misc_Book_09" }, { "Interface\\Icons\\INV_Misc_PocketWatch_01" } },
    -- 我的服務 (crafter settings): the smith's hammer.
    services = { { "Interface\\Icons\\Trade_BlackSmithing" }, { "Interface\\Icons\\INV_Hammer_20" } },
    -- ＋下單 (place an order): a letter (an order sent to a crafter).
    order = { { "Interface\\Icons\\INV_Letter_15" }, { "Interface\\Icons\\INV_Misc_Note_02" } },
    -- GF-002-I (spec §17, design review GF-UI-A §1.4 / §1.7; MANUAL §3ae): the state
    -- badges, 退回, 規則, the arrow of the rules card, 邀請, a raid's fallback.
    state_open = { { "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon" }, { "Interface\\Icons\\INV_Misc_GroupLooking" },
        { "Interface\\Icons\\INV_Misc_Head_Human_01" } },
    state_final = { { "Interface\\Icons\\INV_Scroll_04" }, { "Interface\\Icons\\INV_Scroll_03" }, { "Interface\\RaidFrame\\ReadyCheck-Ready" } },
    state_formed = { { "Interface\\Icons\\INV_Misc_GroupNeedMore" }, { "Interface\\FriendsFrame\\UI-Toast-ChatInviteIcon" },
        { "Interface\\Icons\\Ability_Warrior_BattleShout" } },
    state_done = { { "Interface\\RaidFrame\\ReadyCheck-Ready" } },
    -- 過期 = the time ran out: Borrowed Time (an hourglass), a watch, then the waiting mark.
    state_ended = { { "Interface\\Icons\\Spell_Holy_BorrowedTime" }, { "Interface\\Icons\\INV_Misc_PocketWatch_02" },
        { "Interface\\RaidFrame\\ReadyCheck-Waiting" } },
    -- 未成行 = formed but never went: lying down (Feign Death).
    state_unfinished = { { "Interface\\Icons\\Ability_Rogue_FeignDeath" }, { "Interface\\RaidFrame\\ReadyCheck-NotReady" } },
    state_cancel = { { "Interface\\RaidFrame\\ReadyCheck-NotReady" } },
    -- A worker ticket that is up (上架): the same raised hand as 職工單.
    state_worker = { { "Interface\\Icons\\Spell_Holy_SealOfSalvation" }, { "Interface\\Icons\\INV_Scroll_05" },
        { "Interface\\Icons\\INV_Misc_Note_01" } },
    -- 退回 = a step back (Feint), then the page-back arrow.
    back = { { "Interface\\Icons\\Ability_Rogue_Feint" }, { "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up" } },
    rules = { { "Interface\\Icons\\INV_Misc_QuestionMark" } },
    -- 重開 (the same as the row button, AdventureUI.ICON.reopen) for the rules card.
    reopen = { { "Interface\\Buttons\\UI-RefreshButton" }, { "Interface\\Icons\\Spell_Nature_Reincarnation" } },
    arrow = { { "Interface\\ChatFrame\\ChatFrameExpandArrow" }, { "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up" } },
    -- 邀請 (design review §1.4: the letter stays for orders): a group prayer.
    invite = { { "Interface\\Icons\\Spell_Holy_PrayerOfSpirit" }, { "Interface\\Icons\\INV_Letter_15" } },
    raid = { { "Interface\\Icons\\INV_Misc_Head_Dragon_01" }, { "Interface\\Icons\\INV_Misc_Key_03" } },
    -- GF-002-I (R-17.19): 自動 (group / elite quests): an elite's black dragon head.
    elite = { { "Interface\\Icons\\INV_Misc_Head_Dragon_Black" }, { "Interface\\Icons\\Ability_Warrior_Rampage" },
        { "Interface\\Icons\\INV_Misc_QuestionMark" } },
}

-- Group finder dungeon art (LFGIcon-<name>), the key when the client has none.
-- GF-002-I (R-17.14): the names come from AdventureData's icon field; it calls
-- registerDungeons when it loads (and again after Data.add).
local LFG = "Interface\\LFGFrame\\LFGIcon-"
G.DUNGEON_FILE = {}
function G.registerDungeons(list)
    for _, d in ipairs(list or {}) do
        if d.icon then
            G.DUNGEON_FILE[d.id] = d.icon
            local art = { { LFG .. d.icon } }
            if d.category == "raid" then art[#art + 1] = { G.ART.raid[1][1] } end
            art[#art + 1] = { "Interface\\Icons\\INV_Misc_Key_03" }
            G.ART["dungeon_" .. d.id] = art
        end
    end
end

local function isSquareIcon(file) return type(file) == "string" and file:find("^Interface\\Icons\\") ~= nil end
G.isSquareIcon = isSquareIcon
-- A candidate's texture coordinates (0 - 1): the client's own role layout when it has
-- one, else its box, else the cropped square for spell / item icons, else the whole file.
local function coords(c)
    if c.role and type(GetTexCoordsForRoleSmallCircle) == "function" then
        local ok, l, r, t, b = pcall(GetTexCoordsForRoleSmallCircle, c.role)
        if ok and type(l) == "number" and type(b) == "number" then return l, r, t, b end
    end
    local box = c.box
    if box then return box[1] / 64, box[2] / 64, box[3] / 64, box[4] / 64 end
    if isSquareIcon(c[1]) then return G.ICON_CROP[1], G.ICON_CROP[2], G.ICON_CROP[3], G.ICON_CROP[4] end
    return 0, 1, 0, 1
end
G.coords = coords

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
            if tex.SetTexCoord then tex:SetTexCoord(coords(c)) end
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
    -- GF-002-J: the same coordinates as on a texture (the crop of square icons too).
    local l, r, t, b = coords(c)
    if l == 0 and r == 1 and t == 0 and b == 1 then return "|T" .. c[1] .. ":" .. size .. "|t" end
    local function px(v) return math.floor(v * 64 + 0.5) end
    return string.format("|T%s:%d:%d:0:0:64:64:%d:%d:%d:%d|t", c[1], size, size, px(l), px(r), px(t), px(b))
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

-- GF-UI-B (GF-UI-A §1.4, §1.5, §2.2, §2.11; 0.13.1): art for the roster, the
-- lists, the drop-downs, 同步與診斷 and the order test mode. Each with a
-- fallback; the last one is a file every 1.x client ships. None of the first
-- choices is verified on 16001: tests/addon/MANUAL.md「GF-UI-B 圖示與版面」.
local UIB = {
    -- The chosen list row: the quest log's title glow (gold, ADD).
    row_select = { { "Interface\\QuestFrame\\UI-QuestLogTitleHighlight" }, { "Interface\\QuestFrame\\UI-QuestTitleHighlight" } },
    -- Sort arrows on the column headers, the drop-down arrow on choice buttons.
    sort_up = { { "Interface\\Buttons\\Arrow-Up-Up" }, { "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up" } },
    sort_down = { { "Interface\\Buttons\\Arrow-Down-Up" }, { "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up" } },
    dropdown = { { "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up" }, { "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up" } },
    -- Multi-select lists: a ticked and an empty box, both always drawn.
    check_on = { { "Interface\\Common\\UI-DropDownRadioChecks", box = { 0, 32, 0, 32 } }, { "Interface\\Buttons\\UI-CheckBox-Check" } },
    check_off = { { "Interface\\Common\\UI-DropDownRadioChecks", box = { 32, 64, 0, 32 } }, { "Interface\\Buttons\\UI-CheckBox-Up" } },
    -- Online / offline (the friends list).
    online = { { "Interface\\FriendsFrame\\StatusIcon-Online" }, { "Interface\\RaidFrame\\ReadyCheck-Ready" } },
    offline = { { "Interface\\FriendsFrame\\StatusIcon-Offline" }, { "Interface\\RaidFrame\\ReadyCheck-NotReady" } },
    -- Roster states in the middle of the list.
    loading = { { "Interface\\RaidFrame\\ReadyCheck-Waiting" }, { "Interface\\Icons\\INV_Misc_PocketWatch_01" } },
    noguild = { { "Interface\\RaidFrame\\ReadyCheck-NotReady" }, { "Interface\\Icons\\INV_Misc_QuestionMark" } },
    tabard = { { "Interface\\Icons\\INV_Shirt_GuildTabard_01" }, { "Interface\\Icons\\INV_Misc_QuestionMark" } },
    refresh = { { "Interface\\Buttons\\UI-RefreshButton" }, { "Interface\\Icons\\Spell_Nature_Reincarnation" } },
    -- 診斷 (a gear), 匯出 (a scroll), 小地圖 (the tracking dot), 測試 (a gizmo).
    diag = { { "Interface\\Icons\\Trade_Engineering" }, { "Interface\\Icons\\INV_Misc_Gear_01" }, { "Interface\\Icons\\INV_Misc_QuestionMark" } },
    export = { { "Interface\\Icons\\INV_Scroll_03" }, { "Interface\\Icons\\INV_Misc_Note_01" } },
    minimap = { { "Interface\\Minimap\\Tracking\\None" }, { "Interface\\Icons\\INV_Misc_Map_01" } },
    test = { { "Interface\\Icons\\INV_Misc_EngGizmos_01" }, { "Interface\\Icons\\INV_Misc_Gear_02" }, { "Interface\\Icons\\INV_Misc_QuestionMark" } },
    invite = { { "Interface\\Icons\\Spell_Holy_PrayerOfSpirit" }, { "Interface\\Icons\\INV_Misc_GroupNeedMore" } },
    guildinfo = { { "Interface\\Icons\\INV_Misc_Note_06" }, { "Interface\\Icons\\INV_Misc_Note_01" } },
}
for k, v in pairs(UIB) do if not G.ART[k] then G.ART[k] = v end end
