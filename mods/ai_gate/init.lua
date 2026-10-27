local dsl = dofile(core.get_modpath("ai_gate") .. "/dsl.lua")
local storage = core.get_mod_storage()
local rng = PcgRandom(os.time() + (core.get_us_time() % 2147483647))

local deadline_seconds = math.max(2, math.min(300,
    tonumber(core.settings:get("ai_gate_deadline")) or 4))
local min_steps = tonumber(core.settings:get("ai_gate_min_steps")) or 2
if min_steps ~= min_steps or min_steps == math.huge or min_steps == -math.huge then
    min_steps = 2
end
min_steps = math.max(1, math.min(4, math.floor(min_steps)))
local debug_solutions = core.settings:get_bool("ai_gate_debug_solutions", false)

local pending = {}
local transport
local FORM = "ai_gate:challenge:"
local challenge_serial = 0
local function k(name) return name:lower() end
local function now() return core.get_us_time() / 1000000 end

-- Restore interact only if this mod had previously revoked it, including
-- after an unclean server shutdown. Leave all other privileges untouched.
local function restore(name)
    local key = "interact:" .. k(name)
    local original = storage:get_string(key)
    if original ~= "" then
        core.change_player_privs(name, {interact = (original == "yes")})
        storage:set_string(key, "")
    end
end

local function freeze_interaction(name)
    restore(name)  -- recover privileges if a previous server process crashed
    local privs = core.get_player_privs(name)
    storage:set_string("interact:" .. k(name), privs.interact and "yes" or "no")
    core.change_player_privs(name, {interact = false})
end

local function show(name, state)
    local challenge = state.puzzle
    local lines = {}
    for _, test in ipairs(challenge.public) do
        lines[#lines + 1] = test.input .. "  =>  " .. test.output
    end
    local instructions = {
        "Infer a DSL program from the examples.",
        "Operations run from left to right.",
        "rotate(n) moves n characters left.",
        "Minimum " .. min_steps .. " steps; maximum 4.",
        "Time: " .. deadline_seconds .. "s.",
        "You will be kicked when time expires.",
    }
    local labels = {}
    for i, sentence in ipairs(instructions) do
        labels[#labels + 1] = "label[0.4," .. (0.9 + (i - 1) * 0.4) .. ";" ..
            core.formspec_escape(sentence) .. "]"
    end
    local form =
        "formspec_version[6]size[12,10.8]no_prepend[]" ..
        "label[0.4,0.4;Luanti HACKED - Entry challenge]" ..
        table.concat(labels) ..
        "label[0.4,3.5;reverse() | rotate(n) | swap(i,j)]" ..
        "label[0.4,3.9;swapcase() | upper() | lower() | translate(a,b)]" ..
        "label[0.4,4.35;swap uses indexes 1 to 12.]" ..
        "label[0.4,4.75;Indexes past the string end leave it unchanged.]" ..
        "textarea[0.4,5.25;11.2,2.9;examples;Input => Output;" ..
            core.formspec_escape(table.concat(lines, "\n")) .. "]" ..
        "field[0.4,8.55;11.2,0.8;program;DSL solution (one submission);]" ..
        "field_close_on_enter[program;false]" ..
        "button_exit[4.0,9.65;4.0,0.75;submit;Submit solution]"
    core.show_formspec(name, state.formname, form)
end

local function reject(name, reason, id)
    id = id or (pending[name] and pending[name].formname)
    pending[name] = nil
    if id then transport.result(name, id, false) end
    restore(name)
    core.log("action", "[ai_gate] REJECT " .. name .. " (" .. reason .. ")")
    core.kick_player(name, "AI gate: " .. reason, true)
end

core.register_on_joinplayer(function(player)
    local name = player:get_player_name()
    restore(name)
    transport.join(name)

    freeze_interaction(name)
    local puzzle, err = dsl.generate(rng, min_steps)
    if not puzzle then
        core.log("error", "[ai_gate] " .. err)
        reject(name, "challenge unavailable; reconnect to retry")
        return
    end
    -- Bind forms to a single issued challenge, including across reconnects.
    challenge_serial = challenge_serial + 1
    local state = {puzzle = puzzle, deadline = nil,
        formname = FORM .. tostring(challenge_serial)}
    pending[name] = state

    core.after(0.5, function()
        if pending[name] ~= state or not core.get_player_by_name(name) then
            return
        end
        state.deadline = now() + deadline_seconds
        show(name, state)
        transport.publish(name, state)
        if debug_solutions then
            core.log("warning", "[ai_gate] TEST SOLUTION for " .. name ..
                ": " .. puzzle.expression)
        end
        local function expire()
            if pending[name] ~= state then return end
            local remaining = state.deadline - now()
            if remaining > 0 then
                -- Scheduler time can lead the monotonic deadline slightly.
                -- Re-arm rather than silently losing the timeout callback.
                core.after(math.max(0.01, remaining), expire)
                return
            end
            reject(name, "challenge timed out")
        end
        core.after(deadline_seconds, expire)
    end)
end)

-- Mineclonia death handlers (notably shields) can restore interact, and
-- the death UI can replace our form. Run after those callbacks, retaining
-- the original saved privilege, challenge and deadline across respawns.
local function reapply_gate(player, redisplay)
    local name = player:get_player_name()
    local state = pending[name]
    if not state then return end
    core.after(0, function()
        if pending[name] ~= state or not core.get_player_by_name(name) then
            return
        end
        if state.deadline and now() >= state.deadline then
            reject(name, "challenge timed out")
            return
        end
        -- Do not call freeze_interaction: that would overwrite the saved
        -- pre-challenge privilege with one changed by death/respawn handlers.
        core.change_player_privs(name, {interact = false})
        if redisplay and state.deadline then
            show(name, state)
        end
    end)
end

core.register_on_dieplayer(function(player)
    reapply_gate(player, false)
end)

core.register_on_respawnplayer(function(player)
    reapply_gate(player, true)
    -- Leave normal Mineclonia respawn positioning to its own callbacks.
end)

local function submit(name, id, program)
    local state = pending[name]
    if not state or id ~= state.formname then return end

    -- Both transports consume the same attempt before parsing or checking.
    pending[name] = nil
    if not state.deadline or now() >= state.deadline then
        reject(name, "challenge expired", id)
        return
    end
    if type(program) ~= "string"
            or not dsl.verify(program, state.puzzle.hidden, state.puzzle.min_steps) then
        reject(name, "incorrect solution", id)
        return
    end
    restore(name)
    transport.result(name, id, true)
    if core.close_formspec then core.close_formspec(name, state.formname) end
    core.log("action", "[ai_gate] PASS " .. name)
    core.chat_send_player(name, "AI gate passed. Access granted!")
end

transport = dofile(core.get_modpath("ai_gate") .. "/transport.lua")({
    pending=pending, now=now, submit=submit,
})

core.register_on_player_receive_fields(function(player, formname, fields)
    if fields.submit then submit(player:get_player_name(), formname, fields.program) end
end)

core.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    pending[name] = nil
    restore(name)
    transport.leave(name)
end)

core.register_on_shutdown(function()
    for name in pairs(pending) do
        restore(name)
    end
end)

core.log("action", "[ai_gate] loaded (" .. deadline_seconds .. "s deadline, minimum " .. min_steps .. " steps)")
