create table if not exists public.dealer_threads (
  id uuid primary key default gen_random_uuid(),
  farmer_id uuid not null references auth.users(id) on delete cascade,
  dealer_id uuid not null references auth.users(id) on delete cascade,
  disease_name text not null,
  recommended_drugs text not null,
  diagnosis_image_path text,
  last_message text default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.dealer_messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.dealer_threads(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  receiver_id uuid not null references auth.users(id) on delete cascade,
  message text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

alter table public.dealer_messages
  add column if not exists read_at timestamptz;

alter table public.profiles
  add column if not exists full_name text;

alter table public.profiles
  add column if not exists owner_name text;

alter table public.profiles
  add column if not exists business_name text;

alter table public.profiles
  add column if not exists role text default 'farmer';

alter table public.profiles
  add column if not exists phone_number text;

alter table public.profiles
  add column if not exists district text;

alter table public.profiles
  add column if not exists open_hours text;

alter table public.profiles
  add column if not exists delivery_options text[] default '{}';

alter table public.profiles
  add column if not exists available_drugs text[] default '{}';

alter table public.profiles
  add column if not exists expertise text[] default '{}';

alter table public.dealer_threads enable row level security;
alter table public.dealer_messages enable row level security;

drop policy if exists "dealer_threads participants can read"
on public.dealer_threads;

create policy "dealer_threads participants can read"
on public.dealer_threads
for select
using (auth.uid() = farmer_id or auth.uid() = dealer_id);

drop policy if exists "farmers create dealer threads"
on public.dealer_threads;

create policy "farmers create dealer threads"
on public.dealer_threads
for insert
with check (auth.uid() = farmer_id);

drop policy if exists "participants update their threads"
on public.dealer_threads;

create policy "participants update their threads"
on public.dealer_threads
for update
using (auth.uid() = farmer_id or auth.uid() = dealer_id);

drop policy if exists "participants read messages"
on public.dealer_messages;

create policy "participants read messages"
on public.dealer_messages
for select
using (
  exists (
    select 1
    from public.dealer_threads t
    where t.id = thread_id
      and (t.farmer_id = auth.uid() or t.dealer_id = auth.uid())
  )
);

drop policy if exists "participants send messages"
on public.dealer_messages;

create policy "participants send messages"
on public.dealer_messages
for insert
with check (
  auth.uid() = sender_id
  and exists (
    select 1
    from public.dealer_threads t
    where t.id = thread_id
      and (t.farmer_id = auth.uid() or t.dealer_id = auth.uid())
  )
);

drop policy if exists "receivers mark messages as read"
on public.dealer_messages;

create policy "receivers mark messages as read"
on public.dealer_messages
for update
using (auth.uid() = receiver_id)
with check (auth.uid() = receiver_id);

insert into storage.buckets (id, name, public)
values ('diagnosis-images', 'diagnosis-images', false)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('profile-images', 'profile-images', false)
on conflict (id) do nothing;

drop policy if exists "profile images read own"
on storage.objects;

create policy "profile images read own"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'profile-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "profile images upload own"
on storage.objects;

create policy "profile images upload own"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'profile-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "profile images update own"
on storage.objects;

create policy "profile images update own"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'profile-images'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'profile-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "diagnosis images upload own"
on storage.objects;

create policy "diagnosis images upload own"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'diagnosis-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "diagnosis images thread participants read"
on storage.objects;

create policy "diagnosis images thread participants read"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'diagnosis-images'
  and exists (
    select 1
    from public.dealer_threads t
    where t.diagnosis_image_path = name
      and (t.farmer_id = auth.uid() or t.dealer_id = auth.uid())
  )
);
