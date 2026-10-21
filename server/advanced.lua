local C=RSAdminCore
if not C then error('RSAdminCore unavailable') end
local A=RSAdminServer.Adapter
local H,Can,Audit,Clean,Ok,Err=C.Handle,C.Can,C.Audit,C.Clean,C.Ok,C.Err
local RESOURCE=GetCurrentResourceName()

local function load(name,fallback)
    return C.LoadJson(name,fallback)
end
local STORE={
    staff=load('staff',{}),stats=load('stats',{}),sessions=load('sessions',{}),transactions=load('transactions',{}),
    jails=load('jails',{}),builder=load('builder',{}),widgets=load('widgets',{}),activity=load('activity',{})
}
local joinedAt={}
local staffChat={}
local builderSeq=0
for _,row in ipairs(STORE.builder) do builderSeq=math.max(builderSeq,tonumber(row.id) or 0) end

local function save(name) C.SaveJson(name,STORE[name]) end
local function ids(src) return C.Identifiers(src) end
local function primary(src)
    local order={'license:','license2:','fivem:','discord:','steam:'}
    local list=ids(src)
    for _,prefix in ipairs(order) do for _,id in ipairs(list) do if id:sub(1,#prefix)==prefix then return id end end end
    return list[1]
end
local function jailIdentity(src)
    return C.CharacterIdentity(src)
end
local function tokens(src)
    local out={}; local n=GetNumPlayerTokens(src) or 0
    for i=0,n-1 do local t=GetPlayerToken(src,i); if t and t~='' then out[#out+1]=t end end
    return out
end
local function actor(src) return src==0 and 'console' or (GetPlayerName(src) or ('#%s'):format(src)) end
local function target(src) src=tonumber(src); return src and GetPlayerName(src) and src or nil end
local function pushBounded(t,row,max)
    t[#t+1]=row; while #t>(max or 1000) do table.remove(t,1) end
end
local function roleDef(role)
    if RSAdminServer and RSAdminServer.CustomStaffRoles and RSAdminServer.CustomStaffRoles[role] then return RSAdminServer.CustomStaffRoles[role] end
    return Config.StaffRoles and Config.StaffRoles[role]
end
local function rankOfRole(role) local r=roleDef(role); return r and tonumber(r.rank) or 0 end
local function staffEntry(src)
    local pid=primary(src); if not pid then return end
    local e=STORE.staff[pid]
    -- Reject an expired role immediately, even before the periodic expiry
    -- cleanup persists the removal. Never grant permissions during that gap.
    if e and (tonumber(e.expires) or 0)>0 and tonumber(e.expires)<=os.time() then
        return nil,pid
    end
    return e,pid
end
function RSAdminServer.RoleAllows(src,node)
    local e=staffEntry(src); if not e then return false end
    local def=roleDef(e.role); if not def then return false end
    if def.wildcard then return true end
    for _,p in ipairs(def.permissions or {}) do if p==node or p=='all' then return true end end
    return node=='open'
end
local function staffRole(src)
    if C.Can(src,'owner') then return 'owner',roleDef('owner') end
    local e=staffEntry(src); if e then return e.role,roleDef(e.role) end
end
local function staffRank(src) local _,def=staffRole(src); return def and tonumber(def.rank) or 0 end
RSAdminServer.GetStaffRole=staffRole
RSAdminServer.GetStaffRank=staffRank

local function webhook(channel,title,fields,color)
    if not (Config.Webhooks and Config.Webhooks.enabled) then return end
    local url=Config.Webhooks[channel]; if not url or url=='' then return end
    local embed={title=title,color=color or 3447003,fields={},footer={text='rs-adminmenu'},timestamp=os.date('!%Y-%m-%dT%H:%M:%SZ')}
    for k,v in pairs(fields or {}) do embed.fields[#embed.fields+1]={name=tostring(k),value=tostring(v):sub(1,1000),inline=true} end
    PerformHttpRequest(url,function() end,'POST',json.encode({username='RS Admin',embeds={embed}}),{['Content-Type']='application/json'})
end
RSAdminServer.Webhook=webhook

function RSAdminServer.OnAudit(row)
    pushBounded(STORE.activity,row,Config.Stats.maxActivityRows or 2500); save('activity')
end

local function ensureStats(src)
    local pid=primary(src); if not pid then return end
    local now=os.time(); local s=STORE.stats[pid] or {identifier=pid,firstSeen=now,totalSeconds=0,sessions=0,last7={},last30={}}
    s.name=GetPlayerName(src) or s.name; s.lastSeen=now; STORE.stats[pid]=s; return s,pid
end
local function startSession(src)
    local s,pid=ensureStats(src); if not s then return end
    if not joinedAt[src] then joinedAt[src]=os.time(); s.sessions=(s.sessions or 0)+1; save('stats') end
    return s,pid
end
local function finishSession(src)
    local started=joinedAt[src]; if not started then return end
    local s,pid=ensureStats(src); if not s then joinedAt[src]=nil; return end
    local now=os.time(); local seconds=math.max(0,now-started); s.totalSeconds=(s.totalSeconds or 0)+seconds; s.lastSeen=now
    STORE.sessions[pid]=STORE.sessions[pid] or {}; pushBounded(STORE.sessions[pid],{start=started,finish=now,seconds=seconds},Config.Stats.maxSessionHistoryPerPlayer or 90)
    joinedAt[src]=nil; save('stats'); save('sessions')
end
local function currentSeconds(src)
    local s=joinedAt[src]; return s and math.max(0,os.time()-s) or 0
end
local function playtimeFor(src)
    local st=ensureStats(src); if not st then return {} end
    local total=(st.totalSeconds or 0)+currentSeconds(src)
    return {totalSeconds=total,totalHours=total/3600,totalDays=total/86400,currentSeconds=currentSeconds(src),sessions=st.sessions or 0,firstSeen=st.firstSeen,lastSeen=st.lastSeen}
end

local function onlineProfile(src,viewer)
    src=target(src); if not src then return end
    local data=A and A.GetPlayerData(src) or nil
    local ped=GetPlayerPed(src); local c=ped and ped~=0 and GetEntityCoords(ped) or vector3(0,0,0)
    local vehicle=0
    if ped and ped~=0 then pcall(function() vehicle=GetVehiclePedIsIn(ped,false) or 0 end) end
    local job=data and data.job or {}; local gang=data and data.gang or {}
    local cash=A and A.GetMoney(src,'cash') or 0; local bank=A and A.GetMoney(src,'bank') or 0
    local health,armour,dead=0,0,false
    local meta=data and data.metadata or {}
    local laststand=meta.inlaststand==true
    if ped and ped~=0 then
        pcall(function() health=GetEntityHealth(ped) or 0 end)
        pcall(function() armour=GetPedArmour(ped) or 0 end)
        dead = meta.isdead==true or laststand or health <= 0
    end
    local canSecurity=viewer and (Can(viewer,'security') or Can(viewer,'owner')) or false
    local sensitiveIds=canSecurity and ids(src) or nil
    local endpoint=canSecurity and GetPlayerEndpoint(src) or nil
    return {
        id=src,name=GetPlayerName(src),characterName=data and data.charinfo and Clean((data.charinfo.firstname or '')..' '..(data.charinfo.lastname or ''),80) or nil,ping=GetPlayerPing(src),bucket=GetPlayerRoutingBucket(src),x=c.x,y=c.y,z=c.z,
        identifiers=sensitiveIds,endpoint=endpoint,citizenid=data and data.citizenid or nil,job=job,gang=gang,cash=cash or 0,bank=bank or 0,
        health=health,armour=armour,dead=dead,laststand=laststand,wealth=(cash or 0)+(bank or 0),playtime=playtimeFor(src),currentVehicle=(function()
            if vehicle==0 or not DoesEntityExist(vehicle) then return nil end
            local info={}; pcall(function() info.netId=NetworkGetNetworkIdFromEntity(vehicle) end); pcall(function() info.model=GetEntityModel(vehicle) end); pcall(function() info.plate=GetVehicleNumberPlateText(vehicle) end); return info
        end)()
    }
end

local function activeJailForIdentifier(pid)
    local now=os.time()
    for _,j in ipairs(STORE.jails) do if not j.releasedAt and j.identifier==pid and (j.expires==0 or j.expires>now) then return j end end
end
local function jailPayload(j)
    local cells=Config.Jail.cells or {}; local cell=cells[math.max(1,math.min(#cells,tonumber(j.cell) or 1))] or cells[1]
    return {id=j.id,reason=j.reason,expires=j.expires,coords=cell,release=Config.Jail.release,leashRadius=Config.Jail.leashRadius}
end
local function syncJail(src)
    local j=activeJailForIdentifier(jailIdentity(src)); if j then TriggerClientEvent('rs-admin:client:jail',src,jailPayload(j)) end
end
C.OnCharacterReady('jail',syncJail)

local function transaction(kind,from,to,account,amount,reason,staff,beforeFrom,afterFrom,beforeTo,afterTo)
    local row={id=('%d-%06d'):format(os.time(),math.random(0,999999)),at=os.time(),kind=kind,from=from,to=to,account=account,amount=amount,reason=reason,staff=staff,beforeFrom=beforeFrom,afterFrom=afterFrom,beforeTo=beforeTo,afterTo=afterTo}
    pushBounded(STORE.transactions,row,Config.Economy.maxTransactions or 2000); save('transactions')
    if amount>=(Config.Economy.webhookAbove or math.huge) then webhook('economy','High-value economy transaction',{Amount=('$%s'):format(amount),Account=account,From=from or 'system',To=to or 'system',Staff=staff or '-',Reason=reason or '-'},16753920) end
    return row
end
local function transfersToday(identifier)
    local now=os.time(); local day=now-86400; local total=0
    for i=#STORE.transactions,1,-1 do local r=STORE.transactions[i]; if (r.at or 0)<day then break end; if r.kind=='player_transfer' and r.from==identifier then total=total+(tonumber(r.amount) or 0) end end
    return total
end
local function authorizeTransfer(fromSrc,toSrc,amount,account)
    amount=tonumber(amount);if not amount or amount~=amount or math.abs(amount)==math.huge then return false,'invalid amount' end
    amount=math.floor(amount); account=tostring(account or 'bank')
    if amount<=0 then return false,'invalid amount' end
    if amount>(Config.Economy.maxPlayerTransfer or 500000) then return false,'transfer exceeds server limit' end
    local fromId=primary(fromSrc); if not fromId then return false,'sender identifier unavailable' end
    if transfersToday(fromId)+amount>(Config.Economy.dailyPlayerTransferLimit or math.huge) then return false,'daily transfer limit exceeded' end
    if not (Config.Economy.accounts and Config.Economy.accounts[account]) then return false,'account not allowed' end
    return true
end

local function dashboardSummary()
    local players={}; local cash,bank,vehicles=0,0,0
    local onlineStaff=0
    for _,s in ipairs(GetPlayers()) do if Can(tonumber(s),'open') then onlineStaff=onlineStaff+1 end end
    vehicles=#GetAllVehicles()
    for _,s in ipairs(GetPlayers()) do local id=tonumber(s); local p=onlineProfile(id); if p then players[#players+1]=p; cash=cash+(p.cash or 0); bank=bank+(p.bank or 0) end end
    table.sort(players,function(a,b) return (a.wealth or 0)>(b.wealth or 0) end)
    local openReports=0; for _,r in ipairs(C.Data.reports or {}) do if r.status~='closed' then openReports=openReports+1 end end
    local activeBans=0; local now=os.time(); for _,b in ipairs(C.Data.bans or {}) do if not b.revoked and (not b.expires or b.expires==0 or b.expires>now) then activeBans=activeBans+1 end end
    local activeJails=0; for _,j in ipairs(STORE.jails) do if not j.releasedAt and (j.expires==0 or j.expires>now) then activeJails=activeJails+1 end end
    local high={}; for i=#STORE.transactions,math.max(1,#STORE.transactions-15),-1 do local r=STORE.transactions[i]; if r and (r.amount or 0)>=(Config.Economy.highValueThreshold or 100000) then high[#high+1]=r end end
    local onDutyStaff=(RSAdminOperations and RSAdminOperations.DutyCount and RSAdminOperations.DutyCount()) or 0
    local kicks24h,totalSessions,totalSeconds=0,0,0
    local hourly={}; for i=1,24 do hourly[i]=0 end
    local heat={}; for d=1,7 do heat[d]={}; for h=1,24 do heat[d][h]=0 end end
    local nowTs=os.time(); local dayAgo=nowTs-86400; local weekAgo=nowTs-(7*86400)
    for _,st in pairs(STORE.stats or {}) do totalSessions=totalSessions+(tonumber(st.sessions) or 0); totalSeconds=totalSeconds+(tonumber(st.totalSeconds) or 0) end
    for _,r in ipairs(STORE.activity or {}) do
        local at=tonumber(r.at) or 0
        if at>=dayAgo then
            local h=tonumber(os.date('%H',at)) or 0; hourly[h+1]=(hourly[h+1] or 0)+1
            if tostring(r.action or ''):lower():find('kick',1,true) then kicks24h=kicks24h+1 end
        end
        if at>=weekAgo then
            local age=math.floor((nowTs-at)/86400); local day=math.max(1,math.min(7,7-age)); local h=tonumber(os.date('%H',at)) or 0; heat[day][h+1]=(heat[day][h+1] or 0)+1
        end
    end
    return {onlinePlayers=#players,onlineStaff=onlineStaff,vehicleCount=vehicles,openReports=openReports,activeBans=activeBans,activeJails=activeJails,onDutyStaff=onDutyStaff,kicks24h=kicks24h,totalSessions=totalSessions,averageSessionSeconds=totalSessions>0 and (totalSeconds/totalSessions) or 0,hourlyActivity=hourly,activityHeatmap=heat,cash=cash,bank=bank,totalEconomy=cash+bank,richest={players[1],players[2],players[3]},highValue=high,recentActions={table.unpack(STORE.activity,math.max(1,#STORE.activity-9),#STORE.activity)}}
end
RSAdminServer.Advanced={DashboardSummary=dashboardSummary, Store=STORE, Primary=primary, Target=target, Actor=actor, RoleDef=roleDef, StaffRank=staffRank, Webhook=webhook}
RSAdminServer.Advanced.AuthorizeTransfer=authorizeTransfer
RSAdminServer.Advanced.RecordTransaction=transaction

-- Lifecycle / playtime ---------------------------------------------------------
AddEventHandler('playerJoining',function()
    local src=source;startSession(src)
end)
AddEventHandler('playerDropped',function() finishSession(source) end)
AddEventHandler('onResourceStart',function(res)
    if res~=RESOURCE then return end
    for _,s in ipairs(GetPlayers()) do startSession(tonumber(s)) end
end)
CreateThread(function() while true do Wait((Config.Stats.updateSeconds or 60)*1000); for _,s in ipairs(GetPlayers()) do ensureStats(tonumber(s)) end; save('stats') end end)

-- Dashboard / profiles ---------------------------------------------------------
H('dashboard:summary','open',function() return Ok(dashboardSummary()) end)
H('player:profile','players',function(src,d) local p=onlineProfile(d.target,src); return p and Ok(p) or Err('Player not found') end)
H('player:inventory','inventory',function(_,d) local t=target(d.target); return t and Ok(A.GetInventory(t)) or Err('Player not found') end)
H('player:vehicles','garage',function(_,d) local t=target(d.target); return t and Ok(A.GetOwnedVehicles(t)) or Err('Player not found') end)
H('player:stats','players',function(_,d) local t=target(d.target); return t and Ok(playtimeFor(t)) or Err('Player not found') end)
H('player:history','players',function(_,d)
    local t=target(d.target); if not t then return Err('Player not found') end; local pid=primary(t); local out={}
    for i=#STORE.activity,1,-1 do local r=STORE.activity[i]; if r.target==GetPlayerName(t) or r.identifier==pid then out[#out+1]=r; if #out>=100 then break end end end
    return Ok(out)
end)
H('players:search','players',function(src,d)
    local q=Clean(d.q or '',120):lower(); local rows={}; local security=Can(src,'security') or Can(src,'owner')
    if #q < (Config.PlayerSearch.minQueryLength or 1) then return Ok(C.PlayerSummary()) end
    for _,sid in ipairs(GetPlayers()) do
        local id=tonumber(sid); local p=onlineProfile(id,src)
        if p then
            local data=A and A.GetPlayerData(id) or nil; local job=data and data.job or {}; local gang=data and data.gang or {}
            local fields={tostring(id),p.name or '',p.citizenid or '',job.name or '',job.label or '',gang.name or '',gang.label or ''}
            if security then
                for _,ident in ipairs(ids(id)) do fields[#fields+1]=ident end
                fields[#fields+1]=GetPlayerEndpoint(id) or ''
            end
            local hay=table.concat(fields,' '):lower()
            if hay:find(q,1,true) then rows[#rows+1]=p end
            if #rows >= (Config.PlayerSearch.maxResults or 128) then break end
        end
    end
    table.sort(rows,function(a,b) return a.id<b.id end); return Ok(rows)
end)
H('players:ranked','players',function(_,d)
    local mode=Clean(d.mode or 'wealth',24); local rows={}
    for _,s in ipairs(GetPlayers()) do local p=onlineProfile(tonumber(s)); if p then p.vehicleCount=#(A.GetOwnedVehicles(p.id) or {}); rows[#rows+1]=p end end
    local key=mode=='bank' and 'bank' or mode=='cash' and 'cash' or mode=='vehicles' and 'vehicleCount' or mode=='playtime' and nil or 'wealth'
    table.sort(rows,function(a,b) if mode=='playtime' then return (a.playtime.totalSeconds or 0)>(b.playtime.totalSeconds or 0) end return (a[key] or 0)>(b[key] or 0) end); return Ok(rows)
end)

-- Economy ----------------------------------------------------------------------
H('economy:summary','economy',function() return Ok(dashboardSummary()) end)
H('economy:transactions','economy',function(_,d)
    local q=Clean(d.q or '',80):lower(); local page=math.max(1,math.floor(tonumber(d.page) or 1)); local size=math.max(10,math.min(100,math.floor(tonumber(d.pageSize) or 40))); local rows={}
    for i=#STORE.transactions,1,-1 do local r=STORE.transactions[i]; local hay=json.encode(r):lower(); if q=='' or hay:find(q,1,true) then rows[#rows+1]=r end end
    local total=#rows; local first=(page-1)*size+1; local out={}; for i=first,math.min(total,first+size-1) do out[#out+1]=rows[i] end
    return Ok({rows=out,total=total,page=page,pages=math.max(1,math.ceil(total/size))})
end)
H('economy:adjust','economy',function(src,d)
    local t=target(d.target); if not t then return Err('Player not found') end
    local account=Clean(d.account or 'cash',12); if not Config.Economy.accounts[account] then return Err('Account not allowed') end
    if RSAdminServer.TransferBlocked and RSAdminServer.TransferBlocked(t,account) then return Err('Account has an active or unresolved transfer; review recovery first') end
    local mode=Clean(d.mode or 'add',12); if mode~='add' and mode~='remove' and mode~='set' then return Err('Invalid mode') end
    local amount=math.floor(tonumber(d.amount) or 0); if amount<0 or amount>(Config.Economy.maxAdminAdjustment or 5000000) then return Err('Amount outside configured limit') end
    local reason=Clean(d.reason or 'Admin adjustment',180); if amount>=(Config.Economy.requireReasonAbove or math.huge) and #reason<3 then return Err('Reason required for high value adjustment') end
    local before=A.GetMoney(t,account) or 0; local good,e=A.ChangeMoney(t,account,mode,amount,reason); if not good then return Err(e or 'Money action failed') end; local after=A.GetMoney(t,account) or before
    local row=transaction('admin_adjust',nil,primary(t),account,amount,reason,actor(src),nil,nil,before,after); Audit(src,'economy '..mode,('%s $%s | %s'):format(account,amount,reason),GetPlayerName(t)); return Ok({balance=after,transaction=row})
end)
H('economy:transfer','economy',function(src,d)
    return RSAdminServer.TransferMoney(src,d)
end)
exports('AuthorizeTransfer',function(from,to,amount,account) return authorizeTransfer(from,to,amount,account) end)
exports('RecordTransfer',function(from,to,amount,account,reason)
    return transaction('player_transfer',primary(from) or tostring(from),primary(to) or tostring(to),account,amount,reason,'external',nil,nil,nil,nil)
end)

-- Jail -------------------------------------------------------------------------
H('jail:add','moderate',function(src,d)
    local t=target(d.target); if not t then return Err('Player not found') end; if C.TargetProtected(src,t) then return Err('Owner-protected player') end
    local cells=Config.Jail.cells or {}; if #cells<1 then return Err('No jail coordinates configured') end
    local minutes=math.max(1,math.min(Config.Jail.maxMinutes or 1440,math.floor(tonumber(d.minutes) or Config.Jail.defaultMinutes or 10))); local reason=Clean(d.reason or 'Administrative jail',200); if #reason<2 then return Err('Reason required') end
    local pid=jailIdentity(t);if not pid then return Err('Target character is not loaded') end
    local current=activeJailForIdentifier(pid); if current then current.releasedAt=os.time(); current.releaseReason='Replaced by new sentence'; current.releasedBy=actor(src) end
    local j={id=(#STORE.jails+1),identifier=pid,name=GetPlayerName(t),staff=actor(src),reason=reason,minutes=minutes,created=os.time(),expires=os.time()+minutes*60,cell=math.max(1,math.min(#cells,math.floor(tonumber(d.cell) or math.random(1,#cells))))}
    STORE.jails[#STORE.jails+1]=j; save('jails'); TriggerClientEvent('rs-admin:client:jail',t,jailPayload(j)); Audit(src,'jail',('%s min | %s'):format(minutes,reason),j.name); webhook('moderation','Player jailed',{Player=j.name,Minutes=minutes,Reason=reason,Staff=actor(src)},15105570); return Ok(j)
end)
H('jail:remove','moderate',function(src,d)
    local t=target(d.target); local pid=t and jailIdentity(t) or Clean(d.identifier or '',160); if not pid or pid=='' then return Err('Player/identifier required') end
    local j=activeJailForIdentifier(pid); if not j then return Err('No active jail sentence') end; j.releasedAt=os.time(); j.releasedBy=actor(src); j.releaseReason=Clean(d.reason or 'Unjailed by staff',180); save('jails')
    if t then TriggerClientEvent('rs-admin:client:unjail',t,{coords=Config.Jail.release,reason=j.releaseReason}) end; Audit(src,'unjail',j.releaseReason,j.name); return Ok(j)
end)
H('jail:list','moderate',function() local now=os.time(); local out={}; for _,j in ipairs(STORE.jails) do if not j.releasedAt and (j.expires==0 or j.expires>now) then out[#out+1]=j end end; return Ok(out) end)
H('jail:history','moderate',function() return Ok(STORE.jails) end)

-- Staff roles/chat -------------------------------------------------------------
H('staff:list','staff',function() local out={}; for id,e in pairs(STORE.staff) do local x={identifier=id}; for k,v in pairs(e) do x[k]=v end; out[#out+1]=x end; table.sort(out,function(a,b) return rankOfRole(a.role)>rankOfRole(b.role) end); return Ok(out) end)
H('staff:set','staff',function(src,d)
    local t=target(d.target); if not t then return Err('Player not found') end; local role=Clean(d.role or '',32):lower(); if role=='owner' and not Can(src,'owner') then return Err('Only owner can grant owner') end
    local def=roleDef(role); if role~='none' and not def then return Err('Unknown role') end
    local pid=primary(t); local existing=STORE.staff[pid]; local targetRank=Can(t,'owner') and rankOfRole('owner') or rankOfRole(existing and existing.role)
    if not Can(src,'owner') and targetRank>=staffRank(src) then return Err('Cannot modify equal/higher staff') end
    if role~='none' and staffRank(src)<=rankOfRole(role) and not Can(src,'owner') then return Err('Cannot grant equal/higher rank') end
    if role=='none' then STORE.staff[pid]=nil else STORE.staff[pid]={name=GetPlayerName(t),role=role,position=Clean(d.position or def.position or def.label,80),color=Clean(d.color or def.color or '#ffffff',16),assignedBy=actor(src),assignedAt=os.time(),expires=tonumber(d.expires) or 0} end
    save('staff'); Audit(src,role=='none' and 'remove staff' or 'set staff role',role,GetPlayerName(t)); webhook('staff','Staff role updated',{Player=GetPlayerName(t),Role=role,By=actor(src)}); TriggerClientEvent('rs-admin:client:permissionsRefresh',t); return Ok(STORE.staff[pid])
end)
local function sendStaffChat(src,msg)
    if not (Can(src,'open') or Can(src,'chat')) then return Err('Permission denied') end; msg=Clean(msg,Config.StaffChat.maxMessage or 500); if #msg<1 then return Err('Message required') end
    local role,def=staffRole(src); local row={at=os.time(),source=src,name=actor(src),role=role or 'staff',color=def and def.color or '#ffffff',message=msg}; pushBounded(staffChat,row,Config.StaffChat.maxHistory or 100)
    for _,s in ipairs(GetPlayers()) do local id=tonumber(s); if Can(id,'open') or Can(id,'chat') then TriggerClientEvent('rs-admin:client:staffChat',id,row) end end; return Ok(row)
end
H('staffchat:list','open',function() return Ok(staffChat) end)
H('staffchat:send','open',function(src,d) local r=sendStaffChat(src,d.message); if r.ok then Audit(src,'staff chat',d.message,'staff') end; return r end)
RegisterCommand(Config.StaffChat.command or 'achat',function(src,args) if src>0 then local r=sendStaffChat(src,table.concat(args,' ')); if not r.ok then TriggerClientEvent('rs-admin:client:message',src,{by='RS Admin',text=r.error}) end end end,false)

-- Jobs / gangs -----------------------------------------------------------------
H('jobs:list','players',function() return Ok(A.JobList()) end)
H('gangs:list','players',function() return Ok(A.GangList()) end)
H('player:setJob','players',function(src,d) local t=target(d.target); if not t then return Err('Player not found') end; local job=Clean(d.job,64); local req=Config.Pathways and Config.Pathways.Enabled and Config.Pathways.JobRequirements and Config.Pathways.JobRequirements[job]; if req and RSAdminPathways and not RSAdminPathways.HasCertification(t,req) and not (d.override==true and C.Can(src,'owner')) then return Err(('Requires %s Pathway certification'):format(req)) end; local good,e=A.SetJob(t,job,d.grade); if not good then return Err(e) end; Audit(src,'set job',('%s grade %s'):format(job,d.grade),GetPlayerName(t)); return Ok(true) end)
H('player:setGang','players',function(src,d) local t=target(d.target); if not t then return Err('Player not found') end; local good,e=A.SetGang(t,Clean(d.gang,64),d.grade); if not good then return Err(e) end; Audit(src,'set gang',('%s grade %s'):format(d.gang,d.grade),GetPlayerName(t)); return Ok(true) end)

-- Catalog / inventory -----------------------------------------------------------
-- RS-HVAC parts belong in their own gameplay store, not the general admin
-- asset browser.  This is a catalog-only filter: nothing is unregistered,
-- deleted or made invalid for inventory APIs or existing HVAC scripts.
local hvacItemPrefixes={
    'rs_hvac', 'hvac_', 'aircon_', 'ac_unit', 'contactor_', 'condenser_',
    'blower_', 'filter_drier', 'filter_pleated', 'brazing_rod',
    'refrigerant', 'evaporator_', 'thermostat_', 'compressor_',
    'heat_pump', 'air_handler', 'ductwork_', 'furnace_', 'fan_motor',
    'coil_clean', 'manifold_gauge', 'vacuum_pump', 'service_valve',
    'nitrogen_cylinder'
}
local hvacItemNames={
    tenkgoldchain=true, -- HVAC inventory's "10kg Gold Chain" material
    contactor_1p_30a=true, condenser_fan_motor_third=true,
    filter_drier_half=true, blower_wheel=true,
    brazing_rod_15=true, filter_pleated_merv8=true
}
local hvacLabels={
    'package unit', 'packaged rooftop', 'rooftop unit', 'condenser fan',
    'blower wheel', 'liquid.line filter.drier', 'brazing alloy',
    'pleated filter', 'merv 8', 'air conditioning unit',
    'hvac', 'heat pump', 'air handler', 'refrigerant', 'evaporator coil'
}
local function excludedHVACCatalogItem(item)
    local name=tostring(item.name or ''):lower()
    if hvacItemNames[name] then return true end
    for _,prefix in ipairs(hvacItemPrefixes) do
        if name:sub(1,#prefix)==prefix then return true end
    end
    local image=tostring(item.image or ''):lower()
    if image:find('rs%-hvac') or image:find('rs_hvac',1,true) then return true end
    local label=tostring(item.label or ''):lower()
    for _,pattern in ipairs(hvacLabels) do
        if label:find(pattern) then return true end
    end
    return false
end

H('catalog:items','inventory',function(_,d)
    local all=A.ItemList(d.refresh==true); local q=Clean(d.q or '',80):lower(); local page=math.max(1,math.floor(tonumber(d.page) or 1)); local size=math.max(12,math.min(60,math.floor(tonumber(d.pageSize) or 24))); local rows={}
    for _,item in ipairs(all) do if not excludedHVACCatalogItem(item) and (q=='' or item.name:lower():find(q,1,true) or item.label:lower():find(q,1,true)) then rows[#rows+1]=item end end
    local total=#rows; local first=(page-1)*size+1; local out={}; for i=first,math.min(total,first+size-1) do out[#out+1]=rows[i] end; return Ok({rows=out,total=total,page=page,pages=math.max(1,math.ceil(total/size)),pageSize=size})
end)
H('item:remove','inventory',function(src,d) local t=target(d.target); if not t then return Err('Player not found') end; local item=Clean(d.item,80); local amount=math.max(1,math.floor(tonumber(d.amount) or 1)); local reason=Clean(d.reason or '',180); local good,e=A.RemoveItem(t,item,amount,d.metadata,d.slot); if not good then return Err(e) end; Audit(src,'remove item',('%sx %s%s'):format(amount,item,reason~='' and (' · '..reason) or ''),GetPlayerName(t)); webhook('inventory','Inventory item removed',{Player=GetPlayerName(t),Item=item,Amount=amount,Reason=reason~='' and reason or '-',Staff=actor(src)}); return Ok(true) end)

-- Enhanced announcements -------------------------------------------------------
H('announcement:send','server',function(src,d)
    local msg=Clean(d.message or d.text,500); if #msg<1 then return Err('Message required') end; local audience=Clean(d.audience or 'all',24); local payload={title=Clean(d.title or 'Server Announcement',80),text=msg,category=Clean(d.category or 'server',24),duration=math.max(3,math.min(30,tonumber(d.duration) or 8)),color=Clean(d.color or '#20a9ff',16),by=actor(src)}
    if audience=='all' then TriggerClientEvent('rs-admin:client:announcement',-1,payload) elseif audience=='staff' then for _,s in ipairs(GetPlayers()) do local id=tonumber(s); if Can(id,'open') then TriggerClientEvent('rs-admin:client:announcement',id,payload) end end elseif audience=='player' then local t=target(d.target); if not t then return Err('Player not found') end; TriggerClientEvent('rs-admin:client:announcement',t,payload) else return Err('Unsupported audience') end
    Audit(src,'announcement',msg,audience); return Ok(true)
end)

-- Prank animation registry -----------------------------------------------------
local function animationByKey(key)
    for _,a in ipairs(Config.Pranks.Animations or {}) do if a.key==key then return a end end; for _,a in ipairs(Config.Pranks.CustomAnimations or {}) do if a.key==key then return a end end
end
H('prank:list','pranks',function() local out={}; for _,a in ipairs(Config.Pranks.Animations or {}) do out[#out+1]=a end; for _,a in ipairs(Config.Pranks.CustomAnimations or {}) do out[#out+1]=a end; return Ok(out) end)
H('prank:animation','pranks',function(src,d) local t=target(d.target); if not t then return Err('Player not found') end; if C.TargetProtected(src,t) then return Err('Owner-protected player') end; local a=animationByKey(Clean(d.key,60)); if not a then return Err('Animation preset missing') end; TriggerClientEvent('rs-admin:client:prankAnimation',t,a); Audit(src,'prank animation',a.label,GetPlayerName(t)); return Ok(true) end)
H('prank:customAnimation','pranks',function(src,d)
    local t=target(d.target); if not t then return Err('Player not found') end
    if C.TargetProtected(src,t) then return Err('Owner-protected player') end
    local dict=Clean(d.dict,120); local clip=Clean(d.clip,120)
    if dict=='' or clip=='' then return Err('Animation dictionary and clip are required') end
    local payload={label=Clean(d.label or 'Custom animation',80),dict=dict,clip=clip,duration=math.max(1000,math.min(60000,math.floor(tonumber(d.duration) or 8000))),flag=math.max(0,math.min(255,math.floor(tonumber(d.flag) or 49)))}
    TriggerClientEvent('rs-admin:client:prankAnimation',t,payload)
    Audit(src,'custom prank animation',('%s :: %s'):format(dict,clip),GetPlayerName(t)); return Ok(true)
end)
H('prank:effect','pranks',function(src,d)
    local t=target(d.target); if not t then return Err('Player not found') end; if C.TargetProtected(src,t) then return Err('Owner-protected player') end; local action=Clean(d.action,40); local allowed={fire=true,launch=true,vehicleBlast=true,droneStrike=true,ragdoll=true,drunk=true,spin=true,screenShake=true,vehicleSpin=true}; if not allowed[action] then return Err('Unknown prank effect') end
    local seconds=math.max(1,math.min(Config.PrankMaxSeconds or 30,math.floor(tonumber(d.seconds) or 8))); TriggerClientEvent('rs-admin:client:prankAdvanced',t,{action=action,seconds=seconds}); Audit(src,'prank '..action,seconds..'s',GetPlayerName(t)); return Ok(true)
end)
H('prank:stop','pranks',function(src,d) local t=target(d.target); if not t then return Err('Player not found') end; TriggerClientEvent('rs-admin:client:prankStop',t,{}); Audit(src,'stop prank','',GetPlayerName(t)); return Ok(true) end)

-- Mini world builder -----------------------------------------------------------
local function staffCoords(src) local ped=GetPlayerPed(src); if ped==0 then return end; local c=GetEntityCoords(ped); return c,GetEntityHeading(ped) end
local function coordFrom(src,d)
    if d.useCurrent then local c,h=staffCoords(src); if not c then return end; return c.x,c.y,c.z,h end
    return tonumber(d.x),tonumber(d.y),tonumber(d.z),tonumber(d.w) or tonumber(d.heading) or 0.0
end
local function findBuilder(id) for i,r in ipairs(STORE.builder) do if tonumber(r.id)==tonumber(id) then return r,i end end end
H('builder:list','builder',function() return Ok(STORE.builder) end)
H('builder:add','builder',function(src,d)
    if #STORE.builder>=(Config.Builder.maxPersistent or 500) then return Err('Builder limit reached') end; local kind=Clean(d.kind,16); if kind~='prop' and kind~='ped' and kind~='blip' and kind~='anim' then return Err('Unsupported builder type') end
    local x,y,z,w=coordFrom(src,d); if not x or not y or not z then return Err('Coordinates required') end
    if not Can(src,'owner') then local c=staffCoords(src); if c then local dx,dy,dz=c.x-x,c.y-y,c.z-z; local max=Config.Builder.maxDistanceFromStaff or 500.0; if dx*dx+dy*dy+dz*dz>max*max then return Err('Placement exceeds configured distance') end end end
    builderSeq=builderSeq+1; local row={id=builderSeq,kind=kind,model=Clean(d.model,80),label=Clean(d.label or d.model or kind,80),x=x,y=y,z=z,w=w,alpha=math.max(0,math.min(255,math.floor(tonumber(d.alpha) or 255))),scale=math.max(0.1,math.min(5.0,tonumber(d.scale) or 1.0)),color=math.max(0,math.min(85,math.floor(tonumber(d.color) or 0))),sprite=math.max(0,math.floor(tonumber(d.sprite) or 1)),tint=math.max(0,math.floor(tonumber(d.tint) or 0)),animDict=Clean(d.animDict or '',100),animClip=Clean(d.animClip or '',100),animFlag=math.floor(tonumber(d.animFlag) or 49),frozen=d.frozen~=false,collision=d.collision~=false,createdBy=actor(src),created=os.time()}
    STORE.builder[#STORE.builder+1]=row; save('builder'); TriggerClientEvent('rs-admin:client:builderAdd',-1,row); Audit(src,'builder add',('%s %s'):format(kind,row.model),row.label); webhook('builder','World builder placement',{Type=kind,Model=row.model,By=actor(src)}); return Ok(row)
end)
H('builder:delete','builder',function(src,d) local row,i=findBuilder(d.id); if not row then return Err('Builder entry missing') end; table.remove(STORE.builder,i); save('builder'); TriggerClientEvent('rs-admin:client:builderDelete',-1,{id=row.id}); Audit(src,'builder delete',row.kind,row.label); return Ok(true) end)
H('builder:goto','builder',function(src,d) local row=findBuilder(d.id); if not row then return Err('Builder entry missing') end; TriggerClientEvent('rs-admin:client:teleport',src,{x=row.x,y=row.y,z=row.z}); return Ok(true) end)

-- Vehicle cleanup --------------------------------------------------------------
local function vehicleOwned(v)
    if GetResourceState('qbx_vehicles')~='started' then return nil end
    local plate=GetVehicleNumberPlateText(v); if not plate or plate:match('^%s*$') then return nil end
    local good,exists=pcall(function() return exports.qbx_vehicles:DoesPlayerVehiclePlateExist(plate) end)
    if not good or type(exists)~='boolean' then return nil end
    return exists
end
local function occupiedVehicles()
    local good,peds=pcall(GetAllPeds);if not good or type(peds)~='table' then return end
    local occupied={};for _,ped in ipairs(peds) do if DoesEntityExist(ped) then local v=GetVehiclePedIsIn(ped,false);if v and v~=0 then occupied[v]=true end end end
    return occupied
end
local function cleanupContext(src,d)
    local mode=Clean(d.mode or 'empty',20)
    if mode~='empty' and mode~='radius' and mode~='global' then return nil,'Invalid cleanup mode' end
    local radius=math.max(5,math.min(Config.VehicleCleanup.maxRadius or 500,tonumber(d.radius) or 100))
    local ped=src~=0 and GetPlayerPed(src) or 0
    if mode~='global' and ped==0 then return nil,'Staff character unavailable' end
    return {mode=mode,radius=radius,coords=ped~=0 and GetEntityCoords(ped) or nil,bucket=src~=0 and GetPlayerRoutingBucket(src) or nil}
end
local function cleanupEligible(v,ctx,occupied)
    if not DoesEntityExist(v) or occupied[v] or GetPedInVehicleSeat(v,-1)~=0 then return false end
    if ctx.mode~='global' then
        if GetEntityRoutingBucket(v)~=ctx.bucket then return false end
        local vc=GetEntityCoords(v);local c=ctx.coords;local dx,dy,dz=c.x-vc.x,c.y-vc.y,c.z-vc.z
        if dx*dx+dy*dy+dz*dz>ctx.radius*ctx.radius then return false end
    end
    return true
end
local function vehicleStamp(v) return {model=GetEntityModel(v),plate=GetVehicleNumberPlateText(v),net=NetworkGetNetworkIdFromEntity(v),bucket=GetEntityRoutingBucket(v)} end
local function sameVehicle(v,stamp) return DoesEntityExist(v) and GetEntityModel(v)==stamp.model and GetVehicleNumberPlateText(v)==stamp.plate and NetworkGetNetworkIdFromEntity(v)==stamp.net and GetEntityRoutingBucket(v)==stamp.bucket end
local function cleanupMatches(src,d)
    local ctx,e=cleanupContext(src,d);if not ctx then return nil,e end
    local occupied=occupiedVehicles();if not occupied then return nil,'Occupancy check unavailable' end
    local out={};local unverified=0
    for _,v in ipairs(GetAllVehicles()) do if cleanupEligible(v,ctx,occupied) then
        local stamp=vehicleStamp(v);local owned=vehicleOwned(v)
        if owned==nil then unverified=unverified+1
        elseif owned==false and sameVehicle(v,stamp) then out[#out+1]={entity=v,stamp=stamp} end
    end end
    return out,ctx,unverified
end
H('vehicle:cleanupPreview','vehicles',function(src,d) if d.mode=='global' and Config.VehicleCleanup.ownerOnlyGlobal and not Can(src,'owner') then return Err('Owner required for global cleanup') end; local rows,ctx,unverified=cleanupMatches(src,d);if not rows then return Err(ctx) end;return Ok({count=#rows,radius=ctx.radius,unverified=unverified}) end)
local function executeVehicleCleanup(src,d)
    if d.mode=='global' and Config.VehicleCleanup.ownerOnlyGlobal and src~=0 and not Can(src,'owner') then return nil,'Owner required for global cleanup' end
    local rows,ctx=cleanupMatches(src,d);if not rows then return nil,ctx end;local count=0
    for _,candidate in ipairs(rows) do
        local v=candidate.entity
        if sameVehicle(v,candidate.stamp) and vehicleOwned(v)==false then
            -- Ownership exports may yield. Recheck every seat, identity,
            -- bucket and distance after the lookup, immediately before delete.
            local occupied=occupiedVehicles()
            if occupied and sameVehicle(v,candidate.stamp) and cleanupEligible(v,ctx,occupied) then DeleteEntity(v);count=count+1 end
        end
    end
    if src~=0 then Audit(src,'vehicle cleanup',('%s deleted'):format(count),d.mode or 'empty') end
    return {count=count}
end
RSAdminServer.ExecuteVehicleCleanup=executeVehicleCleanup
H('vehicle:cleanupExecute','vehicles',function(src,d) local result,e=executeVehicleCleanup(src,d); return result and Ok(result) or Err(e) end)

-- Filtered logs -----------------------------------------------------------------
H('logs:list','logs',function(src,d)
    local category=Clean(d.category or 'all',24):lower(); local q=Clean(d.q or '',120):lower()
    local staff=Clean(d.staff or '',100):lower(); local targetName=Clean(d.target or '',100):lower(); local status=Clean(d.status or '',40):lower()
    local page=math.max(1,math.floor(tonumber(d.page) or 1)); local size=math.max(10,math.min(Config.Logs.maxPageSize or 100,math.floor(tonumber(d.pageSize) or Config.Logs.pageSize or 50)))
    local function cat(row)
        local a=tostring(row.action or ''):lower()
        if a:find('ban') or a:find('jail') or a:find('kick') or a:find('warning') or a:find('watchlist') or a:find('community') then return 'moderation' end
        if a:find('economy') or a:find('money') or a:find('transfer') then return 'economy' end
        if a:find('item') or a:find('inventory') then return 'items' end
        if a:find('vehicle') or a:find('car') then return 'vehicles' end
        if a:find('disaster') or a:find('tsunami') then return 'disasters' end
        if a:find('world') or a:find('weather') or a:find('blackout') then return 'world' end
        if a:find('staff') or a:find('role') then return 'staff' end
        if a:find('builder') then return 'builder' end
        if a:find('resource') then return 'server' end
        if a:find('denied') or a:find('security') then return 'security' end
        return 'players'
    end
    local rows={}
    for i=#STORE.activity,1,-1 do
        local r=STORE.activity[i]; local rc=cat(r); local hay=(json.encode(r) or ''):lower()
        local good=(category=='all' or category==rc) and (q=='' or hay:find(q,1,true)) and (staff=='' or tostring(r.staff or ''):lower():find(staff,1,true)) and (targetName=='' or tostring(r.target or ''):lower():find(targetName,1,true))
        if good and (status=='' or hay:find(status,1,true)) then local x={}; for k,v in pairs(r) do x[k]=v end; x.category=rc; rows[#rows+1]=x end
    end
    local total=#rows; local first=(page-1)*size+1; local out={}; for i=first,math.min(total,first+size-1) do out[#out+1]=rows[i] end
    return Ok({rows=out,total=total,page=page,pages=math.max(1,math.ceil(total/size)),pageSize=size})
end)

-- Widgets ----------------------------------------------------------------------
H('widgets:get','open',function(src) local pid=primary(src); return Ok(STORE.widgets[pid] or Config.Widgets.default or {}) end)
H('widgets:save','open',function(src,d) local pid=primary(src); if not pid then return Err('Identifier missing') end; local layout={}; local allowed={}; for _,k in ipairs(Config.Widgets.available or {}) do allowed[k]=true end; for _,w in ipairs(d.widgets or {}) do if allowed[w.key or w] then layout[#layout+1]=type(w)=='table' and w or {key=w} end end; STORE.widgets[pid]=layout; save('widgets'); return Ok(layout) end)

-- Ban engine -------------------------------------------------------------------
RSAdminServer.AdvancedBanReady=true
local function activeBan(b) return not b.revoked and (not b.expires or b.expires==0 or b.expires>os.time()) end
local function nextBanId() local n=0; for _,b in ipairs(C.Data.bans) do n=math.max(n,tonumber(b.id) or 0) end; return n+1 end
local function banMatches(b,src)
    local pids=ids(src); local toks=tokens(src); for _,x in ipairs(b.identifiers or {}) do for _,id in ipairs(pids) do if x==id then return true end end end; for _,x in ipairs(b.tokens or {}) do for _,t in ipairs(toks) do if x==t then return true end end end; return false
end
local function createBan(src,t,d)
    local mins=math.max(0,math.floor(tonumber(d.minutes) or 0)); local scope=Clean(d.scope or 'all',20):lower(); local reason=Clean(d.reason or 'Administrative ban',220); local all=ids(t); local selected={}
    if scope=='all' then selected=all else local prefix=scope..':' for _,id in ipairs(all) do if id:sub(1,#prefix)==prefix then selected[#selected+1]=id end end end
    local bt=(scope=='all' or scope=='token') and tokens(t) or {}; if scope~='token' and #selected==0 then return nil,'Identifier for scope not available' end; if scope=='token' and #bt==0 then return nil,'Player token unavailable' end
    local b={id=nextBanId(),name=GetPlayerName(t),identifiers=selected,tokens=bt,scope=scope,reason=reason,by=actor(src),created=os.time(),expires=mins>0 and os.time()+mins*60 or 0,history={{at=os.time(),action='created',by=actor(src)}}}; C.Data.bans[#C.Data.bans+1]=b; C.SaveJson('bans',C.Data.bans); return b
end
H('player:ban','moderate',function(src,d) local t=target(d.target); if not t then return Err('Player not found') end; if C.TargetProtected(src,t) then return Err('Owner-protected player') end; local b,e=createBan(src,t,d); if not b then return Err(e) end; Audit(src,'ban',b.reason,b.name); webhook('moderation','Player banned',{Player=b.name,Scope=b.scope,Reason=b.reason,Staff=actor(src)}); DropPlayer(t,('Banned: %s'):format(b.reason)); return Ok(b) end)
H('ban:offline','moderate',function(src,d) local identifier=Clean(d.identifier,180); if not identifier:match('^[%w_%-]+:.+$') then return Err('Prefixed identifier required') end; local mins=math.max(0,math.floor(tonumber(d.minutes) or 0)); local b={id=nextBanId(),name=Clean(d.name or 'Offline player',100),identifiers={identifier},tokens={},scope=identifier:match('^([^:]+):') or 'identifier',reason=Clean(d.reason or 'Administrative ban',220),by=actor(src),created=os.time(),expires=mins>0 and os.time()+mins*60 or 0,history={{at=os.time(),action='offline-created',by=actor(src)}}}; C.Data.bans[#C.Data.bans+1]=b; C.SaveJson('bans',C.Data.bans); Audit(src,'offline ban',b.reason,b.name); return Ok(b) end)
H('ban:remove','moderate',function(src,d) for _,b in ipairs(C.Data.bans) do if tonumber(b.id)==tonumber(d.id) then b.revoked=true;b.revokedAt=os.time();b.revokedBy=actor(src);b.history=b.history or {};b.history[#b.history+1]={at=os.time(),action='revoked',by=actor(src)};C.SaveJson('bans',C.Data.bans);Audit(src,'unban','#'..b.id,b.name);return Ok(true) end end; return Err('Ban not found') end)
H('ban:history','moderate',function() return Ok(C.Data.bans) end)
AddEventHandler('playerConnecting',function(_,setKickReason) local src=source; for _,b in ipairs(C.Data.bans) do if activeBan(b) and banMatches(b,src) then setKickReason(('Banned: %s'):format(b.reason or 'No reason')); CancelEvent(); return end end end)

-- Sync persistent builder entries to joining clients.
AddEventHandler('playerJoining',function() local src=source; SetTimeout(2200,function() if GetPlayerName(src) then TriggerClientEvent('rs-admin:client:builderSync',src,STORE.builder) end end) end)

-- World / disaster state -------------------------------------------------------
local globalDisaster,disasterSnapshot,stopGlobalDisaster
local disasterRevision=0
local WORLD={}; for k,v in pairs(Config.World.defaults or {}) do WORLD[k]=v end
WORLD.overrides={}
-- Explicit owner-pinned weather. Never store transient storms as permanent weather.
local WEATHER_FILE='data/disaster_weather.json'
local pinnedWeather=false
local function copyWorld()
    local state={overrides={}}
    for key,value in pairs(WORLD) do if key~='overrides' then state[key]=value end end
    for key,value in pairs(WORLD.overrides) do state.overrides[key]=value end
    return state
end
local function persistWeather(state)
    local stored={}
    for _,key in ipairs({'weather','wind','windDirection','rain','blackout'}) do
        if state.overrides[key] then stored[key]=state[key] end
    end
    local encoded=json.encode(stored)
    local good,saved=pcall(SaveResourceFile,GetCurrentResourceName(),WEATHER_FILE,encoded,#encoded)
    if not good or not saved then return false end
    local readable,value=pcall(LoadResourceFile,GetCurrentResourceName(),WEATHER_FILE)
    return readable and value==encoded
end
local storedWeather=LoadResourceFile(GetCurrentResourceName(),WEATHER_FILE)
if storedWeather and storedWeather~='' then
    local ok,data=pcall(json.decode,storedWeather)
    if ok and type(data)=='table' then
        local valid={}
        for _,w in ipairs(Config.WeatherTypes or {}) do valid[w]=true end
        if type(data.weather)=='string' and valid[data.weather] then WORLD.weather=data.weather;WORLD.overrides.weather=true;pinnedWeather=true end
        if type(data.wind)=='number' and data.wind>=0 and data.wind<=12 then WORLD.wind=data.wind;WORLD.overrides.wind=true end
        if type(data.windDirection)=='number' and data.windDirection>=0 and data.windDirection<=360 then WORLD.windDirection=data.windDirection;WORLD.overrides.windDirection=true end
        if type(data.rain)=='number' and data.rain>=-1 and data.rain<=1 then WORLD.rain=data.rain;WORLD.overrides.rain=true end
        if type(data.blackout)=='boolean' then WORLD.blackout=data.blackout;WORLD.overrides.blackout=true end
    end
end
local worldEpoch=os.time()
local function fallbackWorld()
    -- Leave established weather controllers in charge. Custom controllers can
    -- opt out with set rs_admin_world_sync off, or Config.World.syncProviders.
    if GetConvar('rs_admin_world_sync','auto')=='off' then return {enabled=false,provider='external'} end
    local providers=Config.World.syncProviders or {'qb-weathersync','qbx_weathersync','vSync','vsync','weathersync','cd_easytime','Renewed-Weathersync','rs-zombiecore','rs-zcoreopplifeline'}
    for _,provider in ipairs(providers) do if GetResourceState(provider)=='started' then return {enabled=false,provider=provider} end end
    local defaults=Config.World.defaults or {}
    local secondsPerMinute=math.max(1,tonumber(Config.World.secondsPerGameMinute) or 2)
    local minutes=((defaults.hour or 12)*60+(defaults.minute or 0)+(os.time()-worldEpoch)/secondsPerMinute)%1440
    return {enabled=true,provider='rs-adminmenu',weather=defaults.weather or 'CLEAR',rain=-1,wind=defaults.wind or 0,windDirection=defaults.windDirection or 0,hour=math.floor(minutes/60),minute=math.floor(minutes%60),second=math.floor((minutes%1)*60)}
end
local function worldSnapshot()
    local state=copyWorld();state.fallback=fallbackWorld();state.pinnedWeather=pinnedWeather;state.disaster=disasterSnapshot and disasterSnapshot() or {active=false};return state
end
local function worldBroadcast(target) TriggerClientEvent('rs-admin:client:worldState',target or -1,worldSnapshot()) end
H('world:state','world',function() return Ok(worldSnapshot()) end)
CreateThread(function()
    local previous
    while true do
        local fallback=fallbackWorld();local current=fallback.enabled and 'rs-adminmenu' or fallback.provider
        if fallback.enabled or current~=previous then TriggerClientEvent('rs-admin:client:worldFallback',-1,fallback) end
        previous=current;Wait(1000)
    end
end)
local function finiteWorldNumber(value, default)
    local n=tonumber(value)
    if not n or n~=n or n==math.huge or n==-math.huge then return default end
    return n
end
local function patchWorld(src,d)
    if type(d)~='table' then return nil,'Invalid world request' end
    if pinnedWeather and not Can(src,'owner') and (d.weather~=nil or d.rain~=nil or d.wind~=nil or d.windDirection~=nil or d.blackout~=nil) then return nil,'Owner-pinned weather is active; ask the owner to release it' end
    local weather
    if d.weather~=nil then
        weather=Clean(d.weather,24):upper(); local valid=false
        for _,name in ipairs(Config.WeatherTypes or {}) do if name==weather then valid=true break end end
        if not valid then return nil,'Invalid weather' end
    end
    local allowed={weather=true,hour=true,minute=true,blackout=true,rain=true,wind=true,windDirection=true,traffic=true,parked=true,randomVehicles=true,peds=true,scenarios=true}
    local state=copyWorld()
    local atmosphereChanged=false
    for k,v in pairs(d or {}) do if allowed[k] then
        state.overrides[k]=true
        if k=='weather' or k=='rain' or k=='wind' or k=='windDirection' or k=='blackout' then atmosphereChanged=true end
        if k=='weather' then state.weather=weather
        elseif k=='blackout' then state.blackout=v==true
        elseif k=='hour' then state.hour=math.max(0,math.min(23,math.floor(finiteWorldNumber(v,state.hour or 12))))
        elseif k=='minute' then state.minute=math.max(0,math.min(59,math.floor(finiteWorldNumber(v,state.minute or 0))))
        elseif k=='windDirection' then state.windDirection=finiteWorldNumber(v,0)%360
        else local hi=k=='wind' and 12.0 or 1.0; local lo=k=='rain' and -1.0 or 0.0; state[k]=math.max(lo,math.min(hi,finiteWorldNumber(v,state[k] or 0.0))) end
    end end
    -- A weather preset releases the previous manual rain override. Explicit
    -- rain in the same patch still wins, including a deliberate dry storm.
    if weather and d.rain==nil then state.rain=-1.0;state.overrides.rain=true end
    -- Changes to an owner pin must survive the same restarts as the pin itself.
    if pinnedWeather and atmosphereChanged and not persistWeather(state) then return nil,'Could not save pinned weather; world state was not changed' end
    WORLD=state
    worldBroadcast(-1); Audit(src,'world patch',json.encode(d),'all'); webhook('world','World state changed',{Staff=actor(src),State=json.encode(d)}); return worldSnapshot()
end
RSAdminServer.PatchWorld=patchWorld
H('world:patch','world',function(src,d)
    local result,e=patchWorld(src,d); return result and Ok(result) or Err(e)
end)
local function releaseWorld(src)
    if pinnedWeather and not Can(src,'owner') then return Err('Owner required to release pinned weather') end
    if not persistWeather({overrides={}}) then return Err('Could not clear saved weather; world state was not changed') end
    WORLD={overrides={}};for key,value in pairs(Config.World.defaults or {}) do WORLD[key]=value end
    pinnedWeather=false
    worldBroadcast(-1);Audit(src,'release world overrides','','world');return Ok(worldSnapshot())
end
H('world:release','world',releaseWorld)
H('world:holdWeather','owner',function(src,d)
    if type(d)~='table' then return Err('Invalid weather request') end
    local weather=Clean(d.weather or '',24):upper()
    local allowed=false
    for _,name in ipairs(Config.WeatherTypes or {}) do if weather==name then allowed=true break end end
    if not allowed then return Err('Invalid weather name') end
    local wind=tonumber(d.wind)
    if not wind or wind~=wind or wind<0 or wind>12 then return Err('Wind must be 0-12 m/s') end
    local rain=tonumber(d.rain)
    if not rain or rain~=rain or rain < -1 or rain>1 then return Err('Rain must be -1 to 1') end
    local direction=tonumber(d.windDirection)
    if not direction or direction~=direction or direction < 0 or direction>360 then return Err('Direction must be 0-360') end
    local state=copyWorld()
    for _,key in ipairs({'weather','wind','rain','windDirection'}) do state.overrides[key]=true end
    state.weather=weather;state.wind=wind;state.rain=rain;state.windDirection=direction
    if not persistWeather(state) then return Err('Could not persist weather to resource storage') end
    WORLD=state
    pinnedWeather=true
    worldBroadcast(-1)
    Audit(src,'hold permanent weather',weather,'world')
    return Ok(worldSnapshot())
end)
local function disasterNumber(value, default, low, high)
    local n=tonumber(value)
    if not n or n~=n or n==math.huge or n==-math.huge then n=default end
    return math.max(low,math.min(high,n))
end
local DISASTER_NAMES={blackout=true,thunderstorm=true,hurricane=true,blizzard=true,sandstorm=true,toxicfog=true,earthquake=true,meteor=true,tornado=true,firestorm=true,emp=true,tsunami=true}
local activeDisasters={}
local syncCooldown={}
local meteorEvent=nil
disasterSnapshot=function()
    if not globalDisaster then return {active=false} end
    local p=globalDisaster.payload
    return {active=true,id=p.eventId,name=p.name,by=p.by,started=p.started,expires=globalDisaster.expires,remaining=math.max(0,globalDisaster.expires-os.time()),intensity=p.intensity,scope='all'}
end
local function broadcastDisasterStatus() TriggerClientEvent('rs-admin:client:disasterStatus',-1,disasterSnapshot()) end
stopGlobalDisaster=function(reason,expectedId)
    if expectedId and (not globalDisaster or globalDisaster.payload.eventId~=expectedId) then return false end
    disasterRevision=disasterRevision+1
    activeDisasters={};globalDisaster=nil;meteorEvent=nil
    TriggerClientEvent('rs-admin:client:disasterStop',-1,{reason=reason or 'Stopped by staff'})
    worldBroadcast(-1);broadcastDisasterStatus()
    return true
end
RSAdminServer.StopDisaster=stopGlobalDisaster
H('disaster:state','world',function() return Ok(disasterSnapshot()) end)
H('world:reset','owner',function(src)
    local result=releaseWorld(src);if not result.ok then return result end
    if RSAdminOperations and RSAdminOperations.CancelMaintenance then RSAdminOperations.CancelMaintenance(src) end
    stopGlobalDisaster('Normal world control restored')
    Audit(src,'reset world and disaster','','world')
    return Ok(worldSnapshot())
end)
local function replayGlobalDisaster(src)
    if not globalDisaster then return end
    local remaining=globalDisaster.expires-os.time()
    if remaining<=0 then return end
    local payload={}
    for k,v in pairs(globalDisaster.payload) do payload[k]=v end
    payload.seconds=remaining
    payload.elapsed=globalDisaster.payload.seconds-remaining
    activeDisasters[src]={identity=jailIdentity(src),expires=globalDisaster.expires}
    TriggerClientEvent('rs-admin:client:disaster',src,payload)
end
local function startDisaster(src,d)
    if not Can(src,'world') then return Err('Permission denied') end
    if src~=0 and RSAdminOperations and RSAdminOperations.MaintenanceActive and RSAdminOperations.MaintenanceActive() then return Err('Cancel tsunami maintenance before starting another disaster') end
    local requestSession=src==0 and 'console' or C.SessionIdentity(src)
    if not requestSession then return Err('Staff character is not loaded') end
    local name=Clean(d.name,32):lower()
    if not DISASTER_NAMES[name] then return Err('Unknown disaster') end
    local scope=Clean(d.scope or 'all',16):lower()
    if scope~='all' then return Err('Disasters only support Entire Server scope') end
    if scope=='all' and Config.Disasters.requireOwnerForGlobalDangerous and Config.Disasters.dangerous[name] and not (Can(src,'owner') or Can(src,'developer')) then
        return Err('Owner/developer required for global dangerous event')
    end
    local physicsRequested=(d.affectEntities==true or d.affectPeds==true or d.affectPlayers==true)
    if physicsRequested and name~='tornado' and name~='hurricane' then return Err('Physical gusts only support tornado or hurricane') end
    if physicsRequested and not Can(src,'owner') then return Err('Owner required for physical gusts') end
    if d.affectPlayers==true and not (Config.Disasters.allowDamage==true or Can(src,'owner')) then return Err('Owner required for player ragdolls') end
    local cfg=Config.Disasters.physics or {}
    local payload={
        name=name,scope=scope,
        seconds=math.floor(disasterNumber(d.seconds,30,5,Config.Disasters.maxSeconds or 120)),
        intensity=disasterNumber(d.intensity,.65,.1,1.0),
        damage=(d.damage==true and Config.Disasters.allowDamage==true),
        by=actor(src),
        previewOperator=Can(src,'owner') and src or nil,
        gustDirection=disasterNumber(d.gustDirection,0,0,360)%360,
        gustSeed=math.random(10000,999999), -- replicated once; late join gets same gust timeline
        lift=disasterNumber(d.lift,.65,0,1),
        radius=disasterNumber(d.radius,55,15,math.min(80,cfg.maxRadius or 80)),
        travelSpeed=name=='tornado' and disasterNumber(d.travelSpeed,3.5,0,8) or 0, -- metres/second, server bounded
        affectPeds=d.affectPeds==true and physicsRequested,
        affectPlayers=d.affectPlayers==true and physicsRequested,
        cinematicCars=(d.cinematicCars==true and scope=='all' and Can(src,'owner') and (name=='tornado' or name=='hurricane')),
        cinematicCows=(d.cinematicCows==true and scope=='all' and Can(src,'owner') and (name=='tornado' or name=='hurricane')),
        cinematicImpacts=(d.cinematicImpacts==true and d.cinematicCars==true and scope=='all' and Can(src,'owner') and (name=='tornado' or name=='hurricane')),
        destructiveTraffic=(d.destructiveTraffic==true and d.affectEntities==true and d.cinematicImpacts==true and d.cinematicCars==true and scope=='all' and Can(src,'owner')), 
        surge=(d.surge==true and scope=='all' and name=='hurricane' and Can(src,'owner')),
        affectEntities=d.affectEntities==true and physicsRequested,
        style=(({serious=true,funny=true,extreme=true})[d.style]) and d.style or "serious"
    }
    disasterRevision=disasterRevision+1;local requestRevision=disasterRevision
    if name=='tornado' or name=='hurricane' or name=='meteor' then
        local ped=GetPlayerPed(src)
        if not ped or ped==0 then return Err('Staff character unavailable') end
        local c=GetEntityCoords(ped)
        local heading=math.rad(GetEntityHeading(ped))
        local distance=name=='hurricane' and 125.0 or 15.0
        payload.origin={x=c.x-math.sin(heading)*distance,y=c.y+math.cos(heading)*distance,z=c.z}
        payload.affectedVehicles={}
        if name=='meteor' then payload.origin={x=c.x,y=c.y,z=c.z};payload.meteorSeed=math.random(10000,999999) end
        if payload.affectEntities then
            -- This deliberately fails closed if a supported owned-vehicle registry
            -- cannot verify that each candidate is not owned by a player.
            local candidates,e,unverified=cleanupMatches(src,{mode='radius',radius=80})
            if not candidates then return Err(e or 'Vehicle verification failed') end
            payload.vehicleCandidates=#candidates;payload.unverifiedVehicles=unverified or 0
            for _,row in ipairs(candidates) do
                if #payload.affectedVehicles >= math.min(24,cfg.maxVehicles or 24) then break end
                local st=row.stamp
                if st.net and st.net>0 then
                    payload.affectedVehicles[#payload.affectedVehicles+1]={netId=st.net,plate=st.plate,model=st.model,bucket=st.bucket}
                end
            end
        end
    end
    -- Only the initiator can submit meteor contacts. Visuals are broadcast once;
    -- eligible real cars are independently verified by the existing owner registry.
    if name=='meteor' then
        payload.meteorController=src
        payload.meteorSession=math.random(100000,999999999)
        local candidates=cleanupMatches(src,{mode='radius',radius=math.min(110,tonumber((Config.Disasters.meteor or {}).radius) or 88)})
        local known={}
        if type(candidates)=='table' then
            for _,entry in ipairs(candidates) do
                if #known>=24 then break end
                local stamp=entry.stamp
                if stamp and stamp.net and stamp.net>0 then
                    known[#known+1]={netId=stamp.net,plate=stamp.plate,model=stamp.model,bucket=stamp.bucket}
                end
            end
        end
        payload.meteorCandidates=known
    end
    if requestRevision~=disasterRevision or (src~=0 and C.SessionIdentity(src)~=requestSession) or not Can(src,'world') then return Err('Disaster request expired or staff session changed') end
    if physicsRequested and not Can(src,'owner') then return Err('Owner permission changed during vehicle verification') end
    if Config.Disasters.requireOwnerForGlobalDangerous and Config.Disasters.dangerous[name] and not (Can(src,'owner') or Can(src,'developer')) then return Err('Disaster permission changed') end
    payload.eventId=requestRevision;payload.started=os.time();payload.expires=os.time()+payload.seconds
    if name=='meteor' then
        meteorEvent={source=src,identity=C.SessionIdentity(src),session=payload.meteorSession,
            expires=os.time()+payload.seconds,scope=scope,origin=payload.origin,
            vehicles=payload.meteorCandidates,lastTick=0,count=0,used={}}
        payload.meteorCandidates=nil
    else
        meteorEvent=nil
    end
    for _,player in ipairs(GetPlayers()) do
        local id=tonumber(player)
        activeDisasters[id]={identity=jailIdentity(id),expires=os.time()+payload.seconds}
    end
    globalDisaster={payload=payload,expires=os.time()+payload.seconds}
    TriggerClientEvent('rs-admin:client:disaster',-1,payload)
    broadcastDisasterStatus()
    if name=='tornado' or name=='hurricane' then print(('[rs-adminmenu][storm] %s scope=%s realVehicles=%d unverified=%d npc=%s stuntCars=%s'):format(name,scope,#(payload.affectedVehicles or {}),payload.unverifiedVehicles or 0,tostring(payload.affectPeds),tostring(payload.cinematicCars))) end
    Audit(src,'disaster '..name,('%s %ss'):format(scope,payload.seconds),'world')
    webhook('disasters','Disaster simulation started',{Type=name,Scope=scope,Seconds=payload.seconds,Intensity=payload.intensity,Staff=actor(src)},16744192)
    return Ok(payload)
end
RSAdminServer.StartDisaster=startDisaster
H('disaster:start','world',startDisaster)
-- A client cannot choose a target vehicle or broadcast a damaging blast.
-- Only the owner/developer who started the active meteor event can submit a
-- bounded ground/structure contact; local actors receive visual-only blasts.
RegisterNetEvent('rs-admin:server:meteorImpact',function(hit)
    local src=source
    local e=meteorEvent
    if not e or src~=e.source or not GetPlayerName(src) or
       C.SessionIdentity(src)~=e.identity or
       not (Can(src,'owner') or Can(src,'developer')) or
       os.time()>=e.expires or e.count>=48 or type(hit)~='table' or
       tonumber(hit.session)~=e.session then return end
    local index=tonumber(hit.index)
    local x,y,z=tonumber(hit.x),tonumber(hit.y),tonumber(hit.z)
    if not index or index~=math.floor(index) or index<1 or index>48 or e.used[index] then return end
    if not x or not y or not z or x~=x or y~=y or z~=z or
       math.abs(x)>10000 or math.abs(y)>10000 or math.abs(z)>1200 then return end
    local dx,dy=x-e.origin.x,y-e.origin.y
    local radius=math.min(115,math.max(20,tonumber((Config.Disasters.meteor or {}).radius) or 88))
    if dx*dx+dy*dy>(radius+7)^2 or math.abs(z-e.origin.z)>115 then return end
    local now=GetGameTimer()
    if now-e.lastTick<900 then return end
    e.lastTick=now;e.count=e.count+1;e.used[index]=true
    local verified={}
    for _,row in ipairs(e.vehicles) do
        local v=NetworkGetEntityFromNetworkId(row.netId)
        if v and v~=0 and DoesEntityExist(v) and
           sameVehicle(v,{net=row.netId,plate=row.plate,model=row.model,bucket=row.bucket}) and
           vehicleOwned(v)==false then
            local occupied=occupiedVehicles()
            if meteorEvent~=e or os.time()>=e.expires or C.SessionIdentity(src)~=e.identity then return end
            if occupied and not occupied[v] and sameVehicle(v,{net=row.netId,plate=row.plate,model=row.model,bucket=row.bucket}) and GetPedInVehicleSeat(v,-1)==0 then
            local c=GetEntityCoords(v)
            if (c.x-x)^2+(c.y-y)^2<13^2 and math.abs(c.z-z)<7 then
                verified[#verified+1]=row
                if #verified>=5 then break end
            end
            end
        end
    end
    local meteorCfg=(Config.Disasters or {}).meteor or {}
    if meteorEvent~=e or os.time()>=e.expires or C.SessionIdentity(src)~=e.identity then return end
    if e.scope=='all' and meteorCfg.damagePlayers==true and Config.Disasters.allowDamage==true then
        local impactBucket=GetPlayerRoutingBucket(e.source)
        for _,player in ipairs(GetPlayers()) do
            local id=tonumber(player)
            if id and id~=e.source and not Can(id,'owner') and
               GetPlayerRoutingBucket(id)==impactBucket then
                local ped=GetPlayerPed(id)
                if ped and ped~=0 and DoesEntityExist(ped) then
                    local c=GetEntityCoords(ped)
                    local diff=(c.x-x)^2+(c.y-y)^2
                    if diff<10^2 and math.abs(c.z-z)<7 then
                        local damage=math.floor(105*(1-math.sqrt(diff)/10))
                        if damage>0 then SetEntityHealth(ped,math.max(0,GetEntityHealth(ped)-damage)) end
                    end
                end
            end
        end
    end
    TriggerClientEvent('rs-admin:client:meteorImpact',e.scope=='all' and -1 or src,
        {x=x,y=y,z=z,index=index,session=e.session,verifiedVehicles=verified,
         owner=e.source})
end)
H('disaster:stop','world',function(src,d)
    local scope=Clean(d.scope or 'all',16):lower()
    if scope~='all' then return Err('Disasters only support Entire Server scope') end
    if not Can(src,'owner') then return Err('Owner required to stop a global disaster') end
    if not stopGlobalDisaster('Stopped by '..actor(src),d.eventId) then return Err('The active event changed; refresh before stopping it') end
    Audit(src,'disaster stop',scope,'world')
    return Ok(true)
end)
CreateThread(function()
    while true do Wait(1000);local now=os.time()
        if globalDisaster and now>=globalDisaster.expires then stopGlobalDisaster('Event timer completed',globalDisaster.payload.eventId) end
        for id,storm in pairs(activeDisasters) do
            if not GetPlayerName(id) or jailIdentity(id)~=storm.identity then activeDisasters[id]=nil
            elseif now>=storm.expires then activeDisasters[id]=nil;TriggerClientEvent('rs-admin:client:disasterStop',id,{});worldBroadcast(id) end
        end
    end
end)
AddEventHandler('playerJoining',function()
    local src=source
    SetTimeout(1800,function()
        if GetPlayerName(src) then worldBroadcast(src);replayGlobalDisaster(src) end
    end)
end)
-- Client script restart / late load: state read only, checked by server.
RegisterNetEvent('rs-admin:server:disasterSync',function()
    local src=source
    if not src or src<=0 or not GetPlayerName(src) then return end
    local now=os.time()
    if (syncCooldown[src] or 0)>now then return end
    syncCooldown[src]=now+5
    worldBroadcast(src)
    replayGlobalDisaster(src)
end)
AddEventHandler('playerDropped',function()
    syncCooldown[source]=nil
    activeDisasters[source]=nil
    if meteorEvent and meteorEvent.source==source then stopGlobalDisaster('Meteor controller disconnected') end
end)
C.OnCharacterReady('world',function(src) worldBroadcast(src);replayGlobalDisaster(src) end)

-- Expire jail/staff state without client authority.
CreateThread(function()
    while true do
        Wait(5000); local now=os.time(); local jailDirty=false; local staffDirty=false
        for _,j in ipairs(STORE.jails) do
            if not j.releasedAt and j.expires and j.expires>0 and j.expires<=now then
                j.releasedAt=now; j.releasedBy='system'; j.releaseReason='Sentence complete'; jailDirty=true
                for _,s in ipairs(GetPlayers()) do local id=tonumber(s); if jailIdentity(id)==j.identifier then TriggerClientEvent('rs-admin:client:unjail',id,{coords=Config.Jail.release,reason='Sentence complete'}) end end
            end
        end
        for pid,e in pairs(STORE.staff) do if e.expires and e.expires>0 and e.expires<=now then STORE.staff[pid]=nil; staffDirty=true end end
        if jailDirty then save('jails') end; if staffDirty then save('staff') end
    end
end)
