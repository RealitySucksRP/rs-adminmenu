local service=nil
local choreIndex=1
local offsets={{4.0,0.0},{-4.0,2.0},{2.0,5.0},{-2.5,-4.0},{5.5,-2.0}}
local spots={}
local function notify(msg) if RSAdmin and RSAdmin.Notify then RSAdmin.Notify(msg) end end
local function coords() local c=(service and service.coords) or {}; return vector3(tonumber(c.x) or 170.18,tonumber(c.y) or -990.91,tonumber(c.z) or 30.09) end
local function teleportBase() local c=spots[1] or coords(); SetEntityCoords(PlayerPedId(),c.x,c.y,c.z+0.2,false,false,false,false); local heading=c.w or (service and service.coords and service.coords.w);if heading then SetEntityHeading(PlayerPedId(),heading+0.0) end end
local choreBusy=false
local activeWork
local function stopWork(cancel)
    local work=activeWork;activeWork=nil;choreBusy=false
    if not work then return end
    if work.prop and DoesEntityExist(work.prop) then DeleteEntity(work.prop) end
    if work.dict then StopAnimTask(work.ped,work.dict,work.clip,2.0);RemoveAnimDict(work.dict)
    elseif work.scenario then ClearPedTasks(work.ped) end
    if cancel and work.token then RSAdmin.RPC('communityService:cancel',{id=work.id,token=work.token},function() end) end
end
local function clearService()
    service=nil;stopWork(false)
end
RSAdmin.RegisterServerEvent('rs-admin:client:communityService',function(d)
    if type(d)~='table' or not d.id then return end
    local entering=not service or service.id~=d.id
    if entering then stopWork(true) end
    service=d
    if type(d.offsets)=='table' and #d.offsets>0 then offsets=d.offsets end
    spots={}
    if type(d.spots)=='table' and #d.spots>0 then spots=d.spots
    else
        local base=coords()
        for _,off in ipairs(offsets) do spots[#spots+1]={x=base.x+off[1],y=base.y+off[2],z=base.z,w=d.coords and d.coords.w} end
    end
    choreIndex=math.max(1,math.min(#spots,tonumber(d.choreIndex) or 1))
    if entering then teleportBase();notify(('Community service: %s tasks remaining. %s'):format(d.remaining or 0,d.reason or '')) end
end)
RSAdmin.RegisterServerEvent('rs-admin:client:communityServiceStop',function(d) clearService();notify((d and d.reason) or 'Community service ended.') end)
RSAdmin.RegisterServerEvent('rs-admin:client:clearPunishments',clearService)
AddEventHandler('QBCore:Client:OnPlayerUnload',clearService)
AddEventHandler('qbx_core:client:playerLoggedOut',clearService)
AddEventHandler('onResourceStop',function(res) if res==GetCurrentResourceName() then clearService() end end)
local function startWork(ped,current,x,y,z,heading)
    choreBusy=true
    RSAdmin.RPC('communityService:begin',{id=current.id},function(begin)
        if service~=current then
            choreBusy=false
            if begin and begin.ok then RSAdmin.RPC('communityService:cancel',{id=current.id,token=begin.data.token},function() end) end
            return
        end
        if not begin or not begin.ok then choreBusy=false;notify(begin and begin.error or 'Could not start chore');return end
        local task=current.task or {scenario='WORLD_HUMAN_JANITOR'}
        local work={id=current.id,token=begin.data.token,ped=ped}
        activeWork=work
        CreateThread(function()
            local function available() return activeWork==work and service==current and PlayerPedId()==ped and not IsEntityDead(ped) end
            local function loadAsset(request,loaded)
                request();local deadline=GetGameTimer()+3000
                while available() and not loaded() and GetGameTimer()<deadline do Wait(0) end
                return available() and loaded()
            end
            if task.scenario then work.scenario=task.scenario
            else
                work.dict=task.dict;work.clip=task.clip
                if not work.dict or not work.clip or not loadAsset(function() RequestAnimDict(work.dict) end,function() return HasAnimDictLoaded(work.dict) end) then
                    if activeWork==work then stopWork(true);notify('Chore animation could not load. Try again or contact staff.') end
                    return
                end
            end
            if task.prop and task.prop.model then
                local hash=joaat(task.prop.model)
                if not IsModelValid(hash) or not loadAsset(function() RequestModel(hash) end,function() return HasModelLoaded(hash) end) then
                    SetModelAsNoLongerNeeded(hash)
                    if activeWork==work then stopWork(true);notify('Chore prop could not load. Try again or contact staff.') end
                    return
                end
                local prop=CreateObjectNoOffset(hash,x,y,z,false,false,false);SetModelAsNoLongerNeeded(hash)
                if not prop or prop==0 then stopWork(true);notify('Chore prop could not be created.');return end
                work.prop=prop;SetEntityAsMissionEntity(prop,true,true);SetEntityCollision(prop,false,false)
                local off,rot=task.prop.offset or {},task.prop.rotation or {}
                AttachEntityToEntity(prop,ped,GetPedBoneIndex(ped,task.prop.bone or 28422),off[1] or 0.0,off[2] or 0.0,off[3] or 0.0,rot[1] or 0.0,rot[2] or 0.0,rot[3] or 0.0,true,true,false,true,1,true)
            end
            if not available() then if activeWork==work then stopWork(true) end;return end
            local duration=math.max(3000,math.min(15000,tonumber(current.durationMs) or 3200))
            local facing=heading or task.heading
            if facing then SetEntityHeading(ped,facing+0.0) end
            if work.scenario then TaskStartScenarioInPlace(ped,work.scenario,0,true)
            else TaskPlayAnim(ped,work.dict,work.clip,8.0,-8.0,-1,tonumber(task.flag) or 1,0.0,false,false,false) end
            local started=GetGameTimer()
            while available() and GetGameTimer()-started<duration do
                local p=GetEntityCoords(ped);local dx,dy,dz=p.x-x,p.y-y,p.z-z
                local playing=work.scenario and IsPedUsingAnyScenario(ped) or (work.dict and IsEntityPlayingAnim(ped,work.dict,work.clip,3))
                if dx*dx+dy*dy+dz*dz>3.0 or IsControlJustReleased(0,73) or (GetGameTimer()-started>500 and not playing) then
                    stopWork(true);notify('Chore interrupted. No task deducted.');return
                end
                for _,control in ipairs({21,22,23,24,25,30,31,37,75}) do DisableControlAction(0,control,true) end
                Wait(0)
            end
            if not available() then if activeWork==work then stopWork(true) end;return end
            stopWork(false)
            RSAdmin.RPC('communityService:complete',{id=current.id,token=work.token},function(r)
                if not service or service.id~=current.id then return end
                if r and r.ok then
                    if r.data.remaining<=0 then clearService()
                    else service.remaining=r.data.remaining;choreIndex=math.max(1,math.min(#spots,tonumber(r.data.choreIndex) or choreIndex)) end
                else notify(r and r.error or 'Task failed') end
            end)
        end)
    end)
end
CreateThread(function()
    while true do
        if not service then Wait(1000) else
            local ped=PlayerPedId(); local p=GetEntityCoords(ped);local nearest=math.huge
            for _,spot in ipairs(spots) do local dx,dy,dz=p.x-spot.x,p.y-spot.y,p.z-spot.z;nearest=math.min(nearest,dx*dx+dy*dy+dz*dz) end
            -- The configured yard spans more than 50m: allow every supplied spot.
            if nearest>2500.0 then teleportBase(); p=GetEntityCoords(ped) end
            local currentSpot=spots[choreIndex];local x,y,z=currentSpot.x,currentSpot.y,currentSpot.z
            for idx,spot in ipairs(spots) do
                local active=idx==choreIndex
                DrawMarker(1,spot.x,spot.y,spot.z-1.0,0,0,0,0,0,0,active and 1.2 or .7,active and 1.2 or .7,.25,active and 32 or 130,active and 169 or 130,active and 255 or 130,active and 125 or 65,false,false,2,false,nil,nil,false)
            end
            local ax,ay,az=p.x-x,p.y-y,p.z-z
            if ax*ax+ay*ay+az*az<3.0 then
                local label=(service.task and service.task.label) or 'Work'
                local message=choreBusy and ('%s... ~INPUT_VEH_DUCK~ cancel · %s remaining'):format(label,service.remaining or 0) or ('Press ~INPUT_CONTEXT~ to %s · spot %s/%s · %s remaining'):format(label:lower(),choreIndex,#spots,service.remaining or 0)
                BeginTextCommandDisplayHelp('STRING'); AddTextComponentSubstringPlayerName(message); EndTextCommandDisplayHelp(0,false,true,-1)
                if not choreBusy and IsControlJustReleased(0,38) then
                    startWork(ped,service,x,y,z,currentSpot.w)
                end
            end
            Wait(0)
        end
    end
end)
