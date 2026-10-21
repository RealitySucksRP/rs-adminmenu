local C=RSAdminCore
if not C then error('RSAdminCore unavailable') end
local A=RSAdminServer and RSAdminServer.Adapter
local H,Can,Clean,Ok,Err,Audit=C.Handle,C.Can,C.Clean,C.Ok,C.Err,C.Audit
local function target(v) v=tonumber(v); return v and GetPlayerName(v) and v or nil end
local function safe(src,t) if not t then return false,'Player not found' end; if not C.CharacterIdentity(t) then return false,'Target character is not loaded' end; if C.TargetProtected(src,t) then return false,'Owner-protected player' end; return true end
local function relayAction(src,d,action,extra)
    local t=target(d.target); local good,e=safe(src,t); if not good then return Err(e) end
    local payload={action=action,by=GetPlayerName(src) or 'Staff'}; for k,v in pairs(extra or {}) do payload[k]=v end
    TriggerClientEvent('rs-admin:client:adminAction',t,payload); Audit(src,'player '..action,'',GetPlayerName(t)); return Ok(true)
end
H('player:slap','players',function(src,d) return relayAction(src,d,'slap',{force=math.max(1.0,math.min(20.0,tonumber(d.force) or Config.PlayerActions.slapForce or 6.0))}) end)
H('player:handcuff','players',function(src,d) return relayAction(src,d,'handcuff') end)
H('player:uncuff','players',function(src,d) return relayAction(src,d,'uncuff') end)
H('player:setPed','players',function(src,d)
    if not Config.PlayerActions.setPedAllowed then return Err('Set ped disabled') end
    local model=Clean(d.model or '',64); if model=='' or not model:match('^[%w_%-]+$') then return Err('Invalid ped model') end
    return relayAction(src,d,'setPed',{model=model})
end)
H('player:seat','players',function(src,d) return relayAction(src,d,'seat',{seat=math.max(-1,math.min(6,math.floor(tonumber(d.seat) or -1)))}) end)
H('player:eject','players',function(src,d) return relayAction(src,d,'eject') end)
local function removeTargetWeapons(src,d)
    local t=target(d.target);local good,e=safe(src,t);if not good then return Err(e) end
    local result,reason=RSAdminServer.RemovePlayerWeapons(t)
    Audit(src,'remove target weapons',result and result.delivery or reason,GetPlayerName(t))
    return result and Ok(result) or Err(reason)
end
H('player:strip','moderate',removeTargetWeapons)
H('player:cleanVehicle','vehicles',function(src,d) return relayAction(src,d,'cleanVehicle') end)
H('player:maxVehicle','vehicles',function(src,d) return relayAction(src,d,'maxVehicle') end)
H('player:refuelVehicle','vehicles',function(src,d) return relayAction(src,d,'refuelVehicle') end)
H('player:flipVehicle','vehicles',function(src,d) return relayAction(src,d,'flipVehicle') end)
H('player:deleteCurrentVehicle','vehicles',function(src,d)
    local t=target(d.target); local good,e=safe(src,t); if not good then return Err(e) end; local ped=GetPlayerPed(t); if not ped or ped==0 then return Err('Target ped unavailable') end
    local vehicle=0; pcall(function() vehicle=GetVehiclePedIsIn(ped,false) or 0 end); if vehicle==0 or not DoesEntityExist(vehicle) then return Err('Player is not in a vehicle') end
    if C.ProtectedVehicleOccupant(src,vehicle) then return Err('Owner-protected player is inside this vehicle') end
    DeleteEntity(vehicle); Audit(src,'delete current vehicle','',GetPlayerName(t)); return Ok(true)
end)
H('player:giveVehicleKeys','vehicles',function(src,d)
    local t=target(d.target); local good,e=safe(src,t); if not good then return Err(e) end; if not A or not A.GiveKeys then return Err('Vehicle keys provider unavailable') end
    local ped=GetPlayerPed(t); local vehicle=0; if ped and ped~=0 then pcall(function() vehicle=GetVehiclePedIsIn(ped,false) or 0 end) end; if vehicle==0 then return Err('Player is not in a vehicle') end
    local session=C.SessionIdentity(t)
    local ok,reason=A.GiveKeys(t,vehicle)
    if C.SessionIdentity(t)~=session then return Err('Target session changed while granting keys') end
    if ok~=true then return Err(reason or 'Vehicle keys provider did not confirm the grant') end
    Audit(src,'give current vehicle keys','',GetPlayerName(t)); return Ok(true)
end)
H('weapon:removeTarget','weapons',removeTargetWeapons)
