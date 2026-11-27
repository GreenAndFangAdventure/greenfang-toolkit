-- GuildAdmin (GF-001-Q, 0.12.5): guild management from the toolkit's
-- 「公會名冊」 page, as in the game's own guild window (owner: 「我希望公會清單
-- 上也能進行公會的設定操作（同原公會介面）」).
--
-- Only the game's own guild functions are called, and only from a click
-- (several of them need a hardware event). Each action shows only when the
-- client has the function AND the game says this character may do it
-- (CanGuildPromote, CanGuildRemove, ...), and the target's rank is below
-- ours. Removing and demoting ask first in the game's own confirm box.
--
-- Privacy (AGENTS §4, D-003): notes are read live from GetGuildRosterInfo
-- each time the page draws and kept only in memory. The officer note is
-- never stored in SavedVariables, never put into the outbox, never shared
-- or relayed, and is shown only when CanViewOfficerNote() is true.

local _, ns = ...
local str = ns.str

local G = {}
ns.GuildAdmin = G

-- Resolve "GuildPromote" or "C_PartyInfo.InviteUnit" to a function, or nil.
function G.fn(name)
    local v = _G
    for part in tostring(name):gmatch("[^%.]+") do
        if type(v) ~= "table" then return nil end
        v = v[part]
    end
    return type(v) == "function" and v or nil
end
function G.has(name) return G.fn(name) ~= nil end

-- Every function this page may use (同步與診斷 lists which the client has).
G.API = {
    "GuildInvite", "GuildPromote", "GuildDemote", "GuildUninvite",
    "GuildRosterSetPublicNote", "GuildRosterSetOfficerNote", "GuildSetMOTD", "GetGuildRosterMOTD",
    "GetGuildInfoText", "SetGuildInfoText",
    "CanGuildInvite", "CanGuildPromote", "CanGuildDemote", "CanGuildRemove",
    "CanEditPublicNote", "CanEditOfficerNote", "CanViewOfficerNote", "CanEditMOTD", "CanEditGuildInfo",
    "GuildControlGetNumRanks", "GuildControlGetRankName", "StaticPopup_Show", "InspectUnit", "CanInspect",
}

-- Permission -> { the game's check, the function the action calls }.
G.PERM = {
    invite = { "CanGuildInvite", "GuildInvite" },
    promote = { "CanGuildPromote", "GuildPromote" },
    demote = { "CanGuildDemote", "GuildDemote" },
    remove = { "CanGuildRemove", "GuildUninvite" },
    publicNote = { "CanEditPublicNote", "GuildRosterSetPublicNote" },
    officerNote = { "CanEditOfficerNote", "GuildRosterSetOfficerNote" },
    viewOfficer = { "CanViewOfficerNote" },
    motd = { "CanEditMOTD", "GuildSetMOTD" },
    info = { "CanEditGuildInfo", "SetGuildInfoText" },
}
-- Actions that change someone else ask first in the game's confirm box.
G.CONFIRM = { remove = true, demote = true }

local function truthy(v) return v == true or v == 1 end

-- May this character do it at all? Both functions must exist and the check say yes.
function G.can(perm)
    local p = G.PERM[perm]
    if not p then return false end
    for i = 2, #p do if not G.has(p[i]) then return false end end
    if G.CONFIRM[perm] and not G.has("StaticPopup_Show") then return false end
    local check = G.fn(p[1])
    if not check then return false end
    local ok, v = pcall(check)
    return ok and truthy(v)
end

-- My own rank index (0 = guild master), from the live roster.
function G.myRankIndex()
    local _, _, idx = ns.call(GetGuildInfo, "player")
    return ns.num(idx)
end
function G.lowestRankIndex()
    local n = ns.num(ns.call(GuildControlGetNumRanks))
    return n and (n - 1) or nil
end

---------------------------------------------------------------------------
-- Live roster entries (index, notes) by name: memory only, a few seconds.
---------------------------------------------------------------------------

local live = { at = -1, byName = {} }
function G.invalidate() live.at = -1 end
function G.live()
    local t = ns.now()
    if live.at >= 0 and t - live.at < 5 then return live.byName end
    local byName = {}
    local total = ns.num(ns.call(GetNumGuildMembers)) or 0
    local viewOfficer = G.can("viewOfficer")
    for i = 1, total do
        local ok, name, _, rankIndex, _, _, _, note, officerNote = pcall(GetGuildRosterInfo, i)
        name = ok and str(name) or ""
        if name ~= "" then
            byName[ns.keyName(name)] = {
                index = i, name = name, rankIndex = ns.num(rankIndex),
                note = str(note), officerNote = viewOfficer and str(officerNote) or nil,
            }
        end
    end
    live.at, live.byName = t, byName
    return byName
end
function G.entry(name) return G.live()[ns.keyName(name)] end
function G.notes(name)
    local e = G.entry(name)
    if not e then return "", nil end
    return e.note, e.officerNote
end

local function isSelf(m)
    local me = ns.Data.player().guid
    return m and ((me and m.guid == me) or false)
end

-- What I may do to member m (rank checks on top of the game's permissions).
function G.allowed(m, perm)
    if not m or not G.can(perm) then return false end
    if perm == "publicNote" or perm == "officerNote" then return true end
    if isSelf(m) then return false end
    local mine = G.myRankIndex()
    local e = G.entry(m.name)
    local theirs = (e and e.rankIndex) or ns.num(m.rankIndex)
    if not (mine and theirs) then return false end
    if perm == "promote" then return theirs - 1 > mine end -- never up to my own rank
    if perm == "demote" then
        local lowest = G.lowestRankIndex()
        return theirs > mine and (lowest == nil or theirs < lowest)
    end
    if perm == "remove" then return theirs > mine end
    return false
end

---------------------------------------------------------------------------
-- Actions (each only from a click)
---------------------------------------------------------------------------

function G.whisper(m)
    local name = str(m and m.name)
    if name == "" then return false end
    if G.has("ChatFrame_SendTell") then ChatFrame_SendTell(name); return true end
    if G.has("ChatFrame_OpenChat") then ChatFrame_OpenChat("/w " .. name .. " "); return true end
    return false
end

function G.inviteGroup(m)
    local name = str(m and m.name)
    local f = G.fn("C_PartyInfo.InviteUnit") or G.fn("InviteUnit")
    if name == "" or not f then return false end
    pcall(f, name)
    return true
end

function G.who(m)
    local name = ns.shortName(m and m.name)
    local f = G.fn("C_FriendList.SendWho") or G.fn("SendWho")
    if name == "" or not f then return false end
    pcall(f, 'n-"' .. name .. '"')
    return true
end

function G.canWho() return G.has("C_FriendList.SendWho") or G.has("SendWho") end

-- GF-UI-C (owner: 「查看」 did nothing): 查看 is the game's inspect window.
-- InspectUnit needs a unit token, and the game only has one for a guild
-- member who is my target, under the mouse, or in my party / raid; it must
-- also be close enough (CheckInteractDistance 1). Otherwise the button is
-- not shown at all (never a dead button).
G.UNITS = { "target", "mouseover", "focus" }
for i = 1, 4 do G.UNITS[#G.UNITS + 1] = "party" .. i end
for i = 1, 40 do G.UNITS[#G.UNITS + 1] = "raid" .. i end
function G.unitFor(m)
    local guid = m and str(m.guid)
    if not guid or guid == "" then return nil end
    for _, u in ipairs(G.UNITS) do
        local g = ns.call(UnitGUID, u)
        if g ~= nil and str(g) == guid then return u end
    end
    return nil
end
function G.canInspect(m)
    if isSelf(m) or not G.has("InspectUnit") then return false end
    local unit = G.unitFor(m)
    if not unit then return false end
    if G.has("CanInspect") then
        local ok, yes = pcall(CanInspect, unit, true)
        if not (ok and truthy(yes)) then return false end
    end
    if G.has("CheckInteractDistance") then
        local ok, near = pcall(CheckInteractDistance, unit, 1)
        if ok and not truthy(near) then return false end
    end
    return true
end
function G.inspect(m)
    if not G.canInspect(m) then return false end
    pcall(InspectUnit, G.unitFor(m))
    return true
end

-- GF-UI-C: rank number and name, "3 會員" (number = rank index + 1, as in the game's guild window).
function G.rankName(index)
    if not index then return "" end
    local name = str((ns.call(GuildControlGetRankName, index + 1)))
    return name
end
function G.rankLabel(index, fallback)
    if not index then return str(fallback) end
    local name = G.rankName(index)
    if name == "" then name = str(fallback) end
    return tostring(index + 1) .. (name ~= "" and (" " .. name) or "")
end
function G.rankOf(m)
    local e = m and G.entry(m.name)
    return (e and e.rankIndex) or ns.num(m and m.rankIndex)
end
function G.canWhisper() return G.has("ChatFrame_SendTell") or G.has("ChatFrame_OpenChat") end
function G.canInviteGroup() return G.has("C_PartyInfo.InviteUnit") or G.has("InviteUnit") end

-- The game's own confirm / edit boxes.
G.POPUP = { confirm = "GREENFANGTOOLKIT_GUILD_CONFIRM", edit = "GREENFANGTOOLKIT_GUILD_EDIT" }
local function dialogs()
    if type(StaticPopupDialogs) ~= "table" then return false end
    if not StaticPopupDialogs[G.POPUP.confirm] then
        StaticPopupDialogs[G.POPUP.confirm] = {
            text = "%s", button1 = "確定", button2 = "取消", timeout = 0, whileDead = true, hideOnEscape = true,
            OnAccept = function(_, data) if data and data.run then data.run() end end,
        }
        StaticPopupDialogs[G.POPUP.edit] = {
            text = "%s", button1 = "確定", button2 = "取消", hasEditBox = true, maxLetters = 31,
            timeout = 0, whileDead = true, hideOnEscape = true,
            OnShow = function(self, data)
                local box = self.editBox or self.EditBox
                if box and data then
                    if box.SetMaxLetters then box:SetMaxLetters(data.max or 31) end
                    box:SetText(data.text or "")
                    if box.HighlightText then box:HighlightText() end
                end
            end,
            OnAccept = function(self, data)
                local box = self.editBox or self.EditBox
                if data and data.save and box then data.save(str(box:GetText())) end
            end,
            EditBoxOnEnterPressed = function(box)
                local parent = box:GetParent()
                local data = parent and parent.data
                if data and data.save then data.save(str(box:GetText())) end
                if parent then parent:Hide() end
            end,
            EditBoxOnEscapePressed = function(box) local parent = box:GetParent(); if parent then parent:Hide() end end,
        }
    end
    return true
end

function G.confirm(text, run)
    if not dialogs() or not G.has("StaticPopup_Show") then return nil end
    return StaticPopup_Show(G.POPUP.confirm, text, nil, { run = run })
end
function G.edit(text, current, max, save)
    if not dialogs() or not G.has("StaticPopup_Show") then return nil end
    return StaticPopup_Show(G.POPUP.edit, text, nil, { text = current, max = max, save = save })
end

local function afterChange()
    G.invalidate()
    if ns.Roster and ns.Roster.request then ns.Roster.request() end
    if ns.UI and ns.UI.refresh and ns.Framework.isModuleShown("roster") then ns.UI.refresh() end
end

function G.promote(m)
    if not G.allowed(m, "promote") then return false end
    GuildPromote(m.name)
    afterChange()
    return true
end
function G.demote(m)
    if not G.allowed(m, "demote") then return false end
    return G.confirm("把 " .. ns.shortName(m.name) .. " 降一階？", function() GuildDemote(m.name); afterChange() end) ~= nil
end
function G.remove(m)
    if not G.allowed(m, "remove") then return false end
    return G.confirm("把 " .. ns.shortName(m.name) .. " 踢出公會？", function() GuildUninvite(m.name); afterChange() end) ~= nil
end
-- GF-FIX-E (review M-26): the roster index of name at this moment. The
-- cached index is checked against the live roster (GetGuildRosterInfo(index)
-- must still be that name); if it is not, the roster is read again once. nil =
-- not found: nothing is written (never onto someone else).
local function nameAt(i)
    local ok, n = pcall(GetGuildRosterInfo, i)
    n = ok and str(n) or ""
    return n ~= "" and ns.keyName(n) or nil
end
function G.liveIndex(name)
    local key = ns.keyName(name)
    local e = G.entry(name)
    if e and nameAt(e.index) == key then return e.index end
    G.invalidate()
    e = G.entry(name)
    if e and nameAt(e.index) == key then return e.index end
    return nil
end

-- Write a note through setter(index, text); the text is never kept (the
-- officer note stays out of SavedVariables and every upload).
local function writeNote(m, setter, what, text)
    local i = G.liveIndex(m.name)
    if not i then
        G.invalidate()
        ns.say("名冊剛變動，找不到 " .. ns.shortName(m.name) .. "，" .. what .. "沒有寫入；請再試一次。")
        return false
    end
    setter(i, text)
    afterChange()
    return true
end
G.writeNote = writeNote

function G.editPublicNote(m)
    if not G.allowed(m, "publicNote") then return false end
    local note = G.notes(m.name)
    return G.edit(ns.shortName(m.name) .. " 的公會註記", note, 31, function(text)
        writeNote(m, GuildRosterSetPublicNote, "公會註記", text)
    end) ~= nil
end
function G.editOfficerNote(m)
    if not G.allowed(m, "officerNote") then return false end
    local _, officer = G.notes(m.name)
    return G.edit(ns.shortName(m.name) .. " 的幹部註記", officer or "", 31, function(text)
        writeNote(m, GuildRosterSetOfficerNote, "幹部註記", text)
    end) ~= nil
end
function G.inviteGuild()
    if not G.can("invite") then return false end
    return G.edit("邀請入會：角色名字", "", 48, function(name)
        if name ~= "" then GuildInvite(name) end
    end) ~= nil
end
function G.editMOTD()
    if not G.can("motd") then return false end
    return G.edit("今日訊息", G.motd(), 128, function(text) GuildSetMOTD(text); afterChange() end) ~= nil
end
-- GF-UI-C (owner: the info is long): a large multi-line editor on the
-- roster page (UI.openInfoEditor); the one-line game box only as a fallback.
G.INFO_MAX = 500
function G.saveInfo(text)
    if not G.can("info") then return false end
    SetGuildInfoText(str(text):sub(1, 2000))
    afterChange()
    return true
end
function G.editInfo()
    if not G.can("info") then return false end
    if ns.UI and ns.UI.openInfoEditor then return ns.UI.openInfoEditor() ~= nil end
    return G.edit("公會資訊", G.infoText(), G.INFO_MAX, function(text) G.saveInfo(text) end) ~= nil
end
function G.motd() return str((ns.call(GetGuildRosterMOTD))) end
function G.infoText() return str((ns.call(GetGuildInfoText))) end

-- The game's guild window, for what the toolkit does not do (rank rights, ...).
function G.canOpenGameUI() return G.has("ToggleGuildFrame") or G.has("ToggleFriendsFrame") end
function G.openGameUI()
    if G.has("ToggleGuildFrame") then ToggleGuildFrame(); return "guild" end
    if G.has("ToggleFriendsFrame") then ToggleFriendsFrame(3); return "friends" end
    return nil
end

-- The actions for member m, in order: { key, text, icon, fn }. Only what may be done.
-- GF-UI-C (owner): bar = true are the everyday ones under the list (密語,
-- 組隊, 查看); the officer tools are only in the right-click menu.
G.ACTIONS = {
    { key = "whisper", text = "密語", bar = true, icon = "Interface\\Icons\\INV_Letter_15", ok = function() return G.canWhisper() end, fn = G.whisper },
    { key = "group", text = "組隊", bar = true, icon = "Interface\\Icons\\INV_Misc_GroupNeedMore", ok = function(m) return G.canInviteGroup() and not isSelf(m) end, fn = G.inviteGroup },
    { key = "inspect", text = "查看", bar = true, icon = "Interface\\Icons\\INV_Misc_Spyglass_02", ok = function(m) return G.canInspect(m) end, fn = G.inspect },
    { key = "promote", text = "升階", icon = "Interface\\Buttons\\UI-PlusButton-Up", ok = function(m) return G.allowed(m, "promote") end, fn = G.promote },
    { key = "demote", text = "降階", icon = "Interface\\Buttons\\UI-MinusButton-Up", ok = function(m) return G.allowed(m, "demote") end, fn = G.demote },
    { key = "publicNote", text = "公會註記", icon = "Interface\\Icons\\INV_Misc_Note_01", ok = function(m) return G.allowed(m, "publicNote") end, fn = G.editPublicNote },
    { key = "officerNote", text = "幹部註記", icon = "Interface\\Icons\\INV_Misc_Note_02", ok = function(m) return G.allowed(m, "officerNote") end, fn = G.editOfficerNote },
    { key = "remove", text = "踢出公會", icon = "Interface\\RaidFrame\\ReadyCheck-NotReady", ok = function(m) return G.allowed(m, "remove") end, fn = G.remove },
}
function G.actionsFor(m, barOnly)
    local out = {}
    for _, a in ipairs(G.ACTIONS) do
        local okA, yes = pcall(a.ok, m)
        if okA and yes and (not barOnly or a.bar) then out[#out + 1] = a end
    end
    return out
end
function G.barActions(m) return G.actionsFor(m, true) end

-- GF-UI-C: the menu text. 升階 / 降階 name the rank they lead to ("升階 ＞ 2 幹部").
function G.actionText(a, m)
    local r = G.rankOf(m)
    if a.key == "promote" and r then return a.text .. " ＞ " .. G.rankLabel(r - 1) end
    if a.key == "demote" and r then return a.text .. " ＞ " .. G.rankLabel(r + 1) end
    return a.text
end

-- The right-click menu: the current rank first (not clickable, when known),
-- then every action, text only (GF-UI-C item 12: no mixed icons).
function G.menuItems(m)
    local items = {}
    local r = G.rankOf(m)
    if r then items[#items + 1] = { text = "會階 " .. G.rankLabel(r, m and m.guildRank), header = true } end
    for _, a in ipairs(G.actionsFor(m)) do
        items[#items + 1] = { text = G.actionText(a, m), key = a.key, fn = function() a.fn(m) end }
    end
    return items
end

-- 同步與診斷: which functions the client has, and what this character may do.
function G.diagText()
    local have, missing = {}, {}
    for _, name in ipairs(G.API) do
        if G.has(name) then have[#have + 1] = name else missing[#missing + 1] = name end
    end
    local perms = {}
    for _, p in ipairs({ "invite", "promote", "demote", "remove", "publicNote", "officerNote", "viewOfficer", "motd", "info" }) do
        if G.can(p) then perms[#perms + 1] = p end
    end
    return string.format("函式 %d / %d 可用%s｜這個角色可以：%s",
        #have, #G.API, #missing > 0 and ("（沒有：" .. table.concat(missing, "、") .. "）") or "",
        #perms > 0 and table.concat(perms, "、") or "沒有管理權限")
end
