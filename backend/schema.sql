-- FinPet database schema. Paste into the Supabase SQL editor and run (safe to re-run).
-- Only the backend touches these tables, using the service role key (which bypasses RLS).
-- Avatars are per-device and intentionally NOT stored here.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- users: accounts. Usernames are stored lowercase (the CHECK enforces it), so the
-- plain UNIQUE constraint is effectively case-insensitive.
-- ---------------------------------------------------------------------------
create table if not exists public.users (
    id            uuid primary key default gen_random_uuid(),
    username      text not null unique
                  check (username = lower(username) and username ~ '^[a-z0-9_]{3,20}$'),
    password_hash text not null,               -- bcrypt (cost 12); never plaintext
    created_at    timestamptz not null default now(),
    last_login_at timestamptz
);

-- ---------------------------------------------------------------------------
-- user_stats: one row per user (auto-created by trigger below).
-- ---------------------------------------------------------------------------
create table if not exists public.user_stats (
    user_id            uuid primary key references public.users(id) on delete cascade,
    -- streaks
    current_streak     integer not null default 0 check (current_streak >= 0),
    longest_streak     integer not null default 0 check (longest_streak >= 0),
    last_active_date   date,
    -- progress
    total_xp           integer not null default 0 check (total_xp >= 0),
    lessons_completed  integer not null default 0 check (lessons_completed >= 0),
    practice_sessions  integer not null default 0 check (practice_sessions >= 0),
    total_check_ins    integer not null default 0 check (total_check_ins >= 0),
    quizzes_taken      integer not null default 0 check (quizzes_taken >= 0),
    correct_answers    integer not null default 0 check (correct_answers >= 0),
    -- pet / rewards
    coins              integer not null default 0 check (coins >= 0),
    pet_level          integer not null default 1 check (pet_level >= 1),
    badges_earned      integer not null default 0 check (badges_earned >= 0),
    updated_at         timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- friendships: one row per relationship, directed requester -> addressee.
-- The unique index on the unordered pair stops A->B and B->A both existing.
-- ---------------------------------------------------------------------------
create table if not exists public.friendships (
    id           uuid primary key default gen_random_uuid(),
    requester_id uuid not null references public.users(id) on delete cascade,
    addressee_id uuid not null references public.users(id) on delete cascade,
    status       text not null default 'pending'
                 check (status in ('pending', 'accepted', 'blocked')),
    created_at   timestamptz not null default now(),
    responded_at timestamptz,
    check (requester_id <> addressee_id)
);

create unique index if not exists friendships_pair_uniq
    on public.friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));
create index if not exists friendships_addressee_idx on public.friendships (addressee_id, status);
create index if not exists friendships_requester_idx on public.friendships (requester_id, status);

-- ---------------------------------------------------------------------------
-- friend_streaks: one row per accepted friendship pair. user_a_id < user_b_id (canonical
-- ordering, so a pair has exactly one row). "Both checked in today" = both *_last_check_in
-- equal today's date; last_completed_date is the last day both did.
-- ---------------------------------------------------------------------------
create table if not exists public.friend_streaks (
    user_a_id            uuid not null references public.users(id) on delete cascade,
    user_b_id            uuid not null references public.users(id) on delete cascade,
    current_streak       integer not null default 0 check (current_streak >= 0),
    longest_streak       integer not null default 0 check (longest_streak >= 0),
    last_completed_date  date,
    user_a_last_check_in date,
    user_b_last_check_in date,
    created_at           timestamptz not null default now(),
    updated_at           timestamptz not null default now(),
    primary key (user_a_id, user_b_id),
    check (user_a_id < user_b_id)
);

create index if not exists friend_streaks_b_idx on public.friend_streaks (user_b_id);

-- ---------------------------------------------------------------------------
-- Trigger: every new user gets a user_stats row.
-- ---------------------------------------------------------------------------
create or replace function public.create_user_stats() returns trigger
language plpgsql security definer set search_path = public as $$
begin
    insert into public.user_stats (user_id) values (new.id) on conflict do nothing;
    return new;
end;
$$;

drop trigger if exists users_create_stats on public.users;
create trigger users_create_stats
    after insert on public.users
    for each row execute function public.create_user_stats();

-- ---------------------------------------------------------------------------
-- Row level security: enabled with NO policies, so anon/authenticated API keys can read
-- or write nothing. The backend's service role key bypasses RLS.
-- ---------------------------------------------------------------------------
alter table public.users          enable row level security;
alter table public.user_stats     enable row level security;
alter table public.friendships    enable row level security;
alter table public.friend_streaks enable row level security;

revoke all on public.users, public.user_stats, public.friendships, public.friend_streaks
    from anon, authenticated;

-- PostgREST also requires table privileges for the backend's service role.
grant select, insert on table public.users to service_role;
grant update (last_login_at) on table public.users to service_role;

-- Friends feature: the backend needs these on the friend tables (run again safely any time).
grant select, insert, update, delete on table public.friendships to service_role;
grant select, insert, update, delete on table public.friend_streaks to service_role;
grant select, update on table public.user_stats to service_role;
