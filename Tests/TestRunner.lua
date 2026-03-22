--- Minimal test runner for offline Lua 5.4 testing.
-- @module TestRunner

local TestRunner = {}

local tests = {}
local passed = 0
local failed = 0
local errors = {}

function TestRunner.describe(name, fn)
    print("\n=== " .. name .. " ===")
    fn()
end

function TestRunner.it(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        print("  PASS: " .. name)
    else
        failed = failed + 1
        errors[#errors + 1] = { name = name, err = err }
        print("  FAIL: " .. name)
        print("        " .. tostring(err))
    end
end

function TestRunner.assertEqual(actual, expected, msg)
    if actual ~= expected then
        error((msg or "assertEqual") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

function TestRunner.assertTrue(value, msg)
    if not value then
        error((msg or "assertTrue") .. ": expected truthy, got " .. tostring(value), 2)
    end
end

function TestRunner.assertFalse(value, msg)
    if value then
        error((msg or "assertFalse") .. ": expected falsy, got " .. tostring(value), 2)
    end
end

function TestRunner.assertTableLength(tbl, expected, msg)
    local len = #tbl
    if len ~= expected then
        error((msg or "assertTableLength") .. ": expected length " .. tostring(expected) .. ", got " .. tostring(len), 2)
    end
end

function TestRunner.summary()
    print("\n========================================")
    print(string.format("Results: %d passed, %d failed", passed, failed))
    if #errors > 0 then
        print("\nFailures:")
        for _, e in ipairs(errors) do
            print("  - " .. e.name .. ": " .. tostring(e.err))
        end
    end
    print("========================================")
    return failed == 0
end

return TestRunner
