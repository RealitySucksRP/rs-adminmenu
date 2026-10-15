RSAdminBridge = RSAdminBridge or {}
local B=RSAdminBridge

local function firstStarted(list)
    for _,name in ipairs(list or {}) do
        if GetResourceState(name)=='started' then return name end
    end
end

function B.Status()
    local out={}
    for key,list in pairs(Config.Bridges or {}) do
        local provider=firstStarted(list)
        if key=='garage' and GetResourceState('rs-garage')=='started' then provider='rs-garage' end
        out[key]={provider=provider,state=provider and 'started' or 'unavailable'}
    end
    out.framework={provider=RSAdminServer and RSAdminServer.Adapter and RSAdminServer.Adapter.Framework() or 'standalone',state='started'}
    return out
end

function B.GetProperties(src)
    if Config.BridgeHooks and type(Config.BridgeHooks.properties)=='function' then
        local ok,rows=pcall(Config.BridgeHooks.properties,src)
        if ok and type(rows)=='table' then return true,rows end
        return false,rows
    end
    local provider=firstStarted((Config.Bridges or {}).housing)
    return false,('Housing provider %s is detected but no property adapter is configured'):format(provider or 'none')
end

function B.GiveVehicleKeys(src,vehicle)
    local A=RSAdminServer and RSAdminServer.Adapter
    if A and A.GiveKeys then return A.GiveKeys(src,vehicle) end
    return false,'vehicle keys provider unavailable'
end
