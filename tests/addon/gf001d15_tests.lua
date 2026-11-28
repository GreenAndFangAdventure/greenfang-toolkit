-- GF-001-D15: data was never shared between two different players (0.16.22,
-- the first time two players used it). The roster of this realm gives
-- same-realm names without "-Realm" while CHAT_MSG_ADDON senders carry
-- "Name-Realm", so every message was dropped as not-in-roster. Also: the
-- receive counts in 同步與診斷, /gftk probe share and the 清除結案 button.
-- Offline only; the real sender format still has to be seen in the client
-- (/gftk probe share). Made-up names and GUIDs.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR

    local REALM = "測試 伺服器 1 PvE"     -- spaces, like the real one
    local SENDER_REALM = "測試伺服器1PvE" -- how CHAT_MSG_ADDON writes it

    -- The realm's roster: same-realm names WITHOUT "-Realm" (as in the owner's save).
    local function bareRoster()
        local r = wow.defaultRoster()
        for _, m in ipairs(r) do m.name = m.name:match("^([^-]+)") end
        return r
    end
    local function login(opts)
        opts = opts or {}
        local player = wow.defaultPlayer()
        player.realm = REALM
        wow.reset({ player = player, roster = opts.roster or bareRoster() })
        local ns = wow.login(ADDON_DIR)
        ns.Share.rand = function(a) return a end
        wow.advance(25)
        return ns
    end
    local function has(s, sub) return tostring(s):find(sub, 1, true) ~= nil end
    -- A level/class record of author a, as its author would send it.
    local function vMsg(ns, a, t)
        local v = ns.Share.encodeValue("B", { level = 44, classToken = "WARRIOR" })
        return "S1~V~" .. a .. "~B~" .. ns.Share.b36(t) .. "~" .. ns.Share.hash(v) .. "~" .. v
    end
    local A_B = "0000-0000000B"

    test("GF-001-D15 1 a bare roster name matches a Name-Realm sender of our realm", function()
        local ns = login()
        local bare = false
        for _, mm in ipairs(ns.Roster.current().members) do if mm.name == "測試乙" then bare = true end end
        ok(bare, "roster name has no realm")
        local m = ns.Comm.memberFor("測試乙-" .. SENDER_REALM)
        ok(m and m.guid == "Player-" .. A_B, "Name-Realm (no spaces) finds the member")
        ok(ns.Comm.memberFor("測試乙") == m, "a bare sender still works")
        eq(ns.Comm.memberFor("測試乙-別的伺服器"), nil, "another realm never matches a bare name")
        eq(ns.Comm.memberFor("無此人-" .. SENDER_REALM), nil, "someone not in the roster")
    end)

    test("GF-001-D15 2 a record from another player is stored (was not-in-roster)", function()
        local ns = login()
        local r = ns.Share.onMessage("GFTKS", vMsg(ns, A_B, wow.state.now - 10), "GUILD", "測試乙-" .. SENDER_REALM)
        ok(r ~= "not-in-roster", "not dropped: " .. tostring(r))
        ok(ns.Share.get(A_B, "B"), "the record is kept")
        -- The ledgers (orders, adventure, prices) use the same lookup.
        local lr = ns.Orders.ledger:onMessage(ns.Orders.PREFIX, "x", "GUILD", "測試乙-" .. SENDER_REALM)
        ok(lr ~= "not-in-roster", "orders ledger knows the sender: " .. tostring(lr))
    end)

    test("GF-001-D15 3 roster names WITH the realm keep working", function()
        local r = wow.defaultRoster()
        for _, m in ipairs(r) do m.name = m.name:match("^([^-]+)") .. "-" .. REALM end
        local ns = login({ roster = r })
        ok(ns.Comm.memberFor("測試乙-" .. SENDER_REALM), "full name")
        ok(ns.Comm.memberFor("測試乙"), "bare sender")
    end)

    test("GF-001-D15 4 receive counts: echo, buckets, heard members, no names shown", function()
        local ns = login()
        ns.Comm.resetRx()
        wow.fire("CHAT_MSG_ADDON", "GFTKS", vMsg(ns, A_B, wow.state.now - 5), "GUILD", "測試乙-" .. SENDER_REALM)
        wow.fire("CHAT_MSG_ADDON", "GFTKS", "S1~Q~x~0~0", "GUILD", "測試甲-" .. SENDER_REALM) -- my echo
        wow.fire("CHAT_MSG_ADDON", "GFTKS", "S1~Q~x~0~0", "GUILD", "陌生人-" .. SENDER_REALM)
        wow.fire("CHAT_MSG_ADDON", "GFTKS", "S9~Q", "GUILD", "測試乙-" .. SENDER_REALM)
        wow.fire("CHAT_MSG_ADDON", "OTHERADDON", "hi", "GUILD", "測試乙-" .. SENDER_REALM)
        local rx = ns.Comm.rx()
        eq(rx.total, 4, "only toolkit prefixes are counted")
        eq(rx.self, 1, "my own echo")
        eq(rx.ok, 1, "taken")
        eq(rx.roster, 1, "sender not in the roster")
        eq(rx.version, 1, "other version")
        local text = ns.Diag.shareText()
        ok(has(text, "工具箱訊息 4 則，自己回音 1"), text)
        ok(has(text, "寄件人不在名冊 1"), text)
        ok(has(text, "聽到的線上會友 1 位"), "測試乙 is online in the mock roster: " .. text)
        ok(has(text, "前綴註冊 成功"), text)
        ok(has(text, "公會狀態 本公會"), text)
        ok(has(text, "名冊 4 人（有 GUID 4）"), text)
        for _, n in ipairs({ "測試甲", "測試乙", "陌生人", "Player-", "0000-" }) do
            ok(not has(text, n), "no name or GUID in the diag: " .. n)
        end
    end)

    test("GF-001-D15 5 prefix and send results are shown in plain words", function()
        local ns = login()
        local C = ns.Comm
        eq(C.sendResultText(0), "成功")
        eq(C.sendResultText(true), "成功")
        eq(C.sendResultText(nil), "沒有回傳")
        ok(has(C.sendResultText(3), "被節流"), "throttle")
        ok(has(C.sendResultText(10), "代碼 10"), "an unknown failure keeps its code")
        C_ChatInfo.RegisterAddonMessagePrefix = function() return 3 end
        C.registerPrefix("GFTKZ")
        ok(has(C.prefixText(), "GFTKZ 失敗 3"), C.prefixText())
        C.prefixResults.GFTKZ = nil
        -- The last SendAddonMessage answer is remembered (here a refused one).
        C_ChatInfo.SendAddonMessage = function() return 10 end
        C.broadcast(true)
        ok(has(ns.Diag.shareText(), "最後送出 失敗（代碼 10）"), ns.Diag.shareText())
    end)

    test("GF-001-D15 6 /gftk probe share: one message, echo, sender shape, no name printed", function()
        local ns = login()
        wow.state.sent, wow.state.printed = {}, {}
        local timersBefore = #wow.state.timers
        ns.handleSlash("probe share")
        eq(#wow.state.sent, 1, "exactly one message")
        local m = wow.state.sent[1]
        eq(m.prefix .. "|" .. m.chatType, "GFTK|GUILD", "on the guild channel")
        ok(m.msg:match("^probe~%w+$"), "a probe message")
        ns.handleSlash("probe share")
        eq(#wow.state.sent, 1, "a second one while waiting is not sent")
        -- The server echoes it back with my name and realm.
        wow.fire("CHAT_MSG_ADDON", "GFTK", m.msg, "GUILD", "測試甲-" .. SENDER_REALM)
        -- Someone else hearing it does not store anything.
        local stored, why = ns.Comm.onMessage("GFTK", m.msg, "GUILD", "測試乙-" .. SENDER_REALM)
        eq(tostring(stored) .. "|" .. tostring(why), "false|probe", "never data")
        wow.advance(ns.Comm.PROBE_WAIT + 1)
        local out = table.concat(wow.state.printed, "\n")
        ok(has(out, "送出測試訊息：成功"), out)
        ok(has(out, "自己的回音：有聽到"), out)
        ok(has(out, "寄件人格式：名字-伺服器｜伺服器含空白：否｜伺服器和本角色相同：是"), out)
        ok(has(out, "這個寄件人對得到名冊：是｜認得是自己：是"), out)
        ok(has(out, "名字不含伺服器 4 人"), out)
        ok(not has(out, "測試甲") and not has(out, "測試乙"), "no character name printed")
        ok(has(ns.Probe.copyText() or "", "分享測試"), "the copy window has it")
        local probes = 0
        for _, x in ipairs(wow.state.sent) do if x.msg:match("^probe~") then probes = probes + 1 end end
        eq(probes, 1, "no other test message was sent")
        ok(#wow.state.timers <= timersBefore + 1, "no repeating timer added")
    end)

    test("GF-001-D15 7 probe without an echo says so", function()
        local ns = login()
        wow.state.printed = {}
        ns.handleSlash("probe share")
        wow.advance(ns.Comm.PROBE_WAIT + 1)
        local out = table.concat(wow.state.printed, "\n")
        ok(has(out, "自己的回音：沒聽到"), out)
    end)

    test("GF-001-D15 8 the clear button says what it deletes", function()
        local ns = login()
        ns.Diag.open()
        eq(ns.Diag.clearButton:GetText(), "清除結案")
        ns.Diag.clearButton:GetScript("OnEnter")(ns.Diag.clearButton)
        local tip = {}
        for _, l in ipairs(GameTooltip._lines or {}) do tip[#tip + 1] = tostring(l.text) end
        ok(has(table.concat(tip), "進行中的委託不會動"), "the tooltip says what it deletes")
        local O = ns.Orders
        local id = O.place({ recipe = 2152, item = 2318, skill = 165, qty = 1 })
        if id then
            O.customer(id, "cancel")
            wow.click(ns.Diag.clearButton)
            local p = wow.popup()
            ok(p and has(p.text, "已經結束的委託") and has(p.text, "進行中的委託不會動"), p and p.text)
            wow.cancelPopup()
        end
    end)
end
