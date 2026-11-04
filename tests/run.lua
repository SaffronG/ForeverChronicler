-- Test runner: lua tests/run.lua   (from the repo root)
-- Each test gets a freshly loaded addon with a fake WoW API (tests/wow_stub.lua).

local dir = arg and arg[1] or "."
package.path = dir .. "/tests/?.lua;" .. package.path
local W = dofile(dir .. "/tests/wow_stub.lua")

local tests, failures = {}, 0
local function test(name, fn) table.insert(tests, { name = name, fn = fn }) end
_G.test = test
_G.setup = function(opts) return W.setup(dir, opts) end
_G.eq = function(actual, expected, what)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", what or "value", tostring(expected), tostring(actual)), 2)
    end
end
_G.ok = function(cond, what) if not cond then error((what or "condition") .. " failed", 2) end end

-- Load every tests/test_*.lua file
local files = {}
local p = io.popen('ls "' .. dir .. '/tests"')
for f in p:lines() do if f:match("^test_.*%.lua$") then table.insert(files, f) end end
p:close()
table.sort(files)
for _, f in ipairs(files) do dofile(dir .. "/tests/" .. f) end

for _, t in ipairs(tests) do
    local success, err = pcall(t.fn)
    if success then
        print("  ok   " .. t.name)
    else
        failures = failures + 1
        print("  FAIL " .. t.name .. "\n       " .. tostring(err))
    end
end
print(string.format("\n%d tests, %d failed", #tests, failures))
os.exit(failures == 0 and 0 or 1)
