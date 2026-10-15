RSAdmin = RSAdmin or {}
RSAdmin.permissions = {}
RSAdmin.open = false
RSAdmin.uiMode = 'HIDDEN'
RSAdmin.dockInteracting = false
RSAdmin.callbacks = {}
RSAdmin.req = 0
RSAdmin.frozen = false
local bootstrapEpoch = 0
function RSAdmin.BeginBootstrap()
    bootstrapEpoch=bootstrapEpoch+1
    return bootstrapEpoch
end
function RSAdmin.BootstrapCurrent(epoch)
    return epoch==bootstrapEpoch
end

local function notify(msg)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(('~b~RS ADMIN~s~  %s'):format(msg))
    EndTextCommandThefeedPostTicker(false,false)
end
RSAdmin.Notify = notify

function RSAdmin.Can(node)
    return RSAdmin.permissions.owner or RSAdmin.permissions.all or RSAdmin.permissions[node] == true
end

function RSAdmin.RPC(name,data,cb)
    RSAdmin.req = RSAdmin.req + 1
    local id = ('%s:%s'):format(GetPlayerServerId(PlayerId()),RSAdmin.req)
    if cb then RSAdmin.callbacks[id]={cb=cb,expires=GetGameTimer()+(Config.RpcTimeoutMs or 12000),name=name} end
    TriggerServerEvent('rs-admin:server:rpc',name,id,data or {})
end

RegisterNetEvent('rs-admin:client:rpc',function(id,res)
    local entry=RSAdmin.callbacks[id]
    if entry then RSAdmin.callbacks[id]=nil; entry.cb(res) end
end)
CreateThread(function()
    while true do
        local now=GetGameTimer(); local active=false
        for id,entry in pairs(RSAdmin.callbacks) do active=true; if now>=entry.expires then RSAdmin.callbacks[id]=nil; entry.cb({ok=false,error=('Request timed out: %s'):format(entry.name or 'rpc')}) end end
        Wait(active and 250 or 1000)
    end
end)

local function setUiMode(mode)
    mode=(mode=='FULL' or mode=='DOCKED') and mode or 'HIDDEN'
    if mode~='FULL' then RSAdmin.BeginBootstrap() end
    local previous=RSAdmin.uiMode
    RSAdmin.uiMode=mode; RSAdmin.open=(mode=='FULL')
    if mode=='HIDDEN' and RSAdmin.ClearEntityPreview then RSAdmin.ClearEntityPreview() end
    if mode=='FULL' then
        SetNuiFocus(true,true); SetNuiFocusKeepInput(false)
    elseif previous=='FULL' or RSAdmin.dockInteracting then
        -- Only release focus owned by this resource. The Qbox character picker
        -- may currently own NUI focus while this admin UI is already hidden.
        SetNuiFocus(false,false); SetNuiFocusKeepInput(false)
    end
    if mode~='DOCKED' then RSAdmin.dockInteracting=false end
    SendNUIMessage({type='uiMode',mode=mode})
end
local function setOpen(state) setUiMode(state and 'FULL' or 'HIDDEN') end
RSAdmin.SetOpen=setOpen
RSAdmin.SetUiMode=setUiMode

local function characterReady()
    if GetResourceState('qbx_core') == 'started' then
        return LocalPlayer and LocalPlayer.state and LocalPlayer.state.isLoggedIn == true
    end
    return true
end

local function bootstrap()
    if not characterReady() then
        setUiMode('HIDDEN')
        notify('Select and load a character before opening RS Admin.')
        return
    end
    local requestEpoch=RSAdmin.BeginBootstrap()
    RSAdmin.RPC('bootstrap',{},function(res)
        if not RSAdmin.BootstrapCurrent(requestEpoch) or not characterReady() then return end
        if not res or not res.ok then
            setUiMode('HIDDEN')
            notify(res.error or 'Access denied')
            return
        end
        RSAdmin.permissions=res.data.permissions or {}
        print(('[rs-adminmenu] bootstrap ok framework=%s qbxLoggedIn=%s'):format(tostring(res.data.framework or 'unknown'), tostring(LocalPlayer and LocalPlayer.state and LocalPlayer.state.isLoggedIn)))
        SendNUIMessage({type='bootstrap',data=res.data})
        setOpen(true)
        notify('Admin bootstrap OK — opening menu.')
    end)
end

RSAdmin.Bootstrap=bootstrap
RegisterNetEvent('rs-admin:client:open',bootstrap)
RegisterCommand(Config.Command,function() bootstrap() end,false)
RegisterKeyMapping(Config.Command, 'Open RS Admin Menu', 'keyboard', Config.Keybind)

-- Qbox multicharacter owns focus until a character is fully loaded. Never let
-- the admin NUI compete with that lifecycle, and always release focus on logout.
AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    -- No automatic open. This only marks the point where /rsadmin may be used.
end)
RegisterNetEvent('qbx_core:client:playerLoggedOut', function()
    setUiMode('HIDDEN')
end)
RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    setUiMode('HIDDEN')
end)



-- Live NUI canvas probe. Does not set focus or make the tablet visible.
RegisterCommand('rsadminnuidiag',function()
    print(('[rs-adminmenu] NUI probe requested mode=%s, open=%s'):format(tostring(RSAdmin.uiMode),tostring(RSAdmin.open)))
    SendNUIMessage({type='nuiProbe'})
end,false)
RegisterNUICallback('nuiSurfaceStatus',function(data,cb)
    print('[rs-adminmenu] NUI surface: '..json.encode(data or {}))
    cb({ok=true})
end)

RegisterNUICallback('nuiReady', function(data, cb)
    print(('[rs-adminmenu] NUI ready href=%s'):format(tostring(data and data.href or 'unknown')))
    cb({ok=true})
end)

RegisterCommand('rsadmindiag', function()
    local qbxState = GetResourceState('qbx_core')
    local logged = LocalPlayer and LocalPlayer.state and LocalPlayer.state.isLoggedIn
    local ped = PlayerPedId()
    local cam = GetRenderingCam and GetRenderingCam() or 0
    local faded = IsScreenFadedOut and IsScreenFadedOut() or false
    local fadingOut = IsScreenFadingOut and IsScreenFadingOut() or false
    local fadingIn = IsScreenFadingIn and IsScreenFadingIn() or false
    local gameplayCam = IsGameplayCamRendering and IsGameplayCamRendering() or false
    local cinematicCam = IsCinematicCamRendering and IsCinematicCamRendering() or false
    local visible = DoesEntityExist(ped) and IsEntityVisible(ped) or false
    print(('[rs-adminmenu] DIAG resource=%s qbx=%s loggedIn=%s uiMode=%s open=%s faded=%s fadingOut=%s fadingIn=%s gameplayCam=%s cinematicCam=%s renderCam=%s pedVisible=%s'):format(
        GetResourceState(GetCurrentResourceName()), tostring(qbxState), tostring(logged), tostring(RSAdmin.uiMode), tostring(RSAdmin.open), tostring(faded), tostring(fadingOut), tostring(fadingIn), tostring(gameplayCam), tostring(cinematicCam), tostring(cam), tostring(visible)))
    notify(('DIAG · qbx=%s · loggedIn=%s · ui=%s · faded=%s'):format(tostring(qbxState), tostring(logged), tostring(RSAdmin.uiMode), tostring(faded)))
end, false)

RegisterNUICallback('close',function(_,cb) setUiMode('HIDDEN'); cb({ok=true}) end)
RegisterNUICallback('dock',function(_,cb) setUiMode('DOCKED'); cb({ok=true}) end)
RegisterNUICallback('expand',function(_,cb) setUiMode('FULL'); cb({ok=true}) end)

RegisterCommand('+rsadmindockinteract',function()
    if RSAdmin.uiMode~='DOCKED' then return end
    SetNuiFocus(true,true); SetNuiFocusKeepInput(true)
    RSAdmin.dockInteracting=true
    SendNUIMessage({type='dockInteract',active=true})
end,false)
RegisterCommand('-rsadmindockinteract',function()
    if RSAdmin.uiMode~='DOCKED' then return end
    SetNuiFocus(false,false); SetNuiFocusKeepInput(false)
    RSAdmin.dockInteracting=false
    SendNUIMessage({type='dockInteract',active=false})
end,false)
RegisterKeyMapping('+rsadmindockinteract','Interact with RS Admin dock','keyboard',(Config.Dock and Config.Dock.interactKey) or 'LMENU')
RegisterNUICallback('rpc',function(data,cb)
    local name=tostring(data.name or '')
    RSAdmin.RPC(name,data.data or {},function(res)
        if res and not res.ok then notify(res.error or 'Action failed') end
        cb(res or {ok=false,error='No response'})
    end)
end)

RegisterNUICallback('localAction',function(data,cb)
    local action=tostring(data.action or '')
    if action=='entityPreview' then
        RSAdmin.RPC('builder:validate',data.data or {},function(res)
            if not res or not res.ok then cb(res or {ok=false,error='Access denied'});return end
            local good,result=pcall(RSAdmin.LocalActions.entityPreview,res.data);cb(good and result or {ok=false,error=tostring(result)})
        end)
        return
    end
    if action=='healSelf' or action=='reviveSelf' then
        RSAdmin.RPC(action=='healSelf' and 'operator:heal' or 'operator:revive',{},cb)
        return
    end
    local fn=RSAdmin.LocalActions and RSAdmin.LocalActions[action]
    if not fn then cb({ok=false,error='Unknown local action'}); return end
    local function execute()
        local ok,res=pcall(fn,data.data or {})
        if not ok then cb({ok=false,error=tostring(res)}); return end
        cb(res or {ok=true})
    end
    local guarded={togglePower=true,fullGod=true,resetAdminState=true,setArmor=true,setWanted=true,teleportWaypoint=true,toggleNoclip=true,noclipSpeed=true,toggleLaser=true,operatorCoords=true,stopSpectate=true}
    if guarded[action] then
        RSAdmin.RPC('operator:authorize',{action=action},function(res)
            if not res or not res.ok then cb(res or {ok=false,error='Access denied'}); return end
            execute()
        end)
    else execute() end
end)

RegisterNetEvent('rs-admin:client:freeze',function()
    RSAdmin.frozen=not RSAdmin.frozen
    FreezeEntityPosition(PlayerPedId(),RSAdmin.frozen)
    notify(RSAdmin.frozen and 'You were frozen by staff.' or 'You were unfrozen by staff.')
end)
RegisterNetEvent('rs-admin:client:heal',function() local p=PlayerPedId(); SetEntityHealth(p,GetEntityMaxHealth(p)); SetPedArmour(p,100); notify('Healed by staff.') end)
RegisterNetEvent('rs-admin:client:revive',function() local p=PlayerPedId(); local c=GetEntityCoords(p); NetworkResurrectLocalPlayer(c.x,c.y,c.z,GetEntityHeading(p),true,false); ClearPedBloodDamage(p); SetEntityHealth(p,GetEntityMaxHealth(p)); notify('Revived by staff.') end)
RegisterNetEvent('rs-admin:client:kill',function() SetEntityHealth(PlayerPedId(),0) end)
RegisterNetEvent('rs-admin:client:armor',function(d) SetPedArmour(PlayerPedId(),math.max(0,math.min(100,math.floor(tonumber(d and d.amount) or 100)))); notify('Armor restored by staff.') end)
RegisterNetEvent('rs-admin:client:clearTasks',function() ClearPedTasksImmediately(PlayerPedId()); ClearPedSecondaryTask(PlayerPedId()); notify('Tasks cleared by staff.') end)
RegisterNetEvent('rs-admin:client:fixVehicle',function()
    local p=PlayerPedId(); local v=GetVehiclePedIsIn(p,false)
    if v==0 then notify('You need to be inside a vehicle.'); return end
    SetVehicleFixed(v); SetVehicleDeformationFixed(v); SetVehicleDirtLevel(v,0.0); SetVehicleEngineHealth(v,1000.0); SetVehicleBodyHealth(v,1000.0); SetVehiclePetrolTankHealth(v,1000.0); SetVehicleFuelLevel(v,100.0)
    notify('Your vehicle was repaired and refueled by staff.')
end)
RegisterNetEvent('rs-admin:client:bringTo',function(d) SetEntityCoords(PlayerPedId(),d.x,d.y,d.z+0.5,false,false,false,false); notify('Brought by staff.') end)
RegisterNetEvent('rs-admin:client:teleport',function(d) SetEntityCoords(PlayerPedId(),d.x,d.y,d.z+0.5,false,false,false,false) end)
RegisterNetEvent('rs-admin:client:message',function(d) notify(('%s: %s'):format(d.by or 'Staff',d.text or '')) end)
RegisterNetEvent('rs-admin:client:announcement',function(d) notify(('ANNOUNCEMENT — %s'):format(d.text or '')) end)
RegisterNetEvent('rs-admin:client:permissionsRefresh',function()
    RSAdmin.RPC('bootstrap',{},function(res) if res and res.ok then RSAdmin.permissions=res.data.permissions or {}; if RSAdmin.open then SendNUIMessage({type='bootstrap',data=res.data}) end end end)
end)
RegisterNetEvent('rs-admin:client:staffChat',function(d)
    SendNUIMessage({type='staffChat',data=d})
    if not RSAdmin.open then notify(('STAFF · %s: %s'):format(d.name or 'Staff',d.message or '')) end
end)

RegisterNetEvent('rs-admin:client:reportAlert',function(d)
    if RSAdmin.Can('reports') then notify(('New report #%s from %s'):format(d.id,d.name or 'player')); SendNUIMessage({type='reportAlert',data=d}) end
end)
RegisterNetEvent('rs-admin:client:promptReport',function() setOpen(false); AddTextEntry('RS_ADMIN_REPORT','Describe the issue'); DisplayOnscreenKeyboard(1,'RS_ADMIN_REPORT','','','','','',500); while UpdateOnscreenKeyboard()==0 do Wait(0) end; local v=GetOnscreenKeyboardResult(); if v and #v>2 then RSAdmin.RPC('report:create',{message=v},function(r) if r.ok then notify(('Report #%s submitted.'):format(r.data.id)) else notify(r.error or 'Report failed') end end) end end)

RegisterNetEvent('rs-admin:client:weapon',function(d)
    local p=PlayerPedId()
    if d.action=='give' then GiveWeaponToPed(p,joaat(d.weapon),math.floor(d.ammo or 250),false,true)
    elseif d.action=='all' then for _,w in ipairs(d.weapons or {}) do GiveWeaponToPed(p,joaat(w.name),w.ammo or 250,false,false) end
    elseif d.action=='removeAll' then RemoveAllPedWeapons(p,true)
    elseif d.action=='maxAmmo' then
        for _,w in ipairs(d.weapons or Config.Weapons) do local h=joaat(w.name); if HasPedGotWeapon(p,h,false) then SetPedAmmo(p,h,9999) end end
    end
end)

RegisterNetEvent('rs-admin:client:world',function(d)
    if d.weather then SetWeatherTypeOvertimePersist(d.weather,2.0); Wait(2000); SetWeatherTypeNowPersist(d.weather) end
    if d.hour then NetworkOverrideClockTime(d.hour,d.minute or 0,0) end
    if d.blackout~=nil then SetArtificialLightsState(d.blackout==true); SetArtificialLightsStateAffectsVehicles(false) end
end)

RegisterNetEvent('rs-admin:client:vehicleSpawned',function(d)
    local untilAt=GetGameTimer()+5000
    while GetGameTimer()<untilAt do
        local v=NetworkGetEntityFromNetworkId(d.netId)
        if v and v~=0 and DoesEntityExist(v) then
            SetVehicleOnGroundProperly(v); TaskWarpPedIntoVehicle(PlayerPedId(),v,-1); SetVehicleEngineOn(v,true,true,false)
            if d.admin then
                SetVehicleModKit(v,0)
                for _,slot in ipairs({11,12,13,15,16}) do local n=GetNumVehicleMods(v,slot); if n and n>0 then SetVehicleMod(v,slot,n-1,false) end end
                ToggleVehicleMod(v,18,true); SetVehicleFixed(v); SetVehicleDeformationFixed(v); SetVehicleDirtLevel(v,0.0)
                SetVehicleEngineHealth(v,1000.0); SetVehicleBodyHealth(v,1000.0); SetVehiclePetrolTankHealth(v,1000.0)
                SetVehicleNumberPlateText(v,Config.AdminVehiclePlate or 'RSADMIN'); SetEntityInvincible(v,true); SetVehicleTyresCanBurst(v,false); SetVehicleCanBeVisiblyDamaged(v,false)
                notify('RS command vehicle ready.')
            end
            return
        end
        Wait(50)
    end
end)

local function forceCleanup()
    local ownedFocus=(RSAdmin.uiMode=='FULL' or RSAdmin.dockInteracting)
    if ownedFocus then SetNuiFocus(false,false); SetNuiFocusKeepInput(false) end
    RSAdmin.BeginBootstrap()
    RSAdmin.open=false; RSAdmin.uiMode='HIDDEN'; RSAdmin.dockInteracting=false
    FreezeEntityPosition(PlayerPedId(),false)
    SendNUIMessage({type='uiMode',mode='HIDDEN'})
end
RegisterNetEvent('rs-admin:client:forceCleanup',forceCleanup)
AddEventHandler('onResourceStop',function(res) if res==GetCurrentResourceName() then forceCleanup() end end)


AddEventHandler('onClientResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    CreateThread(function()
        Wait(250)
        -- Do not call SetNuiFocus(false, false) during Qbox character selection.
        -- A newly loaded admin UI has never owned focus.
        RSAdmin.BeginBootstrap()
        RSAdmin.open=false; RSAdmin.uiMode='HIDDEN'
        SendNUIMessage({type='uiMode',mode='HIDDEN'})
        print('[rs-adminmenu] startup failsafe: page hidden, character-selection focus untouched')
    end)
end)
