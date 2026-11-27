-- GF-011-C: which talent tab a node's points count in. The owner's paladin
-- /gftkdev traits (2026-11-27): 51 nodes, most of them in a sub-group
-- (11480..) instead of the tab's own group (11486/11541/11559), so the roster
-- read 0/0/5 with 14 ungrouped instead of 0/7/12. Node IDs, groups, ranks
-- and positions below are from that export (no names, GUIDs or accounts);
-- the other trees are made up.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local ROOT = ADDON_DIR:gsub("/addon/GreenFangToolkit$", "")
    local DEV_DIR = ROOT .. "/addon/GreenFangToolkit_Dev"

    -- { nodeID, groupID (the one the export printed), ranks, posX, posY }
    local PALADIN = {
        { 105320, 11480, 0, 1620, 5730 }, { 105321, 11481, 0, 2220, 5130 }, { 105323, 11482, 0, 1620, 4530 }, { 105324, 11483, 0, 1020, 3930 },
        { 105325, 11484, 0, 1020, 3330 }, { 105327, 11485, 0, 2820, 2730 }, { 105329, 11486, 0, 1620, 3330 }, { 105330, 11483, 0, 2220, 3930 },
        { 105331, 11557, 0, 9680, 3330 }, { 105332, 12754, 0, 5620, 2130 }, { 105333, 11485, 0, 1020, 2730 }, { 105334, 11486, 0, 2220, 2730 },
        { 105335, 11486, 0, 1620, 2130 }, { 105625, 11539, 0, 5020, 3330 }, { 105626, 11536, 5, 6220, 2130 }, { 105627, 11537, 0, 6220, 4530 },
        { 105628, 11535, 0, 5620, 4530 }, { 105630, 12750, 0, 6820, 3330 }, { 105632, 11540, 0, 6820, 2730 }, { 105633, 11541, 0, 5620, 3330 },
        { 105634, 11541, 0, 5620, 3930 }, { 105636, 11541, 0, 6220, 3930 }, { 105637, 11540, 0, 5620, 2730 }, { 105638, 11540, 2, 5020, 2730 },
        { 105639, 11537, 0, 5020, 4530 }, { 105692, 11553, 0, 9680, 5730 }, { 105693, 11555, 0, 10280, 4530 }, { 105694, 11555, 0, 9680, 4530 },
        { 105696, 11557, 0, 10280, 3330 }, { 105697, 11556, 0, 10880, 3930 }, { 105698, 11556, 0, 9080, 3930 }, { 105699, 11557, 2, 10880, 3330 },
        { 105700, 11556, 0, 9680, 3930 }, { 105701, 11558, 3, 10280, 2730 }, { 105702, 11559, 0, 9080, 3330 }, { 105703, 11559, 0, 9680, 2730 },
        { 105704, 11484, 0, 2220, 3330 }, { 105705, 11558, 2, 9080, 2730 }, { 105706, 11559, 5, 10280, 2130 }, { 105707, 11559, 0, 9680, 2130 },
        { 110871, 11485, 0, 1620, 2730 }, { 110872, 11482, 0, 1020, 4530 }, { 110873, 11483, 0, 1620, 3930 }, { 110874, 11539, 0, 6220, 3330 },
        { 110875, 12482, 0, 5620, 5730 }, { 110878, 11538, 0, 5020, 3930 }, { 110879, 12481, 0, 6220, 5130 }, { 110882, 11554, 0, 10280, 5130 },
        { 113629, 11555, 0, 9080, 4530 }, { 113630, 12749, 0, 2220, 2130 }, { 113631, 11482, 0, 2220, 4530 },
    }
    local HOLY, PROT, RET = 11486, 11541, 11559
    -- The sub-group -> tab the export's positions say (for the full-groupIDs variant).
    local SUB = { [12749] = HOLY, [12750] = PROT, [12754] = PROT, [12481] = PROT, [12482] = PROT }
    for g = 11480, 11485 do SUB[g] = HOLY end
    for g = 11535, 11540 do SUB[g] = PROT end
    for g = 11553, 11558 do SUB[g] = RET end

    -- opts.full: every sub-group node also has its tab's group (groupIDs = { sub, tab }).
    local function paladin(opts)
        opts = opts or {}
        local t = { configID = 167385, treeID = 1100, specID = 1486, import = "",
            groups = { { id = HOLY, name = "神聖", icon = 135920, order = 1 }, { id = PROT, name = "防護", icon = 135893, order = 2 },
                { id = RET, name = "懲戒", icon = 135873, order = 3 } },
            nodes = {} }
        for _, r in ipairs(PALADIN) do
            local n = { id = r[1], group = r[2], ranks = r[3], x = r[4], y = r[5] }
            if opts.full and SUB[r[2]] then n.groupIDs = { r[2], SUB[r[2]] } end
            t.nodes[#t.nodes + 1] = n
        end
        return t
    end

    local function login(talents)
        wow.reset({ talents = talents })
        local ns = wow.login(ADDON_DIR)
        ns.Share.rand = function(a) return a end
        if ns.Orders.resetSession then ns.Orders.resetSession() end
        if ns.Adventure.resetSession then ns.Adventure.resetSession() end
        wow.advance(25)
        return ns
    end
    local function spent(d)
        local out = {}
        for k, g in ipairs(d.groups) do out[k] = g.spent end
        return table.concat(out, "/")
    end

    test("GF-011-C paladin export: 神聖 0 / 防護 7 / 懲戒 12, nothing ungrouped (sub-groups placed by position)", function()
        local ns = login(paladin())
        local d = ns.Talents.read()
        eq(spent(d), "0/7/12", "three tabs"); eq(d.other, 0, "未分組")
        eq(d.how.group, 5, "祈福 5 is in the tab's own group"); eq(d.how.pos, 14, "the rest by posX"); eq(d.how.none, 0, "none left")
        eq(ns.Talents.of("Player-0000-0000000A").text, "0/7/12", "roster card text")
        local line = ns.Talents.summaryLine()
        ok(line:find("0(神聖)/7(防護)/12(懲戒)｜未分組 0｜歸屬 群組 5／子群組 0／座標 14 點", 1, true), "probe line: " .. line)
        ns.Probe.run("main")
        ok(GreenFangToolkitDB.probe.main.talents.gf011:find("0(神聖)/7(防護)/12(懲戒)", 1, true), "probe gf011")
        -- Every one of the 51 nodes has a tab, also the unranked ones.
        local facts = {}
        for _, r in ipairs(PALADIN) do facts[#facts + 1] = { id = r[1], groups = { r[2] }, x = r[4] } end
        local res = ns.Talents.assignTabs(ns.Talents.treeGroups(1100), facts)
        local n, wrong = 0, 0
        for _, r in ipairs(PALADIN) do
            local k = res.tab[r[1]]
            if k then n = n + 1 end
            local want = ({ [HOLY] = 1, [PROT] = 2, [RET] = 3 })[SUB[r[2]] or r[2]]
            if k ~= want then wrong = wrong + 1 end
        end
        eq(n, 51, "all nodes placed"); eq(wrong, 0, "each in the tab its position says")
    end)

    test("GF-011-C groupIDs with the tab's group anywhere in the list (not only first): by group, same points", function()
        local ns = login(paladin({ full = true }))
        local d = ns.Talents.read()
        eq(spent(d), "0/7/12", "three tabs"); eq(d.other, 0, "未分組")
        eq(d.how.group, 19, "all by the game's groups"); eq(d.how.pos, 0, "no position needed")
    end)

    test("GF-011-C a sub-group shared with a node of the tab carries that tab (no positions)", function()
        local t = { configID = 1, treeID = 2, specID = 0, import = "", noPos = true,
            groups = { { id = 10, name = "甲" }, { id = 20, name = "乙" } },
            nodes = { { id = 1, groupIDs = { 101, 10 }, ranks = 1 }, { id = 2, groupIDs = { 101 }, ranks = 4 },
                { id = 3, groupIDs = { 201, 20 }, ranks = 0 }, { id = 4, groupIDs = { 201 }, ranks = 2 },
                { id = 5, groupIDs = { 999 }, ranks = 3 } } }
        local ns = login(t)
        local d = ns.Talents.read()
        eq(spent(d), "5/2", "two tabs"); eq(d.how.sub, 6, "by shared sub-group")
        eq(d.other, 3, "a node nothing places stays 未分組 (never guessed)")
        eq(d.how.none, 3, "and the diagnostics say so")
        ok(ns.Talents.summaryLine():find("未分組 3", 1, true), "probe line shows it")
    end)

    test("GF-011-C old shape (every node in a tab's own group) still counts the same", function()
        local t = { configID = 1, treeID = 2, specID = 0, import = "",
            groups = { { id = 10, name = "甲" }, { id = 20, name = "乙" }, { id = 30, name = "丙" } },
            nodes = { { id = 1, group = 10, ranks = 5 }, { id = 2, group = 20, ranks = 3 }, { id = 3, group = 30, ranks = 1 },
                { id = 4, group = 99, ranks = 2 } } }
        local ns = login(t)
        local d = ns.Talents.read()
        eq(spent(d), "5/3/1", "by group"); eq(d.other, 2, "posX all 0 here: the stray node is not pushed into a tab")
    end)

    test("GF-011-C position fallback: 2 and 4 tabs, a tab with no node of its own group, orderIndex not in game order", function()
        local Tl = login(paladin()).Talents
        local function run(tabs, nodes)
            local res = Tl.assignTabs(tabs, nodes)
            local out = {}
            for _, n in ipairs(nodes) do out[#out + 1] = tostring(res.tab[n.id] or "-") .. (res.by[n.id] and res.by[n.id]:sub(1, 1) or "") end
            return table.concat(out, " ")
        end
        -- Two tabs, both with a known node: cut between their ranges.
        eq(run({ { id = 1 }, { id = 2 } }, { { id = 1, groups = { 1 }, x = 100 }, { id = 2, groups = { 7 }, x = 300 },
            { id = 3, groups = { 2 }, x = 2000 }, { id = 4, groups = { 8 }, x = 2600 }, { id = 5, groups = {}, x = 700 } }),
            "1g 1p 2g 2p 1p", "two tabs")
        -- Four tabs, the third has no node of its own group: widest gaps, left to right.
        local nodes = {}
        for tab = 0, 3 do
            for c = 0, 3 do nodes[#nodes + 1] = { id = tab * 10 + c, groups = { 500 + tab }, x = tab * 5000 + c * 600 } end
        end
        nodes[1].groups = { 1 }; nodes[5].groups = { 2 }; nodes[13].groups = { 4 }
        local function tabsOf(res)
            local got = {}
            for _, n in ipairs(nodes) do got[#got + 1] = tostring(res.tab[n.id] or "-") end
            return table.concat(got, "")
        end
        eq(tabsOf(Tl.assignTabs({ { id = 1 }, { id = 2 }, { id = 3 }, { id = 4 } }, nodes)), "1111222233334444", "four tabs by gap")
        -- orderIndex: the game lists them right to left.
        eq(tabsOf(Tl.assignTabs({ { id = 4, order = 4 }, { id = 3, order = 3 }, { id = 2, order = 2 }, { id = 1, order = 1 } }, nodes)),
            "4444333322221111", "tab index follows the game's list; left to right follows orderIndex")
        -- Positions that do not separate (no wide gap): nothing guessed.
        local flat = {}
        for i = 1, 9 do flat[i] = { id = i, groups = { 600 }, x = i * 100 } end
        flat[1].groups = { 1 }
        local res = Tl.assignTabs({ { id = 1 }, { id = 2 }, { id = 3 } }, flat)
        local placed = 0
        for _ in pairs(res.tab) do placed = placed + 1 end
        eq(placed, 1, "only the node in a tab's own group")
        -- A known node on the wrong side of the gap cut: positions refused.
        res = Tl.assignTabs({ { id = 1 }, { id = 2 } }, { { id = 1, groups = { 2 }, x = 0 }, { id = 2, groups = {}, x = 100 },
            { id = 3, groups = {}, x = 5000 } })
        eq(res.tab[2], nil, "inconsistent positions place nothing"); eq(res.tab[3], nil, "nor this")
        -- Ranges that overlap (all tabs known): refused too.
        res = Tl.assignTabs({ { id = 1 }, { id = 2 } }, { { id = 1, groups = { 1 }, x = 0 }, { id = 2, groups = { 1 }, x = 900 },
            { id = 3, groups = { 2 }, x = 500 }, { id = 4, groups = {}, x = 300 } })
        eq(res.tab[4], nil, "overlapping tabs: not placed")
        -- A node with no position and no tab group.
        res = Tl.assignTabs({ { id = 1 }, { id = 2 } }, { { id = 1, groups = { 1 }, x = 0 }, { id = 2, groups = { 2 }, x = 5000 },
            { id = 3, groups = { 9 } } })
        eq(res.tab[3], nil, "no posX: 未分組")
    end)

    test("GF-011-C tab layout is worked out once per tree; rank changes reuse it, a spec change drops it", function()
        local t = paladin()
        local ns = login(t)
        local Tl = ns.Talents
        Tl.read()
        local builds = Tl.layoutBuilds
        Tl.read(); Tl.read()
        eq(Tl.layoutBuilds, builds, "no new layout for the same tree")
        t.nodes[1].ranks = 1 -- a Holy node in sub-group 11480
        wow.installTalents()
        wow.fire("TRAIT_CONFIG_UPDATED", 167385)
        wow.advance(5)
        eq(Tl.of("Player-0000-0000000A").text, "1/7/12", "new point in the right tab")
        eq(Tl.layoutBuilds, builds, "points changed, layout kept")
        wow.fire("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
        wow.advance(5)
        Tl.of("Player-0000-0000000A")
        eq(Tl.layoutBuilds, builds + 1, "spec change: worked out again")
    end)

    test("GF-011-C received talents are shown as the sender sent them (an old sender's numbers are not rewritten)", function()
        local ns = login(paladin())
        local S = ns.Share
        -- A 0.16.12 sender's value: 0/0/5 (its sub-group points never reached the groups it sent).
        local v = ns.Talents.encode({ treeID = 1100, specID = 1486, level = 28, groups = { { spent = 0 }, { spent = 0 }, { spent = 5 } } })
        local A = "0000-0000000B"
        S.onMessage("GFTKS", "S1~V~" .. A .. "~T~" .. S.b36(ns.now()) .. "~" .. S.hash(v) .. "~" .. v, "GUILD", "測試乙-測試伺服器")
        wow.advance(5)
        local got = ns.Talents.of("Player-" .. A)
        ok(got, "received")
        if got then eq(got.text, "0/0/5", "shown as sent"); eq(got.groups[3].name, "懲戒", "names from this client's tree") end
    end)

    test("GF-011-C /gftkdev traits: every groupID per node, the tab the toolkit counts, and how", function()
        local ns = login(paladin({ full = true }))
        local D = {}
        local plainAccess = GreenFangToolkit_DevAccess
        GreenFangToolkit_DevAccess = function() return ns end
        local okL, err = pcall(function() assert(loadfile(DEV_DIR .. "/TraitDump.lua"))("GreenFangToolkit_Dev", D) end)
        local okC, L = pcall(function() return okL and D.TraitDump.collect() or {} end)
        GreenFangToolkit_DevAccess = plainAccess
        ok(okL, tostring(err)); ok(okC, tostring(L))
        local text = table.concat(type(L) == "table" and L or {}, "\n") .. "\n"
        local function has(s) return text:find(s, 1, true) ~= nil end
        ok(has("H assign=toolkit"), "uses the toolkit's rule")
        ok(has("G 2 id=11541 name=防護 spent=7"), "防護 7"); ok(has("G 3 id=11559 name=懲戒 spent=12"), "懲戒 12")
        ok(has("ungroupedSpent=0"), "nothing ungrouped")
        local row = text:match("N 105626[^\n]*") or ""
        ok(row:find("tab=2 grp=11536,11541 rank=5/", 1, true), "盾牌壁壘: both groups, tab 2: " .. row)
        ok(row:find(" by=group$"), "how it was placed: " .. row)
    end)
end
