# Sahachari Equipment Library – Complete Setup Guide (from zero)

Everything here is free. You need: a computer with internet, an email address, and about 60–90 minutes.

## What is in the folder
| File | Purpose |
|---|---|
| `index.html` | The whole website: public QR page, login, admin dashboard |
| `schema.sql` | Creates the database and all security rules (run once) |
| `migrate_v2.sql`, `migrate_photos.sql` | Only for databases created from an older version |
| `manifest.webmanifest`, `sw.js` | Let phones "install" the app |
| `assets/` | Logos, `hero.png` (optional) and `equipment/` photos |

---
## PART A – Create the database (Supabase)
**A1. Account and project**
1. Go to **supabase.com** → Sign up (free).
2. **New project** → name it, choose a long database password (save it in a password manager), pick a region near India (e.g. Mumbai/Singapore) → Create. Wait 2 minutes.

**A2. Create your login**
1. Left menu **Authentication → Users → Add user → Create new user**.
2. Enter your email + a strong, unique password, tick **Auto Confirm User** → Create.
3. Click the new user and copy the **User UID** (looks like `2d3df09f-0f14-…`).

**A3. Turn off public sign-ups** (important)
**Authentication → Sign In / Providers → Email** → switch **off** "Allow new users to sign up" → Save.

**A4. Run the database script**
1. Open `schema.sql` in Notepad. Near the end find `make your login the first administrator` and replace the UID in the next line with **your** UID from A2. Save.
2. Supabase → **SQL Editor → New query** → paste the whole file → **Run**. It should say "Success". (It is safe to run again if something fails.)
3. Optional test data is at the very bottom. For real use, delete the "sample test data" section before running, or delete the sample items later.
4. Check: run `select role, full_name from profiles;` – you should see one `admin`.

**A5. Copy your keys**
**Project Settings → API Keys**: copy the **Project URL** (Settings → Data API) and the **Publishable key** (`sb_publishable_…`). Never use the Secret / service_role key anywhere.

## PART B – Configure the website
1. Open `index.html` in Notepad (not Word). Find the line starting `const SUPABASE_URL=`.
2. Put your URL and publishable key inside the quotes. Save.
3. Test on your computer: double-click `index.html`. You should see the public page. Click **Committee login** (bottom) and sign in.

## PART C – Put it online free (GitHub Pages)
1. Create an account at **github.com** → **New repository** → name e.g. `sahachari` → **Public** → Create.
2. **Add file → Upload files**: drag in `index.html`, `manifest.webmanifest`, `sw.js` and the whole `assets` folder → **Commit changes**. (Do **not** upload CSV exports, backups or photos of people. Everything in a public repo is visible.)
3. **Settings → Pages** → Source: *Deploy from a branch* → Branch `main`, folder `/ (root)` → Save. After ~1 minute your site is `https://YOUR-NAME.github.io/sahachari/`.
4. In Supabase **Authentication → URL Configuration** set *Site URL* to that address (needed for password-reset emails).
5. Open the address on your phone and login to confirm everything works.

## PART D – First-time setup inside the app
1. **Settings → Public information**: initiative name (`Sahachari`), introduction, how to enquire → Save.
2. **Office & hours**: address and opening hours → Save.
3. **Committee contacts**: add each person (phone, WhatsApp with country code e.g. `919876543210`). Delete the sample contact.
4. **Staff accounts**: for each volunteer create the login in Supabase (A2), then paste their UID here with role `staff`. Admins can delete loans and open Settings; staff cannot.
5. **Equipment → Add equipment**: give each physical item its own code (W001, W002…). Add a photo: put the file in `assets/equipment/`, type its file name in the Photo box, upload the folder to GitHub again.

## PART E – The QR code
1. Open your *GitHub Pages* address (not a local file), log in → **Settings → QR code**.
2. **Print poster** (or Download QR as SVG). Stick it at the office entrance. The QR never changes; stock updates appear automatically.
3. Scan it with a phone camera to test. Test with Wi-Fi off too.

## PART F – Daily use
- **Lend**: *Lend equipment* → search beneficiary (or register in *Beneficiaries* first) → click the item card → condition/date/notes → **Confirm loan**. Print a slip from *Loans → More → Print slip*.
- **Return**: *Loans & returns → Inspect return* → choose condition and status after inspection (item becomes Available only when you choose it) → **Complete return**.
- **Reminder**: *More → Send reminder (WhatsApp)* opens WhatsApp with a ready message (10-digit numbers get +91).
- **Mistakes**: *More → Edit due date/notes*, *Undo return*, or (admin) *Delete loan* – asks for confirmation; an active loan's item becomes Available again; a copy stays in *Settings → Activity log*.
- **Item or beneficiary history**: *History* / *Details* buttons.
- Malayalam: the public page has an English / മലയാളം switch. Please have a native speaker check the wording.

## PART G – Install as an app on phones
Open the site in Chrome (Android) → ⋮ → *Add to Home screen / Install app*. On iPhone: Safari → Share → *Add to Home Screen*.

## PART H – Backups (do monthly)
1. **Easiest:** *Settings → Exports & backup → Full backup (JSON)* and the three CSV buttons. Save to a private drive.
2. **Full database copy:** Supabase → **Project Settings → Database → Connection string**; with PostgreSQL tools installed run `pg_dump "CONNECTION-STRING" -Fc -f backup.dump`. Restore into any Postgres with `pg_restore -d NEWDB backup.dump`.
3. **Restore into a new Supabase project:** repeat Part A, then restore with `pg_restore --data-only`, or import each CSV via *Table Editor → Import data*. JSON backups are a safety copy; restoring from them needs a developer's help.
4. **Moving to another host:** copy the website files anywhere that serves static files; keep the same Supabase project (or restore a dump into a new one and update the two keys in `index.html`).

## PART I – Test checklist
- [ ] Add a wheelchair; it appears in Equipment and on the public page.
- [ ] Register a beneficiary; search by phone finds them.
- [ ] Lend the item; the public count drops. Try lending it again – refused.
- [ ] Return it as *Needs cleaning* – still not on the public page. Set Available – it appears.
- [ ] Public page never shows names/phones/addresses. In a private window open `…/#/admin` – you are sent to login.
- [ ] Delete a test loan (confirm dialog), undo a return, check *Activity log*.
- [ ] Change a contact in Settings – public page updates, QR unchanged.
- [ ] Check the site on a phone and a laptop; print a slip and poster.

## PART J – Free limits and upkeep
- Supabase free plan: small database, and projects can **pause after about a week without activity** and have no automatic backups (check supabase.com/pricing for current terms). Log in at least weekly and keep your own backups. If paused, click *Restore project*.
- GitHub Pages free for public repos. No paid service is required.
- Keep admin passwords strong; remove staff who leave (set *Disabled* in Staff accounts).

## Troubleshooting
| Problem | Fix |
|---|---|
| "Could not load availability" | URL/key wrong in `index.html`, or `schema.sql` not run. |
| Login says not authorised | No profile row: run the insert from A4 with the right UID. |
| Photo not showing | File name must match exactly (case-sensitive) and be in `assets/equipment/`; re-upload to GitHub. |
| "relation already exists" | Use the new re-runnable `schema.sql`. |
| Site shows old version | Hard refresh (Ctrl+Shift+R) or reopen the installed app. |
| Delete loan button missing | Only admins see it. |
