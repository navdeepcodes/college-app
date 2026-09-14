-- Every .stream() call in the Flutter app (feed, chat, clubs, notifications,
-- friends, comments, moments, events) subscribes via Supabase Realtime's
-- Postgres Changes feature. That requires the table to be added to the
-- supabase_realtime publication -- a step distinct from creating the table
-- or its RLS policies, and one this migration set never did. Found live:
-- every .stream()-backed screen failed with RealtimeSubscribeException
-- (status: channelError, "Please check Realtime is enabled for the given
-- connect parameters") on first real on-device test of the feed screen.
--
-- RLS still applies to realtime changefeeds (Supabase enforces the same
-- policies on the replication stream), so this does not widen what any
-- user can see -- it only turns on the delivery mechanism the app's
-- .stream() calls already assumed was there.
alter publication supabase_realtime add table
  posts,
  post_likes,
  comments,
  conversations,
  messages,
  anon_messages,
  clubs,
  club_members,
  club_requests,
  club_join_requests,
  club_messages,
  friendships,
  notifications,
  moments,
  events,
  profiles;
