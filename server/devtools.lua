local C=RSAdminCore
local catalog={peds={},props={}}
local raw=LoadResourceFile(GetCurrentResourceName(),'data/entity_catalog.json')
if raw then local good,data=pcall(json.decode,raw);if good and type(data)=='table' then catalog=data end end
local lookup={ped={},prop={}}
for _,kind in ipairs({'ped','prop'}) do for _,row in ipairs(catalog[kind=='ped' and 'peds' or 'props'] or {}) do lookup[kind][row.model]=row end end
C.Handle('catalog:entities','builder',function(_,d)
    local kind=d.kind=='ped' and 'ped' or 'prop';local q=C.Clean(d.q or '',100):lower();local category=C.Clean(d.category or '',50)
    local page=math.max(1,math.floor(tonumber(d.page) or 1));local size=math.max(12,math.min(48,math.floor(tonumber(d.pageSize) or 24)))
    local found,categories={},{}
    for _,row in ipairs(catalog[kind=='ped' and 'peds' or 'props'] or {}) do
        categories[row.category]=true
        if (category=='' or category=='all' or category==row.category) and (q=='' or (row.model..' '..row.label):lower():find(q,1,true)) then found[#found+1]=row end
    end
    local total=#found;local pages=math.max(1,math.ceil(total/size));page=math.min(page,pages);local out={}
    for i=(page-1)*size+1,math.min(total,page*size) do out[#out+1]=found[i] end
    local groups={};for key in pairs(categories) do groups[#groups+1]=key end;table.sort(groups)
    return C.Ok({rows=out,total=total,page=page,pages=pages,pageSize=size,categories=groups})
end)
C.Handle('builder:validate','builder',function(_,d)
    local kind=d.kind=='ped' and 'ped' or 'prop';local row=lookup[kind][C.Clean(d.model,80)]
    return row and C.Ok(row) or C.Err('Model is not in this catalog')
end)
C.Handle('code:authorize','owner',function(src,d)
    if not C.Can(src,'owner') then return C.Err('Owner required') end
    if d.scope~='client' and d.scope~='server' then return C.Err('Choose client or server Lua') end
    if type(d.code)~='string' or #d.code<1 or #d.code>8192 then return C.Err('Enter 1–8192 bytes of Lua') end
    C.Audit(src,'owner Lua console',d.scope..' '..#d.code..' bytes','self')
    if d.scope=='server' then return RSAdminLua.Run(d.code,{scope='server',source=src}) end
    return C.Ok({authorized=true})
end)
