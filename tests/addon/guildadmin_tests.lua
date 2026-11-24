-- GF-001-Q (0.12.5): guild management on the 「公會名冊」 page (owner: 「我希望
-- 公會清單上也能進行公會的設定操作（同原公會介面）」). Only with the game's
-- permission, only functions the client has, the game's confirm box before
-- removing or demoting, and the officer note never leaves the game's UI.
-- Made-up data only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local C, D, B = "測試丙-測試伺服器", "測試丁-測試伺服器", "測試乙-測試伺服器"
    local ALL = { invite = true, promote = true, demote = true, remove = true, publicNote = true, officerNote = true,
        viewOfficer = true, motd = true, info = true }

    local function login(opts)
        wow.reset(opts)
        local ns = wow.login(ADDON_DIR)
        ns.Framework.open("roster")
        return ns
    end
    local function rowFor(ns, name)
        for _, row in ipairs(ns.UI.rows()) do if row:IsShown() and row.memberName == name then return row end end
    end
    local function memberOf(ns, name) local r = rowFor(ns, name); return r and r.member end
    local function barKeys(ns)
        local out = {}
        for _, b in ipairs(ns.UI.actionBar.buttons) do if b:IsShown() then out[#out + 1] = b.action end end
        return table.concat(out, ",")
    end
    local function selectRow(ns, name)
        local row = rowFor(ns, name)
        ok(row, "row " .. name)
        row._scripts.OnMouseUp(row, "LeftButton")
        return row
    end
    local function plain(t) return (tostring(t or ""):gsub("|T.-|t", ""):gsub("^%s+", "")) end
    local function calls() return table.concat(wow.state.guildCalls, ",") end

    test("GF-001-Q without guild rights: only whisper, group and look up; no admin buttons", function()
        local ns = login()
        selectRow(ns, C)
        eq(barKeys(ns), "whisper,group,who", "the member bar")
        local items = ns.UI.memberMenuItems(memberOf(ns, C))
        local texts = {}
        for _, it in ipairs(items) do texts[#texts + 1] = plain(it.text) end
        eq(table.concat(texts, ","), "密語,組隊,查看", "the right-click menu has the same")
        eq(ns.UI.inviteButton._shown, false, "no 邀請入會")
        eq(ns.UI.infoButton._shown, true, "公會資訊 (reading is for everyone)")
        eq(ns.UI.gameGuildButton._shown, true, "開啟遊戲公會介面")
        eq(ns.UI.officerVisible, false, "no 幹部註記 column")
        local row = rowFor(ns, C)
        eq(row.cell.note:GetText(), "公開備註", "the guild note is shown")
        eq(row.cell.officerNote._shown, false, "officer note cell hidden")
        -- The guild info window: read only.
        local f = ns.UI.openGuildInfo()
        eq(f.editMotd._shown, false, "no edit for the message of the day")
        eq(f.editInfo._shown, false, "no edit for the guild info")
        -- Whisper, group and look up call the game's functions.
        selectRow(ns, C)
        for _, b in ipairs(ns.UI.actionBar.buttons) do if b:IsShown() then wow.click(b) end end
        eq(calls(), "tell:" .. C .. ",group:" .. C .. ",who:n-\"測試丙\"", "whisper, group, /who")
    end)

    test("GF-001-Q with rights: by the target's rank (never up to mine, never on higher ranks or myself)", function()
        local ns = login({ guildPerms = ALL, myRankIndex = 1 })
        selectRow(ns, C) -- 會員 (2)
        eq(barKeys(ns), "whisper,group,who,demote,publicNote,officerNote,remove", "會員: not promoted to my own rank")
        selectRow(ns, D) -- 新進 (3, the lowest)
        eq(barKeys(ns), "whisper,group,who,promote,publicNote,officerNote,remove", "新進: promote, no demote below the lowest")
        selectRow(ns, B) -- 會長 (0)
        eq(barKeys(ns), "whisper,group,who,publicNote,officerNote", "the guild master: notes only")
        selectRow(ns, "測試甲-測試伺服器") -- myself
        eq(barKeys(ns), "whisper,who,publicNote,officerNote", "myself: no group, no rank change, no remove")
        eq(ns.UI.inviteButton._shown, true, "邀請入會")
        eq(ns.UI.officerVisible, true, "幹部註記 column")
        eq(rowFor(ns, C).cell.officerNote:GetText(), "幹部備註", "officer note shown")
        local items = ns.UI.memberMenuItems(memberOf(ns, D))
        eq(#items, 7, "right-click: the same 7 actions")
    end)

    test("GF-001-Q removing and demoting ask first in the game's confirm box; promoting does not", function()
        local ns = login({ guildPerms = ALL, myRankIndex = 1 })
        selectRow(ns, C)
        local function press(key) for _, b in ipairs(ns.UI.actionBar.buttons) do if b:IsShown() and b.action == key then wow.click(b); return true end end end
        ok(press("remove"), "踢出公會 pressed")
        eq(calls(), "", "nothing yet")
        local p = wow.popup()
        ok(p and p.text:find("測試丙", 1, true) and p.text:find("踢出公會", 1, true), "the box names who and what: " .. tostring(p and p.text))
        wow.cancelPopup()
        eq(calls(), "", "cancelled: nothing")
        press("remove")
        wow.acceptPopup()
        eq(calls(), "uninvite:" .. C, "confirmed: removed")
        wow.state.guildCalls = {}
        press("demote")
        ok(wow.popup().text:find("降一階", 1, true), "demote asks too")
        wow.acceptPopup()
        eq(calls(), "demote:" .. C, "confirmed: demoted")
        wow.state.guildCalls = {}
        selectRow(ns, D)
        press("promote")
        eq(calls(), "promote:" .. D, "promote at once")
        eq(wow.popup(), nil, "no box for promoting")
    end)

    test("GF-001-Q notes, the message of the day, guild info, invite, the game's guild window", function()
        local ns = login({ guildPerms = ALL, myRankIndex = 1 })
        selectRow(ns, C)
        local function press(key) for _, b in ipairs(ns.UI.actionBar.buttons) do if b:IsShown() and b.action == key then wow.click(b) end end end
        press("publicNote")
        eq(wow.popup().editBox:GetText(), "公開備註", "the box starts with the note")
        wow.acceptPopup("新的公會註記")
        eq(calls(), "publicNote:3:新的公會註記", "GuildRosterSetPublicNote(index, text)")
        ns.GuildAdmin.invalidate(); ns.UI.refresh()
        eq(rowFor(ns, C).cell.note:GetText(), "新的公會註記", "shown")
        wow.state.guildCalls = {}
        press("officerNote")
        wow.acceptPopup("新的幹部註記")
        eq(calls(), "officerNote:3:新的幹部註記", "GuildRosterSetOfficerNote(index, text)")
        wow.state.guildCalls = {}
        wow.click(ns.UI.inviteButton)
        wow.acceptPopup("測試戊")
        eq(calls(), "invite:測試戊", "GuildInvite")
        wow.state.guildCalls = {}
        wow.state.motd = "今天打黑石"
        local f = ns.UI.openGuildInfo()
        eq(f.motd:GetText(), "今天打黑石", "message of the day")
        ok(f.editMotd._shown and f.editInfo._shown, "editable with the rights")
        wow.click(f.editMotd)
        wow.acceptPopup("明天打通靈")
        eq(calls(), "motd:明天打通靈", "GuildSetMOTD")
        eq(f.motd:GetText(), "明天打通靈", "shown at once")
        wow.state.guildCalls = {}
        wow.click(ns.UI.gameGuildButton)
        eq(calls(), "guildFrame:nil", "the game's guild window")
        -- ESC closes the info window first, the roster after.
        ns.UI.openGuildInfo()
        wow.pressEscape()
        ok(not f:IsShown() and ns.Framework.isShown(), "ESC: the info window first")
    end)

    test("GF-001-Q functions the client lacks are hidden; 同步與診斷 says which", function()
        local ns = login({ guildPerms = ALL, myRankIndex = 1, noGuildAdmin = true })
        selectRow(ns, C)
        eq(barKeys(ns), "whisper,group,who", "only what needs no guild function")
        eq(ns.UI.inviteButton._shown, false, "no 邀請入會")
        eq(ns.UI.officerVisible, false, "no officer column without CanViewOfficerNote")
        eq(ns.UI.gameGuildButton._shown, false, "no ToggleGuildFrame / ToggleFriendsFrame: hidden")
        local text = ns.GuildAdmin.diagText()
        ok(text:find("GuildUninvite", 1, true) and text:find("沒有", 1, true), "diag lists the missing ones: " .. text)
        ok(text:find("沒有管理權限", 1, true), "and no rights")
        local d = ns.Diag.open()
        local all = {}
        for _, l in ipairs(ns.Diag.lines()) do all[#all + 1] = l:GetText() end
        ok(table.concat(all, "\n"):find("函式", 1, true), "in the 同步與診斷 window")
        -- Without the confirm box, removing and demoting are hidden too.
        ns = login({ guildPerms = ALL, myRankIndex = 1 })
        StaticPopup_Show = nil
        ns.GuildAdmin.invalidate()
        selectRow(ns, C)
        eq(barKeys(ns), "whisper,group,who,publicNote,officerNote", "no remove / demote / notes edit without a confirm box")
    end)

    test("GF-001-Q the officer note never reaches SavedVariables, the outbox or shared records", function()
        local SECRET = "幹部私密測試字串"
        local roster = wow.defaultRoster()
        roster[3].officerNote = SECRET
        roster[3].note = "公開測試字串"
        local ns = login({ guildPerms = ALL, myRankIndex = 1, roster = roster })
        eq(rowFor(ns, C).cell.officerNote:GetText(), SECRET, "shown in game to an officer")
        wow.advance(120)
        local saved = wow.logout()
        local text = wow.serializeSV("GreenFangToolkitDB", saved.GreenFangToolkitDB)
        ok(not text:find(SECRET, 1, true), "not in SavedVariables (outbox, roster snapshot, share)")
        ok(not text:find("幹部備註", 1, true), "no officer note at all")
        ok(not text:find("公開測試字串", 1, true), "the guild note is not stored either (unchanged rules)")
        for _, m in ipairs(wow.state.sent) do ok(not m.msg:find(SECRET, 1, true), "never sent") end
    end)

    test("GF-001-Q the page: the guild buttons (bottom row, GF-UI-B) and the member bar do not overlap", function()
        local ns = login({ guildPerms = ALL, myRankIndex = 1 })
        local list = { ns.UI.inviteButton, ns.UI.infoButton, ns.UI.gameGuildButton }
        local prevRight
        for _, b in ipairs(list) do
            local x = b._points[1][4]
            eq(b._points[1][1], "BOTTOMLEFT", "on the bottom row")
            ok(x >= 20, "inside the page on the left")
            if prevRight then ok(x >= prevRight, "apart") end
            prevRight = x + b.gfWidth
            ok(b._h >= 30, "30 px buttons")
        end
        ok(prevRight <= ns.UI.diagLeft, "left of 診斷")
        selectRow(ns, D)
        local last
        for _, b in ipairs(ns.UI.actionBar.buttons) do
            if b:IsShown() then
                ok(b.gfWidth >= 32, "32 px icons")
                ok(not b.label._font:find("Small"), "16 px names")
                if last then
                    local need = last.flowX + last.gfWidth + 4 + wow.textWidth(last.label._text, last.label._font)
                    ok(b.flowX >= need, "no overlap: " .. last.label._text .. " / " .. b.label._text)
                end
                last = b
            end
        end
        ok(last.flowX + ns.OrdersUI.buttonSpan(last) <= ns.UI.ROW_WIDTH, "inside the bar")
        ok(ns.UI.actionBar.nameWidth >= 22 + wow.textWidth("測試丁", ns.FIELD_FONT), "the name before the buttons")
    end)
end
