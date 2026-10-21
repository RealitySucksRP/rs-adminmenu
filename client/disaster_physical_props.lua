-- RS AdminMenu: bounded physical storm debris; owned by the local viewer only.
-- Collision-enabled props react to static map geometry and ambient NPCs. No
-- mission peds, player peds, networked props, or player-owned objects are altered.
local P={serial=0,objects={},hits=0,models=0,lastReason='idle'}
local MODELS={
    'apa_bedroom_art','apa_mp_h_acc_artwalll_01_dressing',
    'ch_chint02_03_exit_signs','ch3_04_fencesigns_a_lod',
    'dt1_17_cloth3','prop_venice_sign_04',
    'm23_1_prop_m31_ghostjohnny_01a','m23_1_prop_m31_ghostrurmeth_01a',
    'prop_coffin_02','bkr_prop_coke_scale_01','hei_prop_drug_statue_box_01',
    'prop_office_phone_tnt','prop_laptop_01a',
    'prop_bin_05a','prop_roadcone02a','prop_rub_binbag_01',
    'prop_tree_branch_01','prop_pallet_02a'
}
local function clear()
    P.serial=P.serial+1
    for _,r in ipairs(P.objects) do
        if r.entity and DoesEntityExist(r.entity) then
            SetEntityAsMissionEntity(r.entity,true,true)
            DeleteObject(r.entity)
        end
    end
    P.objects={};P.lastReason='stopped'
end
local function available(hash)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) or IsModelAVehicle(hash) or IsModelAPed(hash) then return false end
    -- Many custom/DLC names resolve only on Enhanced. Skip absent models and
    -- oversized map pieces / LOD shells; never launch entire buildings.
    local ok,min,max=pcall(GetModelDimensions,hash)
    if ok and min and max and max.x then
        local size=math.max(max.x-min.x,max.y-min.y,max.z-min.z)
        if size>4.8 or size<.03 then return false end
    end
    return true
end
local function ownedPed(ped)
    return DoesEntityExist(ped) and not IsPedAPlayer(ped) and
        not IsEntityAMissionEntity(ped) and not IsPedDeadOrDying(ped,true) and
        not IsPedInAnyVehicle(ped,false) and GetInteriorFromEntity(ped)==0 and
        (not NetworkGetEntityIsNetworked(ped) or NetworkHasControlOfEntity(ped))
end
local function playersNoCollision(object)
    for _,id in ipairs(GetActivePlayers()) do
        local ped=GetPlayerPed(id)
        if ped~=0 and DoesEntityExist(ped) then SetEntityNoCollisionEntity(object,ped,false) end
    end
end
RSAdmin.RegisterServerEvent('rs-admin:client:disaster',function(d)
    if source~=65535 then return end
    clear(); P.hits=0;P.models=0
    if type(d)~='table' or d.scope~='all' or
        (d.name~='hurricane' and d.name~='tornado') then return end
    local token=P.serial
    local tornado=d.name=='tornado'
    local duration=math.max(5000,(tonumber(d.seconds) or 30)*1000)
    local limit=math.max(1,math.min(14,tonumber((Config.Disasters.physics or {}).physicalDebris) or 12))
    local damage=math.max(0,math.min(20,tonumber((Config.Disasters.physics or {}).debrisDamage) or 13))
    CreateThread(function()
        local began=GetGameTimer()
        local startAge=math.max(0,tonumber(d.elapsed) or 0)
        local function age() return startAge+(GetGameTimer()-began)*.001 end
        while token==P.serial and GetGameTimer()-began<duration do
            local center=tornado and RSAdmin.StormCenter(d,age()) or GetEntityCoords(PlayerPedId())
            local player=GetEntityCoords(PlayerPedId())
            if (center.x-player.x)^2+(center.y-player.y)^2<160*160 then break end
            Wait(550)
        end
        if token~=P.serial or GetGameTimer()-began>=duration then return end
        local availableModels={}
        for _,name in ipairs(MODELS) do
            local hash=GetHashKey(name)
            if available(hash) then availableModels[#availableModels+1]=hash end
        end
        P.models=#availableModels
        if #availableModels==0 then P.lastReason='models unavailable';return end
        local viewer=GetEntityCoords(PlayerPedId())
        for i=1,limit do
            if token~=P.serial then return end
            local hash=availableModels[(i-1)%#availableModels+1]
            RequestModel(hash)
            local deadline=GetGameTimer()+750
            while token==P.serial and not HasModelLoaded(hash) and GetGameTimer()<deadline do Wait(0) end
            if HasModelLoaded(hash) and token==P.serial then
                local gust=RSAdmin.StormGust(d,age())
                local origin=tornado and RSAdmin.StormCenter(d,age()) or viewer
                -- Launch upwind, avoiding a cluster directly over the operator.
                local side=((i%5)-2)*6
                local x=origin.x-gust.x*(24+(i%4)*6)-gust.y*side
                local y=origin.y-gust.y*(24+(i%4)*6)+gust.x*side
                local obj=CreateObjectNoOffset(hash,x,y,origin.z+3+i%3,false,false,false)
                if obj~=0 and DoesEntityExist(obj) then
                    SetEntityAsMissionEntity(obj,true,true)
                    SetEntityDynamic(obj,true)
                    SetEntityCollision(obj,true,true)
                    SetEntityHasGravity(obj,true)
                    ActivatePhysics(obj)
                    playersNoCollision(obj)
                    SetEntityVelocity(obj,gust.x*14,gust.y*14,4.0)
                    P.objects[#P.objects+1]={entity=obj,lastHit={},index=i,spawn=GetGameTimer()}
                end
            end
            SetModelAsNoLongerNeeded(hash)
            Wait(120)
        end
        P.lastReason='active'
        local nextPedScan=0
        while token==P.serial and GetGameTimer()-began<duration do
            local time=GetGameTimer()
            local gust=RSAdmin.StormGust(d,age())
            local center=tornado and RSAdmin.StormCenter(d,age()) or GetEntityCoords(PlayerPedId())
            local pedestrians={}
            if time>=nextPedScan then
                nextPedScan=time+330
                for _,ped in ipairs(GetGamePool('CPed')) do
                    if #pedestrians>=55 then break end
                    if ownedPed(ped) then pedestrians[#pedestrians+1]=ped end
                end
            end
            for _,r in ipairs(P.objects) do
                local obj=r.entity
                if DoesEntityExist(obj) then
                    playersNoCollision(obj)
                    local c=GetEntityCoords(obj)
                    local dist=math.sqrt((c.x-center.x)^2+(c.y-center.y)^2)
                    if dist>195 or c.z<center.z-17 or c.z>center.z+88 or time-r.spawn>18000 then
                        -- Recycle this disposable physical prop far upwind to
                        -- maintain continuous debris throughout long events.
                        local side=((r.index%5)-2)*7
                        local x=center.x-gust.x*65-gust.y*side
                        local y=center.y-gust.y*65+gust.x*side
                        SetEntityCoordsNoOffset(obj,x,y,center.z+5,false,false,false)
                        SetEntityVelocity(obj,gust.x*16,gust.y*16,3.0)
                        r.spawn=time;r.lastHit={}
                    else
                        local vx,vy
                        if tornado and dist>2 then
                            local nx,ny=(c.x-center.x)/dist,(c.y-center.y)/dist
                            vx=-nx*5-ny*gust.strength*14
                            vy=-ny*5+nx*gust.strength*14
                        else
                            vx,vy=gust.x*(12+gust.strength*8),gust.y*(12+gust.strength*8)
                        end
                        ApplyForceToEntityCenterOfMass(obj,1,vx,vy,(tornado and 2.4 or 1.6)*gust.strength,0,false,false,false)
                        local vel=GetEntityVelocity(obj)
                        local speed=math.sqrt(vel.x*vel.x+vel.y*vel.y+vel.z*vel.z)
                        if speed>42 then
                            local factor=42/speed
                            SetEntityVelocity(obj,vel.x*factor,vel.y*factor,vel.z*factor)
                            speed=42
                        end
                        if speed>7 and #pedestrians>0 then
                            for _,ped in ipairs(pedestrians) do
                                local p=GetEntityCoords(ped)
                                if (p.x-c.x)^2+(p.y-c.y)^2+(p.z-c.z)^2<3.2*3.2 and time>=(r.lastHit[ped] or 0) then
                                    r.lastHit[ped]=time+2200
                                    -- Actual local object/ped collision stays enabled.
                                    -- Extra targeted damage makes impacts observable
                                    -- without a radial blast injuring live players.
                                    ApplyDamageToPed(ped,damage,false)
                                    SetPedToRagdoll(ped,700,1300,0,false,false,false)
                                    ApplyForceToEntityCenterOfMass(ped,1,vx*.65,vy*.65,2.2,0,false,false,false)
                                    P.hits=P.hits+1
                                    break
                                end
                            end
                        end
                    end
                end
            end
            Wait(95)
        end
        if token==P.serial then clear() end
    end)
end)
RSAdmin.RegisterServerEvent('rs-admin:client:disasterStop',function() if source==65535 then clear() end end)
AddEventHandler('onResourceStop',function(res) if res==GetCurrentResourceName() then clear() end end)
RSAdmin.StormPhysicalPropStats=function() return {active=#P.objects,hits=P.hits,models=P.models,state=P.lastReason} end
