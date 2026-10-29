-- 書き込みと計算の関数（RPC）。すべて security definer で、最初に権限を確かめる。
-- エラーは SQLSTATE の独自コード: KB401 未ログイン / KB403 権限なし / KB404 なし / KB409 競合・重複 / KB422 入力の誤り（hint に項目名）

create function public._err(code text, msg text, field text default null) returns void language plpgsql as $$
begin raise exception using errcode = code, message = msg, hint = coalesce(field, ''); end $$;

create function public._uid() returns uuid language plpgsql stable as $$
begin
  if auth.uid() is null then perform public._err('KB401', 'not_authenticated'); end if;
  return auth.uid();
end $$;

create function public._need(g uuid, r public.member_role) returns public.group_members
language plpgsql stable security definer set search_path = public as $$
declare m public.group_members;
begin
  perform public._uid();
  m := public.my_member(g);
  if m.id is null then perform public._err('KB403', 'not_a_member'); end if;
  if public.role_rank(m.role) < public.role_rank(r) then perform public._err('KB403', 'forbidden'); end if;
  return m;
end $$;

-- ---------- プロフィール ----------
create function public.handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, left(coalesce(nullif(btrim(new.raw_user_meta_data ->> 'display_name'), ''), split_part(coalesce(new.email, 'user'), '@', 1), 'user'), 30))
  on conflict (id) do nothing;
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create function public.update_profile(p_display_name text) returns public.profiles
language plpgsql security definer set search_path = public as $$
declare uid uuid := public._uid(); r public.profiles; n text := btrim(coalesce(p_display_name, ''));
begin
  if char_length(n) not between 1 and 30 then perform public._err('KB422', 'display_name_length', 'display_name'); end if;
  insert into public.profiles (id, display_name) values (uid, n)
  on conflict (id) do update set display_name = n, updated_at = now() returning * into r;
  update public.group_members set display_name = n, updated_at = now() where user_id = uid and status = 'active';
  return r;
end $$;

-- ---------- グループ ----------
create function public.create_group(p_name text) returns public.groups
language plpgsql security definer set search_path = public as $$
declare uid uuid := public._uid(); g public.groups; n text := btrim(coalesce(p_name, '')); dn text;
begin
  if char_length(n) not between 1 and 40 then perform public._err('KB422', 'group_name_length', 'name'); end if;
  if (select count(*) from public.group_members where user_id = uid and status = 'active') >= 20 then perform public._err('KB422', 'too_many_groups'); end if;
  select display_name into dn from public.profiles where id = uid;
  insert into public.groups (name, created_by) values (n, uid) returning * into g;
  insert into public.group_members (group_id, user_id, role, display_name) values (g.id, uid, 'owner', coalesce(dn, 'わたし'));
  insert into public.categories (group_id, kind, name, color, icon, sort)
  select g.id, 'expense', x.n, x.c, x.i, x.o from (values
    ('食費', '#e07a3f', '🍚', 1), ('日用品', '#3f8fd0', '🧺', 2), ('家賃', '#7a5cc7', '🏠', 3), ('水道光熱費', '#e0b23f', '💡', 4),
    ('通信費', '#3fb0b0', '📱', 5), ('交通費', '#5c7ac7', '🚃', 6), ('医療費', '#d04f6a', '🏥', 7), ('娯楽', '#c75cb5', '🎮', 8),
    ('趣味', '#8fb03f', '🎨', 9), ('交際費', '#e06f9a', '🍻', 10), ('教育費', '#4f9a6a', '📚', 11), ('保険', '#6b7f99', '🛡️', 12),
    ('税金', '#8a6b4f', '🧾', 13), ('その他', '#6b7280', '🏷️', 99)) as x(n, c, i, o);
  insert into public.categories (group_id, kind, name, color, icon, sort)
  select g.id, 'income', x.n, x.c, x.i, x.o from (values
    ('給与', '#2f8f5f', '💴', 1), ('副業', '#3f7fb0', '💼', 2), ('賞与', '#c79a2f', '🎁', 3), ('臨時収入', '#7a9a3f', '🎉', 4), ('その他', '#6b7280', '🏷️', 99)) as x(n, c, i, o);
  insert into public.payment_methods (group_id, name, sort)
  select g.id, x.n, x.o from (values ('現金', 1), ('クレジットカード', 2), ('電子マネー', 3), ('QR コード決済', 4), ('口座振替', 5), ('その他', 99)) as x(n, o);
  return g;
end $$;

create function public.rename_group(p_group uuid, p_name text) returns public.groups
language plpgsql security definer set search_path = public as $$
declare g public.groups; n text := btrim(coalesce(p_name, ''));
begin
  perform public._need(p_group, 'admin');
  if char_length(n) not between 1 and 40 then perform public._err('KB422', 'group_name_length', 'name'); end if;
  update public.groups set name = n, updated_at = now() where id = p_group returning * into g;
  return g;
end $$;

create function public.delete_group(p_group uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public._need(p_group, 'owner');
  update public.groups set deleted_at = now(), updated_at = now() where id = p_group;
  update public.group_members set status = 'removed', left_at = now(), updated_at = now() where group_id = p_group and status = 'active';
  update public.invitations set revoked_at = now() where group_id = p_group and revoked_at is null;
end $$;

-- ---------- 招待 ----------
create function public.create_invitation(p_group uuid, p_role public.member_role default 'member', p_expires_hours int default 168, p_max_uses int default 1)
returns jsonb language plpgsql security definer set search_path = public as $$
declare code text; alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; i int; inv public.invitations;
begin
  perform public._need(p_group, 'admin');
  if p_role not in ('member', 'viewer') then perform public._err('KB422', 'invite_role', 'role'); end if;
  if p_expires_hours not between 1 and 720 then perform public._err('KB422', 'invite_expiry', 'expires_hours'); end if;
  if p_max_uses not between 1 and 50 then perform public._err('KB422', 'invite_max_uses', 'max_uses'); end if;
  code := '';
  for i in 1..12 loop code := code || substr(alphabet, 1 + (get_byte(gen_random_bytes_safe(), 0) % 32), 1); end loop;
  insert into public.invitations (group_id, code_hash, code_hint, role, expires_at, max_uses, created_by)
  values (p_group, encode(sha256(convert_to(code, 'UTF8')), 'hex'), right(code, 2), p_role, now() + make_interval(hours => p_expires_hours), p_max_uses, auth.uid())
  returning * into inv;
  return jsonb_build_object('id', inv.id, 'code', code, 'expires_at', inv.expires_at, 'role', inv.role, 'max_uses', inv.max_uses);
end $$;

-- 暗号論的に安全な乱数 1 バイト（gen_random_uuid は暗号論的乱数から作られる）
create function public.gen_random_bytes_safe() returns bytea language sql volatile as $$
  select decode(replace(gen_random_uuid()::text, '-', ''), 'hex')
$$;

create function public.revoke_invitation(p_invitation uuid) returns void
language plpgsql security definer set search_path = public as $$
declare g uuid;
begin
  select group_id into g from public.invitations where id = p_invitation;
  if g is null then perform public._err('KB404', 'not_found'); end if;
  perform public._need(g, 'admin');
  update public.invitations set revoked_at = now() where id = p_invitation and revoked_at is null;
end $$;

-- 参加の承認。コードを知っていても、ログインしてこの関数で承認するまでは何も見えない。無効なコードは null を返す
create function public.accept_invitation(p_code text, p_display_name text default null) returns public.group_members
language plpgsql security definer set search_path = public as $$
declare uid uuid := public._uid(); inv public.invitations; m public.group_members; dn text; norm text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
begin
  if (select count(*) from public.invitation_attempts where user_id = uid and at > now() - interval '15 minutes') >= 10 then
    perform public._err('KB409', 'too_many_attempts');
  end if;
  select * into inv from public.invitations where code_hash = encode(sha256(convert_to(norm, 'UTF8')), 'hex') for update;
  if inv.id is null or inv.revoked_at is not null or inv.expires_at < now() or inv.used_count >= inv.max_uses
     or exists (select 1 from public.groups where id = inv.group_id and deleted_at is not null) then
    -- エラーにすると記録も取り消されるので、記録してから null を返す（アプリは null を「コードが無効」と表示する）
    insert into public.invitation_attempts (user_id) values (uid);
    return null;
  end if;
  dn := left(coalesce(nullif(btrim(p_display_name), ''), (select display_name from public.profiles where id = uid), 'メンバー'), 30);
  select * into m from public.group_members where group_id = inv.group_id and user_id = uid;
  if m.id is not null and m.status = 'active' then perform public._err('KB409', 'already_member'); end if;
  if m.id is not null then
    update public.group_members set status = 'active', role = inv.role, display_name = dn, left_at = null, joined_at = now(), updated_at = now() where id = m.id returning * into m;
  else
    insert into public.group_members (group_id, user_id, role, display_name) values (inv.group_id, uid, inv.role, dn) returning * into m;
  end if;
  update public.invitations set used_count = used_count + 1 where id = inv.id;
  return m;
end $$;

-- ---------- メンバー ----------
create function public.change_member_role(p_member uuid, p_role public.member_role) returns public.group_members
language plpgsql security definer set search_path = public as $$
declare t public.group_members; me public.group_members;
begin
  select * into t from public.group_members where id = p_member and status = 'active';
  if t.id is null then perform public._err('KB404', 'not_found'); end if;
  me := public._need(t.group_id, 'admin');
  if p_role = 'owner' then perform public._err('KB422', 'use_transfer_ownership', 'role'); end if;
  if t.role = 'owner' or t.id = me.id then perform public._err('KB403', 'forbidden'); end if;
  -- 管理者は member と viewer の間だけ変えられる。admin にする・admin を変えるのはオーナーだけ
  if me.role <> 'owner' and (t.role = 'admin' or p_role = 'admin') then perform public._err('KB403', 'forbidden'); end if;
  update public.group_members set role = p_role, updated_at = now() where id = p_member returning * into t;
  return t;
end $$;

create function public.remove_member(p_member uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t public.group_members; me public.group_members;
begin
  select * into t from public.group_members where id = p_member and status = 'active';
  if t.id is null then perform public._err('KB404', 'not_found'); end if;
  me := public._need(t.group_id, 'admin');
  if t.role = 'owner' or t.id = me.id then perform public._err('KB403', 'forbidden'); end if;
  if me.role <> 'owner' and t.role = 'admin' then perform public._err('KB403', 'forbidden'); end if;
  update public.group_members set status = 'removed', left_at = now(), updated_at = now() where id = p_member;
end $$;

create function public.leave_group(p_group uuid) returns void
language plpgsql security definer set search_path = public as $$
declare me public.group_members;
begin
  me := public._need(p_group, 'viewer');
  if me.role = 'owner' then perform public._err('KB422', 'owner_must_transfer'); end if;
  update public.group_members set status = 'left', left_at = now(), updated_at = now() where id = me.id;
end $$;

create function public.transfer_ownership(p_member uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t public.group_members; me public.group_members;
begin
  select * into t from public.group_members where id = p_member and status = 'active';
  if t.id is null or t.user_id is null then perform public._err('KB404', 'not_found'); end if;
  me := public._need(t.group_id, 'owner');
  if t.id = me.id then perform public._err('KB422', 'same_member'); end if;
  update public.group_members set role = 'admin', updated_at = now() where id = me.id;
  update public.group_members set role = 'owner', updated_at = now() where id = t.id;
end $$;

-- ---------- カテゴリ・支払い方法 ----------
create function public.save_category(p_group uuid, p_id uuid, p_kind public.txn_kind, p_name text, p_color text, p_icon text, p_sort int default 0, p_version int default null)
returns public.categories language plpgsql security definer set search_path = public as $$
declare c public.categories; n text := btrim(coalesce(p_name, ''));
begin
  perform public._need(p_group, 'admin');
  if char_length(n) not between 1 and 20 then perform public._err('KB422', 'category_name_length', 'name'); end if;
  if coalesce(p_color, '') !~ '^#[0-9a-f]{6}$' then perform public._err('KB422', 'color_format', 'color'); end if;
  if char_length(coalesce(p_icon, '')) not between 1 and 8 then perform public._err('KB422', 'icon_format', 'icon'); end if;
  if exists (select 1 from public.categories where group_id = p_group and kind = p_kind and name = n and archived_at is null and id is distinct from p_id) then
    perform public._err('KB409', 'category_name_taken', 'name');
  end if;
  if p_id is null then
    insert into public.categories (group_id, kind, name, color, icon, sort) values (p_group, p_kind, n, p_color, p_icon, coalesce(p_sort, 0)) returning * into c;
  else
    update public.categories set name = n, color = p_color, icon = p_icon, sort = coalesce(p_sort, sort), updated_at = now(), version = version + 1
    where id = p_id and group_id = p_group and archived_at is null and (p_version is null or version = p_version) returning * into c;
    if c.id is null then
      if exists (select 1 from public.categories where id = p_id and group_id = p_group) then perform public._err('KB409', 'conflict'); end if;
      perform public._err('KB404', 'not_found');
    end if;
  end if;
  return c;
end $$;

-- 使われていないカテゴリは消す。使われていればアーカイブ（取引はそのまま、新しい入力では選べない）
create function public.delete_category(p_category uuid) returns text
language plpgsql security definer set search_path = public as $$
declare c public.categories;
begin
  select * into c from public.categories where id = p_category;
  if c.id is null then perform public._err('KB404', 'not_found'); end if;
  perform public._need(c.group_id, 'admin');
  if exists (select 1 from public.transactions where category_id = c.id) or exists (select 1 from public.recurring_transactions where category_id = c.id)
     or exists (select 1 from public.budgets where category_id = c.id) then
    update public.categories set archived_at = now(), updated_at = now() where id = c.id;
    return 'archived';
  end if;
  delete from public.categories where id = c.id;
  return 'deleted';
end $$;

create function public.save_payment_method(p_group uuid, p_id uuid, p_name text, p_archived boolean default false) returns public.payment_methods
language plpgsql security definer set search_path = public as $$
declare r public.payment_methods; n text := btrim(coalesce(p_name, ''));
begin
  perform public._need(p_group, 'admin');
  if char_length(n) not between 1 and 20 then perform public._err('KB422', 'payment_name_length', 'name'); end if;
  if p_id is null then insert into public.payment_methods (group_id, name) values (p_group, n) returning * into r;
  else update public.payment_methods set name = n, archived_at = case when p_archived then coalesce(archived_at, now()) end, updated_at = now()
       where id = p_id and group_id = p_group returning * into r;
  end if;
  if r.id is null then perform public._err('KB404', 'not_found'); end if;
  return r;
end $$;

-- ---------- 分担の計算（両 OS の表示と同じ決まり。tests/vectors/splits.json） ----------
-- 均等割り: floor(金額 / 人数) を全員に。余りの円は、メンバーの並び（参加日時 → ID）の先頭から 1 円ずつ
create function public.equal_split(p_amount bigint, p_members uuid[]) returns table (member_id uuid, amount bigint)
language sql stable security definer set search_path = public as $$
  with ms as (
    select m.id, row_number() over (order by m.joined_at, m.id) as rn, count(*) over () as n
    from public.group_members m where m.id = any (p_members)
  )
  select id, (p_amount / n) + case when rn <= (p_amount % n) then 1 else 0 end from ms
$$;

-- 取引の検証と分担を作る（save_transaction と定期取引の生成で共通）
create function public._write_splits(t public.transactions, p_split jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare ids uuid[]; total bigint; cnt int;
begin
  delete from public.transaction_splits where transaction_id = t.id;
  if t.split_mode = 'none' then return; end if;
  if jsonb_typeof(p_split) <> 'array' or jsonb_array_length(p_split) = 0 then perform public._err('KB422', 'split_required', 'splits'); end if;
  if t.split_mode = 'equal' then
    select array_agg(distinct (x #>> '{}')::uuid) into ids from jsonb_array_elements(p_split) x;
    select count(*) into cnt from public.group_members where id = any (ids) and group_id = t.group_id and status = 'active';
    if cnt <> coalesce(array_length(ids, 1), 0) then perform public._err('KB422', 'split_member_invalid', 'splits'); end if;
    insert into public.transaction_splits (transaction_id, group_id, member_id, amount)
    select t.id, t.group_id, s.member_id, s.amount from public.equal_split(t.amount, ids) s;
  else
    if exists (select 1 from jsonb_array_elements(p_split) x where jsonb_typeof(x -> 'amount') <> 'number' or (x ->> 'amount')::numeric <> floor((x ->> 'amount')::numeric) or (x ->> 'amount')::bigint < 0) then
      perform public._err('KB422', 'split_amount_invalid', 'splits');
    end if;
    select count(*) into cnt from jsonb_array_elements(p_split) x
      join public.group_members m on m.id = (x ->> 'member_id')::uuid and m.group_id = t.group_id and m.status = 'active';
    if cnt <> jsonb_array_length(p_split) or (select count(distinct x ->> 'member_id') from jsonb_array_elements(p_split) x) <> cnt then
      perform public._err('KB422', 'split_member_invalid', 'splits');
    end if;
    select sum((x ->> 'amount')::bigint) into total from jsonb_array_elements(p_split) x;
    if total <> t.amount then perform public._err('KB422', 'split_sum_mismatch', 'splits'); end if;
    insert into public.transaction_splits (transaction_id, group_id, member_id, amount)
    select t.id, t.group_id, (x ->> 'member_id')::uuid, (x ->> 'amount')::bigint from jsonb_array_elements(p_split) x;
  end if;
end $$;

-- ---------- 取引の登録・更新 ----------
-- p: { id?, version?, client_request_id, kind, amount, occurred_on, category_id, payer_member_id, payment_method_id?, memo?, visibility?, split_mode?, splits? }
-- 同じ client_request_id がもう登録されていれば、その行をそのまま返す（二重送信でも 1 件）
create function public.save_transaction(p_group uuid, p jsonb) returns public.transactions
language plpgsql security definer set search_path = public as $$
declare me public.group_members; t public.transactions; old public.transactions;
  v_id uuid := nullif(p ->> 'id', '')::uuid; v_amount numeric; v_date date; v_kind public.txn_kind; v_vis public.txn_visibility; v_split public.split_mode; v_memo text;
begin
  me := public._need(p_group, 'member');
  begin
    v_kind := (p ->> 'kind')::public.txn_kind;
    v_vis := coalesce(p ->> 'visibility', 'group')::public.txn_visibility;
    v_split := coalesce(p ->> 'split_mode', 'none')::public.split_mode;
  exception when others then perform public._err('KB422', 'enum_invalid', 'kind');
  end;
  if jsonb_typeof(p -> 'amount') <> 'number' then perform public._err('KB422', 'amount_invalid', 'amount'); end if;
  v_amount := (p ->> 'amount')::numeric;
  if v_amount <> floor(v_amount) or v_amount < 1 or v_amount > 999999999 then perform public._err('KB422', 'amount_invalid', 'amount'); end if;
  begin v_date := (p ->> 'occurred_on')::date; exception when others then perform public._err('KB422', 'date_invalid', 'occurred_on'); end;
  if v_date is null or v_date < date '2000-01-01' or v_date > public.today_jst() + 366 then perform public._err('KB422', 'date_invalid', 'occurred_on'); end if;
  v_memo := coalesce(p ->> 'memo', '');
  if char_length(v_memo) > 500 then perform public._err('KB422', 'memo_too_long', 'memo'); end if;
  if v_kind = 'income' and v_split <> 'none' then perform public._err('KB422', 'split_income', 'split_mode'); end if;
  if v_vis = 'private' and v_split <> 'none' then perform public._err('KB422', 'split_private', 'split_mode'); end if;
  if not exists (select 1 from public.categories where id = (p ->> 'category_id')::uuid and group_id = p_group and kind = v_kind and (archived_at is null or v_id is not null)) then
    perform public._err('KB422', 'category_invalid', 'category_id');
  end if;
  if not exists (select 1 from public.group_members where id = (p ->> 'payer_member_id')::uuid and group_id = p_group and (status = 'active' or v_id is not null)) then
    perform public._err('KB422', 'payer_invalid', 'payer_member_id');
  end if;
  if nullif(p ->> 'payment_method_id', '') is not null and not exists (select 1 from public.payment_methods where id = (p ->> 'payment_method_id')::uuid and group_id = p_group) then
    perform public._err('KB422', 'payment_method_invalid', 'payment_method_id');
  end if;

  if v_id is null then
    if nullif(p ->> 'client_request_id', '') is null then perform public._err('KB422', 'client_request_id_required', 'client_request_id'); end if;
    select * into t from public.transactions where group_id = p_group and client_request_id = (p ->> 'client_request_id')::uuid;
    if t.id is not null then return t; end if;   -- 二重送信
    insert into public.transactions (group_id, kind, amount, occurred_on, category_id, payer_member_id, payment_method_id, memo, visibility, split_mode, created_by, created_by_member, updated_by, client_request_id)
    values (p_group, v_kind, v_amount::bigint, v_date, (p ->> 'category_id')::uuid, (p ->> 'payer_member_id')::uuid, nullif(p ->> 'payment_method_id', '')::uuid, v_memo, v_vis, v_split, auth.uid(), me.id, auth.uid(), (p ->> 'client_request_id')::uuid)
    returning * into t;
  else
    select * into old from public.transactions where id = v_id and group_id = p_group and status = 'active' for update;
    if old.id is null then perform public._err('KB404', 'not_found'); end if;
    if old.visibility = 'private' and old.created_by is distinct from auth.uid() then perform public._err('KB404', 'not_found'); end if;
    if me.role = 'member' and old.created_by is distinct from auth.uid() then perform public._err('KB403', 'forbidden'); end if;
    if (p ->> 'version')::int is distinct from old.version then perform public._err('KB409', 'conflict'); end if;
    update public.transactions set kind = v_kind, amount = v_amount::bigint, occurred_on = v_date, category_id = (p ->> 'category_id')::uuid,
      payer_member_id = (p ->> 'payer_member_id')::uuid, payment_method_id = nullif(p ->> 'payment_method_id', '')::uuid, memo = v_memo,
      visibility = v_vis, split_mode = v_split, updated_by = auth.uid(), updated_at = now(), version = version + 1
    where id = v_id returning * into t;
  end if;
  perform public._write_splits(t, coalesce(p -> 'splits', '[]'::jsonb));
  return t;
end $$;

create function public.delete_transaction(p_id uuid, p_version int) returns void
language plpgsql security definer set search_path = public as $$
declare t public.transactions; me public.group_members;
begin
  select * into t from public.transactions where id = p_id and status = 'active' for update;
  if t.id is null then perform public._err('KB404', 'not_found'); end if;
  me := public._need(t.group_id, 'member');
  if t.visibility = 'private' and t.created_by is distinct from auth.uid() then perform public._err('KB404', 'not_found'); end if;
  if me.role = 'member' and t.created_by is distinct from auth.uid() then perform public._err('KB403', 'forbidden'); end if;
  if p_version is distinct from t.version then perform public._err('KB409', 'conflict'); end if;
  update public.transactions set status = 'deleted', updated_by = auth.uid(), updated_at = now(), version = version + 1 where id = p_id;
end $$;

-- 似た取引（同じ日・同じ金額・同じカテゴリ、10 分以内に登録）があるか。登録前の確認に使う
create function public.similar_transactions(p_group uuid, p_amount bigint, p_occurred_on date, p_category uuid) returns setof public.transactions
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform public._need(p_group, 'viewer');
  return query select * from public.transactions t where t.group_id = p_group and t.status = 'active' and t.amount = p_amount and t.occurred_on = p_occurred_on
    and t.category_id = p_category and t.created_at > now() - interval '10 minutes' and (t.visibility = 'group' or t.created_by = auth.uid());
end $$;

-- ---------- 立替・負担・精算 ----------
-- 差額 = 立替（分担のある支出で自分が払った額）− 負担（自分の分担）+ 払った精算 − 受け取った精算（確認済みだけ）
-- プラスなら受け取る側、マイナスなら払う側
create function public.group_balances(p_group uuid) returns table (member_id uuid, display_name text, status public.member_status, paid bigint, burden bigint, settled_out bigint, settled_in bigint, net bigint)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform public._need(p_group, 'viewer');
  return query
  with p as (select payer_member_id m, sum(amount)::bigint v from public.transactions where group_id = p_group and status = 'active' and kind = 'expense' and split_mode <> 'none' group by 1),
       b as (select s.member_id m, sum(s.amount)::bigint v from public.transaction_splits s join public.transactions t on t.id = s.transaction_id
             where t.group_id = p_group and t.status = 'active' group by 1),
       so as (select from_member m, sum(amount)::bigint v from public.settlements where group_id = p_group and status = 'confirmed' group by 1),
       si as (select to_member m, sum(amount)::bigint v from public.settlements where group_id = p_group and status = 'confirmed' group by 1)
  select m.id, m.display_name, m.status, coalesce(p.v, 0), coalesce(b.v, 0), coalesce(so.v, 0), coalesce(si.v, 0),
         coalesce(p.v, 0) - coalesce(b.v, 0) + coalesce(so.v, 0) - coalesce(si.v, 0)
  from public.group_members m left join p on p.m = m.id left join b on b.m = m.id left join so on so.m = m.id left join si on si.m = m.id
  where m.group_id = p_group and (m.status = 'active' or coalesce(p.v, 0) + coalesce(b.v, 0) + coalesce(so.v, 0) + coalesce(si.v, 0) > 0)
  order by m.joined_at, m.id;
end $$;

-- 精算の提案: 払う側（差額の小さい順）と受け取る側（大きい順）を順に組み合わせる。保留中の精算を差し引いてから計算
create function public.settlement_suggestions(p_group uuid) returns table (from_member uuid, to_member uuid, amount bigint)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare ids uuid[]; v bigint[]; n int; i int; di int; ci int; x bigint;
begin
  perform public._need(p_group, 'viewer');
  select array_agg(b.member_id order by b.ord), array_agg(b.v order by b.ord) into ids, v from (
    select g.member_id, row_number() over () ord, g.net
      + coalesce((select sum(s.amount) from public.settlements s where s.group_id = p_group and s.status = 'pending' and s.from_member = g.member_id), 0)
      - coalesce((select sum(s.amount) from public.settlements s where s.group_id = p_group and s.status = 'pending' and s.to_member = g.member_id), 0) as v
    from public.group_balances(p_group) g) b;
  n := coalesce(array_length(ids, 1), 0);
  loop
    di := null; ci := null;
    for i in 1..n loop
      if v[i] < 0 and (di is null or v[i] < v[di]) then di := i; end if;
      if v[i] > 0 and (ci is null or v[i] > v[ci]) then ci := i; end if;
    end loop;
    exit when di is null or ci is null;
    x := least(-v[di], v[ci]);
    from_member := ids[di]; to_member := ids[ci]; amount := x; return next;
    v[di] := v[di] + x; v[ci] := v[ci] - x;
  end loop;
end $$;
-- 精算の記録（払う人か管理者が記録）。保留中のものを含めて、払う側の未精算額と受け取る側の未回収額をこえないこと（二重精算の防止）
create function public.record_settlement(p_group uuid, p_from uuid, p_to uuid, p_amount bigint, p_note text, p_client_request_id uuid) returns public.settlements
language plpgsql security definer set search_path = public as $$
declare me public.group_members; s public.settlements; owe bigint; due bigint;
begin
  me := public._need(p_group, 'member');
  if p_client_request_id is null then perform public._err('KB422', 'client_request_id_required', 'client_request_id'); end if;
  select * into s from public.settlements where group_id = p_group and client_request_id = p_client_request_id;
  if s.id is not null then return s; end if;
  if p_amount is null or p_amount not between 1 and 999999999 then perform public._err('KB422', 'amount_invalid', 'amount'); end if;
  if char_length(coalesce(p_note, '')) > 200 then perform public._err('KB422', 'note_too_long', 'note'); end if;
  if p_from = p_to then perform public._err('KB422', 'same_member', 'to_member'); end if;
  if me.id <> p_from and public.role_rank(me.role) < public.role_rank('admin') then perform public._err('KB403', 'forbidden'); end if;
  perform 1 from public.groups where id = p_group for update;   -- 同じグループの精算を順番に処理する
  select -(b.net) - coalesce((select sum(amount) from public.settlements where group_id = p_group and status = 'pending' and from_member = p_from), 0) into owe
    from public.group_balances(p_group) b where b.member_id = p_from;
  select b.net - coalesce((select sum(amount) from public.settlements where group_id = p_group and status = 'pending' and to_member = p_to), 0) into due
    from public.group_balances(p_group) b where b.member_id = p_to;
  if owe is null or due is null then perform public._err('KB422', 'member_invalid', 'from_member'); end if;
  if p_amount > owe or p_amount > due then perform public._err('KB422', 'settlement_exceeds_balance', 'amount'); end if;
  insert into public.settlements (group_id, from_member, to_member, amount, note, created_by, client_request_id)
  values (p_group, p_from, p_to, p_amount, coalesce(p_note, ''), auth.uid(), p_client_request_id) returning * into s;
  return s;
end $$;

-- 受け取った人（か管理者）が確認する。pending のときだけ。2 回は確認できない
create function public.confirm_settlement(p_id uuid) returns public.settlements
language plpgsql security definer set search_path = public as $$
declare s public.settlements; me public.group_members;
begin
  select * into s from public.settlements where id = p_id for update;
  if s.id is null then perform public._err('KB404', 'not_found'); end if;
  me := public._need(s.group_id, 'member');
  if me.id <> s.to_member and public.role_rank(me.role) < public.role_rank('admin') then perform public._err('KB403', 'forbidden'); end if;
  if s.status <> 'pending' then perform public._err('KB409', 'settlement_not_pending'); end if;
  update public.settlements set status = 'confirmed', confirmed_at = now(), confirmed_by = auth.uid(), version = version + 1 where id = p_id returning * into s;
  return s;
end $$;

create function public.cancel_settlement(p_id uuid) returns public.settlements
language plpgsql security definer set search_path = public as $$
declare s public.settlements; me public.group_members;
begin
  select * into s from public.settlements where id = p_id for update;
  if s.id is null then perform public._err('KB404', 'not_found'); end if;
  me := public._need(s.group_id, 'member');
  if me.id not in (s.from_member, s.to_member) and public.role_rank(me.role) < public.role_rank('admin') then perform public._err('KB403', 'forbidden'); end if;
  if s.status <> 'pending' then perform public._err('KB409', 'settlement_not_pending'); end if;
  update public.settlements set status = 'cancelled', cancelled_at = now(), version = version + 1 where id = p_id returning * into s;
  return s;
end $$;

-- ---------- 予算 ----------
create function public.save_budget(p_group uuid, p_scope public.budget_scope, p_category uuid, p_member uuid, p_start_month date, p_amount bigint, p_end_month date default null)
returns public.budgets language plpgsql security definer set search_path = public as $$
declare r public.budgets; sm date := date_trunc('month', p_start_month)::date; em date := date_trunc('month', p_end_month)::date;
begin
  perform public._need(p_group, 'admin');
  if p_amount is null or p_amount not between 1 and 999999999 then perform public._err('KB422', 'amount_invalid', 'amount'); end if;
  if p_category is not null and not exists (select 1 from public.categories where id = p_category and group_id = p_group and kind = 'expense') then
    perform public._err('KB422', 'category_invalid', 'category_id');
  end if;
  if (p_scope = 'personal') <> (p_member is not null) then perform public._err('KB422', 'budget_member', 'member_id'); end if;
  insert into public.budgets (group_id, scope, category_id, member_id, start_month, end_month, amount, created_by)
  values (p_group, p_scope, p_category, p_member, sm, em, p_amount, auth.uid())
  on conflict (group_id, scope, coalesce(category_id, '00000000-0000-0000-0000-000000000000'::uuid), coalesce(member_id, '00000000-0000-0000-0000-000000000000'::uuid), start_month)
  do update set amount = excluded.amount, end_month = excluded.end_month, updated_at = now(), version = budgets.version + 1
  returning * into r;
  return r;
end $$;

create function public.delete_budget(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare g uuid;
begin
  select group_id into g from public.budgets where id = p_id;
  if g is null then perform public._err('KB404', 'not_found'); end if;
  perform public._need(g, 'admin');
  delete from public.budgets where id = p_id;
end $$;

-- その月の予算の状態。対象: その暦月の有効な支出のうち、公開範囲「グループ」のもの。
--   グループの予算: 支出の金額（カテゴリの予算はそのカテゴリだけ）
--   個人の予算: その人の負担（分担があれば分担額、なければ自分が払った支出）
create function public.budget_status(p_group uuid, p_month date)
returns table (budget_id uuid, scope public.budget_scope, category_id uuid, member_id uuid, amount bigint, spent bigint, remaining bigint, ratio numeric, over boolean)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare m0 date := date_trunc('month', p_month)::date; m1 date := (date_trunc('month', p_month) + interval '1 month')::date;
begin
  perform public._need(p_group, 'viewer');
  return query
  with eff as (
    select distinct on (b.scope, b.category_id, b.member_id) b.* from public.budgets b
    where b.group_id = p_group and b.start_month <= m0 and (b.end_month is null or b.end_month >= m0)
    order by b.scope, b.category_id, b.member_id, b.start_month desc
  ), tx as (
    select * from public.transactions t where t.group_id = p_group and t.status = 'active' and t.kind = 'expense' and t.visibility = 'group' and t.occurred_on >= m0 and t.occurred_on < m1
  ), burden as (
    select tx.category_id, s.member_id, s.amount from tx join public.transaction_splits s on s.transaction_id = tx.id where tx.split_mode <> 'none'
    union all select tx.category_id, tx.payer_member_id, tx.amount from tx where tx.split_mode = 'none'
  )
  select e.id, e.scope, e.category_id, e.member_id, e.amount, x.spent, e.amount - x.spent, round(x.spent::numeric / e.amount, 4), x.spent > e.amount
  from eff e cross join lateral (
    select coalesce(case when e.scope = 'group' then (select sum(tx.amount) from tx where e.category_id is null or tx.category_id = e.category_id)
                         else (select sum(bu.amount) from burden bu where bu.member_id = e.member_id and (e.category_id is null or bu.category_id = e.category_id)) end, 0)::bigint as spent
  ) x
  order by e.scope, e.category_id nulls first;
end $$;

-- ---------- 集計 ----------
-- 月のまとめ（公開範囲「グループ」の有効な取引）。前月も返す
create function public.month_summary(p_group uuid, p_month date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m0 date := date_trunc('month', p_month)::date; r jsonb;
begin
  perform public._need(p_group, 'viewer');
  with t as (select * from public.transactions where group_id = p_group and status = 'active' and visibility = 'group'),
  cur as (select * from t where occurred_on >= m0 and occurred_on < m0 + interval '1 month'),
  prev as (select * from t where occurred_on >= m0 - interval '1 month' and occurred_on < m0)
  select jsonb_build_object(
    'month', m0,
    'income', coalesce((select sum(amount) from cur where kind = 'income'), 0),
    'expense', coalesce((select sum(amount) from cur where kind = 'expense'), 0),
    'prev_income', coalesce((select sum(amount) from prev where kind = 'income'), 0),
    'prev_expense', coalesce((select sum(amount) from prev where kind = 'expense'), 0),
    'by_category', coalesce((select jsonb_agg(jsonb_build_object('category_id', category_id, 'amount', s) order by s desc) from (select category_id, sum(amount) s from cur where kind = 'expense' group by 1) x), '[]'::jsonb),
    'by_payer', coalesce((select jsonb_agg(jsonb_build_object('member_id', payer_member_id, 'amount', s) order by s desc) from (select payer_member_id, sum(amount) s from cur where kind = 'expense' group by 1) x), '[]'::jsonb),
    'by_burden', coalesce((select jsonb_agg(jsonb_build_object('member_id', m, 'amount', s) order by s desc) from (
        select m, sum(a) s from (select sp.member_id m, sp.amount a from cur join public.transaction_splits sp on sp.transaction_id = cur.id where cur.split_mode <> 'none'
                                 union all select payer_member_id, amount from cur where kind = 'expense' and split_mode = 'none') u group by 1) x), '[]'::jsonb)
  ) into r;
  r := r || jsonb_build_object('balance', (r ->> 'income')::bigint - (r ->> 'expense')::bigint);
  return r;
end $$;

-- n か月の推移
create function public.monthly_series(p_group uuid, p_end_month date, p_months int default 12) returns table (month date, income bigint, expense bigint)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare e date := date_trunc('month', p_end_month)::date;
begin
  perform public._need(p_group, 'viewer');
  if p_months not between 1 and 36 then perform public._err('KB422', 'months_range', 'months'); end if;
  return query
  select ms::date, coalesce(sum(t.amount) filter (where t.kind = 'income'), 0)::bigint, coalesce(sum(t.amount) filter (where t.kind = 'expense'), 0)::bigint
  from generate_series(e - make_interval(months => p_months - 1), e, interval '1 month') ms
  left join public.transactions t on t.group_id = p_group and t.status = 'active' and t.visibility = 'group' and t.occurred_on >= ms and t.occurred_on < ms + interval '1 month'
  group by ms order by ms;
end $$;

-- ---------- 定期取引 ----------
-- 次の日付（周期の次）。毎月の 29〜31 日は、その月にない日なら月末にする
create function public.next_occurrence(r public.recurring_transactions, d date) returns date
language plpgsql immutable as $$
declare m date; last int;
begin
  if r.freq = 'weekly' then return d + 7; end if;
  if r.freq = 'monthly' then m := (date_trunc('month', d) + interval '1 month')::date;
  else m := make_date(extract(year from d)::int + 1, r.month_of_year, 1); end if;
  last := extract(day from (m + interval '1 month - 1 day'))::int;
  return m + (least(r.day_of_month, last) - 1);
end $$;

-- 最初の日付（start_on 以降で、周期に合う最初の日）
create function public.first_occurrence(r public.recurring_transactions) returns date
language plpgsql immutable as $$
declare d date := r.start_on; last int; c date;
begin
  if r.freq = 'weekly' then return d + ((r.weekday - extract(dow from d)::int + 7) % 7); end if;
  if r.freq = 'monthly' then
    last := extract(day from (date_trunc('month', d) + interval '1 month - 1 day'))::int;
    c := date_trunc('month', d)::date + (least(r.day_of_month, last) - 1);
    return case when c >= d then c else public.next_occurrence(r, c) end;
  end if;
  c := make_date(extract(year from d)::int, r.month_of_year, 1);
  last := extract(day from (c + interval '1 month - 1 day'))::int;
  c := c + (least(r.day_of_month, last) - 1);
  return case when c >= d then c else public.next_occurrence(r, c) end;
end $$;

create function public.save_recurring(p_group uuid, p jsonb) returns public.recurring_transactions
language plpgsql security definer set search_path = public as $$
declare r public.recurring_transactions; v_id uuid := nullif(p ->> 'id', '')::uuid; amt numeric;
begin
  perform public._need(p_group, 'admin');
  if jsonb_typeof(p -> 'amount') <> 'number' then perform public._err('KB422', 'amount_invalid', 'amount'); end if;
  amt := (p ->> 'amount')::numeric;
  if amt <> floor(amt) or amt not between 1 and 999999999 then perform public._err('KB422', 'amount_invalid', 'amount'); end if;
  r.group_id := p_group; r.kind := (p ->> 'kind')::public.txn_kind; r.amount := amt::bigint;
  r.category_id := (p ->> 'category_id')::uuid; r.payer_member_id := (p ->> 'payer_member_id')::uuid; r.payment_method_id := nullif(p ->> 'payment_method_id', '')::uuid;
  r.memo := coalesce(p ->> 'memo', ''); r.visibility := coalesce(p ->> 'visibility', 'group')::public.txn_visibility;
  r.split_mode := coalesce(p ->> 'split_mode', 'none')::public.split_mode; r.split_spec := coalesce(p -> 'splits', '[]'::jsonb);
  r.freq := (p ->> 'freq')::public.recur_freq; r.day_of_month := (p ->> 'day_of_month')::int; r.weekday := (p ->> 'weekday')::int; r.month_of_year := (p ->> 'month_of_year')::int;
  r.start_on := (p ->> 'start_on')::date; r.end_on := nullif(p ->> 'end_on', '')::date; r.active := coalesce((p ->> 'active')::boolean, true);
  if char_length(r.memo) > 500 then perform public._err('KB422', 'memo_too_long', 'memo'); end if;
  if r.kind = 'income' and r.split_mode <> 'none' then perform public._err('KB422', 'split_income', 'split_mode'); end if;
  if r.start_on is null or r.start_on < date '2000-01-01' then perform public._err('KB422', 'date_invalid', 'start_on'); end if;
  r.next_run_on := public.first_occurrence(r);
  if v_id is null then
    insert into public.recurring_transactions (group_id, kind, amount, category_id, payer_member_id, payment_method_id, memo, visibility, split_mode, split_spec, freq, day_of_month, weekday, month_of_year, start_on, end_on, next_run_on, active, created_by)
    values (r.group_id, r.kind, r.amount, r.category_id, r.payer_member_id, r.payment_method_id, r.memo, r.visibility, r.split_mode, r.split_spec, r.freq, r.day_of_month, r.weekday, r.month_of_year, r.start_on, r.end_on, r.next_run_on, r.active, auth.uid())
    returning * into r;
  else
    -- 開始日・周期を変えたら次の日付を計算し直す（作った取引は消さない。同じ日付は一意制約で二重に作らない）
    update public.recurring_transactions x set kind = r.kind, amount = r.amount, category_id = r.category_id, payer_member_id = r.payer_member_id, payment_method_id = r.payment_method_id,
      memo = r.memo, visibility = r.visibility, split_mode = r.split_mode, split_spec = r.split_spec, freq = r.freq, day_of_month = r.day_of_month, weekday = r.weekday,
      month_of_year = r.month_of_year, start_on = r.start_on, end_on = r.end_on, active = r.active,
      next_run_on = greatest(r.next_run_on, coalesce((select max(occurrence_date) from public.transactions where recurring_id = v_id), r.next_run_on - 1) + 1),
      updated_at = now(), version = x.version + 1
    where x.id = v_id and x.group_id = p_group and x.version = (p ->> 'version')::int returning * into r;
    if r.id is null then
      if exists (select 1 from public.recurring_transactions where id = v_id and group_id = p_group) then perform public._err('KB409', 'conflict'); end if;
      perform public._err('KB404', 'not_found');
    end if;
    if r.next_run_on <> public.first_occurrence(r) then
      -- 計算し直した日が周期に合っていなければ、周期に合う次の日へ
      r.start_on := r.next_run_on; r.next_run_on := public.first_occurrence(r);
      update public.recurring_transactions set next_run_on = r.next_run_on where id = r.id returning * into r;
    end if;
  end if;
  return r;
end $$;

create function public.delete_recurring(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare g uuid;
begin
  select group_id into g from public.recurring_transactions where id = p_id;
  if g is null then perform public._err('KB404', 'not_found'); end if;
  perform public._need(g, 'admin');
  delete from public.recurring_transactions where id = p_id;   -- 作った取引は残る（recurring_id は null になる）
end $$;

-- 期日の来た定期取引から取引を作る。何度呼んでも同じ（(recurring_id, occurrence_date) の一意制約と行ロック）
create function public.generate_due_recurring(p_group uuid) returns int
language plpgsql security definer set search_path = public as $$
declare r public.recurring_transactions; t public.transactions; n int := 0; today date := public.today_jst();
begin
  perform public._need(p_group, 'member');
  for r in select * from public.recurring_transactions where group_id = p_group and active and next_run_on <= today order by id for update skip locked loop
    while r.next_run_on <= today and (r.end_on is null or r.next_run_on <= r.end_on) loop
      insert into public.transactions (group_id, kind, amount, occurred_on, category_id, payer_member_id, payment_method_id, memo, visibility, split_mode, created_by, updated_by, client_request_id, recurring_id, occurrence_date)
      values (r.group_id, r.kind, r.amount, r.next_run_on, r.category_id, r.payer_member_id, r.payment_method_id, r.memo, r.visibility, r.split_mode, r.created_by, r.created_by, gen_random_uuid(), r.id, r.next_run_on)
      on conflict (recurring_id, occurrence_date) do nothing
      returning * into t;
      if t.id is not null then
        perform public._write_splits(t, r.split_spec);
        n := n + 1;
      end if;
      t := null;
      r.next_run_on := public.next_occurrence(r, r.next_run_on);
    end loop;
    update public.recurring_transactions set next_run_on = r.next_run_on, active = (r.end_on is null or r.next_run_on <= r.end_on), updated_at = now() where id = r.id;
  end loop;
  return n;
end $$;

-- ---------- 退会の準備（Edge Function が service_role で呼ぶ。本人の確認は Edge Function で JWT から） ----------
-- オーナーのまま他のメンバーがいるグループがあれば止める。メンバー行は名前を消して残す（共有の記録を壊さない）
create function public.prepare_account_deletion(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare blocking jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object('group_id', g.id, 'name', g.name)), '[]'::jsonb) into blocking
  from public.group_members m join public.groups g on g.id = m.group_id and g.deleted_at is null
  where m.user_id = p_user and m.status = 'active' and m.role = 'owner'
    and exists (select 1 from public.group_members o where o.group_id = m.group_id and o.status = 'active' and o.id <> m.id);
  if jsonb_array_length(blocking) > 0 then return jsonb_build_object('ok', false, 'owner_of', blocking); end if;
  -- 自分しかいないグループは消す
  update public.groups set deleted_at = now() where id in (select group_id from public.group_members where user_id = p_user and status = 'active' and role = 'owner');
  update public.group_members set display_name = '退会したメンバー', status = case when status = 'active' then 'left' else status end,
    left_at = coalesce(left_at, now()), user_id = null, updated_at = now() where user_id = p_user;
  delete from public.transactions where created_by = p_user and visibility = 'private';
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function public.prepare_account_deletion(uuid) from authenticated;

-- ---------- 実行権限 ----------
revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.update_profile(text), public.create_group(text), public.rename_group(uuid, text), public.delete_group(uuid),
  public.create_invitation(uuid, public.member_role, int, int), public.revoke_invitation(uuid), public.accept_invitation(text, text),
  public.change_member_role(uuid, public.member_role), public.remove_member(uuid), public.leave_group(uuid), public.transfer_ownership(uuid),
  public.save_category(uuid, uuid, public.txn_kind, text, text, text, int, int), public.delete_category(uuid), public.save_payment_method(uuid, uuid, text, boolean),
  public.save_transaction(uuid, jsonb), public.delete_transaction(uuid, int), public.similar_transactions(uuid, bigint, date, uuid),
  public.group_balances(uuid), public.settlement_suggestions(uuid), public.record_settlement(uuid, uuid, uuid, bigint, text, uuid),
  public.confirm_settlement(uuid), public.cancel_settlement(uuid),
  public.save_budget(uuid, public.budget_scope, uuid, uuid, date, bigint, date), public.delete_budget(uuid), public.budget_status(uuid, date),
  public.month_summary(uuid, date), public.monthly_series(uuid, date, int),
  public.save_recurring(uuid, jsonb), public.delete_recurring(uuid), public.generate_due_recurring(uuid),
  public.role_rank(public.member_role), public.today_jst(), public.has_role(uuid, public.member_role), public.my_member(uuid)
to authenticated;
grant execute on function public.prepare_account_deletion(uuid) to service_role;
