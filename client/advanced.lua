RSAdmin.Advanced = RSAdmin.Advanced or {}
local jail=nil
local builder={}
local builderBlips={}
local prankEntities={}

local function safeCoords(c) return c and tonumber(c.x),c and tonumber(c.y),c and tonumber(c.z),c and tonumber(c.w or c.heading) end
local function teleport(c)
    local x,y,z,w=safeCoords(c); if not x or not y or not z then return end
    local ped=PlayerPedId(); SetEntityCoordsNoOffset(ped,x,y,z,false,false,false); if w then SetEntityHeading(ped,w) end
end

RSAdmin.RegisterServerEvent('rs-admin:client:jail',function(d)
    if type(d)~='table' or not d.coords then return end
    jail=d; teleport(d.coords); ClearPedTasksImmediately(PlayerPedId()); RSAdmin.Notify(('Jailed: %s'):format(d.reason or 'Administrative sentence'))
end)
RSAdmin.RegisterServerEvent('rs-admin:client:unjail',function(d)
    if type(d)~='table' then return end
    jail=nil; teleport(d.coords); ClearPedTasksImmediately(PlayerPedId()); RSAdmin.Notify(('Released: %s'):format(d.reason or 'Sentence ended'))
end)
local function clearCharacterJail() jail=nil end
AddEventHandler('QBCore:Client:OnPlayerUnload',clearCharacterJail)
AddEventHandler('qbx_core:client:playerLoggedOut',clearCharacterJail)
RSAdmin.RegisterServerEvent('rs-admin:client:clearPunishments',clearCharacterJail)
CreateThread(function()
    while true do
        if not jail or not jail.coords then Wait(1500) else
            local ped=PlayerPedId(); local p=GetEntityCoords(ped); local c=jail.coords; local dx,dy,dz=p.x-c.x,p.y-c.y,p.z-c.z; local r=tonumber(jail.leashRadius) or 35.0
            if dx*dx+dy*dy+dz*dz > r*r then teleport(c); RSAdmin.Notify('Return to the jail area.') end
            Wait(1200)
        end
    end
end)

local function requestAnim(dict)
    RequestAnimDict(dict); local untilAt=GetGameTimer()+4000
    while not HasAnimDictLoaded(dict) and GetGameTimer()<untilAt do Wait(0) end
    return HasAnimDictLoaded(dict)
end
RSAdmin.RegisterServerEvent('rs-admin:client:prankAnimation',function(a)
    if not a or not a.dict or not a.clip then return end; local ped=PlayerPedId(); if not requestAnim(a.dict) then return end
    TaskPlayAnim(ped,a.dict,a.clip,8.0,-8.0,math.max(1000,tonumber(a.duration) or 5000),tonumber(a.flag) or 49,0.0,false,false,false)
end)
local function clearPrankEntities()
    for _,e in ipairs(prankEntities) do if DoesEntityExist(e) then DeleteEntity(e) end end; prankEntities={}; StopEntityFire(PlayerPedId()); StopGameplayCamShaking(true)
end
RSAdmin.RegisterServerEvent('rs-admin:client:prankStop',function() ClearPedTasksImmediately(PlayerPedId()); clearPrankEntities(); if RSAdmin.Pranks and RSAdmin.Pranks.Reset then RSAdmin.Pranks.Reset() end end)
RSAdmin.RegisterServerEvent('rs-admin:client:prankAdvanced',function(d)
    local action=tostring(d.action or ''); local seconds=math.max(1,math.min(Config.PrankMaxSeconds or 30,tonumber(d.seconds) or 8)); local ped=PlayerPedId()
    if action=='fire' then StartEntityFire(ped); SetTimeout(seconds*1000,function() StopEntityFire(ped) end)
    elseif action=='launch' then SetPedToRagdoll(ped,1200,1200,0,false,false,false); ApplyForceToEntity(ped,1,0.0,0.0,22.0,0,0,0,0,false,true,true,false,true)
    elseif action=='vehicleBlast' then local v=GetVehiclePedIsIn(ped,false); local e=v~=0 and v or ped; local c=GetEntityCoords(e); AddExplosion(c.x,c.y,c.z,2,1.0,true,false,0.8,true)
    elseif action=='ragdoll' then CreateThread(function() local stop=GetGameTimer()+seconds*1000; while GetGameTimer()<stop do SetPedToRagdoll(ped,850,850,0,false,false,false); Wait(450) end end)
    elseif action=='drunk' or action=='spin' or action=='screenShake' or action=='vehicleSpin' then RSAdmin.ApplyPrank({action=action,seconds=seconds})
    elseif action=='droneStrike' then
        CreateThread(function()
            local hash=joaat('ch_prop_casino_drone_02a'); RequestModel(hash); local untilAt=GetGameTimer()+3500; while not HasModelLoaded(hash) and GetGameTimer()<untilAt do Wait(0) end
            local c=GetEntityCoords(ped); local drone=0
            if HasModelLoaded(hash) then drone=CreateObjectNoOffset(hash,c.x+6.0,c.y+6.0,c.z+14.0,false,false,false); if drone~=0 then prankEntities[#prankEntities+1]=drone; SetEntityCollision(drone,false,false) end end
            local stop=GetGameTimer()+3000
            while drone~=0 and DoesEntityExist(drone) and GetGameTimer()<stop do local t=GetEntityCoords(ped); local dc=GetEntityCoords(drone); SetEntityCoordsNoOffset(drone,dc.x+(t.x-dc.x)*.06,dc.y+(t.y-dc.y)*.06,math.max(t.z+3.0,dc.z-.22),false,false,false); Wait(30) end
            local t=GetEntityCoords(ped); AddExplosion(t.x,t.y,t.z,2,1.0,true,false,1.0,true); if drone~=0 and DoesEntityExist(drone) then DeleteEntity(drone) end
        end)
    end
end)

local function model(hash)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return false end; RequestModel(hash); local untilAt=GetGameTimer()+5000; while not HasModelLoaded(hash) and GetGameTimer()<untilAt do Wait(0) end; return HasModelLoaded(hash)
end
local function applyScale(ent,scale)
    scale=tonumber(scale) or 1.0; if math.abs(scale-1.0)<0.01 then return end
    pcall(function()
        local f,r,u,p=GetEntityMatrix(ent)
        SetEntityMatrix(ent,f.x*scale,f.y*scale,f.z*scale,r.x*scale,r.y*scale,r.z*scale,u.x*scale,u.y*scale,u.z*scale,p.x,p.y,p.z)
    end)
end
local function removeBuilder(id)
    id=tonumber(id); local e=builder[id]; if e and DoesEntityExist(e) then DeleteEntity(e) end; builder[id]=nil; local b=builderBlips[id]; if b and DoesBlipExist(b) then RemoveBlip(b) end; builderBlips[id]=nil
end
local function addBuilder(r)
    if not r or not r.id then return end; removeBuilder(r.id); local kind=r.kind
    if kind=='blip' then local b=AddBlipForCoord(r.x+0.0,r.y+0.0,r.z+0.0); SetBlipSprite(b,tonumber(r.sprite) or 1); SetBlipColour(b,tonumber(r.color) or 0); SetBlipScale(b,tonumber(r.scale) or .8); SetBlipAlpha(b,tonumber(r.alpha) or 255); BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName(r.label or 'RS Admin'); EndTextCommandSetBlipName(b); builderBlips[tonumber(r.id)]=b; return end
    local modelName=(kind=='anim' and (r.model=='' or not r.model) and 'a_m_m_business_01') or r.model; local hash=joaat(modelName or ''); if not model(hash) then return end; local ent
    if kind=='prop' then ent=CreateObjectNoOffset(hash,r.x+0.0,r.y+0.0,r.z+0.0,false,false,false)
    else ent=CreatePed(4,hash,r.x+0.0,r.y+0.0,r.z+0.0,r.w+0.0,false,false) end
    SetModelAsNoLongerNeeded(hash); if not ent or ent==0 then return end; builder[tonumber(r.id)]=ent; SetEntityHeading(ent,tonumber(r.w) or 0); FreezeEntityPosition(ent,r.frozen~=false); SetEntityCollision(ent,r.collision~=false,r.collision~=false); SetEntityAlpha(ent,tonumber(r.alpha) or 255,false); if kind=='prop' then pcall(SetObjectTintIndex,ent,tonumber(r.tint) or 0) end; if kind~='prop' then SetEntityInvincible(ent,true); SetBlockingOfNonTemporaryEvents(ent,true) end; applyScale(ent,r.scale)
    if (kind=='ped' or kind=='anim') and r.animDict and r.animDict~='' and r.animClip and r.animClip~='' and requestAnim(r.animDict) then TaskPlayAnim(ent,r.animDict,r.animClip,8.0,-8.0,-1,tonumber(r.animFlag) or 49,0,false,false,false) end
end
RSAdmin.RegisterServerEvent('rs-admin:client:builderAdd',addBuilder)
RSAdmin.RegisterServerEvent('rs-admin:client:builderDelete',function(d) removeBuilder(d and d.id) end)
RSAdmin.RegisterServerEvent('rs-admin:client:builderSync',function(rows) for id in pairs(builder) do removeBuilder(id) end; for id in pairs(builderBlips) do removeBuilder(id) end; for _,r in ipairs(rows or {}) do addBuilder(r) end end)

AddEventHandler('onResourceStop',function(res)
    if res~=GetCurrentResourceName() then return end; jail=nil; clearPrankEntities(); for id in pairs(builder) do removeBuilder(id) end; for id in pairs(builderBlips) do removeBuilder(id) end
end)
