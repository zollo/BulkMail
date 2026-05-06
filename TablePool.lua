-- TablePool.lua: Memory pool for table reuse

local mod = BulkMail

local new, del, newHash, newSet, deepDel
do
    local list = setmetatable({}, {__mode='k'})

    function new(...)
        local t = next(list)
        if t then
            list[t] = nil
            for i = 1, select('#', ...) do
                t[i] = select(i, ...)
            end
            return t
        else
            return { ... }
        end
    end

    function newHash(...)
        local t = next(list)
        if t then
            list[t] = nil
        else
            t = {}
        end
        for i = 1, select('#', ...), 2 do
            t[select(i, ...)] = select(i+1, ...)
        end
        return t
    end

    function newSet(...)
        local t = next(list)
        if t then
            list[t] = nil
        else
            t = {}
        end
        for i = 1, select('#', ...) do
            t[select(i, ...)] = true
        end
        return t
    end

    function del(t)
        for k in pairs(t) do
            t[k] = nil
        end
        list[t] = true
        return nil
    end

    function deepDel(t)
        if type(t) ~= "table" then
            return nil
        end
        for k,v in pairs(t) do
            t[k] = deepDel(v)
        end
        return del(t)
    end
end

mod.new     = new
mod.del     = del
mod.newHash = newHash
mod.newSet  = newSet
mod.deepDel = deepDel
