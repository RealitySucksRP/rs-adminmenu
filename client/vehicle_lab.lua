RSAdmin.LocalActions = RSAdmin.LocalActions or {}
local rotate={active=false,slot=23,index=-1,nextAt=0,delay=1100}
local groupRotate={active=false,slots={},nextAt=0,delay=1300}
RSAdmin.VehicleLab = RSAdmin.VehicleLab or {}
RSAdmin.VehicleLab.StopRotations=function() rotate.active=false; groupRotate.active=false end
local snapshots={}

local function veh()
    local p=PlayerPedId(); local v=GetVehiclePedIsIn(p,false)
    if v~=0 then return v end
    local c=GetEntityCoords(p); local best=0; local bestD=8.0
    local handle,x=FindFirstVehicle(); if handle==-1 then return 0 end
    local ok=true
    repeat if DoesEntityExist(x) then local d=#(GetEntityCoords(x)-c); if d<bestD then best,bestD=x,d end end; ok,x=FindNextVehicle(handle) until not ok
    EndFindVehicle(handle); return best
end

local function modelName(v)
    local h=GetEntityModel(v); local label=GetDisplayNameFromVehicleModel(h); return label and label~='CARNOTFOUND' and label:lower() or tostring(h)
end
local function spawnName(v)
    local ok,name=pcall(GetEntityArchetypeName,v)
    if ok and name and name~='' then return tostring(name):lower() end
    return modelName(v)
end

local OX_MOD_KEYS={
    [0]='modSpoilers',[1]='modFrontBumper',[2]='modRearBumper',[3]='modSideSkirt',[4]='modExhaust',[5]='modFrame',
    [6]='modGrille',[7]='modHood',[8]='modFender',[9]='modRightFender',[10]='modRoof',[11]='modEngine',[12]='modBrakes',
    [13]='modTransmission',[14]='modHorns',[15]='modSuspension',[16]='modArmor',[17]='modNitrous',[19]='modSubwoofer',
    [23]='modFrontWheels',[24]='modBackWheels',[25]='modPlateHolder',[26]='modVanityPlate',[27]='modTrimA',[28]='modOrnaments',
    [29]='modDashboard',[30]='modDial',[31]='modDoorSpeaker',[32]='modSeats',[33]='modSteeringWheel',[34]='modShifterLeavers',
    [35]='modAPlate',[36]='modSpeakers',[37]='modTrunk',[38]='modHydrolic',[39]='modEngineBlock',[40]='modAirFilter',
    [41]='modStruts',[42]='modArchCover',[43]='modAerials',[44]='modTrimB',[45]='modTank',[46]='modWindows',[47]='modDoorR',
    [48]='modLivery',[49]='modLightbar'
}

local function capture(v)
    SetVehicleModKit(v,0)
    local mods={}
    local props={model=GetEntityModel(v)}
    for slot=0,49 do
        local count=GetNumVehicleMods(v,slot)
        if count and count>0 then mods[tostring(slot)]=GetVehicleMod(v,slot) end
        local key=OX_MOD_KEYS[slot]
        if key then props[key]=GetVehicleMod(v,slot) end
    end
    props.mods=mods -- RS-native snapshot map; ignored by ox_lib/qbx_vehicles but useful for fast local restore.

    local extras={}
    for i=0,20 do if DoesExtraExist(v,i) then extras[tostring(i)]=IsVehicleExtraTurnedOn(v,i) and 0 or 1 end end
    props.extras=extras

    local c1,c2=GetVehicleColours(v)
    if GetIsVehiclePrimaryColourCustom(v) then c1={GetVehicleCustomPrimaryColour(v)} end
    if GetIsVehicleSecondaryColourCustom(v) then c2={GetVehicleCustomSecondaryColour(v)} end
    local pearl,wheel=GetVehicleExtraColours(v)
    props.color1=c1; props.color2=c2; props.pearlescentColor=pearl; props.wheelColor=wheel
    props.interiorColor=GetVehicleInteriorColor(v); props.dashboardColor=GetVehicleDashboardColour(v)
    props.wheels=GetVehicleWheelType(v); props.wheelType=props.wheels
    props.windowTint=GetVehicleWindowTint(v); props.tint=props.windowTint
    props.xenonColor=GetVehicleXenonLightsColor(v)
    props.modTurbo=IsToggleModOn(v,18); props.turbo=props.modTurbo
    props.modSmokeEnabled=IsToggleModOn(v,20); props.modHydraulics=IsToggleModOn(v,21); props.modXenon=IsToggleModOn(v,22); props.xenon=props.modXenon
    props.modCustomTiresF=GetVehicleModVariation(v,23); props.modCustomTiresR=GetVehicleModVariation(v,24)
    props.plate=GetVehicleNumberPlateText(v); props.plateIndex=GetVehicleNumberPlateTextIndex(v)
    props.livery=GetVehicleLivery(v); props.modRoofLivery=GetVehicleRoofLivery(v)
    props.neonEnabled={}
    for i=0,3 do props.neonEnabled[i+1]=IsVehicleNeonLightEnabled(v,i) end
    props.neonColor={GetVehicleNeonLightsColour(v)}; props.neon=props.neonColor; props.neonOn=props.neonEnabled[1]
    props.tyreSmokeColor={GetVehicleTyreSmokeColor(v)}
    props.engineHealth=GetVehicleEngineHealth(v); props.bodyHealth=GetVehicleBodyHealth(v); props.tankHealth=GetVehiclePetrolTankHealth(v)
    props.fuelLevel=GetVehicleFuelLevel(v); props.dirtLevel=GetVehicleDirtLevel(v); props.oilLevel=GetVehicleOilLevel(v)
    return props
end

local function apply(v,p)
    SetVehicleModKit(v,0)
    local wheelType=p.wheels
    if wheelType==nil then wheelType=p.wheelType end
    if wheelType~=nil then SetVehicleWheelType(v,math.floor(tonumber(wheelType) or 0)) end

    if type(p.mods)=='table' then
        for slot,index in pairs(p.mods) do SetVehicleMod(v,tonumber(slot),tonumber(index),false) end
    else
        for slot,key in pairs(OX_MOD_KEYS) do if p[key]~=nil then SetVehicleMod(v,slot,tonumber(p[key]) or -1,false) end end
    end
    if p.modFrontWheels~=nil then SetVehicleMod(v,23,tonumber(p.modFrontWheels) or -1,p.modCustomTiresF==true) end
    if p.modBackWheels~=nil then SetVehicleMod(v,24,tonumber(p.modBackWheels) or -1,p.modCustomTiresR==true) end

    for id,disable in pairs(p.extras or {}) do SetVehicleExtra(v,tonumber(id),tonumber(disable)==1) end
    local turbo=p.modTurbo; if turbo==nil then turbo=p.turbo end; if turbo~=nil then ToggleVehicleMod(v,18,turbo==true) end
    local xenon=p.modXenon; if xenon==nil then xenon=p.xenon end; if xenon~=nil then ToggleVehicleMod(v,22,xenon==true) end
    if p.modSmokeEnabled~=nil then ToggleVehicleMod(v,20,p.modSmokeEnabled==true) end
    if p.modHydraulics~=nil then ToggleVehicleMod(v,21,p.modHydraulics==true) end
    if p.windowTint~=nil then SetVehicleWindowTint(v,tonumber(p.windowTint) or 0) elseif p.tint~=nil then SetVehicleWindowTint(v,tonumber(p.tint) or 0) end
    if p.livery and tonumber(p.livery)>=0 then SetVehicleLivery(v,tonumber(p.livery)) end
    if p.modRoofLivery and tonumber(p.modRoofLivery)>=0 then SetVehicleRoofLivery(v,tonumber(p.modRoofLivery)) end
    if p.plate then SetVehicleNumberPlateText(v,tostring(p.plate):sub(1,8)) end
    if p.plateIndex~=nil then SetVehicleNumberPlateTextIndex(v,tonumber(p.plateIndex) or 0) end

    if type(p.color1)=='table' and #p.color1>=3 then SetVehicleCustomPrimaryColour(v,p.color1[1],p.color1[2],p.color1[3]) elseif type(p.color1)=='number' then local _,c2=GetVehicleColours(v); SetVehicleColours(v,p.color1,c2) end
    if type(p.color2)=='table' and #p.color2>=3 then SetVehicleCustomSecondaryColour(v,p.color2[1],p.color2[2],p.color2[3]) elseif type(p.color2)=='number' then local c1=GetVehicleColours(v); SetVehicleColours(v,c1,p.color2) end
    if p.pearlescentColor~=nil or p.wheelColor~=nil then local pearl,wheel=GetVehicleExtraColours(v); SetVehicleExtraColours(v,tonumber(p.pearlescentColor) or pearl,tonumber(p.wheelColor) or wheel) end
    if p.interiorColor~=nil then SetVehicleInteriorColor(v,tonumber(p.interiorColor) or 0) end
    if p.dashboardColor~=nil then SetVehicleDashboardColour(v,tonumber(p.dashboardColor) or 0) end
    if p.xenonColor~=nil then SetVehicleXenonLightsColor(v,tonumber(p.xenonColor) or -1) end
    local neon=p.neonColor or p.neon
    if type(neon)=='table' and #neon>=3 then SetVehicleNeonLightsColour(v,neon[1],neon[2],neon[3]) end
    if type(p.neonEnabled)=='table' then for i=0,3 do if p.neonEnabled[i+1]~=nil then SetVehicleNeonLightEnabled(v,i,p.neonEnabled[i+1]==true) end end elseif p.neonOn~=nil then for i=0,3 do SetVehicleNeonLightEnabled(v,i,p.neonOn==true) end end
    if type(p.tyreSmokeColor)=='table' and #p.tyreSmokeColor>=3 then SetVehicleTyreSmokeColor(v,p.tyreSmokeColor[1],p.tyreSmokeColor[2],p.tyreSmokeColor[3]) end
    if p.engineHealth~=nil then SetVehicleEngineHealth(v,tonumber(p.engineHealth)+0.0) end
    if p.bodyHealth~=nil then SetVehicleBodyHealth(v,tonumber(p.bodyHealth)+0.0) end
    if p.tankHealth~=nil then SetVehiclePetrolTankHealth(v,tonumber(p.tankHealth)+0.0) end
    if p.fuelLevel~=nil then SetVehicleFuelLevel(v,tonumber(p.fuelLevel)+0.0) end
    if p.dirtLevel~=nil then SetVehicleDirtLevel(v,tonumber(p.dirtLevel)+0.0) end
end

local function need() if not (RSAdmin.Can('vehicles') or RSAdmin.Can('owner')) then return false,{ok=false,error='Permission denied'} end; local v=veh(); if v==0 then return false,{ok=false,error='No vehicle nearby'} end; return v end

local function modName(v,slot,index)
    if not index or index < 0 then return 'STOCK' end
    local raw=GetModTextLabel(v,slot,index)
    if raw and raw~='' then
        local text=GetLabelText(raw)
        if text and text~='' and text~='NULL' then return text end
        return raw
    end
    return ('OPTION %s'):format(index+1)
end

RSAdmin.LocalActions.vehicleInspect=function()
    local v,e=need(); if not v then return e end
    SetVehicleModKit(v,0)
    local slots={}
    for slot,label in pairs(Config.VehicleModSlots) do
        local n=GetNumVehicleMods(v,slot)
        if n and n>0 then
            local current=GetVehicleMod(v,slot)
            slots[#slots+1]={slot=slot,label=label,count=n,current=current,currentName=modName(v,slot,current)}
        end
    end
    table.sort(slots,function(a,b) return a.slot<b.slot end)
    local extras={}; for i=0,20 do if DoesExtraExist(v,i) then extras[#extras+1]={id=i,on=IsVehicleExtraTurnedOn(v,i)} end end
    return {ok=true,data={model=spawnName(v),displayName=modelName(v),spawnName=spawnName(v),netId=NetworkGetNetworkIdFromEntity(v),slots=slots,extras=extras,wheelType=GetVehicleWheelType(v),liveryCount=GetVehicleLiveryCount(v),livery=GetVehicleLivery(v),props=capture(v)}}
end

RSAdmin.LocalActions.vehicleMod=function(d) local v,e=need(); if not v then return e end; local slot=tonumber(d.slot); local idx=tonumber(d.index); if not slot or not idx then return {ok=false,error='Invalid mod'} end; SetVehicleModKit(v,0); SetVehicleMod(v,slot,idx,d.customTires==true); return {ok=true} end
RSAdmin.LocalActions.vehicleWheelType=function(d) local v,e=need(); if not v then return e end; SetVehicleWheelType(v,math.max(0,math.min(12,tonumber(d.value) or 0))); return RSAdmin.LocalActions.vehicleInspect() end
RSAdmin.LocalActions.vehicleExtra=function(d) local v,e=need(); if not v then return e end; local id=tonumber(d.id); if not id or not DoesExtraExist(v,id) then return {ok=false,error='Extra missing'} end; SetVehicleExtra(v,id,d.enabled and 0 or 1); return {ok=true} end
RSAdmin.LocalActions.vehicleRepair=function() local v,e=need(); if not v then return e end; SetVehicleFixed(v); SetVehicleDeformationFixed(v); SetVehicleDirtLevel(v,0.0); SetVehicleEngineHealth(v,1000.0); SetVehicleBodyHealth(v,1000.0); return {ok=true} end
RSAdmin.LocalActions.vehicleMax=function() local v,e=need(); if not v then return e end; SetVehicleModKit(v,0); for _,s in ipairs({11,12,13,15,16}) do local n=GetNumVehicleMods(v,s); if n>0 then SetVehicleMod(v,s,n-1,false) end end; ToggleVehicleMod(v,18,true); return {ok=true} end
RSAdmin.LocalActions.vehicleMaxAll=function() local v,e=need(); if not v then return e end; SetVehicleModKit(v,0); for slot=0,49 do local n=GetNumVehicleMods(v,slot); if n and n>0 and slot~=14 then SetVehicleMod(v,slot,n-1,false) end end; ToggleVehicleMod(v,18,true); ToggleVehicleMod(v,22,true); SetVehicleFixed(v); SetVehicleDirtLevel(v,0.0); return RSAdmin.LocalActions.vehicleInspect() end
RSAdmin.LocalActions.vehicleFlip=function() local v,e=need(); if not v then return e end; local c=GetEntityCoords(v); SetEntityRotation(v,0.0,0.0,GetEntityHeading(v),2,true); SetEntityCoordsNoOffset(v,c.x,c.y,c.z+0.5,false,false,false); SetVehicleOnGroundProperly(v); return {ok=true} end
RSAdmin.LocalActions.vehicleDelete=function() local v,e=need(); if not v then return e end; local net=NetworkGetNetworkIdFromEntity(v); RSAdmin.RPC('vehicle:deleteNet',{netId=net},function(r) if not r.ok then RSAdmin.Notify(r.error or 'Delete failed') end end); return {ok=true,pending=true} end
RSAdmin.LocalActions.vehicleRandom=function() local v,e=need(); if not v then return e end; SetVehicleModKit(v,0); for slot=0,49 do local n=GetNumVehicleMods(v,slot); if n>0 and slot~=11 and slot~=12 and slot~=13 and slot~=16 then SetVehicleMod(v,slot,math.random(-1,n-1),false) end end; return RSAdmin.LocalActions.vehicleInspect() end
RSAdmin.LocalActions.vehiclePlate=function(d) local v,e=need(); if not v then return e end; SetVehicleNumberPlateText(v,tostring(d.text or 'RSADMIN'):sub(1,8):upper()); return {ok=true} end
RSAdmin.LocalActions.vehicleLivery=function(d) local v,e=need(); if not v then return e end; SetVehicleLivery(v,tonumber(d.index) or -1); return {ok=true} end
RSAdmin.LocalActions.vehicleNeon=function(d) local v,e=need(); if not v then return e end; local on=d.enabled==true; for i=0,3 do SetVehicleNeonLightEnabled(v,i,on) end; if d.r then SetVehicleNeonLightsColour(v,math.floor(d.r),math.floor(d.g or 0),math.floor(d.b or 0)) end; return {ok=true} end
RSAdmin.LocalActions.vehicleSnapshot=function(d) local v,e=need(); if not v then return e end; local k=tostring(d.key or 'A'):upper(); snapshots[k]=capture(v); return {ok=true,key=k} end
RSAdmin.LocalActions.vehicleApplySnapshot=function(d) local v,e=need(); if not v then return e end; local k=tostring(d.key or 'A'):upper(); if not snapshots[k] then return {ok=false,error='Snapshot '..k..' is empty'} end; apply(v,snapshots[k]); return {ok=true} end
RSAdmin.LocalActions.vehicleSavePreset=function(d) local v,e=need(); if not v then return e end; local model=spawnName(v); local props=capture(v); local out=nil; RSAdmin.RPC('preset:save',{model=model,name=tostring(d.name or ''),props=props},function(r) SendNUIMessage({type='rpcPush',key='presets',data=r.data}); if not r.ok then RSAdmin.Notify(r.error or 'Save failed') end end); return {ok=true,pending=true} end
RSAdmin.LocalActions.vehicleApplyPreset=function(d) local v,e=need(); if not v then return e end; if type(d.props)~='table' then return {ok=false,error='Preset missing'} end; apply(v,d.props); return {ok=true} end
local catalogueCache=nil
local function vehicleCatalogue()
    if catalogueCache then return catalogueCache end
    local models=GetAllVehicleModels() or {}; local out={}
    for i=1,#models do
        local model=tostring(models[i]); local h=joaat(model); local display=GetDisplayNameFromVehicleModel(h); local make=GetMakeNameFromVehicleModel(h); local label=model
        if display and display~='' and display~='CARNOTFOUND' then local dl=GetLabelText(display); label=(dl and dl~='NULL') and dl or display end
        if make and make~='' and make~='CARNOTFOUND' then local ml=GetLabelText(make); if ml and ml~='NULL' then label=ml..' '..label end end
        out[#out+1]={model=model,label=label,class=GetVehicleClassFromName(h),image=(Config.VehicleImages.cfxBase or 'https://docs.fivem.net/vehicles/')..model..'.webp',localImage=(Config.VehicleImages.localBase or 'assets/vehicles/')..model..'.webp',fallback=Config.VehicleImages.fallback}
    end
    table.sort(out,function(a,b) return a.label:lower()<b.label:lower() end); catalogueCache=out; return out
end
RSAdmin.LocalActions.vehicleCatalogue=function(d)
    if not (RSAdmin.Can('vehicles') or RSAdmin.Can('garage') or RSAdmin.Can('owner')) then return {ok=false,error='Permission denied'} end
    d=d or {}; local q=tostring(d.q or ''):lower(); local page=math.max(1,math.floor(tonumber(d.page) or 1)); local size=math.max(12,math.min(48,math.floor(tonumber(d.pageSize) or 24))); local rows={}
    for _,v in ipairs(vehicleCatalogue()) do if q=='' or v.model:lower():find(q,1,true) or v.label:lower():find(q,1,true) then rows[#rows+1]=v end end
    local total=#rows; local first=(page-1)*size+1; local out={}; for i=first,math.min(total,first+size-1) do out[#out+1]=rows[i] end
    return {ok=true,data={rows=out,total=total,page=page,pages=math.max(1,math.ceil(total/size)),pageSize=size}}
end

RSAdmin.LocalActions.vehicleConfiguredProps=function(d)
    if not (RSAdmin.Can('vehicles') or RSAdmin.Can('garage') or RSAdmin.Can('owner')) then return {ok=false,error='Permission denied'} end
    local model=tostring(d.model or ''):lower(); if model=='' then return {ok=false,error='Vehicle model required'} end; local hash=joaat(model)
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then return {ok=false,error='Invalid vehicle model'} end
    RequestModel(hash); local untilAt=GetGameTimer()+5000; while not HasModelLoaded(hash) and GetGameTimer()<untilAt do Wait(0) end; if not HasModelLoaded(hash) then return {ok=false,error='Vehicle model failed to load'} end
    local c=GetEntityCoords(PlayerPedId()); local v=CreateVehicle(hash,c.x,c.y,c.z-25.0,0.0,false,false); if v==0 then return {ok=false,error='Preview vehicle failed'} end
    SetEntityVisible(v,false,false); SetEntityCollision(v,false,false); SetVehicleModKit(v,0)
    if d.maxBuild==true then for slot=0,49 do local n=GetNumVehicleMods(v,slot); if n and n>0 and slot~=14 then SetVehicleMod(v,slot,n-1,false) end end; ToggleVehicleMod(v,18,true); ToggleVehicleMod(v,22,true) end
    if d.primary then SetVehicleColours(v,tonumber(d.primary) or 0,tonumber(d.secondary) or 0) end
    if d.pearlescent then local _,wheel=GetVehicleExtraColours(v); SetVehicleExtraColours(v,tonumber(d.pearlescent) or 0,wheel) end
    if d.wheelType~=nil then SetVehicleWheelType(v,math.max(0,math.min(12,math.floor(tonumber(d.wheelType) or 7)))) end
    if d.livery~=nil and tonumber(d.livery) and tonumber(d.livery)>=0 then local n=GetVehicleLiveryCount(v); if n and n>0 then SetVehicleLivery(v,math.max(0,math.min(n-1,math.floor(tonumber(d.livery))))) end end
    if d.plate and tostring(d.plate)~='' then SetVehicleNumberPlateText(v,tostring(d.plate):upper():sub(1,8)) end
    local props=capture(v); DeleteEntity(v); SetModelAsNoLongerNeeded(hash); return {ok=true,data=props}
end

RSAdmin.LocalActions.vehicleGiveCurrent=function(d)
    local v,e=need(); if not v then return e end
    local target=tonumber(d.target) or GetPlayerServerId(PlayerId())
    local garage=tostring(d.garage or Config.DefaultGarage or '')
    local props=capture(v); props.plate=GetVehicleNumberPlateText(v)
    RSAdmin.RPC('vehicle:giveOwned',{target=target,model=spawnName(v),garage=garage,props=props},function(r)
        if r.ok then RSAdmin.Notify(('Vehicle saved to garage [%s]'):format((r.data and r.data.plate) or props.plate or '?')) else RSAdmin.Notify(r.error or 'Vehicle grant failed') end
    end)
    return {ok=true,pending=true}
end

RSAdmin.LocalActions.vehicleRotateGroup=function(d)
    local v,e=need(); if not v then return e end
    local groups={body={0,1,2,3,5,6,7,8,9,10},rims={23,24},performance={11,12,13,15,16},allvisual={0,1,2,3,4,5,6,7,8,9,10,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,39,40,41,42,43,44,45,46,48,49}}
    local slots=groups[tostring(d.group or 'body')] or groups.body
    groupRotate.active=not groupRotate.active; groupRotate.slots=slots; groupRotate.delay=math.max(300,math.min(5000,tonumber(d.delay) or 1300)); groupRotate.nextAt=0
    return {ok=true,enabled=groupRotate.active}
end

RSAdmin.LocalActions.vehicleRotate=function(d)
    local v,e=need(); if not v then return e end
    local slot=tonumber(d.slot) or 23; local count=GetNumVehicleMods(v,slot); if count<=0 then return {ok=false,error='No mods in this slot'} end
    rotate.active=not rotate.active; rotate.slot=slot; rotate.index=GetVehicleMod(v,slot); rotate.delay=math.max(250,math.min(5000,tonumber(d.delay) or 1100)); rotate.nextAt=0
    return {ok=true,enabled=rotate.active,slot=slot,count=count}
end

CreateThread(function()
    while true do
        if not groupRotate.active then Wait(350) else
            local v=veh()
            if v==0 then groupRotate.active=false else
                local now=GetGameTimer()
                if now>=groupRotate.nextAt then
                    SetVehicleModKit(v,0)
                    for _,slot in ipairs(groupRotate.slots) do
                        local n=GetNumVehicleMods(v,slot)
                        if n and n>0 then local cur=GetVehicleMod(v,slot)+1; if cur>=n then cur=-1 end; SetVehicleMod(v,slot,cur,false) end
                    end
                    groupRotate.nextAt=now+groupRotate.delay
                    SendNUIMessage({type='groupRotation'})
                end
                Wait(0)
            end
        end
    end
end)

CreateThread(function()
    while true do
        if not rotate.active then Wait(300) else
            local v=veh(); if v==0 then rotate.active=false else
                local now=GetGameTimer(); if now>=rotate.nextAt then local n=GetNumVehicleMods(v,rotate.slot); if n<=0 then rotate.active=false else rotate.index=rotate.index+1; if rotate.index>=n then rotate.index=-1 end; SetVehicleModKit(v,0); SetVehicleMod(v,rotate.slot,rotate.index,false); rotate.nextAt=now+rotate.delay; SendNUIMessage({type='rotation',slot=rotate.slot,index=rotate.index,count=n}) end end
                Wait(0)
            end
        end
    end
end)
