-- GF-011: roster talents. The own character's trait tree (Forever 1.60.1 has
-- no classic talent API), shared through GFTKS as local group "T", shown on
-- the roster card as 14/32/5 with the group icons, and the 「天賦連結」
-- action in the member menu. Made-up names, IDs and GUIDs only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local A_PEER = "0000-0000000B"
    local PEER = "測試乙-測試伺服器"
    local IMPORT = "BcQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

    -- A druid-like tree: 平衡 14, 野性戰鬥 32, 恢復 5, plus 1 rank outside any group.
    local function talents(over)
        local t = {
            configID = 7001, treeID = 900, specID = 102, import = IMPORT,
            groups = { { id = 11, name = "平衡", icon = 136096 }, { id = 12, name = "野性戰鬥", icon = 132276 },
                { id = 13, name = "恢復", icon = 136041 } },
            nodes = {},
        }
        local function add(group, ranks) t.nodes[#t.nodes + 1] = { id = 100 + #t.nodes, group = group, ranks = ranks } end
        add(11, 5); add(11, 5); add(11, 4)
        for _ = 1, 6 do add(12, 5) end
        add(12, 2); add(12, 0)
        add(13, 5)
        add(99, 1) -- not one of the three groups
        for k, v in pairs(over or {}) do t[k] = v end
        return t
    end

    local function login(opts)
        wow.reset(opts)
        local ns = wow.login(ADDON_DIR)
        ns.Share.rand = function(a) return a end
        if ns.Orders.resetSession then ns.Orders.resetSession() end
        if ns.Adventure.resetSession then ns.Adventure.resetSession() end
        wow.advance(25)
        return ns
    end
    local function vMsg(ns, a, t, v)
        return "S1~V~" .. a .. "~T~" .. ns.Share.b36(t) .. "~" .. ns.Share.hash(v) .. "~" .. v
    end
    local function from(ns, sender, text) return ns.Share.onMessage("GFTKS", text, "GUILD", sender) end
    local function sentWith(sub)
        local list = {}
        for _, s in ipairs(wow.state.sent) do
            if s.prefix == "GFTKS" and s.msg:find(sub, 1, true) then list[#list + 1] = s.msg end
        end
        return list
    end
    local function rowFor(ns, name)
        for _, r in ipairs(ns.UI.rows()) do if r:IsShown() and r.memberName == name then return r end end
    end
    local function peerValue(ns, over)
        local d = { treeID = 901, specID = 71, level = 60, import = IMPORT,
            groups = { { spent = 14, icon = 132355 }, { spent = 32, icon = 132347 }, { spent = 5, icon = 132341 } } }
        for k, v in pairs(over or {}) do d[k] = v end
        return ns.Talents.encode(d)
    end
    local function menuKeys(items)
        local out = {}
        for _, it in ipairs(items) do if it.key then out[it.key] = it end end
        return out
    end

    test("GF-011 codec: the T value round-trips; bad values are refused; T is local", function()
        local ns = login()
        local Tl = ns.Talents
        local v = peerValue(ns)
        ok(#v < 120, "fits one message: " .. #v)
        local d = Tl.decode(v)
        eq(d.treeID, 901, "tree"); eq(d.specID, 71, "spec"); eq(d.level, 60, "level")
        eq(#d.groups, 3, "three groups"); eq(d.groups[2].spent, 32, "points"); eq(d.groups[3].icon, 132341, "icon")
        eq(d.import, IMPORT, "import string"); eq(d.total, 51, "total")
        eq(Tl.decode(Tl.encode({ treeID = 5, level = 10, groups = { { spent = 3 } } })).groups[1].icon, nil, "no icon")
        eq(Tl.decode(Tl.encode({ treeID = 5, level = 10, groups = { { spent = 3 } } })).import, nil, "no import")
        for _, bad in ipairs({ "", "2.p0.1z.1o.e,w,5.,,.", "1.p0.1z.1o.e,w.,,.", "1.p0.1z.1o.e,w,5.,,.A|B",
            "1.0.1z.1o.e,w,5.,,.", "1.p0.1z.0.e,w,5.,,.", "1.p0.1z.1o.5k,5k,5k.,,.", "1.p0.1z.1o.E,w,5.,,.",
            "1.p0.1z.1o.,,,,,.,,,,.", "1.p0.1z.1o.e,w,5.,,", "1.p0.1z.1o.e,w,5.,,." .. string.rep("A", 121) }) do
            eq(Tl.decode(bad), nil, "refused: " .. bad)
        end
        ok(ns.Share.isLocalGroup("T"), "T is never uploaded by GF Sync (local)")
        eq(ns.Share.offer(A_PEER, "T", ns.Share.serverNow(), ns.Share.hash("1.x"), "1.x", true, A_PEER), "invalid", "malformed")
    end)

    test("GF-011 bare client (no trait API, classic globals nil): no talents, nothing sent, no errors", function()
        local ns = login()
        eq(GetTalentInfo, nil, "no GetTalentInfo"); eq(GetTalentTabInfo, nil, "no GetTalentTabInfo")
        eq(GetNumTalentTabs, nil, "no GetNumTalentTabs"); eq(GetActiveTalentGroup, nil, "no GetActiveTalentGroup")
        eq(GetUnspentTalentPoints, nil, "no GetUnspentTalentPoints"); eq(IsDualSpecUnlocked, nil, "no IsDualSpecUnlocked")
        local d, why = ns.Talents.read()
        eq(d, nil, "nothing read"); eq(why, "api", "why")
        eq(ns.Talents.ownValue(), nil, "no own value")
        wow.advance(40)
        eq(#sentWith("~T~"), 0, "no T record")
        ok(ns.Talents.diagText():find("沒有天賦介面", 1, true), "diag: " .. ns.Talents.diagText())
        ns.Framework.open("roster")
        ns.UI.showRowTooltip(rowFor(ns, "測試甲-測試伺服器"), nil)
        ok(not ns.UI.rosterCardText():find("天賦", 1, true), "no 天賦 section without data")
    end)

    test("GF-011 own talents: points per group from the trait nodes; shared as T after login", function()
        local ns = login({ talents = talents() })
        local d = ns.Talents.read()
        eq(d.groups[1].spent, 14, "平衡"); eq(d.groups[2].spent, 32, "野性戰鬥"); eq(d.groups[3].spent, 5, "恢復")
        eq(d.groups[2].name, "野性戰鬥", "group name"); eq(d.groups[1].icon, 136096, "group icon")
        eq(d.other, 1, "a rank outside the groups is not counted in any of them")
        eq(d.import, IMPORT, "import string"); eq(d.specID, 102, "spec"); eq(d.level, 32, "level")
        wow.advance(40)
        local S = ns.Share
        local rec = S.get(S.selfAuthor(), "T")
        ok(rec and rec.v == ns.Talents.ownValue(), "own T record stored (relayed on request like B/P)")
        local listed = false
        for _, m in ipairs(wow.state.sent) do
            if m.prefix == "GFTKS" and m.msg:find("~T%.") then listed = true end
        end
        ok(listed, "T is in the author's index")
        local mine = ns.Talents.of("Player-0000-0000000A")
        eq(mine.text, "14/32/5", "summary"); ok(mine.own, "own")
        ok(ns.Talents.summaryLine():find("14(平衡)/32(野性戰鬥)/5(恢復)", 1, true), "probe line: " .. ns.Talents.summaryLine())
        -- No groupIDs on the nodes (an unknown client): one total, never wrong groups.
        local ns2 = login({ talents = talents({ noGroupIDs = true }) })
        local d2 = ns2.Talents.read()
        eq(d2.groups[1].spent + d2.groups[2].spent + d2.groups[3].spent, 0, "no group gets points it may not have")
        eq(d2.other, 52, "all ranks are counted as outside the groups")
    end)

    test("GF-011 a talent change is read again and sent after a short wait; nobody is inspected", function()
        local t = talents()
        local ns = login({ talents = t })
        wow.advance(40)
        local inspected = 0
        NotifyInspect = function() inspected = inspected + 1 end
        local before = #sentWith("~T~")
        t.nodes[#t.nodes + 1] = { id = 500, group = 13, ranks = 3 }
        wow.installTalents()
        wow.fire("TRAIT_CONFIG_UPDATED", 7001)
        wow.advance(1)
        eq(#sentWith("~T~"), before, "not at once")
        wow.advance(40)
        ok(#sentWith("~T~") > before, "sent after the wait")
        eq(ns.Talents.of("Player-0000-0000000A").text, "14/32/8", "new points")
        eq(inspected, 0, "no inspect")
        NotifyInspect = nil
    end)

    test("GF-011 roster card: 天賦 14/32/5 with the group icons; 「天賦連結」 puts a talentbuild link in chat", function()
        local ns = login({ talents = talents() })
        local S = ns.Share
        eq(from(ns, PEER, vMsg(ns, A_PEER, S.serverNow() - 50, peerValue(ns))), "new", "peer talents stored")
        ns.Framework.open("roster")
        local peer = rowFor(ns, PEER)
        ns.UI.showRowTooltip(peer, nil)
        local text = ns.UI.rosterCardText()
        ok(text:find("天賦 14/32/5", 1, true), "card: " .. text)
        local card = ns.UI.rosterCard()
        ok(card.head.talent:IsShown(), "天賦 head")
        for i, icon in ipairs({ 132355, 132347, 132341 }) do
            ok(card.talentIcon[i]:IsShown(), "group icon " .. i)
            eq(card.talentIcon[i]._texture, icon, "the author's icon (tree not on this client)")
        end
        eq(card.talentText[2]:GetText(), "32", "points next to the icon")
        -- The section sits between 職責 and 專業.
        local function yOf(fs) return fs._points[#fs._points][5] end
        local yT, yR, yP = yOf(card.head.talent), yOf(card.head.role), yOf(card.head.prof)
        ok(yR > yT and yT > yP, "order 職責 > 天賦 > 專業: " .. yR .. " " .. yT .. " " .. yP)
        -- Member menu: 「天賦連結」.
        local items = menuKeys(ns.UI.memberMenuItems(peer.member))
        ok(items.talentlink, "menu has 天賦連結")
        eq(items.talentlink.text, "天賦連結", "label")
        local inserted
        ChatEdit_InsertLink = function(link) inserted = link; return true end
        items.talentlink.fn()
        ChatEdit_InsertLink = nil
        ok(inserted and inserted:find("|Htalentbuild:71:60:" .. IMPORT .. "|h[", 1, true), "link: " .. tostring(inserted))
        ok(inserted:find("14/32/5", 1, true), "link text has the summary")
        -- No chat box function: opens the chat with the link.
        local opened
        ChatFrame_OpenChat = function(t) opened = t end
        eq((ns.Talents.insertLink(peer.memberGuid, PEER)), true, "opened chat")
        ChatFrame_OpenChat = nil
        ok(opened and opened:find("talentbuild", 1, true), "opened with the link")
    end)

    test("GF-011 no link without an import string, a spec, or the talentbuild link type", function()
        local ns = login({ talents = talents() })
        local S = ns.Share
        local PEER_C = "測試丙-測試伺服器"
        from(ns, PEER, vMsg(ns, A_PEER, S.serverNow() - 50, peerValue(ns, { import = "" })))
        from(ns, PEER_C, vMsg(ns, "0000-0000000C", S.serverNow() - 50, peerValue(ns, { specID = 0 })))
        ns.Framework.open("roster")
        ok(not menuKeys(ns.UI.memberMenuItems(rowFor(ns, PEER).member)).talentlink, "no import: no link")
        ok(not menuKeys(ns.UI.memberMenuItems(rowFor(ns, PEER_C).member)).talentlink, "no spec: no link")
        ns.UI.showRowTooltip(rowFor(ns, PEER), nil)
        ok(ns.UI.rosterCardText():find("天賦 14/32/5", 1, true), "the summary still shows")
        local ns2 = login({ talents = talents({ noLink = true }) })
        ns2.Framework.open("roster")
        ok(not menuKeys(ns2.UI.memberMenuItems(rowFor(ns2, "測試甲-測試伺服器").member)).talentlink, "no link type: no link")
        eq(ns2.Talents.insertLink("Player-0000-0000000A"), false, "insertLink refuses")
    end)

    test("GF-011 privacy: talents never reach GF Sync's outbox; probe and diag have a line", function()
        local ns = login({ talents = talents() })
        wow.advance(40)
        ok(ns.Talents.diagText():find("14(平衡)/32(野性戰鬥)/5(恢復)", 1, true), "diag: " .. ns.Talents.diagText())
        ns.Probe.run("main")
        local p = GreenFangToolkitDB.probe.main.talents
        ok(type(p.gf011) == "string" and p.gf011:find("14", 1, true), "probe gf011: " .. tostring(p.gf011))
        local saved = wow.logout()
        local db = saved.GreenFangToolkitDB or GreenFangToolkitDB
        local function walk(t, path)
            for k, v in pairs(t) do
                ok(k ~= "T" and k ~= "talents", "outbox key " .. path .. "." .. tostring(k))
                if type(v) == "string" then ok(not v:find(IMPORT, 1, true), "import string in outbox at " .. path) end
                if type(v) == "table" then walk(v, path .. "." .. tostring(k)) end
            end
        end
        walk(db.sync.outbox, "outbox")
    end)
end
