insert into packages (name, price_cents, duration_days, is_featured, homepage_slot, search_boost) values
 ('Standard', 9900, 30, false, false, 0),
 ('Featured', 19900, 30, true, false, 1),
 ('Premium', 39900, 30, true, true, 2);
insert into settings (key, value) values ('auto_approve','false'), ('max_photos','20');
insert into categories (slug, name, sort_order) values
 ('house','House',1),('apartment','Apartment',2),('flat','Flat',3),('townhouse','Townhouse',4),('penthouse','Penthouse',5),
 ('vacant-land','Vacant Land & Plots',6),('farm','Farm',7),('commercial','Commercial Property',8),('student','Student Accommodation',9),
 ('new-development','New Development',10),('fixer-upper','Fixer-Upper',11),('investment','Investment Property',12),('holiday','Holiday Property',13),('room','Room & Shared Accommodation',14);
insert into locations (slug, name, kind) values
 ('gauteng','Gauteng','province'),('western-cape','Western Cape','province'),('kwazulu-natal','KwaZulu-Natal','province'),
 ('eastern-cape','Eastern Cape','province'),('free-state','Free State','province'),('limpopo','Limpopo','province'),('mpumalanga','Mpumalanga','province');
insert into locations (slug, name, kind, parent_id)
select v.slug, v.name, 'city', (select id from locations where slug = v.prov) from (values
 ('johannesburg','Johannesburg','gauteng'),('sandton','Sandton','gauteng'),('midrand','Midrand','gauteng'),('pretoria','Pretoria','gauteng'),
 ('cape-town','Cape Town','western-cape'),('durban','Durban','kwazulu-natal'),('umhlanga','Umhlanga','kwazulu-natal'),('ballito','Ballito','kwazulu-natal'),
 ('gqeberha','Gqeberha','eastern-cape'),('bloemfontein','Bloemfontein','free-state'),('polokwane','Polokwane','limpopo'),('mbombela','Mbombela','mpumalanga')) as v(slug,name,prov);
