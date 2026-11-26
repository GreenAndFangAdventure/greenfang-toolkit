-- GF-011-B: 「天賦樹」 opens the game's own talent window (the own tree, or a
-- member's build view-only from the shared import string), and 「製作」 on an
-- accepted order opens the profession window with the recipe. The native
-- functions are fakes with Forever 1.60.1's names (WoWBlzCode Forever).
-- Made-up names, IDs and GUIDs only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local SELF_GUID = "Player-0000-0000000A"
    local A_PEER, PEER_GUID, PEER = "0000-0000000B", "Player-0000-0000000B", "測試乙-測試伺服器"
    local IMPORT = "BcQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

    local function talents()
        return { configID = 7001, treeID = 900, specID = 102, import = IMPORT,
            groups = { { id = 11, name = "平衡", icon = 136096 }, { id = 12, name = "野性戰鬥", icon = 132276 },
                { id = 13, name = "恢復", icon = 136041 } },
            nodes = { { id = 1, group = 11, ranks = 5 }, { id = 2, group = 12, ranks = 3 } } }
    end
    local function login(opts)
        opts = opts or {}
        if opts.talents == nil then opts.talents = talents() end
        wow.reset(opts)
        local ns = wow.login(ADDON_DIR)
        ns.Share.rand = function(a) return a end
        if ns.Orders.resetSession then ns.Orders.resetSession() end
        if ns.Adventure.resetSession then ns.Adventure.resetSession() end
        wow.advance(25)
        return ns
    end
    local function peerTalents(ns, over)
        local d = { treeID = 901, specID = 71, level = 60, import = IMPORT,
            groups = { { spent = 14 }, { spent = 32 }, { spent = 5 } } }
        for k, v in pairs(over or {}) do d[k] = v end
        local v = ns.Talents.encode(d)
        local msg = "S1~V~" .. A_PEER .. "~T~" .. ns.Share.b36(ns.Share.serverNow() - 50) .. "~" .. ns.Share.hash(v) .. "~" .. v
        return ns.Share.onMessage("GFTKS", msg, "GUILD", PEER)
    end

    -- Fakes of the game's talent window entry points; returns the call log.
    local NATIVE = { "PlayerSpellsUtil", "PlayerSpellsFrame", "SetItemRef", "HideUIPanel", "ChatEdit_InsertLink",
        "ProfessionsUtil", "OpenProfessionUIToSkillLine", "TogglePlayerSpellsFrame", "ToggleTalentFrame" }
    local saved
    local function native(opts)
        opts = opts or {}
        saved = {}
        for _, n in ipairs(NATIVE) do saved[n] = _G[n] end
        local log = {}
        local inspectingNow = false
        if not opts.noFrame then
            PlayerSpellsFrame = { IsInspecting = function() return inspectingNow end }
        end
        if not opts.noUtil then
            PlayerSpellsUtil = {
                OpenToClassTalentsTab = function() log[#log + 1] = "own" end,
                InspectLoadout = function(data)
                    log[#log + 1] = "inspect:" .. data
                    inspectingNow = not opts.refuse
                end,
            }
        end
        HideUIPanel = function() log[#log + 1] = "hide" end
        if opts.itemRef then SetItemRef = function(link, text) log[#log + 1] = "ref:" .. link end end
        ChatEdit_InsertLink = function(link) log[#log + 1] = "chat:" .. link; return true end
        return log
    end
    local function restore()
        for _, n in ipairs(NATIVE) do _G[n] = saved[n] end
    end
    local function menuKeys(ns, m)
        local out = {}
        for _, it in ipairs(ns.UI.memberMenuItems(m)) do if it.key then out[it.key] = it end end
        return out
    end
    local function rowFor(ns, name)
        for _, r in ipairs(ns.UI.rows()) do if r:IsShown() and r.memberName == name then return r end end
    end

    test("GF-011-B 天賦樹: the own card opens the normal talent window", function()
        local ns = login()
        local log = native()
        eq(ns.Talents.treeMode(SELF_GUID), "own", "own mode")
        local okO, how = ns.Talents.openTree(SELF_GUID)
        eq(okO, true, "opened"); eq(how, "own", "how"); eq(log[1], "own", "OpenToClassTalentsTab")
        restore()
        -- Without PlayerSpellsUtil: TogglePlayerSpellsFrame(2) (the talents tab).
        local tab
        log = native({ noUtil = true })
        TogglePlayerSpellsFrame = function(t) tab = t end
        eq(select(2, ns.Talents.openTree(SELF_GUID)), "own", "toggle"); eq(tab, 2, "talents tab")
        restore()
    end)

    test("GF-011-B 天賦樹: another member's build opens view-only from the import string", function()
        local ns = login()
        eq(peerTalents(ns), "new", "peer talents stored")
        local log = native()
        eq(ns.Talents.treeMode(PEER_GUID), "view", "view mode")
        local okO, how = ns.Talents.openTree(PEER_GUID, PEER)
        eq(okO, true, "opened"); eq(how, "view", "how")
        eq(log[1], "inspect:71:60:" .. IMPORT, "InspectLoadout(<spec>:<level>:<import>), like a link click")
        eq(#log, 1, "nothing else (no chat, no hide)")
        restore()
        -- The game refuses the string (it then shows the own tree): closed, the chat link instead.
        log = native({ refuse = true })
        local okR, howR = ns.Talents.openTree(PEER_GUID, PEER)
        eq(okR, true, "fell back"); eq(howR, "chat", "the chat link")
        eq(log[2], "hide", "the own tree it fell back to is closed")
        ok(log[3] and log[3]:find("|Htalentbuild:71:60:" .. IMPORT .. "|h", 1, true), "link in chat: " .. tostring(log[3]))
        restore()
        -- No InspectLoadout, but SetItemRef: the link is opened the native way.
        log = native({ noUtil = true, itemRef = true })
        eq(ns.Talents.treeMode(PEER_GUID), "ref", "ref mode")
        eq(select(2, ns.Talents.openTree(PEER_GUID, PEER)), "ref", "SetItemRef")
        eq(log[1], "ref:talentbuild:71:60:" .. IMPORT, "the hyperlink")
        restore()
        -- Neither: the chat link.
        log = native({ noUtil = true })
        eq(select(2, ns.Talents.openTree(PEER_GUID, PEER)), "chat", "chat")
        restore()
    end)

    test("GF-011-B 天賦樹 is greyed with nothing to show or in combat; the menu has it only when it can open", function()
        local ns = login()
        native()
        peerTalents(ns)
        ns.Framework.open("roster")
        local card = ns.ProfileUI.openCard(rowFor(ns, PEER).member)
        ok(card.tree:IsShown(), "天賦樹 on the card")
        eq(card.tree.gfEnabled ~= false, true, "enabled")
        eq(card.talentText:GetText(), "14/32/5", "the summary")
        ok(menuKeys(ns, rowFor(ns, PEER).member).talenttree, "menu has 天賦樹")
        eq(menuKeys(ns, rowFor(ns, PEER).member).talenttree.text, "天賦樹", "label")
        -- 測試丙: nothing received.
        local third = rowFor(ns, "測試丙-測試伺服器").member
        card = ns.ProfileUI.openCard(third)
        eq(card.tree.gfEnabled, false, "greyed: nothing received")
        eq(card.tree.tip, "沒有收到天賦", "why")
        eq(card.talentText:GetText(), "未知", "未知")
        ok(not menuKeys(ns, third).talenttree, "no menu item")
        -- No import string: greyed too.
        peerTalents(ns, { import = "" })
        wow.advance(1)
        -- (an older record with the same t is kept; a newer one replaces it)
        local v = ns.Talents.encode({ treeID = 901, specID = 71, level = 60, groups = { { spent = 1 } } })
        ns.Share.onMessage("GFTKS", "S1~V~" .. A_PEER .. "~T~" .. ns.Share.b36(ns.Share.serverNow()) .. "~"
            .. ns.Share.hash(v) .. "~" .. v, "GUILD", PEER)
        card = ns.ProfileUI.openCard(rowFor(ns, PEER).member)
        eq(card.tree.gfEnabled, false, "greyed: no import string")
        eq(card.tree.tip, "沒有匯出字串", "why")
        -- Combat: greyed, and openTree refuses.
        wow.enterCombat()
        card = ns.ProfileUI.openCard(rowFor(ns, "測試甲-測試伺服器").member)
        eq(card.tree.gfEnabled, false, "greyed in combat")
        eq(card.tree.tip, "戰鬥中不能開", "why")
        local okC, why = ns.Talents.openTree(SELF_GUID)
        eq(okC, false, "refused"); eq(why, "combat", "combat")
        wow.leaveCombat()
        restore()
    end)

    ---------------------------------------------------------------------------
    -- 「製作」
    ---------------------------------------------------------------------------

    local LEATHER, BOOTS, BOOTS_ITEM = 165, 2149, 2307 -- the default character has 製皮 (165)
    local SMITH, STONE, STONE_ITEM = 164, 2660, 2862   -- and no 鍛造 (164)

    local function acceptedTest(ns, recipe, skill, item)
        local O = ns.Orders
        O.setTestMode(true)
        local id = O.placeTest({ recipe = recipe, skill = skill, item = item, qty = 1 })
        ok(id, "test order placed")
        O.press(O.get(id), "accept")
        eq(O.get(id).state, "making", "accepted")
        return id
    end
    local function rowOf(ns, id)
        ns.Framework.open("orders")
        ns.OrdersUI.refresh()
        for _, r in ipairs(ns.OrdersUI.rowFrames()) do
            if r:IsShown() and r.view and r.view.id == id then return r end
        end
    end
    local function craftButton(row)
        for _, b in ipairs(row.buttons) do if b:IsShown() and b.action == "craft" then return b end end
    end

    test("GF-011-B 製作 on an accepted order opens the profession window at the recipe", function()
        local ns = login()
        local log = {}
        saved = {}
        for _, n in ipairs(NATIVE) do saved[n] = _G[n] end
        ProfessionsUtil = { OpenProfessionFrameToRecipe = function(r) log[#log + 1] = "recipe:" .. r; return true end }
        local id = acceptedTest(ns, BOOTS, LEATHER, BOOTS_ITEM)
        local row = rowOf(ns, id)
        ok(row, "row on the page")
        local b = craftButton(row)
        ok(b, "製作 button")
        eq(b.label:GetText(), "製作", "label")
        eq(b.gfEnabled ~= false, true, "enabled (I have 製皮)")
        b:GetScript("OnClick")(b)
        eq(log[1], "recipe:" .. BOOTS, "OpenProfessionFrameToRecipe(recipe)")
        eq(b.lastCraft, true, "opened")
        -- The other buttons are still there (交付, 取消) and nothing was crafted or pressed.
        eq(ns.Orders.get(id).state, "making", "the order did not move")
        -- Only C_TradeSkillUI.OpenTradeSkill: the window without the recipe.
        ProfessionsUtil = nil
        local opened
        C_TradeSkillUI = { OpenTradeSkill = function(s) opened = s; return true end }
        local okP, how = ns.Recipes.openCraft(LEATHER, BOOTS)
        eq(okP, true, "opened"); eq(how, "profession", "window only"); eq(opened, LEATHER, "the order's profession")
        C_TradeSkillUI = nil
        restore()
    end)

    test("GF-011-B 製作 is greyed without the profession, in combat, or with no way to open it", function()
        local ns = login()
        saved = {}
        for _, n in ipairs(NATIVE) do saved[n] = _G[n] end
        local calls = 0
        ProfessionsUtil = { OpenProfessionFrameToRecipe = function() calls = calls + 1; return true end }
        local id = acceptedTest(ns, STONE, SMITH, STONE_ITEM)
        local b = craftButton(rowOf(ns, id))
        ok(b, "shown")
        eq(b.gfEnabled, false, "greyed: no 鍛造")
        ok(b.tex._desaturated, "icon desaturated")
        ok(b.tip:find("你沒有這個專業", 1, true), "why: " .. tostring(b.tip))
        eq(select(2, ns.Recipes.openCraft(SMITH, STONE)), "noprof", "refused")
        eq(calls, 0, "never called")
        wow.enterCombat()
        eq(select(2, ns.Recipes.canCraft(LEATHER)), "combat", "combat")
        wow.leaveCombat()
        ProfessionsUtil = nil
        eq(select(2, ns.Recipes.canCraft(LEATHER)), "noui", "no way to open it")
        restore()
    end)

    test("GF-011-B 製作 only on 製作中 orders I craft: not while waiting, not as the customer", function()
        local ns = login()
        local O = ns.Orders
        O.setTestMode(true)
        local id = O.placeTest({ recipe = BOOTS, skill = LEATHER, item = BOOTS_ITEM, qty = 1 })
        ok(not craftButton(rowOf(ns, id)), "waiting: no 製作")
        local me = ns.Share.selfAuthor()
        local v = { state = "making", skill = LEATHER, customer = me, crafter = A_PEER }
        eq(ns.OrdersUI.showsCraft(v, me), false, "customer: no 製作")
        v.crafter, v.customer = me, A_PEER
        eq(ns.OrdersUI.showsCraft(v, me), true, "crafter: 製作")
        v.state = "checking"
        eq(ns.OrdersUI.showsCraft(v, me), false, "after delivery: no 製作")
    end)
end
