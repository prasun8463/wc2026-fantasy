-- ============================================================
-- WC 2026 Fantasy Predictor — Supabase Schema
-- Run this entire file in Supabase > SQL Editor > New Query
-- ============================================================

-- 1. LEAGUES
create table if not exists leagues (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text not null unique,
  admin_username text not null,
  bet_amount integer not null default 100,
  created_at timestamptz default now()
);

-- 2. USERS
create table if not exists users (
  id uuid primary key default gen_random_uuid(),
  username text not null unique,
  password_hash text not null,
  league_id uuid references leagues(id),
  earned integer not null default 0,
  spent integer not null default 0,
  created_at timestamptz default now()
);

-- 3. MATCHES (pre-seeded with WC 2026 fixtures)
create table if not exists matches (
  id text primary key,
  grp text not null,
  home text not null,
  away text not null,
  home_flag text default '🏳️',
  away_flag text default '🏳️',
  match_date text not null,
  result_home integer,
  result_away integer,
  resolved boolean default false,
  resolved_pot integer,
  resolved_share integer,
  resolved_type text,
  resolved_winners text[],
  created_at timestamptz default now()
);

-- 4. PREDICTIONS
create table if not exists predictions (
  id uuid primary key default gen_random_uuid(),
  match_id text references matches(id),
  username text not null,
  pred_home integer not null,
  pred_away integer not null,
  created_at timestamptz default now(),
  unique(match_id, username)
);

-- ============================================================
-- ROW LEVEL SECURITY — allow all reads, restrict writes
-- ============================================================
alter table leagues enable row level security;
alter table users enable row level security;
alter table matches enable row level security;
alter table predictions enable row level security;

-- Public read on everything
create policy "public read leagues" on leagues for select using (true);
create policy "public read users" on users for select using (true);
create policy "public read matches" on matches for select using (true);
create policy "public read predictions" on predictions for select using (true);

-- Allow inserts/updates from anonymous (app handles auth logic)
create policy "public insert leagues" on leagues for insert with check (true);
create policy "public insert users" on users for insert with check (true);
create policy "public update users" on users for update using (true);
create policy "public insert predictions" on predictions for insert with check (true);
create policy "public update matches" on matches for update using (true);
create policy "public insert matches" on matches for insert with check (true);
create policy "public update leagues" on leagues for update using (true);

-- ============================================================
-- SEED: WC 2026 FIXTURES
-- ============================================================
insert into matches (id, grp, home, away, home_flag, away_flag, match_date) values
('g01','A','Mexico','South Africa','🇲🇽','🇿🇦','Jun 11'),
('g02','B','Canada','UEFA Play-off','🇨🇦','🌍','Jun 12'),
('g03','D','USA','Paraguay','🇺🇸','🇵🇾','Jun 12'),
('g04','B','Qatar','Switzerland','🇶🇦','🇨🇭','Jun 12'),
('g05','C','Brazil','Morocco','🇧🇷','🇲🇦','Jun 12'),
('g06','C','Haiti','Scotland','🇭🇹','🏴󠁧󠁢󠁳󠁣󠁴󠁿','Jun 13'),
('g07','E','Germany','Curaçao','🇩🇪','🌍','Jun 13'),
('g08','F','Netherlands','Japan','🇳🇱','🇯🇵','Jun 13'),
('g09','G','Belgium','Egypt','🇧🇪','🇪🇬','Jun 14'),
('g10','H','Spain','Cabo Verde','🇪🇸','🇨🇻','Jun 14'),
('g11','H','Saudi Arabia','Uruguay','🇸🇦','🇺🇾','Jun 14'),
('g12','G','Iran','New Zealand','🇮🇷','🇳🇿','Jun 14'),
('g13','I','France','Senegal','🇫🇷','🇸🇳','Jun 15'),
('g14','I','Norway','CONMEBOL Play-off','🇳🇴','🌍','Jun 15'),
('g15','J','Argentina','Algeria','🇦🇷','🇩🇿','Jun 15'),
('g16','J','Austria','Jordan','🇦🇹','🇯🇴','Jun 15'),
('g17','K','Portugal','IC Play-off','🇵🇹','🌍','Jun 16'),
('g18','L','England','Croatia','🏴󠁧󠁢󠁥󠁮󠁧󠁿','🇭🇷','Jun 17'),
('g19','L','Ghana','Panama','🇬🇭','🇵🇦','Jun 17'),
('g20','K','Colombia','Uzbekistan','🇨🇴','🇺🇿','Jun 17'),
('g21','A','South Korea','UEFA Play-off D','🇰🇷','🌍','Jun 17'),
('g22','E','Ecuador','Ivory Coast','🇪🇨','🇨🇮','Jun 18'),
('g23','F','Tunisia','UEFA Play-off B','🇹🇳','🌍','Jun 18'),
('g24','A','Mexico','South Korea','🇲🇽','🇰🇷','Jun 21'),
('g25','A','South Africa','UEFA Play-off D','🇿🇦','🌍','Jun 21'),
('g26','C','Brazil','Haiti','🇧🇷','🇭🇹','Jun 21'),
('g27','C','Scotland','Morocco','🏴󠁧󠁢󠁳󠁣󠁴󠁿','🇲🇦','Jun 21'),
('g28','D','USA','Australia','🇺🇸','🇦🇺','Jun 22'),
('g29','E','Germany','Ivory Coast','🇩🇪','🇨🇮','Jun 22'),
('g30','F','Netherlands','UEFA Play-off B','🇳🇱','🌍','Jun 22'),
('g31','H','Spain','Saudi Arabia','🇪🇸','🇸🇦','Jun 23'),
('g32','G','Belgium','Iran','🇧🇪','🇮🇷','Jun 23'),
('g33','I','France','Norway','🇫🇷','🇳🇴','Jun 25'),
('g34','J','Argentina','Austria','🇦🇷','🇦🇹','Jun 25'),
('g35','K','Portugal','Colombia','🇵🇹','🇨🇴','Jun 25'),
('g36','L','England','Ghana','🏴󠁧󠁢󠁥󠁮󠁧󠁿','🇬🇭','Jun 26'),
('g37','B','Canada','Qatar','🇨🇦','🇶🇦','Jun 26'),
('g38','B','Switzerland','UEFA Play-off','🇨🇭','🌍','Jun 26'),
('g39','D','Paraguay','Australia','🇵🇾','🇦🇺','Jun 26'),
('g40','A','Mexico','South Africa','🇲🇽','🇿🇦','Jun 28'),
('g41','A','South Korea','UEFA Play-off D','🇰🇷','🌍','Jun 28'),
('g42','C','Brazil','Scotland','🇧🇷','🏴󠁧󠁢󠁳󠁣󠁴󠁿','Jun 28'),
('g43','C','Morocco','Haiti','🇲🇦','🇭🇹','Jun 28'),
('g44','D','USA','UEFA Play-off C','🇺🇸','🌍','Jun 28'),
('g45','H','Spain','Uruguay','🇪🇸','🇺🇾','Jun 29'),
('g46','H','Cabo Verde','Saudi Arabia','🇨🇻','🇸🇦','Jun 29'),
('g47','G','Belgium','New Zealand','🇧🇪','🇳🇿','Jun 29'),
('g48','G','Egypt','Iran','🇪🇬','🇮🇷','Jun 29'),
('g49','I','France','CONMEBOL Play-off','🇫🇷','🌍','Jun 30'),
('g50','I','Senegal','Norway','🇸🇳','🇳🇴','Jun 30'),
('g51','J','Algeria','Jordan','🇩🇿','🇯🇴','Jun 30'),
('g52','J','Argentina','Austria','🇦🇷','🇦🇹','Jun 30'),
('g53','K','Portugal','Uzbekistan','🇵🇹','🇺🇿','Jul 1'),
('g54','K','Colombia','IC Play-off','🇨🇴','🌍','Jul 1'),
('g55','L','Croatia','Panama','🇭🇷','🇵🇦','Jul 1'),
('g56','L','England','Panama','🏴󠁧󠁢󠁥󠁮󠁧󠁿','🇵🇦','Jul 2'),
('r01','R32','TBD','TBD','🏳️','🏳️','Jul 4'),
('r02','R32','TBD','TBD','🏳️','🏳️','Jul 4'),
('r03','R32','TBD','TBD','🏳️','🏳️','Jul 5'),
('r04','R32','TBD','TBD','🏳️','🏳️','Jul 5'),
('r05','R16','TBD','TBD','🏳️','🏳️','Jul 9'),
('r06','R16','TBD','TBD','🏳️','🏳️','Jul 10'),
('qf1','QF','TBD','TBD','🏳️','🏳️','Jul 12'),
('qf2','QF','TBD','TBD','🏳️','🏳️','Jul 13'),
('sf1','SF','TBD','TBD','🏳️','🏳️','Jul 15'),
('sf2','SF','TBD','TBD','🏳️','🏳️','Jul 16'),
('fin','Final','TBD','TBD','🏳️','🏳️','Jul 19')
on conflict (id) do nothing;
