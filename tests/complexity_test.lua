local dsl=dofile('mods/ai_gate/dsl.lua')
local count=0
local function check(v,message) assert(v,message);count=count+1 end
local function shorter(text,minimum) return dsl.has_shorter(assert(dsl.parse(text)),minimum) end
for _, expression in ipairs({'reverse()|reverse()', 'upper()|lower()',
    'swapcase()|upper()', 'rotate(2)|rotate(3)',
    'swap(1,2)|swap(2,1)', 'swap(1,12)|swap(12,1)', 'swap(3,3)|reverse()',
    'translate(a,Z)|translate(Z,b)', 'lower()|lower()|lower()|lower()'}) do
    check(shorter(expression,2)==true,'failed to collapse '..expression)
end
check(shorter('rotate(9)|rotate(9)',2)==false,'large rotation needs two steps across lengths')
check(shorter('reverse()|rotate(3)',2)==false,'reverse and rotation are distinct')
check(shorter('reverse()|rotate(3)|upper()',3)==false,'three irreducible steps')
check(shorter('reverse()|rotate(3)|upper()|translate(A,b)',4)==false,'four irreducible steps')
check(shorter('translate(a,Z)|translate(b,a)|translate(Z,b)',3)==false,'temporary character swap needs three steps')
check(shorter('reverse()|rotate(3)',3)==true,'two steps cannot claim three')
check(dsl.has_shorter(assert(dsl.parse('upper()')),2,0)==nil,'budget exhaustion is unknown')
local seed=93
local rng={next=function(_,lo,hi) seed=seed*48271%2147483647;return lo+seed%(hi-lo+1) end}
local generated_swap=false
for minimum=1,4 do
    for _=1,25 do
        local puzzle,err=dsl.generate(rng,minimum)
        check(puzzle~=nil,err)
        local ops=assert(dsl.parse(puzzle.expression))
        if puzzle.expression:find('swap(',1,true) then generated_swap=true end
        check(#ops>=minimum and #ops<=4,'generated operation count')
        check(puzzle.min_steps==minimum,'challenge minimum recorded')
        check(shorter(puzzle.expression,minimum)==false,'shorter equivalent exists')
        check(dsl.verify(puzzle.expression,puzzle.hidden,minimum),'reference rejected')
    end
end
check(generated_swap,'generator includes positional swaps')
-- Independent enumeration of every legal one-op program for a generated
-- two-step challenge, using a varied set of domain witnesses.
local puzzle=assert(dsl.generate(rng,2))
local reference=assert(dsl.parse(puzzle.expression))
local alphabet='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
local domain='abcdeABCDE12345'
local witnesses={}
for i=1,#domain do witnesses[#witnesses+1]=string.rep(domain:sub(i,i),8) end
for length=8,12 do
    for offset=0,#domain-1 do
        local input=''
        for j=1,length do local n=(j+offset-1)%#domain+1;input=input..domain:sub(n,n) end
        witnesses[#witnesses+1]=input
    end
end
local tests={}
for _,input in ipairs(witnesses) do tests[#tests+1]={input=input,output=dsl.apply(reference,input)} end
local function ruled_out(expression)
    check(not dsl.verify(expression,tests),'independent one-op shortcut: '..expression)
end
for _,op in ipairs({'reverse()','upper()','lower()','swapcase()'}) do ruled_out(op) end
for n=-9,9 do ruled_out('rotate('..n..')') end
for i=1,12 do
    for j=1,12 do ruled_out('swap('..i..','..j..')') end
end
for i=1,#alphabet do
    for j=1,#alphabet do ruled_out('translate('..alphabet:sub(i,i)..','..alphabet:sub(j,j)..')') end
end
local hidden={{input='abcdeABCDE',output='EDCBAedcba'}}
check(dsl.verify('reverse()',hidden,1),'one-step reference works')
check(not dsl.verify('reverse()',hidden,2),'one-op submission must be rejected')
check(not dsl.verify('reverse()|rotate(0)',hidden,2),'padding must not meet semantic minimum')
check(not dsl.verify('reverse()|reverse()|reverse()',hidden,3),'cancellation must not meet semantic minimum')
check(shorter('swap(1,2)|swap(3,4)',2)==false,'two disjoint swaps need two operations')
check(shorter('swap(1,2)|swap(3,4)|swap(5,6)',3)==false,'three disjoint swaps need three operations')
check(shorter('swap(1,2)|swap(3,4)|swap(5,6)',4)==true,'inverse lookup finds three-step positional equivalent')
check(shorter('swap(1,2)|swap(2,3)|swap(1,2)',3)==true,'swap conjugation collapses to one swap')
check(shorter('swap(1,12)',2)==true,'one length-dependent swap is one operation')
-- Independent exhaustive search of all positional programs of length <=2.
local position_expressions={'reverse()'}
for n=-9,9 do position_expressions[#position_expressions+1]='rotate('..n..')' end
for i=1,12 do
    for j=i+1,12 do position_expressions[#position_expressions+1]='swap('..i..','..j..')' end
end
local target_ops=assert(dsl.parse('swap(1,2)|swap(3,4)|swap(5,6)'))
local samples={'abcdefgh','abcdefghi','abcdefghij','abcdefghijk','abcdefghijkl'}
local function signature(ops)
    local outputs={}
    for i,input in ipairs(samples) do outputs[i]=dsl.apply(ops,input) end
    return table.concat(outputs,'|')
end
local target_signature=signature(target_ops)
for _,a in ipairs(position_expressions) do
    for _,b in ipairs(position_expressions) do
        check(signature(assert(dsl.parse(a..'|'..b)))~=target_signature,
            'three swaps reduced by independent positional search')
    end
end
local unavailable=dsl.generate({next=function(_,lo) return lo end},2)
check(unavailable==nil,'repeated reducible candidates must fail closed')
print('PASS '..count..' logical complexity assertions')
