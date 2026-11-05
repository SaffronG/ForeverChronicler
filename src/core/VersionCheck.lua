-- Forever Chronicler: tell players when a group member has a newer version
-- Your version is announced to your group when it changes (at most once a
-- minute). Anyone with an older version is told once per session that a newer
-- one exists; if you receive an older announcement, you answer by whisper so
-- that player learns about your newer version too.

local ADDON, FC = ...

local function metadata(field)
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return get and get(ADDON, field)
end
FC.version = metadata("Version") or "0.0.0"

-- "1.2.10" -> comparable table; anything non-numeric counts as 0
local function parse(v)
    local parts = {}
    for n in tostring(v):gmatch("%d+") do parts[#parts + 1] = tonumber(n) end
    return parts
end

-- -1 if a < b, 0 if equal, 1 if a > b
function FC.CompareVersions(a, b)
    local pa, pb = parse(a), parse(b)
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    return 0
end

local lastAnnounce, warned = 0, false

local function announce()
    local channel = FC:GroupChannel()
    if not channel or time() - lastAnnounce < 60 then return end
    lastAnnounce = time()
    FC:SendComm("VER", { v = FC.version }, channel)
end

FC:OnComm("VER", function(fields, sender)
    local theirs = fields.v
    if type(theirs) ~= "string" or #theirs > 20 or not theirs:match("^%d+[%.%d]*$") then return end
    local cmp = FC.CompareVersions(theirs, FC.version)
    if cmp > 0 and not warned then
        warned = true
        FC:Print(string.format("|cffffd100A newer version (%s) is available - you have %s. Ask %s for it, or download the latest release.|r",
            theirs, FC.version, FC.ShortName(sender)))
    elseif cmp < 0 and fields.reply ~= "1" then
        FC:SendComm("VER", { v = FC.version, reply = "1" }, "WHISPER", sender)
    end
end)

FC:RegisterEvent("GROUP_ROSTER_UPDATE", announce)
FC:On("READY", function() C_Timer.After(10, function() FC:SafeCall(announce) end) end)

FC:Command("version", "/chron version - show the addon version", function()
    FC:Print("Forever Chronicler " .. FC.version)
end, 96)
