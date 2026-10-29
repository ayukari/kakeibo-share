-- テスト用の道具（ローカルの DB だけ）
create schema if not exists tst;
grant usage on schema tst to authenticated;

create or replace function tst.user(p_id uuid, p_email text, p_name text) returns uuid language sql as $$
  insert into auth.users (id, email, raw_user_meta_data) values (p_id, p_email, jsonb_build_object('display_name', p_name)) on conflict do nothing returning id
$$;
-- 次の SET ROLE authenticated から、このユーザーとして振る舞う
create or replace function tst.as_user(p_id uuid) returns void language sql as $$
  select set_config('request.jwt.claims', case when p_id is null then '' else json_build_object('sub', p_id, 'role', 'authenticated')::text end, false)
$$;
-- sql が errcode のエラーになること（ならなければ失敗）
create or replace function tst.raises(p_sql text, p_code text, p_label text) returns void language plpgsql as $$
begin
  execute p_sql;
  raise exception 'FAIL(%) エラーになりませんでした: %', p_label, p_sql;
exception when others then
  if sqlerrm like 'FAIL(%' then raise; end if;
  if sqlstate <> p_code then raise exception 'FAIL(%) 期待 % なのに % (%): %', p_label, p_code, sqlstate, sqlerrm, p_sql; end if;
end $$;
create or replace function tst.eq(a anyelement, b anyelement, p_label text) returns void language plpgsql as $$
begin
  if a is distinct from b then raise exception 'FAIL(%) % <> %', p_label, a, b; end if;
end $$;
grant execute on all functions in schema tst to authenticated;
