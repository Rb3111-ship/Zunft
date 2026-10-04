-- ==============================================================================
-- Migration: 20261008000000_function_privileges.sql
--
-- Supabase gives EXECUTE on every new function in the public schema to the roles "anon" (not
-- logged in) and "authenticated" (logged in) automatically. "REVOKE ... FROM PUBLIC" in the
-- earlier migrations does not take that away, because those grants are made to the roles by name.
-- So here, explicitly:
--
--   * anon may call NOTHING of ours (our functions all need a logged-in person anyway).
--   * logged-in clients may call only the functions meant for them. Internal helpers (seat
--     counting, code generation, trigger functions, document numbering) are not callable from the
--     app: seats_in_use(), for example, would otherwise let anyone ask about any business.
-- ==============================================================================

DO $$
DECLARE
    f RECORD;
BEGIN
    FOR f IN
        SELECT p.oid::regprocedure AS signature
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
    LOOP
        EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon', f.signature);
    END LOOP;
END
$$;

REVOKE ALL ON FUNCTION
    seats_in_use(UUID),
    new_invite_code(),
    set_note_author_name(),
    assign_creator_to_job(),
    set_created_by(),
    guard_profile_update(),
    guard_business_plan(),
    guard_document_change(),
    guard_document_insert(),
    set_updated_at(),
    get_next_document_number(UUID, TEXT, INT)
FROM PUBLIC, anon, authenticated;

-- Functions created from now on are not callable by anon unless a migration says so.
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM anon;
