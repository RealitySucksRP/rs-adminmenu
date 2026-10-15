RSAdmin.LocalActions = RSAdmin.LocalActions or {}
RSAdmin.Power = RSAdmin.Power or {}
local P=RSAdmin.Power
P.state={
    god=false,invisible=false,superjump=false,fastrun=false,fastswim=false,stamina=false,
    infiniteammo=false,noreload=false,explosiveammo=false,fireammo=false,explosivemelee=false,
    thermal=false,nightvision=false,noragdoll=false,neverwanted=false,ignored=false,policeignore=false,
    meleeboost=false,weaponboost=false,vehiclegod=false
}

local function requirePower() return RSAdmin.Can('developer') or RSAdmin.Can('owner') end
RSAdmin.LocalActions.operatorCoords=function()
    if not requirePower() then return {ok=false,error='Permission denied'} end
    local p=PlayerPedId(); local c=GetEntityCoords(p); local h=GetEntityHeading(p)
    return {ok=true,data={x=c.x,y=c.y,z=c.z,heading=h,text=('vector4(%.2f, %.2f, %.2f, %.2f)'):format(c.x,c.y,c.z,h)}}
end
local function resetWeaponAmmoFlags(ped)
    for _,w in ipairs(Config.Weapons or {}) do local h=joaat(w.name); if HasPedGotWeapon(ped,h,false) then SetPedInfiniteAmmo(ped,false,h) end end
end

RSAdmin.LocalActions.togglePower=function(d)
    if not requirePower() then return {ok=false,error='Permission denied'} end
    local key=tostring(d.key or '')
    if P.state[key]==nil then return {ok=false,error='Unknown power'} end
    P.state[key]=not P.state[key]
    local ped=PlayerPedId(); local pid=PlayerId(); local on=P.state[key]
    if key=='god' then SetPlayerInvincible(pid,on); SetEntityInvincible(ped,on) end
    if key=='invisible' then SetEntityVisible(ped,not on,false); if on then SetLocalPlayerVisibleLocally(true) end end
    if key=='noreload' then SetPedInfiniteAmmoClip(ped,on) end
    if key=='infiniteammo' and not on then resetWeaponAmmoFlags(ped) end
    if key=='thermal' then SetSeethrough(on) end
    if key=='nightvision' then SetNightvision(on) end
    if key=='noragdoll' then SetPedCanRagdoll(ped,not on) end
    if key=='neverwanted' and not on then SetMaxWantedLevel(5) end
    if key=='ignored' then SetEveryoneIgnorePlayer(pid,on) end
    if key=='policeignore' then SetPoliceIgnorePlayer(pid,on) end
    if key=='meleeboost' then SetPlayerMeleeWeaponDamageModifier(pid,on and 8.0 or 1.0) end
    if key=='weaponboost' then SetPlayerWeaponDamageModifier(pid,on and 4.0 or 1.0) end
    if key=='vehiclegod' and not on then local v=GetVehiclePedIsIn(ped,false); if v~=0 then SetEntityInvincible(v,false); SetVehicleTyresCanBurst(v,true); SetVehicleCanBeVisiblyDamaged(v,true) end end
    return {ok=true,state=P.state}
end

RSAdmin.LocalActions.healSelf=function()
    if not requirePower() then return {ok=false,error='Permission denied'} end
    local p=PlayerPedId(); SetEntityHealth(p,GetEntityMaxHealth(p)); SetPedArmour(p,100); ClearPedBloodDamage(p); ResetPedVisibleDamage(p); return {ok=true}
end

RSAdmin.LocalActions.reviveSelf=function()
    if not requirePower() then return {ok=false,error='Permission denied'} end
    local p=PlayerPedId(); local c=GetEntityCoords(p)
    NetworkResurrectLocalPlayer(c.x,c.y,c.z,GetEntityHeading(p),true,false); ClearPedBloodDamage(p); ResetPedVisibleDamage(p); SetEntityHealth(p,GetEntityMaxHealth(p)); SetPedArmour(p,100)
    return {ok=true}
end

RSAdmin.LocalActions.setWanted=function(d)
    if not requirePower() then return {ok=false,error='Permission denied'} end
    local level=math.max(0,math.min(5,math.floor(tonumber(d.level) or 0))); local pid=PlayerId()
    if P.state.neverwanted then P.state.neverwanted=false end
    SetMaxWantedLevel(5)
    if level==0 then ClearPlayerWantedLevel(pid); SetPlayerWantedLevel(pid,0,false)
    else SetPlayerWantedLevel(pid,level,false); SetPlayerWantedLevelNow(pid,false) end
    return {ok=true,level=level,state=P.state}
end

local function resetPowerEffects()
    local ped=PlayerPedId(); local pid=PlayerId()
    SetPlayerInvincible(pid,false); SetEntityInvincible(ped,false); SetEntityVisible(ped,true,false)
    SetRunSprintMultiplierForPlayer(pid,1.0); SetSwimMultiplierForPlayer(pid,1.0); SetPedMoveRateOverride(ped,1.0)
    SetPedInfiniteAmmoClip(ped,false); resetWeaponAmmoFlags(ped); SetSeethrough(false); SetNightvision(false); SetPedCanRagdoll(ped,true)
    SetMaxWantedLevel(5); ClearPlayerWantedLevel(pid); SetEveryoneIgnorePlayer(pid,false); SetPoliceIgnorePlayer(pid,false)
    SetPlayerMeleeWeaponDamageModifier(pid,1.0); SetPlayerWeaponDamageModifier(pid,1.0)
    local v=GetVehiclePedIsIn(ped,false)
    if v~=0 then SetEntityInvincible(v,false); SetVehicleTyresCanBurst(v,true); SetVehicleCanBeVisiblyDamaged(v,true) end
end

RSAdmin.LocalActions.fullGod=function()
    if not requirePower() then return {ok=false,error='Permission denied'} end
    for key in pairs(P.state) do P.state[key]=false end
    for _,key in ipairs({'god','invisible','superjump','fastrun','fastswim','stamina','infiniteammo','noreload','noragdoll','neverwanted','ignored','policeignore','meleeboost','weaponboost','vehiclegod'}) do
        P.state[key]=true
    end
    local ped=PlayerPedId(); local pid=PlayerId()
    SetEntityHealth(ped,GetEntityMaxHealth(ped)); SetPedArmour(ped,100); ClearPedBloodDamage(ped); ResetPedVisibleDamage(ped)
    SetPlayerInvincible(pid,true); SetEntityInvincible(ped,true); SetEntityVisible(ped,false,false); SetLocalPlayerVisibleLocally(true)
    SetPedInfiniteAmmoClip(ped,true); SetPedCanRagdoll(ped,false); SetMaxWantedLevel(0); ClearPlayerWantedLevel(pid)
    SetEveryoneIgnorePlayer(pid,true); SetPoliceIgnorePlayer(pid,true); SetPlayerMeleeWeaponDamageModifier(pid,8.0); SetPlayerWeaponDamageModifier(pid,4.0)
    local v=GetVehiclePedIsIn(ped,false)
    if v~=0 then SetEntityInvincible(v,true); SetVehicleTyresCanBurst(v,false); SetVehicleCanBeVisiblyDamaged(v,false) end
    return {ok=true,state=P.state}
end

RSAdmin.LocalActions.resetAdminState=function()
    if not requirePower() then return {ok=false,error='Permission denied'} end
    for key in pairs(P.state) do P.state[key]=false end
    resetPowerEffects()
    if RSAdmin.Noclip and RSAdmin.Noclip.Set then RSAdmin.Noclip.Set(false) end
    if RSAdmin.EntityLaser and RSAdmin.EntityLaser.Set then RSAdmin.EntityLaser.Set(false) end
    if RSAdmin.VehicleLab and RSAdmin.VehicleLab.StopRotations then RSAdmin.VehicleLab.StopRotations() end
    if RSAdmin.Pranks and RSAdmin.Pranks.Reset then RSAdmin.Pranks.Reset() end
    if RSAdmin.Spectate and RSAdmin.Spectate.Stop then RSAdmin.Spectate.Stop() end
    RSAdmin.frozen=false
    FreezeEntityPosition(PlayerPedId(),false)
    return {ok=true,state=P.state}
end

RSAdmin.LocalActions.setArmor=function(d)
    if not requirePower() then return {ok=false,error='Permission denied'} end
    local amount=math.max(0,math.min(100,math.floor(tonumber(d.amount) or 100)))
    SetPedArmour(PlayerPedId(),amount)
    return {ok=true,armor=amount}
end

RSAdmin.LocalActions.teleportWaypoint=function()
    if not requirePower() then return {ok=false,error='Permission denied'} end
    local b=GetFirstBlipInfoId(8); if not DoesBlipExist(b) then return {ok=false,error='Set a waypoint first'} end
    local c=GetBlipInfoIdCoord(b); local ped=PlayerPedId()
    for h=1000.0,0.0,-25.0 do SetEntityCoordsNoOffset(ped,c.x,c.y,h,false,false,false); RequestCollisionAtCoord(c.x,c.y,h); Wait(0); local ok,z=GetGroundZFor_3dCoord(c.x,c.y,h,false); if ok then SetEntityCoordsNoOffset(ped,c.x,c.y,z+1.0,false,false,false); return {ok=true} end end
    return {ok=false,error='Could not find ground'}
end

CreateThread(function()
    while true do
        local active=false; local ped=PlayerPedId(); local pid=PlayerId()
        if P.state.god then SetPlayerInvincible(pid,true); SetEntityInvincible(ped,true); active=true end
        if P.state.invisible then SetEntityVisible(ped,false,false); SetLocalPlayerVisibleLocally(true); active=true end
        if P.state.superjump then SetSuperJumpThisFrame(pid); active=true end
        if P.state.fastrun then SetRunSprintMultiplierForPlayer(pid,1.49); SetPedMoveRateOverride(ped,1.49); active=true end
        if P.state.fastswim then SetSwimMultiplierForPlayer(pid,1.49); active=true end
        if P.state.stamina then RestorePlayerStamina(pid,1.0); active=true end
        if P.state.infiniteammo then local w=GetSelectedPedWeapon(ped); if w and w~=joaat('WEAPON_UNARMED') then SetPedInfiniteAmmo(ped,true,w) end; active=true end
        if P.state.noreload then SetPedInfiniteAmmoClip(ped,true); active=true end
        if P.state.explosiveammo then SetExplosiveAmmoThisFrame(pid); active=true end
        if P.state.fireammo then SetFireAmmoThisFrame(pid); active=true end
        if P.state.explosivemelee then SetExplosiveMeleeThisFrame(pid); active=true end
        if P.state.noragdoll then SetPedCanRagdoll(ped,false); active=true end
        if P.state.neverwanted then ClearPlayerWantedLevel(pid); SetMaxWantedLevel(0); active=true end
        if P.state.ignored then SetEveryoneIgnorePlayer(pid,true); active=true end
        if P.state.policeignore then SetPoliceIgnorePlayer(pid,true); active=true end
        if P.state.vehiclegod then local v=GetVehiclePedIsIn(ped,false); if v~=0 then SetEntityInvincible(v,true); SetVehicleTyresCanBurst(v,false); SetVehicleCanBeVisiblyDamaged(v,false) end; active=true end
        Wait(active and 0 or 350)
    end
end)

AddEventHandler('onResourceStop',function(res)
    if res~=GetCurrentResourceName() then return end
    resetPowerEffects()
end)
