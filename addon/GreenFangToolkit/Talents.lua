-- Talents (GF-011): this character's talents in the roster.
--
-- Forever 1.60.1 (ui 16001, owner's /gftk probe 2026-11-26) has no classic
-- talent API (GetTalentInfo, GetTalentTabInfo, GetNumTalentTabs,
-- GetActiveTalentGroup, GetUnspentTalentPoints, IsDualSpecUnlocked are all
-- nil). Talents are a trait tree: C_ClassTalents.GetActiveConfigID ->
-- C_Traits.GetConfigInfo(cfg).treeIDs[1] -> GetTreeNodes(tree) ->
-- GetNodeInfo(cfg, node) { ranksPurchased, activeRank, groupIDs, posX }; the
-- groups of GetGroupDisplayInfoByTreeID(tree) { groupID, displayName, icon,
-- orderIndex } are the old tabs. Points per tab = ranks of the nodes in it.
-- GF-011-C (owner's paladin trait export 2026-11-27): most nodes carry a
-- sub-group (11480..), not the tab's group (11486), so a node's tab comes from
-- Talents.assignTabs: any of its groupIDs, else a sub-group it shares with
-- such a node, else its posX (the tabs sit side by side). Worked out once per
-- tree and kept (Talents.layout); a node nothing places stays 「未分組」.
--
-- Shared with the guild through GFTKS (Share.lua) as group "T", local = true:
-- never in GF Sync's outbox, never on the website (upload-api §3.13: the site
-- gets talents from the Blizzard API). Value:
--   1.<treeID>.<specID>.<level>.<s1>,<s2>,<s3>.<i1>,<i2>,<i3>.<import>
-- numbers base 36; s = points per group, i = group icon fileID ("" = none),
-- import = C_Traits.GenerateImportString(cfg) ("" = none).
-- Only this character's own talents are read; nobody is inspected.

local _, ns = ...
local str = ns.str

local Talents = {}
ns.Talents = Talents

Talents.GROUP = "T"
Talents.VERSION = "1"
Talents.MAX_GROUPS = 4
Talents.MAX_POINTS, Talents.MAX_TOTAL = 200, 300
Talents.MAX_IMPORT = 120
Talents.READ_DELAY = 2   -- seconds after a talent event before reading
Talents.LINK_TYPE = "talentbuild"
Talents.LINK_COLOR = "ffffd000"
Talents.HEAD = "天賦"
Talents.LINK_LABEL = "天賦連結"

local b36, unb36 = ns.Share.b36, ns.Share.unb36

local function num(v)
    if type(v) ~= "number" then return nil end
    if v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end

local function fn(path)
    local t = _G
    for part in path:gmatch("[^%.]+") do
        if type(t) ~= "table" then return nil end
        t = t[part]
    end
    return type(t) == "function" and t or nil
end

---------------------------------------------------------------------------
-- Codec (pure)
---------------------------------------------------------------------------

-- d = { treeID, specID, level, groups = { { spent, icon }, ... }, import }
function Talents.encode(d)
    if type(d) ~= "table" then return nil end
    local tree, level = num(d.treeID), num(d.level)
    if not (tree and tree >= 1 and level and level >= 1) then return nil end
    local groups = type(d.groups) == "table" and d.groups or {}
    if #groups < 1 or #groups > Talents.MAX_GROUPS then return nil end
    local s, i = {}, {}
    for k, g in ipairs(groups) do
        local spent = math.floor(num(g.spent) or 0)
        if spent < 0 then spent = 0 end
        s[k] = b36(spent)
        local icon = num(g.icon)
        i[k] = (icon and icon > 0) and b36(math.floor(icon)) or ""
    end
    local import = str(d.import)
    if #import > Talents.MAX_IMPORT or import:find("[^%w%+/=]") then import = "" end
    return table.concat({ Talents.VERSION, b36(math.floor(tree)), b36(math.max(0, math.floor(num(d.specID) or 0))),
        b36(math.floor(level)), table.concat(s, ","), table.concat(i, ","), import }, ".")
end

local function split(s, sep)
    local out = {}
    for part in (s .. sep):gmatch("([^" .. sep .. "]*)" .. sep) do out[#out + 1] = part end
    return out
end

local function n36(s, lo, hi)
    if type(s) ~= "string" or s == "" or s:find("[^0-9a-z]") then return nil end
    local v = unb36(s)
    if type(v) ~= "number" or v < lo or v > hi then return nil end
    return v
end

function Talents.decode(v)
    if type(v) ~= "string" or #v > 240 then return nil end
    local ver, tree, spec, level, s, i, import = v:match("^([^%.]*)%.([^%.]*)%.([^%.]*)%.([^%.]*)%.([^%.]*)%.([^%.]*)%.([^%.]*)$")
    if ver ~= Talents.VERSION then return nil end
    local d = { treeID = n36(tree, 1, 10000000), specID = n36(spec, 0, 1000000), level = n36(level, 1, 200) }
    if not (d.treeID and d.specID and d.level) then return nil end
    if #import > Talents.MAX_IMPORT or import:find("[^%w%+/=]") then return nil end
    d.import = import ~= "" and import or nil
    local sl, il = split(s, ","), split(i, ",")
    if #sl < 1 or #sl > Talents.MAX_GROUPS or #il ~= #sl then return nil end
    d.groups = {}
    local total = 0
    for k = 1, #sl do
        local spent = n36(sl[k], 0, Talents.MAX_POINTS)
        if not spent then return nil end
        local icon = nil
        if il[k] ~= "" then
            icon = n36(il[k], 0, 2147483647) -- gftks.md §3.2: 0 = no icon, like ""
            if not icon then return nil end
            if icon == 0 then icon = nil end
        end
        total = total + spent
        d.groups[k] = { spent = spent, icon = icon }
    end
    if total > Talents.MAX_TOTAL then return nil end
    d.total = total
    return d
end

---------------------------------------------------------------------------
-- Reading this character's own talents (C_ first; nothing classic)
---------------------------------------------------------------------------

local function activeConfig()
    local cfg = num((ns.call(fn("C_ClassTalents.GetActiveConfigID"))))
    if cfg then return cfg end
    local group = num((ns.call(fn("C_SpecializationInfo.GetActiveSpecGroup"))))
    if group then return num((ns.call(fn("C_SpecializationInfo.GetCombatConfigIDForSpecGroup"), group))) end
    return nil
end

local function specID()
    local idx = num((ns.call(fn("C_SpecializationInfo.GetSpecialization"))))
    if not idx then return 0 end
    local id = num((ns.call(fn("C_SpecializationInfo.GetSpecializationInfo"), idx)))
    return id and id > 0 and id or 0
end

-- Group display info of a tree: { { id, name, icon }, ... } in the game's order.
function Talents.treeGroups(tree)
    local list = ns.call(fn("C_Traits.GetGroupDisplayInfoByTreeID"), tree)
    local out = {}
    if type(list) ~= "table" then return out end
    for _, g in ipairs(list) do
        if type(g) == "table" then
            out[#out + 1] = { id = num(g.groupID) or num(g.ID), name = type(g.displayName) == "string" and g.displayName or nil,
                icon = num(g.icon) or num(g.iconFileID), order = num(g.orderIndex) }
        end
        if #out >= Talents.MAX_GROUPS then break end
    end
    return out
end

---------------------------------------------------------------------------
-- GF-011-C: which tab each node is in (pure)
---------------------------------------------------------------------------

Talents.GAP_RATIO = 1.5 -- coordinate fallback without a known node in every tab: a gap between tabs is this much wider than any gap inside one

-- Tab k for an x, given the cut points between neighbouring tabs (left to right).
local function cluster(x, cuts)
    local c = 1
    for _, cut in ipairs(cuts) do if x > cut then c = c + 1 end end
    return c
end

-- Cut points between the tabs on posX, or nil when the positions do not
-- tell them apart. leftToRight = tab indices sorted by orderIndex; known =
-- tab index -> list of x of nodes already placed by their groups.
local function positionCuts(leftToRight, known, xs)
    local n = #leftToRight
    if n < 1 then return nil end
    local all = true
    for _, k in ipairs(leftToRight) do if not known[k] or #known[k] == 0 then all = false end end
    local cuts = {}
    if all then
        -- Each tab's own x range; they must not overlap, in orderIndex order.
        local lo, hi = {}, {}
        for i, k in ipairs(leftToRight) do
            lo[i], hi[i] = math.huge, -math.huge
            for _, x in ipairs(known[k]) do lo[i] = math.min(lo[i], x); hi[i] = math.max(hi[i], x) end
        end
        for i = 1, n - 1 do
            if not (hi[i] < lo[i + 1]) then return nil end
            cuts[i] = (hi[i] + lo[i + 1]) / 2
        end
        return cuts
    end
    -- Some tab has no placed node: the n-1 widest gaps between distinct x.
    local seen, list = {}, {}
    for _, x in ipairs(xs) do if not seen[x] then seen[x] = true; list[#list + 1] = x end end
    table.sort(list)
    if #list < n then return nil end
    local gaps = {}
    for i = 1, #list - 1 do gaps[i] = { w = list[i + 1] - list[i], at = (list[i] + list[i + 1]) / 2 } end
    table.sort(gaps, function(a, b) return a.w > b.w end)
    if n > 1 and gaps[n] and gaps[n - 1].w <= gaps[n].w * Talents.GAP_RATIO then return nil end
    for i = 1, n - 1 do cuts[i] = gaps[i].at end
    table.sort(cuts)
    -- Every node its groups already placed must land in its own tab.
    for i, k in ipairs(leftToRight) do
        for _, x in ipairs(known[k] or {}) do if cluster(x, cuts) ~= i then return nil end end
    end
    return cuts
end

-- tabs = { { id, order } } (game order; order = orderIndex or nil);
-- nodes = { { id, groups = { groupID, ... }, x } }. Returns
-- { tab = { [nodeID] = k }, by = { [nodeID] = "group" | "sub" | "pos" } };
-- a node in neither is 「未分組」.
function Talents.assignTabs(tabs, nodes)
    local tabIndex, tab, by = {}, {}, {}
    for k, t in ipairs(tabs) do if t.id then tabIndex[t.id] = k end end
    -- 1. One of the node's groups is a tab's group.
    local subTab = {} -- sub-group -> tab k, or false when its nodes disagree
    for _, nd in ipairs(nodes) do
        local k
        for _, g in ipairs(nd.groups) do
            local t = tabIndex[g]
            if t then
                if k and k ~= t then k = false; break end
                k = t
            end
        end
        if k then
            tab[nd.id], by[nd.id] = k, "group"
            for _, g in ipairs(nd.groups) do
                if not tabIndex[g] then
                    if subTab[g] == nil then subTab[g] = k elseif subTab[g] ~= k then subTab[g] = false end
                end
            end
        end
    end
    -- 2. A sub-group shared with nodes of one tab only.
    for _, nd in ipairs(nodes) do
        if not tab[nd.id] then
            local k
            for _, g in ipairs(nd.groups) do
                local t = subTab[g]
                if t then
                    if k and k ~= t then k = false; break end
                    k = t
                end
            end
            if k then tab[nd.id], by[nd.id] = k, "sub" end
        end
    end
    -- 3. posX: the tabs side by side, left to right by orderIndex.
    local leftToRight = {}
    for k = 1, #tabs do leftToRight[k] = k end
    table.sort(leftToRight, function(a, b)
        local oa, ob = tabs[a].order, tabs[b].order
        if oa and ob and oa ~= ob then return oa < ob end
        return a < b
    end)
    local known, xs = {}, {}
    for _, nd in ipairs(nodes) do
        if nd.x then
            xs[#xs + 1] = nd.x
            local k = tab[nd.id]
            if k then known[k] = known[k] or {}; known[k][#known[k] + 1] = nd.x end
        end
    end
    local cuts = #tabs > 0 and positionCuts(leftToRight, known, xs)
    if cuts then
        for _, nd in ipairs(nodes) do
            if not tab[nd.id] and nd.x then tab[nd.id], by[nd.id] = leftToRight[cluster(nd.x, cuts)], "pos" end
        end
    end
    return { tab = tab, by = by }
end

-- The node facts assignTabs needs, from one GetNodeInfo result.
function Talents.nodeFacts(id, ni)
    local groups = {}
    if type(ni.groupIDs) == "table" then
        for _, g in ipairs(ni.groupIDs) do
            g = num(g)
            if g then groups[#groups + 1] = g end
        end
    end
    return { id = id, groups = groups, x = num(ni.posX) }
end

-- Tab layout per tree, worked out on the first read and kept: node groups
-- and positions belong to the tree, not to the points spent. Dropped by
-- Talents.onEvent on events that can swap the tree (spec, config list, login).
local layout = nil
Talents.layoutBuilds = 0

-- Read now. Returns the snapshot (Talents.encode's shape, plus names and
-- why = nil) or nil, why ("api" no trait API, "config", "tree", "nodes").
function Talents.read()
    if not fn("C_Traits.GetConfigInfo") then return nil, "api" end
    local cfg = activeConfig()
    if not cfg then return nil, "config" end
    local info = ns.call(fn("C_Traits.GetConfigInfo"), cfg)
    local tree = type(info) == "table" and type(info.treeIDs) == "table" and num(info.treeIDs[1]) or nil
    if not tree then return nil, "tree" end
    local nodes = ns.call(fn("C_Traits.GetTreeNodes"), tree)
    if type(nodes) ~= "table" then return nil, "nodes" end
    local fresh = not (layout and layout.tree == tree and layout.count == #nodes)
    local groups = fresh and Talents.treeGroups(tree) or layout.groups
    local spent, other = {}, 0
    for k = 1, #groups do spent[k] = 0 end
    local nodeInfo = fn("C_Traits.GetNodeInfo")
    local facts, ranks = {}, {}
    for i = 1, math.min(#nodes, 1000) do
        local ni = ns.call(nodeInfo, cfg, nodes[i])
        if type(ni) == "table" then
            ranks[#ranks + 1] = { id = nodes[i], r = num(ni.ranksPurchased) or num(ni.activeRank) or 0 }
            if fresh then facts[#facts + 1] = Talents.nodeFacts(nodes[i], ni) end
        end
    end
    if fresh then
        -- Kept only when every node answered (a half-loaded tree is worked out again next read).
        layout = { tree = tree, count = #facts == math.min(#nodes, 1000) and #nodes or -1, groups = groups, map = Talents.assignTabs(groups, facts) }
        Talents.layoutBuilds = Talents.layoutBuilds + 1
    end
    local how = { group = 0, sub = 0, pos = 0, none = 0 }
    for _, n in ipairs(ranks) do
        if n.r > 0 then
            local k = layout.map.tab[n.id]
            if k then spent[k] = spent[k] + n.r else other = other + n.r end
            local b = layout.map.by[n.id] or "none"
            how[b] = how[b] + n.r
        end
    end
    local out = { configID = cfg, treeID = tree, specID = specID(),
        level = num((ns.call(UnitLevel, "player"))) or 1, groups = {}, other = other, how = how }
    if #groups == 0 then
        out.groups[1] = { spent = other }
    else
        for k, g in ipairs(groups) do out.groups[k] = { spent = spent[k], icon = g.icon, name = g.name } end
    end
    local import = ns.call(fn("C_Traits.GenerateImportString"), cfg)
    out.import = type(import) == "string" and import or nil
    return out
end

local cache, cacheWhy, dirty = nil, nil, true
function Talents.own()
    if dirty then
        cache, cacheWhy = Talents.read()
        dirty = false
    end
    return cache, cacheWhy
end
function Talents.markDirty() dirty = true end

-- The own value for the share group (Share.observeOwn).
function Talents.ownValue()
    local d = Talents.own()
    return d and Talents.encode(d) or nil
end

---------------------------------------------------------------------------
-- Read-only API (roster)
---------------------------------------------------------------------------

-- Talents of a character, or nil (nothing received / no data):
-- { groups = { { spent, icon, name } }, total, text = "14/32/5", import,
--   specID, level, treeID, at, own, relayed }
function Talents.of(guid)
    guid = str(guid)
    if guid == "" then return nil end
    local S = ns.Share
    local selfG = ns.Profile and ns.Profile.selfGuid()
    local d, at, own, relayed
    if guid == selfG then
        local mine = Talents.own()
        if mine then d = Talents.decode(Talents.encode(mine) or ""); own = true; at = ns.now() end
    end
    if not d and S and S.store() then
        local a = S.authorOf(guid)
        local rec = a and S.get(a, Talents.GROUP)
        d = rec and S.decoded(a, Talents.GROUP)
        if d then at, relayed = rec.t, not rec.fromAuthor end
    end
    if not d then return nil end
    -- Names (and missing icons) from this client's copy of the same tree.
    local local_ = Talents.treeGroups(d.treeID)
    local nums, groups = {}, {}
    for k, g in ipairs(d.groups) do
        local lg = local_[k]
        groups[k] = { spent = g.spent, icon = g.icon or (lg and lg.icon), name = lg and lg.name or nil }
        nums[k] = tostring(g.spent)
    end
    local total = 0
    for _, g in ipairs(groups) do total = total + g.spent end
    return { groups = groups, total = total, text = table.concat(nums, "/"), import = d.import,
        specID = d.specID, level = d.level, treeID = d.treeID, at = at, own = own, relayed = relayed }
end

-- Can the client make a talentbuild link for this record?
function Talents.canLink(t)
    if not (t and t.import and t.specID and t.specID > 0) then return false end
    local lt = type(LinkTypes) == "table" and LinkTypes.TalentBuild
    return lt == Talents.LINK_TYPE
end

-- "|cffffd000|Htalentbuild:<specID>:<level>:<import>|h[天賦：名字 14/32/5]|h|r", or nil.
function Talents.link(guid, name)
    local t = Talents.of(guid)
    if not Talents.canLink(t) then return nil end
    local text = Talents.HEAD .. "：" .. (str(name) ~= "" and (ns.shortName and ns.shortName(name) or name) .. " " or "") .. t.text
    return string.format("|c%s|H%s:%d:%d:%s|h[%s]|h|r", Talents.LINK_COLOR, Talents.LINK_TYPE, t.specID, t.level, t.import, text)
end

local function chatUtil(modern, legacy)
    if type(ChatFrameUtil) == "table" and type(ChatFrameUtil[modern]) == "function" then return ChatFrameUtil[modern] end
    if type(_G[legacy]) == "function" then return _G[legacy] end
    return nil
end

-- 「天賦連結」: put the link into the chat box (opening it when closed). The
-- player sends it (or clicks it to open the game's own loadout view).
function Talents.insertLink(guid, name)
    local link = Talents.link(guid, name)
    if not link then return false, "nolink" end
    local insert = chatUtil("InsertLink", "ChatEdit_InsertLink")
    if insert and ns.call(insert, link) then return true end
    local open = chatUtil("OpenChat", "ChatFrame_OpenChat")
    if open and pcall(open, link) then return true end
    return false, "nochat"
end

---------------------------------------------------------------------------
-- GF-011-B 「天賦樹」 (owner 0.16.5: 「天賦我以為可以打開天賦樹?」): the game's
-- own talent window. Forever's code (WoWBlzCode Forever, 1.60.1):
-- ItemRefHandlers.lua handles a talentbuild link with
-- PlayerSpellsUtil.InspectLoadout("<specID>:<level>:<import>"), which loads
-- Blizzard_PlayerSpells (LoadOnDemand) and calls
-- PlayerSpellsFrame:SetInspectString -> TalentsFrame:ViewLoadout: read-only,
-- the spec comes from the import string's own header (any class). When
-- ViewLoadout refuses the string, the frame drops the inspect and would show
-- the player's own tree, so that case falls back to the chat link.
-- Own character: PlayerSpellsUtil.OpenToClassTalentsTab() (the normal window).
-- Never in combat (the window is a UI panel; loading it mid-fight is refused).
---------------------------------------------------------------------------

Talents.TREE_LABEL = "天賦樹"
Talents.TREE_TIP = { combat = "戰鬥中不能開", nodata = "沒有收到天賦", noimport = "沒有匯出字串", noui = "這個用戶端開不了天賦視窗" }

local function selfGuid() return ns.Profile and ns.Profile.selfGuid() or nil end

-- How "天賦樹" would open for this member: "own", "view", "ref", "chat", or
-- nil, why (Talents.TREE_TIP key). No combat check here (UI greys it there).
function Talents.treeMode(guid)
    guid = str(guid)
    if guid ~= "" and guid == selfGuid() then
        if fn("PlayerSpellsUtil.OpenToClassTalentsTab") or fn("TogglePlayerSpellsFrame") or fn("ToggleTalentFrame") then return "own" end
        return nil, "noui"
    end
    local t = Talents.of(guid)
    if not t then return nil, "nodata" end
    if not t.import then return nil, "noimport" end
    if fn("PlayerSpellsUtil.InspectLoadout") then return "view" end
    if fn("SetItemRef") and Talents.canLink(t) then return "ref" end
    if Talents.canLink(t) then return "chat" end
    return nil, "noui"
end

local function inspecting()
    local f = PlayerSpellsFrame
    if type(f) ~= "table" or type(f.IsInspecting) ~= "function" then return nil end
    local ok, v = pcall(f.IsInspecting, f)
    if not ok then return nil end
    return v == true
end

-- Open it. Returns true, mode ("own", "view", "ref", "chat") or false, why.
function Talents.openTree(guid, name)
    if ns.inCombat() then return false, "combat" end
    local mode, why = Talents.treeMode(guid)
    if not mode then return false, why end
    if mode == "own" then
        for _, path in ipairs({ "PlayerSpellsUtil.OpenToClassTalentsTab", "PlayerSpellsUtil.ToggleClassTalentFrame",
            "TogglePlayerSpellsFrame", "ToggleTalentFrame" }) do
            local f = fn(path)
            if f then
                local ok = path == "TogglePlayerSpellsFrame" and pcall(f, 2) or pcall(f)
                if ok then return true, "own" end
            end
        end
        return false, "noui"
    end
    local t = Talents.of(guid)
    local data = string.format("%d:%d:%s", t.specID or 0, t.level or 1, t.import)
    if mode == "view" then
        local ok = pcall(fn("PlayerSpellsUtil.InspectLoadout"), data)
        if ok and inspecting() ~= false then return true, "view" end
        -- Refused (bad string, other serialization version): close the own tree it fell back to.
        if PlayerSpellsFrame and HideUIPanel then pcall(HideUIPanel, PlayerSpellsFrame) end
    elseif mode == "ref" then
        local link = Talents.link(guid, name)
        local ok = pcall(SetItemRef, Talents.LINK_TYPE .. ":" .. data, link, "LeftButton")
        if ok then return true, "ref" end
    end
    local okC = Talents.insertLink(guid, name)
    if okC then return true, "chat" end
    return false, "noui"
end

---------------------------------------------------------------------------
-- Diagnostics and /gftk probe
---------------------------------------------------------------------------

Talents.WHY = { api = "沒有天賦介面", config = "沒有啟用的配置", tree = "沒有天賦樹", nodes = "讀不到節點" }

-- GF-FIX-C (review low-13): the cached read (dirty on every talent event), not a fresh one each second.
function Talents.summaryLine()
    local d, why = Talents.own()
    if not d then return "本角色天賦：" .. (Talents.WHY[why] or str(why)) end
    local nums = {}
    for k, g in ipairs(d.groups) do nums[k] = tostring(g.spent) .. (g.name and ("(" .. g.name .. ")") or "") end
    local h = d.how or {}
    return string.format("本角色天賦：%s｜未分組 %d｜歸屬 群組 %d／子群組 %d／座標 %d 點｜樹 %d｜專精 %d｜等級 %d｜匯出字串 %s｜連結 %s",
        table.concat(nums, "/"), d.other or 0, h.group or 0, h.sub or 0, h.pos or 0, d.treeID, d.specID, d.level,
        d.import and (#d.import .. " 字") or "無", Talents.canLink({ import = d.import, specID = d.specID }) and "可" or "不可")
end

function Talents.diagText()
    local got = 0
    local S = ns.Share
    local s = S and S.store()
    if s then
        local me = S.selfAuthor()
        for a, groups in pairs(s.rec) do if a ~= me and groups[Talents.GROUP] then got = got + 1 end end
    end
    return string.format("%s｜收到天賦 %d 位", Talents.summaryLine(), got)
end

---------------------------------------------------------------------------
-- Share group and events
---------------------------------------------------------------------------

ns.Share.registerGroup({
    name = "TALENTS",
    ["local"] = true,
    match = function(g) return g == Talents.GROUP end,
    encode = function(_, d) return Talents.encode(d) end,
    decode = function(_, v) return Talents.decode(v) end,
    ownGroups = { Talents.GROUP },
    own = function() return Talents.ownValue() end,
})

Talents.EVENTS = { "PLAYER_ENTERING_WORLD", "TRAIT_CONFIG_UPDATED", "TRAIT_CONFIG_LIST_UPDATED",
    "ACTIVE_PLAYER_SPECIALIZATION_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_TALENT_UPDATE",
    "CHARACTER_POINTS_CHANGED", "PLAYER_LEVEL_UP" }
-- GF-011-C: events that can bring another tree (or a tree not fully loaded
-- before) also drop the kept tab layout; point changes keep it.
Talents.LAYOUT_EVENTS = { PLAYER_ENTERING_WORLD = true, TRAIT_CONFIG_LIST_UPDATED = true,
    ACTIVE_PLAYER_SPECIALIZATION_CHANGED = true, ACTIVE_TALENT_GROUP_CHANGED = true }
function Talents.dropLayout() layout = nil end
local waiting = false
function Talents.onEvent(event)
    if Talents.LAYOUT_EVENTS[event] then layout = nil end
    dirty = true
    if waiting then return end
    waiting = true
    ns.after(Talents.READ_DELAY, function()
        waiting = false
        dirty = true
        if ns.Share.store() then ns.Share.ownChanged() end
        if Talents.onChanged then pcall(Talents.onChanged) end
    end)
end
local events = CreateFrame("Frame")
for _, e in ipairs(Talents.EVENTS) do pcall(events.RegisterEvent, events, e) end
events:SetScript("OnEvent", function(_, event) Talents.onEvent(event) end)
