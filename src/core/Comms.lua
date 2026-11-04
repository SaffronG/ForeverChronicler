-- Forever Chronicaller: addon-to-addon messaging
--   FC:SendComm(type, fields, channel, target)  -- fields: table of string -> string/number/boolean
--   FC:OnComm(type, function(fields, sender, channel) ... end)
--
-- * Messages are split into chunks to fit the 255-byte addon message limit and
--   reassembled on the other side.
-- * Everything goes through an outgoing queue. Midnight-style restrictions block
--   addon messages in instances during encounters / M+ / PvP; queued messages
--   simply wait and are sent once messaging is allowed again.
-- * Only a few messages are sent per second to stay clear of throttling.
-- * Incoming data is untrusted: handlers must validate every field.

local _, FC = ...

local PREFIX = "FChron"
local PROTOCOL = "1"
local CHUNK = 200            -- payload bytes per message (header added on top)
local SEND_PER_TICK = 4      -- messages per second
local PARTIAL_TIMEOUT = 60   -- seconds to wait for missing chunks
local MAX_PAYLOAD = 4000     -- refuse to reassemble anything bigger

-- Encoding: k=v pairs joined by "~". % ~ = |, control characters and non-ASCII
-- bytes are %XX-escaped, so a chunk boundary can never split a UTF-8 character.
local function esc(s)
    return (tostring(s):gsub("[%%~=|%c\128-\255]", function(c) return string.format("%%%02X", c:byte()) end))
end
local function unesc(s)
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

function FC.EncodeFields(fields)
    local parts = {}
    for k, v in pairs(fields) do
        parts[#parts + 1] = esc(k) .. "=" .. esc(v)
    end
    table.sort(parts) -- deterministic, easier to test
    return table.concat(parts, "~")
end

function FC.DecodeFields(s)
    local fields = {}
    for pair in s:gmatch("[^~]+") do
        local k, v = pair:match("^([^=]*)=(.*)$")
        if not k then return nil end
        fields[unesc(k)] = unesc(v)
    end
    return fields
end

-- Outgoing queue ------------------------------------------------------------------
local queue, ticker = {}, nil
local msgCounter = 0

local function blocked()
    return C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
end

local function flush()
    local sent = 0
    while queue[1] and sent < SEND_PER_TICK do
        if blocked() then return end
        local m = queue[1]
        local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, m.text, m.channel, m.target)
        -- Older clients return true/false; newer ones return a result code (0 = success).
        local success = ok and (result == true or result == nil or result == 0
            or (Enum and Enum.SendAddonMessageResult and result == Enum.SendAddonMessageResult.Success))
        if not success then
            m.tries = (m.tries or 0) + 1
            if m.tries >= 30 then table.remove(queue, 1) end -- give up after ~30 s
            return
        end
        table.remove(queue, 1)
        sent = sent + 1
    end
    if not queue[1] and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function ensureTicker()
    if not ticker then
        ticker = C_Timer.NewTicker(1, function() FC:SafeCall(flush) end)
    end
end

function FC:SendComm(msgType, fields, channel, target)
    msgCounter = msgCounter + 1
    local id = string.format("%x%x", time() % 65536, msgCounter)
    local payload = FC.EncodeFields(fields)
    local total = math.max(1, math.ceil(#payload / CHUNK))
    for i = 1, total do
        local chunk = payload:sub((i - 1) * CHUNK + 1, i * CHUNK)
        table.insert(queue, {
            text = table.concat({ PROTOCOL, msgType, id, i, total, chunk }, "|"),
            channel = channel, target = target,
        })
    end
    FC:SafeCall(flush)
    if queue[1] then ensureTicker() end
    return id
end

function FC:PendingCommCount() return #queue end

-- The channel to reach your current group, or nil if you're not in one.
function FC:GroupChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE or 2) and not IsInGroup(LE_PARTY_CATEGORY_HOME or 1) then
        return "INSTANCE_CHAT"
    end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

-- Incoming ----------------------------------------------------------------------------
local handlers, partials = {}, {}

function FC:OnComm(msgType, fn)
    handlers[msgType] = handlers[msgType] or {}
    table.insert(handlers[msgType], fn)
end

local function shortName(name)
    if Ambiguate then return Ambiguate(name, "none") end
    return (name:gsub("%-.*$", ""))
end
FC.ShortName = shortName

local function isMe(sender)
    return shortName(sender) == UnitName("player")
end

FC:RegisterEvent("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
    if prefix ~= PREFIX or type(text) ~= "string" or type(sender) ~= "string" then return end
    if isMe(sender) and not FC.commLoopback then return end
    local proto, msgType, id, idx, total, chunk = text:match("^(%d+)|(%w+)|(%w+)|(%d+)|(%d+)|(.*)$")
    if proto ~= PROTOCOL or not handlers[msgType] then return end
    idx, total = tonumber(idx), tonumber(total)
    if idx < 1 or total < 1 or idx > total or total * CHUNK > MAX_PAYLOAD then return end

    local key = sender .. ":" .. id
    local p = partials[key]
    if not p then
        p = { parts = {}, count = 0, started = time() }
        partials[key] = p
    end
    if not p.parts[idx] then
        p.parts[idx] = chunk
        p.count = p.count + 1
    end
    if p.count < total then return end
    partials[key] = nil

    local fields = FC.DecodeFields(table.concat(p.parts, "", 1, total))
    if not fields then return end
    for _, fn in ipairs(handlers[msgType]) do
        FC:SafeCall(fn, fields, sender, channel)
    end

    -- forget half-received messages from people who left mid-way
    local now = time()
    for k, old in pairs(partials) do
        if now - old.started > PARTIAL_TIMEOUT then partials[k] = nil end
    end
end)

FC:On("READY", function()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    end
end)
FC.COMM_PREFIX = PREFIX
