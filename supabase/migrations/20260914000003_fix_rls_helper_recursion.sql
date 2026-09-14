-- Bug found via live testing (supabase/tests/rls_scenario_check.py, step
-- 2a): every helper function that looks up the CALLER's own row
-- (current_college_id, is_platform_admin, is_club_member, is_club_admin)
-- queries a table that has, in ITS OWN RLS policy, a call back into that
-- same helper function -- e.g. profiles_select calls current_college_id(),
-- which selects from profiles, which re-evaluates profiles_select, which
-- calls current_college_id() again. Infinite recursion, surfaced
-- immediately as "stack depth limit exceeded" the moment any policy that
-- uses one of these helpers actually ran (a posts insert was the first
-- real write in the test sequence to hit it).
--
-- This is exactly the "isolated inspection missed a real bug, only a real
-- executed sequence caught it" lesson this whole project has hit
-- repeatedly on the Firestore side (users.read, club_members.read). The
-- structural fix here is the standard, documented Postgres/Supabase
-- pattern: mark the helper SECURITY DEFINER with a pinned search_path, so
-- ITS internal lookup runs with the function owner's privileges (bypassing
-- RLS for that one internal query only) instead of re-triggering the
-- caller's own RLS evaluation. This does not weaken authorization for the
-- CALLER -- it only lets the helper read what it needs to answer "what is
-- the caller's own college_id / admin flag / membership", which is
-- exactly the same thing the old Firestore get() calls inside rules did
-- unconditionally (Firestore's get() inside a rule already runs with
-- elevated, rule-bypassing privileges for that read -- this restores the
-- same property, which SECURITY INVOKER, the default, had silently lost).

alter function public.current_college_id() security definer set search_path = public, pg_temp;
alter function public.is_platform_admin() security definer set search_path = public, pg_temp;
alter function public.is_club_member(uuid) security definer set search_path = public, pg_temp;
alter function public.is_club_admin(uuid) security definer set search_path = public, pg_temp;

-- Second, related bug in the same category, caught by continuing to read
-- the trigger functions with the recursion fix's lesson in mind rather
-- than waiting to hit each one at runtime individually: the counter-
-- maintenance triggers (bump_post_likes_count, etc.) update a DIFFERENT
-- row than the one the triggering statement touched -- e.g. B liking A's
-- post fires an UPDATE on A's posts row to bump likes_count. That UPDATE
-- is a completely separate statement subject to its OWN RLS policy
-- (posts_update, which requires user_id = auth.uid()) unless the trigger
-- function is SECURITY DEFINER -- so, unfixed, any like/comment/friend/
-- club-join from someone who isn't the target row's owner would have its
-- counter update silently blocked by RLS. bump_conversation_last_message
-- is the one exception: the message sender is always a conversation
-- participant, and conversations_update already permits either
-- participant, so no fix is needed there -- left as SECURITY INVOKER
-- deliberately rather than applying DEFINER everywhere by reflex (a
-- SECURITY DEFINER function is a real, narrow trust boundary; it should
-- only be used where the correctness argument actually requires it).
alter function public.bump_post_likes_count() security definer set search_path = public, pg_temp;
alter function public.bump_post_comments_count() security definer set search_path = public, pg_temp;
alter function public.bump_friends_count() security definer set search_path = public, pg_temp;
alter function public.bump_club_members_count() security definer set search_path = public, pg_temp;
