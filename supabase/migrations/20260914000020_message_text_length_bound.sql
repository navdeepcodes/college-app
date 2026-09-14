-- Hardening pass task J (client-side profanity filter): evaluated whether
-- to add server-side profanity enforcement to match lib/moderation/
-- text_filter.dart. Decided NOT to duplicate that word/emoji list into SQL
-- -- two independently-maintained banned-word lists (Dart client + SQL)
-- will drift, and a regex-based server copy risks both false positives
-- (blocking legitimate messages in ways the client's more nuanced check
-- doesn't) and false negatives (missing what the client catches) without
-- ever being a complete solution either way. The client-side filter is
-- real but explicitly NOT tamper-proof (a modified client or a direct API
-- call bypasses it) -- documented as a known limitation in the final
-- report; the moderation/report_block migration (20260914000017) adding a
-- real report/review flow is the appropriate complementary safety net for
-- whatever slips through, not a second automated filter.
--
-- What IS a lightweight, unambiguous, worth-doing hardening step: none of
-- messages/comments/club_messages/anon_messages had ANY upper bound on
-- text length -- only `length(trim(text)) > 0`. A malicious or buggy
-- client (or a direct API call, bypassing the client's own TextField
-- limits entirely) could insert an arbitrarily large payload into any of
-- these, a real storage-abuse/DoS surface distinct from profanity
-- filtering but squarely "an obviously invalid message state" the
-- database should refuse regardless of content. 4000 chars is generous
-- for any real chat message in this app (none of the compose UIs are
-- long-form) while still ruling out multi-megabyte payloads.
alter table public.messages
  drop constraint if exists messages_text_check,
  add constraint messages_text_check check (length(trim(text)) > 0 and length(text) <= 4000);

alter table public.comments
  drop constraint if exists comments_text_check,
  add constraint comments_text_check check (length(trim(text)) > 0 and length(text) <= 4000);

alter table public.club_messages
  drop constraint if exists club_messages_text_check,
  add constraint club_messages_text_check check (length(trim(text)) > 0 and length(text) <= 4000);

alter table public.anon_messages
  drop constraint if exists anon_messages_text_check,
  add constraint anon_messages_text_check check (length(trim(text)) > 0 and length(text) <= 4000);
