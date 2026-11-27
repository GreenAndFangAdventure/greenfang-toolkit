-- GF-002-D (0.12.2): every clickable icon has a short name next to it,
-- every window row has a field name, one popup at a time, empty pages say
-- so, and no name is cut to "…". Owner's report after 0.12.1: "只有圖片是無法
-- 使用，不知道功能". Made-up data only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local B = "0000-0000000B"

    local function login(opts)
        wow.reset(opts)
        local ns = wow.login(ADDON_DIR)
        ns.Orders.resetSession(); ns.Adventure.resetSession()
        return ns
    end

    local function visible(o)
        local f = o
        while f do
            if f._shown == false then return false end
            f = f._parent
        end
        return true
    end
    local function under(o, root)
        local f = o
        while f do
            if f == root then return true end
            f = f._parent
        end
        return false
    end
    local function plain(t) return (tostring(t or ""):gsub("|T.-|t", ""):gsub("%s", "")) end

    -- Buttons under root that are shown but have no name.
    local function unnamed(root)
        local out = {}
        for _, o in ipairs(wow.allObjects()) do
            if o._kind == "Button" and under(o, root) and visible(o) then
                -- infoOnly: an icon that only shows a tooltip (nothing happens on click).
                local named = plain(o._text) ~= "" or (o.label and plain(o.label._text) ~= "") or o.fieldNamed
                    or (o.infoOnly and not o._scripts.OnClick)
                if not named then out[#out + 1] = tostring(o.tip or o.action or "?") end
            end
        end
        return out
    end
    -- FontStrings under root whose text does not fit their width.
    local function truncated(root)
        local out = {}
        for _, o in ipairs(wow.allObjects()) do
            if o._kind == "FontString" and visible(o) and (under(o, root) or (o._parent and under(o._parent, root)))
                and o.IsTruncated and o:IsTruncated() then
                out[#out + 1] = plain(o._text)
            end
        end
        return out
    end

    local function withOrderAndTicket(ns)
        local t = ns.Share.serverNow()
        local w = "id=gbbb.1,cf=" .. "0000-0000000A" .. ",cr=" .. ns.Share.b36(t) .. ",rc=21w,it=27i,sk=4k,q=1,fe=0,st=o,sa=" .. ns.Share.b36(t)
        ns.Orders.ledger:offer(B, "W", t, ns.Share.hash(w), w)
        ns.Orders.place({ recipe = 2660, item = 2862, skill = 164, qty = 1 })
        local v = ns.Adventure.encodeList({ { id = "abbb.1", src = "g", ver = 1, cr = t, ds = "smg", qs = "", tm = "n",
            rt = 1, rh = 1, rd = 3, lr = "d", tg = 3, md = "a", st = "o", sa = t } })
        ns.Adventure.ledger:offer(B, "T", t, ns.Share.hash(v), v)
        ns.Adventure.open({ dungeon = "sfk", leaderRole = "h" })
    end

    test("GF-002-D every button on the two pages and in every window has a name", function()
        local ns = login()
        withOrderAndTicket(ns)
        ns.Framework.open("orders")
        local p = ns.Framework.panel("orders")
        eq(table.concat(unnamed(p), ","), "", "orders page")
        ns.Framework.open("adventure")
        p = ns.Framework.panel("adventure")
        eq(table.concat(unnamed(p), ","), "", "adventure page")
        local windows = {
            { function() ns.AdventureUI.openTicket() end, ns.AdventureUI.TICKET_NAME },
            { function() ns.AdventureUI.openWorker() end, ns.AdventureUI.WORKER_NAME },
            { function() ns.OrdersUI.openOrder({ recipe = 2660, skill = 164, crafters = {} }) end, ns.OrdersUI.POPUP_NAME },
            { function() ns.OrdersUI.editFee({ skill = 165 }) end, ns.OrdersUI.FEE_NAME },
            { function() ns.OrdersUI.openPaste() end, ns.OrdersUI.PASTE_NAME },
        }
        for _, w in ipairs(windows) do
            w[1]()
            local f = _G[w[2]]
            eq(table.concat(unnamed(f), ","), "", w[2])
        end
        ns.AdventureUI.dungeonGrid(UIParent, function() end)
        local grid = ns.AdventureUI.grid()
        for _, b in ipairs(grid.buttons) do ok(b.label and plain(b.label._text) ~= "", "dungeon name under " .. b.dungeon) end
    end)

    test("GF-002-D the owner's screens: names on the top buttons, fields, choices, empty values", function()
        local ns = login()
        wow.advance(30) -- own professions are known once sharing has started
        ns.Framework.open("adventure")
        ok(plain(ns.AdventureUI.newButton:GetText()):find("冒險單", 1, true), "＋冒險單")
        ok(plain(ns.AdventureUI.workerButton:GetText()):find("職工單", 1, true), "＋職工單")
        ns.AdventureUI.openTicket()
        local f = _G[ns.AdventureUI.TICKET_NAME]
        eq(table.concat(f.fields, ","), "目的地,時段,人數,錄取,標籤,備註", "field names (GF-002-H: 時段 chips, each with 開始 and 長度)")
        ok(f.startButton:GetText():find("現在", 1, true), "the first slot says 現在")
        ok(f.pickDungeon:IsShown() and f.pickQuest:IsShown() and not f.dest:IsShown(), "GF-002-H R-16.26: step one is 地城 / 任務")
        eq(f.pickDungeon.label._text .. "," .. f.pickQuest.label._text, "地城,任務", "their names")
        eq(f.addSlot:GetText(), "＋時段", "＋時段 (GF-002-H: up to 5 slots)")
        eq(f.direct.label._text .. "," .. f.consent.label._text, "直接錄取,團長同意", "admission names")
        eq(f.tagButtons.quest.label._text, "解任務", "tag names")
        ns.AdventureUI.openWorker()
        local w = _G[ns.AdventureUI.WORKER_NAME]
        eq(table.concat(w.fields, ","), "地城,任務,職責,副職責,時段", "worker field names (GF-002-H: 長度 is in each slot's picker)")
        eq(w.addDungeon:GetText(), "＋地城", "no dungeon yet: only 「＋地城」 (GF-002-F)"); eq(w.quests:GetText(), "選擇任務", "no quest yet (not x0)")
        -- GF-002-J (owner): role icons without names (the one exception); the name is the tooltip.
        ok(not (w.mainRoles.d.label and w.mainRoles.d.label:IsShown()), "no role names"); eq(w.mainRoles.d.tip, "輸出", "the tooltip")
        ok(w.remove.label._text:find("移除", 1, true), "remove named")
        ns.Framework.open("orders")
        local pb = ns.OrdersUI.profButtons()[1]
        ok(pb and (pb.label._text == "接單" or pb.label._text == "不接"), "接單 switch named")
        eq(pb.feeButton:GetText(), "工錢", "工錢 named")
        eq(ns.OrdersUI.historyButton.label._text, "歷史", "history"); eq(ns.OrdersUI.pasteButton.label._text, "匯入", "paste")
        eq(ns.AdventureUI.nextInvite._shown, false, "the invite-next icon only when needed")
    end)

    test("GF-002-D only one window at a time; opening one closes the others and the dungeon grid", function()
        local ns = login()
        local A, O = ns.AdventureUI, ns.OrdersUI
        local function shown(name) local f = _G[name]; return f ~= nil and f:IsShown() end
        A.openTicket()
        A.pickDestination(UIParent)
        ok(A.grid():IsShown(), "grid open")
        A.openWorker()
        ok(shown(A.WORKER_NAME) and not shown(A.TICKET_NAME), "worker replaces ticket")
        ok(not A.grid():IsShown(), "grid closed")
        O.openOrder({ recipe = 2660, skill = 164, crafters = {} })
        ok(shown(O.POPUP_NAME) and not shown(A.WORKER_NAME), "order replaces worker")
        O.editFee({ skill = 165 })
        ok(shown(O.FEE_NAME) and not shown(O.POPUP_NAME), "fee replaces order")
        O.openPaste()
        ok(shown(O.PASTE_NAME) and not shown(O.FEE_NAME), "paste replaces fee")
        A.openTicket()
        ok(shown(A.TICKET_NAME) and not shown(O.PASTE_NAME), "ticket replaces paste")
        local count = 0
        for _, f in ipairs(ns.exclusivePopups()) do if f:IsShown() then count = count + 1 end end
        eq(count, 1, "exactly one open")
    end)

    test("GF-002-D time: :00/:15/:30/:45 on the player's clock; start and length chosen apart; menus on top", function()
        local ns = login()
        local U = ns.AdventureUI
        wow.state.serverSkew = 61 -- the player's clock is a minute off the server (0.12.1 showed 01:14)
        local d = U.openTicket()
        d.dungeon = "smg"
        U.pickTime(UIParent, "t")
        local f = _G[U.TICKET_NAME]
        local sl = d.slots[1]
        ok(f.startButton._shown and f.addSlot._shown, "a slot chip and ＋時段")
        for _, t in ipairs(U.quarterTimes(ns.Share.serverNow(), 8)) do
            local mm = tonumber(U.clock(t):match(":(%d%d)$"))
            ok(mm % 15 == 0, "quarter on the player's clock: " .. U.clock(t))
        end
        ok(U.clock(sl.start):match(":(%d%d)$") and tonumber(U.clock(sl.start):match(":(%d%d)$")) % 15 == 0, "default start on a quarter")
        eq(sl.dur, nil, "GF-002-H R-16.2: no length unless chosen")
        local pk = U.pickStart(UIParent)
        eq(pk.title:GetText(), "時段 1", "the picker is named after the slot")
        eq(pk._strata, "TOOLTIP", "above the windows")
        ok(pk.lenLabel:IsShown() and #pk.lens == 6, "長度: 不填 and 1-5 hours")
        eq(pk.lens[1]:GetText(), "不填", "不填 first")
        wow.click(pk.lens[4]) -- 3 小時
        eq(sl.dur, 3, "length 3 hours")
        local tomorrow8 = pk.hours[2][8]
        wow.click(tomorrow8)
        eq(U.clock(sl.start), "08:00", "明天 08 → 08:00")
        wow.click(pk.minutes[3])
        eq(U.clock(sl.start), "08:30", ":30")
        eq(sl.dur, 3, "length kept when the start changes")
        pk:Hide()
        U.pickTime(UIParent, "f")
        ok(plain(f.startButton:GetText()):match("%d%d%d%d/%d%d/%d%d"), "其他日期: the date on the chip")
        eq(U.clock(sl.start), "20:00", "evening by default")
        local menu = U.pickDay(UIParent)
        eq(menu.items[1]:GetText(), "|cffffd100日期|r", "the menu starts with its name")
        eq(menu._strata, "TOOLTIP", "the menu is above the windows")
        wow.click(menu.items[3]) -- two days ahead
        eq(U.clock(sl.start), "20:00", "same hour on the new day")
        local id = U.submitTicket()
        ok(id and ns.Adventure.get(id).timeMode == "f", "opened")
        wow.state.serverSkew = nil
    end)

    test("GF-002-D 16001 quest log: header rows (questID 0) are skipped; difficultyLevel is the level", function()
        local ns = login()
        local rows = {
            { questID = 0, title = "剃刀沼澤", difficultyLevel = 0 },
            { questID = 1101, title = "測試任務甲", difficultyLevel = 33 },
            { questID = 1102, title = "測試任務乙", difficultyLevel = 35, isHeader = false },
        }
        C_QuestLog = { GetNumQuestLogEntries = function() return #rows, 2 end, GetInfo = function(i) return rows[i] end }
        local log = ns.Adventure.questLog()
        eq(log[0], nil, "no header")
        eq(log[1101].title, "測試任務甲", "quest"); eq(log[1101].level, 33, "difficultyLevel")
        local n = 0
        for _ in pairs(log) do n = n + 1 end
        eq(n, 2, "two quests")
        C_QuestLog = nil
    end)

    test("GF-002-D 16001 quest rows: isHeader skips titles (questID 0 the fallback); level, then difficultyLevel", function()
        local ns = login()
        local rows = {
            { isHeader = true, questID = 0, title = "剃刀沼澤", level = 0 },
            { isHeader = true, questID = 999, title = "某個區域" },          -- isHeader wins even with an id
            { questID = 0, title = "沒有 isHeader 的標題列" },               -- the fallback
            { isHeader = false, questID = 216, title = "測試任務甲", level = 24, difficultyLevel = 24, isScaling = true },
            { isHeader = false, questID = 217, title = "測試任務乙", difficultyLevel = 30 },
        }
        C_QuestLog = { GetNumQuestLogEntries = function() return #rows, 2 end, GetInfo = function(i) return rows[i] end }
        local log = ns.Adventure.questLog()
        eq(log[999], nil, "isHeader row skipped"); eq(log[0], nil, "questID 0 skipped")
        eq(log[216].level, 24, "level"); ok(log[216].scaling, "scaling flag")
        eq(log[217].level, 30, "difficultyLevel when level is missing")
        C_QuestLog = nil
    end)

    test("GF-002-D R-6.1 point 3: quest tickets check the level; scaling quests never exclude", function()
        local ns = login()
        local Adv = ns.Adventure
        local rows = {
            { isHeader = false, questID = 216, title = "測試任務甲", level = 24, isScaling = true },
            { isHeader = false, questID = 217, title = "測試任務乙", level = 30 },
        }
        C_QuestLog = { GetNumQuestLogEntries = function() return #rows, 2 end, GetInfo = function(i) return rows[i] end }
        local fixed = Adv.open({ quests = { 217 }, size = 4, leaderRole = "d" })
        local scaling = Adv.open({ quests = { 216 }, size = 4, leaderRole = "d" })
        C_QuestLog = nil
        local w = { dungeons = {}, quests = { [216] = true, [217] = true }, main = "d", slots = { { now = true } } }
        local okFixed, why = Adv.matches(Adv.get(fixed), w, 20)
        eq(okFixed and "ok" or why, "level", "level 20 vs a level 30 quest: excluded")
        ok(Adv.matches(Adv.get(fixed), w, 28), "level 28 vs 30: within 3")
        ok(Adv.matches(Adv.get(scaling), w, 10), "scaling quest: any level")
    end)

    test("GF-002-D empty pages show a short line", function()
        local ns = login()
        ns.Framework.open("orders")
        eq(ns.OrdersUI.emptyLine._text, "沒有委託", "orders (GF-UI-K)")
        ns.Framework.open("adventure")
        eq(ns.AdventureUI.emptyLine._text, "沒有冒險單", "adventure")
        ns.Adventure.open({ dungeon = "smg", leaderRole = "d" })
        ns.AdventureUI.refresh()
        eq(ns.AdventureUI.emptyLine._text, "", "gone once there is one")
        ns.Orders.place({ recipe = 2660, item = 2862, skill = 164, qty = 1 })
        ns.Framework.open("orders")
        eq(ns.OrdersUI.emptyLine._text, "", "orders too")
    end)

    test("GF-002-D no name is cut short", function()
        local ns = login()
        withOrderAndTicket(ns)
        ns.Framework.open("orders")
        eq(table.concat(truncated(ns.Framework.panel("orders")), ","), "", "orders page")
        ns.Framework.open("adventure")
        eq(table.concat(truncated(ns.Framework.panel("adventure")), ","), "", "adventure page")
        for _, open in ipairs({ ns.AdventureUI.openTicket, ns.AdventureUI.openWorker }) do open() end
        eq(table.concat(truncated(_G[ns.AdventureUI.WORKER_NAME]), ","), "", "worker window")
        ns.AdventureUI.openTicket()
        eq(table.concat(truncated(_G[ns.AdventureUI.TICKET_NAME]), ","), "", "ticket window")
        ns.OrdersUI.openOrder({ recipe = 2660, skill = 164, crafters = {} })
        eq(table.concat(truncated(_G[ns.OrdersUI.POPUP_NAME]), ","), "", "order window")
        -- The longest names used on buttons fit their label width.
        for _, name in ipairs({ "工匠結案", "指定工匠", "直接錄取", "團長同意", "移除職工單", "邀請下一位", "選擇目的地" }) do
            ok(ns.labelWidth(name) >= #name / 3 * 11, "width for " .. name)
        end
    end)
end
