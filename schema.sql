-- Community Medical Equipment Lending  |  SAFE TO RE-RUN (never deletes your data)
-- Run in Supabase > SQL Editor

-- ========== TABLES ==========
create table if not exists profiles(id uuid primary key references auth.users on delete cascade, full_name text, role text not null default 'staff' check(role in('admin','staff')), active boolean not null default true);
create table if not exists items(id uuid primary key default gen_random_uuid(), code text unique not null, name text not null, category text not null, brand text,
 description text, condition text not null default 'good' check(condition in('new','good','fair','damaged','under_repair')),
 status text not null default 'available' check(status in('available','borrowed','maintenance','damaged','retired')),
 acquired_on date, photo text, notes text, created_at timestamptz default now(), updated_at timestamptz default now());
alter table items add column if not exists photo text;   -- file name inside assets/equipment/
create sequence if not exists ben_seq; create sequence if not exists loan_seq;
create table if not exists beneficiaries(id uuid primary key default gen_random_uuid(), ref text unique default 'B-'||lpad(nextval('ben_seq')::text,5,'0'),
 full_name text not null, phone text not null, alt_phone text, address text, emergency_contact text, notes text,
 active boolean not null default true, created_at timestamptz default now());
create index if not exists beneficiaries_phone_idx on beneficiaries(phone);
create table if not exists loans(id uuid primary key default gen_random_uuid(), ref text unique not null default 'L-'||lpad(nextval('loan_seq')::text,6,'0'),
 item_id uuid not null references items, beneficiary_id uuid not null references beneficiaries,
 issued_at timestamptz not null default now(), expected_return date, condition_out text, notes text, issued_by uuid default auth.uid(),
 returned_at timestamptz, condition_in text, return_notes text, returned_by uuid);
create unique index if not exists one_active_loan_per_item on loans(item_id) where returned_at is null;
create table if not exists contacts(id uuid primary key default gen_random_uuid(), name text not null, role text, phone text not null, whatsapp text, email text,
 sort int default 0, public boolean default true);
create table if not exists settings(id int primary key default 1 check(id=1), initiative_name text, intro text, address text, hours text, enquiry_text text);
create table if not exists audit_log(id bigserial primary key, at timestamptz default now(), actor uuid, tbl text, op text, row_id text, data jsonb);

-- ========== HELPER FUNCTIONS ==========
create or replace function is_staff() returns boolean language sql security definer stable set search_path=public as
$$ select exists(select 1 from profiles where id=auth.uid() and active) $$;
create or replace function is_admin() returns boolean language sql security definer stable set search_path=public as
$$ select exists(select 1 from profiles where id=auth.uid() and active and role='admin') $$;

-- ========== TRIGGERS ==========
create or replace function touch() returns trigger language plpgsql as $$ begin new.updated_at=now(); return new; end $$;
create or replace function guard_status() returns trigger language plpgsql as $$ begin
 if (old.status='borrowed' or new.status='borrowed') and old.status is distinct from new.status
    and coalesce(current_setting('app.rpc',true),'')<>'on' then raise exception 'Use Issue/Return to change borrowed status'; end if;
 return new; end $$;
create or replace function audit() returns trigger language plpgsql security definer set search_path=public as $$ begin
 insert into audit_log(actor,tbl,op,row_id,data) values(auth.uid(),tg_table_name,tg_op,to_jsonb(coalesce(new,old))->>'id',to_jsonb(coalesce(new,old))); return null; end $$;

drop trigger if exists t_touch on items;  create trigger t_touch before update on items for each row execute function touch();
drop trigger if exists t_guard on items;  create trigger t_guard before update on items for each row execute function guard_status();
drop trigger if exists a1 on items;         create trigger a1 after insert or update or delete on items         for each row execute function audit();
drop trigger if exists a2 on beneficiaries; create trigger a2 after insert or update or delete on beneficiaries for each row execute function audit();
drop trigger if exists a3 on loans;         create trigger a3 after insert or update or delete on loans         for each row execute function audit();
drop trigger if exists a4 on contacts;      create trigger a4 after insert or update or delete on contacts      for each row execute function audit();
drop trigger if exists a5 on settings;      create trigger a5 after insert or update or delete on settings      for each row execute function audit();
drop trigger if exists a6 on profiles;      create trigger a6 after insert or update or delete on profiles      for each row execute function audit();

-- ========== ROW LEVEL SECURITY (anonymous users can read nothing) ==========
alter table profiles enable row level security; alter table items enable row level security; alter table beneficiaries enable row level security;
alter table loans enable row level security; alter table contacts enable row level security; alter table settings enable row level security;
alter table audit_log enable row level security;
drop policy if exists p_prof_r on profiles;  create policy p_prof_r on profiles for select using(id=auth.uid() or is_admin());
drop policy if exists p_prof_w on profiles;  create policy p_prof_w on profiles for all using(is_admin()) with check(is_admin());
drop policy if exists p_items on items;      create policy p_items on items for all using(is_staff()) with check(is_staff());
drop policy if exists p_ben on beneficiaries;create policy p_ben on beneficiaries for all using(is_staff()) with check(is_staff());
drop policy if exists p_loans_r on loans;    create policy p_loans_r on loans for select using(is_staff());   -- loans are written ONLY by issue_item/return_item
drop policy if exists p_con_r on contacts;   create policy p_con_r on contacts for select using(is_staff());
drop policy if exists p_con_w on contacts;   create policy p_con_w on contacts for all using(is_admin()) with check(is_admin());
drop policy if exists p_set_r on settings;   create policy p_set_r on settings for select using(is_staff());
drop policy if exists p_set_w on settings;   create policy p_set_w on settings for all using(is_admin()) with check(is_admin());
drop policy if exists p_audit on audit_log;  create policy p_audit on audit_log for select using(is_admin());
revoke delete on items, loans, beneficiaries from authenticated, anon;   -- history is never deleted; archive items as 'retired'
revoke all on all tables in schema public from anon;
grant usage on sequence ben_seq, loan_seq to authenticated;

-- ========== LENDING FUNCTIONS (atomic, row-locked) ==========
create or replace function issue_item(p_item uuid,p_ben uuid,p_expected date,p_cond text,p_notes text) returns text
language plpgsql security definer set search_path=public as $$
declare it items; lref text; begin
 if not is_staff() then raise exception 'Not authorised'; end if;
 select * into it from items where id=p_item for update;
 if not found or it.status<>'available' then raise exception 'Item is not available'; end if;
 if not exists(select 1 from beneficiaries where id=p_ben and active) then raise exception 'Beneficiary not found or inactive'; end if;
 perform set_config('app.rpc','on',true);
 insert into loans(item_id,beneficiary_id,expected_return,condition_out,notes) values(p_item,p_ben,p_expected,p_cond,p_notes) returning ref into lref;
 update items set status='borrowed' where id=p_item;
 return lref; end $$;
create or replace function return_item(p_loan uuid,p_cond text,p_notes text,p_next text) returns void
language plpgsql security definer set search_path=public as $$
declare iid uuid; begin
 if not is_staff() then raise exception 'Not authorised'; end if;
 if p_next not in('available','maintenance','damaged','retired') then raise exception 'Choose the item status after inspection'; end if;
 if p_next='available' and p_cond in('damaged','under_repair') then raise exception 'A damaged item cannot be marked available'; end if;
 perform set_config('app.rpc','on',true);
 update loans set returned_at=now(),condition_in=p_cond,return_notes=p_notes,returned_by=auth.uid() where id=p_loan and returned_at is null returning item_id into iid;
 if iid is null then raise exception 'Loan not found or already returned'; end if;
 update items set status=p_next,condition=p_cond where id=iid; end $$;


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

-- ========== PUBLIC (QR PAGE) FUNCTIONS: the only things anonymous visitors can call ==========
create or replace function public_availability() returns jsonb language sql security definer stable set search_path=public as $$
 select jsonb_build_object('updated',now(),'groups',coalesce(jsonb_agg(g order by g->>'category'),'[]'::jsonb)) from
 (select jsonb_build_object('category',category,'count',count(*),'items',jsonb_agg(jsonb_build_object('name',name,'condition',condition,'photo',photo) order by name)) g
  from items where status='available' and condition in('new','good','fair') group by category) t $$;
create or replace function public_info() returns jsonb language sql security definer stable set search_path=public as $$
 select jsonb_build_object('settings',(select to_jsonb(s)-'id' from settings s limit 1),
  'contacts',(select coalesce(jsonb_agg(jsonb_build_object('name',name,'role',role,'phone',phone,'whatsapp',whatsapp,'email',email) order by sort,name),'[]'::jsonb) from contacts where public)) $$;
revoke execute on all functions in schema public from public, anon;
grant execute on function public_availability(), public_info() to anon, authenticated;
grant execute on function is_staff(), is_admin(), issue_item(uuid,uuid,date,text,text), return_item(uuid,text,text,text),
  delete_loan(uuid,text), reopen_loan(uuid), update_loan(uuid,date,text) to authenticated;

-- ========== REQUIRED: default public-page text (only inserted if missing) ==========
insert into settings(id,initiative_name,intro,address,hours,enquiry_text) values(1,'Sahachari – SKSSF Alungal Unit',
 'Sahachari is a community initiative of SKSSF Alungal Unit to lend surgical and mobility equipment free of charge to people in the local area.','SKSSF Alungal Unit, Sahachari Center, Alungal Thottiyil, Malappuram','','Call or message a contact below.')
on conflict (id) do nothing;

-- ========== REQUIRED: make your login the first administrator ==========
insert into profiles(id,full_name,role,active) values('2d3df09f-0f14-49ce-ad87-a505bd24dcbc','Administrator','admin',true)
on conflict (id) do update set role='admin', active=true;

-- ========== Public contacts for Sahachari (edit later in Settings > Committee contacts) ==========
insert into contacts(name,role,phone,whatsapp,sort)
select v.* from (values ('Suhail T.C','President','+919645051827','919645051827',1),('Abdul Faris C.K','Vice President','+918086168051','918086168051',2),('Muhammad Irshad K','Member','+917356264323','917356264323',3)) as v(name,role,phone,whatsapp,sort)
where not exists (select 1 from contacts c where c.phone=v.phone);

-- ========== OPTIONAL: sample test data. Run ONCE, delete this section afterwards ==========
insert into items(code,name,category,brand,condition) values
 ('W001','Folding wheelchair','Wheelchairs','Generic','good'),('W002','Folding wheelchair','Wheelchairs','Generic','fair'),
 ('WK001','Walking frame','Walkers',null,'good'),('A001','Anti-bedsore air mattress','Air beds',null,'new'),('C001','Commode chair','Commode chairs',null,'good')
on conflict (code) do nothing;
