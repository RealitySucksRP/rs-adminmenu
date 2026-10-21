local C,A,Adv=RSAdminCore,RSAdminServer.Adapter,RSAdminServer.Advanced
local journal=C.LoadJson('transfer_recovery',{})
local locks={}
local final={completed=true,refunded=true,debit_rejected=true,preparation_failed=true,resolved=true}
local function save()
    -- Keep unresolved outcomes indefinitely; bound completed history.
    local completed={}
    for id,r in pairs(journal) do if final[r.status] then completed[#completed+1]={id=id,at=r.at or 0} end end
    table.sort(completed,function(a,b) return a.at>b.at end)
    for i=(Config.Economy.maxTransactions or 2000)+1,#completed do journal[completed[i].id]=nil end
    return C.SaveCriticalJson('transfer_recovery',journal)
end
local function lockKey(character,account) return character..':'..account end
local function unresolved(character,account)
    for _,r in pairs(journal) do
        if not final[r.status] and r.account==account and (r.fromKey==character or r.toKey==character) then return true end
    end
    return false
end
function RSAdminServer.TransferBlocked(src,account)
    local key=C.CharacterIdentity(src)
    return not key or locks[lockKey(key,account)] or unresolved(key,account)
end
local function money(src,account,mode,amount,reason)
    local ok,result,e,uncertain=pcall(A.ChangeMoney,src,account,mode,amount,reason)
    return ok and result==true,ok and e or tostring(result),not ok or uncertain==true
end
function RSAdminServer.TransferMoney(src,d)
    local from,to=Adv.Target(d.from),Adv.Target(d.to)
    if not from or not to or from==to then return C.Err('Invalid players') end
    local amount=tonumber(d.amount)
    if not amount or amount~=amount or math.abs(amount)==math.huge then return C.Err('Invalid amount') end
    amount=math.floor(amount)
    local account=C.Clean(d.account or 'bank',12)
    local fromKey,toKey=C.CharacterIdentity(from),C.CharacterIdentity(to)
    local actorSession,fromSession,toSession=C.SessionIdentity(src),C.SessionIdentity(from),C.SessionIdentity(to)
    if not actorSession or not fromSession or not toSession then return C.Err('Both characters and staff must be loaded') end
    if RSAdminServer.TransferBlocked(from,account) or RSAdminServer.TransferBlocked(to,account) then return C.Err('Account has an active or unresolved transfer; review recovery first') end
    local first,second=lockKey(fromKey,account),lockKey(toKey,account)
    locks[first]=true;locks[second]=true
    local row
    local function unchanged() return C.SessionIdentity(from)==fromSession and C.SessionIdentity(to)==toSession and C.SessionIdentity(src)==actorSession and C.Can(src,'economy') end
    local function update(status,error)
        row.status=status;row.error=error and C.Clean(error,240) or nil;row.updated=os.time()
        return save()
    end
    local function refund(reason)
        update('refund_pending',reason)
        if C.SessionIdentity(from)~=fromSession then update('refund_required','Sender session changed; refund deferred');return C.Err('Refund requires owner review. Recovery ID: '..row.id) end
        local refunded,e,uncertain=money(from,account,'add',amount,'transfer rollback '..row.id)
        if refunded then update('refunded',reason);return C.Err('Credit failed; sender refund confirmed. Recovery ID: '..row.id) end
        update(uncertain and 'review_required' or 'refund_required',e or reason)
        C.Audit(src,'transfer recovery required',row.id,row.fromKey)
        return C.Err('Credit and refund failed; funds require owner review. Recovery ID: '..row.id)
    end
    local good,result=pcall(function()
        local allowed,e=Adv.AuthorizeTransfer(from,to,amount,account);if not allowed then return C.Err(e) end
        local reason=C.Clean(d.reason or 'Player transfer',180)
        if amount>=(Config.Economy.requireReasonAbove or math.huge) and #reason<3 then return C.Err('Reason required') end
        local beforeFrom,beforeTo=A.GetMoney(from,account),A.GetMoney(to,account)
        if type(beforeFrom)~='number' or type(beforeTo)~='number' then return C.Err('Balance provider unavailable') end
        if beforeFrom<amount then return C.Err('Sender has insufficient funds') end
        if not unchanged() then return C.Err('Player session or staff permission changed') end
        local id
        repeat id=('%s-%09d'):format(os.time(),math.random(1,999999999)) until not journal[id]
        row={id=id,status='prepared',at=os.time(),updated=os.time(),fromKey=fromKey,toKey=toKey,from=Adv.Primary(from),to=Adv.Primary(to),fromName=GetPlayerName(from),toName=GetPlayerName(to),account=account,amount=amount,reason=reason,staff=Adv.Actor(src),beforeFrom=beforeFrom,beforeTo=beforeTo}
        journal[id]=row
        if not save() then update('preparation_failed','Could not save preparation');return C.Err('Could not save transfer preparation; no money moved') end
        if not unchanged() then update('preparation_failed','Session changed before debit');return C.Err('Player session changed; no money moved') end
        local debited,de,uncertainDebit=money(from,account,'remove',amount,reason)
        if not debited then update(uncertainDebit and 'review_required' or 'debit_rejected',de);return C.Err((de or 'Debit rejected')..'. Recovery ID: '..row.id) end
        if not update('debited') then return refund('Could not persist debit stage') end
        if not unchanged() then return refund('Player session or staff permission changed after debit') end
        local credited,ce,uncertainCredit=money(to,account,'add',amount,reason)
        if uncertainCredit then update('review_required',ce or 'Credit outcome unknown');return C.Err('Credit outcome is uncertain; no automatic refund attempted. Recovery ID: '..row.id) end
        if not credited then return refund(ce or 'Credit rejected') end
        local persisted=update('completed')
        local transaction=Adv.RecordTransaction('player_transfer',row.from,row.to,account,amount,reason,row.staff,beforeFrom,beforeFrom-amount,beforeTo,beforeTo+amount)
        C.Audit(src,'economy transfer',('%s %s recovery:%s'):format(account,amount,id),row.fromKey..' -> '..row.toKey)
        local response=C.Ok(transaction)
        if not persisted then response.persistenceWarning='Transfer applied; recovery journal save pending' end
        return response
    end)
    locks[first]=nil;locks[second]=nil
    if not good then
        if row then row.status='review_required';row.error=C.Clean(result,240);save() end
        return C.Err('Transfer interrupted; owner review required'..(row and ('. Recovery ID: '..row.id) or ''))
    end
    return result
end
C.Handle('economy:recoveryList','owner',function()
    local rows={}
    for _,r in pairs(journal) do if not final[r.status] then rows[#rows+1]=r end end
    table.sort(rows,function(a,b) return (a.at or 0)>(b.at or 0) end)
    return C.Ok(rows)
end)
C.Handle('economy:resolveTransfer','owner',function(src,d)
    local r=journal[C.Clean(d.id,80)]
    if not r or final[r.status] then return C.Err('Unresolved transfer not found') end
    local note=C.Clean(d.note,300)
    if d.confirm~='REVIEWED' or #note<10 then return C.Err('Verify provider balances and supply a resolution note of at least 10 characters') end
    if locks[lockKey(r.fromKey,r.account)] or locks[lockKey(r.toKey,r.account)] then return C.Err('Transfer is still running') end
    local previous=r.status
    r.status='resolved';r.resolution=note;r.resolvedBy=Adv.Actor(src);r.resolvedAt=os.time()
    if not save() then r.status=previous;r.resolution=nil;r.resolvedBy=nil;r.resolvedAt=nil;save();return C.Err('Could not save resolution') end
    C.Audit(src,'transfer manually resolved',r.id..' '..note,r.fromKey)
    return C.Ok(true)
end)
