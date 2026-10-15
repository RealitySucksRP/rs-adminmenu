local C=RSAdminCore
if not C then error('RSAdminCore unavailable') end
local H,Can,Clean,Ok,Err,Audit=C.Handle,C.Can,C.Clean,C.Ok,C.Err,C.Audit
local RESOURCE=GetCurrentResourceName()

local function loadGroups()
    return C.LoadJson('staff_groups',{})
end
local groups=loadGroups()
RSAdminServer.CustomStaffRoles=groups

local function save() C.SaveJson('staff_groups',groups) end
local function safeKey(v) return Clean(v or '',32):lower():gsub('[^%w_%-]','') end
local function safeColor(v)
    v=Clean(v or '#20a9ff',16)
    if not v:match('^#%x%x%x%x%x%x$') then return '#20a9ff' end
    return v
end
local function permissions(list)
    local allowed={}
    for k in pairs(Config.Ace or {}) do allowed[k]=true end
    allowed.chat=true; allowed.all=true
    local out={}; local seen={}
    for _,p in ipairs(type(list)=='table' and list or {}) do p=Clean(p,32); if allowed[p] and not seen[p] then seen[p]=true; out[#out+1]=p end end
    return out
end
local function list()
    local out={}
    for k,v in pairs(Config.StaffRoles or {}) do local x={key=k,builtin=true}; for a,b in pairs(v) do x[a]=b end; out[#out+1]=x end
    for k,v in pairs(groups) do local x={key=k,builtin=false}; for a,b in pairs(v) do x[a]=b end; out[#out+1]=x end
    table.sort(out,function(a,b) return (tonumber(a.rank) or 0)>(tonumber(b.rank) or 0) end); return out
end
H('staffGroup:list','staff',function(src) return Ok(list()) end)
H('staffGroup:create','owner',function(src,d)
    if not (Config.StaffGroups and Config.StaffGroups.allowCustomGroups) then return Err('Custom groups disabled') end
    local key=safeKey(d.key); if key=='' then return Err('Group key required') end
    if (Config.StaffRoles and Config.StaffRoles[key]) or groups[key] then return Err('Group already exists') end
    local count=0; for _ in pairs(groups) do count=count+1 end; if count>=(Config.StaffGroups.maxGroups or 32) then return Err('Custom group limit reached') end
    local rank=math.max(1,math.min(99,math.floor(tonumber(d.rank) or 10)))
    groups[key]={label=Clean(d.label or key,64),rank=rank,color=safeColor(d.color),position=Clean(d.position or d.label or key,80),wildcard=d.wildcard==true,permissions=permissions(d.permissions),createdBy=GetPlayerName(src),createdAt=os.time()}
    save(); Audit(src,'staff group create',key,key); return Ok(groups[key])
end)
H('staffGroup:update','owner',function(src,d)
    local key=safeKey(d.key); local g=groups[key]; if not g then return Err('Custom group not found') end
    if d.label~=nil then g.label=Clean(d.label,64) end; if d.rank~=nil then g.rank=math.max(1,math.min(99,math.floor(tonumber(d.rank) or g.rank))) end
    if d.color~=nil then g.color=safeColor(d.color) end; if d.position~=nil then g.position=Clean(d.position,80) end; if d.wildcard~=nil then g.wildcard=d.wildcard==true end
    if d.permissions~=nil then g.permissions=permissions(d.permissions) end; g.updatedBy=GetPlayerName(src); g.updatedAt=os.time(); save(); Audit(src,'staff group update',key,key); return Ok(g)
end)
H('staffGroup:clone','owner',function(src,d)
    local from=safeKey(d.from); local key=safeKey(d.key); local base=groups[from] or (Config.StaffRoles and Config.StaffRoles[from]); if not base then return Err('Source group not found') end
    if key=='' or groups[key] or (Config.StaffRoles and Config.StaffRoles[key]) then return Err('Invalid or existing target key') end
    local g={label=Clean(d.label or ((base.label or from)..' Copy'),64),rank=math.max(1,math.min(99,tonumber(base.rank) or 10)),color=safeColor(base.color),position=Clean(base.position or base.label or key,80),wildcard=false,permissions=permissions(base.permissions),createdBy=GetPlayerName(src),createdAt=os.time()}; groups[key]=g; save(); Audit(src,'staff group clone',from..' -> '..key,key); return Ok(g)
end)
H('staffGroup:delete','owner',function(src,d)
    local key=safeKey(d.key); if not groups[key] then return Err('Custom group not found') end
    local store=RSAdminServer.Advanced and RSAdminServer.Advanced.Store
    if store and store.staff then for _,e in pairs(store.staff) do if e.role==key then return Err('Group is still assigned to staff') end end end
    groups[key]=nil; save(); Audit(src,'staff group delete',key,key); return Ok(true)
end)
