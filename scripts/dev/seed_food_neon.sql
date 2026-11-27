-- Synthetic Food catalog for the DEV Neon database (project kunde-dev). Idempotent: a restaurant whose slug already
-- exists is skipped entirely (its menu is not touched), so reruns change nothing. Every row is marked
-- is_synthetic = true (Consumer shows the «ДЕМО» badge). No users, orders, reviews, photos or personal data.
-- Prices are in tiyn (minor units). Run with scripts/dev/seed_food_neon.sh. DEV ONLY: never run against PROD.
do $seed$
declare
    r jsonb;
    s jsonb;
    d jsonb;
    rid uuid;
    sid uuid;
    rn int := 0;
    sn int;
    dn int;
begin
    for r in select * from jsonb_array_elements($json$[
      {"slug":"test-fresco","name":"Fresco Restaurant","cuisine":"Европейская кухня","emoji":"🥗","tone":"green",
       "description":"Выдуманный ресторан для тестов: стейки, салаты и горячее.","fee":100000,"min":150000,"eta":[15,30],"sort":20,
       "address":"Алматы, тестовый адрес 1",
       "sections":[
        {"name":"Популярное","dishes":[
          {"n":"Стейк из говядины","d":"300 г","p":490000,"e":"🥩","t":"red"},
          {"n":"Цезарь с курицей","d":"250 г","p":280000,"e":"🥗","t":"green"},
          {"n":"Паста карбонара","d":"320 г","p":310000,"e":"🍝","t":"amber"}]},
        {"name":"Салаты","dishes":[
          {"n":"Греческий салат","d":"230 г","p":240000,"e":"🥗","t":"green"},
          {"n":"Салат с лососем","d":"260 г","p":340000,"e":"🥗","t":"blue"}]},
        {"name":"Горячее","dishes":[
          {"n":"Курица на гриле","d":"280 г","p":360000,"e":"🍗","t":"amber"},
          {"n":"Ризотто с грибами","d":"300 г","p":330000,"e":"🍚","t":"orange"}]}]},
      {"slug":"test-sushi-time","name":"Sushi Time","cuisine":"Суши и роллы","emoji":"🍣","tone":"blue",
       "description":"Выдуманная суши-кухня для тестов.","fee":120000,"min":200000,"eta":[20,35],"sort":21,
       "address":"Алматы, тестовый адрес 2",
       "sections":[
        {"name":"Роллы","dishes":[
          {"n":"Филадельфия","d":"8 шт","p":420000,"e":"🍣","t":"blue"},
          {"n":"Калифорния","d":"8 шт","p":380000,"e":"🍣","t":"orange"},
          {"n":"Запечённый ролл","d":"8 шт","p":400000,"e":"🍣","t":"red"}]},
        {"name":"Сеты","dishes":[
          {"n":"Сет «Тест»","d":"24 шт","p":1190000,"e":"🍱","t":"amber"}]},
        {"name":"Напитки","dishes":[
          {"n":"Зелёный чай","d":"0.5 л","p":90000,"e":"🍵","t":"green"}]}]},
      {"slug":"test-nomad-food","name":"Nomad Food","cuisine":"Казахская кухня","emoji":"🍖","tone":"orange",
       "description":"Выдуманная национальная кухня для тестов.","fee":90000,"min":180000,"eta":[25,40],"sort":22,
       "address":"Алматы, тестовый адрес 3",
       "sections":[
        {"name":"Горячее","dishes":[
          {"n":"Бешбармак","d":"400 г","p":450000,"e":"🍖","t":"orange"},
          {"n":"Лагман","d":"350 г","p":290000,"e":"🍜","t":"red"},
          {"n":"Манты","d":"6 шт","p":320000,"e":"🥟","t":"amber"}]},
        {"name":"Выпечка","dishes":[
          {"n":"Баурсаки","d":"10 шт","p":120000,"e":"🍩","t":"amber"},
          {"n":"Самса с мясом","d":"1 шт","p":80000,"e":"🥟","t":"orange"}]}]},
      {"slug":"test-burger-lab","name":"Burger Lab","cuisine":"Бургеры","emoji":"🍔","tone":"amber",
       "description":"Выдуманная бургерная для тестов.","fee":0,"min":120000,"eta":[20,30],"sort":23,
       "address":"Алматы, тестовый адрес 4",
       "sections":[
        {"name":"Бургеры","dishes":[
          {"n":"Чизбургер","d":"250 г","p":260000,"e":"🍔","t":"amber"},
          {"n":"Двойной бургер","d":"380 г","p":390000,"e":"🍔","t":"red"}]},
        {"name":"Гарниры","dishes":[
          {"n":"Картофель фри","d":"150 г","p":120000,"e":"🍟","t":"amber"}]}]},
      {"slug":"test-sweet-house","name":"Sweet House","cuisine":"Десерты","emoji":"🍰","tone":"red",
       "description":"Выдуманная кондитерская для тестов.","fee":80000,"min":100000,"eta":[15,25],"sort":24,
       "address":"Алматы, тестовый адрес 5",
       "sections":[
        {"name":"Десерты","dishes":[
          {"n":"Чизкейк","d":"130 г","p":180000,"e":"🍰","t":"red"},
          {"n":"Тирамису","d":"150 г","p":200000,"e":"🍰","t":"amber"}]},
        {"name":"Напитки","dishes":[
          {"n":"Капучино","d":"250 мл","p":110000,"e":"☕","t":"amber"}]}]}
    ]$json$::jsonb)
    loop
        if exists (select 1 from marketplace.food_restaurants where slug = r->>'slug') then
            raise notice 'skip %: already exists', r->>'slug';
            continue;
        end if;
        insert into marketplace.food_restaurants
            (slug, name, cuisine, description, emoji, tone, delivery_fee_minor, min_order_minor,
             eta_min_minutes, eta_max_minutes, is_open, is_synthetic, sort_order, vertical,
             pickup_enabled, address_text, prep_minutes, latitude, longitude)
        values
            (r->>'slug', r->>'name', r->>'cuisine', r->>'description', r->>'emoji', r->>'tone',
             (r->>'fee')::bigint, (r->>'min')::bigint,
             (r->'eta'->>0)::int, (r->'eta'->>1)::int, true, true, (r->>'sort')::int, 'FOOD',
             true, r->>'address', 20,
             round((43.2389 + ((abs(hashtext(r->>'slug')) % 1000) - 500) / 10000.0)::numeric, 6),
             round((76.8897 + ((abs(hashtext((r->>'slug') || '#lon')) % 1000) - 500) / 10000.0)::numeric, 6))
        returning id into rid;
        sn := 0;
        for s in select * from jsonb_array_elements(r->'sections') loop
            insert into marketplace.food_menu_sections (restaurant_id, name, sort_order)
            values (rid, s->>'name', sn) returning id into sid;
            dn := 0;
            for d in select * from jsonb_array_elements(s->'dishes') loop
                insert into marketplace.food_dishes
                    (restaurant_id, section_id, name, description, price_minor, emoji, tone, sort_order)
                values (rid, sid, d->>'n', d->>'d', (d->>'p')::bigint, d->>'e', d->>'t', dn);
                dn := dn + 1;
            end loop;
            sn := sn + 1;
        end loop;
        rn := rn + 1;
        raise notice 'inserted %', r->>'slug';
    end loop;
    raise notice 'restaurants inserted: %', rn;
end
$seed$;
