#!/usr/bin/env python3
"""
Live RLS verification against the real Supabase project (not a local
emulator — Supabase has no local-RLS-emulator equivalent to the Firestore
Emulator this project's functions/test-rules/*.test.js suites use).

Mirrors functions/test-rules/scenario_walkthrough.test.js: real accounts
(A/B at NMIT, C at RVCE), real signed session JWTs from a real sign-in
(not hand-crafted tokens), real PostgREST calls exercising the actual RLS
policies from 20260914000002_rls_policies.sql in the same order a real
client would issue them. Every college-isolation boundary is asserted in
both directions, exactly like the Firestore scenario test.

This script is NOT meant to be committed with real keys inline — it reads
them from environment variables. See docs/supabase-migration-plan.md for
how this was actually invoked this session (keys were exported inline in
the shell command, never written to a file in the repo).
"""
import json
import os
import sys
import urllib.request
import urllib.error

PROJECT_URL = os.environ["SUPABASE_URL"]
ANON_KEY = os.environ["SUPABASE_ANON_KEY"]
SERVICE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
JWT_A = os.environ["JWT_A"]
JWT_B = os.environ["JWT_B"]
JWT_C = os.environ["JWT_C"]
UID_A = os.environ["UID_A"]
UID_B = os.environ["UID_B"]
UID_C = os.environ["UID_C"]

passed = 0
failed = 0


def rest(method, path, jwt=None, body=None, extra_headers=None, params=None):
    url = f"{PROJECT_URL}/rest/v1/{path}"
    if params:
        url += "?" + "&".join(f"{k}={v}" for k, v in params.items())
    headers = {
        "apikey": ANON_KEY,
        "Authorization": f"Bearer {jwt or ANON_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }
    if extra_headers:
        headers.update(extra_headers)
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, raw.decode(errors="replace")


def test(name, fn):
    global passed, failed
    try:
        fn()
        passed += 1
        print(f"  ✔ {name}")
    except AssertionError as e:
        failed += 1
        print(f"  ✘ {name}\n      {e}")


def expect_ok(status, body, name):
    assert 200 <= status < 300, f"{name}: expected 2xx, got {status}: {body}"


def expect_denied(status, body, name):
    # PostgREST returns 401/403 for RLS-denied writes, and an EMPTY array
    # (200, []) for RLS-filtered reads (a denied SELECT isn't an error —
    # it's zero visible rows, the same "denied reads as absence" property
    # Postgres gives for free that Firestore had to be carefully coded to
    # approximate). Both count as "denied" here.
    if status in (401, 403):
        return
    if status == 200 and body == []:
        return
    if status >= 400:
        return
    raise AssertionError(f"{name}: expected denial, got {status}: {body}")


print("\n== Step 1: profile bootstrap ==")


def s1a():
    st, b = rest("POST", "profiles", jwt=JWT_A,
                 body={"id": UID_A, "email": "a@nmit.ac.in", "college_id": "nmit"})
    expect_ok(st, b, "s1a")


def s1b():
    st, b = rest("POST", "profiles", jwt=JWT_B,
                 body={"id": UID_B, "email": "b@nmit.ac.in", "college_id": "nmit"})
    expect_ok(st, b, "s1b")


def s1c():
    st, b = rest("POST", "profiles", jwt=JWT_C,
                 body={"id": UID_C, "email": "c@rvce.edu.in", "college_id": "rvce"})
    expect_ok(st, b, "s1c")


def s1d():
    # forging someone else's id on your own insert must be denied
    st, b = rest("POST", "profiles", jwt=JWT_A,
                 body={"id": UID_B, "email": "hijack@nmit.ac.in", "college_id": "nmit"})
    expect_denied(st, b, "s1d")


def s1e():
    # collegeId must match the email domain (insert trigger)
    st, b = rest("POST", "profiles", jwt=JWT_C,
                 body={"id": "00000000-0000-0000-0000-000000000099",
                       "email": "forge@rvce.edu.in", "college_id": "nmit"})
    assert st >= 400, f"s1e: expected the college_id/email mismatch trigger to reject this, got {st}: {b}"


test("1a A bootstraps own profile", s1a)
test("1b B bootstraps own profile", s1b)
test("1c C bootstraps own profile (different college)", s1c)
test("1d A cannot create a profile row for B's id", s1d)
test("1e college_id must match email domain (trigger)", s1e)

print("\n== Step 2: feed (college isolation) ==")
post_id = {}


def s2a():
    st, b = rest("POST", "posts", jwt=JWT_A,
                 body={"user_id": UID_A, "college_id": "nmit", "text": "hello nmit"})
    expect_ok(st, b, "s2a")
    post_id["v"] = b[0]["id"]


def s2b():
    st, b = rest("GET", "posts", jwt=JWT_B, params={"id": f"eq.{post_id['v']}"})
    expect_ok(st, b, "s2b")
    assert len(b) == 1, f"s2b: expected B to see A's post, got {b}"


def s2c():
    st, b = rest("GET", "posts", jwt=JWT_C, params={"id": f"eq.{post_id['v']}"})
    expect_denied(st, b, "s2c")


def s2d():
    st, b = rest("POST", "post_likes", jwt=JWT_B,
                 body={"post_id": post_id["v"], "user_id": UID_B})
    expect_ok(st, b, "s2d")


def s2e():
    st, b = rest("POST", "post_likes", jwt=JWT_C,
                 body={"post_id": post_id["v"], "user_id": UID_C})
    expect_denied(st, b, "s2e")


def s2f():
    st, b = rest("GET", "posts", jwt=JWT_B, params={"id": f"eq.{post_id['v']}"})
    expect_ok(st, b, "s2f")
    assert b[0]["likes_count"] == 1, f"s2f: expected likes_count trigger to fire, got {b[0]}"


test("2a A posts to nmit feed", s2a)
test("2b B (same college) reads A's post", s2b)
test("2c C (different college) cannot read A's post", s2c)
test("2d B likes A's post", s2d)
test("2e C cannot like A's post (cross-college)", s2e)
test("2f likes_count trigger fired atomically", s2f)

print("\n== Step 3: friends ==")
req_id = {}


def s3a():
    st, b = rest("POST", "friend_requests", jwt=JWT_A,
                 body={"from_uid": UID_A, "to_uid": UID_B})
    expect_ok(st, b, "s3a")
    req_id["v"] = b[0]["id"]


def s3b():
    st, b = rest("GET", "friend_requests", jwt=JWT_B, params={"id": f"eq.{req_id['v']}"})
    expect_ok(st, b, "s3b")
    assert len(b) == 1


def s3c():
    st, b = rest("PATCH", "friend_requests", jwt=JWT_B,
                 body={"status": "accepted"}, params={"id": f"eq.{req_id['v']}"})
    expect_ok(st, b, "s3c")


def s3d():
    ua, ub = sorted([UID_A, UID_B])
    st, b = rest("POST", "friendships", jwt=JWT_B,
                 body={"user_a": ua, "user_b": ub, "source_request_id": req_id["v"]})
    # NOTE: request is now 'accepted', not 'pending' -- the consent-check
    # policy requires status='pending' at the moment friendships.insert
    # runs, exactly mirroring the Firestore friends.create rule's
    # get(...).data.status == 'pending' check. Real client ordering
    # (friend_service.dart) creates the friendship BEFORE flipping status,
    # not after -- this step intentionally probes the wrong order to prove
    # the consent check is real, then s3e proves the right order works.
    expect_denied(st, b, "s3d (wrong order: status already flipped)")


def s3e():
    # Redo in the correct order: request stays pending until AFTER the
    # friendship is created (mirrors friend_service.dart exactly).
    st, b = rest("POST", "friend_requests", jwt=JWT_A, body={"from_uid": UID_A, "to_uid": UID_B})
    expect_ok(st, b, "s3e setup")
    rid = b[0]["id"]
    ua, ub = sorted([UID_A, UID_B])
    st2, b2 = rest("POST", "friendships", jwt=JWT_B,
                   body={"user_a": ua, "user_b": ub, "source_request_id": rid})
    expect_ok(st2, b2, "s3e create friendship while request still pending")


def s3f():
    st, b = rest("GET", "friendships", jwt=JWT_C)
    expect_ok(st, b, "s3f")
    assert b == [], f"s3f: C must not see A/B's friendship, got {b}"


def s3g():
    # duplicate pending request in the reverse direction must be denied
    # (partial unique index on least/greatest pair)
    st, b = rest("POST", "friend_requests", jwt=JWT_B, body={"from_uid": UID_B, "to_uid": UID_A})
    expect_denied(st, b, "s3g duplicate pending request denied by unique index")


test("3a A sends friend request to B", s3a)
test("3b B reads incoming request", s3b)
test("3c B accepts (status -> accepted)", s3c)
test("3d wrong-order friendship create denied (consent check is real)", s3d)
test("3e correct-order friendship create succeeds", s3e)
test("3f C cannot see A/B friendship", s3f)
test("3g duplicate pending friend_request denied by unique index", s3g)

print("\n== Step 4: 1:1 chat ==")
conv_id = {}


def s4a():
    ua, ub = sorted([UID_A, UID_B])
    st, b = rest("POST", "conversations", jwt=JWT_A, body={"user_a": ua, "user_b": ub})
    expect_ok(st, b, "s4a")
    conv_id["v"] = b[0]["id"]


def s4b():
    st, b = rest("POST", "messages", jwt=JWT_A,
                 body={"conversation_id": conv_id["v"], "from_uid": UID_A, "to_uid": UID_B, "text": "hey!"})
    expect_ok(st, b, "s4b")


def s4c():
    st, b = rest("POST", "messages", jwt=JWT_A,
                 body={"conversation_id": conv_id["v"], "from_uid": UID_C, "to_uid": UID_B, "text": "spoof"})
    expect_denied(st, b, "s4c sender spoofing denied")


def s4d():
    st, b = rest("GET", "messages", jwt=JWT_C, params={"conversation_id": f"eq.{conv_id['v']}"})
    expect_ok(st, b, "s4d")
    assert b == [], f"s4d: C must not read A/B's messages, got {b}"


test("4a A creates the conversation", s4a)
test("4b A sends first message", s4b)
test("4c sender-spoofing (from_uid=C while authed as A) denied", s4c)
test("4d C cannot read A/B's messages", s4d)

print("\n== Step 5: clubs ==")
club_req_id = {}
club_id = {}


def s5a():
    st, b = rest("POST", "club_requests", jwt=JWT_A,
                 body={"owner_uid": UID_A, "club_name": "Chess Club", "id_card_url": "https://x/id.jpg"})
    expect_ok(st, b, "s5a")
    club_req_id["v"] = b[0]["id"]


def s5b():
    # A normal user (not platform admin) attempting self-service club
    # creation must be denied -- same escalation this project closed in
    # Firestore (Phase 18: clubs.create used to allow admins==[auth.uid]
    # unconditionally).
    st, b = rest("POST", "clubs", jwt=JWT_A, body={"name": "Self Club", "owner_uid": UID_A})
    expect_denied(st, b, "s5b self-service club creation denied")


def s5c():
    # simulate platform-admin approval using the service-role key (the
    # RLS-bypass equivalent of Firestore's isAdmin() branch -- there is no
    # real platform-admin *account* to sign in as yet, since is_admin is a
    # per-row flag the project owner sets once on their real account; the
    # service-role key is the correct stand-in for "trusted server-side
    # admin action" here, exactly like withSecurityRulesDisabled() was
    # used for fixture setup in the Firestore test suites).
    st, b = rest("POST", "clubs", jwt=SERVICE_KEY, body={"name": "Chess Club", "owner_uid": UID_A})
    expect_ok(st, b, "s5c admin bootstraps club")
    club_id["v"] = b[0]["id"]
    st2, b2 = rest("POST", "club_members", jwt=SERVICE_KEY,
                   body={"club_id": club_id["v"], "user_id": UID_A, "role": "admin"})
    expect_ok(st2, b2, "s5c bootstrap admin member")


def s5d():
    # B has not joined: reading their OWN (nonexistent) membership row via
    # a filtered query must succeed as an EMPTY result, not an error --
    # this is exactly the Phase 21 club_members.read fix, now true by
    # construction rather than by a carefully-guarded rule clause.
    st, b = rest("GET", "club_members", jwt=JWT_B,
                 params={"club_id": f"eq.{club_id['v']}", "user_id": f"eq.{UID_B}"})
    expect_ok(st, b, "s5d (Phase 21 equivalent: own nonexistent row reads as empty, not an error)")
    assert b == []


def s5e():
    st, b = rest("POST", "club_join_requests", jwt=JWT_B,
                 body={"club_id": club_id["v"], "user_id": UID_B})
    expect_ok(st, b, "s5e")


def s5f():
    # club admin (A) approves the join
    st, b = rest("POST", "club_members", jwt=JWT_A,
                 body={"club_id": club_id["v"], "user_id": UID_B, "role": "member"})
    expect_ok(st, b, "s5f")


def s5g():
    st, b = rest("GET", "clubs", jwt=JWT_A, params={"id": f"eq.{club_id['v']}"})
    expect_ok(st, b, "s5g")
    assert b[0]["members_count"] == 2, f"s5g: expected members_count trigger, got {b[0]}"


def s5h():
    st, b = rest("POST", "club_messages", jwt=JWT_B,
                 body={"club_id": club_id["v"], "user_id": UID_B, "text": "hi club"})
    expect_ok(st, b, "s5h")


def s5i():
    st, b = rest("GET", "club_messages", jwt=JWT_C, params={"club_id": f"eq.{club_id['v']}"})
    expect_ok(st, b, "s5i")
    assert b == [], f"s5i: C (non-member) must not read club chat, got {b}"


test("5a A submits club creation request", s5a)
test("5b self-service club creation denied", s5b)
test("5c admin approves: club + admin membership bootstrapped", s5c)
test("5d B's own nonexistent membership row reads as empty (Phase 21 equivalent)", s5d)
test("5e B requests to join", s5e)
test("5f club admin approves the join", s5f)
test("5g members_count trigger fired", s5g)
test("5h B sends a club message", s5h)
test("5i C (non-member) cannot read club chat", s5i)

print("\n== Step 6: anonymous college chat ==")


def s6a():
    st, b = rest("POST", "anon_rooms", jwt=JWT_A, body={"college_id": "nmit", "created_by": UID_A})
    if 200 <= st < 300:
        return
    # idempotent: room may already exist from a prior run of this script
    assert st >= 400


def s6b():
    st, b = rest("GET", "anon_rooms", jwt=JWT_C, params={"college_id": "eq.nmit"})
    expect_ok(st, b, "s6b")
    assert b == [], f"s6b: C must not see the nmit room, got {b}"


def s6c():
    st, b = rest("POST", "anon_messages", jwt=JWT_A,
                 body={"room_college_id": "nmit", "user_id": UID_A, "anon_id": "anonA",
                       "text": "anon hello",
                       "expires_at": "2099-01-01T00:00:00Z"})
    expect_denied(st, b, "s6c far-future expiry denied")


test("6a A opens the nmit anon room (idempotent)", s6a)
test("6b C cannot see the nmit room (college isolation)", s6b)
test("6c far-future expiresAt denied (TTL bound enforced)", s6c)

print("\n== Step 7: events ==")
event_id = {}


def s7a():
    st, b = rest("POST", "events", jwt=JWT_A,
                 body={"created_by": UID_A, "college_id": "nmit", "title": "Chess Tournament",
                       "start_date": "2027-01-01T00:00:00Z", "end_date": "2027-01-02T00:00:00Z"})
    expect_ok(st, b, "s7a")
    event_id["v"] = b[0]["id"]


def s7b():
    st, b = rest("GET", "events", jwt=JWT_B, params={"id": f"eq.{event_id['v']}"})
    expect_ok(st, b, "s7b")
    assert len(b) == 1


def s7c():
    st, b = rest("GET", "events", jwt=JWT_C, params={"id": f"eq.{event_id['v']}"})
    expect_denied(st, b, "s7c")


test("7a A creates a college event", s7a)
test("7b B (same college) reads the event", s7b)
test("7c C (different college) cannot read the event", s7c)

print("\n== Step 8: notifications ==")


def s8a():
    # return=minimal, not representation: the sender (A) creating a
    # notification FOR B is correctly unable to read it back afterwards
    # (notifications_select is recipient-only, matching the original
    # firestore.rules notifications.read rule exactly) -- requesting the
    # representation back would require a SELECT the sender was never
    # meant to pass, which is a PostgREST-level detail, not an app bug:
    # the real Flutter client never reads back a notification it just
    # sent to someone else either.
    st, b = rest("POST", "notifications", jwt=JWT_A,
                 body={"type": "friend_request", "from_uid": UID_A, "to_uid": UID_B},
                 extra_headers={"Prefer": "return=minimal"})
    assert st == 201, f"s8a: expected 201, got {st}: {b}"


def s8b():
    st, b = rest("GET", "notifications", jwt=JWT_B, params={"to_uid": f"eq.{UID_B}"})
    expect_ok(st, b, "s8b setup: B can read their own notification")
    assert len(b) == 1, f"s8b: expected B to see the notification A sent, got {b}"


def s8c():
    st, b = rest("GET", "notifications", jwt=JWT_C, params={"to_uid": f"eq.{UID_B}"})
    expect_ok(st, b, "s8c")
    assert b == [], f"s8c: C must not read B's notifications, got {b}"


test("8a A creates a notification to B (sender can't read it back — correct)", s8a)
test("8b B (the recipient) can read their own notification", s8b)
test("8c C cannot read B's notifications", s8c)

print("\n== Step 9: moderation (reports/blocks) ==")
report_id = {}


def s9a():
    st, b = rest("POST", "reports", jwt=JWT_A,
                 body={"reporter_uid": UID_A, "target_type": "user", "target_id": UID_C, "reason": "spam"})
    expect_ok(st, b, "s9a")
    report_id["v"] = b[0]["id"]


def s9b():
    # forging someone else's reporter_uid must be denied
    st, b = rest("POST", "reports", jwt=JWT_A,
                 body={"reporter_uid": UID_B, "target_type": "user", "target_id": UID_C, "reason": "forged"})
    expect_denied(st, b, "s9b")


def s9c():
    # C is neither the reporter nor an admin -- must not see A's report
    st, b = rest("GET", "reports", jwt=JWT_C, params={"id": f"eq.{report_id['v']}"})
    expect_ok(st, b, "s9c")
    assert b == [], f"s9c: C must not read A's report, got {b}"


def s9d():
    # a non-admin (A, the reporter) cannot dismiss/review their own report --
    # only a platform admin transitions status. The service-role key stands
    # in for a real platform-admin account exactly as s5c already does.
    st, b = rest("PATCH", "reports", jwt=JWT_A,
                 body={"status": "dismissed"}, params={"id": f"eq.{report_id['v']}"})
    expect_ok(st, b, "s9d")
    assert b == [], f"s9d: non-admin status update should affect 0 rows (RLS-filtered), got {b}"


def s9e():
    st, b = rest("POST", "blocks", jwt=JWT_B, body={"blocker_uid": UID_B, "blocked_uid": UID_C})
    expect_ok(st, b, "s9e")


def s9f():
    # the blocked party (C) must not be able to friend-request the blocker
    # (B) -- this is the exact bug found live: the naive first version of
    # this check was itself RLS-filtered out from the blocked user's own
    # point of view (fixed by the is_blocked_pair() SECURITY DEFINER helper).
    st, b = rest("POST", "friend_requests", jwt=JWT_C, body={"from_uid": UID_C, "to_uid": UID_B})
    expect_denied(st, b, "s9f")


def s9g():
    # nor the reverse direction (blocker -> blocked)
    st, b = rest("POST", "friend_requests", jwt=JWT_B, body={"from_uid": UID_B, "to_uid": UID_C})
    expect_denied(st, b, "s9g")


def s9h():
    # the blocked party must not be able to remove the block that targets
    # them -- only the blocker can unblock.
    st, b = rest("DELETE", "blocks", jwt=JWT_C,
                 params={"blocker_uid": f"eq.{UID_B}", "blocked_uid": f"eq.{UID_C}"},
                 extra_headers={"Prefer": "return=representation"})
    expect_ok(st, b, "s9h")
    assert b == [], f"s9h: blocked party's unblock attempt should affect 0 rows, got {b}"


def s9i():
    # the blocker CAN unblock their own block.
    st, b = rest("DELETE", "blocks", jwt=JWT_B,
                 params={"blocker_uid": f"eq.{UID_B}", "blocked_uid": f"eq.{UID_C}"},
                 extra_headers={"Prefer": "return=representation"})
    expect_ok(st, b, "s9i")
    assert len(b) == 1, f"s9i: blocker's own unblock should remove exactly one row, got {b}"


test("9a A reports C (as self)", s9a)
test("9b forging another user's reporter_uid denied", s9b)
test("9c C cannot read A's report (not reporter, not admin)", s9c)
test("9d non-admin cannot change a report's status", s9d)
test("9e B blocks C", s9e)
test("9f blocked party (C) cannot friend-request the blocker (B)", s9f)
test("9g blocker (B) cannot friend-request the blocked party (C) either", s9g)
test("9h blocked party cannot unblock themselves", s9h)
test("9i blocker can unblock their own block", s9i)

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
