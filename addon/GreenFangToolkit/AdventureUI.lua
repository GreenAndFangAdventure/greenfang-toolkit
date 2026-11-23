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
-- Days between today (the player's clock) and t: 0 today, 1 tomorrow.
function UI.dayOffset(t)
    return math.floor((UI.dayStart(0, t) - UI.dayStart(0)) / 86400 + 0.5)
end
-- "23:00～02:00（隔天）"; "明天 00:30～02:30" when the start itself is tomorrow.
function UI.spanText(s, e)
    if not s then return "" end
    local text = UI.clock(s) .. "～" .. UI.clock(e)
    if e and UI.dayStart(0, e) ~= UI.dayStart(0, s) then text = text .. "（隔天）" end
    return text
end
function UI.startText(t)
    if UI.dayOffset(t) == 1 then return "明天 " .. UI.clock(t) end
    return UI.clock(t)
end

-- "⚡ 現在" / "今天 20:00～22:00" / "📖 2026/11/25 19:00～21:00"
function UI.timeText(v)
    if v.timeMode == "n" then return tex("now") .. " 現在" end
    if v.timeMode == "f" then return tex("future") .. " " .. UI.day(v.start) .. " " .. UI.spanText(v.start, v.finish) end
    local pre = UI.dayOffset(v.start) == 1 and "明天 " or ""
    return tex("today") .. " " .. pre .. UI.spanText(v.start, v.finish)
end

-- GF-002-C item 2: one entry per seat, in role order: { role, filled }.
-- Dungeon tickets: tank, healer, dps; quest tickets: one person per seat.
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

function UI.tagText(tags)
    local out = {}
    for _, k in ipairs(UI.TAG_KEYS) do
        if math.floor((tags or 0) / A().TAGS[k]) % 2 == 1 then out[#out + 1] = tex("tag_" .. k) end
    end
    return table.concat(out, "")
end
UI.TAG_NAME = { quest = "解任務", farm = "連刷", slow = "慢慢打", fast = "速刷", voice = "語音" }
function UI.tagNames(tags)
    local out = {}
    for _, k in ipairs(UI.TAG_KEYS) do
        if math.floor((tags or 0) / A().TAGS[k]) % 2 == 1 then out[#out + 1] = UI.TAG_NAME[k] end
    end
    return table.concat(out, "、")
end

-- GF-002-C items 3, 4: the short name next to the dungeon art; a quest
-- ticket shows the scroll and the number of quests (names in the tooltip).
function UI.destText(v)
    if v.dungeon then return ns.AdventureData.short(v.dungeon) end
    return "任務 " .. #v.quests
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

-- Tooltip lines for a ticket: the full destination, quest names, tags, the note.
function UI.ticketTooltip(v)
    local lines = {}
    if v.dungeon then
        local d = ns.AdventureData.byId[v.dungeon]
        lines[#lines + 1] = d and (d.name .. "  " .. UI.levelText(v.dungeon)) or v.dungeon
    end
    local log = A().questLog() or {}
    for _, q in ipairs(v.quests) do
        local info = log[tonumber(q) or q]
        lines[#lines + 1] = tex("quest") .. " " .. ((info and info.title) or ("#" .. tostring(q)))
    end
    local tags = UI.tagNames(v.tags)
    if tags ~= "" then lines[#lines + 1] = tags end
    if v.mode == "c" then lines[#lines + 1] = tex("consent") .. " 團長同意" end
    if v.note and v.note ~= "" then lines[#lines + 1] = v.note end
    return lines
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

local ROW_HEIGHT = ns.PAGE_ROW -- GF-002-F: 36
UI.ROW_WIDTH = 1030
local panel, scroll, content, summaryLine
local rowWidgets, shownRows = {}, {}
local popup, draft   -- the ticket window and its draft
local wpopup, wdraft -- the worker window and its draft

-- GF-002-F (owner: 「職工單設定後，沒看到」): my own worker ticket has its own
-- section on top (it was never listed: only other members' matching ones were).
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
    return out
end

-- The buttons a viewer gets on a ticket (R-6.3 – R-7.3, R-4.7, R-4.9).
function UI.buttonsFor(v)
    local my = S().selfAuthor()
    local out = {}
    if v.leader == my then
        if A().local_().reopen[v.id] then return { "reopen", "dismiss" } end
        if v.closed then return out end
        if #v.pending > 0 then out[#out + 1] = "approve" end
        if v.state == "departed" then out[#out + 1] = "done" else out[#out + 1] = "form" end
        out[#out + 1] = "remove"
        return out
    end
    if v.closed then return out end
    for _, i in ipairs(v.invited) do if i.a == my then return { "accept", "refuse" } end end
    for _, list in ipairs({ v.members, v.waitlist, v.pending }) do
        for _, x in ipairs(list) do if x.a == my then return { "withdraw" } end end
    end
    if v.state ~= "departed" then out[#out + 1] = "apply" end
    return out
end

UI.BUTTON = {
    apply = { icon = "apply", tip = "申請" }, withdraw = { icon = "no", tip = "撤回" },
    accept = { icon = "yes", tip = "接受" }, refuse = { icon = "no", tip = "拒絕" },
    approve = { icon = "yes", tip = "同意" }, form = { icon = "form", tip = "組隊" },
    done = { icon = "yes", tip = "完成" }, remove = { icon = "no", tip = "移除" },
    reopen = { icon = "reopen", tip = "重開" }, dismiss = { icon = "no", tip = "不要" },
    invite = { icon = "invite", tip = "邀請" },
    edit = { icon = "reopen", tip = "編輯" }, unregister = { icon = "no", tip = "移除" },
}

-- Press a ticket button. Returns a result (tests).
function UI.press(v, button, owner)
    local Adv = A()
    local r
    if button == "apply" then
        -- R-6.3: show the ticket's time first; ✓ confirms.
        if owner then
            return ns.showMenu(owner, { { text = UI.timeText(v) .. "  " .. tex("yes") .. " 申請", fn = function()
                Adv.worker(v.id, "apply"); UI.refresh()
            end } }) and "confirm" or "none"
        end
        r = Adv.worker(v.id, "apply")
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

-- Leader's menu on their own ticket: kick, approve, the admission mode (R-4.5, R-6.6).
function UI.leaderMenu(v)
    local items = {}
    local Adv = A()
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

-- Row columns (GF-002-F: 36 px rows, 32 px destination art, 16 px text; the
-- tags moved to the tooltip so the buttons keep room for their names).
UI.COL = { dest = 24, name = 62, time = 176, seats = 416, cls = 642, who = 668, buttons = 784 }

local function newRow(i)
    local C = UI.COL
    local row = CreateFrame("Frame", nil, content)
    row:SetSize(UI.ROW_WIDTH, ROW_HEIGHT)
    row.bg = row:CreateTexture(nil, "BACKGROUND"); row.bg:SetAllPoints()
    row.att = row:CreateTexture(nil, "ARTWORK"); row.att:SetSize(18, 18); row.att:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.dest = row:CreateTexture(nil, "ARTWORK"); row.dest:SetSize(ns.ICON, ns.ICON); row.dest:SetPoint("LEFT", row, "LEFT", C.dest, 0)
    local function text(x, w)
        local fs = row:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)
        fs:SetPoint("LEFT", row, "LEFT", x, 0); fs:SetWidth(w); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
        return fs
    end
    row.name = text(C.name, C.time - C.name - 6)
    row.time = text(C.time, C.seats - C.time - 6)
    row.roles = text(C.seats, C.cls - C.seats - 6)
    -- GF-002-C item 2: one icon per seat, bright when taken, grey when open.
    row.slots = {}
    for k = 1, UI.MAX_SLOTS do
        local s = row:CreateTexture(nil, "ARTWORK")
        s:SetSize(20, 20)
        s:SetPoint("LEFT", row, "LEFT", C.seats + (k - 1) * 22, 0)
        s:Hide()
        row.slots[k] = s
    end
    row.cls = row:CreateTexture(nil, "ARTWORK"); row.cls:SetSize(22, 22); row.cls:SetPoint("LEFT", row, "LEFT", C.cls, 0)
    row.off = row:CreateTexture(nil, "OVERLAY"); row.off:SetSize(12, 12); row.off:SetPoint("BOTTOMRIGHT", row.cls, "BOTTOMRIGHT", 3, -3)
    row.who = text(C.who, C.buttons - C.who - 6)
    row.buttons = {}
    UI.ROW_BUTTON_X = C.buttons
    for k = 1, 3 do
        local b = iconButton(row, ns.ROW_ICON, "yes", nil)
        b:SetPoint("LEFT", row, "LEFT", UI.ROW_BUTTON_X, 0) -- laid out by their names (fillRow)
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

local function fillWho(row, a)
    local m = A().member(a)
    if m and Icons.setClassIcon(row.cls, m.classToken) then row.cls:Show() else row.cls:Hide() end
    row.who:SetText(m and ns.shortName(m.name) or "?")
    local c = Icons.classColor(m and m.classToken)
    row.who:SetTextColor(c[1], c[2], c[3])
end

-- "影牙、墓地 +2" / "任務 3" / "全部任務"
function UI.workerDest(w)
    local names = {}
    for i, d in ipairs(w.dungeons or {}) do if i <= 2 then names[#names + 1] = ns.AdventureData.short(d) end end
    local text = table.concat(names, "、")
    if #(w.dungeons or {}) > 2 then text = text .. " +" .. (#w.dungeons - 2) end
    local q = w.allQuests and "全部任務" or (#(w.quests or {}) > 0 and ("任務 " .. #w.quests) or "")
    if text ~= "" and q ~= "" then return text .. "  " .. q end
    return text ~= "" and text or q
end
function UI.slotsText(slots)
    local out = {}
    for _, sl in ipairs(slots or {}) do
        out[#out + 1] = sl.now and (tex("now") .. " 現在") or ((UI.dayOffset(sl.s) == 1 and "明天 " or "") .. UI.spanText(sl.s, sl.e))
    end
    return table.concat(out, "  ")
end
function UI.rolesName(main, alt)
    return tex(main or "d", 20) .. " " .. UI.ROLE_NAME[main or "d"] .. (alt and ("／" .. tex(alt, 16) .. " " .. UI.ROLE_NAME[alt]) or "")
end

local function setButtons(row, list)
    for k, b in ipairs(row.buttons) do
        local spec = list[k]
        if spec then
            Icons.set(b.tex, UI.ICON[spec.icon] or spec.icon); b.tip = spec.tip; b.action = spec.action
            ns.OrdersUI.setLabel(b, spec.tip) -- GF-002-D: the name next to the icon
            b:SetScript("OnClick", spec.fn)
            b:Show()
        else b:Hide(); b.action = nil end
    end
    UI.flowButtons(row)
end

local function fillRow(row, data, i)
    row.bg:SetColorTexture(0.2, 0.15, 0.15, i % 2 == 0 and 0.35 or 0.09)
    local parts = { row.att, row.dest, row.name, row.time, row.roles, row.cls, row.who }
    row.view = nil
    row.mine = nil
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
    row.name:SetTextColor(1, 1, 1)
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
        fillWho(row, S().selfAuthor())
        row.off:Hide()
        setButtons(row, {
            { icon = "reopen", tip = "編輯", action = "edit", fn = function() UI.openWorker() end },
            { icon = "no", tip = "移除", action = "unregister", fn = function() A().removeWorker(); UI.refresh() end },
        })
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
            fn = function() A().leader(v.id, "invite", data.worker); UI.refresh() end } })
        return
    end
    local v = data.view
    row.view = v
    UI.setDest(row.dest, v)
    row.name:SetText(UI.destText(v))
    row.name:SetTextColor(v.closed and 0.5 or 1, v.closed and 0.5 or 1, v.closed and 0.5 or 1)
    row.time:SetText(UI.timeText(v))
    if v.closed then
        row.roles:SetText(tex(v.state == "done" and "yes" or "no") .. (v.state == "done" and " 完成" or " 取消"))
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
    fillWho(row, v.leader)
    -- R-4.7: the leader is offline (委託者離線中).
    if v.leaderOffline then setIcon(row.off, "offline") else row.off:Hide() end
    local list = {}
    for _, name in ipairs(UI.buttonsFor(v)) do
        local spec = UI.BUTTON[name]
        list[#list + 1] = { icon = spec.icon, tip = spec.tip, action = name, fn = function(self) UI.press(v, name, self) end }
    end
    setButtons(row, list)
end

-- GF-002-E: the row buttons follow each other by their measured names.
function UI.flowButtons(row)
    local shown = {}
    for _, b in ipairs(row.buttons) do if b:IsShown() then shown[#shown + 1] = b end end
    ns.OrdersUI.flow(row, shown, UI.ROW_BUTTON_X, 0, 10, "LEFT")
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
            else row:Hide(); row.view = nil; row.mine = nil end
        end
    end
end
function UI.rowFrames() return rowWidgets end
function UI.shownRows() return shownRows end

-- R-11.3: "🏰 SM 3 人想去 缺🩹".
-- GF-002-C item 9: dungeon art, the number of people, the missing role icons (no words).
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
    if not panel then return end
    shownRows = UI.pageRows()
    content:SetHeight(math.max(1, #shownRows * ROW_HEIGHT))
    UI.layoutRows()
    summaryLine:SetText(UI.summaryText())
    UI.emptyLine:SetText(#shownRows == 0 and "沒有冒險單" or "") -- GF-002-D
    if #A().pendingInvites() > 0 then UI.nextInvite:Show() else UI.nextInvite:Hide() end
end

local function build(p)
    -- GF-002-D: icon + name; GF-002-F: 16 px text, 20 px icons in the buttons.
    UI.newButton = ns.OrdersUI.textButton(p, tex("adventure", 20) .. " ＋冒險單")
    UI.newButton:SetPoint("TOPLEFT", p, "TOPLEFT", 24, -40)
    UI.newButton:SetScript("OnClick", function() UI.openTicket() end)
    UI.workerButton = ns.OrdersUI.textButton(p, tex("worker", 20) .. " ＋職工單")
    UI.workerButton:SetPoint("LEFT", UI.newButton, "RIGHT", 12, 0)
    UI.workerButton:SetScript("OnClick", function() UI.openWorker() end)
    summaryLine = ns.freeText(p:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
    summaryLine:SetPoint("LEFT", UI.workerButton, "RIGHT", 24, 0)
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
-- Times (R-4.2). GF-002-F: today's start times reach past midnight; the
-- future has the year; durations 1–5 hours.
---------------------------------------------------------------------------

-- Server time of 00:00 (the player's clock) dayOff days from the day of t (default now).
function UI.dayStart(dayOff, t)
    local skew = UI.skew()
    local localT = (t or S().serverNow()) - skew
    local d = date("*t", localT)
    local midnight = localT - (d.hour * 3600 + d.min * 60 + d.sec)
    return midnight + (dayOff or 0) * 86400 + skew
end

-- Times every 15 minutes from now (R-4.2).
-- GF-002-D: aligned to :00 :15 :30 :45 of the clock the player sees.
function UI.quarterTimes(from, count, step)
    step = step or 900
    local skew = UI.skew()
    local out = {}
    local t = math.ceil((from - skew) / step) * step + skew
    for i = 0, count - 1 do out[#out + 1] = t + i * step end
    return out
end
UI.DURATIONS = { 1, 2, 3, 4, 5 }
UI.TODAY_HOURS = 8 -- 今天: start times up to 8 hours ahead (past midnight too)

-- 今天: the next quarter, then every half hour for TODAY_HOURS.
function UI.todayStarts(now)
    now = now or S().serverNow()
    local first = UI.quarterTimes(now, 1)[1]
    local out = { first }
    local half = UI.quarterTimes(first + 1, 1, 1800)[1]
    while half <= now + UI.TODAY_HOURS * 3600 do
        out[#out + 1] = half
        half = half + 1800
    end
    return out
end

UI.TIME_NAME = { n = "現在", t = "今天", f = "之後" }
UI.TIME_KEY = { n = "now", t = "today", f = "future" }

---------------------------------------------------------------------------
-- New adventure ticket (R-4.1 – R-4.5, R-11.2: destination -> time -> 開單)
-- GF-002-F layout: field names in one column on the left, the controls from
-- one line on the right, 52 px rows, 32 px icons, no empty rows.
---------------------------------------------------------------------------

UI.TICKET_NAME = "GreenFangToolkit_AdventurePopup"

function UI.newDraft()
    local _, token = ns.call(UnitClass, "player")
    local main = A().defaultRoles(token)
    return { timeMode = "n", roles = { t = 1, h = 1, d = 3 }, size = 5, tags = 0, note = "", mode = "a",
        leaderRole = main, quests = {}, start = nil, finish = nil, dur = 2 }
end

UI.SUBMIT_ERROR = { ["no-destination"] = "請先選目的地", ["bad-time"] = "時間不對", ["too-far"] = "日期太遠",
    ["too-many"] = "冒險單太多了" }
function UI.submitTicket(d)
    d = d or draft
    if not d then return nil end
    local id, why = A().open(d)
    if id and popup then popup:Hide() end
    if not id and popup then popup.result:SetText(tex("no") .. " " .. (UI.SUBMIT_ERROR[why] or "沒有開成")) end
    UI.refresh()
    return id, why
end

local function destLabel(id, quests)
    if id then
        return ns.GameIcons.markup(ns.GameIcons.dungeonKey(id), 24) .. " " .. ns.AdventureData.short(id) .. "  " .. UI.levelText(id)
    end
    if quests and #quests > 0 then return tex("quest", 24) .. " 任務 " .. #quests end
    return nil
end

local function drawTicket()
    if not (popup and draft) then return end
    local f = popup
    f.dest:SetText(destLabel(draft.dungeon, draft.quests) or "選擇目的地")
    for _, m in ipairs({ "n", "t", "f" }) do ns.OrdersUI.setSelected(f.timeButtons[m], draft.timeMode == m) end
    local timed = draft.timeMode ~= "n"
    f.timeText:SetText(timed and UI.spanText(draft.start, draft.finish) or "")
    for _, b in ipairs({ f.startButton, f.durButton }) do b:SetEnabled(timed) end
    f.dayButton:SetEnabled(draft.timeMode == "f")
    f.startButton:SetText(timed and UI.startText(draft.start) or "－")
    f.durButton:SetText(timed and ((draft.dur or 2) .. " 小時") or "－")
    f.dayButton:SetText(draft.timeMode == "f" and UI.dayText(draft.start) or "－")
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
end
UI.drawTicket = drawTicket

function UI.changeCount(role, n)
    if role == "any" then draft.size = math.max(2, math.min(5, draft.size + n))
    else draft.roles[role] = math.max(0, math.min(5, draft.roles[role] + n)) end
    drawTicket()
end

UI.TICKET_FIELDS = { "目的地", "時間", "開始", "時長", "日期", "人數", "錄取", "標籤", "備註" }
function UI.openTicket()
    draft = UI.newDraft()
    if not popup then
        local f = ns.popupWindow(UI.TICKET_NAME, 740, 540)
        f:SetPoint("CENTER", 0, 40)
        f:EnableMouse(true)
        ns.exclusivePopup(f)
        if f.TitleText then f.TitleText:SetText("冒險單") end
        local O = ns.OrdersUI
        local FX = O.FIELD_X
        local X = O.controlX({ "目的地", "時間", "開始", "人數", "錄取", "標籤", "備註" })
        local function y(i) return -48 - (i - 1) * O.ROW_STEP end
        local field = O.fieldLabel
        f.controlX = X
        field(f, "目的地", FX, y(1) - 8)
        f.dest = O.textButton(f, "選擇目的地", function(self) UI.pickDestination(self) end, 320)
        f.dest:SetPoint("TOPLEFT", f, "TOPLEFT", X, y(1))
        field(f, "時間", FX, y(2) - 8)
        f.timeButtons = {}
        local list = {}
        for _, m in ipairs({ "n", "t", "f" }) do
            local b = iconButton(f, ns.ICON, UI.TIME_KEY[m], UI.TIME_NAME[m], function(self) UI.pickTime(self, m) end, UI.TIME_NAME[m])
            f.timeButtons[m] = b
            list[#list + 1] = b
        end
        local after = O.flow(f, list, X, y(2), 28)
        f.timeText = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
        f.timeText:SetPoint("TOPLEFT", f, "TOPLEFT", after + 8, y(2) - 8)
        -- 開始 / 時長 / 日期: always there (grey "－" for 現在), so no row jumps.
        f.startField = field(f, "開始", FX, y(3) - 8)
        f.startButton = O.textButton(f, "－", function(self) UI.pickStart(self) end, 130)
        f.startButton:SetPoint("TOPLEFT", f, "TOPLEFT", X, y(3))
        local x2 = X + 130 + 26
        f.durField = field(f, "時長", x2, y(3) - 8)
        f.durButton = O.textButton(f, "－", function(self) UI.pickDuration(self) end, 96)
        f.durButton:SetPoint("TOPLEFT", f, "TOPLEFT", x2 + ns.labelWidth("時長") + 8, y(3))
        local x3 = x2 + ns.labelWidth("時長") + 8 + 96 + 26
        f.dayField = field(f, "日期", x3, y(3) - 8)
        f.dayButton = O.textButton(f, "－", function(self) UI.pickDay(self) end, 180)
        f.dayButton:SetPoint("TOPLEFT", f, "TOPLEFT", x3 + ns.labelWidth("日期") + 8, y(3))
        -- 人數: 坦 1 ＋ －  補 1 ＋ －  輸出 3 ＋ － (one 人數 for quests).
        field(f, "人數", FX, y(4) - 8)
        f.roleGroups = {}
        local x = X
        for _, r in ipairs({ "t", "h", "d" }) do
            local g = {}
            g.icon = f:CreateTexture(nil, "ARTWORK"); g.icon:SetSize(ns.ICON, ns.ICON)
            g.icon:SetPoint("TOPLEFT", f, "TOPLEFT", x, y(4))
            ns.GameIcons.set(g.icon, UI.GAME[r])
            g.text = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
            g.text:SetPoint("TOPLEFT", f, "TOPLEFT", x + ns.ICON + 4, y(4) - 8)
            local bx = x + ns.ICON + 4 + ns.labelWidth("輸出 5") + 2
            g.plus = O.textButton(f, "＋", function() UI.changeCount(r, 1) end, nil, 34); g.plus.fieldNamed = UI.ROLE_NAME[r]
            g.plus:SetPoint("TOPLEFT", f, "TOPLEFT", bx, y(4) + 1)
            g.minus = O.textButton(f, "－", function() UI.changeCount(r, -1) end, nil, 34); g.minus.fieldNamed = UI.ROLE_NAME[r]
            g.minus:SetPoint("TOPLEFT", f, "TOPLEFT", bx + 38, y(4) + 1)
            f.roleGroups[r] = g
            x = bx + 38 + 34 + 24
        end
        local g = {}
        g.icon = f:CreateTexture(nil, "ARTWORK"); g.icon:SetSize(ns.ICON, ns.ICON)
        g.icon:SetPoint("TOPLEFT", f, "TOPLEFT", X, y(4))
        ns.GameIcons.set(g.icon, UI.GAME.any)
        g.text = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
        g.text:SetPoint("TOPLEFT", f, "TOPLEFT", X + ns.ICON + 4, y(4) - 8)
        local bx = X + ns.ICON + 4 + ns.labelWidth("隊員 5") + 2
        g.plus = O.textButton(f, "＋", function() UI.changeCount("any", 1) end, nil, 34); g.plus.fieldNamed = "人數"
        g.plus:SetPoint("TOPLEFT", f, "TOPLEFT", bx, y(4) + 1)
        g.minus = O.textButton(f, "－", function() UI.changeCount("any", -1) end, nil, 34); g.minus.fieldNamed = "人數"
        g.minus:SetPoint("TOPLEFT", f, "TOPLEFT", bx + 38, y(4) + 1)
        f.roleGroups.any = g
        field(f, "錄取", FX, y(5) - 8)
        f.direct = iconButton(f, ns.ICON, "direct", "直接錄取", function() draft.mode = "a"; drawTicket() end, "直接錄取")
        f.consent = iconButton(f, ns.ICON, "consent", "團長同意", function() draft.mode = "c"; drawTicket() end, "團長同意")
        O.flow(f, { f.direct, f.consent }, X, y(5), 32)
        f.modeButton = f.direct
        field(f, "標籤", FX, y(6) - 8)
        f.tagButtons = {}
        local tags = {}
        for _, k in ipairs(UI.TAG_KEYS) do
            local b = iconButton(f, ns.ICON, "tag_" .. k, UI.TAG_NAME[k], function()
                local bit = A().TAGS[k]
                if math.floor(draft.tags / bit) % 2 == 1 then draft.tags = draft.tags - bit else draft.tags = draft.tags + bit end
                drawTicket()
            end, UI.TAG_NAME[k])
            f.tagButtons[k] = b
            tags[#tags + 1] = b
        end
        O.flow(f, tags, X, y(6), 18)
        field(f, "備註", FX, y(7) - 8)
        f.note = ns.createFrame("EditBox", nil, f, "InputBoxTemplate"); f.note:SetSize(540, 30)
        if f.note.SetFontObject then f.note:SetFontObject(ns.LABEL_FONT) end
        f.note:SetPoint("TOPLEFT", f, "TOPLEFT", X + 6, y(7))
        f.note:SetAutoFocus(false)
        if f.note.SetMaxLetters then f.note:SetMaxLetters(A().NOTE_MAX) end
        f.note:SetScript("OnTextChanged", function(self) if draft then draft.note = A().cleanNote(self:GetText()) end end)
        f.note:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        f.result = ns.freeText(f:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)); f.result:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", FX, 24)
        if f.result.SetTextColor then f.result:SetTextColor(1, 0.4, 0.4) end
        f.go = O.textButton(f, tex("yes", 20) .. " 開單", function() UI.submitTicket() end, 120)
        f.go:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 18)
        f:Hide()
        popup = f
    end
    popup.note:SetText("")
    popup.result:SetText("")
    popup:Show()
    drawTicket()
    return draft
end
function UI.draft() return draft end

---------------------------------------------------------------------------
-- 選擇目的地 (GF-002-F, owner: 「目的地的圖請放大，且不應該有重疊」「副本建議
-- 等級請清楚」): its own window. The ticket / worker window steps aside while
-- it is open and comes back when it closes (a pick, ESC or a click outside),
-- so nothing is covered. Every dungeon: 48 px art, the short name and the
-- suggested levels, coloured white (fits), grey (too low), red (too high).
---------------------------------------------------------------------------

UI.GRID_NAME = "GreenFangToolkit_DungeonGrid"
UI.GRID_COLUMNS, UI.GRID_CELL_W, UI.GRID_CELL_H = 8, 100, 110
local grid

function UI.dungeonGrid(owner, onClick, isOn, onQuest, returnTo)
    if ns.Framework.closeMenu then ns.Framework.closeMenu() end
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
            b.label = ns.freeText(grid:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
            b.label:SetPoint("TOP", b, "BOTTOM", 0, -4)
            b.label:SetText(name)
            b.level = ns.freeText(grid:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT))
            b.level:SetPoint("TOP", b.label, "BOTTOM", 0, -2)
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
    local function mark(b)
        if isOn then ns.OrdersUI.setSelected(b, isOn(b.dungeon))
        else b.sel:Hide(); b.tex:SetAlpha(1); if b.tex.SetDesaturated then b.tex:SetDesaturated(false) end end
        if isOn and isOn(b.dungeon) then ns.GameIcons.set(b.badge, "yes") else b.badge:Hide() end
        b.label:SetTextColor(1, 1, 1)
    end
    for _, b in ipairs(grid.buttons) do
        ns.GameIcons.set(b.tex, ns.GameIcons.dungeonKey(b.dungeon))
        local r, g, bl = ns.GameIcons.levelColor(b.dungeon, level)
        b.level:SetTextColor(r, g, bl)
        b.levelColor = { r, g, bl }
        b.tip = nil -- the name and levels are written out; no tooltip over the grid
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
    return UI.dungeonGrid(owner, function(id) draft.dungeon = id; draft.quests = {}; drawTicket() end, nil,
        hasQuests and function() UI.pickQuests(owner) end or nil, popup)
end

function UI.pickQuests(owner)
    local items = {}
    local log = A().questLog()
    if log then
        local n = 0
        for id, q in pairs(log) do
            n = n + 1
            if n > 15 then break end
            local on = false
            for _, x in ipairs(draft.quests) do if x == id then on = true end end
            items[#items + 1] = { text = (on and (tex("yes") .. " ") or "") .. tex("quest") .. " " .. str(q.title), fn = function()
                draft.dungeon = nil
                for i, x in ipairs(draft.quests) do if x == id then table.remove(draft.quests, i); drawTicket(); return end end
                if #draft.quests < A().MAX_QUESTS then draft.quests[#draft.quests + 1] = id end
                drawTicket()
            end }
        end
    end
    items[#items + 1] = { text = tex("no") .. " 清除", fn = function() draft.dungeon = nil; draft.quests = {}; drawTicket() end }
    return UI.menu(owner, titled("任務", items))
end

-- 現在 / 今天 / 之後 choose the mode; 開始, 時長 and 日期 are their own buttons.
function UI.setFinish() if draft.start then draft.finish = draft.start + (draft.dur or 2) * 3600 end end

function UI.pickTime(owner, mode)
    draft.timeMode = mode
    draft.dur = draft.dur or 2
    if mode == "n" then draft.start, draft.finish = nil, nil
    elseif mode == "t" then
        draft.start = UI.todayStarts()[1]
    else
        draft.dayOff = draft.dayOff or 1
        draft.start = UI.dayStart(draft.dayOff) + 20 * 3600 -- 20:00 that day
    end
    UI.setFinish()
    drawTicket()
end

function UI.pickStart(owner)
    local items = {}
    if draft.timeMode == "f" then
        local base = UI.dayStart(draft.dayOff or 1)
        for h = 8, 23 do
            local t = base + h * 3600
            items[#items + 1] = { text = UI.clock(t), fn = function() draft.start = t; UI.setFinish(); drawTicket() end }
        end
    else
        for _, t in ipairs(UI.todayStarts()) do
            items[#items + 1] = { text = UI.startText(t), fn = function() draft.start = t; UI.setFinish(); drawTicket() end }
        end
    end
    return UI.menu(owner, titled("開始", items))
end

function UI.pickDuration(owner)
    local items = {}
    for _, h in ipairs(UI.DURATIONS) do
        items[#items + 1] = { text = h .. " 小時" .. (draft.start and ("  ～" .. UI.clock(draft.start + h * 3600)
            .. (UI.dayStart(0, draft.start + h * 3600) ~= UI.dayStart(0, draft.start) and "（隔天）" or "")) or ""),
            fn = function() draft.dur = h; UI.setFinish(); drawTicket() end }
    end
    return UI.menu(owner, titled("時長", items))
end

function UI.pickDay(owner)
    local items = {}
    for dayOff = 1, A().FUTURE_DAYS do
        items[#items + 1] = { text = UI.dayText(UI.dayStart(dayOff) + 43200), fn = function()
            local tod = draft.start and (draft.start - UI.dayStart(draft.dayOff or 1)) or 20 * 3600
            draft.dayOff = dayOff
            draft.start = UI.dayStart(dayOff) + tod
            UI.setFinish(); drawTicket()
        end }
    end
    return UI.menu(owner, titled("日期", items))
end

---------------------------------------------------------------------------
-- Worker ticket (R-5.1 – R-5.4). GF-002-F (owner: 「選擇的地城圖標與文字也都
-- 放大，且要清楚看出選了哪些」): the chosen dungeons are listed one by one
-- (32 px art and the name; a click removes one), then 「＋地城」.
---------------------------------------------------------------------------

UI.WORKER_NAME = "GreenFangToolkit_WorkerPopup"

function UI.newWorkerDraft()
    local mine = A().myWorker()
    if mine then return mine end
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

UI.CHIPS_PER_LINE = 5
function UI.drawWorker()
    if not (wpopup and wdraft) then return end
    local f = wpopup
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
        ns.OrdersUI.setLabel(c, ns.AdventureData.short(id))
        c:Show()
    end
    for i = #wdraft.dungeons + 1, #f.chips do f.chips[i]:Hide() end
    -- One after another, a new line every CHIPS_PER_LINE; 「＋地城」 last.
    local shown = {}
    for i = 1, #wdraft.dungeons do shown[#shown + 1] = f.chips[i] end
    shown[#shown + 1] = f.addDungeon
    for line = 0, math.ceil(#shown / UI.CHIPS_PER_LINE) - 1 do
        local part = {}
        for k = line * UI.CHIPS_PER_LINE + 1, math.min(#shown, (line + 1) * UI.CHIPS_PER_LINE) do part[#part + 1] = shown[k] end
        ns.OrdersUI.flow(f, part, X, f.dungeonY - line * 42, 16)
    end
    for _, r in ipairs(A().ROLES) do
        ns.OrdersUI.setSelected(f.mainRoles[r], wdraft.main == r)
        ns.OrdersUI.setSelected(f.altRoles[r], wdraft.alt == r)
    end
    f.quests:SetText(wdraft.allQuests and (tex("quest", 20) .. " 全部任務")
        or (#wdraft.quests > 0 and (tex("quest", 20) .. " 任務 " .. #wdraft.quests) or "選擇任務"))
    f.slots:SetText(UI.slotsText(wdraft.slots))
    UI.drawWorkerTitle()
end
local drawWorker = function() UI.drawWorker() end

UI.WORKER_FIELDS = { "地城", "任務", "職責", "副職責", "時段" }
function UI.openWorker()
    wdraft = UI.newWorkerDraft()
    if not wpopup then
        local f = ns.popupWindow(UI.WORKER_NAME, 740, 470)
        f:SetPoint("CENTER", 0, 40)
        f:EnableMouse(true)
        ns.exclusivePopup(f)
        local O = ns.OrdersUI
        local FX = O.FIELD_X
        local X = O.controlX(UI.WORKER_FIELDS)
        f.controlX = X
        local field = O.fieldLabel
        -- 地城 takes two lines of chips.
        f.dungeonY = -48
        local Y = { -48, -48 - 2 * 42 - 14, 0, 0, 0 }
        for i = 3, 5 do Y[i] = Y[i - 1] - O.ROW_STEP end
        field(f, "地城", FX, Y[1] - 8)
        f.chips = {}
        f.addDungeon = O.textButton(f, "＋地城", function(self) UI.pickWorkerDungeons(self) end, 96)
        f.addDungeon:SetPoint("TOPLEFT", f, "TOPLEFT", X, Y[1])
        field(f, "任務", FX, Y[2] - 8)
        f.quests = O.textButton(f, "選擇任務", function(self) UI.pickWorkerQuests(self) end, 220)
        f.quests:SetPoint("TOPLEFT", f, "TOPLEFT", X, Y[2])
        field(f, "職責", FX, Y[3] - 8)
        field(f, "副職責", FX, Y[4] - 8)
        f.mainRoles, f.altRoles = {}, {}
        local mains, alts = {}, {}
        for _, r in ipairs(A().ROLES) do
            local m = iconButton(f, ns.ICON, r, UI.ROLE_NAME[r], function()
                wdraft.main = r; if wdraft.alt == r then wdraft.alt = nil end; drawWorker()
            end, UI.ROLE_NAME[r])
            f.mainRoles[r] = m
            mains[#mains + 1] = m
            local a = iconButton(f, ns.ICON, r, UI.ROLE_NAME[r], function()
                wdraft.alt = (wdraft.alt == r or wdraft.main == r) and nil or r; drawWorker()
            end, UI.ROLE_NAME[r])
            f.altRoles[r] = a
            alts[#alts + 1] = a
        end
        O.flow(f, mains, X, Y[3], 40)
        O.flow(f, alts, X, Y[4], 40)
        f.roles = f.mainRoles.t
        field(f, "時段", FX, Y[5] - 8)
        f.slots = O.textButton(f, "現在", function(self) UI.pickWorkerSlots(self) end, 520)
        f.slots:SetPoint("TOPLEFT", f, "TOPLEFT", X, Y[5])
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
    local ok = A().setWorker(d)
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
    end, nil, wpopup)
end

function UI.pickWorkerQuests(owner)
    local items = { { text = (wdraft.allQuests and (tex("yes") .. " ") or "") .. tex("quest") .. " 全部任務",
        fn = function() wdraft.allQuests = not wdraft.allQuests; drawWorker() end } }
    local log = A().questLog()
    if log then
        local n = 0
        for id, q in pairs(log) do
            n = n + 1
            if n > 15 then break end
            local on = false
            for _, x in ipairs(wdraft.quests) do if x == id then on = true end end
            items[#items + 1] = { text = (on and (tex("yes") .. " ") or "") .. str(q.title), fn = function()
                for i, x in ipairs(wdraft.quests) do if x == id then table.remove(wdraft.quests, i); drawWorker(); return end end
                wdraft.quests[#wdraft.quests + 1] = id
                drawWorker()
            end }
        end
    end
    return UI.menu(owner, titled("任務", items))
end

function UI.pickWorkerRoles(owner)
    local items = {}
    for _, r in ipairs(A().ROLES) do
        items[#items + 1] = { text = tex(r) .. " " .. UI.ROLE_NAME[r], fn = function() wdraft.main = r; if wdraft.alt == r then wdraft.alt = nil end drawWorker() end }
    end
    for _, r in ipairs(A().ROLES) do
        items[#items + 1] = { text = "(" .. tex(r) .. ")", fn = function() wdraft.alt = (wdraft.alt == r or wdraft.main == r) and nil or r; drawWorker() end }
    end
    return UI.menu(owner, items)
end

-- 時段: 現在, or two hours from any start of 今天 (past midnight too).
function UI.pickWorkerSlots(owner)
    local items = { { text = tex("now") .. " 現在", fn = function() wdraft.slots = { { now = true } }; drawWorker() end } }
    for _, t in ipairs(UI.todayStarts()) do
        items[#items + 1] = { text = "+ " .. (UI.dayOffset(t) == 1 and "明天 " or "") .. UI.spanText(t, t + 7200), fn = function()
            local kept = {}
            for _, sl in ipairs(wdraft.slots) do if not sl.now then kept[#kept + 1] = sl end end
            if #kept < A().MAX_SLOTS then kept[#kept + 1] = { s = t, e = t + 7200 } end
            wdraft.slots = kept
            drawWorker()
        end }
    end
    return UI.menu(owner, UI.titled("時段", items))
end

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
