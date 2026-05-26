create extension if not exists pgcrypto;

create or replace function public.handle_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  owner_name text,
  business_name text,
  email text,
  role text not null default 'farmer',
  preferred_language text default 'en',
  phone_number text,
  district text,
  open_hours text,
  delivery_options text[] not null default '{}',
  available_drugs text[] not null default '{}',
  expertise text[] not null default '{}',
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles
  add column if not exists full_name text,
  add column if not exists owner_name text,
  add column if not exists business_name text,
  add column if not exists email text,
  add column if not exists role text default 'farmer',
  add column if not exists preferred_language text default 'en',
  add column if not exists phone_number text,
  add column if not exists district text,
  add column if not exists open_hours text,
  add column if not exists delivery_options text[] default '{}',
  add column if not exists available_drugs text[] default '{}',
  add column if not exists expertise text[] default '{}',
  add column if not exists avatar_url text,
  add column if not exists created_at timestamptz default now(),
  add column if not exists updated_at timestamptz default now();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (
    id,
    full_name,
    owner_name,
    business_name,
    email,
    role,
    preferred_language,
    phone_number,
    district,
    open_hours,
    delivery_options,
    available_drugs,
    expertise
  )
  values (
    new.id,
    new.raw_user_meta_data ->> 'full_name',
    coalesce(
      new.raw_user_meta_data ->> 'owner_name',
      new.raw_user_meta_data ->> 'full_name'
    ),
    coalesce(
      new.raw_user_meta_data ->> 'business_name',
      new.raw_user_meta_data ->> 'full_name'
    ),
    new.email,
    coalesce(new.raw_user_meta_data ->> 'role', 'farmer'),
    coalesce(new.raw_user_meta_data ->> 'preferred_language', 'en'),
    new.raw_user_meta_data ->> 'phone_number',
    new.raw_user_meta_data ->> 'district',
    new.raw_user_meta_data ->> 'open_hours',
    coalesce(
      (
        select array_agg(value)
        from jsonb_array_elements_text(
          coalesce(new.raw_user_meta_data -> 'delivery_options', '[]'::jsonb)
        ) as value
      ),
      '{}'::text[]
    ),
    coalesce(
      (
        select array_agg(value)
        from jsonb_array_elements_text(
          coalesce(new.raw_user_meta_data -> 'available_drugs', '[]'::jsonb)
        ) as value
      ),
      '{}'::text[]
    ),
    coalesce(
      (
        select array_agg(value)
        from jsonb_array_elements_text(
          coalesce(new.raw_user_meta_data -> 'expertise', '[]'::jsonb)
        ) as value
      ),
      '{}'::text[]
    )
  )
  on conflict (id) do update
  set
    full_name = excluded.full_name,
    owner_name = excluded.owner_name,
    business_name = excluded.business_name,
    email = excluded.email,
    role = excluded.role,
    preferred_language = excluded.preferred_language,
    phone_number = excluded.phone_number,
    district = excluded.district,
    open_hours = excluded.open_hours,
    delivery_options = excluded.delivery_options,
    available_drugs = excluded.available_drugs,
    expertise = excluded.expertise,
    updated_at = now();

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

drop trigger if exists profiles_set_updated_at on public.profiles;

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute procedure public.handle_updated_at();

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

create index if not exists idx_profiles_role on public.profiles(role);
create index if not exists idx_dealer_threads_farmer_id on public.dealer_threads(farmer_id);
create index if not exists idx_dealer_threads_dealer_id on public.dealer_threads(dealer_id);
create index if not exists idx_dealer_threads_updated_at on public.dealer_threads(updated_at desc);
create index if not exists idx_dealer_messages_thread_id on public.dealer_messages(thread_id);
create index if not exists idx_dealer_messages_created_at on public.dealer_messages(created_at);
create index if not exists idx_dealer_messages_receiver_read_at
on public.dealer_messages(receiver_id, read_at);

drop trigger if exists dealer_threads_set_updated_at on public.dealer_threads;

create trigger dealer_threads_set_updated_at
before update on public.dealer_threads
for each row execute procedure public.handle_updated_at();

alter table public.profiles enable row level security;
alter table public.dealer_threads enable row level security;
alter table public.dealer_messages enable row level security;

drop policy if exists "users read own profile" on public.profiles;
create policy "users read own profile"
on public.profiles
for select
to authenticated
using (auth.uid() = id);

drop policy if exists "users insert own profile" on public.profiles;
create policy "users insert own profile"
on public.profiles
for insert
to authenticated
with check (auth.uid() = id);

drop policy if exists "users update own profile" on public.profiles;
create policy "users update own profile"
on public.profiles
for update
to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);

drop policy if exists "authenticated users read dealer profiles" on public.profiles;
create policy "authenticated users read dealer profiles"
on public.profiles
for select
to authenticated
using (role = 'dealer');

drop policy if exists "dealer_threads participants can read" on public.dealer_threads;
create policy "dealer_threads participants can read"
on public.dealer_threads
for select
to authenticated
using (auth.uid() = farmer_id or auth.uid() = dealer_id);

drop policy if exists "farmers create dealer threads" on public.dealer_threads;
create policy "farmers create dealer threads"
on public.dealer_threads
for insert
to authenticated
with check (auth.uid() = farmer_id);

drop policy if exists "participants update their threads" on public.dealer_threads;
create policy "participants update their threads"
on public.dealer_threads
for update
to authenticated
using (auth.uid() = farmer_id or auth.uid() = dealer_id)
with check (auth.uid() = farmer_id or auth.uid() = dealer_id);

drop policy if exists "participants read messages" on public.dealer_messages;
create policy "participants read messages"
on public.dealer_messages
for select
to authenticated
using (
  exists (
    select 1
    from public.dealer_threads t
    where t.id = thread_id
      and (t.farmer_id = auth.uid() or t.dealer_id = auth.uid())
  )
);

drop policy if exists "participants send messages" on public.dealer_messages;
create policy "participants send messages"
on public.dealer_messages
for insert
to authenticated
with check (
  auth.uid() = sender_id
  and exists (
    select 1
    from public.dealer_threads t
    where t.id = thread_id
      and (t.farmer_id = auth.uid() or t.dealer_id = auth.uid())
  )
);

drop policy if exists "receivers mark messages as read" on public.dealer_messages;
create policy "receivers mark messages as read"
on public.dealer_messages
for update
to authenticated
using (auth.uid() = receiver_id)
with check (auth.uid() = receiver_id);

insert into storage.buckets (id, name, public)
values
  ('profile-images', 'profile-images', false),
  ('diagnosis-images', 'diagnosis-images', false)
on conflict (id) do nothing;

drop policy if exists "authenticated users read profile images" on storage.objects;
create policy "authenticated users read profile images"
on storage.objects
for select
to authenticated
using (bucket_id = 'profile-images');

drop policy if exists "users upload own profile images" on storage.objects;
create policy "users upload own profile images"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'profile-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "users update own profile images" on storage.objects;
create policy "users update own profile images"
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

drop policy if exists "users upload own diagnosis images" on storage.objects;
create policy "users upload own diagnosis images"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'diagnosis-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "thread participants read diagnosis images" on storage.objects;
create policy "thread participants read diagnosis images"
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
