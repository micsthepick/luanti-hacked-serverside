-- An intentionally tiny string-transformation DSL. No dynamic Lua execution.
local M = {}

-- Expressions: reverse()|rotate(2)|swapcase()|translate(a,Z)
-- rotate(n) rotates LEFT by n characters (negative rotates right).
-- swap(i,j) uses 1-based indexes 1..12. If either is past the end, no-op.
function M.parse(text)
    if type(text) ~= "string" or #text == 0 or #text > 160 then
        return nil, "invalid program length"
    end
    if text:find("||", 1, true) or text:match("^%s*|")
            or text:match("|%s*$") then
        return nil, "empty operation"
    end

    local ops = {}
    for raw_item in text:gmatch("[^|]+") do
        local item = raw_item:match("^%s*(.-)%s*$")
        local name, args = item:match("^([a-z]+)%(([^()]*)%)$")
        if not name then
            return nil, "invalid syntax"
        end
        local op = {name = name}
        if name == "reverse" or name == "swapcase"
                or name == "upper" or name == "lower" then
            if args ~= "" then return nil, "unexpected arguments" end
        elseif name == "rotate" then
            if not args:match("^%-?%d+$") then
                return nil, "rotate expects integer"
            end
            op.n = tonumber(args)
            if not op.n or op.n < -9 or op.n > 9 then
                return nil, "rotation out of range"
            end
        elseif name == "swap" then
            local i, j = args:match("^(%d+),(%d+)$")
            op.i, op.j = tonumber(i), tonumber(j)
            if not op.i or not op.j or op.i < 1 or op.i > 12
                    or op.j < 1 or op.j > 12 then
                return nil, "swap expects two indexes from 1 to 12"
            end
        elseif name == "translate" then
            op.src, op.dst = args:match("^([A-Za-z0-9]),([A-Za-z0-9])$")
            if not op.src then
                return nil, "translate expects two ASCII characters"
            end
        else
            return nil, "unknown operation"
        end
        ops[#ops + 1] = op
        if #ops > 4 then return nil, "too many operations" end
    end
    if #ops == 0 then return nil, "empty program" end
    return ops
end

function M.apply(ops, input)
    local s = input
    for _, op in ipairs(ops) do
        if op.name == "reverse" then
            s = s:reverse()
        elseif op.name == "rotate" then
            if #s > 0 then
                local n = op.n % #s
                s = s:sub(n + 1) .. s:sub(1, n)
            end
        elseif op.name == "swap" then
            local i, j = math.min(op.i, op.j), math.max(op.i, op.j)
            if j <= #s and i ~= j then
                s = s:sub(1, i - 1) .. s:sub(j, j) .. s:sub(i + 1, j - 1)
                    .. s:sub(i, i) .. s:sub(j + 1)
            end
        elseif op.name == "swapcase" then
            s = s:gsub("[A-Za-z]", function(ch)
                if ch:match("%l") then return ch:upper() end
                return ch:lower()
            end)
        elseif op.name == "upper" then
            s = s:upper()
        elseif op.name == "lower" then
            s = s:lower()
        elseif op.name == "translate" then
            s = s:gsub(op.src, op.dst)
        else
            return nil
        end
    end
    return s
end

local alphabet = "abcdeABCDE12345"
local function sample(rng)
    local n = rng:next(8, 12)
    local chars = {}
    for i = 1, n do
        local j = rng:next(1, #alphabet)
        chars[i] = alphabet:sub(j, j)
    end
    return table.concat(chars)
end

local function candidate(rng, min_steps)
    local names = {"reverse", "rotate", "swapcase", "translate", "upper", "lower", "swap"}
    local program = {}
    for i = 1, rng:next(math.max(2, min_steps), math.max(3, min_steps)) do
        local name = names[rng:next(1, #names)]
        if name == "rotate" then
            local n = rng:next(1, 4)
            program[#program + 1] = "rotate(" .. n .. ")"
        elseif name == "swap" then
            -- Every generated input is at least eight characters long.
            local i, j = rng:next(1, 8), rng:next(1, 7)
            if j >= i then j = j + 1 end
            program[#program + 1] = "swap(" .. i .. "," .. j .. ")"
        elseif name == "translate" then
            -- Choose from common symbols so substitution is observable.
            local chars = "abcdeABCDE"
            local k = rng:next(1, #chars)
            local src = chars:sub(k, k)
            local m = rng:next(1, #chars)
            local dst = chars:sub(m, m)
            program[#program + 1] = "translate(" .. src .. "," .. dst .. ")"
        else
            program[#program + 1] = name .. "()"
        end
    end
    local expression = table.concat(program, "|")
    local ops = assert(M.parse(expression))
    local public, hidden = {}, {}
    for i = 1, 18 do
        local input = sample(rng)
        local test = {input = input, output = M.apply(ops, input)}
        if i <= 6 then
            public[#public + 1] = test
        else
            hidden[#hidden + 1] = test
        end
    end
    return {expression = expression, public = public, hidden = hidden}
end

-- Use the same analyser in standalone tests and in the engine sandbox.
local directory
if core and core.get_current_modname and core.get_modpath then
    directory = core.get_modpath(core.get_current_modname())
    if directory:sub(-1) ~= "/" and directory:sub(-1) ~= ":" then directory = directory .. "/" end
else
    local source = debug.getinfo(1, "S").source:sub(2)
    directory = source:match("^(.*[/\\])") or "./"
end
local complexity = dofile(directory .. "complexity.lua")(M)
M.has_shorter = complexity.has_shorter

function M.generate(rng, min_steps)
    min_steps = min_steps or 2
    assert(min_steps == math.floor(min_steps) and min_steps >= 1 and min_steps <= 4,
        "minimum steps must be an integer from 1 to 4")
    for _ = 1, 128 do
        local puzzle = candidate(rng, min_steps)
        local ops = assert(M.parse(puzzle.expression))
        -- Unknown (proof-budget exhaustion) must never count as a proof.
        if M.has_shorter(ops, min_steps) == false then
            puzzle.min_steps = min_steps
            return puzzle
        end
    end
    return nil, "could not prove minimum challenge complexity"
end

function M.verify(solution, hidden, min_steps, checkpoint)
    local ops = M.parse(solution)
    if not ops or #ops < (min_steps or 1) then return false end
    if min_steps and min_steps > 1 and M.has_shorter(ops, min_steps, nil, checkpoint) ~= false then
        return false
    end
    for _, test in ipairs(hidden) do
        if M.apply(ops, test.input) ~= test.output then
            return false
        end
    end
    return true
end

return M
