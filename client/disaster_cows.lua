-- RS AdminMenu: optional airborne cows (GTA native a_c_cow).
-- Visual-only, local non-networked actors. They never enter the player's ped pool
-- as network-owned livestock, have no collision, and are deleted on stop/restart.
-- This resource DOES NOT depend on RS AnimeGrab or any third-party model.
local Cows={generation=0,actors={},spawned=0,reason='idle'}
local MODEL='a_c_cow'
local function cleanup()
    Cows.generation=Cows.generation+1
    for _,ped in ipairs(Cows.actors) do
        if ped and ped~=0 and DoesEntityExist(ped) then
            SetEntityAsMissionEntity(ped,true,true)
            DeletePed(ped)
        end
    end
    Cows.actors={}
    Cows.spawned=0
    Cows.reason='stopped'
end
local function withinDistance(a,b,limit)
    local dx,dy=a.x-b.x,a.y-b.y
    return dx*dx+dy*dy<limit*limit
end
RSAdmin.RegisterServerEvent('rs-admin:client:disaster',function(data)
    if source~=65535 then return end
    cleanup()
    if type(data)~='table' or (data.name~='tornado' and data.name~='hurricane') or
        data.cinematicCows~=true or data.scope~='all' then return end
    local generation=Cows.generation
    local tornado=data.name=='tornado'
    local duration=math.max(1000,(tonumber(data.seconds) or 30)*1000)
    local maxCows=math.max(1,math.min(2,math.floor(tonumber((Config.Disasters.physics or {}).cinematicCows) or 2)))
    CreateThread(function()
        local started=GetGameTimer()
        local baseAge=math.max(0,tonumber(data.elapsed) or 0)
        local function age() return baseAge+(GetGameTimer()-started)*.001 end
        local function center()
            return tornado and RSAdmin.StormCenter(data,age()) or GetEntityCoords(PlayerPedId())
        end
        -- When the tornado crosses the map toward another player, spawn on approach.
        if tornado then
            while generation==Cows.generation and GetGameTimer()-started<duration do
                if withinDistance(center(),GetEntityCoords(PlayerPedId()),165) then break end
                Wait(500)
            end
        end
        if generation~=Cows.generation or GetGameTimer()-started>=duration then return end
        local hash=GetHashKey(MODEL)
        if not IsModelInCdimage(hash) or not IsModelAPed(hash) then
            Cows.reason='cow model unavailable';return
        end
        RequestModel(hash)
        local deadline=GetGameTimer()+3500
        while generation==Cows.generation and not HasModelLoaded(hash) and GetGameTimer()<deadline do Wait(0) end
        if generation~=Cows.generation or not HasModelLoaded(hash) then
            Cows.reason='cow model load timeout';return
        end
        for i=1,maxCows do
            if generation~=Cows.generation then break end
            local c=center()
            -- Spawn safely off the ground to avoid grabbing civilian ped AI.
            local ped=CreatePed(28,hash,c.x+(i==1 and 8 or -9),c.y+(i==1 and 9 or -11),c.z+16,0.0,false,false)
            if ped and ped~=0 and DoesEntityExist(ped) then
                SetEntityAsMissionEntity(ped,true,true)
                SetEntityInvincible(ped,true)
                SetEntityCollision(ped,false,false)
                SetBlockingOfNonTemporaryEvents(ped,true)
                SetPedCanRagdoll(ped,false)
                FreezeEntityPosition(ped,true)
                Cows.actors[#Cows.actors+1]=ped
                Cows.spawned=Cows.spawned+1
            end
            Wait(150)
        end
        SetModelAsNoLongerNeeded(hash)
        if #Cows.actors==0 then Cows.reason='local ped creation refused';return end
        Cows.reason='active'
        while generation==Cows.generation and GetGameTimer()-started<duration do
            local t=age()
            local c=center()
            local gust=RSAdmin.StormGust(data,t)
            for i,ped in ipairs(Cows.actors) do
                if DoesEntityExist(ped) then
                    local a=t*(tornado and 1.48 or .63)+i*math.pi*.91
                    local orbit=tornado and (13+i*5) or (17+i*7)
                    local x,y
                    if tornado then
                        x=c.x+math.cos(a)*orbit
                        y=c.y+math.sin(a)*orbit
                    else
                        local lane=math.sin(t*.45+i*2.05)*43*gust.strength
                        local cross=math.sin(a)*orbit
                        -- Non-orbiting hurricane gust lanes change heading over time.
                        x=c.x+gust.x*lane-gust.y*cross
                        y=c.y+gust.y*lane+gust.x*cross
                    end
                    local z=c.z+11+i*5+math.abs(math.sin(t*.72+i))*17
                    SetEntityCoordsNoOffset(ped,x,y,z,false,false,false)
                    SetEntityRotation(ped,math.sin(a)*65+t*17,math.cos(a)*70+t*59,t*115+i*110,2,true)
                end
            end
            Wait(80)
        end
        if generation==Cows.generation then cleanup() end
    end)
end)
RSAdmin.RegisterServerEvent('rs-admin:client:disasterStop',function()
    if source==65535 then cleanup() end
end)
AddEventHandler('onResourceStop',function(resource)
    if resource==GetCurrentResourceName() then cleanup() end
end)
RSAdmin.StormCowStats=function()
    return {active=#Cows.actors,count=Cows.spawned,state=Cows.reason}
end
