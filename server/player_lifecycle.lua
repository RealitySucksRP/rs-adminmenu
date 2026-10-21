local C=RSAdminCore
local A=RSAdminServer.Adapter
local ready,unload,observed,generation={},{},{},{}

function C.CharacterIdentity(src)
    if not GetPlayerName(src) then return end
    local framework=A.Framework()
    local data=A.GetPlayerData(src)
    if framework=='qbox' or framework=='qbcore' then
        if not data or not data.citizenid then return end
        if framework=='qbox' then
            local player=Player(src)
            if not player or player.state.isLoggedIn~=true then return end
        end
        return 'character:'..data.citizenid
    end
    if framework=='esx' then return data and data.identifier and ('character:'..data.identifier) end
    for _,id in ipairs(C.Identifiers(src)) do if id:sub(1,8)=='license:' then return id end end
    return C.Identifiers(src)[1]
end

function C.SessionIdentity(src)
    local character=C.CharacterIdentity(src)
    if character then return tostring(generation[src] or 0)..':'..character end
end

function C.OnCharacterReady(name,fn) ready[name]=fn end
function C.OnCharacterUnload(name,fn) unload[name]=fn end
local function notify(callbacks,src)
    for name,fn in pairs(callbacks) do
        local ok,e=pcall(fn,src)
        if not ok then print(('[rs-adminmenu] Character sync %s failed: %s'):format(name,e)) end
    end
end
function C.PollCharacter(src,force)
    local key=C.SessionIdentity(src)
    if observed[src] and observed[src]~=key then notify(unload,src) end
    if not key then observed[src]=nil;return end
    if observed[src]~=key or force then observed[src]=key;notify(ready,src) end
end
local function invalidate(src)
    generation[src]=(generation[src] or 0)+1
    if observed[src] then notify(unload,src) end
    observed[src]=nil
end
AddEventHandler('playerJoining',function() invalidate(source) end)
AddEventHandler('playerDropped',function() invalidate(source) end)
AddEventHandler('QBCore:Server:OnPlayerUnload',function(src) invalidate(tonumber(src) or source) end)
AddEventHandler('qbx_core:server:playerLoggedOut',function(src) invalidate(tonumber(src) or source) end)
-- Readiness is derived from server player data, never from a client citizen ID.
RegisterNetEvent('QBCore:Server:OnPlayerLoaded',function() C.PollCharacter(source) end)
CreateThread(function()
    while true do
        for _,id in ipairs(GetPlayers()) do C.PollCharacter(tonumber(id)) end
        Wait(1000)
    end
end)
