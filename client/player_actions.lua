local handcuffed=false
local function notify(msg) if RSAdmin and RSAdmin.Notify then RSAdmin.Notify(msg) end end
local function currentVehicle() local p=PlayerPedId(); local v=GetVehiclePedIsIn(p,false); if v==0 then v=GetVehiclePedIsIn(p,true) end; return v end
local function maxVehicle(v)
    if not v or v==0 then return false end
    SetVehicleModKit(v,0)
    for slot=0,49 do local n=GetNumVehicleMods(v,slot); if n and n>0 then pcall(SetVehicleMod,v,slot,n-1,false) end end
    pcall(ToggleVehicleMod,v,18,true); pcall(ToggleVehicleMod,v,22,true); SetVehicleFixed(v); SetVehicleDeformationFixed(v); SetVehicleDirtLevel(v,0.0); SetVehicleEngineHealth(v,1000.0); SetVehicleBodyHealth(v,1000.0); SetVehiclePetrolTankHealth(v,1000.0); SetVehicleFuelLevel(v,100.0); SetVehicleTyresCanBurst(v,false)
    for i=0,7 do pcall(FixVehicleWindow,v,i) end; for i=0,5 do pcall(SetVehicleDoorShut,v,i,false) end
    return true
end
local function setHandcuffed(on)
    handcuffed=on==true; local p=PlayerPedId(); SetEnableHandcuffs(p,handcuffed); SetPedCanPlayGestureAnims(p,not handcuffed); SetPedCanSwitchWeapon(p,not handcuffed)
    if handcuffed then SetCurrentPedWeapon(p,joaat('WEAPON_UNARMED'),true) else ClearPedTasks(p) end
end
RegisterNetEvent('rs-admin:client:adminAction',function(d)
    local action=d and d.action; local p=PlayerPedId()
    if action=='slap' then SetPedToRagdoll(p,1000,1300,0,false,false,false); ApplyForceToEntity(p,1,0.0,0.0,tonumber(d.force) or 6.0,0,0,0,0,false,true,true,false,true); notify('Slapped by staff.')
    elseif action=='handcuff' then setHandcuffed(true); notify('Handcuffed by staff.')
    elseif action=='uncuff' then setHandcuffed(false); notify('Uncuffed by staff.')
    elseif action=='strip' then RemoveAllPedWeapons(p,true); notify('Weapons stripped by staff.')
    elseif action=='setPed' then
        local hash=joaat(tostring(d.model or '')); if not IsModelInCdimage(hash) or not IsModelAPed(hash) then notify('Staff ped model is unavailable.'); return end
        RequestModel(hash); local untilAt=GetGameTimer()+5000; while not HasModelLoaded(hash) and GetGameTimer()<untilAt do Wait(0) end; if HasModelLoaded(hash) then SetPlayerModel(PlayerId(),hash); SetModelAsNoLongerNeeded(hash); notify(('Ped changed to %s'):format(d.model)) end
    elseif action=='seat' then
        local c=GetEntityCoords(p); local best=GetClosestVehicle(c.x,c.y,c.z,8.0,0,71); if best and best~=0 then TaskWarpPedIntoVehicle(p,best,math.floor(tonumber(d.seat) or -1)); notify('Seated in vehicle by staff.') else notify('No nearby vehicle.') end
    elseif action=='eject' then local v=GetVehiclePedIsIn(p,false); if v~=0 then TaskLeaveVehicle(p,v,16); notify('Removed from vehicle by staff.') end
    elseif action=='cleanVehicle' then local v=currentVehicle(); if v~=0 then SetVehicleDirtLevel(v,0.0); WashDecalsFromVehicle(v,1.0); notify('Vehicle cleaned by staff.') end
    elseif action=='maxVehicle' then local v=currentVehicle(); if maxVehicle(v) then notify('Vehicle maxed by staff.') else notify('No vehicle found.') end
    elseif action=='refuelVehicle' then local v=currentVehicle(); if v~=0 then SetVehicleFuelLevel(v,100.0); notify('Vehicle refueled by staff.') end
    elseif action=='flipVehicle' then local v=currentVehicle(); if v~=0 then SetEntityRotation(v,0.0,0.0,GetEntityHeading(v),2,true); SetVehicleOnGroundProperly(v); notify('Vehicle flipped by staff.') end
    end
end)
CreateThread(function()
    while true do
        if not handcuffed then Wait(500) else
            DisableControlAction(0,21,true); DisableControlAction(0,22,true); DisableControlAction(0,23,true); DisableControlAction(0,24,true); DisableControlAction(0,25,true); DisableControlAction(0,37,true); DisableControlAction(0,44,true); DisableControlAction(0,75,true)
            Wait(0)
        end
    end
end)
AddEventHandler('onResourceStop',function(res) if res==GetCurrentResourceName() and handcuffed then setHandcuffed(false) end end)
