local S={active=false,target=nil,coords=nil,heading=nil,vehicleNet=nil,seat=nil}
RSAdmin.Spectate = RSAdmin.Spectate or {}

local function stopLocal(reason)
    if not S.active then return end
    local ped=PlayerPedId()
    NetworkSetInSpectatorMode(false,ped)
    SetEntityVisible(ped,true,false)
    SetEntityCollision(ped,true,true)
    FreezeEntityPosition(ped,false)
    SetEntityInvincible(ped,RSAdmin.Power and RSAdmin.Power.state.god or false)
    local restoredVehicle=false
    if S.vehicleNet and NetworkDoesNetworkIdExist(S.vehicleNet) then
        local v=NetToVeh(S.vehicleNet)
        if v~=0 and DoesEntityExist(v) then
            SetEntityCoordsNoOffset(ped,S.coords.x,S.coords.y,S.coords.z,false,false,false)
            TaskWarpPedIntoVehicle(ped,v,S.seat or -1)
            restoredVehicle=true
        end
    end
    if not restoredVehicle and S.coords then
        RequestCollisionAtCoord(S.coords.x,S.coords.y,S.coords.z)
        SetEntityCoordsNoOffset(ped,S.coords.x,S.coords.y,S.coords.z,false,false,false)
        SetEntityHeading(ped,S.heading or 0.0)
    end
    S.active=false; S.target=nil; S.vehicleNet=nil; S.seat=nil
    if reason then RSAdmin.Notify(reason) end
end


RSAdmin.Spectate.IsActive=function() return S.active end
RSAdmin.Spectate.StopLocal=stopLocal
RSAdmin.Spectate.Stop=function()
    if S.active then RSAdmin.RPC('spectate:stop',{},function() end) end
end

RegisterNetEvent('rs-admin:client:spectateStart',function(d)
    stopLocal()
    local ped=PlayerPedId()
    S.coords=GetEntityCoords(ped); S.heading=GetEntityHeading(ped); S.target=tonumber(d.target); S.active=true
    if IsPedInAnyVehicle(ped,false) then
        local v=GetVehiclePedIsIn(ped,false); S.vehicleNet=VehToNet(v)
        for seat=-1,GetVehicleModelNumberOfSeats(GetEntityModel(v))-2 do if GetPedInVehicleSeat(v,seat)==ped then S.seat=seat break end end
    else S.vehicleNet=nil; S.seat=nil end
    if RSAdmin.SetOpen then RSAdmin.SetOpen(false) end
    SetEntityVisible(ped,false,false); SetEntityCollision(ped,false,false); SetEntityInvincible(ped,true); FreezeEntityPosition(ped,true)
    SetEntityCoordsNoOffset(ped,tonumber(d.x) or 0.0,tonumber(d.y) or 0.0,(tonumber(d.z) or 0.0)-8.0,false,false,false)
    CreateThread(function()
        local untilAt=GetGameTimer()+7000
        while S.active and GetGameTimer()<untilAt do
            local idx=GetPlayerFromServerId(S.target)
            if idx~=-1 then
                local targetPed=GetPlayerPed(idx)
                if targetPed~=0 and DoesEntityExist(targetPed) then NetworkSetInSpectatorMode(true,targetPed); return end
            end
            Wait(100)
        end
        if S.active then TriggerServerEvent('rs-admin:server:rpc','spectate:stop','spectate-timeout:'..GetGameTimer(),{}) end
    end)
end)

RegisterNetEvent('rs-admin:client:spectateStop',function(d)
    stopLocal(d and d.reason)
end)

RSAdmin.LocalActions = RSAdmin.LocalActions or {}
RSAdmin.LocalActions.stopSpectate=function()
    if not S.active then return {ok=true,enabled=false} end
    RSAdmin.RPC('spectate:stop',{},function() end)
    return {ok=true,enabled=false}
end

CreateThread(function()
    while true do
        if not S.active then Wait(500) else
            local idx=GetPlayerFromServerId(S.target or -1)
            if idx==-1 then RSAdmin.RPC('spectate:stop',{},function() end); Wait(500) else Wait(250) end
        end
    end
end)

AddEventHandler('onResourceStop',function(res) if res==GetCurrentResourceName() then stopLocal() end end)
