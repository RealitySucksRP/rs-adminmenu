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
    local data=A and A.GetPlayerData(src)
    return data and data.citizenid and ('character:'..data.citizenid) or primary(src)
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
    amount=math.floor(tonumber(amount) or 0); account=tostring(account or 'bank')
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

-- Lifecycle / playtime ---------------------------------------------------------
AddEventHandler('playerJoining',function()
    local src=source; SetTimeout(1200,function() if GetPlayerName(src) then startSession(src); syncJail(src) end end)
end)
AddEventHandler('playerDropped',function() finishSession(source) end)
AddEventHandler('onResourceStart',function(res)
    if res~=RESOURCE then return end
    for _,s in ipairs(GetPlayers()) do local src=tonumber(s); startSession(src); SetTimeout(1200,function() if GetPlayerName(src) then syncJail(src) end end) end
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
    local mode=Clean(d.mode or 'add',12); if mode~='add' and mode~='remove' and mode~='set' then return Err('Invalid mode') end
    local amount=math.floor(tonumber(d.amount) or 0); if amount<0 or amount>(Config.Economy.maxAdminAdjustment or 5000000) then return Err('Amount outside configured limit') end
    local reason=Clean(d.reason or 'Admin adjustment',180); if amount>=(Config.Economy.requireReasonAbove or math.huge) and #reason<3 then return Err('Reason required for high value adjustment') end
    local before=A.GetMoney(t,account) or 0; local good,e=A.ChangeMoney(t,account,mode,amount,reason); if not good then return Err(e or 'Money action failed') end; local after=A.GetMoney(t,account) or before
    local row=transaction('admin_adjust',nil,primary(t),account,amount,reason,actor(src),nil,nil,before,after); Audit(src,'economy '..mode,('%s $%s | %s'):format(account,amount,reason),GetPlayerName(t)); return Ok({balance=after,transaction=row})
end)
H('economy:transfer','economy',function(src,d)
    local from=target(d.from); local to=target(d.to); if not from or not to or from==to then return Err('Invalid players') end
    local amount=math.floor(tonumber(d.amount) or 0); local account=Clean(d.account or 'bank',12); local allowed,e=authorizeTransfer(from,to,amount,account); if not allowed then return Err(e) end
    local reason=Clean(d.reason or 'Player transfer',180); if amount>=(Config.Economy.requireReasonAbove or math.huge) and #reason<3 then return Err('Reason required') end
    local bf=A.GetMoney(from,account) or 0; local bt=A.GetMoney(to,account) or 0; if bf<amount then return Err('Sender has insufficient funds') end
    local good,er=A.ChangeMoney(from,account,'remove',amount,reason); if not good then return Err(er or 'Debit failed') end
    good,er=A.ChangeMoney(to,account,'add',amount,reason); if not good then A.ChangeMoney(from,account,'add',amount,'transfer rollback'); return Err(er or 'Credit failed; sender rolled back') end
    local af=A.GetMoney(from,account) or (bf-amount); local at=A.GetMoney(to,account) or (bt+amount); local row=transaction('player_transfer',primary(from),primary(to),account,amount,reason,actor(src),bf,af,bt,at)
    Audit(src,'economy transfer',('%s $%s'):format(account,amount),('%s -> %s'):format(GetPlayerName(from),GetPlayerName(to))); return Ok(row)
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
    local pid=jailIdentity(t); local current=activeJailForIdentifier(pid); if current then current.releasedAt=os.time(); current.releaseReason='Replaced by new sentence'; current.releasedBy=actor(src) end
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
local WORLD={}; for k,v in pairs(Config.World.defaults or {}) do WORLD[k]=v end
WORLD.overrides={}
local function worldBroadcast(target) TriggerClientEvent('rs-admin:client:worldState',target or -1,WORLD) end
H('world:state','world',function() return Ok(WORLD) end)
local function patchWorld(src,d)
    local weather
    if d.weather~=nil then
        weather=Clean(d.weather,24):upper(); local valid=false
        for _,name in ipairs(Config.WeatherTypes or {}) do if name==weather then valid=true break end end
        if not valid then return nil,'Invalid weather' end
    end
    local allowed={weather=true,hour=true,minute=true,blackout=true,rain=true,wind=true,windDirection=true,traffic=true,parked=true,randomVehicles=true,peds=true,scenarios=true}
    for k,v in pairs(d or {}) do if allowed[k] then
        WORLD.overrides[k]=true
        if k=='weather' then WORLD.weather=weather
        elseif k=='blackout' then WORLD.blackout=v==true
        elseif k=='hour' then WORLD.hour=math.max(0,math.min(23,math.floor(tonumber(v) or WORLD.hour or 12)))
        elseif k=='minute' then WORLD.minute=math.max(0,math.min(59,math.floor(tonumber(v) or WORLD.minute or 0)))
        elseif k=='windDirection' then WORLD.windDirection=(tonumber(v) or 0)%360
        else local hi=k=='wind' and 20.0 or 1.0; local lo=k=='rain' and -1.0 or 0.0; WORLD[k]=math.max(lo,math.min(hi,tonumber(v) or WORLD[k] or 0.0)) end
    end end
    -- A weather preset releases the previous manual rain override. Explicit
    -- rain in the same patch still wins, including a deliberate dry storm.
    if weather and d.rain==nil then WORLD.rain=-1.0;WORLD.overrides.rain=true end
    worldBroadcast(-1); Audit(src,'world patch',json.encode(d),'all'); webhook('world','World state changed',{Staff=actor(src),State=json.encode(d)}); return WORLD
end
RSAdminServer.PatchWorld=patchWorld
H('world:patch','world',function(src,d)
    local result,e=patchWorld(src,d); return result and Ok(result) or Err(e)
end)
H('world:release','world',function(src)
    WORLD.overrides={};worldBroadcast(-1);Audit(src,'release world overrides','','world');return Ok(WORLD)
end)
local DISASTER_NAMES={blackout=true,thunderstorm=true,hurricane=true,blizzard=true,sandstorm=true,toxicfog=true,earthquake=true,meteor=true,tornado=true,firestorm=true,emp=true,tsunami=true}
local activeDisasters={}
H('disaster:start','world',function(src,d)
    local name=Clean(d.name,32):lower(); if not DISASTER_NAMES[name] then return Err('Unknown disaster') end; local scope=Clean(d.scope or 'self',16):lower(); local dst=(scope=='all') and -1 or src
    if scope=='all' and Config.Disasters.requireOwnerForGlobalDangerous and Config.Disasters.dangerous[name] and not (Can(src,'owner') or Can(src,'developer')) then return Err('Owner/developer required for global dangerous event') end
    local payload={name=name,seconds=math.max(5,math.min(Config.Disasters.maxSeconds or 120,math.floor(tonumber(d.seconds) or 30))),intensity=math.max(0.1,math.min(1.0,tonumber(d.intensity) or .65)),damage=(d.damage==true and Config.Disasters.allowDamage==true),by=actor(src)}
    if name=='tornado' then
        local ped=GetPlayerPed(src);if ped==0 then return Err('Staff character unavailable') end
        local c=GetEntityCoords(ped);local heading=math.rad(GetEntityHeading(ped));payload.origin={x=c.x-math.sin(heading)*15.0,y=c.y+math.cos(heading)*15.0,z=c.z};payload.affectedVehicles={}
        if d.affectEntities==true then
            if not Can(src,'owner') then return Err('Owner required for storm vehicle physics') end
            local candidates=cleanupMatches(src,{mode='radius',radius=80})
            for i,row in ipairs(candidates or {}) do if i>24 then break end;payload.affectedVehicles[#payload.affectedVehicles+1]={netId=row.stamp.net,plate=row.stamp.plate,model=row.stamp.model} end
        end
    end
    for _,player in ipairs(dst==-1 and GetPlayers() or {src}) do local id=tonumber(player);activeDisasters[id]={identity=jailIdentity(id),expires=os.time()+payload.seconds} end
    TriggerClientEvent('rs-admin:client:disaster',dst,payload); Audit(src,'disaster '..name,('%s %ss'):format(scope,payload.seconds),'world'); webhook('disasters','Disaster simulation started',{Type=name,Scope=scope,Seconds=payload.seconds,Intensity=payload.intensity,Staff=actor(src)},16744192); return Ok(payload)
end)
H('disaster:stop','world',function(src,d) local scope=Clean(d.scope or 'self',16);if scope=='all' then activeDisasters={} else activeDisasters[src]=nil end; TriggerClientEvent('rs-admin:client:disasterStop',scope=='all' and -1 or src,{}); worldBroadcast(scope=='all' and -1 or src); Audit(src,'disaster stop',scope,'world'); return Ok(true) end)
CreateThread(function()
    while true do Wait(1000);local now=os.time()
        for id,storm in pairs(activeDisasters) do
            if not GetPlayerName(id) or jailIdentity(id)~=storm.identity then activeDisasters[id]=nil
            elseif now>=storm.expires then activeDisasters[id]=nil;TriggerClientEvent('rs-admin:client:disasterStop',id,{});worldBroadcast(id) end
        end
    end
end)
AddEventHandler('playerJoining',function() local src=source; SetTimeout(1800,function() if GetPlayerName(src) then worldBroadcast(src) end end) end)

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
