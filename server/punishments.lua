local C=RSAdminCore
if not C then error('RSAdminCore unavailable') end
local H,Can,Clean,Ok,Err,Audit=C.Handle,C.Can,C.Clean,C.Ok,C.Err,C.Audit
local RESOURCE=GetCurrentResourceName()
local Adv=RSAdminServer.Advanced or {}
local function load(name,fallback) return C.LoadJson(name,fallback) end
local S={warnings=load('warnings',{}),community_service=load('community_service',{}),staff_notes=load('staff_notes',{}),watchlist=load('watchlist',{})}
local function save(n) C.SaveJson(n,S[n]) end
local function target(v) v=tonumber(v); return v and GetPlayerName(v) and v or nil end
local function primary(src)
    if Adv.Primary then return Adv.Primary(src) end
    local ids=C.Identifiers(src); return ids[1]
end
local function actor(src) return src==0 and 'console' or (GetPlayerName(src) or ('#%s'):format(src)) end
local function hook(title,fields,color) if Adv.Webhook then Adv.Webhook('moderation',title,fields,color or 16753920) end end
local function bounded(t,row,max) t[#t+1]=row; while #t>(max or 1000) do table.remove(t,1) end end
local function nextId(rows) local n=0; for _,r in ipairs(rows) do n=math.max(n,tonumber(r.id) or 0) end; return n+1 end
local function protected(src,t) return C.TargetProtected(src,t) end

H('warning:add','punishments',function(src,d)
    local t=target(d.target); if not t then return Err('Player not found') end; if protected(src,t) then return Err('Owner-protected player') end
    local reason=Clean(d.reason or '',300); if #reason<2 then return Err('Reason required') end
    local row={id=nextId(S.warnings),identifier=primary(t),name=GetPlayerName(t),reason=reason,staff=actor(src),at=os.time(),active=true}; bounded(S.warnings,row,3000); save('warnings'); Audit(src,'warning',reason,row.name); hook('Player warning',{Player=row.name,Reason=reason,Staff=actor(src)},16763904); TriggerClientEvent('rs-admin:client:message',t,{by='Staff Warning',text=reason}); return Ok(row)
end)
H('warning:list','punishments',function(_,d)
    local pid=Clean(d.identifier or '',180); local t=target(d.target); if t then pid=primary(t) end; local out={}; for i=#S.warnings,1,-1 do local r=S.warnings[i]; if pid=='' or r.identifier==pid then out[#out+1]=r end end; return Ok(out)
end)

local function activeService(pid)
    if not pid then return end
    for _,r in ipairs(S.community_service) do if r.identifier==pid and not r.completedAt and not r.removedAt and (tonumber(r.remaining) or 0)>0 then return r end end
end
local function syncService(t)
    local r=activeService(C.CharacterIdentity(t)); if r then TriggerClientEvent('rs-admin:client:communityService',t,{id=r.id,remaining=r.remaining,reason=r.reason,coords=Config.Punishments.communityServiceCoords,choreIndex=tonumber(r.choreIndex) or 1,offsets=Config.Punishments.communityServiceOffsets}) end
end
local chores={}
C.OnCharacterReady('communityService',syncService)
C.OnCharacterUnload('punishments',function(src)
    chores[src]=nil
    TriggerClientEvent('rs-admin:client:clearPunishments',src,{})
end)
H('communityService:add','punishments',function(src,d)
    local t=target(d.target); if not t then return Err('Player not found') end; if protected(src,t) then return Err('Owner-protected player') end
    local count=math.max(1,math.min(Config.Punishments.maxCommunityService or 1000,math.floor(tonumber(d.count) or Config.Punishments.communityServiceDefault or 20))); local reason=Clean(d.reason or 'Community service',300)
    local pid=C.CharacterIdentity(t);if not pid then return Err('Target character is not loaded') end
    if activeService(pid) then return Err('This character already has active community service') end
    local row={id=nextId(S.community_service),identifier=pid,name=GetPlayerName(t),count=count,remaining=count,reason=reason,staff=actor(src),created=os.time(),lastComplete=0,choreIndex=1}; S.community_service[#S.community_service+1]=row; save('community_service'); syncService(t); Audit(src,'community service',('%s tasks | %s'):format(count,reason),row.name); hook('Community service assigned',{Player=row.name,Tasks=count,Reason=reason,Staff=actor(src)},16763904); return Ok(row)
end)
local function choreAtPlayer(src,d)
    local pid=C.CharacterIdentity(src);local r=activeService(pid)
    if not r or tonumber(r.id)~=tonumber(d.id) then return nil,'No active community service' end
    local base=Config.Punishments.communityServiceCoords or {}; local offsets=Config.Punishments.communityServiceOffsets or {}
    local idx=math.max(1,math.min(#offsets,tonumber(r.choreIndex) or 1)); local off=offsets[idx]
    if not off then return nil,'Community service chore configuration missing' end
    local ped=GetPlayerPed(src); if not ped or ped==0 then return nil,'Player entity unavailable' end
    local pos=GetEntityCoords(ped); local x=(tonumber(base.x) or 0)+(tonumber(off[1]) or 0); local y=(tonumber(base.y) or 0)+(tonumber(off[2]) or 0); local z=tonumber(base.z) or 0
    local dx,dy,dz=pos.x-x,pos.y-y,pos.z-z; local radius=tonumber(Config.Punishments.communityServiceRadius) or 2.25
    if dx*dx+dy*dy+dz*dz > radius*radius then
        Audit(src,'SECURITY community service rejected',('chore %s distance %.2f'):format(idx,math.sqrt(dx*dx+dy*dy+dz*dz)),r.name)
        return nil,'You are not at the assigned chore'
    end
    return r,idx
end
H('communityService:begin',nil,function(src,d)
    local r,idx=choreAtPlayer(src,d);if not r then return Err(idx) end
    if chores[src] and GetGameTimer()<chores[src].expires then return Err('Finish the current chore first') end
    local token=('%s:%s:%s'):format(r.id,GetGameTimer(),math.random(100000,999999))
    chores[src]={id=r.id,index=idx,session=C.SessionIdentity(src),bucket=GetPlayerRoutingBucket(src),token=token,started=GetGameTimer(),expires=GetGameTimer()+30000}
    return Ok({token=token})
end)
H('communityService:complete',nil,function(src,d)
    local r,idx=choreAtPlayer(src,d);if not r then return Err(idx) end
    local offsets=Config.Punishments.communityServiceOffsets or {}
    local task=chores[src];local tick=GetGameTimer()
    if not task or task.id~=r.id or task.index~=idx or task.token~=d.token or task.session~=C.SessionIdentity(src) or task.bucket~=GetPlayerRoutingBucket(src) or tick>=task.expires or tick-task.started<3000 then return Err('Start and finish the assigned chore before claiming progress') end
    chores[src]=nil
    local now=os.time()
    r.lastComplete=now; r.remaining=math.max(0,(tonumber(r.remaining) or 0)-1)
    if r.remaining<=0 then r.completedAt=now; r.completedBy='player'; TriggerClientEvent('rs-admin:client:communityServiceStop',src,{reason='Community service complete'})
    else r.choreIndex=(idx % #offsets)+1; syncService(src) end
    save('community_service'); return Ok({remaining=r.remaining,choreIndex=r.choreIndex})
end)
H('communityService:remove','punishments',function(src,d)
    local t=target(d.target); local pid=t and C.CharacterIdentity(t) or Clean(d.identifier or '',180); local r=activeService(pid); if not r then return Err('No active community service') end
    local affected={};for _,id in ipairs(GetPlayers()) do local player=tonumber(id);if C.CharacterIdentity(player)==pid then if protected(src,player) then return Err('Owner-protected player') end;affected[#affected+1]=player end end
    r.removedAt=os.time(); r.removedBy=actor(src); r.removeReason=Clean(d.reason or 'Removed by staff',200); save('community_service');for _,player in ipairs(affected) do chores[player]=nil;TriggerClientEvent('rs-admin:client:communityServiceStop',player,{reason=r.removeReason}) end; Audit(src,'remove community service',r.removeReason,r.name); return Ok(r)
end)
H('communityService:list','punishments',function()
    local rows={};local framework=RSAdminServer.Adapter.Framework()
    for _,r in ipairs(S.community_service) do
        local row={};for k,v in pairs(r) do row[k]=v end
        row.legacy=(framework=='qbox' or framework=='qbcore') and tostring(r.identifier):sub(1,10)~='character:'
        rows[#rows+1]=row
    end
    return Ok(rows)
end)

H('staffNote:add','punishments',function(src,d)
    local t=target(d.target); local pid=t and primary(t) or Clean(d.identifier or '',180); if not pid or pid=='' then return Err('Player/identifier required') end; local note=Clean(d.note or '',500); if #note<2 then return Err('Note required') end
    local row={id=nextId(S.staff_notes),identifier=pid,name=t and GetPlayerName(t) or Clean(d.name or 'Offline player',100),note=note,staff=actor(src),at=os.time(),active=true}; S.staff_notes[#S.staff_notes+1]=row; save('staff_notes'); Audit(src,'staff note',note,row.name); hook('Staff note added',{Player=row.name,Note=note,Staff=actor(src)},3447003); return Ok(row)
end)
H('staffNote:list','punishments',function(_,d) local pid=Clean(d.identifier or '',180); local t=target(d.target); if t then pid=primary(t) end; local out={}; for i=#S.staff_notes,1,-1 do local r=S.staff_notes[i]; if r.active~=false and (pid=='' or r.identifier==pid) then out[#out+1]=r end end; return Ok(out) end)
H('staffNote:remove','punishments',function(src,d) for _,r in ipairs(S.staff_notes) do if tonumber(r.id)==tonumber(d.id) then r.active=false;r.removedAt=os.time();r.removedBy=actor(src);save('staff_notes');Audit(src,'remove staff note','#'..r.id,r.name);return Ok(true) end end; return Err('Note not found') end)

H('watchlist:add','punishments',function(src,d)
    local t=target(d.target); local pid=t and primary(t) or Clean(d.identifier or '',180); if not pid or pid=='' then return Err('Player/identifier required') end; local note=Clean(d.note or '',Config.Punishments.watchlistMaxNote or 500); if #note<2 then return Err('Reason required') end
    for _,r in ipairs(S.watchlist) do if r.identifier==pid and r.active~=false then r.note=note;r.updated=os.time();r.updatedBy=actor(src);save('watchlist');return Ok(r) end end
    local row={id=nextId(S.watchlist),identifier=pid,name=t and GetPlayerName(t) or Clean(d.name or 'Offline player',100),note=note,staff=actor(src),created=os.time(),active=true}; S.watchlist[#S.watchlist+1]=row; save('watchlist'); Audit(src,'watchlist add',note,row.name); hook('Watchlist flag added',{Player=row.name,Reason=note,Staff=actor(src)},15105570); return Ok(row)
end)
H('watchlist:remove','punishments',function(src,d) for _,r in ipairs(S.watchlist) do if tonumber(r.id)==tonumber(d.id) then r.active=false;r.removedAt=os.time();r.removedBy=actor(src);save('watchlist');Audit(src,'watchlist remove','#'..r.id,r.name);return Ok(true) end end; return Err('Watchlist row not found') end)
H('watchlist:list','punishments',function() local out={}; for i=#S.watchlist,1,-1 do if S.watchlist[i].active~=false then out[#out+1]=S.watchlist[i] end end; return Ok(out) end)

AddEventHandler('playerDropped',function() chores[source]=nil end)
