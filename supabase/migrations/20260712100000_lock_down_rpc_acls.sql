-- DB-P0-1: upsert_board_jobs was callable by PUBLIC (default fn ACL, never
-- revoked). SECURITY DEFINER + anon-key access = arbitrary feed injection via
-- POST /rest/v1/rpc/upsert_board_jobs. Verified live 2026-07-12: anon call
-- returned 200 before this migration.
revoke all on function public.upsert_board_jobs(jsonb) from public, anon, authenticated;
-- service_role grant already exists; re-assert for clarity.
grant execute on function public.upsert_board_jobs(jsonb) to service_role;
