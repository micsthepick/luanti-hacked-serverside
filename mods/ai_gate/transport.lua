-- Transport only: authentication, pending state and validation belong to init.lua.
return function(api)
    local T = {}
    if not core.mod_channel_join or not core.register_on_modchannel_message
            or not core.settings:get_bool('enable_mod_channels', false) then
        function T.join() end
        function T.leave() end
        function T.publish() end
        function T.result() end
        return T
    end
    local prefix = 'ai_gate:v1:'
    local connections = {}
    local function send(name, payload)
        local c = connections[name]
        if c and c.channel:is_writeable() then
            c.channel:send_all(core.write_json(payload))
        end
    end
    function T.join(name)
        T.leave(name)
        connections[name] = {channel = core.mod_channel_join(prefix .. name)}
    end
    function T.leave(name)
        local c = connections[name]
        if c then c.channel:leave(); connections[name] = nil end
    end
    function T.publish(name, state)
        local c = connections[name]
        if not c or not c.ready or not state.deadline or state.transport_sent
                or not c.channel:is_writeable() then return end
        local remaining = math.floor((state.deadline - api.now()) * 1000)
        if remaining <= 0 then return end
        state.transport_sent = true
        send(name, {v=1, type='challenge', id=state.formname, dsl_version=2,
            remaining_ms=remaining, min_steps=state.puzzle.min_steps,
            max_steps=4, max_program_bytes=160, index_base=1, max_index=12,
            swap_out_of_range='identity', public=state.puzzle.public})
    end
    function T.result(name, id, passed)
        send(name, {v=1, type='result', id=id, passed=passed})
    end
    core.register_on_modchannel_message(function(channel_name, sender, message)
        -- Sender is engine-authenticated. Channel names and payload names
        -- are not proof of identity; never act on another player's channel.
        local c = connections[sender]
        if not c or channel_name ~= prefix .. sender
                or not core.get_player_by_name(sender)
                or type(message) ~= 'string' or #message > 2048 then return end
        local time = api.now()
        if not c.window or time - c.window >= 1 then c.window=time; c.count=0 end
        c.count = c.count + 1
        if c.count > 20 then return end
        local ok, packet = pcall(core.parse_json, message)
        if not ok or type(packet) ~= 'table' or packet.v ~= 1 then return end
        local state = api.pending[sender]
        if packet.type == 'hello' then
            if c.last_hello and time - c.last_hello < 1 then return end
            c.last_hello = time
            c.ready = true
            if state then T.publish(sender, state) end
        elseif packet.type == 'response' and state and packet.id == state.formname then
            -- A matching envelope consumes the attempt even if program is missing,
            -- oversized or invalid. Unknown IDs never consume a new challenge.
            api.submit(sender, packet.id, packet.program)
        end
    end)
    return T
end
