-- 操作履歴: 重要な表の追加・変更・削除をトリガーで記録する。秘密情報（招待コードのハッシュ等）は記録しない。
create function public._audit() returns trigger language plpgsql security definer set search_path = public as $$
declare o jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end; n jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  r jsonb := coalesce(n, o); changed text[]; d jsonb := '{}'::jsonb; act text;
begin
  if tg_op = 'UPDATE' then
    select array_agg(k) into changed from jsonb_object_keys(n) k
    where k not in ('updated_at', 'version', 'code_hash') and n -> k is distinct from o -> k;
    if changed is null then return null; end if;
    d := jsonb_build_object('changed', to_jsonb(changed));
    if tg_table_name = 'group_members' and 'role' = any (changed) then d := d || jsonb_build_object('role_from', o -> 'role', 'role_to', n -> 'role'); end if;
    if tg_table_name in ('group_members', 'settlements', 'transactions') and 'status' = any (changed) then d := d || jsonb_build_object('status_from', o -> 'status', 'status_to', n -> 'status'); end if;
  end if;
  if tg_table_name in ('transactions', 'settlements') then d := d || jsonb_build_object('amount', r -> 'amount'); end if;
  if tg_table_name = 'invitations' then d := d || jsonb_build_object('role', r -> 'role', 'max_uses', r -> 'max_uses'); end if;
  act := tg_table_name || '.' || lower(tg_op);
  insert into public.audit_logs (group_id, actor, action, target_table, target_id, detail)
  values (case when tg_table_name = 'groups' then (r ->> 'id')::uuid else (r ->> 'group_id')::uuid end, auth.uid(), act, tg_table_name,
          case when tg_table_name = 'transaction_splits' then (r ->> 'transaction_id')::uuid else (r ->> 'id')::uuid end, d);
  return null;
end $$;

create trigger audit_groups after insert or update on public.groups for each row execute function public._audit();
create trigger audit_members after insert or update on public.group_members for each row execute function public._audit();
create trigger audit_invitations after insert or update on public.invitations for each row execute function public._audit();
create trigger audit_categories after insert or update or delete on public.categories for each row execute function public._audit();
create trigger audit_budgets after insert or update or delete on public.budgets for each row execute function public._audit();
create trigger audit_transactions after insert or update on public.transactions for each row execute function public._audit();
create trigger audit_settlements after insert or update on public.settlements for each row execute function public._audit();
create trigger audit_recurring after insert or update or delete on public.recurring_transactions for each row execute function public._audit();
create trigger audit_payment_methods after insert or update on public.payment_methods for each row execute function public._audit();

-- 履歴は誰も書き換えられない（service_role でも、この関数経由のトリガー以外では足さない運用）
revoke insert, update, delete, truncate on public.audit_logs from authenticated, anon;
revoke execute on function public._audit() from public, anon, authenticated;
