-- AdventureUI (GF-002-B, spec §11, §8): the 「冒險」 page, the new-ticket
-- and worker-ticket popups, and the adventure number on the minimap button.
-- R-11.1: icons first, at most one or two buttons a row, no explanation
-- lines or time stamps; technical details only in 同步與診斷.
-- R-8.3: adventure rows start with the destination icon (orders start with
-- the item), and their state is the role-gap icons (orders use ⏳🔨📦✅❌).

local _, ns = ...
local str = ns.str

local UI = {}
ns.AdventureUI = UI

local function A() return ns.Adventure end
local function S() return ns.Share end
local Icons = ns.Icons

UI.ICON = {
    dungeon = "Interface\\Icons\\INV_Misc_Key_03",
    quest = "Interface\\Icons\\INV_Misc_Note_01",
    now = "Interface\\Icons\\Spell_Nature_TimeStop",
    t = "Interface\\Icons\\Ability_Defend",
    h = "Interface\\Icons\\Spell_Holy_Heal",
    d = "Interface\\Icons\\INV_Sword_04",
    any = "Interface\\Icons\\INV_Misc_GroupNeedMore",
    apply = "Interface\\Icons\\INV_Gauntlets_04",
    invite = "Interface\\Icons\\INV_Letter_15",
    yes = "Interface\\RaidFrame\\ReadyCheck-Ready",
    no = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    wait = "Interface\\RaidFrame\\ReadyCheck-Waiting",
    form = "Interface\\Icons\\Ability_Warrior_BattleShout",
    reopen = "Interface\\Buttons\\UI-RefreshButton",
    attention = "Interface\\GossipFrame\\AvailableQuestIcon",
    offline = "Interface\\FriendsFrame\\StatusIcon-Offline",
    online = "Interface\\FriendsFrame\\StatusIcon-Online",
    consent = "Interface\\Icons\\Spell_Holy_SealOfWisdom",
    direct = "Interface\\Icons\\Spell_Holy_SealOfMight",
    worker = "Interface\\Icons\\INV_Misc_Bag_10",
    tag_quest = "Interface\\Icons\\INV_Misc_Note_02", tag_farm = "Interface\\Icons\\Spell_Nature_Reincarnation",
    tag_slow = "Interface\\Icons\\Ability_Hunter_Pet_Turtle", tag_fast = "Interface\\Icons\\Ability_Rogue_Sprint",
    tag_voice = "Interface\\Icons\\Spell_Holy_Silence",
}
UI.ROLE_NAME = { t = "坦", h = "補", d = "輸出", any = "隊員" }
UI.TAG_KEYS = { "quest", "farm", "slow", "fast", "voice" }

-- GF-002-C: role, person, time and quest marks use the game's own art (GameIcons, with fallbacks).
UI.GAME = { t = "role_t", h = "role_h", d = "role_d", any = "person", now = "now", today = "today", future = "future",
    quest = "quest", dungeon = "key", worker = "worker", yes = "yes", no = "no", adventure = "adventure",
    group = "group", lfg = "lfg", -- GF-002-G: several heads; the game's group finder
    final = "final", calendar = "calendar", -- GF-002-H: 定案 (a sealed scroll), 行事曆 (an agenda)
    -- GF-002-E: icons that match their meaning (MANUAL §3z).
    adjust = "adjust", direct = "direct", consent = "consent",
    tag_quest = "tag_quest", tag_farm = "tag_farm", tag_slow = "tag_slow", tag_fast = "tag_fast", tag_voice = "tag_voice" }
local function tex(key, size)
    local g = UI.GAME[key]
    if g then return ns.GameIcons.markup(g, size) end
    return "|T" .. (UI.ICON[key] or key) .. ":" .. tostring(size or 14) .. "|t"
end
UI.tex = tex
local function setIcon(t, key)
    local g = UI.GAME[key]
    if g then return ns.GameIcons.set(t, g) end
    if Icons.set(t, UI.ICON[key] or key) then t:Show(); return true end
    t:Hide(); return false
end
UI.setIcon = setIcon

---------------------------------------------------------------------------
-- Pure helpers
---------------------------------------------------------------------------

-- Seconds the server clock is ahead of the local one.
function UI.skew() return (ns.num((ns.call(GetServerTime))) or ns.now()) - ns.now() end

-- Local "HH:MM" of a server time (R-4.2: stored as server time, shown local).
function UI.clock(t)
    if not t then return "" end
    return date("%H:%M", t - UI.skew())
end
-- GF-002-F (owner: 「未來日期要包含年」): "2026/11/25".
function UI.day(t)
    if not t then return "" end
    return date("%Y/%m/%d", t - UI.skew())
end
UI.WEEKDAY = { "日", "一", "二", "三", "四", "五", "六" }
-- "2026/11/25（三）"
function UI.dayText(t)
    if not t then return "" end
    local d = date("*t", t - UI.skew())
    return UI.day(t) .. "（" .. UI.WEEKDAY[d.wday] .. "）"
end

-- Server time of 00:00 (the player's clock) dayOff days from the day of t (default now).
function UI.dayStart(dayOff, t)
    local skew = UI.skew()
    local localT = (t or S().serverNow()) - skew
    local d = date("*t", localT)
    local midnight = localT - (d.hour * 3600 + d.min * 60 + d.sec)
    return midnight + (dayOff or 0) * 86400 + skew
end
-- Days between today (the player's clock) and t: 0 today, 1 tomorrow.
function UI.dayOffset(t)
    return math.floor((UI.dayStart(0, t) - UI.dayStart(0)) / 86400 + 0.5)
end
-- "今天" / "明天" / "2026/11/27"
function UI.dayWord(t)
    local off = UI.dayOffset(t)
    if off == 0 then return "今天" end
    if off == 1 then return "明天" end
    return UI.day(t)
end
-- "23:00～02:00（隔天）"
function UI.spanText(s, e)
    if not s then return "" end
    local text = UI.clock(s) .. "～" .. UI.clock(e)
    if e and UI.dayStart(0, e) ~= UI.dayStart(0, s) then text = text .. "（隔天）" end
    return text
end
-- "明天 00:30" (today's times without the word)
function UI.startText(t)
    if UI.dayOffset(t) == 0 then return UI.clock(t) end
    return UI.dayWord(t) .. " " .. UI.clock(t)
end

-- GF-002-H: one slot { now, s, d }: "現在" / "現在～22:30" / "今天 20:00" /
-- "明天 20:00～22:00" / "2026/11/27 23:00～01:00（隔天）". d = seconds or nil (no length).
function UI.slotText(sl, size)
    if not sl then return "" end
    if sl.now then
        return tex("now", size) .. " 現在" .. (sl.d and sl.s and ("～" .. UI.clock(sl.s + sl.d)) or "")
    end
    local icon = tex(UI.dayOffset(sl.s) <= 1 and "today" or "future", size)
    local e = sl.d and (sl.s + sl.d) or (sl.e ~= sl.s and sl.e) or nil
    return icon .. " " .. UI.dayWord(sl.s) .. " " .. (e and UI.spanText(sl.s, e) or UI.clock(sl.s))
end

-- GF-002-G (owner: 「時間設定簡化，不要這樣分三種」): one line, the day word first.
-- "現在～22:30" / "今天 20:00～22:00" / "2026/11/27 20:00～22:00"
-- GF-002-H: the finalized (or only) slot; else the first one and "+N" (R-16.8).
function UI.timeText(v)
    if v.slots and #v.slots > 0 then
        if v.slot then
            return UI.slotText(v.slot) .. ((#v.slots > 1 and v.final) and ("  " .. tex("final") .. " 定案") or "")
        end
        return UI.slotText(v.slots[1]) .. (#v.slots > 1 and ("  +" .. (#v.slots - 1)) or "")
    end
    if v.timeMode == "n" then
        return tex("now") .. " 現在" .. (v.finish and ("～" .. UI.clock(v.finish)) or "")
    end
    return tex(v.timeMode == "f" and "future" or "today") .. " " .. UI.dayWord(v.start) .. " " .. UI.spanText(v.start, v.finish)
end

-- GF-002-C item 2: one entry per seat, in role order: { role, filled }.
function UI.slotList(v)
    local out = {}
    if v.capacity.any then
        local filled = v.capacity.any - (v.seats.any or 0)
        for i = 1, v.capacity.any do out[#out + 1] = { role = "any", filled = i <= filled } end
        return out
    end
    for _, r in ipairs(A().ROLES) do
        local cap = v.capacity[r] or 0
        local filled = cap - (v.seats[r] or 0)
        for i = 1, cap do out[#out + 1] = { role = r, filled = i <= filled } end
    end
    return out
end
UI.MAX_SLOTS = 10

-- Role gaps as icons: a filled seat bright, an empty one grey (R-8.3).
function UI.roleText(v)
    local parts = {}
    if v.capacity.any then
        local filled = v.capacity.any - (v.seats.any or 0)
        parts[#parts + 1] = tex("any") .. filled .. "/" .. v.capacity.any
    else
        for _, r in ipairs(A().ROLES) do
            local cap = v.capacity[r] or 0
            if cap > 0 then parts[#parts + 1] = tex(r) .. (cap - (v.seats[r] or 0)) .. "/" .. cap end
        end
    end
    return table.concat(parts, " ")
end

UI.STATE_NAME = { done = "成行", unfinished = "未成行", ended = "結束", cancel = "取消", formed = "成團" }
UI.TAG_NAME = { quest = "解任務", farm = "連刷", slow = "慢慢打", fast = "速刷", voice = "語音" }
function UI.tagText(tags)
    local out = {}
    for _, k in ipairs(UI.TAG_KEYS) do
        if math.floor((tags or 0) / A().TAGS[k]) % 2 == 1 then out[#out + 1] = tex("tag_" .. k) end
    end
    return table.concat(out, "")
end
function UI.tagNames(tags)
    local out = {}
    for _, k in ipairs(UI.TAG_KEYS) do
        if math.floor((tags or 0) / A().TAGS[k]) % 2 == 1 then out[#out + 1] = UI.TAG_NAME[k] end
    end
    return table.concat(out, "、")
end
-- GF-002-G (owner: 「備註和標記應該要可以直接看到」): the second line of a row:
-- each tag as its icon and name, then the note.
function UI.detailText(v)
    local parts = {}
    if v.dungeon and #(v.quests or {}) > 0 then parts[#parts + 1] = tex("quest", 18) .. " " .. UI.questsText(v.quests, v.questNames, v.questLevels, 1) end
    for _, k in ipairs(UI.TAG_KEYS) do
        if math.floor((v.tags or 0) / A().TAGS[k]) % 2 == 1 then parts[#parts + 1] = tex("tag_" .. k, 18) .. " " .. UI.TAG_NAME[k] end
    end
    if v.mode == "c" then parts[#parts + 1] = tex("consent", 18) .. " 團長同意" end
    local text = table.concat(parts, "   ")
    if v.note and v.note ~= "" then text = text .. (text ~= "" and "   " or "") .. "|cffd0d0d0" .. v.note .. "|r" end
    return text
end

-- GF-002-H (R-16.28): a quest's name and level: the ticket's synced names (qn,
-- in-game only), else my own log.
function UI.questName(id, names, levels)
    local log = A().questLog() or {}
    local info = log[tonumber(id) or id]
    local name = (names and names[tonumber(id)]) or (info and info.title) or ("#" .. tostring(id))
    local lv = levels and levels[tonumber(id)]
    if lv == nil and info then lv = info.scaling and "s" or info.level end
    return name, lv
end
-- Quest difficulty colors (the game's own when it has them).
function UI.questColor(level)
    if type(level) ~= "number" then return 1, 0.82, 0 end
    if type(GetQuestDifficultyColor) == "function" then
        local okC, c = pcall(GetQuestDifficultyColor, level)
        if okC and type(c) == "table" and c.r then return c.r, c.g, c.b end
    end
    local diff = level - (A().myLevel() or level)
    if diff >= 5 then return 1, 0.1, 0.1 end
    if diff >= 3 then return 1, 0.5, 0.25 end
    if diff >= -2 then return 1, 1, 0 end
    if diff >= -8 then return 0.25, 0.75, 0.25 end
    return 0.5, 0.5, 0.5
end
function UI.levelMark(lv)
    if lv == "s" then return "" end
    if type(lv) ~= "number" or lv <= 0 then return "" end
    local r, g, b = UI.questColor(lv)
    return string.format("|cff%02x%02x%02x%d|r", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), lv)
end
-- "測試任務甲 24 +2"
function UI.questsText(ids, names, levels, max)
    max = max or 1
    local parts = {}
    for i, q in ipairs(ids or {}) do
        if i <= max then
            local name, lv = UI.questName(q, names, levels)
            local mark = UI.levelMark(lv)
            parts[#parts + 1] = name .. (mark ~= "" and (" " .. mark) or "")
        end
    end
    local text = table.concat(parts, "、")
    if #(ids or {}) > max then text = text .. " +" .. (#ids - max) end
    return text
end

-- GF-002-G (owner: 「名稱盡量完整顯示」): the full dungeon name on the row.
-- GF-002-H (R-16.28): a quest ticket shows its first quest's full name and level, +N.
function UI.destText(v)
    if v.dungeon then
        local d = ns.AdventureData.byId[v.dungeon]
        return d and d.name or ns.AdventureData.short(v.dungeon)
    end
    if #v.quests == 0 then return "任務" end
    return UI.questsText(v.quests, v.questNames, v.questLevels, 1)
end

function UI.setDest(t, v)
    if v.dungeon then return ns.GameIcons.set(t, ns.GameIcons.dungeonKey(v.dungeon)) end
    return ns.GameIcons.set(t, "quest")
end

-- GF-002-F (owner: 「副本建議等級請清楚」): "26-36" (the game font has no en dash).
function UI.levelText(id)
    local d = ns.AdventureData.byId[id]
    return d and (d.min .. "-" .. d.max) or ""
end

-- Tooltip lines for a ticket: the levels and quest names (the rest is on the row).
function UI.ticketTooltip(v)
    local lines = {}
    if v.dungeon then
        local d = ns.AdventureData.byId[v.dungeon]
        lines[#lines + 1] = d and (d.name .. "  " .. UI.levelText(v.dungeon)) or v.dungeon
    end
    for _, q in ipairs(v.quests) do
        local name, lv = UI.questName(q, v.questNames, v.questLevels)
        local mark = UI.levelMark(lv)
        lines[#lines + 1] = tex("quest") .. " " .. name .. (mark ~= "" and ("  " .. mark) or "")
    end
    local tags = UI.tagNames(v.tags)
    if tags ~= "" then lines[#lines + 1] = tags end
    if v.note and v.note ~= "" then lines[#lines + 1] = v.note end
    return lines
end

---------------------------------------------------------------------------
-- The page. GF-002-G: two lines a row (owner: 「一筆單占用兩列」): line 1 the
-- 44 px destination art, the full name, the time, the open seats and the
-- leader; line 2 the tags with their names, the note, and the buttons.
---------------------------------------------------------------------------

local ROW_HEIGHT = 62
UI.ROW_HEIGHT = ROW_HEIGHT
UI.ROW_WIDTH = 1030
UI.LINE1, UI.LINE2 = 13, -14 -- y offsets of the two lines from the row's middle
local panel, scroll, content, summaryLine
local rowWidgets, shownRows = {}, {}
local popup, draft   -- the ticket window and its draft
local wpopup, wdraft -- the worker window and its draft

function UI.pageRows()
    local tickets, matched = A().rowsFor()
    local out = {}
    local mine = A().myWorker()
    if mine then
        out[#out + 1] = { header = tex("worker", 20) .. " 我的職工單" }
        out[#out + 1] = { myWorker = mine }
    end
    if #tickets > 0 then
        out[#out + 1] = { header = tex("adventure", 20) .. " 冒險單" }
        for _, r in ipairs(tickets) do out[#out + 1] = r end
    end
    if #matched > 0 then
        out[#out + 1] = { header = tex("worker", 20) .. " 職工單" }
        for _, r in ipairs(matched) do r.isWorker = true; out[#out + 1] = r end
    end
    -- GF-002-G: groups in the game's group finder for my dungeons (the last search).
    local lfg = UI.lfgRows()
    if #lfg > 0 then
        out[#out + 1] = { header = ns.GameIcons.markup("lfg", 20) .. " 尋求組隊（遊戲內建）" }
        for _, r in ipairs(lfg) do out[#out + 1] = { lfg = r } end
    end
    return out
end

-- The dungeons I care about now: my worker ticket's and my open tickets'.
function UI.myDungeons()
    local set, any = {}, false
    local w = A().myWorker()
    for _, d in ipairs(w and w.dungeons or {}) do set[d] = true; any = true end
    local my = S().selfAuthor()
    for _, v in pairs(A().all()) do
        if v.leader == my and not v.closed and v.dungeon then set[v.dungeon] = true; any = true end
    end
    return any and set or nil
end
function UI.lfgRows()
    local L = ns.NativeLFG
    if not (L and L.available() and L.results) then return {} end
    local set = UI.myDungeons()
    if not set then return {} end
    return L.resultsFor(set)
end

-- The buttons a viewer gets on a ticket (R-6.3 – R-7.3, R-4.7, R-4.9).
function UI.buttonsFor(v)
    local my = S().selfAuthor()
    local out = {}
    if v.leader == my then
        if A().local_().reopen[v.id] then return { "reopen", "dismiss" } end
        if v.closed then return out end
        -- GF-002-H (R-16.8, R-16.15): 定案 first (several slots), then 組隊, then 完成 once 成團.
        if not v.formed then out[#out + 1] = "edit" end -- GF-002-G (成團: the right-click menu still has it)
        if #v.pending > 0 then out[#out + 1] = "approve" end
        if not v.final and #(v.slots or {}) > 1 then out[#out + 1] = "finalize"
        elseif not v.departed then out[#out + 1] = "form" end
        if v.formed then out[#out + 1] = "done" end
        out[#out + 1] = "remove"
        return out
    end
    if v.closed then return out end
    for _, i in ipairs(v.invited) do if i.a == my then return { "accept", "refuse" } end end
    for _, list in ipairs({ v.members, v.waitlist, v.pending }) do
        for _, x in ipairs(list) do
            if x.a == my then
                -- GF-002-H (R-16.5): change my slots while the leader has not finalized one.
                if not v.final and #(v.slots or {}) > 1 then return { "slots", "withdraw" } end
                return { "withdraw" }
            end
        end
    end
    if not v.departed then out[#out + 1] = "apply" end
    return out
end

UI.BUTTON = {
    apply = { icon = "apply", tip = "申請" }, withdraw = { icon = "no", tip = "撤回" },
    accept = { icon = "yes", tip = "接受" }, refuse = { icon = "no", tip = "拒絕" },
    approve = { icon = "yes", tip = "同意" }, form = { icon = "group", tip = "組隊" },
    done = { icon = "yes", tip = "完成" }, remove = { icon = "no", tip = "移除" },
    reopen = { icon = "reopen", tip = "重開" }, dismiss = { icon = "no", tip = "不要" },
    invite = { icon = "invite", tip = "邀請" }, edit = { icon = "edit", tip = "編輯" },
    finalize = { icon = "final", tip = "定案" }, slots = { icon = "today", tip = "時段" }, -- GF-002-H
}
UI.ICON.edit = "Interface\\Icons\\INV_Feather_05"

-- Press a ticket button. Returns a result (tests).
function UI.press(v, button, owner)
    local Adv = A()
    local r
    if button == "apply" and #(v.slots or {}) > 1 and not v.final then
        -- GF-002-H (R-16.5): tick the slots I can make (those matching my worker ticket first).
        local w = Adv.myWorker()
        local pre = w and Adv.overlapSlots(v, w.slots) or {}
        if #pre == 0 then for _, sl in ipairs(v.slots) do pre[#pre + 1] = sl.id end end
        if owner then
            UI.slotChooser(owner, { title = "申請", slots = v.slots, counts = v.slotCounts, selected = pre, multi = true,
                button = tex("apply", 18) .. " 申請", onDone = function(ids) Adv.worker(v.id, "apply", ids); UI.refresh() end })
            return "slots"
        end
        r = Adv.worker(v.id, "apply", pre)
    elseif button == "slots" then
        local mine
        for _, list in ipairs({ v.members, v.waitlist, v.pending }) do
            for _, x in ipairs(list) do if x.a == S().selfAuthor() then mine = x end end
        end
        local pre = (mine and mine.slots) or {}
        if not (mine and mine.slots) then for _, sl in ipairs(v.slots) do pre[#pre + 1] = sl.id end end
        UI.slotChooser(owner, { title = "時段", slots = v.slots, counts = v.slotCounts, selected = pre, multi = true,
            button = tex("yes", 18) .. " 儲存", onDone = function(ids) Adv.worker(v.id, "apply", ids); UI.refresh() end })
        return "slots"
    elseif button == "finalize" then
        -- R-16.7 / R-16.8: each slot with its signups per role; pick one.
        local best, n = nil, -1
        for _, sl in ipairs(v.slots) do
            local c = v.slotCounts[sl.id]
            if c and c.total > n then best, n = sl.id, c.total end
        end
        UI.slotChooser(owner, { title = "定案", slots = v.slots, counts = v.slotCounts, selected = { best }, multi = false,
            button = tex("final", 18) .. " 定案", onDone = function(ids) if ids[1] then Adv.leader(v.id, "finalize", ids[1]) end; UI.refresh() end })
        return "finalize"
    elseif button == "apply" then
        -- R-6.3: show the ticket's time first; ✓ confirms.
        if owner then
            return ns.showMenu(owner, { { text = UI.timeText(v) .. "  " .. tex("yes") .. " 申請", fn = function()
                Adv.worker(v.id, "apply"); UI.refresh()
            end } }) and "confirm" or "none"
        end
        r = Adv.worker(v.id, "apply")
    elseif button == "edit" then UI.openTicket(v); return "edit"
    elseif button == "withdraw" then r = Adv.worker(v.id, "withdraw")
    elseif button == "accept" then r = Adv.worker(v.id, "accept")
    elseif button == "refuse" then r = Adv.worker(v.id, "refuse")
    elseif button == "approve" then r = Adv.leader(v.id, "approve", v.pending[1] and v.pending[1].a)
    elseif button == "form" then r = Adv.form(v.id)
    elseif button == "done" then r = Adv.leader(v.id, "done")
    elseif button == "remove" then r = Adv.leader(v.id, "cancel", "manual")
    elseif button == "reopen" then r = Adv.reopen(v.id)
    elseif button == "dismiss" then Adv.dismissReopen(v.id); r = true
    end
    UI.refresh()
    return r
end

-- R-6.4 / R-16.5: invite a worker; with several slots, for the ones that fit them.
function UI.invite(v, a, w, owner)
    local Adv = A()
    if v.final or #(v.slots or {}) <= 1 then
        local r = Adv.leader(v.id, "invite", a, v.final and { v.final } or nil)
        UI.refresh()
        return r
    end
    local pre = Adv.overlapSlots(v, w and w.slots or {})
    if #pre == 0 then for _, sl in ipairs(v.slots) do pre[#pre + 1] = sl.id end end
    if not owner then local r = Adv.leader(v.id, "invite", a, pre); UI.refresh(); return r end
    UI.slotChooser(owner, { title = "邀請", slots = v.slots, counts = v.slotCounts, selected = pre, multi = true,
        button = tex("invite", 18) .. " 邀請", onDone = function(ids) Adv.leader(v.id, "invite", a, ids); UI.refresh() end })
    return "slots"
end

-- Leader's menu on their own ticket: kick, approve, the admission mode (R-4.5, R-6.6).
function UI.leaderMenu(v)
    local items = {}
    local Adv = A()
    items[#items + 1] = { text = "|T" .. UI.ICON.edit .. ":16|t 編輯", fn = function() UI.openTicket(v) end }
    for _, m in ipairs(v.pending) do
        local mm = Adv.member(m.a)
        items[#items + 1] = { text = tex("yes") .. " " .. (mm and ns.shortName(mm.name) or "?"), fn = function() Adv.leader(v.id, "approve", m.a); UI.refresh() end }
    end
    for _, list in ipairs({ v.members, v.waitlist }) do
        for _, m in ipairs(list) do
            local mm = Adv.member(m.a)
            items[#items + 1] = { text = tex("no") .. " " .. (mm and ns.shortName(mm.name) or "?"), fn = function() Adv.leader(v.id, "kick", m.a); UI.refresh() end }
        end
    end
    items[#items + 1] = { text = tex(v.mode == "c" and "direct" or "consent") .. " " .. (v.mode == "c" and "直接錄取" or "團長同意"),
        fn = function() Adv.leader(v.id, "mode", v.mode == "c" and "a" or "c"); UI.refresh() end }
    return items
end

local function iconButton(parent, size, key, tip, onClick, label)
    local b = ns.OrdersUI.iconButton(parent, size, UI.ICON[key] or key, tip, onClick, label)
    if UI.GAME[key] then ns.GameIcons.set(b.tex, UI.GAME[key]) end
    return b
end
UI.iconButton = iconButton
local function setButtonIcon(b, key)
    if UI.GAME[key] then return ns.GameIcons.set(b.tex, UI.GAME[key]) end
    return Icons.set(b.tex, UI.ICON[key] or key)
end

-- Row columns. Line 1: art, name, time, seats, leader. Line 2: details, buttons.
UI.COL = { dest = 22, name = 76, time = 290, seats = 530, cls = 756, who = 782, whoW = 160,
    detail = 76, detailW = 600, buttons = 690 }
UI.DEST_ICON = 44

local function newRow(i)
    local C = UI.COL
    local row = CreateFrame("Frame", nil, content)
    row:SetSize(UI.ROW_WIDTH, ROW_HEIGHT)
    row.bg = row:CreateTexture(nil, "BACKGROUND"); row.bg:SetAllPoints()
    row.att = row:CreateTexture(nil, "ARTWORK"); row.att:SetSize(18, 18); row.att:SetPoint("LEFT", row, "LEFT", 2, UI.LINE1)
    row.dest = row:CreateTexture(nil, "ARTWORK"); row.dest:SetSize(UI.DEST_ICON, UI.DEST_ICON)
    row.dest:SetPoint("LEFT", row, "LEFT", C.dest + 4, 0)
    local function text(x, w, y, font)
        local fs = row:CreateFontString(nil, "ARTWORK", font or ns.LABEL_FONT)
        fs:SetPoint("LEFT", row, "LEFT", x, y); fs:SetWidth(w); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
        return fs
    end
    row.name = text(C.name, C.time - C.name - 8, UI.LINE1, ns.FIELD_FONT)
    row.time = text(C.time, C.seats - C.time - 8, UI.LINE1)
    row.roles = text(C.seats, C.cls - C.seats - 8, UI.LINE1)
    row.detail = text(C.detail, C.detailW, UI.LINE2)
    -- GF-002-C item 2: one icon per seat, bright when taken, grey when open.
    row.slots = {}
    for k = 1, UI.MAX_SLOTS do
        local s = row:CreateTexture(nil, "ARTWORK")
        s:SetSize(20, 20)
        s:SetPoint("LEFT", row, "LEFT", C.seats + (k - 1) * 22, UI.LINE1)
        s:Hide()
        row.slots[k] = s
    end
    row.cls = row:CreateTexture(nil, "ARTWORK"); row.cls:SetSize(22, 22); row.cls:SetPoint("LEFT", row, "LEFT", C.cls, UI.LINE1)
    row.off = row:CreateTexture(nil, "OVERLAY"); row.off:SetSize(12, 12); row.off:SetPoint("BOTTOMRIGHT", row.cls, "BOTTOMRIGHT", 3, -3)
    row.who = text(C.who, C.whoW, UI.LINE1)
    row.buttons = {}
    UI.ROW_BUTTON_X = C.buttons
    for k = 1, 4 do
        local b = iconButton(row, ns.ROW_ICON, "yes", nil)
        b:SetPoint("LEFT", row, "LEFT", UI.ROW_BUTTON_X, UI.LINE2) -- laid out by their names (fillRow)
        row.buttons[k] = b
    end
    row.head = row:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT); row.head:SetPoint("LEFT", row, "LEFT", 6, 0)
    row:EnableMouse(true)
    if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    row:SetScript("OnMouseUp", function(self, mouse)
        local v = self.view
        if v and v.leader == S().selfAuthor() and not v.closed and mouse == "RightButton" then
            ns.showMenu(self, UI.leaderMenu(v))
        end
    end)
    row:SetScript("OnEnter", function(self)
        local v = self.view
        if not v then return end
        local lines = UI.ticketTooltip(v)
        if #lines == 0 then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        for _, l in ipairs(lines) do GameTooltip:AddLine(l, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rowWidgets[i] = row
    return row
end

local function fillWho(row, a, name)
    local m = a and A().member(a)
    if m and Icons.setClassIcon(row.cls, m.classToken) then row.cls:Show() else row.cls:Hide() end
    row.who:SetText(m and ns.shortName(m.name) or ns.shortName(name or "?"))
    local c = Icons.classColor(m and m.classToken)
    row.who:SetTextColor(c[1], c[2], c[3])
end

-- "死礦、影牙、黑暗淵 +8"
function UI.workerDest(w)
    local names = {}
    for i, d in ipairs(w.dungeons or {}) do if i <= 3 then names[#names + 1] = ns.AdventureData.short(d) end end
    local text = table.concat(names, "、")
    if #(w.dungeons or {}) > 3 then text = text .. " +" .. (#w.dungeons - 3) end
    if text == "" then text = UI.workerQuests(w, 2) end
    return text
end
-- GF-002-H (R-16.29): the chosen quests by name (+N), or 日誌全部 N.
function UI.workerQuests(w, max)
    if w.allQuests then return "日誌全部" .. (w.questCount and (" " .. w.questCount) or "") end
    if #(w.quests or {}) == 0 then return "" end
    return UI.questsText(w.quests, w.questNames, nil, max or 2)
end
function UI.workerDetail(w)
    local parts = {}
    if #(w.dungeons or {}) > 3 then
        local rest = {}
        for i = 4, #w.dungeons do rest[#rest + 1] = ns.AdventureData.short(w.dungeons[i]) end
        parts[#parts + 1] = table.concat(rest, "、")
    end
    local q = UI.workerQuests(w, 2)
    if q ~= "" and #(w.dungeons or {}) > 0 then parts[#parts + 1] = tex("quest", 18) .. " " .. q end
    return table.concat(parts, "   ")
end
-- A worker's slots: the first two, then "+N" (GF-002-H: up to 5).
function UI.slotsText(slots)
    local out = {}
    for i, sl in ipairs(slots or {}) do
        if i <= 2 then out[#out + 1] = UI.slotText(sl) end
    end
    local text = table.concat(out, "  ")
    if #(slots or {}) > 2 then text = text .. "  +" .. (#slots - 2) end
    return text
end
function UI.rolesName(main, alt)
    return tex(main or "d", 20) .. " " .. UI.ROLE_NAME[main or "d"] .. (alt and ("／" .. tex(alt, 18) .. " " .. UI.ROLE_NAME[alt]) or "")
end
function UI.needText(need)
    local parts = {}
    for _, r in ipairs(A().ROLES) do
        local n = need and need[r]
        if n and n > 0 then parts[#parts + 1] = tex(r, 18) .. " " .. UI.ROLE_NAME[r] .. " " .. n end
    end
    return #parts > 0 and ("缺 " .. table.concat(parts, "  ")) or ""
end

local function setButtons(row, list)
    for k, b in ipairs(row.buttons) do
        local spec = list[k]
        if spec then
            setButtonIcon(b, spec.icon); b.tip = spec.tip; b.action = spec.action
            ns.OrdersUI.setLabel(b, spec.tip) -- GF-002-D: the name next to the icon
            -- GF-002-H (R-16.16): 完成 glows inside the destination (nothing automatic).
            b.glowing = spec.glow == true
            if spec.glow then b.sel:Show(); b.shine:Show() else b.sel:Hide(); b.shine:Hide() end
            b:SetScript("OnClick", spec.fn)
            b:Show()
        else b:Hide(); b.action = nil end
    end
    UI.flowButtons(row)
end

local function fillRow(row, data, i)
    row.bg:SetColorTexture(0.2, 0.15, 0.15, i % 2 == 0 and 0.35 or 0.09)
    local parts = { row.att, row.dest, row.name, row.time, row.roles, row.cls, row.who, row.detail }
    row.view, row.mine, row.lfg = nil, nil, nil
    for _, s in ipairs(row.slots) do s:Hide() end
    if data.header then
        for _, w in ipairs(parts) do w:Hide() end
        row.off:Hide()
        for _, b in ipairs(row.buttons) do b:Hide() end
        row.head:SetText(data.header); row.head:Show()
        return
    end
    row.head:Hide()
    for _, w in ipairs(parts) do w:Show() end
    row.name:SetTextColor(1, 0.82, 0)
    row.detail:SetText("")
    if data.attention then setIcon(row.att, "attention") else row.att:Hide() end
    if data.myWorker then
        -- My own worker ticket (GF-002-F): visible, editable, removable.
        local w = data.myWorker
        row.mine = w
        if w.dungeons[1] then ns.GameIcons.set(row.dest, ns.GameIcons.dungeonKey(w.dungeons[1]))
        else ns.GameIcons.set(row.dest, "quest") end
        row.name:SetText(UI.workerDest(w))
        row.time:SetText(UI.slotsText(w.slots))
        row.roles:SetText(UI.rolesName(w.main, w.alt))
        row.detail:SetText(UI.workerDetail(w))
        fillWho(row, S().selfAuthor())
        row.off:Hide()
        setButtons(row, {
            { icon = "edit", tip = "編輯", action = "edit", fn = function() UI.openWorker() end },
            { icon = "no", tip = "移除", action = "unregister", fn = function() A().removeWorker(); UI.refresh() end },
        })
        return
    end
    if data.lfg then
        -- A group in the game's group finder (the last search) for one of my dungeons.
        local r = data.lfg
        row.lfg = r
        ns.GameIcons.set(row.dest, ns.GameIcons.dungeonKey(r.dungeon))
        row.name:SetText(UI.destText({ dungeon = r.dungeon, quests = {} }))
        row.time:SetText(tex("now") .. " 現在  " .. tex("any", 18) .. " " .. (r.members or 0))
        row.roles:SetText(UI.needText(r.need))
        row.detail:SetText(r.comment ~= "" and ("|cffd0d0d0" .. r.comment .. "|r") or r.name)
        fillWho(row, nil, r.leader)
        row.off:Hide()
        local list = {}
        if ns.GuildAdmin and ns.GuildAdmin.canWhisper() and r.leader ~= "" then
            list[#list + 1] = { icon = "invite", tip = "密語", action = "whisper", fn = function() ns.GuildAdmin.whisper({ name = r.leader }) end }
        end
        if ns.NativeLFG.canApply() then
            local w = A().myWorker()
            list[#list + 1] = { icon = "apply", tip = "申請", action = "lfgApply", fn = function()
                local _, token = ns.call(UnitClass, "player")
                local main, alt = A().defaultRoles(token)
                ns.NativeLFG.apply(r, w and w.main or main, w and w.alt or alt)
            end }
        end
        setButtons(row, list)
        return
    end
    if data.isWorker then
        -- A worker matching one of my tickets: invite (R-6.4).
        local w, v = data.w, data.ticket
        UI.setDest(row.dest, v)
        row.name:SetText(UI.destText(v))
        row.time:SetText(UI.slotsText(w.slots))
        row.roles:SetText(UI.rolesName(w.main, w.alt))
        fillWho(row, data.worker)
        if w.online then setIcon(row.off, "online") else setIcon(row.off, "offline") end
        setButtons(row, { { icon = "invite", tip = "邀請", action = "invite",
            fn = function(self) UI.invite(v, data.worker, w, self) end } })
        return
    end
    local v = data.view
    row.view = v
    UI.setDest(row.dest, v)
    row.name:SetText(UI.destText(v))
    if v.closed then row.name:SetTextColor(0.5, 0.5, 0.5) end
    row.time:SetText(UI.timeText(v))
    if v.closed then
        -- GF-002-H (R-16.15 - R-16.17): 成行 / 未成行 (成團未成行) / 結束 / 取消.
        row.roles:SetText(tex(v.state == "done" and "yes" or "no") .. " " .. (UI.STATE_NAME[v.state] or "取消"))
    else
        row.roles:SetText("")
        for k, sl in ipairs(UI.slotList(v)) do
            local s = row.slots[k]
            if not s then break end
            ns.GameIcons.set(s, UI.GAME[sl.role])
            if s.SetDesaturated then s:SetDesaturated(not sl.filled) end
            s:SetAlpha(sl.filled and 1 or 0.45)
            s.filled = sl.filled
        end
    end
    local detail = UI.detailText(v)
    if v.formed then detail = tex("group", 18) .. " 成團" .. (detail ~= "" and ("   " .. detail) or "") end
    row.detail:SetText(detail)
    fillWho(row, v.leader)
    -- R-4.7: the leader is offline (委託者離線中).
    if v.leaderOffline then setIcon(row.off, "offline") else row.off:Hide() end
    local list = {}
    for _, name in ipairs(UI.buttonsFor(v)) do
        local spec = UI.BUTTON[name]
        list[#list + 1] = { icon = spec.icon, tip = spec.tip, action = name, fn = function(self) UI.press(v, name, self) end,
            glow = name == "done" and A().inDestination(v) }
    end
    setButtons(row, list)
end

-- GF-002-E: the row buttons follow each other by their measured names (line 2).
function UI.flowButtons(row)
    local shown = {}
    for _, b in ipairs(row.buttons) do if b:IsShown() then shown[#shown + 1] = b end end
    ns.OrdersUI.flow(row, shown, UI.ROW_BUTTON_X, UI.LINE2, 10, "LEFT")
end

function UI.layoutRows()
    if not scroll then return end
    local offset = ns.num((scroll:GetVerticalScroll())) or 0
    local h = ns.num((scroll:GetHeight())) or 0
    if h <= 0 then h = 420 end
    local count = math.ceil(h / ROW_HEIGHT) + 1
    local first = math.max(1, math.floor(offset / ROW_HEIGHT) + 1)
    for k = 1, math.max(count, #rowWidgets) do
        local i = first + k - 1
        local data = k <= count and shownRows[i] or nil
        local row = rowWidgets[k] or (data and newRow(k)) or nil
        if row then
            if data then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
                fillRow(row, data, i)
                row:Show()
            else row:Hide(); row.view = nil; row.mine = nil; row.lfg = nil end
        end
    end
end
function UI.rowFrames() return rowWidgets end
function UI.shownRows() return shownRows end

-- R-11.3 / GF-002-C item 9: dungeon art, the number of people, the missing roles.
function UI.summaryText()
    local s = A().summary()
    if not s then return "" end
    local lack = {}
    for _, r in ipairs(A().ROLES) do if s.lack[r] then lack[#lack + 1] = tex(r, 20) end end
    return ns.GameIcons.markup(ns.GameIcons.dungeonKey(s.dungeon), 24) .. " " .. ns.AdventureData.short(s.dungeon)
        .. "  " .. tex("any", 20) .. s.count .. (#lack > 0 and ("   " .. table.concat(lack, " ")) or "")
end

function UI.refresh()
    UI.updateBadge()
    if wpopup and wpopup:IsShown() and wdraft then UI.drawWorkerTitle() end
    if UI.calendar and UI.calendar() and UI.calendar():IsShown() then UI.drawCalendar() end
    if not panel then return end
    shownRows = UI.pageRows()
    content:SetHeight(math.max(1, #shownRows * ROW_HEIGHT))
    UI.layoutRows()
    summaryLine:SetText(UI.summaryText())
    UI.emptyLine:SetText(#shownRows == 0 and "沒有冒險單" or "") -- GF-002-D
    if #A().pendingInvites() > 0 then UI.nextInvite:Show() else UI.nextInvite:Hide() end
    if ns.NativeLFG and ns.NativeLFG.canSearch() then UI.lfgButton:Show() else UI.lfgButton:Hide() end
end

local function build(p)
    -- GF-002-D: icon + name; GF-002-F: 16 px text, 20 px icons in the buttons.
    UI.newButton = ns.OrdersUI.textButton(p, tex("adventure", 20) .. " ＋冒險單")
    UI.newButton:SetPoint("TOPLEFT", p, "TOPLEFT", 24, -40)
    UI.newButton:SetScript("OnClick", function() UI.openTicket() end)
    UI.workerButton = ns.OrdersUI.textButton(p, tex("worker", 20) .. " ＋職工單")
    UI.workerButton:SetPoint("LEFT", UI.newButton, "RIGHT", 12, 0)
    UI.workerButton:SetScript("OnClick", function() UI.openWorker() end)
    -- GF-002-G: search the game's group finder (a click: the game allows it then).
    UI.lfgButton = ns.OrdersUI.textButton(p, ns.GameIcons.markup("lfg", 20) .. " 搜尋尋求組隊", function()
        ns.NativeLFG.search()
    end)
    -- GF-002-H (R-16.12): the adventure calendar.
    UI.calendarButton = ns.OrdersUI.textButton(p, tex("calendar", 20) .. " 行事曆", function() UI.openCalendar() end)
    UI.calendarButton:SetPoint("LEFT", UI.workerButton, "RIGHT", 12, 0)
    UI.lfgButton:SetPoint("LEFT", UI.calendarButton, "RIGHT", 12, 0)
    summaryLine = ns.freeText(p:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
    summaryLine:SetPoint("LEFT", UI.lfgButton, "RIGHT", 24, 0)
    scroll = ns.createFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -84)
    scroll:SetPoint("BOTTOMRIGHT", -40, 52)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(UI.ROW_WIDTH, 1)
    scroll:SetScrollChild(content)
    scroll:HookScript("OnVerticalScroll", function() UI.layoutRows() end)
    UI.nextInvite = iconButton(p, ns.ICON, "invite", "邀請下一位", function() A().inviteNext(); UI.refresh() end, "邀請下一位")
    UI.nextInvite:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -310, 10)
    UI.nextInvite:Hide() -- only while names wait for a click (R-7.2 fallback)
    UI.emptyLine = p:CreateFontString(nil, "ARTWORK", ns.DISABLED_FONT)
    UI.emptyLine:SetPoint("TOP", p, "TOP", 0, -200)
    ns.Diag.smallButton(p, "BOTTOMRIGHT", -24, 10)
    panel = p
end

ns.Framework.register({
    id = "adventure",
    title = "冒險",
    order = 14,
    available = function() return ns.guildState() == "target" end,
    create = build,
    show = function() A().markSeen(); UI.refresh() end,
})

---------------------------------------------------------------------------
-- Times (R-4.2). GF-002-G: one 開始 control: 現在, any quarter today or
-- tomorrow (past midnight), or 其他日期. GF-002-H: the same picker sets each
-- slot's 長度 (不填 or 1-5 hours, R-16.2) and removes a slot.
---------------------------------------------------------------------------

-- Times every 15 minutes from now, on the player's clock (GF-002-D).
function UI.quarterTimes(from, count, step)
    step = step or 900
    local skew = UI.skew()
    local out = {}
    local t = math.ceil((from - skew) / step) * step + skew
    for i = 0, count - 1 do out[#out + 1] = t + i * step end
    return out
end
UI.DURATIONS = { 1, 2, 3, 4, 5 }
UI.MINUTES = { 0, 15, 30, 45 }
function UI.nextQuarter() return UI.quarterTimes(S().serverNow() + 1, 1)[1] end

-- The start picker: 現在, the hours of today and tomorrow (or of one other
-- day), the quarter, and 其他日期…. A menu: ESC or a click outside closes it.
UI.PICKER_NAME = "GreenFangToolkit_TimePicker"
local picker
function UI.timePicker(owner, opts)
    -- opts = { start = t or nil (現在), dayOff = n (other day) or nil, allowOther, onPick(t or nil), onOther(),
    --   GF-002-H: title, dur = hours or nil, onDur(hours or nil) (the 長度 row), onRemove() (the 移除 button) }
    if ns.Framework.closeMenu then ns.Framework.closeMenu() end
    local g = UI.grid and UI.grid()
    if g and g:IsShown() then g:Hide() end
    local O = ns.OrdersUI
    if not picker then
        picker = CreateFrame("Frame", UI.PICKER_NAME, UIParent)
        picker:SetFrameStrata("TOOLTIP")
        if picker.SetFrameLevel then picker:SetFrameLevel(60) end
        ns.makeOpaque(picker, 0)
        picker:EnableMouse(true)
        ns.escRegister(picker, ns.ESC_LEVEL.menu)
        picker.title = ns.freeText(picker:CreateFontString(nil, "ARTWORK", ns.TITLE_FONT))
        picker.title:SetPoint("TOPLEFT", picker, "TOPLEFT", 14, -10)
        picker.title:SetText("開始")
        picker.now = O.textButton(picker, tex("now", 18) .. " 現在", function() picker.choose(nil) end, 96)
        picker.now:SetPoint("TOPLEFT", picker, "TOPLEFT", 70, -40)
        picker.dayLabels, picker.hours = {}, {}
        for i = 1, 3 do
            picker.dayLabels[i] = ns.freeText(picker:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT))
        end
        for d = 1, 3 do
            picker.hours[d] = {}
            for h = 0, 23 do
                local b = O.textButton(picker, string.format("%02d", h), nil, nil, 40)
                b.hour, b.dayIndex = h, d
                picker.hours[d][h] = b
            end
        end
        picker.minLabel = ns.freeText(picker:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT))
        picker.minLabel:SetText("分")
        picker.minutes = {}
        for i, m in ipairs(UI.MINUTES) do
            local b = O.textButton(picker, string.format(":%02d", m), function() picker.setMinute(m) end, nil, 52)
            b.minute = m
            picker.minutes[i] = b
        end
        -- GF-002-H (R-16.2): the length is optional: 不填 or 1-5 hours.
        picker.lenLabel = ns.freeText(picker:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT))
        picker.lenLabel:SetText("長度")
        picker.lens = {}
        for i, h in ipairs({ false, 1, 2, 3, 4, 5 }) do
            local b = O.textButton(picker, h and (h .. " 小時") or "不填", function() picker.setLen(h or nil) end, nil, h and 76 or 64)
            b.hours = h or nil
            picker.lens[i] = b
        end
        picker.remove = O.textButton(picker, tex("no", 18) .. " 移除", function()
            picker:Hide(); if picker.opts.onRemove then picker.opts.onRemove() end
        end)
        picker.other = O.textButton(picker, "其他日期", function() picker:Hide(); if picker.opts.onOther then picker.opts.onOther() end end)
        picker.done = O.textButton(picker, tex("yes", 18) .. " 完成", function() picker:Hide() end, 96)
        picker:Hide()
        function picker.apply()
            local o = picker.opts
            local base = UI.dayStart(picker.sel.day)
            local t = base + picker.sel.hour * 3600 + picker.sel.minute * 60
            local first = UI.nextQuarter()
            if t < first then t = first end
            picker.sel.start = t
            o.onPick(t)
            picker.mark()
        end
        function picker.choose(t)
            picker.sel.start = t
            picker.opts.onPick(t)
            if picker.opts.onDur then picker.mark() else picker:Hide() end
        end
        function picker.setLen(h)
            picker.sel.dur = h
            if picker.opts.onDur then picker.opts.onDur(h) end
            picker.mark()
        end
        function picker.setMinute(m)
            if not picker.sel.hour then return end
            picker.sel.minute = m
            picker.apply()
        end
        function picker.mark()
            local sel = picker.sel
            for d = 1, 3 do
                for h = 0, 23 do
                    local b = picker.hours[d][h]
                    local on = sel.start ~= nil and b.day == sel.day and h == sel.hour
                    b.selected = on
                    if b.LockHighlight then if on then b:LockHighlight() else b:UnlockHighlight() end end
                end
            end
            for _, b in ipairs(picker.minutes) do
                local on = sel.start ~= nil and b.minute == sel.minute
                b.selected = on
                if b.LockHighlight then if on then b:LockHighlight() else b:UnlockHighlight() end end
            end
            picker.now.selected = sel.start == nil
            for _, b in ipairs(picker.lens) do
                local on = b.hours == sel.dur
                b.selected = on
                if b.LockHighlight then if on then b:LockHighlight() else b:UnlockHighlight() end end
            end
        end
    end
    picker.opts = opts
    picker.title:SetText(opts.title or "開始")
    -- Which days: today and tomorrow, or the one other day.
    local days
    if opts.dayOff and opts.dayOff >= 2 then days = { opts.dayOff } else days = { 0, 1 } end
    local nowLocal = date("*t", S().serverNow() - UI.skew())
    local y = -40
    if opts.allowNow ~= false then picker.now:Show(); y = y - 40 else picker.now:Hide() end
    for i = 1, 3 do picker.dayLabels[i]:Hide(); for h = 0, 23 do picker.hours[i][h]:Hide() end end
    for i, dayOff in ipairs(days) do
        local label = picker.dayLabels[i]
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", picker, "TOPLEFT", 14, y - 6)
        label:SetText(dayOff == 0 and "今天" or dayOff == 1 and "明天" or UI.day(UI.dayStart(dayOff) + 43200))
        label:Show()
        local k = 0
        local labelW = dayOff >= 2 and ns.labelWidth(label:GetText()) + 10 or 56
        for h = 0, 23 do
            local b = picker.hours[i][h]
            -- today: only hours that still have a quarter ahead
            local okHour = not (dayOff == 0 and h < nowLocal.hour)
            if okHour then
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", picker, "TOPLEFT", 14 + labelW + (k % 12) * 44, y - math.floor(k / 12) * 34)
                b.day = dayOff
                b:SetScript("OnClick", function(self)
                    picker.sel.day, picker.sel.hour, picker.sel.minute = self.day, self.hour, 0 -- an hour starts at :00
                    picker.apply()
                end)
                b:Show()
                k = k + 1
            end
        end
        y = y - math.max(1, math.ceil(k / 12)) * 34 - 6
    end
    picker.minLabel:ClearAllPoints()
    picker.minLabel:SetPoint("TOPLEFT", picker, "TOPLEFT", 14, y - 6)
    for i, b in ipairs(picker.minutes) do
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", picker, "TOPLEFT", 70 + (i - 1) * 58, y)
    end
    y = y - 40
    if opts.onDur then
        picker.lenLabel:ClearAllPoints()
        picker.lenLabel:SetPoint("TOPLEFT", picker, "TOPLEFT", 14, y - 6)
        picker.lenLabel:Show()
        local x = 70
        for _, b in ipairs(picker.lens) do
            b:ClearAllPoints(); b:SetPoint("TOPLEFT", picker, "TOPLEFT", x, y); b:Show()
            x = x + b.gfWidth + 6
        end
        y = y - 40
    else
        picker.lenLabel:Hide()
        for _, b in ipairs(picker.lens) do b:Hide() end
    end
    picker.other:ClearAllPoints()
    picker.other:SetPoint("TOPLEFT", picker, "TOPLEFT", 14, y)
    if opts.allowOther ~= false then picker.other:Show() else picker.other:Hide() end
    picker.remove:ClearAllPoints()
    picker.remove:SetPoint("TOPLEFT", picker, "TOPLEFT", 14 + (opts.allowOther ~= false and (picker.other.gfWidth + 12) or 0), y)
    if opts.onRemove then picker.remove:Show() else picker.remove:Hide() end
    picker.done:ClearAllPoints()
    picker.done:SetPoint("TOPRIGHT", picker, "TOPRIGHT", -14, y)
    y = y - 40
    picker:SetSize(14 + 56 + 12 * 44 + 14, -y + 6)
    -- The current choice.
    local sel = { start = opts.start, minute = 0, dur = opts.dur }
    if opts.start then
        local d = date("*t", opts.start - UI.skew())
        sel.day, sel.hour, sel.minute = UI.dayOffset(opts.start), d.hour, d.min - d.min % 15
    end
    picker.sel = sel
    picker.mark()
    picker:ClearAllPoints()
    picker:SetPoint("TOPLEFT", owner or UIParent, "BOTTOMLEFT", 0, -4)
    if picker.SetClampedToScreen then picker:SetClampedToScreen(true) end
    picker:Show()
    return picker
end
function UI.picker() return picker end

UI.TIME_NAME = { n = "現在", t = "今天", f = "之後" }
UI.TIME_KEY = { n = "now", t = "today", f = "future" }

---------------------------------------------------------------------------
-- New / edit adventure ticket (R-4.1 – R-4.5). GF-002-G: no full-width
-- buttons (owner: 「我不喜歡一個很長條的按鈕」), one 開始 control, editing.
---------------------------------------------------------------------------

UI.TICKET_NAME = "GreenFangToolkit_AdventurePopup"

function UI.newDraft()
    local _, token = ns.call(UnitClass, "player")
    local main = A().defaultRoles(token)
    -- GF-002-H: slots = { { id, now, start, dur (hours or nil = no length), dayOff } }, 1-5 (R-16.1).
    return { slots = { { now = true } }, roles = { t = 1, h = 1, d = 3 }, size = 5, tags = 0, note = "", mode = "a",
        leaderRole = main, quests = {} }
end

---------------------------------------------------------------------------
-- GF-002-H: slots in a draft (both windows). A draft slot is { id, now, start,
-- dur = hours or nil, dayOff }; the model's slot is { id, now, s, d = seconds }.
---------------------------------------------------------------------------

function UI.draftSlot(sl)
    local d = { id = sl.id, now = sl.now and true or false }
    local len = sl.d or (sl.e and sl.s and (sl.e - sl.s)) or nil
    if len and len > 0 then d.dur = math.max(1, math.min(5, math.floor(len / 3600 + 0.5))) end
    if not sl.now then
        d.start = sl.s
        local off = UI.dayOffset(sl.s)
        d.dayOff = off >= 2 and off or nil
    end
    return d
end
function UI.slotData(ds)
    return { id = ds.id, now = ds.now or nil, s = (not ds.now) and ds.start or nil, d = ds.dur and ds.dur * 3600 or nil }
end
-- For the chip text: a 現在 slot counts from now.
function UI.draftSlotView(ds)
    return { now = ds.now, s = ds.now and S().serverNow() or ds.start, d = ds.dur and ds.dur * 3600 or nil }
end
function UI.hasNow(d)
    for _, sl in ipairs(d and d.slots or {}) do if sl.now then return true end end
    return false
end

-- One slot: the 開始 picker with the 長度 row and 移除 (R-16.3).
function UI.editSlot(owner, list, i, redraw)
    local sl = list[i]
    if not sl then return nil end
    return UI.timePicker(owner, { title = "時段 " .. i, start = (not sl.now) and sl.start or nil, dayOff = sl.dayOff, dur = sl.dur,
        onPick = function(t)
            if t then sl.now, sl.start = false, t; if UI.dayOffset(t) <= 1 then sl.dayOff = nil end
            else sl.now, sl.start, sl.dayOff = true, nil, nil end
            redraw()
        end,
        onDur = function(h) sl.dur = h; redraw() end,
        onRemove = #list > 1 and function() table.remove(list, i); redraw() end or nil,
        onOther = function() UI.pickDay(owner, sl, redraw) end })
end

-- ＋時段: the next one a day after the last (tomorrow 20:00 after 現在), then its picker.
function UI.addSlot(list, redraw, owner)
    if #list >= A().MAX_SLOTS then return nil end
    local last = list[#list]
    local ns2 = {}
    if last and not last.now and last.start then
        local nextDay = last.start + 86400
        ns2.start = (UI.dayOffset(nextDay) <= A().FUTURE_DAYS) and nextDay or (last.start + 3600)
    else
        ns2.start = UI.dayStart(1) + 20 * 3600
    end
    ns2.now = false
    ns2.dur = last and last.dur or nil
    local off = UI.dayOffset(ns2.start)
    ns2.dayOff = off >= 2 and off or nil
    list[#list + 1] = ns2
    redraw()
    if owner then UI.editSlot(owner, list, #list, redraw) end
    return #list
end

-- The chips of a slot list (one button per slot, then ＋時段) from x, y; returns the lines used.
local function setTextWidth(b, text)
    b:SetText(text)
    b.gfWidth = ns.labelWidth(text) + 28
    b:SetSize(b.gfWidth, ns.BUTTON_H)
end
UI.setTextWidth = setTextWidth
function UI.drawSlotChips(f, list, chips, add, x, y, onChip)
    local shown = {}
    for i, ds in ipairs(list) do
        local c = chips[i]
        if not c then
            c = ns.OrdersUI.textButton(f, "", nil)
            chips[i] = c
        end
        c.slotIndex = i
        c:SetScript("OnClick", function(self) onChip(self, self.slotIndex) end)
        setTextWidth(c, UI.slotText(UI.draftSlotView(ds), 18))
        c:Show()
        shown[#shown + 1] = c
    end
    for i = #list + 1, #chips do chips[i]:Hide() end
    if #list < A().MAX_SLOTS then add:Show(); shown[#shown + 1] = add else add:Hide() end
    return UI.wrapFlow(f, shown, x, y, f.width - 24, UI.CHIP_LINE, 12)
end

-- A draft from my ticket's view (editing).
function UI.draftFrom(v)
    local d = UI.newDraft()
    d.editId = v.id
    d.dungeon = v.dungeon
    d.quests = {}
    for _, q in ipairs(v.quests) do d.quests[#d.quests + 1] = tonumber(q) or q end
    if v.roles then d.roles = { t = v.roles.t, h = v.roles.h, d = v.roles.d } end
    d.size = v.size or 5
    d.tags, d.note, d.mode = v.tags or 0, v.note or "", v.mode or "a"
    d.leaderRole = v.leaderRole or d.leaderRole
    d.slots = {}
    for _, sl in ipairs(v.slots or {}) do d.slots[#d.slots + 1] = UI.draftSlot(sl) end
    if #d.slots == 0 then d.slots = { { now = true } } end
    return d
end

-- The draft in the shape Adventure.open / editTicket take.
function UI.ticketData(d)
    local o = {}
    for k, v in pairs(d) do o[k] = v end
    o.slots = {}
    for _, ds in ipairs(d.slots or {}) do o.slots[#o.slots + 1] = UI.slotData(ds) end
    return o
end

UI.SUBMIT_ERROR = { ["no-destination"] = "請先選目的地", ["bad-time"] = "時間不對", ["too-far"] = "日期太遠",
    ["too-many"] = "冒險單太多了", closed = "這張單已經結束" }
function UI.submitTicket(d)
    d = d or draft
    if not d then return nil end
    local o = UI.ticketData(d)
    local id, why
    if d.editId then
        local ok
        ok, why = A().editTicket(d.editId, o)
        id = ok and d.editId or nil
    else
        id, why = A().open(o)
    end
    local lfgNote
    -- GF-002-G: also list it in the game's group finder (this click allows it).
    if id and UI.hasNow(d) and d.dungeon and d.lfg and ns.NativeLFG and ns.NativeLFG.canList() then
        local ok = ns.NativeLFG.list(d.dungeon, d.note)
        lfgNote = ok and "lfg-ok" or "lfg-failed"
    end
    if id and popup then popup:Hide() end
    if not id and popup then popup.result:SetText(tex("no") .. " " .. (UI.SUBMIT_ERROR[why] or "沒有開成")) end
    UI.refresh()
    return id, why, lfgNote
end

UI.TICKET_FIELDS = { "目的地", "時段", "人數", "錄取", "標籤", "備註" }

-- 目的地: the chosen art + name + levels, then a small 「選擇」/「更換」 button.
local function drawDest(f)
    local d = draft
    if d.dungeon then
        ns.GameIcons.set(f.destIcon, ns.GameIcons.dungeonKey(d.dungeon))
        f.destIcon:Show()
        local info = ns.AdventureData.byId[d.dungeon]
        f.destName:SetText((info and info.name or d.dungeon) .. "  |cffb0b0b0" .. UI.levelText(d.dungeon) .. "|r")
    elseif #d.quests > 0 then
        ns.GameIcons.set(f.destIcon, "quest")
        f.destIcon:Show()
        f.destName:SetText(UI.questsText(d.quests, nil, nil, 1)) -- GF-002-H: the first quest, +N
    else
        f.destIcon:Hide()
        f.destName:SetText("")
    end
    -- GF-002-H (R-16.26): step one is two big buttons, 地城 and 任務; once chosen,
    -- the art + name, then a small 地城 and 任務 to change it.
    local chosen = d.dungeon or #d.quests > 0
    local hasLog = A().questLog() ~= nil
    f.pickQuest.disabled = not hasLog
    f.pickQuest.tex:SetAlpha(hasLog and 1 or 0.4)
    if f.pickQuest.label then f.pickQuest.label:SetAlpha(hasLog and 1 or 0.4) end
    f.pickQuest.tip = not hasLog and "任務日誌讀不到" or nil
    if chosen then
        f.pickDungeon:Hide(); f.pickQuest:Hide()
        f.dest:Show(); f.destQuest:Show()
        f.dest:ClearAllPoints(); f.dest:SetPoint("LEFT", f.destName, "RIGHT", 16, 0)
        f.destQuest:ClearAllPoints(); f.destQuest:SetPoint("LEFT", f.dest, "RIGHT", 10, 0)
        if hasLog then f.destQuest:Show() else f.destQuest:Hide() end
    else
        f.dest:Hide(); f.destQuest:Hide()
        f.pickDungeon:Show(); f.pickQuest:Show()
        ns.OrdersUI.flow(f, { f.pickDungeon, f.pickQuest }, f.controlX, f.rowY[1] + 6, 40)
    end
end

-- The rows under 時段 follow its chips (GF-002-H: up to 5 slots wrap over two lines).
local function layoutTicket(f, lines)
    local O = ns.OrdersUI
    local FX, X = O.FIELD_X, f.controlX
    local y = f.rowY[2] - lines * UI.CHIP_LINE - 10
    local rows = {}
    for i = 3, 7 do rows[i] = y; y = y - O.ROW_STEP end
    f.rowY[3], f.rowY[4], f.rowY[5], f.rowY[6], f.rowY[7] = rows[3], rows[4], rows[5], rows[6], rows[7]
    local function label(name, yy)
        local fs = f.fieldStrings[name]
        fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", f, "TOPLEFT", FX, yy - 8)
    end
    label("人數", rows[3])
    for _, g in pairs(f.roleGroups) do
        g.icon:ClearAllPoints(); g.icon:SetPoint("TOPLEFT", f, "TOPLEFT", g.x, rows[3])
        g.text:ClearAllPoints(); g.text:SetPoint("TOPLEFT", f, "TOPLEFT", g.x + ns.ICON + 4, rows[3] - 8)
        g.plus:ClearAllPoints(); g.plus:SetPoint("TOPLEFT", f, "TOPLEFT", g.bx, rows[3] + 1)
        g.minus:ClearAllPoints(); g.minus:SetPoint("TOPLEFT", f, "TOPLEFT", g.bx + 38, rows[3] + 1)
    end
    label("錄取", rows[4]); O.flow(f, { f.direct, f.consent }, X, rows[4], 32)
    label("標籤", rows[5]); O.flow(f, f.tagList, X, rows[5], 18)
    label("備註", rows[6]); f.note:ClearAllPoints(); f.note:SetPoint("TOPLEFT", f, "TOPLEFT", X + 6, rows[6])
    f.lfgCheck:ClearAllPoints(); f.lfgCheck:SetPoint("TOPLEFT", f, "TOPLEFT", FX, rows[7])
    f:SetHeight(-rows[7] + 110)
end

local function drawTicket()
    if not (popup and draft) then return end
    local f = popup
    if f.TitleText then f.TitleText:SetText(draft.editId and "編輯冒險單" or "冒險單") end
    f.go:SetText(tex("yes", 20) .. (draft.editId and " 儲存" or " 開單"))
    drawDest(f)
    -- 時段: one chip per slot (click: its picker), then ＋時段 (R-16.3).
    local lines = UI.drawSlotChips(f, draft.slots, f.slotChips, f.addSlot, f.controlX, f.rowY[2], function(self, i) UI.pickStart(self, i) end)
    f.startButton = f.slotChips[1]
    layoutTicket(f, math.max(1, lines))
    -- 人數: each role with its own ＋ － (dungeon), or one number (quests).
    for _, r in ipairs({ "t", "h", "d", "any" }) do
        local g = f.roleGroups[r]
        local show = (r == "any") == (draft.dungeon == nil)
        for _, w in ipairs({ g.icon, g.text, g.plus, g.minus }) do if show then w:Show() else w:Hide() end end
        g.text:SetText(UI.ROLE_NAME[r] .. " " .. (r == "any" and draft.size or draft.roles[r]))
    end
    ns.OrdersUI.setSelected(f.direct, draft.mode ~= "c")
    ns.OrdersUI.setSelected(f.consent, draft.mode == "c")
    for k, b in pairs(f.tagButtons) do ns.OrdersUI.setSelected(b, math.floor(draft.tags / A().TAGS[k]) % 2 == 1) end
    -- 尋求組隊: only for 現在 with a dungeon, when the game lets us list.
    local L = ns.NativeLFG
    local canLfg = L and L.canList() and UI.hasNow(draft) and draft.dungeon ~= nil and not draft.editId
    if canLfg then f.lfgCheck:Show(); f.lfgCheck.label:Show(); f.lfgCheck.set(draft.lfg == true)
    else f.lfgCheck:Hide(); f.lfgCheck.label:Hide() end
end
UI.drawTicket = drawTicket

function UI.changeCount(role, n)
    if role == "any" then draft.size = math.max(2, math.min(5, draft.size + n))
    else draft.roles[role] = math.max(0, math.min(5, draft.roles[role] + n)) end
    drawTicket()
end

-- opts: a view to edit (my own open ticket), or nil for a new one.
function UI.openTicket(v)
    draft = v and UI.draftFrom(v) or UI.newDraft()
    if not popup then
        local f = ns.popupWindow(UI.TICKET_NAME, 820, 470)
        f:SetPoint("CENTER", 0, 40)
        f:EnableMouse(true)
        ns.exclusivePopup(f)
        local O = ns.OrdersUI
        local FX = O.FIELD_X
        local X = O.controlX(UI.TICKET_FIELDS)
        f.controlX, f.width = X, 820
        f.rowY = {}
        for i = 1, 7 do f.rowY[i] = -48 - (i - 1) * O.ROW_STEP end
        local y = f.rowY
        local field = O.fieldLabel
        field(f, "目的地", FX, y[1] - 8)
        f.destIcon = f:CreateTexture(nil, "ARTWORK"); f.destIcon:SetSize(ns.ICON, ns.ICON)
        f.destIcon:SetPoint("TOPLEFT", f, "TOPLEFT", X, y[1] + 1)
        f.destName = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
        f.destName:SetPoint("LEFT", f.destIcon, "RIGHT", 8, 0)
        f.pickDungeon = iconButton(f, 40, "dungeon", nil, function(self) UI.pickDestination(self) end, "地城")
        f.pickQuest = iconButton(f, 40, "quest", nil, function(self) if not self.disabled then UI.pickQuests(self) end end, "任務")
        f.dest = O.textButton(f, tex("dungeon", 18) .. " 地城", function(self) UI.pickDestination(self) end)
        f.destQuest = O.textButton(f, tex("quest", 18) .. " 任務", function(self) UI.pickQuests(self) end)
        -- 時段 [現在] [明天 20:00～22:00] [＋時段] (GF-002-H, R-16.1 - R-16.3)
        field(f, "時段", FX, y[2] - 8)
        f.slotChips = {}
        f.addSlot = O.textButton(f, "＋時段", function(self) UI.addSlot(draft.slots, drawTicket, self) end)
        -- 人數: 坦 1 ＋ －  補 1 ＋ －  輸出 3 ＋ － (one 人數 for quests).
        field(f, "人數", FX, y[3] - 8)
        f.roleGroups = {}
        local x = X
        local function group(r, gx, name)
            local g = { x = gx }
            g.icon = f:CreateTexture(nil, "ARTWORK"); g.icon:SetSize(ns.ICON, ns.ICON)
            ns.GameIcons.set(g.icon, UI.GAME[r])
            g.text = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
            g.bx = gx + ns.ICON + 4 + ns.labelWidth(name .. " 5") + 2
            g.plus = O.textButton(f, "＋", function() UI.changeCount(r, 1) end, nil, 34); g.plus.fieldNamed = UI.ROLE_NAME[r]
            g.minus = O.textButton(f, "－", function() UI.changeCount(r, -1) end, nil, 34); g.minus.fieldNamed = UI.ROLE_NAME[r]
            f.roleGroups[r] = g
            return g.bx + 38 + 34 + 24
        end
        for _, r in ipairs({ "t", "h", "d" }) do x = group(r, x, "輸出") end
        group("any", X, "隊員")
        field(f, "錄取", FX, y[4] - 8)
        f.direct = iconButton(f, ns.ICON, "direct", "直接錄取", function() draft.mode = "a"; drawTicket() end, "直接錄取")
        f.consent = iconButton(f, ns.ICON, "consent", "團長同意", function() draft.mode = "c"; drawTicket() end, "團長同意")
        f.modeButton = f.direct
        field(f, "標籤", FX, y[5] - 8)
        f.tagButtons, f.tagList = {}, {}
        for _, k in ipairs(UI.TAG_KEYS) do
            local b = iconButton(f, ns.ICON, "tag_" .. k, UI.TAG_NAME[k], function()
                local bit = A().TAGS[k]
                if math.floor(draft.tags / bit) % 2 == 1 then draft.tags = draft.tags - bit else draft.tags = draft.tags + bit end
                drawTicket()
            end, UI.TAG_NAME[k])
            f.tagButtons[k] = b
            f.tagList[#f.tagList + 1] = b
        end
        field(f, "備註", FX, y[6] - 8)
        f.note = ns.createFrame("EditBox", nil, f, "InputBoxTemplate"); f.note:SetSize(480, 30)
        if f.note.SetFontObject then f.note:SetFontObject(ns.LABEL_FONT) end
        f.note:SetAutoFocus(false)
        if f.note.SetMaxLetters then f.note:SetMaxLetters(A().NOTE_MAX) end
        f.note:SetScript("OnTextChanged", function(self) if draft then draft.note = A().cleanNote(self:GetText()) end end)
        f.note:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        -- GF-002-G: also list in the game's group finder (現在 + a dungeon only).
        f.lfgCheck = ns.checkBox(f, ns.GameIcons.markup("lfg", 18) .. " 同時在尋求組隊上架", FX, y[7], function(on) draft.lfg = on end)
        f.result = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)); f.result:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", FX, 24)
        if f.result.SetTextColor then f.result:SetTextColor(1, 0.4, 0.4) end
        f.go = O.textButton(f, tex("yes", 20) .. " 開單", function() UI.submitTicket() end, 120)
        f.go:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 18)
        f:Hide()
        popup = f
    end
    popup.note:SetText(draft.note or "")
    popup.result:SetText("")
    popup:Show()
    drawTicket()
    return draft
end
function UI.draft() return draft end

---------------------------------------------------------------------------
-- 選擇目的地 (GF-002-F): its own window; the ticket / worker window steps
-- aside while it is open. GF-002-G: with 現在, the dungeons people are
-- looking for in the game's group finder say so ("現在 2 隊").
---------------------------------------------------------------------------

UI.GRID_NAME = "GreenFangToolkit_DungeonGrid"
UI.GRID_COLUMNS, UI.GRID_CELL_W, UI.GRID_CELL_H = 8, 100, 124
local grid

function UI.dungeonGrid(owner, onClick, isOn, onQuest, returnTo, showLfg)
    if ns.Framework.closeMenu then ns.Framework.closeMenu() end
    local qp = UI.questPickerFrame and UI.questPickerFrame()
    if qp and qp:IsShown() then qp:Hide() end
    if not grid then
        grid = CreateFrame("Frame", UI.GRID_NAME, UIParent)
        grid:SetFrameStrata("TOOLTIP") -- above the click-outside blocker
        if grid.SetFrameLevel then grid:SetFrameLevel(50) end
        ns.makeOpaque(grid, 0)
        grid:EnableMouse(true)
        ns.escRegister(grid, ns.ESC_LEVEL.grid)
        grid.title = ns.freeText(grid:CreateFontString(nil, "ARTWORK", ns.TITLE_FONT))
        grid.title:SetPoint("TOPLEFT", grid, "TOPLEFT", 20, -14)
        grid.buttons = {}
        local C, W, H, ICON = UI.GRID_COLUMNS, UI.GRID_CELL_W, UI.GRID_CELL_H, ns.DUNGEON_ICON
        local TOP = 48
        local function place(b, i)
            b:SetPoint("TOPLEFT", grid, "TOPLEFT", 16 + ((i - 1) % C) * W + (W - ICON) / 2, -TOP - math.floor((i - 1) / C) * H)
        end
        local function texts(b, name)
            b.label = ns.freeText(b:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
            b.label:SetPoint("TOP", b, "BOTTOM", 0, -4)
            b.label:SetText(name)
            b.level = ns.freeText(b:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
            b.level:SetPoint("TOP", b.label, "BOTTOM", 0, -2)
            b.lfgCount = ns.freeText(b:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
            b.lfgCount:SetPoint("TOP", b.level, "BOTTOM", 0, -2)
            b.lfgCount:SetTextColor(0.45, 0.85, 1)
        end
        for i, d in ipairs(ns.AdventureData.DUNGEONS) do
            local b = iconButton(grid, ICON, "dungeon", nil)
            place(b, i)
            texts(b, d.short or d.name)
            b.level:SetText(UI.levelText(d.id))
            b.dungeon = d.id
            grid.buttons[i] = b
        end
        local n = #ns.AdventureData.DUNGEONS
        grid.quest = iconButton(grid, ICON, "quest", nil)
        texts(grid.quest, "任務")
        grid.quest.level:SetText("")
        ns.GameIcons.set(grid.quest.tex, "quest")
        place(grid.quest, n + 1)
        local rows = math.ceil((n + 1) / C)
        grid.done = ns.OrdersUI.textButton(grid, tex("yes", 20) .. " 完成", function() grid:Hide() end, 110)
        grid.done:SetPoint("BOTTOMRIGHT", grid, "BOTTOMRIGHT", -20, 14)
        grid:SetSize(32 + C * W, TOP + rows * H + 56)
        grid:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
        grid:HookScript("OnHide", function(self)
            local back = self.returnTo
            self.returnTo = nil
            if back and not back:IsShown() then
                back:Show()
                if back == popup then drawTicket() elseif back == wpopup then UI.drawWorker() end
            end
        end)
        grid:Hide()
    end
    grid.title:SetText(isOn and "選擇地城（可以選好幾個）" or "選擇目的地")
    if isOn then grid.done:Show() else grid.done:Hide() end
    if onQuest then
        grid.quest:SetScript("OnClick", function(self) grid:Hide(); onQuest(self) end)
        grid.quest:Show()
    else
        grid.quest:Hide()
    end
    local level = A().myLevel()
    local counts = (showLfg and ns.NativeLFG and ns.NativeLFG.results) and ns.NativeLFG.counts() or {}
    local function mark(b)
        if isOn then ns.OrdersUI.setSelected(b, isOn(b.dungeon))
        else
            b.sel:Hide(); b.shine:Hide(); b.selected = nil
            if b.tex.SetVertexColor then b.tex:SetVertexColor(1, 1, 1) end
        end
        if isOn and isOn(b.dungeon) then ns.GameIcons.set(b.badge, "yes") else b.badge:Hide() end
        b.label:SetTextColor(1, 1, 1)
    end
    for _, b in ipairs(grid.buttons) do
        ns.GameIcons.set(b.tex, ns.GameIcons.dungeonKey(b.dungeon))
        local r, g, bl = ns.GameIcons.levelColor(b.dungeon, level)
        b.level:SetTextColor(r, g, bl)
        b.levelColor = { r, g, bl }
        b.tip = nil -- the name and levels are written out; no tooltip over the grid
        b.lfgCount:SetText(counts[b.dungeon] and ("現在 " .. counts[b.dungeon] .. " 隊") or "")
        mark(b)
        b:SetScript("OnClick", function(self)
            onClick(self.dungeon)
            if isOn then mark(self) else grid:Hide() end
        end)
    end
    -- The window it was opened from steps aside (nothing is covered).
    grid.returnTo = returnTo
    grid:Show()
    if returnTo and returnTo:IsShown() then returnTo:Hide() end
    return grid
end
function UI.grid() return grid end
ns.onExclusiveShow = function() if grid and grid:IsShown() then grid.returnTo = nil; grid:Hide() end end

-- Every menu on this page goes through here: the dungeon grid closes first.
function UI.menu(owner, items)
    if grid and grid:IsShown() then grid:Hide() end
    return ns.showMenu(owner, items)
end

local function titled(title, items)
    table.insert(items, 1, { text = "|cffffd100" .. title .. "|r", fn = function() end })
    return items
end
UI.titled = titled

-- Dungeons (the picker); its quest cell opens my quest log instead (R-4.1).
function UI.pickDestination(owner)
    local hasQuests = A().questLog() ~= nil
    -- GF-002-H (R-16.26): quests have their own button; the grid is dungeons only.
    return UI.dungeonGrid(owner, function(id) draft.dungeon = id; draft.quests = {}; draft.questDungeon = nil; drawTicket() end, nil,
        nil, popup, UI.hasNow(draft))
end

function UI.pickQuests(owner)
    -- R-16.27: up to 5; a quest of a dungeon brings that dungeon along.
    return UI.questPicker(owner, { title = "選擇任務（最多 5 個）", max = A().MAX_QUESTS,
        isOn = function(id) for _, x in ipairs(draft.quests) do if x == id then return true end end return false end,
        onToggle = function(id, info)
            for i, x in ipairs(draft.quests) do
                if x == id then table.remove(draft.quests, i); UI.questDungeonFor(draft); drawTicket(); return end
            end
            if #draft.quests >= A().MAX_QUESTS then return end
            draft.quests[#draft.quests + 1] = id
            UI.questDungeonFor(draft)
            drawTicket()
        end })
end
-- The dungeon a draft's quests belong to (the first dungeon quest), R-16.27.
function UI.questDungeonFor(d)
    local log = A().questLog() or {}
    local found
    for _, q in ipairs(d.quests) do
        local dg = UI.questDungeon(log[q])
        if dg then found = dg; break end
    end
    if found then d.dungeon, d.questDungeon = found, true
    elseif d.questDungeon then d.dungeon, d.questDungeon = nil, nil end
end

-- The dungeon a quest log zone header names (ids of AdventureData), or nil.
function UI.questDungeon(info)
    local zone = info and str(info.zone)
    if not zone or zone == "" then return nil end
    for _, dg in ipairs(ns.AdventureData.DUNGEONS) do
        local base = dg.name:match("^(.-)：") or dg.name
        if zone == dg.name or zone == base or zone:find(base, 1, true) then return dg.id end
    end
    return nil
end

---------------------------------------------------------------------------
-- GF-002-H (R-16.27, R-16.29): the quest picker. Grouped by the quest log's
-- zone headers; a row: the quest (or its dungeon's) art, the full name, the
-- level in its difficulty color; ❗ when an open adventure ticket wants it.
---------------------------------------------------------------------------

UI.QUEST_PICKER_NAME = "GreenFangToolkit_QuestPicker"
UI.QP_ROW, UI.QP_COL_W, UI.QP_MAX_Y = 30, 420, 560
local qpicker
function UI.questList()
    local log = A().questLog() or {}
    local list = {}
    for id, info in pairs(log) do list[#list + 1] = { id = id, info = info } end
    table.sort(list, function(x, y)
        local ox, oy = x.info.order or 0, y.info.order or 0
        if ox ~= oy then return ox < oy end
        return x.id < y.id
    end)
    local groups, byZone = {}, {}
    for _, q in ipairs(list) do
        local z = str(q.info.zone) ~= "" and q.info.zone or "其他"
        if not byZone[z] then byZone[z] = { zone = z, quests = {} }; groups[#groups + 1] = byZone[z] end
        table.insert(byZone[z].quests, q)
    end
    return groups
end
function UI.questPicker(owner, opts)
    -- opts = { title, max, isOn(id), onToggle(id, info), all = { on, count, toggle() } (worker) }
    if ns.Framework.closeMenu then ns.Framework.closeMenu() end
    local g = UI.grid and UI.grid()
    if g and g:IsShown() then g:Hide() end
    local O = ns.OrdersUI
    if not qpicker then
        qpicker = CreateFrame("Frame", UI.QUEST_PICKER_NAME, UIParent)
        qpicker:SetFrameStrata("TOOLTIP")
        if qpicker.SetFrameLevel then qpicker:SetFrameLevel(60) end
        ns.makeOpaque(qpicker, 0)
        qpicker:EnableMouse(true)
        ns.escRegister(qpicker, ns.ESC_LEVEL.menu)
        qpicker.title = ns.freeText(qpicker:CreateFontString(nil, "ARTWORK", ns.TITLE_FONT))
        qpicker.title:SetPoint("TOPLEFT", qpicker, "TOPLEFT", 16, -12)
        qpicker.all = iconButton(qpicker, 28, "quest", nil, function() if qpicker.opts.all then qpicker.opts.all.toggle(); qpicker.draw() end end, "")
        qpicker.heads, qpicker.rows = {}, {}
        qpicker.done = O.textButton(qpicker, tex("yes", 18) .. " 完成", function() qpicker:Hide() end, 96)
        qpicker.empty = qpicker:CreateFontString(nil, "ARTWORK", ns.DISABLED_FONT)
        qpicker.empty:SetPoint("TOPLEFT", qpicker, "TOPLEFT", 16, -50)
        qpicker:Hide()
        local function row(k)
            local r = qpicker.rows[k]
            if r then return r end
            r = CreateFrame("Button", nil, qpicker)
            r:SetSize(UI.QP_COL_W - 20, UI.QP_ROW - 2)
            r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(24, 24); r.icon:SetPoint("LEFT", r, "LEFT", 4, 0)
            r.want = r:CreateTexture(nil, "OVERLAY"); r.want:SetSize(16, 16); r.want:SetPoint("TOPLEFT", r.icon, "TOPLEFT", -6, 6)
            r.name = r:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)
            r.name:SetPoint("LEFT", r, "LEFT", 34, 0); r.name:SetWidth(UI.QP_COL_W - 120); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
            r.level = r:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)
            r.level:SetPoint("LEFT", r, "LEFT", UI.QP_COL_W - 80, 0)
            r.sel = r:CreateTexture(nil, "BACKGROUND"); r.sel:SetAllPoints()
            r.sel:SetColorTexture(1, 0.82, 0.2, 0.22)
            if r.SetHighlightTexture then r:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD") end
            r:SetScript("OnClick", function(self) qpicker.opts.onToggle(self.questId, self.info); qpicker.draw() end)
            qpicker.rows[k] = r
            return r
        end
        local function head(k)
            local h = qpicker.heads[k]
            if h then return h end
            h = ns.freeText(qpicker:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT))
            h:SetTextColor(1, 0.82, 0)
            qpicker.heads[k] = h
            return h
        end
        function qpicker.draw()
            local o = qpicker.opts
            local wanted = A().wantedQuests()
            local y, col, maxY = -48, 0, 0
            if o.all then
                qpicker.all:Show()
                qpicker.all:ClearAllPoints(); qpicker.all:SetPoint("TOPLEFT", qpicker, "TOPLEFT", 16, y)
                O.setLabel(qpicker.all, "日誌全部" .. (o.all.count and (" " .. o.all.count) or ""))
                O.setSelected(qpicker.all, o.all.on())
                y = y - 40
            else qpicker.all:Hide() end
            local top = y
            local nh, nr = 0, 0
            local groups = UI.questList()
            local function place(w, h)
                if y - h < -UI.QP_MAX_Y and col == 0 then col, y = 1, top end
                w:ClearAllPoints()
                w:SetPoint("TOPLEFT", qpicker, "TOPLEFT", 16 + col * UI.QP_COL_W, y)
                y = y - h
                maxY = math.max(maxY, -y)
            end
            for _, gr in ipairs(groups) do
                nh = nh + 1
                local h = head(nh)
                h:SetText(gr.zone)
                place(h, 26); h:Show()
                for _, q in ipairs(gr.quests) do
                    nr = nr + 1
                    local r = row(nr)
                    r.questId, r.info = q.id, q.info
                    local dg = UI.questDungeon(q.info)
                    if dg then ns.GameIcons.set(r.icon, ns.GameIcons.dungeonKey(dg)) else ns.GameIcons.set(r.icon, "quest") end
                    r.name:SetText(str(q.info.title))
                    local lv = q.info.scaling and "s" or q.info.level
                    r.level:SetText(UI.levelMark(lv))
                    if wanted[q.id] then setIcon(r.want, "attention"); r.want:Show() else r.want:Hide() end
                    r.wanted = wanted[q.id] == true
                    local on = o.isOn(q.id)
                    r.selected = on
                    if on then r.sel:Show() else r.sel:Hide() end
                    if o.all and o.all.on() then r:SetAlpha(0.5) else r:SetAlpha(1) end
                    place(r, UI.QP_ROW); r:Show()
                end
            end
            for k = nh + 1, #qpicker.heads do qpicker.heads[k]:Hide() end
            for k = nr + 1, #qpicker.rows do qpicker.rows[k]:Hide() end
            qpicker.empty:SetText(nr == 0 and "任務日誌是空的" or "")
            local width = 32 + (col + 1) * UI.QP_COL_W
            qpicker.done:ClearAllPoints()
            qpicker.done:SetPoint("BOTTOMRIGHT", qpicker, "BOTTOMRIGHT", -16, 12)
            qpicker:SetSize(width, math.max(maxY, 90) + 60)
        end
    end
    qpicker.opts = opts
    qpicker.title:SetText(opts.title or "任務")
    qpicker:ClearAllPoints()
    qpicker:SetPoint("TOPLEFT", owner or UIParent, owner and "BOTTOMLEFT" or "CENTER", 0, -4)
    if qpicker.SetClampedToScreen then qpicker:SetClampedToScreen(true) end
    qpicker:Show()
    qpicker.draw()
    return qpicker
end
function UI.questPickerFrame() return qpicker end

-- Set a slot's start directly (scripts and tests): "n" 現在, "t" the next quarter,
-- "f" 20:00 the day after tomorrow (其他日期). i = the slot (default 1).
function UI.pickTime(owner, mode, i)
    local sl = draft.slots[i or 1]
    if not sl then sl = {}; draft.slots[i or 1] = sl end
    if mode == "n" then sl.now, sl.start, sl.dayOff = true, nil, nil
    elseif mode == "t" then sl.now, sl.start, sl.dayOff = false, UI.nextQuarter(), nil
    else
        sl.now, sl.dayOff = false, 2
        sl.start = UI.dayStart(2) + 20 * 3600
    end
    drawTicket()
end

-- A slot's 開始 and 長度: the picker (現在, today / tomorrow, or the other day chosen).
function UI.pickStart(owner, i)
    return UI.editSlot(owner, draft.slots, i or 1, drawTicket)
end
-- The length of slot i in hours (nil = none); scripts and tests.
function UI.setDuration(h, i)
    local sl = draft.slots[i or 1]
    if sl then sl.dur = h end
    drawTicket()
end

-- 其他日期: the days after tomorrow (with the year), for one draft slot.
function UI.pickDay(owner, sl, redraw)
    sl = sl or draft.slots[1]
    redraw = redraw or drawTicket
    local items = {}
    for dayOff = 2, A().FUTURE_DAYS do
        items[#items + 1] = { text = UI.dayText(UI.dayStart(dayOff) + 43200), fn = function()
            local tod = (sl.start and not sl.now) and (sl.start - UI.dayStart(0, sl.start)) or 20 * 3600
            sl.now = false
            sl.dayOff = dayOff
            sl.start = UI.dayStart(dayOff) + tod
            redraw()
        end }
    end
    return UI.menu(owner, titled("日期", items))
end

---------------------------------------------------------------------------
-- Worker ticket (R-5.1 – R-5.4). GF-002-G: the chosen dungeons wrap over as
-- many lines as they need and the rows below move down (0.12.4 drew the
-- third line over 「任務」); 時段 uses the same 開始 / 時長 controls.
---------------------------------------------------------------------------

UI.WORKER_NAME = "GreenFangToolkit_WorkerPopup"

function UI.newWorkerDraft()
    local mine = A().myWorker()
    if mine then
        local slots = {}
        for _, sl in ipairs(mine.slots or {}) do slots[#slots + 1] = UI.draftSlot(sl) end
        mine.slots = #slots > 0 and slots or { { now = true } }
        return mine
    end
    local _, token = ns.call(UnitClass, "player")
    local main, alt = A().defaultRoles(token)
    return { dungeons = {}, quests = {}, allQuests = false, main = main, alt = alt, slots = { { now = true } } }
end

function UI.drawWorkerTitle()
    if not wpopup then return end
    local registered = A().myWorker() ~= nil
    if wpopup.TitleText then wpopup.TitleText:SetText(registered and "職工單（已登記）" or "職工單") end
    wpopup.save:SetText(tex("yes", 20) .. (registered and " 更新" or " 登記"))
    if registered then wpopup.remove:Show() else wpopup.remove:Hide() end
end

-- Lay buttons out left to right, wrapping before maxRight. Returns the number of lines.
function UI.wrapFlow(f, list, x0, y0, maxRight, lineH, gap)
    local x, y, lines = x0, y0, (#list > 0) and 1 or 0
    for _, b in ipairs(list) do
        local span = ns.OrdersUI.buttonSpan(b)
        if x > x0 and x + span > maxRight then
            x, y, lines = x0, y - lineH, lines + 1
        end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
        b.flowX, b.flowY = x, y
        x = x + span + gap
    end
    return lines
end
UI.CHIP_LINE = 42

function UI.drawWorker()
    if not (wpopup and wdraft) then return end
    local f = wpopup
    local O = ns.OrdersUI
    local X = f.controlX
    for i, id in ipairs(wdraft.dungeons) do
        local c = f.chips[i]
        if not c then
            c = iconButton(f, ns.ICON, "dungeon", nil, function(self) UI.toggleWorkerDungeon(self.dungeon) end, "")
            f.chips[i] = c
        end
        ns.GameIcons.set(c.tex, ns.GameIcons.dungeonKey(id))
        c.dungeon = id
        c.tip = ns.AdventureData.byId[id] and ns.AdventureData.byId[id].name
        O.setLabel(c, ns.AdventureData.short(id))
        c:Show()
    end
    for i = #wdraft.dungeons + 1, #f.chips do f.chips[i]:Hide() end
    local shown = {}
    for i = 1, #wdraft.dungeons do shown[#shown + 1] = f.chips[i] end
    shown[#shown + 1] = f.addDungeon
    local lines = UI.wrapFlow(f, shown, X, f.top, f.width - 24, UI.CHIP_LINE, 16)
    -- The rows below follow the chips.
    local y = f.top - lines * UI.CHIP_LINE - 10
    local function place(fs, ctl, yy)
        fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", f, "TOPLEFT", O.FIELD_X, yy - 8)
        if ctl then ctl:ClearAllPoints(); ctl:SetPoint("TOPLEFT", f, "TOPLEFT", X, yy) end
    end
    place(f.questField, f.quests, y); y = y - O.ROW_STEP
    place(f.mainField, nil, y); O.flow(f, f.mainList, X, y, 40); y = y - O.ROW_STEP
    place(f.altField, nil, y); O.flow(f, f.altList, X, y, 40); y = y - O.ROW_STEP
    -- GF-002-H: 時段 chips (1-5), each with its picker; the window grows with them.
    place(f.slotField, nil, y)
    local slotLines = UI.drawSlotChips(f, wdraft.slots, f.slotChips, f.addSlot, X, y, function(self, i) UI.pickWorkerSlots(self, i) end)
    f.slots = f.slotChips[1]
    y = y - math.max(1, slotLines) * UI.CHIP_LINE - 10
    f:SetHeight(-y + 70)
    for _, r in ipairs(A().ROLES) do
        O.setSelected(f.mainRoles[r], wdraft.main == r)
        O.setSelected(f.altRoles[r], wdraft.alt == r)
    end
    local qn = UI.workerQuests({ allQuests = wdraft.allQuests, quests = wdraft.quests, questNames = wdraft.questNames,
        questCount = wdraft.allQuests and A().questCount() or nil }, 2)
    local qText = qn ~= "" and (tex("quest", 20) .. " " .. qn) or "選擇任務"
    f.quests:SetText(qText)
    f.quests.gfWidth = ns.labelWidth(qText) + 28
    f.quests:SetSize(f.quests.gfWidth, ns.BUTTON_H)
    UI.drawWorkerTitle()
end
local drawWorker = function() UI.drawWorker() end

UI.WORKER_FIELDS = { "地城", "任務", "職責", "副職責", "時段" }
function UI.openWorker()
    wdraft = UI.newWorkerDraft()
    if not wpopup then
        local f = ns.popupWindow(UI.WORKER_NAME, 740, 420)
        f:SetPoint("CENTER", 0, 40)
        f:EnableMouse(true)
        ns.exclusivePopup(f)
        local O = ns.OrdersUI
        local FX = O.FIELD_X
        local X = O.controlX(UI.WORKER_FIELDS)
        f.controlX, f.top, f.width = X, -48, 740
        local field = O.fieldLabel
        f.dungeonField = field(f, "地城", FX, f.top - 8)
        f.chips = {}
        f.addDungeon = O.textButton(f, "＋地城", function(self) UI.pickWorkerDungeons(self) end)
        f.questField = field(f, "任務", FX, 0)
        f.quests = O.textButton(f, "選擇任務", function(self) UI.pickWorkerQuests(self) end)
        f.mainField = field(f, "職責", FX, 0)
        f.altField = field(f, "副職責", FX, 0)
        f.mainRoles, f.altRoles, f.mainList, f.altList = {}, {}, {}, {}
        for _, r in ipairs(A().ROLES) do
            local m = iconButton(f, ns.ICON, r, UI.ROLE_NAME[r], function()
                wdraft.main = r; if wdraft.alt == r then wdraft.alt = nil end; drawWorker()
            end, UI.ROLE_NAME[r])
            f.mainRoles[r] = m
            f.mainList[#f.mainList + 1] = m
            local a = iconButton(f, ns.ICON, r, UI.ROLE_NAME[r], function()
                wdraft.alt = (wdraft.alt == r or wdraft.main == r) and nil or r; drawWorker()
            end, UI.ROLE_NAME[r])
            f.altRoles[r] = a
            f.altList[#f.altList + 1] = a
        end
        f.roles = f.mainRoles.t
        f.slotField = field(f, "時段", FX, 0)
        f.slotChips = {}
        f.addSlot = O.textButton(f, "＋時段", function(self) UI.addSlot(wdraft.slots, drawWorker, self) end)
        f.remove = iconButton(f, ns.ICON, "no", "移除", function() A().removeWorker(); f:Hide(); UI.refresh() end, "移除職工單")
        f.remove:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", FX, 18)
        f.save = O.textButton(f, tex("yes", 20) .. " 登記", function() UI.saveWorker() end, 120)
        f.save:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 18)
        f:Hide()
        wpopup = f
    end
    wpopup:Show()
    drawWorker()
    return wdraft
end
function UI.workerDraft() return wdraft end

function UI.saveWorker(d)
    d = d or wdraft
    local o = {}
    for k, v in pairs(d) do o[k] = v end
    o.slots = {}
    for _, ds in ipairs(d.slots or {}) do o.slots[#o.slots + 1] = UI.slotData(ds) end
    local ok = A().setWorker(o)
    if wpopup then wpopup:Hide() end
    UI.refresh()
    return ok
end

function UI.toggleWorkerDungeon(id)
    for i, x in ipairs(wdraft.dungeons) do if x == id then table.remove(wdraft.dungeons, i); drawWorker(); return false end end
    wdraft.dungeons[#wdraft.dungeons + 1] = id
    drawWorker()
    return true
end

function UI.pickWorkerDungeons(owner)
    return UI.dungeonGrid(owner, function(id) UI.toggleWorkerDungeon(id) end, function(id)
        for _, x in ipairs(wdraft.dungeons) do if x == id then return true end end
        return false
    end, nil, wpopup, UI.hasNow(wdraft))
end

function UI.pickWorkerQuests(owner)
    -- R-16.29: 日誌全部 (with the count) or the quests one by one; ❗ = an open ticket wants it.
    return UI.questPicker(owner, { title = "選擇任務",
        all = { count = A().questCount(), on = function() return wdraft.allQuests == true end,
            toggle = function() wdraft.allQuests = not wdraft.allQuests; drawWorker() end },
        isOn = function(id) for _, x in ipairs(wdraft.quests) do if x == id then return true end end return false end,
        onToggle = function(id)
            for i, x in ipairs(wdraft.quests) do if x == id then table.remove(wdraft.quests, i); drawWorker(); return end end
            wdraft.quests[#wdraft.quests + 1] = id
            drawWorker()
        end })
end

function UI.pickWorkerRoles(owner)
    local items = {}
    for _, r in ipairs(A().ROLES) do
        items[#items + 1] = { text = tex(r) .. " " .. UI.ROLE_NAME[r], fn = function() wdraft.main = r; if wdraft.alt == r then wdraft.alt = nil end drawWorker() end }
    end
    return UI.menu(owner, items)
end

-- 時段: the same picker as the adventure ticket (開始, 長度, 其他日期, 移除).
-- Scripts and tests: set slot i's start (nil = 現在).
function UI.setWorkerSlot(t, i)
    local sl = wdraft.slots[i or 1]
    if not sl then sl = {}; wdraft.slots[i or 1] = sl end
    if t then sl.now, sl.start = false, t else sl.now, sl.start, sl.dayOff = true, nil, nil end
    drawWorker()
end
function UI.pickWorkerSlots(owner, i)
    return UI.editSlot(owner, wdraft.slots, i or 1, drawWorker)
end

---------------------------------------------------------------------------
-- GF-002-H (R-16.5, R-16.7, R-16.8): pick slots of a ticket: several (申請,
-- 邀請, change my slots) or one (定案), each with its signups per role.
---------------------------------------------------------------------------

UI.CHOOSER_NAME = "GreenFangToolkit_SlotChooser"
local chooser
function UI.slotChooser(owner, opts)
    -- opts = { title, slots, counts = { [id] = { t, h, d, any, total } }, selected = { ids }, multi, button, onDone(ids) }
    if ns.Framework.closeMenu then ns.Framework.closeMenu() end
    local O = ns.OrdersUI
    if not chooser then
        chooser = CreateFrame("Frame", UI.CHOOSER_NAME, UIParent)
        chooser:SetFrameStrata("TOOLTIP")
        if chooser.SetFrameLevel then chooser:SetFrameLevel(60) end
        ns.makeOpaque(chooser, 0)
        chooser:EnableMouse(true)
        ns.escRegister(chooser, ns.ESC_LEVEL.menu)
        chooser.title = ns.freeText(chooser:CreateFontString(nil, "ARTWORK", ns.TITLE_FONT))
        chooser.title:SetPoint("TOPLEFT", chooser, "TOPLEFT", 14, -10)
        chooser.rows = {}
        for i = 1, 5 do
            local b = iconButton(chooser, ns.ICON, "today", nil, function(self) chooser.toggle(self.slotId) end, "")
            b:SetPoint("TOPLEFT", chooser, "TOPLEFT", 18, -44 - (i - 1) * 44)
            b.count = ns.freeText(chooser:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
            b.count:SetPoint("TOPLEFT", chooser, "TOPLEFT", 400, -44 - (i - 1) * 44 - 8)
            chooser.rows[i] = b
        end
        chooser.go = O.textButton(chooser, "", function()
            local ids = {}
            for _, b in ipairs(chooser.rows) do if b:IsShown() and b.selected then ids[#ids + 1] = b.slotId end end
            if #ids == 0 then return end
            chooser:Hide()
            chooser.opts.onDone(ids)
        end, 110)
        function chooser.toggle(id)
            local o = chooser.opts
            for _, b in ipairs(chooser.rows) do
                if b:IsShown() then
                    if o.multi then
                        if b.slotId == id then O.setSelected(b, not b.selected) end
                    else O.setSelected(b, b.slotId == id) end
                end
            end
        end
        chooser:Hide()
    end
    chooser.opts = opts
    chooser.title:SetText(opts.title or "時段")
    local pre = {}
    for _, id in ipairs(opts.selected or {}) do pre[id] = true end
    local n = 0
    for i, b in ipairs(chooser.rows) do
        local sl = opts.slots[i]
        if sl then
            n = i
            b.slotId = sl.id
            ns.GameIcons.set(b.tex, sl.now and "now" or (UI.dayOffset(sl.s) <= 1 and "today" or "future"))
            local label = UI.slotText({ now = sl.now, s = sl.s, d = sl.d }):gsub("^|T.-|t ", "")
            O.setLabel(b, label)
            O.setSelected(b, pre[sl.id] == true)
            local c = opts.counts and opts.counts[sl.id]
            local parts = {}
            if c then
                if (c.any or 0) > 0 then parts[#parts + 1] = tex("any", 18) .. " " .. c.any end
                for _, r in ipairs(A().ROLES) do if (c[r] or 0) > 0 then parts[#parts + 1] = tex(r, 18) .. " " .. c[r] end end
            end
            b.count:SetText(table.concat(parts, "  "))
            b:Show(); b.count:Show()
        else b:Hide(); b.count:Hide() end
    end
    chooser.go:SetText(opts.button or (tex("yes", 18) .. " 完成"))
    chooser.go:ClearAllPoints()
    chooser.go:SetPoint("BOTTOMRIGHT", chooser, "BOTTOMRIGHT", -14, 12)
    chooser:SetSize(600, 44 + n * 44 + 56)
    chooser:ClearAllPoints()
    chooser:SetPoint("TOPLEFT", owner or UIParent, owner and "BOTTOMLEFT" or "CENTER", 0, -4)
    if chooser.SetClampedToScreen then chooser:SetClampedToScreen(true) end
    chooser:Show()
    return chooser
end
function UI.chooser() return chooser end

---------------------------------------------------------------------------
-- GF-002-H (R-16.12 - R-16.14): the adventure calendar. One week a page,
-- up to 14 days ahead; each day shows the destinations of the tickets with a
-- slot that day (only the finalized slot once there is one). Frames: mine
-- gold, my signups green, finalized slots shine. Click a day: its tickets.
-- Only the tickets the toolkit synced; never the game's calendar.
---------------------------------------------------------------------------

UI.CALENDAR_NAME = "GreenFangToolkit_AdventureCalendar"
UI.CAL_CELL_W, UI.CAL_CELL_H, UI.CAL_ICONS = 132, 150, 6
UI.CAL_PAGES = math.floor(14 / 7) + 1 -- days 0-14: three pages (the last one has day 14)
local calendar
UI.CAL_MINE = { 1, 0.82, 0.2 }
UI.CAL_SIGNED = { 0.35, 1, 0.45 }

-- The items of one day (dayOff from today): { view, slot, mine, signed, final }.
function UI.calendarItems(dayOff)
    local my = S().selfAuthor()
    local out = {}
    local list = {}
    for _, v in pairs(A().all()) do list[#list + 1] = v end
    table.sort(list, function(x, y) return x.id < y.id end)
    for _, v in ipairs(list) do
        if not v.closed then
            local slots = (v.final and v.slotById and v.slotById[v.final]) and { v.slotById[v.final] } or (v.slots or {})
            local mineRow
            for _, l in ipairs({ v.members, v.waitlist, v.pending }) do
                for _, x in ipairs(l) do if x.a == my then mineRow = x end end
            end
            for _, sl in ipairs(slots) do
                local off = sl.now and 0 or UI.dayOffset(sl.s)
                if off == dayOff then
                    local signed = false
                    if mineRow then
                        if not mineRow.slots then signed = true
                        else for _, id in ipairs(mineRow.slots) do if id == sl.id then signed = true end end end
                    end
                    out[#out + 1] = { view = v, slot = sl, mine = v.leader == my, signed = signed, final = v.final == sl.id,
                        at = sl.now and 0 or sl.s }
                    break -- one entry per ticket a day
                end
            end
        end
    end
    table.sort(out, function(x, y) if x.at ~= y.at then return x.at < y.at end return x.view.id < y.view.id end)
    return out
end

local function frameIcon(cell, k)
    local ic = cell.icons[k]
    if ic then return ic end
    ic = CreateFrame("Frame", nil, cell)
    ic:SetSize(32, 32)
    ic.tex = ic:CreateTexture(nil, "ARTWORK"); ic.tex:SetAllPoints()
    ic.glow = ic:CreateTexture(nil, "OVERLAY")
    ic.glow:SetSize(56, 56); ic.glow:SetPoint("CENTER", ic, "CENTER", 0, 0)
    if not Icons.set(ic.glow, ns.OrdersUI.GLOW) then ic.glow:SetColorTexture(1, 0.85, 0.4, 0.35) end
    if ic.glow.SetBlendMode then ic.glow:SetBlendMode("ADD") end
    ic.glow:Hide()
    ic.shine = ic:CreateTexture(nil, "OVERLAY"); ic.shine:SetAllPoints()
    if Icons.set(ic.shine, ns.OrdersUI.SHINE) then
        if ic.shine.SetBlendMode then ic.shine:SetBlendMode("ADD") end
        ic.shine:SetAlpha(0.6)
    end
    ic.shine:Hide()
    local col, row = (k - 1) % 3, math.floor((k - 1) / 3)
    ic:SetPoint("TOPLEFT", cell, "TOPLEFT", 12 + col * 38, -40 - row * 40)
    cell.icons[k] = ic
    return ic
end

-- Draw one icon: the destination, the frame for mine / signed, the shine for finalized.
function UI.calendarMark(ic, item)
    UI.setDest(ic.tex, item.view)
    local c = item.mine and UI.CAL_MINE or item.signed and UI.CAL_SIGNED or nil
    if c then
        if ic.glow.SetVertexColor then ic.glow:SetVertexColor(c[1], c[2], c[3]) end
        ic.glow:Show()
    else ic.glow:Hide() end
    if item.final then ic.shine:Show() else ic.shine:Hide() end
    ic.kind = item.mine and "mine" or item.signed and "signed" or "other"
    ic.final = item.final
    ic:Show()
end

function UI.drawCalendar()
    if not (calendar and calendar:IsShown()) then return end
    local f = calendar
    local first = (f.page or 0) * 7
    f.weekLabel:SetText(UI.day(UI.dayStart(first) + 43200):sub(6) .. " - " .. UI.day(UI.dayStart(math.min(first + 6, 14)) + 43200):sub(6))
    for i, cell in ipairs(f.cells) do
        local off = first + i - 1
        cell.dayOff = off
        local inRange = off <= 14
        local t = UI.dayStart(off) + 43200
        local d = date("*t", t - UI.skew())
        cell.head:SetText(UI.WEEKDAY[d.wday] .. " " .. d.day)
        if off == 0 then cell.head:SetTextColor(1, 0.82, 0) else cell.head:SetTextColor(1, 1, 1) end
        local items = inRange and UI.calendarItems(off) or {}
        cell.items = items
        for k = 1, UI.CAL_ICONS do
            local item = items[k]
            if item then UI.calendarMark(frameIcon(cell, k), item)
            elseif cell.icons[k] then cell.icons[k]:Hide() end
        end
        cell.more:SetText(#items > UI.CAL_ICONS and ("+" .. (#items - UI.CAL_ICONS)) or "")
        cell.bg:SetColorTexture(0.2, 0.15, 0.15, (off == f.day) and 0.7 or (inRange and 0.35 or 0.1))
        if cell.SetAlpha then cell:SetAlpha(inRange and 1 or 0.4) end
        cell.enabled = inRange
    end
    if f.page > 0 then f.prev:Show() else f.prev:Hide() end
    if f.page < UI.CAL_PAGES - 1 then f.next:Show() else f.next:Hide() end
    -- The chosen day's tickets.
    local items = UI.calendarItems(f.day or 0)
    f.dayLabel:SetText(UI.dayText(UI.dayStart(f.day or 0) + 43200))
    for k, row in ipairs(f.list) do
        local item = items[k]
        if item then
            row.item = item
            UI.setDest(row.dest, item.view)
            row.name:SetText(UI.destText(item.view))
            row.time:SetText(UI.slotText(item.slot))
            row.seats:SetText(UI.roleText(item.view))
            row.state:SetText((item.view.formed and (tex("group", 18) .. " 成團  ") or "")
                .. (item.mine and "|cffffd100我開的|r" or item.signed and "|cff66ff77我報名|r" or ""))
            row:Show()
        else row:Hide(); row.item = nil end
    end
    f.empty:SetText(#items == 0 and "這天沒有冒險單" or "")
end

function UI.openCalendar()
    if not calendar then
        local W, H = UI.CAL_CELL_W, UI.CAL_CELL_H
        local f = ns.popupWindow(UI.CALENDAR_NAME, 40 + 7 * (W + 4), 640)
        f:SetPoint("CENTER", 0, 40)
        f:EnableMouse(true)
        ns.exclusivePopup(f)
        if f.TitleText then f.TitleText:SetText("行事曆") end
        f.prev = iconButton(f, ns.ROW_ICON, "prev", "上一週", function() f.page = math.max(0, f.page - 1); UI.drawCalendar() end)
        ns.GameIcons.set(f.prev.tex, "prev")
        f.prev:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -36)
        f.weekLabel = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT))
        f.weekLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 60, -42)
        f.next = iconButton(f, ns.ROW_ICON, "next", "下一週", function() f.page = math.min(UI.CAL_PAGES - 1, f.page + 1); UI.drawCalendar() end)
        ns.GameIcons.set(f.next.tex, "next")
        f.next:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -36)
        -- Legend: the three frames (2-3 character names).
        local lx = 260
        f.legend = {}
        for _, it in ipairs({ { "我開的", { mine = true } }, { "我報名", { signed = true } }, { "已定案", { final = true } } }) do
            local ic = CreateFrame("Frame", nil, f)
            ic:SetSize(24, 24)
            ic:SetPoint("TOPLEFT", f, "TOPLEFT", lx, -38)
            ic.tex = ic:CreateTexture(nil, "ARTWORK"); ic.tex:SetAllPoints()
            ns.GameIcons.set(ic.tex, "key")
            ic.glow = ic:CreateTexture(nil, "OVERLAY"); ic.glow:SetSize(42, 42); ic.glow:SetPoint("CENTER", ic, "CENTER", 0, 0)
            if not Icons.set(ic.glow, ns.OrdersUI.GLOW) then ic.glow:SetColorTexture(1, 0.85, 0.4, 0.35) end
            if ic.glow.SetBlendMode then ic.glow:SetBlendMode("ADD") end
            ic.shine = ic:CreateTexture(nil, "OVERLAY"); ic.shine:SetAllPoints()
            if Icons.set(ic.shine, ns.OrdersUI.SHINE) and ic.shine.SetBlendMode then ic.shine:SetBlendMode("ADD") end
            local c = it[2].mine and UI.CAL_MINE or it[2].signed and UI.CAL_SIGNED or nil
            if c then if ic.glow.SetVertexColor then ic.glow:SetVertexColor(c[1], c[2], c[3]) end else ic.glow:Hide() end
            if not it[2].final then ic.shine:Hide() end
            local l = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
            l:SetPoint("LEFT", ic, "RIGHT", 10, 0)
            l:SetText(it[1])
            f.legend[#f.legend + 1] = { icon = ic, label = l }
            lx = lx + 24 + 10 + ns.labelWidth(it[1]) + 28
        end
        f.cells = {}
        for i = 1, 7 do
            local cell = CreateFrame("Button", nil, f)
            cell:SetSize(W, H)
            cell:SetPoint("TOPLEFT", f, "TOPLEFT", 20 + (i - 1) * (W + 4), -76)
            cell.bg = cell:CreateTexture(nil, "BACKGROUND"); cell.bg:SetAllPoints()
            cell.head = ns.freeText(cell:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT))
            cell.head:SetPoint("TOPLEFT", cell, "TOPLEFT", 10, -10)
            cell.more = ns.freeText(cell:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
            cell.more:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -8, 8)
            cell.icons = {}
            if cell.SetHighlightTexture then cell:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD") end
            cell:SetScript("OnClick", function(self)
                if not self.enabled then return end
                f.day = self.dayOff
                UI.drawCalendar()
            end)
            f.cells[i] = cell
        end
        f.dayLabel = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT))
        f.dayLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -76 - H - 16)
        f.list = {}
        for k = 1, 8 do
            local row = CreateFrame("Frame", nil, f)
            row:SetSize(7 * (W + 4) - 4, ns.PAGE_ROW)
            row:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -76 - H - 48 - (k - 1) * ns.PAGE_ROW)
            row.dest = row:CreateTexture(nil, "ARTWORK"); row.dest:SetSize(ns.ROW_ICON, ns.ROW_ICON)
            row.dest:SetPoint("LEFT", row, "LEFT", 4, 0)
            local function text(x, w)
                local fs = row:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)
                fs:SetPoint("LEFT", row, "LEFT", x, 0); fs:SetWidth(w); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
                return fs
            end
            row.name = text(40, 250)
            row.time = text(300, 250)
            row.seats = text(560, 190)
            row.state = text(760, 180)
            row:Hide()
            f.list[k] = row
        end
        f.empty = f:CreateFontString(nil, "ARTWORK", ns.DISABLED_FONT)
        f.empty:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -76 - H - 52)
        f:Hide()
        calendar = f
    end
    calendar.page, calendar.day = 0, 0
    calendar:Show()
    UI.drawCalendar()
    return calendar
end
function UI.calendar() return calendar end

---------------------------------------------------------------------------
-- Minimap: a second number for adventures (R-8.2), its own color and corner
---------------------------------------------------------------------------

function UI.updateBadge()
    local b = ns.Framework.minimapButton
    if not b then return end
    if not b.adventureBadge then
        b.adventureBadge = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.adventureBadge:SetPoint("TOPLEFT", b, "TOPLEFT", -2, 2)
        b.adventureBadge:SetTextColor(1, 0.35, 0.3)
    end
    local n = ns.guildState() == "target" and A().attentionCount() or 0
    b.adventureBadge:SetText(n > 0 and tostring(n) or "")
    UI.badgeCount = n
end

-- Two lines of numbers in the minimap tooltip (R-8.2).
ns.Framework.tooltipLines = ns.Framework.tooltipLines or {}
table.insert(ns.Framework.tooltipLines, function(tip)
    local a = UI.badgeCount or 0
    local o = ns.OrdersUI and ns.OrdersUI.badgeCount or 0
    if a > 0 then tip:AddLine(tex("dungeon") .. " 冒險 " .. a, 1, 0.5, 0.45) end
    if o > 0 then tip:AddLine(ns.OrdersUI.tex("making") .. " 訂單 " .. o, 1, 0.82, 0) end
end)

A().onChanged = function()
    ns.coalesce("adventure-page", 1, function()
        UI.updateBadge()
        if ns.Framework.isModuleShown("adventure") then UI.refresh() end
    end)
end
