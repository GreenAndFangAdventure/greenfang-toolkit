-- GF-DIGEST-01: /gftkdev traits (GreenFangToolkit_Dev/TraitDump.lua), the
-- talent tree's IDs as copyable text: the line format, the total line count
-- on line 1, every node (also unranked), APIs the client lacks written out,
-- no names or GUIDs, nothing in combat, no events / timers / OnUpdate, parts.
-- Made-up IDs and names; the C_Traits field names are not checked in Forever.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local ROOT = ADDON_DIR:gsub("/addon/GreenFangToolkit$", "")
    local DEV_DIR = ROOT .. "/addon/GreenFangToolkit_Dev"

    local function readAll(path) local h = io.open(path, "rb"); if not h then return nil end local s = h:read("*a"); h:close(); return s end
    local function tocFiles()
        local out = {}
        for line in (readAll(DEV_DIR .. "/GreenFangToolkit_Dev.toc") or ""):gmatch("[^\r\n]+") do
            if line:match("^[%w_]+%.lua$") then out[#out + 1] = line end
        end
        return out
    end
    local function lines(text)
        local out = {}
        for l in (text .. "\n"):gmatch("([^\n]*)\n") do out[#out + 1] = l end
        return out
    end
    local function has(text, s) return text:find(s, 1, true) ~= nil end

    -- Three tabs, five nodes (two unranked, one with two entries / a choice).
    local function talents(extra)
        local t = { configID = 9001, treeID = 801, specID = 0, import = "ABC",
            groups = { { id = 11, name = "戒律" }, { id = 12, name = "神聖" }, { id = 13, name = "暗影" } },
            nodes = { { id = 2001, group = 11, ranks = 2 }, { id = 2002, group = 11, ranks = 0 },
                { id = 2003, group = 12, ranks = 1 }, { id = 2004, group = 13, ranks = 0 }, { id = 2005, group = 11, ranks = 1 } } }
        for k, x in pairs(extra or {}) do t[k] = x end
        return t
    end
    -- The fields the roster mock leaves out (entryIDs, maxRanks, activeEntry),
    -- and spell names: 3xxxx entries, 4xxxx definitions, 5xxxx spells.
    local function patchTraits(t)
        local byId = {}
        for _, n in ipairs(t.nodes) do byId[n.id] = n end
        C_Traits.GetNodeInfo = function(_, id)
            local n = byId[id]
            if not n then return nil end
            local entries = { 30000 + id }
            if id == 2005 then entries[2] = 31000 + id end
            return { ID = id, activeRank = n.ranks, ranksPurchased = n.ranks, currentRank = n.ranks, maxRanks = 3,
                posX = id, posY = 100, isVisible = true, type = id == 2005 and 2 or 0, groupIDs = { n.group }, entryIDs = entries,
                activeEntry = n.ranks > 0 and { entryID = entries[#entries], rank = n.ranks } or nil }
        end
        C_Traits.GetEntryInfo = function(_, e) return { definitionID = e + 10000, maxRanks = 3, type = 1 } end
        C_Traits.GetDefinitionInfo = function(d) return { spellID = d + 10000 } end
        C_Traits.GetConfigInfo = function(id)
            if id ~= t.configID then return nil end
            return { ID = id, type = 1, name = "私人配置名", treeIDs = { t.treeID } }
        end
        C_Spell = { GetSpellName = function(id) return "法術" .. id end }
    end

    local function loadDev(opts)
        opts = opts or {}
        wow.reset({ talents = opts.talents or talents() })
        if not opts.raw then patchTraits(wow.state.talents) end
        if opts.before then opts.before() end
        local D = {}
        for _, file in ipairs(tocFiles()) do assert(loadfile(DEV_DIR .. "/" .. file))("GreenFangToolkit_Dev", D) end
        wow.fire("ADDON_LOADED", "GreenFangToolkit_Dev")
        wow.fire("PLAYER_ENTERING_WORLD")
        return D, D.TraitDump
    end
    local function slash(msg) SlashCmdList.GFTKDEV(msg) end
    local function done(fn) return function() local okRun, err = pcall(fn); GreenFangToolkitDevDB = nil; if not okRun then error(err, 0) end end end

    test("GF-DIGEST-01 /gftkdev traits: line 1 = total lines, header, tabs with points, every node with entry/definition/spell", done(function()
        local _, TD = loadDev()
        slash("traits")
        local text = TD.copyText()
        ok(text, "the copy window has the text")
        local L = lines(text)
        local total = tonumber(L[1]:match("^GF%-TRAITDUMP v1 lines=(%d+) parts=1$"))
        eq(total, #L, "line 1 says how many lines there are")
        eq(L[2], "# part 1/1 lines 2-" .. #L .. " of " .. #L, "the part line")
        ok(has(text, "H class=DRUID "), "class token")
        ok(has(text, " version=1.16.1 build=99999 toc=16001"), "GetBuildInfo")
        ok(has(text, "H configID=9001 configFrom=C_ClassTalents.GetActiveConfigID configType=1 treeID=801 treeIDs=801"), "config and tree")
        ok(has(text, "G 1 id=11 name=戒律 spent=3"), "tab 1, its points")
        ok(has(text, "G 2 id=12 name=神聖 spent=1"), "tab 2")
        ok(has(text, "G 3 id=13 name=暗影 spent=0"), "tab 3")
        ok(has(text, "H nodes=5 listed=5 tabs=3 ungroupedSpent=0"), "node count")
        ok(has(text, "N 2001 tab=1 grp=11 rank=2/3 cur=2 active=2 vis=1 type=0 pos=2001,100 sub=? E=32001:42001:52001:法術52001:*"), "a ranked node")
        ok(has(text, "N 2002 tab=1 grp=11 rank=0/3 cur=0 active=0 vis=1 type=0 pos=2002,100 sub=? E=32002:42002:52002:法術52002"), "an unranked node is listed too")
        ok(has(text, "N 2004 tab=3 grp=13 rank=0/3"), "unranked, another tab")
        ok(has(text, "E=32005:42005:52005:法術52005;33005:43005:53005:法術53005:*"), "a choice node: both entries, the chosen one marked")
        local n = 0
        for _, l in ipairs(L) do if l:match("^N %d+ ") then n = n + 1 end end
        eq(n, 5, "one line per node")
        ok(has(text, "! MISSING GetNumSpecializations"), "the mock has no spec count: said, not skipped")
        ok(TD.window():IsShown(), "window shown")
    end))

    test("GF-DIGEST-01 /gftkdev traits: missing or empty APIs are written out by name", done(function()
        local _, TD = loadDev({ before = function()
            C_Traits.GetEntryInfo = nil
            C_Spell = nil
            local real = C_Traits.GetNodeInfo
            C_Traits.GetNodeInfo = function(cfg, id) if id == 2003 then return nil end return real(cfg, id) end
        end })
        slash("traits")
        local text = TD.copyText()
        ok(has(text, "! MISSING C_Traits.GetEntryInfo"), "no GetEntryInfo")
        ok(has(text, "N 2003 ! EMPTY C_Traits.GetNodeInfo"), "the node it could not read stays in the list")
        ok(has(text, "! EMPTY C_Traits.GetNodeInfo n=1 first=9001,2003"), "and is counted")
        ok(has(text, "E=32001:?:?:?"), "entry ID kept, the rest ?")
        ok(not has(text, "! none"), "not 'every API answered'")

        local _, TD2 = loadDev({ raw = true, talents = talents(), before = function() C_Traits = nil; C_ClassTalents = nil; C_SpecializationInfo = nil end })
        slash("traits")
        local t2 = TD2.copyText()
        ok(has(t2, "! MISSING C_ClassTalents.GetActiveConfigID"), "no config API")
        ok(has(t2, "H configID=? configFrom=? configType=? treeID=? treeIDs=?"), "header says ? for what it could not get")
        ok(has(t2, "H nodes=0 listed=0 tabs=0"), "no nodes")
        local L = lines(t2)
        eq(tonumber(L[1]:match("lines=(%d+)")), #L, "line count still right")
    end))

    test("GF-DIGEST-01 /gftkdev traits: no character / realm / guild name, no GUID, no loadout name", done(function()
        local _, TD = loadDev()
        slash("traits")
        local text = TD.copyText()
        local p = wow.defaultPlayer()
        for _, s in ipairs({ p.name, p.realm, p.guild, p.guid, "Player-", "私人配置名" }) do
            ok(not has(text, s), "not in the dump: " .. s)
        end
        for _, l in ipairs(wow.printed()) do ok(not has(l, p.name) and not has(l, p.guid), "chat line clean") end
    end))

    test("GF-DIGEST-01 /gftkdev traits: refused in combat; only on the command (no events, timers, OnUpdate)", done(function()
        local _, TD = loadDev()
        local timers = #wow.state.timers
        local reads = wow.state.talentReads
        eq(reads, 0, "loading reads nothing")
        wow.setCombat(true)
        slash("traits")
        eq(TD.parts, nil, "no dump in combat")
        eq(TD.window(), nil, "no window in combat")
        eq(wow.state.talentReads, 0, "no tree read in combat")
        local said = table.concat(wow.printed(), "\n")
        ok(has(said, "戰鬥中不執行"), "says why")
        wow.setCombat(false)
        slash("traits")
        eq(wow.state.talentReads, 1, "one read on the command")
        eq(#wow.state.timers, timers, "no timer")
        for _, f in ipairs(wow.state.frames) do
            ok(f:GetScript("OnUpdate") == nil, "no OnUpdate")
            if f._events then
                for e in pairs(f._events) do
                    ok(e == "PLAYER_ENTERING_WORLD" or e == "GET_ITEM_INFO_RECEIVED" or e == "ITEM_DATA_LOAD_RESULT",
                        "only CatalogScan's events: " .. e)
                end
            end
        end
    end))

    test("GF-DIGEST-01 /gftkdev traits: a long tree in parts; every part's lines add up; /gftkdev traits 2 reads nothing new", done(function()
        local nodes = {}
        for i = 1, 300 do nodes[i] = { id = 5000 + i, group = 11 + (i % 3), ranks = i % 4 == 0 and 1 or 0 } end
        local _, TD = loadDev({ talents = talents({ nodes = nodes }) })
        TD.PART_LIMIT = 3000
        slash("traits")
        local n = #TD.parts
        ok(n >= 3, "several parts: " .. n)
        local first = lines(TD.parts[1])
        local total = tonumber(first[1]:match("^GF%-TRAITDUMP v1 lines=(%d+) parts=" .. n .. "$"))
        local sum, nodeLines = 0, 0
        for i, p in ipairs(TD.parts) do
            ok(#p <= TD.PART_LIMIT + 80, "part " .. i .. " fits")
            local L = lines(p)
            local head = L[i == 1 and 2 or 1]
            local a, b = head:match("^# part " .. i .. "/" .. n .. " lines (%d+)%-(%d+) of " .. total .. "$")
            ok(a, "part line " .. i)
            eq(tonumber(b) - tonumber(a) + 1, #L - (i == 1 and 1 or 0), "part " .. i .. " range")
            sum = sum + #L
            for _, l in ipairs(L) do if l:match("^N %d+ ") then nodeLines = nodeLines + 1 end end
        end
        eq(sum, total, "all parts together are line 1's count")
        eq(nodeLines, 300, "every node once")
        ok(TD.window().nextButton:IsShown(), "下一段 button")
        local reads = wow.state.talentReads
        slash("traits 2")
        eq(TD.shown, 2, "part 2 shown")
        eq(TD.copyText(), TD.parts[2], "its text")
        eq(wow.state.talentReads, reads, "no new read")
        TD.window().nextButton:GetScript("OnClick")()
        eq(TD.shown, 3 <= n and 3 or 1, "下一段 goes on")
    end))
end
