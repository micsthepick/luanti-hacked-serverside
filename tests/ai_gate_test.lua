-- Deterministic API simulation; does not authenticate or connect real players.
local modpath = 'mods/ai_gate'
local dsl = dofile(modpath .. '/dsl.lua')
local count = 0
local function check(value, message)
    assert(value, message)
    count = count + 1
end
for _, text in ipairs({'', '|reverse()', 'reverse()|', 'reverse()||upper()',
    'reverse()| |upper()', 'rotate(10)', 'translate(%,a)', 'os.execute(x)',
    'reverse()|reverse()|reverse()|reverse()|reverse()', 'swap()', 'swap(1)',
    'swap(0,2)', 'swap(1,13)', 'swap(-1,2)', 'swap(1.5,2)', 'swap(1,a)',
    'swap(1,2,3)', string.rep('a', 161)}) do
    check(not dsl.parse(text), 'accepted invalid DSL: ' .. text)
end
check(dsl.apply(assert(dsl.parse('reverse()|rotate(-1)|swapcase()')), 'abC12') == 'A21cB', 'DSL semantics')
check(dsl.apply(assert(dsl.parse('swap(1,3)')), 'abcde')=='cbade', 'swap exact positions')
check(dsl.apply(assert(dsl.parse('swap(3,1)')), 'abcde')=='cbade', 'swap reversed indexes')
check(dsl.apply(assert(dsl.parse('swap(1,2)')), 'abcde')=='bacde', 'swap adjacent positions')
check(dsl.apply(assert(dsl.parse('swap(2,2)')), 'abcde')=='abcde', 'same position identity')
check(dsl.apply(assert(dsl.parse('swap(1,12)')), 'abcde')=='abcde', 'past-end identity')
check(dsl.apply(assert(dsl.parse('swap(10,12)')), 'abcdeABCDE12')=='abcdeABCD21E', 'swap at maximum index')
check(dsl.apply(assert(dsl.parse('swap(1,2)|reverse()')), 'abcde')=='edcab', 'swap composes left to right')
local seed = 43
function PcgRandom()
    return {next = function(_, lo, hi)
        seed = (seed * 48271) % 2147483647
        return lo + seed % (hi - lo + 1)
    end}
end
for _ = 1, 100 do
    local p = dsl.generate(PcgRandom())
    check(#p.public == 6 and #p.hidden == 12, 'test counts')
    check(dsl.verify(p.expression, p.hidden), 'generated solution')
end
check(dsl.verify('reverse()|reverse()', {{input='abC',output='abC'}}), 'equivalent solution')
local data, privs, online = {}, {}, {}
local callbacks, queue, forms, kicked, logs = {}, {}, {}, {}, {}
local settings = {ai_gate_grant_seconds="600"} -- obsolete setting cannot enable a bypass
local passes = {}
local packets, wire = {}, {}
local function encode(packet)
    packets[#packets+1]=packet
    return '{"fixture_packet":'..#packets..'}'
end
local function decode(message)
    local index=message:match('^%{"fixture_packet":(%d+)%}$')
    return index and packets[tonumber(index)]
end
local time, wall = 0, 2000000000
local real_time = os.time
os.time = function() return wall + math.floor(time) end
local function copy(t) local n = {}; for k,v in pairs(t) do n[k]=v end; return n end
local storage = {
    get_string=function(_, k) return data[k] or '' end,
    set_string=function(_, k,v) data[k]=v end,
    get_int=function(_, k) return tonumber(data[k]) or 0 end,
    set_int=function(_, k,v) data[k]=v end,
}
core = {
    write_json=encode, parse_json=decode,
    mod_channel_join=function(name)
        local c={messages={}}
        function c:is_writeable() return not self.closed end
        function c:leave() self.closed=true end
        function c:send_all(message) self.messages[#self.messages+1]=decode(message) end
        wire[name]=c
        return c
    end,
    register_on_modchannel_message=function(fn) callbacks.message=fn end,
    settings={get=function(_,key) return settings[key] end, get_bool=function() return true end},
    get_modpath=function() return modpath end, get_mod_storage=function() return storage end,
    get_us_time=function() return time*1000000 end,
    get_player_privs=function(n) return copy(privs[n]) end,
    change_player_privs=function(n, changes)
        for k,v in pairs(changes) do privs[n][k] = v or nil end
    end,
    formspec_escape=function(s) return s end,
    show_formspec=function(n,f,s) forms[n]={name=f, text=s} end,
    get_player_by_name=function(n) return online[n] end,
    after=function(delay, fn) queue[#queue+1]={at=time+delay, fn=fn} end,
    kick_player=function(n,reason) kicked[n]=reason end,
    log=function(_, message)
        logs[#logs+1]=message
        local name=message:match('^%[ai_gate%] PASS (.+)$')
        if name then passes[name]=(passes[name] or 0)+1 end
    end,
    chat_send_player=function() end,
    register_chatcommand=function(_, def) callbacks.reset=def.func end,
}
for _, event in ipairs({'prejoinplayer','joinplayer','leaveplayer','player_receive_fields','shutdown','dieplayer','respawnplayer'}) do
    core['register_on_'..event] = function(fn) callbacks[event]=fn end
end
local function loadmod() dofile(modpath .. '/init.lua') end
local function advance(delta)
    time=time+delta
    local again=true
    while again do
        again=false
        for i,job in ipairs(queue) do
            if job.at<=time then table.remove(queue,i); job.fn(); again=true; break end
        end
    end
end
local function join(name, interact)
    if not privs[name] then privs[name]={interact=interact or nil, shout=true} end
    local p={get_player_name=function() return name end}
    online[name]=p
    callbacks.joinplayer(p)
    advance(0.5)
    return p
end
local function answer(p, expression, form)
    callbacks.player_receive_fields(p, form or forms[p:get_player_name()].name,
        {submit=true, program=expression})
end
local function solution(name)
    for i=#logs,1,-1 do
        local expression=logs[i]:match('TEST SOLUTION for '..name..': (.*)')
        if expression then return expression end
    end
    error('no solution for '..name)
end
data['grant:pass']=os.time()+3600 -- legacy persistent grant is ignored, not deleted
local old_grant=data['grant:pass']
loadmod()
local p=join('pass',true)
check(not privs.pass.interact, 'interact revoked')
answer(p,solution('pass'))
check(privs.pass.interact and privs.pass.shout and not kicked.pass, 'success restores only interact')
local pass_count=passes.pass
answer(p,'invalid')
check(passes.pass==pass_count and not kicked.pass, 'duplicate ignored')
callbacks.leaveplayer(p); online.pass=nil
p=join('pass',true)
check(not privs.pass.interact, 'every reconnect revokes interact even with a legacy grant')
check(data['grant:pass']==old_grant, 'legacy grant storage preserved')
answer(p,solution('pass'))
check(privs.pass.interact and passes.pass==2, 'reconnect requires a second successful challenge')
callbacks.leaveplayer(p); online.pass=nil
local bad=join('bad',true)
answer(bad,'invalid')
check(kicked.bad and privs.bad.interact, 'failure restores privileges')
answer(bad,solution('bad'))
check(not data['grant:bad'], 'failed challenge cannot retry')
-- Old persisted cooldowns must not block immediate reconnects.
data['cooldown:bad']=os.time()+3600
check(not callbacks.prejoinplayer, 'retry delay hook removed')
callbacks.leaveplayer(bad); online.bad=nil; kicked.bad=nil
bad=join('bad',true)
answer(bad,solution('bad'))
check(not kicked.bad and passes.bad==1, 'immediate retry succeeds despite old cooldown')
local no=join('no',false)
answer(no,solution('no'))
check(not privs.no.interact and privs.no.shout, 'no escalation on success')
local exp=join('expire',true)
advance(4)
check(kicked.expire and privs.expire.interact, 'automatic expiry restores')
answer(exp,solution('expire'))
check(not data['grant:expire'], 'expired challenge cannot retry')
local leave=join('leave',true)
callbacks.leaveplayer(leave); online.leave=nil
check(privs.leave.interact, 'disconnect restores')
advance(5)
check(not kicked.leave, 'disconnected timer ignored')
-- A stale form from the preceding session must not consume a fresh challenge.
local old=join('replay',true)
local oldform=forms.replay.name
callbacks.leaveplayer(old); online.replay=nil
local fresh=join('replay',true)
answer(fresh,'invalid',oldform)
check(not kicked.replay, 'stale form consumed fresh challenge')
answer(fresh,solution('replay'))
check(privs.replay.interact and passes.replay==1, 'fresh form succeeds')
-- Simulate missed timer dispatch exactly at deadline.
local edge=join('edge',true)
time=time+4
answer(edge,solution('edge'))
check(kicked.edge and not data['grant:edge'] and privs.edge.interact, 'deadline equality accepted')
-- Simulated restart: persistent original privilege must survive lost Lua state.
join('crash',true)
queue={}; loadmod()
local crash=join('crash',true)
answer(crash,solution('crash'))
check(privs.crash.interact, 'restart recovery')
local denied=join('denied',false)
answer(denied,'invalid')
check(kicked.denied and not privs.denied.interact and privs.denied.shout, 'no escalation on failure')
join('denied_timeout',false)
advance(4)
check(kicked.denied_timeout and not privs.denied_timeout.interact, 'no escalation on timeout')
-- Mineclonia death handling may restore interact and replace the formspec.
local dead=join('death',true)
local death_form=forms.death.name
advance(1)
check(callbacks.dieplayer ~= nil and callbacks.respawnplayer ~= nil, 'death/respawn gate hooks installed')
callbacks.dieplayer(dead)
privs.death.interact=true -- emulate a later Mineclonia death callback
advance(0)
check(not privs.death.interact, 'death cannot restore interact while pending')
forms.death=nil -- engine death/respawn UI replaces the challenge
callbacks.respawnplayer(dead)
privs.death.interact=true -- emulate a later game callback
advance(0)
check(not privs.death.interact and forms.death.name==death_form, 'respawn restores same gate')
advance(3)
check(kicked.death and privs.death.interact and not data['grant:death'], 'respawn does not extend original deadline')
local dead_no=join('death_no',false)
callbacks.dieplayer(dead_no)
privs.death_no.interact=true
advance(0)
callbacks.respawnplayer(dead_no)
advance(0)
answer(dead_no,solution('death_no'))
check(not privs.death_no.interact, 'death does not overwrite original denied privilege')
local dead_pass=join('death_pass',true)
callbacks.dieplayer(dead_pass)
privs.death_pass.interact=true
advance(0)
callbacks.respawnplayer(dead_pass)
advance(0)
answer(dead_pass,solution('death_pass'))
check(privs.death_pass.interact and passes.death_pass==1, 'verification after respawn restores original interact')
callbacks.dieplayer(dead_pass)
callbacks.respawnplayer(dead_pass)
advance(0)
check(privs.death_pass.interact, 'verified players unaffected by death/respawn hooks')
-- Deferred work from an old session cannot affect a new session or a pass.
local race=join('death_race',true)
callbacks.respawnplayer(race)
answer(race,solution('death_race'))
advance(0)
check(privs.death_race.interact, 'deferred respawn cannot revoke after pass')
join('shutdown',true)
callbacks.shutdown()
check(privs.shutdown.interact, 'clean shutdown restoration')
for _,config in ipairs({{value='4',want=4},{value='99',want=4},
    {value='0',want=1},{value='nonsense',want=2}}) do
    settings.ai_gate_min_steps=config.value
    loadmod()
    local name='minimum'..config.value
    local player=join(name,true)
    check(forms[name].text:find('Minimum '..config.want..' steps',1,true), 'formspec advertises configured bound')
    check(#assert(dsl.parse(solution(name)))>=config.want, 'configured generation bound')
    answer(player,solution(name))
    check(privs[name].interact and passes[name]==1, 'configured reference passes')
end
settings.ai_gate_min_steps='2'
loadmod()
local function receive(name, packet, sender, channel)
    callbacks.message(channel or 'ai_gate:v1:'..name, sender or name, encode(packet))
end
local function hello(name) receive(name,{v=1,type='hello'}) end
local function reply(name,id,program) receive(name,{v=1,type='response',id=id,program=program}) end
local player=join('wire',true)
hello('wire')
local c=wire['ai_gate:v1:wire']
local packet=c.messages[1]
check(packet and packet.type=='challenge' and #packet.public==6, 'public challenge transported')
check(not packet.hidden and not packet.expression and packet.min_steps==2, 'private reference and tests not sent')
check(packet.dsl_version==2 and packet.max_index==12 and packet.index_base==1, 'swap capabilities advertised')
hello('wire'); advance(1); hello('wire')
check(#c.messages==1, 'hello cannot reissue or resend challenge')
reply('wire','stale','invalid')
receive('wire',{v=1,type='response',id=packet.id,program='invalid'},'pass','ai_gate:v1:wire')
check(not kicked.wire and not privs.wire.interact, 'stale ID and spoofed owner ignored')
reply('wire',packet.id,solution('wire'))
check(privs.wire.interact and passes.wire==1 and c.messages[2].passed, 'wire pass restores privilege')
reply('wire',packet.id,'invalid'); answer(player,'invalid')
check(not kicked.wire, 'one attempt shared by formspec and channel')
callbacks.leaveplayer(player)
check(c.closed, 'server leaves channel on disconnect')
local malformed=join('wire_bad',true); hello('wire_bad')
local badpacket=wire['ai_gate:v1:wire_bad'].messages[1]
reply('wire_bad',badpacket.id,nil)
reply('wire_bad',badpacket.id,solution('wire_bad'))
check(kicked.wire_bad and not data['grant:wire_bad'] and privs.wire_bad.interact, 'missing program consumes wire attempt')
local mixed=join('mixed',true); hello('mixed')
local mixedpacket=wire['ai_gate:v1:mixed'].messages[1]
answer(mixed,solution('mixed')); reply('mixed',mixedpacket.id,'invalid')
check(not kicked.mixed and passes.mixed==1, 'form answer consumes wire attempt')
local early={get_player_name=function() return 'early' end}
privs.early={interact=true}; online.early=early
callbacks.joinplayer(early); hello('early')
check(#wire['ai_gate:v1:early'].messages==0, 'early hello does not start deadline')
advance(0.5)
check(#wire['ai_gate:v1:early'].messages==1, 'challenge published when original deadline starts')
advance(4)
check(kicked.early and privs.early.interact, 'wire hello does not extend deadline')
local old_wire=join('wire_reconnect',true); hello('wire_reconnect')
local old_id=wire['ai_gate:v1:wire_reconnect'].messages[1].id
callbacks.leaveplayer(old_wire); online.wire_reconnect=nil
local new_wire=join('wire_reconnect',true); hello('wire_reconnect')
reply('wire_reconnect',old_id,'invalid')
check(not kicked.wire_reconnect and not privs.wire_reconnect.interact, 'wire old session ID cannot consume new challenge')
answer(new_wire,solution('wire_reconnect'))
local large=join('large',true); hello('large')
callbacks.message('ai_gate:v1:large','large',string.rep('x',2049))
callbacks.message('ai_gate:v1:large','large','invalid json')
check(not kicked.large and not privs.large.interact, 'oversized and invalid envelopes ignored')
answer(large,solution('large'))
data['grant:wire']=os.time()+3600
local legacy_grant=data['grant:wire']
local rejoined=join('wire',true); hello('wire')
local fresh_packet=wire['ai_gate:v1:wire'].messages[1]
check(fresh_packet.type=='challenge' and fresh_packet.id~=packet.id and not privs.wire.interact,
    'wire reconnect always issues fresh challenge despite legacy grant')
check(fresh_packet.remaining_ms==4000, 'wire deadline is exactly four seconds')
reply('wire',fresh_packet.id,solution('wire'))
check(privs.wire.interact and passes.wire==2 and data['grant:wire']==legacy_grant,
    'rejoined wire client must verify again without modifying legacy storage')
-- An answer just before the four-second boundary is accepted.
local boundary=join('before_deadline',true)
advance(3.999)
answer(boundary,solution('before_deadline'))
check(passes.before_deadline==1 and not kicked.before_deadline, 'answer before four seconds accepted')
check(forms.before_deadline.text:find('Time: 4s.',1,true), 'form advertises four-second deadline')
-- Expiry must kick even if the timer is dispatched a little early first.
local early_timer=join('timer_early',true)
local timer=table.remove(queue)
advance(3.5)
timer.fn()
check(not kicked.timer_early, 'early timer cannot reject before deadline')
advance(0.5)
check(kicked.timer_early=='AI gate: challenge timed out' and privs.timer_early.interact,
    'early timer re-arms and kicks at deadline without a submission')
-- Closing the form cannot stop expiry or require a submit event to kick.
local closed=join('closed_form',true)
callbacks.player_receive_fields(closed,forms.closed_form.name,{quit=true})
advance(4)
check(kicked.closed_form=='AI gate: challenge timed out', 'closed form still kicks at four seconds')
os.time=real_time
print('PASS '..count..' assertions (simulated Luanti API)')
