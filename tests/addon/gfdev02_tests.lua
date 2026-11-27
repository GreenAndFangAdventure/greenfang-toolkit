-- GF-DEV-02: /gftkdev preview (GreenFangToolkit_Dev/Preview.lua), made-up
-- rows on the toolkit's windows for the owner to look at: every notice kind,
-- the notice switches, every confirm box, the lists (委託 / 冒險單 / 調貨所 /
-- 名冊). The made-up data never reaches GreenFangToolkitDB, the outbox, the
-- guild channel or a whisper; preview off (and /reload) shows the real data.
-- Made-up names only (測試甲...). Run alone: run_lupa.py --only gfdev02

return function(T)
    local test, eq, ok, wow, ADDON_DIR, deepEq = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR, T.deepEq
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
    local function deepCopy(v)
        if type(v) ~= "table" then return v end
        local o = {}
        for k, x in pairs(v) do o[deepCopy(k)] = deepCopy(x) end
        return o
    end
    local function has(s, sub) return tostring(s):find(sub, 1, true) ~= nil end
    -- Every string anywhere in t (keys too).
    local function strings(t, acc, seen)
        acc, seen = acc or {}, seen or {}
        if type(t) ~= "table" or seen[t] then return acc end
        seen[t] = true
        for k, v in pairs(t) do
            if type(k) == "string" then acc[#acc + 1] = k end
            if type(v) == "string" then acc[#acc + 1] = v elseif type(v) == "table" then strings(v, acc, seen) end
        end
        return acc
    end
    -- (the mock roster itself uses 測試甲...: the made-up rows are told apart by these)
    local FAKE = { "預覽伺服器", "pv-", "PV-", "預覽", "preview:", "名字特別長" }
    local function clean(t, what)
        for _, s in ipairs(strings(t)) do
            for _, f in ipairs(FAKE) do ok(not has(s, f), (what or "data") .. " has made-up data: " .. s) end
        end
    end

    -- The toolkit, every list page opened once (as a player would), then the dev AddOn.
    local function start(opts)
        opts = opts or {}
        wow.reset()
        local ns = wow.login(ADDON_DIR)
        for _, id in ipairs({ "orders", "adventure", "supply", "roster", "bank" }) do pcall(ns.Framework.open, id) end
        ns.NotifyUI.open(); ns.NotifyUI.list():Hide()
        wow.advance(3)
        if not opts.noDev then C_AddOns.IsAddOnLoaded = function(name) return name == "GreenFangToolkit_Dev" end end
        local D = {}
        for _, file in ipairs(tocFiles()) do assert(loadfile(DEV_DIR .. "/" .. file))("GreenFangToolkit_Dev", D) end
        wow.fire("ADDON_LOADED", "GreenFangToolkit_Dev")
        return ns, D, D.Preview
    end
    local function slash(msg) SlashCmdList.GFTKDEV(msg) end
    local function said() return table.concat(wow.printed(), "\n") end
    local function done(fn)
        return function()
            local okRun, err = pcall(fn)
            GreenFangToolkitDevDB = nil
            if C_AddOns then C_AddOns.IsAddOnLoaded = nil end
            if not okRun then error(err, 0) end
        end
    end
    local function sentCount() return #wow.state.sent end
    local function click(b) local fn = b:GetScript("OnClick"); return fn and fn(b, "LeftButton") end
    local function frameCount() return #wow.state.frames end

    test("GF-DEV-02 preview: /gftkdev preview lists the items; the toolkit answers only with the dev AddOn loaded", done(function()
        local ns, _, P = start({ noDev = true })
        eq(GreenFangToolkit_DevAccess(), nil, "no dev AddOn: nothing")
        wow.clearPrinted()
        slash("preview notify")
        ok(has(said(), "找不到綠皮冒險工具箱"), "says the toolkit is not reachable")
        eq(P.isActive(), false, "nothing started")
        C_AddOns.IsAddOnLoaded = function(name) return name == "GreenFangToolkit_Dev" end
        eq(GreenFangToolkit_DevAccess(), ns, "dev AddOn loaded: the toolkit")
        wow.clearPrinted()
        slash("preview")
        for _, w in ipairs({ "preview notify", "preview settings", "preview confirm", "preview lists", "preview off" }) do
            ok(has(said(), "/gftkdev " .. w), "help names " .. w)
        end
        wow.clearPrinted()
        slash("")
        ok(has(said(), "/gftkdev preview"), "the /gftkdev usage line names preview")
    end))

    test("GF-DEV-02 preview notify: one made-up notice of every kind, 另有 N 則, buttons; clicks run nothing; real ones kept", done(function()
        local ns, _, P = start()
        local N = ns.Notify
        N.push({ module = "supply", key = "real:1", text = "真的通知" })
        local before = deepCopy(GreenFangToolkitDB)
        local sent = sentCount()
        local ended = 0
        local realEnd = ns.RecipeLink.endListing
        ns.RecipeLink.endListing = function() ended = ended + 1 end
        slash("preview notify")
        local list = N.list()
        local kinds = {}
        for _, e in ipairs(list) do ok(e.gfPreview, "only made-up notices shown"); kinds[e.module] = true end
        for _, m in ipairs(N.MODULES) do ok(kinds[m.key], "a notice of " .. m.key) end
        ok(#N.MODULES >= 14, "every switch: " .. #N.MODULES)
        local more, buttons, three
        for _, e in ipairs(list) do
            if e.key == N.MORE_KEY then more = e end
            if e.actions and #e.actions > 0 then buttons = true end
            if e.actions and #e.actions == 3 then three = true end
        end
        ok(more and has(more.text, "另有 12 則"), "the merged 另有 N 則 notice")
        ok(buttons and three, "notices with buttons (three on one)")
        local f = ns.NotifyUI.list()
        ok(f:IsShown(), "the notice list is open")
        ok(has(P.bannerText() or "", "預覽中"), "says it is a preview")
        ok(has(said(), "假通知"), "chat says so")
        -- Buttons and clicks: nothing runs, no page opens.
        for _, e in ipairs(N.list()) do
            for _, a in ipairs(e.actions or {}) do
                if a.key ~= "ignore" then eq(N.action(e, a.key), "preview", "button " .. a.key .. " does nothing") end
            end
        end
        eq(ended, 0, "結束徵求 not run")
        local opened = ns.Framework.current()
        eq(N.open(N.list()[1]), "preview", "a click opens nothing")
        eq(ns.Framework.current(), opened, "no page opened")
        local n = #N.list()
        local ign
        for _, e in ipairs(N.list()) do if e.actions and e.actions[2] and e.actions[2].key == "ignore" then ign = e end end
        ok(ign, "a made-up notice with 忽略")
        eq(N.action(ign, "ignore"), "preview", "忽略 on a made-up notice")
        eq(#N.list(), n - 1, "忽略 drops only the made-up notice")
        N.markAllRead()
        eq(N.unread(), 0, "全部已讀 on the made-up ones")
        eq(sentCount(), sent, "nothing sent")
        ok(deepEq(GreenFangToolkitDB, before), "GreenFangToolkitDB unchanged")
        slash("preview off")
        local after = N.list()
        eq(#after, 1, "the real notice is back")
        eq(after[1].text, "真的通知", "and it is the real one")
        ok(after[1].unread, "still unread (全部已讀 touched only the made-up ones)")
        eq(P.swapCount(), 0, "every function put back")
        ok(not P.bannerText(), "banner gone")
        ns.RecipeLink.endListing = realEnd
    end))

    test("GF-DEV-02 preview settings: the switch list (19 rows, two columns); clicks are not saved", done(function()
        local ns, _, P = start()
        local N = ns.Notify
        local before = deepCopy(GreenFangToolkitDB)
        slash("preview settings")
        local f = ns.NotifyUI.list()
        ok(f:IsShown() and f.settings:IsShown(), "the switches are shown")
        local boxes = f.settings.boxes
        eq(#boxes, 19, "19 rows")
        local cols = {}
        for _, c in ipairs(boxes) do cols[c.col] = true end
        ok(cols[0] and cols[1], "two columns")
        ok(has(wow.printed()[#wow.printed()], "兩欄"), "chat says two columns")
        local was = {}
        for i, c in ipairs(boxes) do was[i] = c:GetChecked() and true or false end
        for _, c in ipairs(boxes) do
            c:SetChecked(not c:GetChecked())
            click(c)
        end
        for i, c in ipairs(boxes) do eq(c:GetChecked() and true or false, was[i], "box " .. i .. " back as it was") end
        ok(N.enabled("supply") and not N.enabled("order_guild") and N.chatOn(), "switches unchanged")
        ok(deepEq(GreenFangToolkitDB, before), "GreenFangToolkitDB unchanged")
        slash("preview off")
        -- After off the switches save again.
        local sup
        for _, c in ipairs(boxes) do if c.key == "supply" then sup = c end end
        ns.NotifyUI.open(); click(f.setup)
        sup:SetChecked(false); click(sup)
        eq(N.enabled("supply"), false, "after off a click saves again")
    end))

    test("GF-DEV-02 preview confirm: every confirm box, one at a time; no button runs anything", done(function()
        local ns, _, P = start()
        local before = deepCopy(GreenFangToolkitDB)
        local runs = 0
        local G = ns.GuildAdmin
        for _, k in ipairs({ "GuildDemote", "GuildUninvite", "GuildInvite", "GuildRosterSetPublicNote", "GuildRosterSetOfficerNote", "GuildSetMOTD", "SetGuildInfoText" }) do
            _G[k] = function() runs = runs + 1 end
        end
        local cleared, ended, closed = 0, 0, 0
        local oc, re, sc = ns.Orders.clearClosed, ns.RecipeLink.endListing, ns.SupplyUI.closeForm
        ns.Orders.clearClosed = function() cleared = cleared + 1 end
        ns.RecipeLink.endListing = function() ended = ended + 1 end
        ns.SupplyUI.closeForm = function() closed = closed + 1 end
        local list = P.confirmList(ns)
        ok(#list >= 12, "the toolkit's boxes: " .. #list)
        local names = {}
        for _, it in ipairs(list) do names[#names + 1] = it.name end
        local all = table.concat(names, "\n")
        for _, w in ipairs({ "學會圖紙", "放棄編輯", "結束刊登", "刪除冒險單", "降一階", "踢出公會", "公會註記", "今日訊息", "清除已結案" }) do
            ok(has(all, w), "box listed: " .. w)
        end
        slash("preview confirm")
        local seen = 0
        for i = 1, #list do
            local it = P.chain.current
            ok(it, "box " .. i .. " is up")
            seen = seen + 1
            if it.widget then
                local f = ns.Widgets.confirmFrame()
                ok(f:IsShown(), "the toolkit's box shown: " .. it.name)
                eq(f.text:GetText(), it.text, "its text")
                click(f.yes) -- 確定: nothing to run; the next one comes after it closed
            else
                local pop = wow.popup()
                ok(pop and (pop.which == P.POPUP or pop.which == P.POPUP_EDIT), "a look-alike box: " .. it.name)
                ok(pop.which ~= it.popup, "never the toolkit's own box")
                if it.edit then ok(pop.editBox, "with its edit box") end
                wow.acceptPopup("改過的字")
                StaticPopupDialogs[pop.which].OnHide(pop)
            end
            wow.advance(0.1)
        end
        eq(seen, #list, "every box came")
        eq(P.chain.current, nil, "chain over")
        ok(has(said(), "確認視窗都看完了"), "says it is over")
        eq(runs, 0, "no guild change")
        eq(cleared + ended + closed, 0, "nothing cleared, ended or closed")
        ok(deepEq(GreenFangToolkitDB, before), "GreenFangToolkitDB unchanged")
        ns.Orders.clearClosed, ns.RecipeLink.endListing, ns.SupplyUI.closeForm = oc, re, sc
        -- off in the middle closes the open box
        slash("preview confirm")
        ok(P.chain.current, "first box up")
        slash("preview off")
        eq(P.chain.current, nil, "off stops the boxes")
    end))

    local function realRows(ns)
        return {
            orders = ns.OrdersUI.pageRows(), adventure = ns.AdventureUI.pageRows(),
            supply = ns.SupplyUI.listFor("mine"),
            roster = ns.UI.filterMembers(ns.Roster.current() and ns.Roster.current().members or {}, "", {}),
        }
    end
    local function anyPreview(list)
        for _, r in ipairs(list) do
            if r.gfPreview or (r.view and r.view.gfPreview) or r.myWorker and r.myWorker.gfPreview then return true end
        end
        return false
    end

    test("GF-DEV-02 preview lists 少: made-up rows on 委託 / 冒險單 / 調貨所 / 名冊, every state; covers; off brings the real rows", done(function()
        local ns, _, P = start()
        local real = realRows(ns)
        slash("preview lists 少")
        local O, A = ns.OrdersUI.pageRows(), ns.AdventureUI.pageRows()
        ok(anyPreview(O) and #O >= 5, "委託 rows: " .. #O)
        ok(anyPreview(A), "冒險單 rows: " .. #A)
        local S = ns.SupplyUI.listFor("mine")
        eq(#S, 5, "調貨所 5 rows")
        local R = ns.UI.filterMembers({}, "", {})
        eq(#R, 5, "名冊 5 rows")
        for _, id in ipairs({ "orders", "adventure", "supply", "roster" }) do
            ok(P.covers[id] and P.covers[id]:IsShown(), "cover on " .. id)
        end
        ok(not P.covers.bank, "臨時黑箱 not previewed")
        ok(has(said(), "臨時黑箱"), "says why 臨時黑箱 is not")
        ok(has(P.bannerText() or "", "預覽中"), "banner")
        slash("preview off")
        for k, list in pairs(realRows(ns)) do
            ok(not anyPreview(list), k .. ": no made-up rows after off")
            eq(#list, #real[k], k .. ": the real rows again")
        end
        for _, c in pairs(P.covers) do ok(not c:IsShown(), "covers hidden") end
        eq(P.swapCount(), 0, "every function put back")
        eq(ns.Share.memberFor(P.author(1)), nil, "made-up people gone")
    end))

    test("GF-DEV-02 preview lists 多: ~100 rows a page, every state and icon; the pages reuse their row frames", done(function()
        local ns, _, P = start()
        slash("preview lists 少")
        local few = frameCount()
        slash("preview lists 多")
        local many = frameCount()
        local O = ns.OrdersUI.pageRows()
        ok(#O >= 100, "委託 100 rows (+ headers): " .. #O)
        local states, att, buttons = {}, false, false
        for _, r in ipairs(O) do
            if r.view then states[r.view.state] = true; if r.attention then att = true end end
        end
        for _, s in ipairs({ "waiting", "making", "checking", "deal", "cancel" }) do ok(states[s], "委託 state " .. s) end
        ok(att, "委託 attention icons")
        local A = ns.AdventureUI.pageRows()
        local open, closed, worker, mine = false, false, false, false
        for _, r in ipairs(A) do
            if r.view then if r.view.closed then closed = true else open = true end end
            if r.isWorker or r.otherWorker then worker = true end
            if r.myWorker then mine = true end
        end
        ok(open and closed and worker and mine, "冒險單: open, ended, 職工單, my own")
        local S = ns.SupplyUI.listFor("mine")
        eq(#S, 100, "調貨所 100 rows")
        local st = {}
        for _, d in ipairs(S) do st[d.listing.status] = true end
        for _, s in ipairs({ "active", "closed", "cancelled", "expired" }) do ok(st[s], "刊登 " .. s) end
        eq(#ns.UI.filterMembers({}, "", {}), 100, "名冊 100 rows")
        -- 100 rows: only the rows in view are frames (a few more than with 5 at most).
        ok(many - few < 40, "row frames reused: " .. (many - few) .. " more frames for 100 rows on 4 pages")
        for _ = 1, 60 do
            for _, id in ipairs({ "orders", "adventure", "supply", "roster" }) do
                local c = P.covers[id]
                c:GetScript("OnMouseWheel")(c, -1)
            end
        end
        eq(frameCount(), many, "scrolling to the end makes no frame")
        ok(ns.OrdersUI.scrollFrame():GetVerticalScroll() > 0, "the wheel scrolls 委託")
        -- The page's buttons sit under the cover; a click on it runs nothing.
        local sent = sentCount()
        local c = P.covers.orders
        c:GetScript("OnMouseDown")(c)
        ok(has(said(), "按鈕暫停"), "cover says the buttons are paused")
        eq(sentCount(), sent, "nothing sent")
        slash("preview off")
    end))

    test("GF-DEV-02 preview lists: every page draws the made-up rows (no error), 調貨所 detail, long text, top to bottom", done(function()
        local ns, _, P = start()
        for _, size in ipairs({ "少", "多" }) do
            slash("preview lists " .. size)
            for _, UI in ipairs({ ns.OrdersUI, ns.AdventureUI, ns.SupplyUI, ns.UI }) do UI.refresh() end
            for i = 1, #ns.SupplyUI.listFor("mine") do ns.SupplyUI.select(i) end
            for _, sf in ipairs({ ns.OrdersUI.scrollFrame(), ns.AdventureUI.scrollFrame(), ns.UI.scrollFrame() }) do
                for y = 0, 6000, 200 do sf:SetVerticalScroll(y) end
                sf:SetVerticalScroll(0)
            end
            for _ = 1, 100 do ns.SupplyUI.scroll(-1) end
        end
        local texts = table.concat(wow.allTexts(), "\n")
        ok(has(texts, "收到的（預覽）") and has(texts, "我下的（預覽）"), "委託 headers say 預覽")
        ok(has(texts, "冒險單（預覽）") and has(texts, "我的職工單（預覽）"), "冒險單 headers say 預覽")
        ok(has(texts, "名字特別長"), "a long name is drawn")
        ok(has(texts, "特別長的備註"), "a long note is drawn")
        ok(has(texts, "預覽中"), "the cover line")
        slash("preview off")
        for _, UI in ipairs({ ns.OrdersUI, ns.AdventureUI, ns.SupplyUI, ns.UI }) do UI.refresh() end
    end))

    test("GF-DEV-02 preview: GreenFangToolkitDB the same, nothing sent, the outbox / export / logout save without made-up data", done(function()
        local ns, _, P = start()
        local before = deepCopy(GreenFangToolkitDB)
        local sent = sentCount()
        slash("preview notify")
        slash("preview settings")
        slash("preview lists 多")
        slash("preview confirm")
        -- the page work a player could cause meanwhile
        for _, id in ipairs({ "orders", "adventure", "supply", "roster" }) do ns.Framework.open(id) end
        ns.Orders.maintain(); ns.Adventure.maintain()
        eq(sentCount(), sent, "the preview sends no addon message, guild line or whisper")
        -- The toolkit's own timed sends go on meanwhile: none carries made-up data.
        wow.advance(120)
        local out = {}
        for i = sent + 1, sentCount() do out[#out + 1] = wow.state.sent[i] end
        clean(out, "what the toolkit sent meanwhile")
        if ns.Roster.current() then
            clean({ ns.Export.jsonParts(ns.Roster.current()), ns.Export.tsvParts(ns.Roster.current()) }, "export")
        end
        clean(ns.Orders.all(), "Orders.all")
        clean(ns.Adventure.all(), "Adventure.all")
        clean(ns.SupplyListings.own(), "my listings")
        -- What /reload would write while the preview is on: nothing made up.
        local saved = wow.logout()
        clean(saved, "the saved variables")
        clean(GreenFangToolkitDB.sync and GreenFangToolkitDB.sync.outbox or {}, "the GF Sync outbox")
        -- And after /reload the preview is gone (nothing of it is saved).
        local ns2 = wow.loadAddon(ADDON_DIR, saved)
        wow.fire("PLAYER_LOGIN"); wow.advance(10)
        clean(ns2.Notify.list(), "notices after reload")
        clean(ns2.OrdersUI.pageRows(), "委託 after reload")
        P.off(true)
    end))

    test("GF-DEV-02 preview: GreenFangToolkitDB deep-equal before and after a whole preview", done(function()
        local ns, _, P = start()
        local before = deepCopy(GreenFangToolkitDB)
        slash("preview notify"); slash("preview settings"); slash("preview lists 多"); slash("preview confirm")
        slash("preview off")
        ok(deepEq(GreenFangToolkitDB, before), "GreenFangToolkitDB unchanged")
        eq(GreenFangToolkitDevDB and GreenFangToolkitDevDB.preview, nil, "nothing in the dev AddOn's save either")
    end))

    test("GF-DEV-02 preview: refused in combat; no events, no OnUpdate, no repeating timer", done(function()
        local ns, D, P = start()
        local frames = frameCount()
        wow.setCombat(true)
        wow.clearPrinted()
        slash("preview lists 多")
        ok(has(said(), "戰鬥中不做預覽"), "says why")
        eq(P.isActive(), false, "nothing started in combat")
        eq(frameCount(), frames, "no frame in combat")
        wow.setCombat(false)
        slash("preview notify"); slash("preview lists 多"); slash("preview confirm")
        -- in combat the confirm boxes stop
        wow.setCombat(true)
        P.confirmNext()
        eq(P.chain.current, nil, "confirm boxes stop in combat")
        wow.setCombat(false)
        for _, f in ipairs(wow.state.frames) do
            ok(f:GetScript("OnUpdate") == nil, "no OnUpdate")
        end
        local src = readAll(DEV_DIR .. "/Preview.lua")
        ok(not has(src, "RegisterEvent"), "Preview.lua registers no event")
        ok(not has(src, "NewTicker") and not has(src, "OnUpdate\""), "no ticker / OnUpdate")
        local code = src:gsub("%-%-[^\n]*", "")
        ok(not has(code, "GreenFangToolkitDB"), "the code never touches the saved variables")
        slash("preview off")
    end))
end
