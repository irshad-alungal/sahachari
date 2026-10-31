-- Run once on a database set up with an older schema.sql (adds delete / undo / edit loan). Safe to re-run.

-- delete / undo / edit loans (v2)
create or replace function delete_loan(p_loan uuid,p_reason text) returns void
language plpgsql security definer set search_path=public as $$
declare l loans; begin
 if not is_admin() then raise exception 'Only an administrator can delete loans'; end if;
 select * into l from loans where id=p_loan for update;
 if not found then raise exception 'Loan not found'; end if;
 perform set_config('app.rpc','on',true);
 if l.returned_at is null then update items set status='available' where id=l.item_id and status='borrowed'; end if;
 delete from loans where id=p_loan;
 insert into audit_log(actor,tbl,op,row_id,data) values(auth.uid(),'loans','DELETE_REASON',p_loan::text,jsonb_build_object('ref',l.ref,'reason',p_reason));
end $$;
create or replace function reopen_loan(p_loan uuid) returns void
language plpgsql security definer set search_path=public as $$
declare l loans; it items; begin
 if not is_staff() then raise exception 'Not authorised'; end if;
 select * into l from loans where id=p_loan for update;
 if not found or l.returned_at is null then raise exception 'This loan is not returned'; end if;
 select * into it from items where id=l.item_id for update;
 if it.status='borrowed' then raise exception 'This item is already lent out again'; end if;
 perform set_config('app.rpc','on',true);
 update loans set returned_at=null,condition_in=null,return_notes=null,returned_by=null where id=p_loan;
 update items set status='borrowed' where id=l.item_id;
end $$;
create or replace function update_loan(p_loan uuid,p_expected date,p_notes text) returns void
language plpgsql security definer set search_path=public as $$
begin
 if not is_staff() then raise exception 'Not authorised'; end if;
 update loans set expected_return=p_expected,notes=p_notes where id=p_loan;
 if not found then raise exception 'Loan not found'; end if;
end $$;

revoke execute on function delete_loan(uuid,text), reopen_loan(uuid), update_loan(uuid,date,text) from public, anon;
grant execute on function delete_loan(uuid,text), reopen_loan(uuid), update_loan(uuid,date,text) to authenticated;
