-- =====================================================================
-- SÜTYEM PRO — Supabase (PostgreSQL) şeması
-- =====================================================================
-- Kaynak: lib/core/database/migrations/ (SQLite, şu an v10)
-- Bu dosyanın karşılık geldiği yerel şema sürümü: v10
--
-- GENEL KURAL: Uygulamaya yeni tablo / sütun / index eklendiğinde
-- (yeni migration yazıldığında) bu dosya AYNI commit'te güncellenir.
-- Dosyanın sonundaki "DEĞİŞİKLİK GEÇMİŞİ" bölümüne de satır eklenir.
--
-- Supabase'de çalıştırma: Dashboard → SQL Editor → bu dosyanın
-- tamamını yapıştır → Run. Dosya tekrar çalıştırılabilir (idempotent).
--
-- TASARIM NOTLARI
-- 1) Çok kullanıcı: her satırda `kullanici_id` (auth.users) var.
--    Satır Düzeyi Güvenlik (RLS) ile herkes yalnızca kendi verisini görür.
-- 2) Birincil anahtar (kullanici_id, id): telefondaki SQLite `id`
--    değerleri buluta AYNEN taşınır; iki farklı kullanıcının id'leri
--    çakışmaz. Yabancı anahtarlar da (kullanici_id, cari_id) çiftidir.
-- 3) Tarihler: SQLite'ta 'yyyy-MM-dd' metni → burada `date`.
--    Ay: 'yyyy-MM' metni → `text` + biçim kontrolü.
-- 4) Miktar/para: SQLite REAL → `numeric` (kuruş hatası olmaz).
-- 5) `_migration_log` buluta taşınmaz (cihaza özel teknik kayıt).
--    `terazi_cihazlari` cihaza özeldir; yine de yedek amaçlı tutulur.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Ortak: updated_at otomatik güncelleme
-- ---------------------------------------------------------------------
create or replace function public.updated_at_guncelle()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- cariler  (v1 + v7: aktif, not_metni)
-- ---------------------------------------------------------------------
create table if not exists public.cariler (
  kullanici_id uuid   not null default auth.uid() references auth.users (id) on delete cascade,
  id           bigint not null,
  ad           text   not null,
  soyad        text   not null,
  adres        text,
  telefon      text,
  hayvan_turu  text,
  aktif        boolean not null default true,
  not_metni    text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  primary key (kullanici_id, id)
);
create index if not exists idx_cariler_ad_soyad on public.cariler (kullanici_id, ad, soyad);

-- ---------------------------------------------------------------------
-- sutler  (v1 + v8: bir cari için günde tek satır)
-- ---------------------------------------------------------------------
create table if not exists public.sutler (
  kullanici_id uuid   not null default auth.uid() references auth.users (id) on delete cascade,
  id           bigint not null,
  cari_id      bigint not null,
  tarih        date   not null,
  sabah        numeric(10,2) not null default 0 check (sabah  >= 0 and sabah  <= 20000),
  aksam        numeric(10,2) not null default 0 check (aksam  >= 0 and aksam  <= 20000),
  toplam       numeric(10,2) not null default 0 check (toplam >= 0),
  aciklama     text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  primary key (kullanici_id, id),
  foreign key (kullanici_id, cari_id) references public.cariler (kullanici_id, id) on delete cascade,
  constraint uq_sutler_cari_tarih unique (kullanici_id, cari_id, tarih)
);
create index if not exists idx_sutler_tarih on public.sutler (kullanici_id, tarih);

-- ---------------------------------------------------------------------
-- yemler  (v1) — aynı güne birden çok teslimat olabilir (bilinçli)
-- ---------------------------------------------------------------------
create table if not exists public.yemler (
  kullanici_id uuid   not null default auth.uid() references auth.users (id) on delete cascade,
  id           bigint not null,
  cari_id      bigint not null,
  tarih        date   not null,
  sut_yemi     numeric(10,2) not null default 0 check (sut_yemi    >= 0),
  besi_yemi    numeric(10,2) not null default 0 check (besi_yemi   >= 0),
  b_baslangic  numeric(10,2) not null default 0 check (b_baslangic >= 0),
  b_buyutme    numeric(10,2) not null default 0 check (b_buyutme   >= 0),
  kuzu_yemi    numeric(10,2) not null default 0 check (kuzu_yemi   >= 0),
  tavuk_yemi   numeric(10,2) not null default 0 check (tavuk_yemi  >= 0),
  toplam       numeric(10,2) not null default 0 check (toplam      >= 0),
  aciklama     text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  primary key (kullanici_id, id),
  foreign key (kullanici_id, cari_id) references public.cariler (kullanici_id, id) on delete cascade
);
create index if not exists idx_yemler_cari_tarih on public.yemler (kullanici_id, cari_id, tarih);
create index if not exists idx_yemler_tarih on public.yemler (kullanici_id, tarih);

-- ---------------------------------------------------------------------
-- fiyatlar  (v1) — eski, cariye bağlı olmayan genel fiyat geçmişi
-- ---------------------------------------------------------------------
create table if not exists public.fiyatlar (
  kullanici_id uuid   not null default auth.uid() references auth.users (id) on delete cascade,
  id           bigint not null,
  urun_turu    text   not null,
  birim_fiyat  numeric(12,4) not null default 0 check (birim_fiyat >= 0),
  tarih        date   not null,
  aciklama     text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  primary key (kullanici_id, id)
);
create index if not exists idx_fiyatlar_urun_tarih on public.fiyatlar (kullanici_id, urun_turu, tarih);

-- ---------------------------------------------------------------------
-- cari_odemeler  (v2 + v3: detay_json + v7: vade_tarihi)
-- islem_turu: 'odeme' | 'tahsilat'  (eski kayıtlarda 'alim','sut','yem')
-- bakiye = (süt + tahsilat) − (yem + ödeme)
-- ---------------------------------------------------------------------
create table if not exists public.cari_odemeler (
  kullanici_id uuid   not null default auth.uid() references auth.users (id) on delete cascade,
  id           bigint not null,
  cari_id      bigint not null,
  tarih        date   not null,
  islem_turu   text   not null check (islem_turu in ('odeme','tahsilat','alim','sut','yem')),
  miktar       numeric(12,2) not null default 0,
  birim_fiyat  numeric(12,4) not null default 0,
  toplam_tutar numeric(14,2) not null default 0,
  odenen_tutar numeric(14,2) default 0,
  kalan_tutar  numeric(14,2) default 0,
  aciklama     text,
  detay_json   jsonb,
  vade_tarihi  date,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  primary key (kullanici_id, id),
  foreign key (kullanici_id, cari_id) references public.cariler (kullanici_id, id) on delete cascade
);
create index if not exists idx_odemeler_cari_tarih  on public.cari_odemeler (kullanici_id, cari_id, tarih);
create index if not exists idx_odemeler_islem_turu  on public.cari_odemeler (kullanici_id, islem_turu);
create index if not exists idx_odemeler_tarih       on public.cari_odemeler (kullanici_id, tarih);

-- ---------------------------------------------------------------------
-- cari_fiyatlar  (v3) — cari bazlı aylık fiyat; o ay yoksa önceki ay geçerli
-- ---------------------------------------------------------------------
create table if not exists public.cari_fiyatlar (
  kullanici_id      uuid   not null default auth.uid() references auth.users (id) on delete cascade,
  id                bigint not null,
  cari_id           bigint not null,
  ay                text   not null check (ay ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  sut_fiyat         numeric(12,4) not null default 0 check (sut_fiyat         >= 0),
  sut_yemi_fiyat    numeric(12,4) not null default 0 check (sut_yemi_fiyat    >= 0),
  besi_yemi_fiyat   numeric(12,4) not null default 0 check (besi_yemi_fiyat   >= 0),
  b_baslangic_fiyat numeric(12,4) not null default 0 check (b_baslangic_fiyat >= 0),
  b_buyutme_fiyat   numeric(12,4) not null default 0 check (b_buyutme_fiyat   >= 0),
  kuzu_yemi_fiyat   numeric(12,4) not null default 0 check (kuzu_yemi_fiyat   >= 0),
  tavuk_yemi_fiyat  numeric(12,4) not null default 0 check (tavuk_yemi_fiyat  >= 0),
  primary key (kullanici_id, id),
  foreign key (kullanici_id, cari_id) references public.cariler (kullanici_id, id) on delete cascade,
  unique (kullanici_id, cari_id, ay)
);
create index if not exists idx_cari_fiyatlar_ay on public.cari_fiyatlar (kullanici_id, ay);

-- ---------------------------------------------------------------------
-- terazi_cihazlari  (v5) — cihaza özel, yedek amaçlı
-- ---------------------------------------------------------------------
create table if not exists public.terazi_cihazlari (
  kullanici_id        uuid   not null default auth.uid() references auth.users (id) on delete cascade,
  id                  bigint not null,
  cihaz_adi           text   not null,
  cihaz_adresi        text   not null,
  baglanti_turu       text   not null check (baglanti_turu in ('ble','classic','wifi')),
  port                integer,
  varsayilan          boolean not null default false,
  son_baglanti_tarihi timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  primary key (kullanici_id, id),
  unique (kullanici_id, cihaz_adresi, baglanti_turu)
);

-- ---------------------------------------------------------------------
-- islem_gecmisi  (v6) — denetim izi; islem: ekle | guncelle | sil | birlestir
-- ---------------------------------------------------------------------
create table if not exists public.islem_gecmisi (
  kullanici_id uuid   not null default auth.uid() references auth.users (id) on delete cascade,
  id           bigint not null,
  tablo_adi    text   not null,
  kayit_id     bigint not null,
  islem        text   not null check (islem in ('ekle','guncelle','sil','birlestir')),
  onceki_deger jsonb,
  yeni_deger   jsonb,
  tarih        timestamptz not null default now(),
  primary key (kullanici_id, id)
);
create index if not exists idx_islem_gecmisi_tablo on public.islem_gecmisi (kullanici_id, tablo_adi, kayit_id);

-- ---------------------------------------------------------------------
-- donemler  (v9) — aylık dönem; durum: acik | kapali
-- ---------------------------------------------------------------------
create table if not exists public.donemler (
  kullanici_id   uuid   not null default auth.uid() references auth.users (id) on delete cascade,
  id             bigint not null,
  ay             text   not null check (ay ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  durum          text   not null default 'acik' check (durum in ('acik','kapali')),
  kapanis_tarihi timestamptz,
  acilis_sayisi  integer not null default 0,
  aciklama       text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  primary key (kullanici_id, id),
  unique (kullanici_id, ay)
);

-- ---------------------------------------------------------------------
-- donem_hakedisleri  (v9) — kapanış anındaki bordro (dondurulmuş)
-- donem_sonu = devir + (sut_tutar + tahsilat) − (yem_tutar + odeme)
-- ---------------------------------------------------------------------
create table if not exists public.donem_hakedisleri (
  kullanici_id uuid   not null default auth.uid() references auth.users (id) on delete cascade,
  id           bigint not null,
  donem_id     bigint not null,
  cari_id      bigint not null,
  devir        numeric(14,2) not null default 0,
  sut_kg       numeric(12,2) not null default 0,
  sut_fiyat    numeric(12,4) not null default 0,
  sut_tutar    numeric(14,2) not null default 0,
  yem_kg       numeric(12,2) not null default 0,
  yem_tutar    numeric(14,2) not null default 0,
  odeme        numeric(14,2) not null default 0,
  tahsilat     numeric(14,2) not null default 0,
  donem_sonu   numeric(14,2) not null default 0,
  created_at   timestamptz not null default now(),
  primary key (kullanici_id, id),
  foreign key (kullanici_id, donem_id) references public.donemler (kullanici_id, id) on delete cascade,
  foreign key (kullanici_id, cari_id)  references public.cariler  (kullanici_id, id) on delete cascade,
  unique (kullanici_id, donem_id, cari_id)
);

-- ---------------------------------------------------------------------
-- Kapalı dönem kilidi (v9): kapalı aya ait süt / yem / ödeme / fiyat
-- satırı eklenemez, değiştirilemez, silinemez. Hata metni: DONEM_KAPALI
-- ---------------------------------------------------------------------
create or replace function public.donem_kapali_mi(p_kullanici uuid, p_ay text)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1 from public.donemler d
    where d.kullanici_id = p_kullanici and d.ay = p_ay and d.durum = 'kapali'
  );
$$;

create or replace function public.donem_kilidi()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  eski_ay text;
  yeni_ay text;
begin
  if TG_TABLE_NAME = 'cari_fiyatlar' then
    if TG_OP <> 'INSERT' then eski_ay := old.ay; end if;
    if TG_OP <> 'DELETE' then yeni_ay := new.ay; end if;
  else
    if TG_OP <> 'INSERT' then eski_ay := to_char(old.tarih, 'YYYY-MM'); end if;
    if TG_OP <> 'DELETE' then yeni_ay := to_char(new.tarih, 'YYYY-MM'); end if;
  end if;

  if (eski_ay is not null and public.donem_kapali_mi(old.kullanici_id, eski_ay))
     or (yeni_ay is not null and public.donem_kapali_mi(new.kullanici_id, yeni_ay)) then
    raise exception 'DONEM_KAPALI';
  end if;

  if TG_OP = 'DELETE' then return old; end if;
  return new;
end;
$$;

create or replace function public.donem_bordrosu_kilidi()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (select 1 from public.donemler d
             where d.kullanici_id = old.kullanici_id and d.id = old.donem_id and d.durum = 'kapali') then
    raise exception 'DONEM_KAPALI';
  end if;
  return old;
end;
$$;

do $$
declare t text;
begin
  foreach t in array array['sutler','yemler','cari_odemeler','cari_fiyatlar']
  loop
    execute format('drop trigger if exists trg_%1$s_donem_kilidi on public.%1$I', t);
    execute format(
      'create trigger trg_%1$s_donem_kilidi before insert or update or delete on public.%1$I
         for each row execute function public.donem_kilidi()', t);
  end loop;
end $$;

drop trigger if exists trg_donem_hakedisleri_sil on public.donem_hakedisleri;
create trigger trg_donem_hakedisleri_sil before delete on public.donem_hakedisleri
  for each row execute function public.donem_bordrosu_kilidi();

-- ---------------------------------------------------------------------
-- updated_at tetikleyicileri
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['cariler','sutler','yemler','fiyatlar','cari_odemeler','terazi_cihazlari','donemler']
  loop
    execute format('drop trigger if exists trg_%1$s_updated_at on public.%1$I', t);
    execute format(
      'create trigger trg_%1$s_updated_at before update on public.%1$I
         for each row execute function public.updated_at_guncelle()', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Satır Düzeyi Güvenlik (RLS): herkes yalnızca kendi satırları
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['cariler','sutler','yemler','fiyatlar','cari_odemeler',
                           'cari_fiyatlar','terazi_cihazlari','islem_gecmisi',
                           'donemler','donem_hakedisleri']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %1$s_sahibi on public.%1$I', t);
    execute format(
      'create policy %1$s_sahibi on public.%1$I
         for all to authenticated
         using (kullanici_id = (select auth.uid()))
         with check (kullanici_id = (select auth.uid()))', t);
  end loop;
end $$;

-- =====================================================================
-- DEĞİŞİKLİK GEÇMİŞİ (yerel migration ↔ bu dosya)
-- =====================================================================
-- v1  cariler, sutler, yemler, fiyatlar
-- v2  cari_odemeler
-- v3  cari_fiyatlar, cari_odemeler.detay_json
-- v4  indexler
-- v5  terazi_cihazlari
-- v6  islem_gecmisi
-- v7  cariler.aktif, cariler.not_metni, cari_odemeler.vade_tarihi
-- v8  sutler UNIQUE (cari_id, tarih); tarihler yyyy-MM-dd
-- v9  donemler, donem_hakedisleri, kapalı dönem kilidi (DONEM_KAPALI)
-- v10 tarih indeksleri: sutler(tarih) [zaten vardı], yemler(tarih), cari_odemeler(tarih)
-- 2026-11-04  Dosya ilk kez oluşturuldu (yerel şema v8).
-- 2026-11-04  v9 eklendi (dönem kapanışı / hakediş).
-- =====================================================================
