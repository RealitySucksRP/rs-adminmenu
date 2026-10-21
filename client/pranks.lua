local prank = { drunk=false, shake=false, spinning=false }
RSAdmin.Pranks = RSAdmin.Pranks or {}

local function clearDrunk()
    local ped=PlayerPedId()
    ResetPedMovementClipset(ped,0.0)
    SetPedIsDrunk(ped,false)
    StopGameplayCamShaking(true)
    prank.drunk=false
end

local function resetPranks()
    prank.spinning=false
    clearDrunk()
    StopGameplayCamShaking(true)
    prank.shake=false
end
RSAdmin.Pranks.Reset=resetPranks

local function applyPrank(d)
    local action=tostring(d.action or '')
    local seconds=math.max(1,math.min(30,tonumber(d.seconds) or 8))
    local ped=PlayerPedId(); local pid=PlayerId()

    if action=='drunk' then
        prank.drunk=true
        RequestAnimSet('move_m@drunk@verydrunk')
        local untilAt=GetGameTimer()+3000
        while not HasAnimSetLoaded('move_m@drunk@verydrunk') and GetGameTimer()<untilAt do Wait(0) end
        if HasAnimSetLoaded('move_m@drunk@verydrunk') then SetPedMovementClipset(ped,'move_m@drunk@verydrunk',1.0) end
        SetPedIsDrunk(ped,true); ShakeGameplayCam('DRUNK_SHAKE',0.8)
        SetTimeout(seconds*1000,clearDrunk)
    elseif action=='ragdoll' then
        CreateThread(function()
            local untilAt=GetGameTimer()+seconds*1000
            while GetGameTimer()<untilAt do SetPedToRagdoll(ped,800,800,0,false,false,false); Wait(450) end
        end)
    elseif action=='spin' then
        prank.spinning=true
        CreateThread(function()
            local untilAt=GetGameTimer()+seconds*1000
            while prank.spinning and GetGameTimer()<untilAt do
                SetEntityHeading(ped,(GetEntityHeading(ped)+12.0)%360.0)
                Wait(35)
            end
            prank.spinning=false
        end)
    elseif action=='fakeExplosion' then
        local c=GetEntityCoords(ped)
        AddExplosion(c.x,c.y,c.z,2,0.0,true,false,0.7,true)
    elseif action=='screenShake' then
        prank.shake=true; ShakeGameplayCam('LARGE_EXPLOSION_SHAKE',1.0)
        SetTimeout(seconds*1000,function() StopGameplayCamShaking(true); prank.shake=false end)
    elseif action=='wanted5' then
        SetMaxWantedLevel(5); SetPlayerWantedLevel(pid,5,false); SetPlayerWantedLevelNow(pid,false)
    elseif action=='clearWanted' then
        ClearPlayerWantedLevel(pid); SetPlayerWantedLevel(pid,0,false); SetMaxWantedLevel(5)
    elseif action=='launch' then
        SetPedToRagdoll(ped,1200,1200,0,false,false,false)
        ApplyForceToEntity(ped,1,0.0,0.0,18.0,0.0,0.0,0.0,0,false,true,true,false,true)
    elseif action=='stumble' then
        SetPedToRagdoll(ped,math.min(seconds*1000,5000),math.min(seconds*1000,5000),0,false,false,false)
    elseif action=='vehicleSpin' then
        local v=GetVehiclePedIsIn(ped,false)
        if v~=0 then SetEntityAngularVelocity(v,0.0,0.0,5.5) end
    end
end
RSAdmin.ApplyPrank=applyPrank
RSAdmin.RegisterServerEvent('rs-admin:client:prank',applyPrank)

AddEventHandler('onResourceStop',function(res)
    if res~=GetCurrentResourceName() then return end
    resetPranks()
end)
