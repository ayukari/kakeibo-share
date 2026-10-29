-- 共有家計簿: テーブル・制約・インデックス・読み取りの RLS
-- 決まり（docs/spec-common.md）:
--   金額は日本円の整数（bigint、円）。通貨は JPY 固定。
--   取引の日付は date（日本時間の暦日）。記録の日時は timestamptz（UTC で保存）。
--   書き込みはすべて関数（RPC）を通す。テーブルへの直接の INSERT / UPDATE / DELETE はアプリのロールに許さない。
--   読み取りは RLS で「そのグループの有効なメンバー」だけ。

-- ---------- 型 ----------
create type public.member_role as enum ('owner', 'admin', 'member', 'viewer');
create type public.member_status as enum ('active', 'left', 'removed');
create type public.txn_kind as enum ('income', 'expense');
create type public.txn_status as enum ('active', 'deleted');
create type public.txn_visibility as enum ('group', 'private');
create type public.split_mode as enum ('none', 'equal', 'custom');
create type public.settlement_status as enum ('pending', 'confirmed', 'cancelled');
create type public.recur_freq as enum ('weekly', 'monthly', 'yearly');
create type public.budget_scope as enum ('group', 'personal');

-- 役割の強さ（owner が最も強い）
create function public.role_rank(r public.member_role) returns int language sql immutable as $$
  select case r when 'owner' then 4 when 'admin' then 3 when 'member' then 2 else 1 end
$$;

-- 日本時間の今日
create function public.today_jst() returns date language sql stable as $$
  select (now() at time zone 'Asia/Tokyo')::date
$$;

-- ---------- プロフィール ----------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 30),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------- グループ ----------
create table public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 40),
  currency text not null default 'JPY' check (currency = 'JPY'),
  timezone text not null default 'Asia/Tokyo' check (timezone = 'Asia/Tokyo'),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.group_members (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid references auth.users (id) on delete set null,   -- 退会したら null（取引の記録は「退会したメンバー」として残る）
  role public.member_role not null default 'member',
  status public.member_status not null default 'active',
  display_name text not null check (char_length(display_name) between 1 and 30),
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, group_id),            -- ほかの表から (member_id, group_id) で参照し、別グループのメンバーを指せないようにする
  unique (group_id, user_id)
);
create index group_members_user_idx on public.group_members (user_id) where status = 'active';
-- オーナーは 1 グループに 1 人だけ
create unique index group_members_one_owner on public.group_members (group_id) where role = 'owner' and status = 'active';

create table public.invitations (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  code_hash text not null unique,                     -- コードそのものは保存しない（sha256 の 16 進）
  code_hint text not null,                            -- 一覧で見分ける用の末尾 2 文字
  role public.member_role not null default 'member' check (role in ('member', 'viewer')),
  expires_at timestamptz not null,
  max_uses int not null default 1 check (max_uses between 1 and 50),
  used_count int not null default 0 check (used_count >= 0),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  check (used_count <= max_uses)
);
create index invitations_group_idx on public.invitations (group_id);

-- 招待コードの総当たりを防ぐための記録（失敗した試行）
create table public.invitation_attempts (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  at timestamptz not null default now()
);
create index invitation_attempts_user_idx on public.invitation_attempts (user_id, at);

-- ---------- カテゴリ・支払い方法 ----------
create table public.categories (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  kind public.txn_kind not null,
  name text not null check (char_length(btrim(name)) between 1 and 20),
  color text not null default '#6b7280' check (color ~ '^#[0-9a-f]{6}$'),
  icon text not null default '🏷️' check (char_length(icon) between 1 and 8),
  sort int not null default 0,
  archived_at timestamptz,                            -- 使われたカテゴリは消さずにアーカイブ（取引の参照を壊さない）
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version int not null default 1,
  unique (id, group_id),
  unique (id, group_id, kind)
);
create unique index categories_name_uniq on public.categories (group_id, kind, name) where archived_at is null;

create table public.payment_methods (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 20),
  sort int not null default 0,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, group_id)
);
create unique index payment_methods_name_uniq on public.payment_methods (group_id, name) where archived_at is null;

-- ---------- 定期取引（取引より先に作る。取引から参照する） ----------
create table public.recurring_transactions (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  kind public.txn_kind not null,
  amount bigint not null check (amount between 1 and 999999999),
  category_id uuid not null,
  payer_member_id uuid not null,
  payment_method_id uuid,
  memo text not null default '' check (char_length(memo) <= 500),
  visibility public.txn_visibility not null default 'group',
  split_mode public.split_mode not null default 'none',
  split_spec jsonb not null default '[]'::jsonb,      -- equal: [member_id, ...] / custom: [{member_id, amount}, ...]
  freq public.recur_freq not null,
  day_of_month int check (day_of_month between 1 and 31),   -- 31 は「月末」（その月にない日は月末にする）
  weekday int check (weekday between 0 and 6),              -- 0 = 日曜
  month_of_year int check (month_of_year between 1 and 12),
  start_on date not null,
  end_on date,
  next_run_on date not null,
  active boolean not null default true,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version int not null default 1,
  foreign key (category_id, group_id, kind) references public.categories (id, group_id, kind),
  foreign key (payer_member_id, group_id) references public.group_members (id, group_id),
  foreign key (payment_method_id, group_id) references public.payment_methods (id, group_id),
  check (end_on is null or end_on >= start_on),
  check ((freq = 'weekly' and weekday is not null) or (freq = 'monthly' and day_of_month is not null) or (freq = 'yearly' and day_of_month is not null and month_of_year is not null)),
  unique (id, group_id)
);
create index recurring_due_idx on public.recurring_transactions (group_id, next_run_on) where active;

-- ---------- 取引 ----------
create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  kind public.txn_kind not null,
  amount bigint not null check (amount between 1 and 999999999),
  currency text not null default 'JPY' check (currency = 'JPY'),
  occurred_on date not null check (occurred_on >= date '2000-01-01'),
  category_id uuid not null,
  payer_member_id uuid not null,                      -- 支出なら支払った人、収入なら受け取った人
  payment_method_id uuid,
  memo text not null default '' check (char_length(memo) <= 500),
  visibility public.txn_visibility not null default 'group',
  split_mode public.split_mode not null default 'none',
  status public.txn_status not null default 'active',
  created_by uuid references auth.users (id) on delete set null,
  created_by_member uuid,
  updated_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version int not null default 1,
  client_request_id uuid not null,                    -- 同じ送信が 2 回届いても 1 件だけにする
  recurring_id uuid,
  occurrence_date date,
  foreign key (category_id, group_id, kind) references public.categories (id, group_id, kind),
  foreign key (payer_member_id, group_id) references public.group_members (id, group_id),
  foreign key (payment_method_id, group_id) references public.payment_methods (id, group_id),
  foreign key (recurring_id, group_id) references public.recurring_transactions (id, group_id) on delete set null (recurring_id),
  unique (group_id, client_request_id),
  unique (recurring_id, occurrence_date),
  unique (id, group_id),
  check (kind = 'expense' or split_mode = 'none'),     -- 分担は支出だけ
  check (visibility = 'group' or split_mode = 'none')  -- 自分だけの取引は分担しない
);
create index transactions_month_idx on public.transactions (group_id, occurred_on desc) where status = 'active';
create index transactions_category_idx on public.transactions (group_id, category_id);
create index transactions_payer_idx on public.transactions (group_id, payer_member_id);

create table public.transaction_splits (
  transaction_id uuid not null,
  group_id uuid not null,
  member_id uuid not null,
  amount bigint not null check (amount >= 0),
  primary key (transaction_id, member_id),
  foreign key (transaction_id, group_id) references public.transactions (id, group_id) on delete cascade,
  foreign key (member_id, group_id) references public.group_members (id, group_id)
);
create index transaction_splits_member_idx on public.transaction_splits (group_id, member_id);

-- ---------- 予算 ----------
-- start_month の月から、同じ対象の新しい予算が始まるまで、毎月同じ額が続く（月が変わっても設定し直さなくてよい）
create table public.budgets (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  scope public.budget_scope not null default 'group',
  category_id uuid,                                   -- null は全体
  member_id uuid,                                     -- 個人の予算のときだけ
  start_month date not null check (extract(day from start_month) = 1),
  end_month date check (end_month is null or extract(day from end_month) = 1),
  amount bigint not null check (amount between 1 and 999999999),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version int not null default 1,
  foreign key (category_id, group_id) references public.categories (id, group_id),
  foreign key (member_id, group_id) references public.group_members (id, group_id),
  check ((scope = 'group' and member_id is null) or (scope = 'personal' and member_id is not null)),
  check (end_month is null or end_month >= start_month)
);
create unique index budgets_uniq on public.budgets (group_id, scope, coalesce(category_id, '00000000-0000-0000-0000-000000000000'::uuid), coalesce(member_id, '00000000-0000-0000-0000-000000000000'::uuid), start_month);

-- ---------- 精算 ----------
-- 家計簿の上での記録。実際の送金はしない。pending（払った人が記録）→ confirmed（受け取った人が確認）か cancelled
create table public.settlements (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  from_member uuid not null,
  to_member uuid not null,
  amount bigint not null check (amount between 1 and 999999999),
  status public.settlement_status not null default 'pending',
  note text not null default '' check (char_length(note) <= 200),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  confirmed_at timestamptz,
  confirmed_by uuid references auth.users (id) on delete set null,
  cancelled_at timestamptz,
  client_request_id uuid not null,
  version int not null default 1,
  foreign key (from_member, group_id) references public.group_members (id, group_id),
  foreign key (to_member, group_id) references public.group_members (id, group_id),
  unique (group_id, client_request_id),
  check (from_member <> to_member)
);
create index settlements_group_idx on public.settlements (group_id, created_at desc);

-- ---------- 操作履歴 ----------
create table public.audit_logs (
  id bigint generated always as identity primary key,
  group_id uuid references public.groups (id) on delete cascade,
  actor uuid,                                         -- auth.users.id（退会後も番号は残る）
  action text not null,                               -- 例: transactions.insert / members.role
  target_table text not null,
  target_id uuid,
  detail jsonb not null default '{}'::jsonb,          -- 変わった項目の名前など。秘密情報（コード・トークン）は入れない
  at timestamptz not null default now()
);
create index audit_logs_group_idx on public.audit_logs (group_id, at desc);

-- ---------- 判定の関数（RLS と RPC で使う） ----------
-- ログイン中のユーザーの、そのグループでの有効なメンバー行
create function public.my_member(g uuid) returns public.group_members
language sql stable security definer set search_path = public as $$
  select m.* from public.group_members m
  join public.groups gr on gr.id = m.group_id and gr.deleted_at is null
  where m.group_id = g and m.user_id = auth.uid() and m.status = 'active'
$$;

-- そのグループで、指定の役割以上か
create function public.has_role(g uuid, min_role public.member_role) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.group_members m join public.groups gr on gr.id = m.group_id and gr.deleted_at is null
    where m.group_id = g and m.user_id = auth.uid() and m.status = 'active' and public.role_rank(m.role) >= public.role_rank(min_role)
  )
$$;

-- ---------- RLS: 読み取りだけ許す。書き込みは関数（RPC）だけ ----------
alter table public.profiles enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.invitations enable row level security;
alter table public.invitation_attempts enable row level security;
alter table public.categories enable row level security;
alter table public.payment_methods enable row level security;
alter table public.recurring_transactions enable row level security;
alter table public.transactions enable row level security;
alter table public.transaction_splits enable row level security;
alter table public.budgets enable row level security;
alter table public.settlements enable row level security;
alter table public.audit_logs enable row level security;

-- アプリのロールからの直接の書き込みを取り上げる（関数は security definer で書く）
revoke insert, update, delete, truncate on all tables in schema public from anon, authenticated;
revoke all on all tables in schema public from anon;
revoke all on public.invitation_attempts from authenticated;

-- プロフィール: 自分と、同じグループのメンバー
create policy profiles_read on public.profiles for select to authenticated using (
  id = auth.uid() or exists (
    select 1 from public.group_members a join public.group_members b on a.group_id = b.group_id
    where a.user_id = auth.uid() and a.status = 'active' and b.user_id = profiles.id
  )
);
create policy groups_read on public.groups for select to authenticated using (deleted_at is null and public.has_role(id, 'viewer'));
create policy members_read on public.group_members for select to authenticated using (public.has_role(group_id, 'viewer'));
create policy invitations_read on public.invitations for select to authenticated using (public.has_role(group_id, 'admin'));
create policy categories_read on public.categories for select to authenticated using (public.has_role(group_id, 'viewer'));
create policy payment_methods_read on public.payment_methods for select to authenticated using (public.has_role(group_id, 'viewer'));
create policy recurring_read on public.recurring_transactions for select to authenticated using (
  public.has_role(group_id, 'viewer') and (visibility = 'group' or created_by = auth.uid())
);
-- 取引: 公開範囲が「グループ」ならメンバー全員、「自分だけ」なら作った人だけ
create policy transactions_read on public.transactions for select to authenticated using (
  public.has_role(group_id, 'viewer') and (visibility = 'group' or created_by = auth.uid())
);
create policy splits_read on public.transaction_splits for select to authenticated using (
  exists (select 1 from public.transactions t where t.id = transaction_id
          and public.has_role(t.group_id, 'viewer') and (t.visibility = 'group' or t.created_by = auth.uid()))
);
create policy budgets_read on public.budgets for select to authenticated using (public.has_role(group_id, 'viewer'));
create policy settlements_read on public.settlements for select to authenticated using (public.has_role(group_id, 'viewer'));
create policy audit_read on public.audit_logs for select to authenticated using (public.has_role(group_id, 'admin'));

-- 関数の実行権限: 既定の public への付与を外し、必要なものだけ authenticated に付ける（後のマイグレーションで）
revoke execute on all functions in schema public from public, anon;
grant execute on function public.role_rank(public.member_role), public.today_jst(), public.has_role(uuid, public.member_role), public.my_member(uuid) to authenticated;
