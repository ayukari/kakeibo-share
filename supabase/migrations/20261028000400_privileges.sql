-- 内部用の関数を、ログインした利用者が直接呼べないようにする
-- Supabase は public スキーマの新しい関数に、既定で anon・authenticated の実行権限を付ける。
-- そのままだと _write_splits（権限の確認をしない内部の書き込み）などを API から直接呼べてしまう
revoke execute on function
  public._err(text, text, text), public._uid(), public._need(uuid, public.member_role),
  public.handle_new_user(), public.gen_random_bytes_safe(),
  public.equal_split(bigint, uuid[]), public._write_splits(public.transactions, jsonb),
  public.next_occurrence(public.recurring_transactions, date), public.first_occurrence(public.recurring_transactions),
  public.prepare_account_deletion(uuid)
from public, anon, authenticated;

-- これから作る関数も、既定では誰も実行できないようにする（使うものだけ明示して許可する）
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;
