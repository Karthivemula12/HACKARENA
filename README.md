# HACKARENA

**Play · Compete · Create**

HACKARENA is a dark-neon esports and hackathon platform. It includes mini-games, player accounts, XP, tournaments, hackathons, team creation, project submissions, a leaderboard, and admin controls.

## Stack
- Static frontend: HTML, CSS and JavaScript
- Authentication and PostgreSQL database: Supabase
- Database authorization: PostgreSQL Row Level Security (RLS)
- Hosting: GitHub Pages (or any static web host)

## 1. Create the Supabase project
1. Open [Supabase](https://supabase.com/) and create a new project.
2. Choose a strong database password and save it somewhere private.
3. After the project is ready, open **Project Settings → API** (or the API Keys page).
4. Copy the **Project URL** and the **publishable key** (or legacy **anon** key).

## 2. Create the database
1. In Supabase, open **SQL Editor → New query**.
2. Open `supabase/schema.sql` from this repository.
3. Copy the entire SQL file into the SQL Editor and run it.
4. The script creates the tables, starter events, signup/team triggers, XP awarding trigger, admin review function, and RLS policies.

Review any SQL errors in the editor before continuing.

## 3. Connect the website
1. Open `config.js` in this repository.
2. Replace `https://YOUR-PROJECT-REF.supabase.co` with your Supabase Project URL.
3. Replace `YOUR_SUPABASE_PUBLISHABLE_OR_ANON_KEY` with the project's publishable key (or legacy anon key).
4. Commit the change to GitHub.

**Security:** only the publishable/anon key belongs in `config.js`. Never put a Supabase secret key, service-role key, database password, or other private credential in browser JavaScript or GitHub. Keep RLS enabled.

## 4. Enable email sign-in
1. In Supabase, open **Authentication → URL Configuration**.
2. Set the Site URL to your GitHub Pages URL, for example `https://Karthivemula12.github.io/HACKARENA/` after Pages is enabled.
3. Add that URL to the allowed redirect URLs.
4. In **Authentication → Providers**, ensure Email is enabled.
5. For testing, email confirmation can be disabled temporarily. For a public launch, keep confirmation enabled and configure email delivery.

## 5. Publish with GitHub Pages
1. In GitHub, open this repository → **Settings → Pages**.
2. Choose **Deploy from a branch**.
3. Select branch `main` and folder `/ (root)`, then save.
4. Wait for the Pages deployment and open the published URL.

## 6. Make your account an admin
First create your account through the website and confirm your email if confirmation is enabled. Then in Supabase → **SQL Editor**, run this command after replacing the email:

```sql
update public.profiles
set role = 'admin'
where id = (
  select id from auth.users where email = 'YOUR_EMAIL'
);
```

Sign out and sign in again. The Admin tab will appear. Only grant admin status to trusted accounts.

## Features connected to the database
- Email/password signup, login and sign-out
- Player profiles and display names
- XP and games-played totals stored in PostgreSQL
- Tournaments and hackathons loaded from the events table
- Event registration stored per account
- Team creation and membership
- Hackathon project submissions and optional repository links
- Global XP leaderboard
- Admin event publishing/status changes and project review status

## Important limitations before a public competition
This is a full-stack starter platform, not yet a hardened tournament service. The current mini-games run in the browser and submit a score to the database. A determined user can manipulate browser code or submit a fake score. Do not use client-submitted scores to award money, valuable prizes, or official rankings. Before running a prize competition, move game validation and scoring into trusted server-side Edge Functions, add rate limits and audit logs, and test the system with real users.

Also configure Supabase email delivery, backups, monitoring, privacy terms, and age-appropriate community rules before opening registration publicly.

## Repository layout
- `index.html` — HACKARENA website
- `config.js` — public Supabase URL and publishable/anon key placeholders
- `supabase/schema.sql` — database schema, triggers and RLS policies
