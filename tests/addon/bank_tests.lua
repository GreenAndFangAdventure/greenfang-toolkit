-- GF-012 phase 1 (spec v2.0 §8, design GF-012-A): who is guild master, the
-- custodian list (group K), its checks (author = current guild master, epoch
-- never goes back), revocation, a custodian's own scope, the page.
-- Offline only: IsGuildLeader and the roster are the fake game below / mock.lua;
-- nothing here was checked in the Forever client. Made-up names only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR

    local A, B, C, D = "0000-0000000A", "0000-0000000B", "0000-0000000C", "0000-0000000D"
    local PEER_B, PEER_C = "測試乙-測試伺服器", "測試丙-測試伺服器"

    -- The default roster with other ranks: ranks = { A = "會長", B = "會員", ... }.
    local function roster(ranks)
        local r = wow.defaultRoster()
        local key = { A = 1, B = 2, C = 3, D = 4 }
        for who, rank in pairs(ranks or {}) do r[key[who]].rank = rank end
        return r
    end
    local function setRanks(ranks, ns)
        wow.state.roster = roster(ranks)
        ns.Bank.invalidate()
    end

    local calls -- bag / bank / item function calls made from Bank.lua or BankUI.lua
    local function installBags()
        calls = 0
        local function counted(ret)
            return function()
                local tb = debug and debug.traceback and debug.traceback() or ""
                if tb:find("Bank", 1, true) then calls = calls + 1 end
                return ret
            end
        end
        C_Container = { GetContainerNumSlots = counted(20), GetContainerItemInfo = counted(nil),
            GetContainerItemID = counted(nil) }
        C_Bank = { CanViewBank = counted(true), FetchPurchasedBankTabData = counted({}) }
        GetItemCount = counted(0)
    end
    local function removeGame() C_Container, C_Bank, GetItemCount, IsGuildLeader = nil, nil, nil, nil end

    -- opts.leader: IsGuildLeader() result (nil: no IsGuildLeader at all);
    -- opts.ranks: roster ranks; opts.myRankIndex: GetGuildInfo rank.
    local function login(opts)
        opts = opts or {}
        wow.reset({ roster = roster(opts.ranks), myRankIndex = opts.myRankIndex })
        installBags()
        if opts.leader ~= nil then
            local v = opts.leader
            IsGuildLeader = function() if v == "nil" then return nil end return v end
        else
            IsGuildLeader = nil
        end
        local ns = wow.loadAddon(ADDON_DIR, opts.saved)
        ns.Share.rand = function(a) return a end
        if ns.Supply then ns.Supply.rand = function(a) return a end end
        wow.fire("PLAYER_LOGIN")
        wow.fire("PLAYER_ENTERING_WORLD")
        wow.advance(30)
        wow.advance(40)
        wow.state.sent = {}
        ns.Bank.invalidate()
        return ns
    end
    local function asLeaderA() return login({ ranks = { A = "會長", B = "會員" }, leader = true }) end

    local function T0() return math.floor(wow.state.now) end
    local function vMsg(ns, a, t, v)
        return "S1~V~" .. a .. "~K~" .. ns.Share.b36(t) .. "~" .. ns.Share.hash(v) .. "~" .. v
    end
    local function from(ns, sender, text) return ns.Share.onMessage("GFTKS", text, "GUILD", sender) end
    -- A list value: entries = { { a, kinds, enabled, epoch } }.
    local function list(ns, leader, epoch, entries)
        local d = { epoch = epoch, leader = leader, entries = {} }
        for _, e in ipairs(entries) do d.entries[#d.entries + 1] = { a = e[1], kinds = e[2], enabled = e[3], epoch = e[4] or epoch } end
        return assert(ns.Bank.encode(d))
    end
    local function done(fn) return function() local okRun, err = pcall(fn); removeGame(); if not okRun then error(err, 0) end end end

    ---------------------------------------------------------------------------
    -- Who is guild master
    ---------------------------------------------------------------------------

    test("GF-012 authority: member by default, leader only when IsGuildLeader and the roster agree", done(function()
        local ns = login()
        local auth, leaderA = ns.Bank.authority()
        eq(auth, "member", "rank 4 and B is guild master"); eq(leaderA, B, "roster says B")
        ns = asLeaderA()
        eq((ns.Bank.authority()), "leader", "IsGuildLeader true and roster rank 0")
        ns = login({ ranks = { A = "會長", B = "會員" }, myRankIndex = 0 })
        eq((ns.Bank.authority()), "leader", "without IsGuildLeader: GetGuildInfo rank 0 and the roster")
    end))

    test("GF-012 authority unknown refuses to manage (conflict, nil, empty roster, two masters)", done(function()
        local ns = login({ leader = true }) -- IsGuildLeader says yes, the roster says B
        local auth, _, why = ns.Bank.authority()
        eq(auth, "unknown", "conflict"); eq(why, "conflict", "why")
        eq(ns.Bank.appoint(PEER_C), "no-authority", "refused")
        eq(ns.Share.get(A, "K"), nil, "nothing stored")
        ns = login({ ranks = { A = "會長", B = "會員" }, leader = "nil" })
        eq((ns.Bank.authority()), "unknown", "IsGuildLeader nil")
        eq(ns.Bank.revoke(C), "no-authority", "refused")
        ns = asLeaderA()
        setRanks({ A = "會長", B = "會長" }, ns)
        eq((ns.Bank.authority()), "unknown", "two rank-0 rows")
        eq(ns.Bank.current().state, "unknown", "no list trusted either")
        wow.state.roster = {}; ns.Bank.invalidate()
        eq((ns.Bank.authority()), "unknown", "roster not loaded")
        eq(ns.Bank.appoint(PEER_C), "no-authority", "refused")
        eq(ns.Bank.canManage(), false, "cannot manage")
        ok(ns.Bank.stats.refused >= 1, "counted")
    end))

    ---------------------------------------------------------------------------
    -- Publishing and checking
    ---------------------------------------------------------------------------

    test("GF-012 the guild master appoints: own record K, sent to GUILD, sources per kind", done(function()
        local ns = asLeaderA()
        eq(ns.Bank.appoint(PEER_C), "ok", "appointed")
        eq(ns.Bank.appoint(PEER_C), "same", "again: no change")
        eq(ns.Bank.appoint("沒有這個人"), "not-found", "unknown name")
        local rec = ns.Share.get(A, "K")
        ok(rec and rec.fromAuthor, "own record")
        local cur = ns.Bank.current()
        eq(cur.state, "ok", "in force"); ok(cur.direct, "my own")
        ok((ns.Bank.isCustodian(C)), "C is custodian")
        local src = ns.Bank.sources()
        eq(#src, 2, "bags and bank"); eq(src[1].sourceID, C .. ".b", "bags source"); eq(src[2].kind, "bank", "bank source")
        eq(src[1].custodianGUID, "Player-" .. C, "GUID"); ok(src[1].authorityEpoch >= ns.Share.EPOCH, "epoch")
        wow.advance(31)
        local found = false
        for _, m in ipairs(wow.state.sent) do
            if m.prefix == "GFTKS" and m.msg:find("S1~V~" .. A .. "~K~", 1, true) == 1 then found = true end
        end
        ok(found, "went out")
        eq(ns.Bank.setKind(C, "bank", false), "ok", "bags only")
        eq(ns.Bank.setKind(C, "bags", false), "last-kind", "the last kind stays")
        eq(#ns.Bank.sources(), 1, "one source left")
        eq(ns.Share.isLocalGroup("K"), true, "GF Sync leaves it out")
    end))

    test("GF-012 a member takes the guild master's list; I am custodian", done(function()
        local ns = login()
        local t = T0()
        eq(from(ns, PEER_B, vMsg(ns, B, t, list(ns, B, t, { { A, "bk", true } }))), "new", "stored")
        local cur = ns.Bank.current()
        eq(cur.state, "ok", "in force"); ok(cur.direct, "heard from B")
        eq(ns.Bank.myRole(), "custodian", "my role")
        ok(ns.Bank.diagText():find("保管人", 1, true), "diagnostics")
    end))

    test("GF-012 a non-guild-master's list is refused (own name, false leader field)", done(function()
        local ns = login()
        local t = T0()
        -- C publishes a list in C's own name.
        from(ns, PEER_C, vMsg(ns, C, t, list(ns, C, t, { { A, "bk", true } })))
        eq(ns.Bank.current().state, "expired", "C is not guild master")
        eq((ns.Bank.isCustodian(A)), false, "not custodian")
        eq(ns.Bank.myRole(), "member", "member")
        -- C relays a list under B's name whose leader field says C.
        from(ns, PEER_C, vMsg(ns, B, t, list(ns, C, t, { { A, "bk", true } })))
        eq(ns.Bank.current().state, "forged", "leader field does not match")
        eq((ns.Bank.isCustodian(A)), false, "still not")
        -- Malformed lists are not even stored.
        eq(from(ns, PEER_C, vMsg(ns, B, t + 1, "1;zz;" .. B .. ";" .. A .. ",x,1,1")), "invalid", "bad kinds")
    end))

    test("GF-012 a relayed copy under the master's name is marked 經轉送", done(function()
        local ns = login()
        local t = T0()
        from(ns, PEER_C, vMsg(ns, B, t, list(ns, B, t, { { A, "b", true } })))
        local cur = ns.Bank.current()
        eq(cur.state, "ok", "accepted"); eq(cur.direct, false, "not heard from B")
    end))

    test("GF-012 a forged withdrawal (X) of the master's list is refused", done(function()
        local ns = login()
        local t = T0()
        from(ns, PEER_B, vMsg(ns, B, t, list(ns, B, t, { { A, "bk", true } })))
        from(ns, PEER_C, "S1~X~" .. B .. "~K~" .. ns.Share.b36(t + 5))
        ok(ns.Share.get(B, "K"), "record kept")
        ok((ns.Bank.isCustodian(A)), "still custodian")
    end))

    ---------------------------------------------------------------------------
    -- Revocation, old packets, a new guild master
    ---------------------------------------------------------------------------

    test("GF-012 revocation spreads; an old packet never brings it back", done(function()
        local ns = login()
        local t1 = T0()
        local v1 = list(ns, B, t1, { { A, "bk", true } })
        from(ns, PEER_B, vMsg(ns, B, t1, v1))
        ok((ns.Bank.isCustodian(A)), "custodian")
        wow.advance(100)
        local t2 = T0()
        from(ns, PEER_B, vMsg(ns, B, t2, list(ns, B, t2, { { A, "bk", false, t2 }, { C, "k", true, t2 } })))
        local on, e = ns.Bank.isCustodian(A)
        eq(on, false, "revoked"); eq(e.enabled, false, "the entry says so")
        ok((ns.Bank.isCustodian(C)), "C appointed")
        -- The old packet again: Share keeps the newer one.
        eq(from(ns, PEER_C, vMsg(ns, B, t1, v1)), "older", "Share refuses it")
        eq((ns.Bank.isCustodian(A)), false, "still revoked")
        -- Share lost the record (pruned / evicted), then the old one comes back.
        ns.Share.store().rec[B].K = nil
        eq(from(ns, PEER_C, vMsg(ns, B, t1, v1)), "new", "Share stores it")
        eq(ns.Bank.current().state, "old", "epoch below the one seen")
        eq((ns.Bank.isCustodian(A)), false, "not back")
        eq(ns.Bank.myRole(), "member", "member")
    end))

    test("GF-012 a new guild master: the old list stops counting, the former master stops publishing", done(function()
        local ns = login()
        local t = T0()
        from(ns, PEER_B, vMsg(ns, B, t, list(ns, B, t, { { A, "bk", true } })))
        ok((ns.Bank.isCustodian(A)), "custodian under B")
        setRanks({ B = "會員", C = "會長" }, ns)
        eq(ns.Bank.current().state, "expired", "B's list no longer counts")
        eq((ns.Bank.isCustodian(A)), false, "not custodian")
        -- The former master's own computer.
        ns = asLeaderA()
        eq(ns.Bank.appoint(PEER_C), "ok", "appointed while master")
        ok(ns.Bank.ownValue(), "publishing")
        setRanks({ A = "會員", B = "會長" }, ns)
        IsGuildLeader = function() return false end
        eq((ns.Bank.authority()), "member", "known: no longer master")
        eq(ns.Bank.checkStepDown(), true, "original put aside")
        eq(ns.Bank.ownValue(), nil, "nothing published any more")
        ok(ns.Bank.guildData().previous, "kept as previous")
        eq(ns.Bank.appoint(PEER_C), "no-authority", "cannot manage")
        -- Unknown (not member) keeps the original.
        ns = asLeaderA()
        ns.Bank.appoint(PEER_C)
        wow.state.roster = {}; ns.Bank.invalidate()
        eq(ns.Bank.checkStepDown(), false, "unknown: nothing changed")
        ok(ns.Bank.guildData().own, "kept")
    end))

    test("GF-012 the master's computer republishes over a forged copy under its name", done(function()
        local ns = asLeaderA()
        ns.Bank.appoint(PEER_C)
        local before = ns.Bank.current().list.epoch
        local t = T0() + 50
        from(ns, PEER_C, vMsg(ns, A, t, list(ns, A, t, { { D, "bk", true } })))
        eq(ns.Bank.stats.healed, 1, "healed once")
        local cur = ns.Bank.current()
        eq(cur.state, "ok", "in force")
        ok((ns.Bank.isCustodian(C)), "my C is back"); eq((ns.Bank.isCustodian(D)), false, "their D is gone")
        ok(cur.list.epoch > t and cur.list.epoch > before, "newer epoch than the forgery")
    end))

    ---------------------------------------------------------------------------
    -- Scope and privacy
    ---------------------------------------------------------------------------

    test("GF-012 scope: only an enabled custodian, only the kinds on the list, no account bank", done(function()
        local ns = login()
        eq(ns.Bank.setScope("bags", 0, true), "not-custodian", "not on the list")
        local t = T0()
        from(ns, PEER_B, vMsg(ns, B, t, list(ns, B, t, { { A, "b", true } })))
        eq(ns.Bank.setScope("bags", 0, true), "ok", "backpack")
        eq(ns.Bank.setScope("bags", 5, true), "ok", "reagent bag")
        eq(ns.Bank.setScope("bank", 6, true), "not-custodian", "bank not given")
        eq(ns.Bank.setScope("bank", 15, true), "invalid", "account bank is not offered")
        eq(ns.Bank.setScope("bags", -1, true), "invalid", "unknown bag")
        local s = ns.Bank.scopeInForce()
        eq(#s.bags, 2, "two bags"); eq(#s.bank, 0, "no bank")
        local fresh = ns.Bank.scope()
        eq(next(fresh.bank), nil, "nothing ticked by default")
        wow.advance(10)
        local t2 = T0()
        from(ns, PEER_B, vMsg(ns, B, t2, list(ns, B, t2, { { A, "b", false } })))
        eq(#ns.Bank.scopeInForce().bags, 0, "revoked: nothing counts")
        eq(ns.Bank.setScope("bags", 1, true), "not-custodian", "cannot set")
    end))

    test("GF-012 privacy: no bag, bank or item function in Bank.lua / BankUI.lua, none called", done(function()
        for _, f in ipairs({ "Bank.lua", "BankUI.lua" }) do
            local h = assert(io.open(ADDON_DIR .. "/" .. f, "rb")); local src = h:read("*a"); h:close()
            src = src:gsub("%-%-[^\n]*", "") -- comments may name them
            for _, fn in ipairs({ "C_Container", "GetContainer", "C_Bank", "GetItemCount", "GetBag", "GetInventoryItem", "C_Item" }) do
                ok(not src:find(fn, 1, true), f .. " calls " .. fn)
            end
        end
        local ns = asLeaderA()
        ns.Bank.appoint(PEER_C); ns.Bank.appoint("測試甲")
        ns.Bank.setScope("bags", 0, true); ns.Bank.setScope("bank", 6, true)
        ns.Framework.open("bank")
        ns.BankUI.refresh()
        eq(calls, 0, "no bag / bank call from the bank files")
    end))

    ---------------------------------------------------------------------------
    -- The page
    ---------------------------------------------------------------------------

    test("GF-012 page: under 物資調度, member sees the list with every button off, stock 尚未開放", done(function()
        local ns = login()
        local t = T0()
        from(ns, PEER_B, vMsg(ns, B, t, list(ns, B, t, { { C, "bk", true }, { D, "b", false } })))
        local F = ns.Framework
        eq(F.entryOf(F.get("bank")), "logistics", "物資調度")
        F.open("bank")
        local c = ns.BankUI.controls
        ok(c, "built")
        eq(c.rows[1].name:GetText(), "測試丙", "active first")
        eq(c.rows[1].state:GetText(), "有效", "state")
        eq(c.rows[2].state:GetText(), "已撤銷", "revoked shown")
        eq(c.appoint.disabled, true, "指定 off")
        eq(c.rows[1].revoke.disabled, true, "撤銷 off")
        eq(ns.Theme.hoverable(c.appoint), false, "never lights")
        -- GF-012-B: the stock list replaced 「庫存：第二階段才有」; with no snapshot yet it says why.
        eq(c.stock.kind, "empty", "stock state")
        eq(c.stock.text:GetText(), "保管人還沒分享庫存", "GF-012-B: why the stock list is empty")
        eq(c.scopeState.text:GetText(), "你不是保管人", "no scope for a member")
        ok(c.role:GetText():find("職工", 1, true), "role (GF-UI-K: 成員 = 職工)")
    end))

    -- GF-UI-M (owner): more than 8 people: 「還有 N 位」 and the wheel; the same 8 rows.
    test("GF-UI-M bank list: 12 people scroll with the wheel in the same pooled rows; 「還有 N 位」; the 庫存 text", done(function()
        local ns = login()
        local t = T0()
        local entries = {}
        for i = 1, 12 do
            entries[i] = { string.format("0000-%08X", 0x100 + i), "b", i <= 10, t - i }
        end
        from(ns, PEER_B, vMsg(ns, B, t, list(ns, B, t, entries)))
        ns.Framework.open("bank")
        local UI = ns.BankUI
        local c = UI.controls
        -- GF-012-C: 8 rows again (GF-012-B had 4; the stock has its own view now).
        eq(#c.rows, UI.ROWS, "the pooled rows"); eq(UI.ROWS, 8, "8 rows")
        eq(c.total, 12, "12 on the list")
        local function shown() local n = 0; for _, r in ipairs(c.rows) do if r:IsShown() then n = n + 1 end end return n end
        eq(shown(), UI.ROWS, "all rows shown")
        eq(c.more:GetText(), "還有 4 位，用滑鼠滾輪往下看", "the more line")
        local first = c.rows[1].entry
        -- The wheel on a row: one down.
        c.rows[1]:GetScript("OnMouseWheel")(c.rows[1], -1)
        eq(c.offset, 1, "one down")
        ok(c.rows[1].entry ~= first, "the next person on top")
        eq(c.more:GetText(), "還有 3 位，用滑鼠滾輪往下看", "three more")
        for _ = 1, 10 do UI.scroll(-1) end
        eq(c.offset, 4, "stops at the last person")
        eq(c.more:GetText(), "", "the last one in view: no line")
        eq(c.rows[UI.ROWS].state:GetText(), "已撤銷", "the revoked ones at the end")
        ok(not UI.scroll(-1), "no further")
        UI.scroll(20)
        eq(c.offset, 0, "back to the top")
        eq(#c.rows, UI.ROWS, "no new rows")
        eq(c.stock.text:GetText(), UI.STOCK_EMPTY.nobody[1], "GF-012-B: made-up custodians not in the roster are nobody")
    end))

    test("GF-012 page: the master's buttons work; a custodian sees the scope boxes", done(function()
        local ns = asLeaderA()
        ns.Framework.open("bank")
        ns.BankUI.setView("setup") -- GF-012-C: the list has its own view
        local c = ns.BankUI.controls
        eq(c.appoint.disabled, false, "指定 on")
        c.name:SetText("測試丙")
        wow.click(c.appoint)
        eq(c.rows[1].name:GetText(), "測試丙", "appointed row")
        eq(c.rows[1].revoke.disabled, false, "撤銷 on")
        wow.click(c.rows[1].revoke)
        eq(c.rows[1].state:GetText(), "已撤銷", "revoked")
        -- A custodian (me, appointed by myself as master).
        ns.Bank.appoint("測試甲", "b")
        ns.BankUI.refresh()
        eq(c.scopeState.kind, nil, "scope shown")
        local bagBox, bankBox = c.scope.bags[1], c.scope.bank[1]
        eq(bagBox.disabled, false, "bags editable")
        eq(bankBox.disabled, true, "bank not given: off")
        wow.click(bagBox)
        eq(ns.Bank.scope().bags[0], true, "saved")
    end))
end
