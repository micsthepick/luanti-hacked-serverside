-- Exact shorter-program search on the challenge input domain:
-- lengths 8..12 over abcdeABCDE12345. No execution of submitted code.
-- Every operation is either a position permutation or a per-character map.
-- Those two kinds commute. Unless the map is constant, equivalence requires
-- both parts to agree; hence their minimum operation counts add.
return function(dsl)
    local M = {}
    local domain = 'abcdeABCDE12345'
    local symbols = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    local char_ops = {{name='upper'}, {name='lower'}, {name='swapcase'}}
    local position_ops = {{name='reverse'}}
    for n=-9,9 do
        if n~=0 then position_ops[#position_ops+1]={name='rotate',n=n} end
    end
    local function position_key(ops)
        local values={}
        for n=8,12 do
            values[#values+1]=dsl.apply(ops, symbols:sub(1,n))
        end
        return table.concat(values,'|')
    end
    for i=1,12 do
        for j=i+1,12 do position_ops[#position_ops+1]={name='swap',i=i,j=j} end
    end
    local function transform_position(key, op)
        return (key:gsub('[^|]+', function(value) return dsl.apply({op},value) end))
    end
    local positions={[position_key({})]=0}
    local frontier={position_key({})}
    -- Store at most two steps, then undo each possible final operation when
    -- looking for a three-step equivalent. This avoids a cubic state table.
    for depth=1,2 do
        local next_frontier={}
        for _, key in ipairs(frontier) do
            for _, op in ipairs(position_ops) do
                local candidate=transform_position(key,op)
                if positions[candidate]==nil then
                    positions[candidate]=depth
                    next_frontier[#next_frontier+1]=candidate
                end
            end
        end
        frontier=next_frontier
    end
    local function position_cost(ops)
        local key=position_key(ops)
        if positions[key]~=nil then return positions[key] end
        for _, op in ipairs(position_ops) do
            local inverse=op
            if op.name=='rotate' then inverse={name='rotate',n=-op.n} end
            if positions[transform_position(key,inverse)]~=nil then return 3 end
        end
        -- No equivalent below four steps exists. That's all the proof needs.
        return 4
    end

    local function compatible(current, target)
        -- Character maps can merge classes but can never split them again.
        local classes={}
        for i=1,#domain do
            local from,to=current:sub(i,i),target:sub(i,i)
            if classes[from] and classes[from]~=to then return false end
            classes[from]=to
        end
        return true
    end
    local function one_step(current,target)
        for _, op in ipairs(char_ops) do
            if dsl.apply({op},current)==target then return true end
        end
        local src,dst
        for i=1,#domain do
            local a,b=current:sub(i,i),target:sub(i,i)
            if a~=b then
                if src and (src~=a or dst~=b) then return false end
                src,dst=a,b
            end
        end
        return src and dsl.apply({{name='translate',src=src,dst=dst}},current)==target
    end

    -- true = a shorter equivalent exists; false = exhaustively ruled out;
    -- nil = proof budget exhausted (caller must discard this candidate).
    function M.has_shorter(ops, minimum, budget, checkpoint)
        local positional,chars={},{}
        for _, op in ipairs(ops) do
            local part=(op.name=='reverse' or op.name=='rotate' or op.name=='swap') and positional or chars
            part[#part+1]=op
        end
        local target=dsl.apply(chars,domain)
        local cost=position_cost(positional)
        -- A constant character map would make position irrelevant. Such maps
        -- are not reachable in four operations on this 15-character domain,
        -- but handle the case explicitly to preserve the search invariant.
        if target==string.rep(target:sub(1,1),#domain) then cost=0 end
        local remaining=minimum-1-cost
        if remaining<0 then return false end
        local visited,examined={},0
        budget=budget or 50000
        local function search(current, depth)
            examined=examined+1
            if checkpoint and examined % 128 == 0 then checkpoint() end
            if examined>budget then return nil end
            if current==target then return true end
            if depth==0 or not compatible(current,target) then return false end
            if depth==1 then return not not one_step(current,target) end
            local key=current..':'..depth
            if visited[key] then return false end
            visited[key]=true
            local function try(next_value)
                if next_value==current then return false end
                return search(next_value,depth-1)
            end
            for _, op in ipairs(char_ops) do
                local found=try(dsl.apply({op},current))
                if found~=false then return found end
            end
            local sources={}
            for i=1,#current do sources[current:sub(i,i)]=true end
            for src in pairs(sources) do
                for i=1,#symbols do
                    local dst=symbols:sub(i,i)
                    if src~=dst then
                        local found=try(dsl.apply({{name='translate',src=src,dst=dst}},current))
                        if found~=false then return found end
                    end
                end
            end
            return false
        end
        return search(domain,remaining)
    end
    return M
end
