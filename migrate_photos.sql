-- Run once on a database you already set up (adds equipment photos). Safe to re-run.
alter table items add column if not exists photo text;
create or replace function public_availability() returns jsonb language sql security definer stable set search_path=public as $$
 select jsonb_build_object('updated',now(),'groups',coalesce(jsonb_agg(g order by g->>'category'),'[]'::jsonb)) from
 (select jsonb_build_object('category',category,'count',count(*),'items',jsonb_agg(jsonb_build_object('name',name,'condition',condition,'photo',photo) order by name)) g
  from items where status='available' and condition in('new','good','fair') group by category) t $$;
