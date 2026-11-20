-- Export: copyable TSV and JSON, unchanged from v0.3.1 so the site's existing
-- admin import (gfguildroster.report schemaVersion 1) keeps working.
-- Manual export is the player's own choice and still includes zone/online.

local _, ns = ...
local str = ns.str

local Export = {}
ns.Export = Export
Export.PART_LIMIT = 14500 -- conservative EditBox text length per copyable part

function Export.timestampText(snapshot)
    if not snapshot then return "未取得" end
    if type(snapshot.capturedAtLocal) == "string" and snapshot.capturedAtLocal ~= "" then
        return snapshot.capturedAtLocal
    end
    if type(snapshot.capturedAt) == "number" then
        local t = ns.localTime(snapshot.capturedAt)
        if t ~= "" then return t end
    end
    return "未取得"
end

function Export.professionText(m)
    if type(m.professions) ~= "table" or #m.professions == 0 then return "未取得" end
    local text = table.concat(m.professions, "、")
    if m.professionSource == "cached" then text = text .. "（舊資料）" end
    return text
end

function Export.raceText(m)
    if not m.race or m.race == "" then return "未取得" end
    if m.raceSource == "cached" then return m.race .. "（舊資料）" end
    return m.race
end

local function safeCell(value)
    return (str(value):gsub("[\t\r\n]", " "))
end

local escaped = {
    ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
    ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
}
function Export.jsonString(value)
    local valueString = str(value)
    return '"' .. valueString:gsub('[%z\1-\31\\"]', function(ch)
        return escaped[ch] or string.format("\\u%04x", ch:byte())
    end) .. '"'
end
local jsonString = Export.jsonString

local function numberOrNull(value)
    return type(value) == "number" and tostring(value) or "null"
end

local function jsonMember(m)
    local prof = {}
    for _, p in ipairs(type(m.professions) == "table" and m.professions or {}) do
        prof[#prof + 1] = jsonString(p)
    end
    return table.concat({
        '{"name":', jsonString(m.name), ',"race":', jsonString(m.race),
        ',"raceID":', numberOrNull(m.raceID), ',"raceSource":', jsonString(m.raceSource),
        ',"class":', jsonString(m.class), ',"classToken":', jsonString(m.classToken),
        ',"professions":[', table.concat(prof, ","), '],"professionSource":', jsonString(m.professionSource),
        ',"level":', numberOrNull(m.level), ',"zone":', jsonString(m.zone),
        ',"onlineAtCapture":', tostring(m.online == true), ',"guildRank":', jsonString(m.guildRank), '}'
    })
end

local function chunkRows(rows)
    local parts, this, length = {}, {}, 0
    for _, row in ipairs(rows) do
        if #this > 0 and (length + #row + 2 > Export.PART_LIMIT) then
            parts[#parts + 1] = this
            this, length = {}, 0
        end
        this[#this + 1] = row
        length = length + #row + 2
    end
    if #this > 0 then parts[#parts + 1] = this end
    return parts
end

function Export.jsonParts(s)
    local encoded = {}
    for _, m in ipairs(s.members) do encoded[#encoded + 1] = jsonMember(m) end
    local groups, parts = chunkRows(encoded), {}
    for i, group in ipairs(groups) do
        parts[i] = table.concat({
            '{"schema":"gfguildroster.report","schemaVersion":1,"addonVersion":', jsonString(ns.VERSION),
            ',"guild":', jsonString(s.guild), ',"realm":', jsonString(s.realm),
            ',"capturedAtUnix":', numberOrNull(s.capturedAt),
            ',"capturedAtUTC":', jsonString(s.capturedAtUTC),
            ',"capturedAtLocal":', jsonString(Export.timestampText(s)),
            ',"total":', numberOrNull(s.total), ',"onlineAtCapture":', numberOrNull(s.online),
            ',"part":', tostring(i), ',"partCount":', tostring(#groups),
            ',"members":[', table.concat(group, ","), ']}'
        })
    end
    return parts
end

function Export.tsvParts(s)
    local header = "角色\t種族\t職業\t專業技能\t等級\t位置\t掃描時狀態\t掃描時間（本機）"
    local lines = {}
    for _, m in ipairs(s.members) do
        lines[#lines + 1] = table.concat({
            safeCell(m.name), safeCell(Export.raceText(m)), safeCell(m.class),
            safeCell(Export.professionText(m)), tostring(m.level or 0),
            safeCell(str(m.zone) ~= "" and m.zone or "未記錄"),
            m.online and "在線" or "離線", Export.timestampText(s)
        }, "\t")
    end
    local groups, parts = chunkRows(lines), {}
    for i, group in ipairs(groups) do
        parts[i] = header .. "\n" .. table.concat(group, "\n")
    end
    return parts
end
