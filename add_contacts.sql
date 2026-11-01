-- Run once on an existing database: adds the three public contacts and removes the sample contact. Safe to re-run.
delete from contacts where name='Sample Coordinator';
insert into contacts(name,role,phone,whatsapp,sort)
select v.* from (values ('Suhail T.C','President','+919645051827','919645051827',1),('Abdul Faris C.K','Vice President','+918086168051','918086168051',2),('Muhammad Irshad K','Member','+917356264323','917356264323',3)) as v(name,role,phone,whatsapp,sort)
where not exists (select 1 from contacts c where c.phone=v.phone);
