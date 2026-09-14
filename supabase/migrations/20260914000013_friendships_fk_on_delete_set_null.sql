-- Found live, on-device, testing the actual friend-request-accept flow
-- through the real app for the first time: PostgrestException 23503
-- ("update or delete on table friend_requests violates foreign key
-- constraint friendships_source_request_id_fkey ... Key is still
-- referenced from table friendships").
--
-- lib/services/friend_service.dart's acceptRequest() has always done,
-- by design (see its own comment): insert the friendships row first
-- (referencing the request it came from via source_request_id), then
-- delete the now-processed friend_requests row. The FK constraint was
-- created with the default ON DELETE NO ACTION, so Postgres refused the
-- second step outright -- accepting a friend request was completely
-- broken through the real app the entire time this schema has existed.
--
-- This is exactly the gap the "don't trust RLS tests alone" mission
-- brief predicted: the earlier RLS scenario test's step 3c ("B accepts
-- (status -> accepted)") exercised a *different* operation --
-- UPDATE-ing a status column -- than the real client code, which
-- deletes the row outright. The scenario test's 40/40 pass never
-- exercised this exact insert-then-delete sequence, so it never caught
-- this.
--
-- source_request_id is provenance only (which request led to this
-- friendship) -- losing it when the request row is cleaned up is
-- correct and matches the column already being nullable. ON DELETE
-- CASCADE would be wrong here: it would delete the friendship itself
-- along with the request, destroying real relationship data over a
-- housekeeping delete.
alter table public.friendships
  drop constraint friendships_source_request_id_fkey,
  add constraint friendships_source_request_id_fkey
    foreign key (source_request_id) references public.friend_requests(id)
    on delete set null;
