-- =============================================================================
-- The Trellis — 016_feedback_and_dna_propagation.sql
-- =============================================================================
-- (015 is the demo-code migration applied separately; 017 is the calendar
-- availability migration.)
--
--   A. feedback_submissions — durable record behind the submit-feedback Edge
--      Function, so a note is never lost to an email-provider problem and the
--      function can throttle per user. Service-role only.
--
--   B. DNA Rhythm propagation. Until now a new DNA Rhythm reached only the
--      Runners who redeemed the church's code AFTER it was created
--      (redeem_church_code copies the church's rhythms at join time). A rhythm
--      a Cloud admin adds today now lands on every current member's Rule of
--      Life in the same transaction, and is also backfilled for members who
--      joined before any existing rhythm. (Edits already propagate — 012 — and
--      so do members who join later — redeem_church_code.)
-- =============================================================================


-- -----------------------------------------------------------------------------
-- A. feedback_submissions
-- -----------------------------------------------------------------------------
create table if not exists public.feedback_submissions (
  id            uuid primary key default gen_random_uuid(),
  -- For throttling and abuse control only; never put in the email. Deleted with
  -- the account.
  user_id       uuid not null references public.profiles (id) on delete cascade,
  rating        smallint not null check (rating between 1 and 5),
  category      text not null check (category in ('bug', 'spiritual_flow_content', 'ui_usability')),
  message       text not null check (char_length(message) between 1 and 4000),
  reply_ok      boolean not null default false,
  platform      text,
  role_view     text,
  email_status  text not null default 'pending' check (email_status in ('pending', 'sent', 'failed')),
  email_error   text,
  created_at    timestamptz not null default now()
);
comment on table public.feedback_submissions is
  'Written only by the submit-feedback Edge Function (service role). email_status '
  'records whether the email to support went out; a failed row still holds the note.';

create index if not exists feedback_submissions_user_idx
  on public.feedback_submissions (user_id, created_at desc);

alter table public.feedback_submissions enable row level security;
revoke all on public.feedback_submissions from authenticated, anon;
-- Deliberately no policies: no client can read or write this table.


-- -----------------------------------------------------------------------------
-- B. Push a new DNA Rhythm to every current member
-- -----------------------------------------------------------------------------
-- Applies one church rhythm to every member of that church who doesn't have it
-- yet, and returns how many members were touched. Idempotent — safe to run
-- twice, which is what lets the backfill below reuse it.
--
--   * A member who already has a PERSONAL rhythm with the same title (ignoring
--     case/spacing) adopts the church's version in place: it becomes mandated
--     and takes the church's category and schedule, and keeps its id — so its
--     check-in history and season score carry over, and they don't end up with
--     two copies of the same habit. (Their Anchor flag is left as they set it.)
--   * Everyone else gets a new mandated rhythm. Under the fair-start rule it is
--     unscored until their first check-in on it, so a rhythm landing today
--     can't drag anyone's score down.
create or replace function public.apply_dna_rhythm_to_members(
  p_church_id   uuid,
  p_title       text,
  p_category    public.rule_category,
  p_frequency   public.rule_frequency,
  p_weekly_days smallint[]
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_adopted integer := 0;
  v_added   integer := 0;
begin
  update public.rule_items ri
     set is_church_mandated = true,
         title       = p_title,
         category    = p_category,
         frequency   = p_frequency,
         weekly_days = p_weekly_days
    from public.profiles p
   where ri.runner_id = p.id
     and p.church_id = p_church_id
     and not ri.is_church_mandated
     and lower(trim(ri.title)) = lower(trim(p_title));
  get diagnostics v_adopted = row_count;

  insert into public.rule_items
    (runner_id, category, title, frequency, weekly_days, is_church_mandated)
  select p.id, p_category, p_title, p_frequency, p_weekly_days, true
    from public.profiles p
   where p.church_id = p_church_id
     and not exists (
       select 1 from public.rule_items ri
        where ri.runner_id = p.id
          and ri.is_church_mandated
          and lower(trim(ri.title)) = lower(trim(p_title))
     );
  get diagnostics v_added = row_count;

  return v_adopted + v_added;
end;
$$;

revoke execute on function public.apply_dna_rhythm_to_members(uuid, text, public.rule_category, public.rule_frequency, smallint[])
  from public, anon, authenticated;

create or replace function public.propagate_new_dna_rhythm()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- AFTER INSERT, so NEW already carries the days chosen by 012's normalizer
  -- (a weekly rhythm always has at least one).
  perform public.apply_dna_rhythm_to_members(
    new.church_id, new.title, new.category, new.frequency, new.weekly_days
  );
  return new;
end;
$$;

drop trigger if exists dna_rhythms_propagate_new on public.dna_rhythms;
create trigger dna_rhythms_propagate_new
  after insert on public.dna_rhythms
  for each row execute function public.propagate_new_dna_rhythm();

-- One-time backfill: bring every existing member up to date with every DNA
-- Rhythm their church already has. Safe to re-run.
select public.apply_dna_rhythm_to_members(
         church_id, title, category, frequency, weekly_days
       )
  from public.dna_rhythms;


-- =============================================================================
-- Verification (SQL editor, dev branch)
-- =============================================================================
-- A. Feedback
--    select email_status, count(*) from feedback_submissions group by 1;
--    -- as authenticated: select * from feedback_submissions;   -- permission denied
--
-- B. Propagation
--    -- Pick a church that has 2+ members, then as the SQL owner:
--    insert into dna_rhythms (church_id, title, category, frequency, weekly_days)
--    values ('<church-uuid>', 'Corporate Worship', 'community_hospitality', 'weekly', '{7}');
--    -- every member now has it:
--    select p.name, ri.title, ri.is_church_mandated, ri.weekly_days
--      from profiles p
--      join rule_items ri on ri.runner_id = p.id and ri.title = 'Corporate Worship'
--     where p.church_id = '<church-uuid>';
--    -- re-adding is idempotent (no duplicates):
--    select apply_dna_rhythm_to_members('<church-uuid>', 'Corporate Worship',
--           'community_hospitality', 'weekly', '{7}');          -- 0
--    -- a member with a personal rhythm of the same name keeps ONE row (now mandated):
--    select count(*) from rule_items where runner_id = '<member-uuid>'
--       and lower(title) = 'corporate worship';                  -- 1
-- =============================================================================
