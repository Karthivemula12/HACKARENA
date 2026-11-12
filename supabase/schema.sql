-- HACKARENA Supabase schema
-- Run this entire file in Supabase Dashboard -> SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Player' check (char_length(display_name) between 2 and 30),
  xp integer not null default 0 check (xp >= 0),
  games_played integer not null default 0 check (games_played >= 0),
  role text not null default 'student' check (role in ('student','admin')),
  created_at timestamptz not null default now()
);

create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text not null default '',
  event_type text not null check (event_type in ('tournament','hackathon')),
  format text not null default 'Solo',
  theme text,
  status text not null default 'open' check (status in ('draft','open','closed','completed')),
  starts_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.registrations (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(event_id,user_id)
);

create table if not exists public.teams (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 40),
  focus text not null default '',
  owner_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.team_members (
  team_id uuid not null references public.teams(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  member_role text not null default 'member' check (member_role in ('owner','member')),
  joined_at timestamptz not null default now(),
  primary key(team_id,user_id)
);

create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  team_id uuid references public.teams(id) on delete set null,
  title text not null check (char_length(title) between 2 and 80),
  description text not null check (char_length(description) between 10 and 2000),
  repo_url text,
  status text not null default 'submitted' check (status in ('submitted','reviewing','shortlisted','winner')),
  created_at timestamptz not null default now()
);

create table if not exists public.game_scores (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  game_code text not null check (game_code in ('reaction','quiz','number','code')),
  score integer not null check (score between 0 and 10000),
  xp_awarded integer not null default 0,
  created_at timestamptz not null default now()
);

create or replace function public.is_hackarena_admin()
returns boolean language sql stable security definer set search_path = public
as $$ select exists(select 1 from public.profiles where id = auth.uid() and role = 'admin'); $$;

create or replace function public.handle_new_hackarena_user()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles(id,display_name)
  values (new.id, coalesce(nullif(left(new.raw_user_meta_data->>'display_name',30),''),'Player'))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_hackarena_user_created on auth.users;
create trigger on_hackarena_user_created after insert on auth.users
for each row execute procedure public.handle_new_hackarena_user();

create or replace function public.handle_new_hackarena_team()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.team_members(team_id,user_id,member_role)
  values(new.id,new.owner_id,'owner') on conflict do nothing;
  return new;
end;
$$;

drop trigger if exists on_hackarena_team_created on public.teams;
create trigger on_hackarena_team_created after insert on public.teams
for each row execute procedure public.handle_new_hackarena_team();

create or replace function public.award_hackarena_game_xp()
returns trigger language plpgsql security definer set search_path = public
as $$
declare earned integer;
begin
  earned := least(50, greatest(5, floor(new.score::numeric / 100)::integer));
  new.xp_awarded := earned;
  update public.profiles
    set xp = xp + earned, games_played = games_played + 1
    where id = new.user_id;
  return new;
end;
$$;

drop trigger if exists on_hackarena_score_created on public.game_scores;
create trigger on_hackarena_score_created before insert on public.game_scores
for each row execute procedure public.award_hackarena_game_xp();

alter table public.profiles enable row level security;
alter table public.events enable row level security;
alter table public.registrations enable row level security;
alter table public.teams enable row level security;
alter table public.team_members enable row level security;
alter table public.projects enable row level security;
alter table public.game_scores enable row level security;

drop policy if exists "Profiles visible to signed-in players" on public.profiles;
create policy "Profiles visible to signed-in players" on public.profiles for select to authenticated using (true);
drop policy if exists "Players edit their own display name" on public.profiles;
create policy "Players edit their own display name" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "Events are public to read" on public.events;
create policy "Events are public to read" on public.events for select to anon,authenticated using (status <> 'draft' or public.is_hackarena_admin());
drop policy if exists "Admins manage events" on public.events;
create policy "Admins manage events" on public.events for all to authenticated using (public.is_hackarena_admin()) with check (public.is_hackarena_admin());

drop policy if exists "Players see their registrations" on public.registrations;
create policy "Players see their registrations" on public.registrations for select to authenticated using (user_id = auth.uid() or public.is_hackarena_admin());
drop policy if exists "Players register themselves" on public.registrations;
create policy "Players register themselves" on public.registrations for insert to authenticated with check (
  user_id = auth.uid() and exists(select 1 from public.events e where e.id = event_id and e.status = 'open')
);
drop policy if exists "Players cancel own registrations" on public.registrations;
create policy "Players cancel own registrations" on public.registrations for delete to authenticated using (user_id = auth.uid() or public.is_hackarena_admin());

drop policy if exists "Signed-in players can view teams" on public.teams;
create policy "Signed-in players can view teams" on public.teams for select to authenticated using (true);
drop policy if exists "Players create teams they own" on public.teams;
create policy "Players create teams they own" on public.teams for insert to authenticated with check (owner_id = auth.uid());
drop policy if exists "Owners manage their teams" on public.teams;
create policy "Owners manage their teams" on public.teams for update to authenticated using (owner_id = auth.uid() or public.is_hackarena_admin()) with check (owner_id = auth.uid() or public.is_hackarena_admin());
drop policy if exists "Owners delete their teams" on public.teams;
create policy "Owners delete their teams" on public.teams for delete to authenticated using (owner_id = auth.uid() or public.is_hackarena_admin());

drop policy if exists "Members see their memberships" on public.team_members;
create policy "Members see their memberships" on public.team_members for select to authenticated using (
  user_id = auth.uid() or exists(select 1 from public.teams t where t.id = team_id and t.owner_id = auth.uid()) or public.is_hackarena_admin()
);
drop policy if exists "Team owners add members" on public.team_members;
create policy "Team owners add members" on public.team_members for insert to authenticated with check (
  exists(select 1 from public.teams t where t.id = team_id and t.owner_id = auth.uid()) or (user_id = auth.uid() and member_role = 'member')
);
drop policy if exists "Team owners or members leave" on public.team_members;
create policy "Team owners or members leave" on public.team_members for delete to authenticated using (
  (user_id = auth.uid() and member_role <> 'owner') or exists(select 1 from public.teams t where t.id = team_id and t.owner_id = auth.uid()) or public.is_hackarena_admin()
);

drop policy if exists "Project visibility for submitter team and admins" on public.projects;
create policy "Project visibility for submitter team and admins" on public.projects for select to authenticated using (
  user_id = auth.uid() or public.is_hackarena_admin() or (team_id is not null and exists(select 1 from public.team_members tm where tm.team_id = team_id and tm.user_id = auth.uid()))
);
drop policy if exists "Players submit their own projects" on public.projects;
create policy "Players submit their own projects" on public.projects for insert to authenticated with check (
  user_id = auth.uid() and exists(select 1 from public.events e where e.id = event_id and e.event_type = 'hackathon' and e.status = 'open')
  and (team_id is null or exists(select 1 from public.team_members tm where tm.team_id = team_id and tm.user_id = auth.uid()))
);
drop policy if exists "Submitters update own projects admins review" on public.projects;
create policy "Submitters update own projects admins review" on public.projects for update to authenticated using (user_id = auth.uid() or public.is_hackarena_admin()) with check (user_id = auth.uid() or public.is_hackarena_admin());

drop policy if exists "Scores visible to signed-in players" on public.game_scores;
create policy "Scores visible to signed-in players" on public.game_scores for select to authenticated using (true);
drop policy if exists "Players submit their own scores" on public.game_scores;
create policy "Players submit their own scores" on public.game_scores for insert to authenticated with check (user_id = auth.uid());

-- Least-privilege API access. Revoke default table grants first, then grant only what the app needs.
-- Never put a Supabase secret/service-role key in the browser.
revoke all on public.profiles, public.events, public.registrations, public.teams,
  public.team_members, public.projects, public.game_scores from anon, authenticated;
grant select on public.events to anon, authenticated;
grant select on public.profiles, public.teams, public.team_members, public.game_scores to authenticated;
grant update(display_name) on public.profiles to authenticated;
grant select,insert,delete on public.registrations to authenticated;
grant insert,update,delete on public.teams to authenticated;
grant insert,delete on public.team_members to authenticated;
grant select,insert,update on public.projects to authenticated;
grant insert on public.game_scores to authenticated;
grant insert,update,delete on public.events to authenticated;
grant execute on function public.is_hackarena_admin() to authenticated;

insert into public.events(title,description,event_type,format,theme,status)
select v.title,v.description,v.event_type,v.format,v.theme,'open'
from (values
 ('Arcade Showdown','A friendly competition across quick games.','tournament','Solo',null),
 ('Logic League','Put your problem-solving skills to the test.','tournament','Solo',null),
 ('Code Clash','A coding knowledge challenge for builders.','tournament','Solo','Programming'),
 ('Build for Good','Create a simple solution to a real-world problem.','hackathon','Team','Social impact'),
 ('FutureTech Sprint','Explore creative uses of AI and technology.','hackathon','Team','Future tech'),
 ('Green Code Challenge','Design tech ideas for a cleaner planet.','hackathon','Team','Sustainability')
) as v(title,description,event_type,format,theme)
where not exists(select 1 from public.events e where e.title=v.title);

-- After signing up with your own account, promote yourself to admin in SQL Editor:
-- update public.profiles set role = 'admin' where id = (select id from auth.users where email = 'YOUR_EMAIL');
