RSAdmin.LocalActions = RSAdmin.LocalActions or {}
local noclip=false
local speed=1.5
RSAdmin.Noclip = RSAdmin.Noclip or {}

local function camDir()
    local r=GetGameplayCamRot(2); local rz=math.rad(r.z); local rx=math.rad(r.x); local cx=math.abs(math.cos(rx))
    return vector3(-math.sin(rz)*cx, math.cos(rz)*cx, math.sin(rx))
end

local function setNoclip(enabled)
    noclip=enabled==true
    local ped=PlayerPedId()
    SetEntityCollision(ped,not noclip,not noclip)
    FreezeEntityPosition(ped,noclip)
    SetEntityInvincible(ped,noclip or (RSAdmin.Power and RSAdmin.Power.state.god) or false)
end
RSAdmin.Noclip.Set=setNoclip
RSAdmin.Noclip.IsActive=function() return noclip end

RSAdmin.LocalActions.toggleNoclip=function()
    if not (RSAdmin.Can('developer') or RSAdmin.Can('owner')) then return {ok=false,error='Permission denied'} end
    setNoclip(not noclip)
    return {ok=true,enabled=noclip}
end

RSAdmin.LocalActions.noclipSpeed=function(d) speed=math.max(0.25,math.min(15.0,tonumber(d.speed) or speed)); return {ok=true,speed=speed} end

CreateThread(function()
    while true do
        if not noclip then Wait(300) else
            local ped=PlayerPedId(); local pos=GetEntityCoords(ped); local dir=camDir(); local right=vector3(dir.y,-dir.x,0.0); local mult=speed
            if IsControlPressed(0,21) then mult=mult*3.0 end
            if IsControlPressed(0,36) then mult=mult*0.25 end
            if IsControlPressed(0,32) then pos=pos+dir*mult end
            if IsControlPressed(0,33) then pos=pos-dir*mult end
            if IsControlPressed(0,34) then pos=pos-right*mult end
            if IsControlPressed(0,35) then pos=pos+right*mult end
            if IsControlPressed(0,44) then pos=pos+vector3(0,0,mult) end
            if IsControlPressed(0,38) then pos=pos-vector3(0,0,mult) end
            SetEntityCoordsNoOffset(ped,pos.x,pos.y,pos.z,true,true,true); SetEntityVelocity(ped,0,0,0); SetEntityHeading(ped,GetGameplayCamRot(2).z)
            Wait(0)
        end
    end
end)

AddEventHandler('onResourceStop',function(res) if res==GetCurrentResourceName() and noclip then setNoclip(false) end end)
