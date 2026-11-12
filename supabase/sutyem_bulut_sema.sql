-- ═════════════════════════════════════════════════════════════════════════
--  SÜT-YEM — ÇOKLU CİHAZ BULUT ŞEMASI (Supabase / PostgreSQL)
-- ═════════════════════════════════════════════════════════════════════════
--  Bu bulut market ve fırın uygulamalarından AYRIDIR: kendi Supabase projesinde
--  kurulur (aynı projeye kurulsa bile tablo/fonksiyon adları "sutyem_" ile başlar,
--  hiçbir şeyle çakışmaz).
--
--  Nasıl kurulur:
--    1. supabase.com → yeni proje açın (örn. "sutyem").
--    2. Sol menü → SQL Editor → New query → bu dosyanın TAMAMINI yapıştırın → Run.
--    3. Project Settings → API (ya da "API Keys") bölümünden şunları alın:
--         • Project URL                (https://xxxx.supabase.co)
--         • anon / publishable key     (eyJ... ya da sb_publishable_...)
--    4. Uygulamada: ⋮ menü → Çoklu Cihaz ve Bulut → Bulut → URL ve anahtarı yazın,
--       işletme kodu + işletme şifresi belirleyin (diğer cihazlarda AYNISINI yazın).
--
--  NOT: supabase/supabase_sema.sql dosyası yerel şemanın tablo tablo AYNASIDIR
--  (belgeleme / ileride rapor amaçlı). Çoklu cihaz eşitlemesi için kurulacak dosya
--  BU dosyadır.
--
--  Bu dosya defalarca çalıştırılabilir (IF NOT EXISTS / CREATE OR REPLACE).
--
--  TASARIM
--  • Uygulamadaki her kayıt bulutta TEK satırdır: (işletme, tablo, anahtar).
--    "veri" sütunu kaydın tüm alanlarını JSON olarak taşır. Uygulamaya yeni
--    sütun eklense bile BURADA DEĞİŞİKLİK GEREKMEZ.
--  • "sira" her değişiklikte artan sayıdır; cihazlar "şu sıradan sonrasını ver"
--    diye çeker — saat farkından etkilenmez.
--  • Son yazan kazanır: daha ESKİ zamanlı bir değişiklik yenisinin üzerine yazamaz.
--  • Güvenlik: anon anahtar uygulamanın içinde olduğundan herkese açık sayılır.
--    Bu yüzden tablolara DOĞRUDAN erişim tamamen KAPALIDIR (RLS açık, politika yok);
--    tüm okuma/yazma, işletme kodu + şifresini doğrulayan fonksiyonlarla yapılır.
--    Şifre bulutta düz değil, SHA-256 özeti olarak durur.
-- ═════════════════════════════════════════════════════════════════════════

create extension if not exists pgcrypto with schema extensions;

-- ── İşletmeler ──────────────────────────────────────────────────────────
create table if not exists public.sutyem_isletmeler (
  kod           text primary key check (length(kod) between 3 and 64),
  sifre_ozeti   text not null,
  ad            text,
  olusturma     timestamptz not null default now()
);

-- ── Kayıtlar (her uygulama kaydının son hali) ───────────────────────────
create sequence if not exists public.sutyem_sira;

create table if not exists public.sutyem_kayitlar (
  isletme   text   not null references public.sutyem_isletmeler(kod) on delete cascade,
  tablo     text   not null,
  anahtar   text   not null,
  veri      jsonb,                          -- silinmiş kayıtta boş
  silindi   boolean not null default false,
  -- "C" sıralaması: karşılaştırma bayt sırasıyla (cihazdaki SQLite ile AYNI sonuç).
  zaman     text collate "C" not null,      -- değişikliğin cihazdaki anı (UTC ISO)
  cihaz     text collate "C" not null,      -- değişikliği yapan cihaz
  sira      bigint not null default nextval('public.sutyem_sira'),
  sunucu_zamani timestamptz not null default now(),
  primary key (isletme, tablo, anahtar)
);
create index if not exists sutyem_kayitlar_sira on public.sutyem_kayitlar (isletme, sira);

-- ── Cihazlar (kim, en son ne zaman eşitledi) ────────────────────────────
create table if not exists public.sutyem_cihazlar (
  isletme     text not null references public.sutyem_isletmeler(kod) on delete cascade,
  cihaz       text not null,
  ad          text,
  son_gorulme timestamptz not null default now(),
  primary key (isletme, cihaz)
);

-- Doğrudan erişim KAPALI (yalnız aşağıdaki fonksiyonlar).
alter table public.sutyem_isletmeler enable row level security;
alter table public.sutyem_kayitlar  enable row level security;
alter table public.sutyem_cihazlar  enable row level security;
revoke all on public.sutyem_isletmeler, public.sutyem_kayitlar, public.sutyem_cihazlar from anon, authenticated;

-- ── Yardımcı: işletme şifresi doğru mu? ─────────────────────────────────
create or replace function public.sutyem_dogrula(p_isletme text, p_sifre text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not exists (
    select 1 from public.sutyem_isletmeler
     where kod = p_isletme
       and sifre_ozeti = encode(extensions.digest(p_sifre, 'sha256'), 'hex')
  ) then
    raise exception 'SUTYEM_YETKISIZ: işletme kodu veya şifresi hatalı' using errcode = '28000';
  end if;
end $$;

-- ── İşletme kur / bağlan ─────────────────────────────────────────────────
-- Kod yoksa işletmeyi bu şifreyle KURAR; varsa şifreyi doğrular.
create or replace function public.sutyem_baglan(p_isletme text, p_sifre text, p_cihaz text, p_cihaz_ad text, p_isletme_ad text default null)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare
  v_yeni boolean := false;
begin
  if length(coalesce(p_sifre, '')) < 6 then
    raise exception 'SUTYEM_SIFRE_KISA: işletme şifresi en az 6 karakter olmalı';
  end if;
  if not exists (select 1 from public.sutyem_isletmeler where kod = p_isletme) then
    insert into public.sutyem_isletmeler (kod, sifre_ozeti, ad)
    values (p_isletme, encode(extensions.digest(p_sifre, 'sha256'), 'hex'), p_isletme_ad);
    v_yeni := true;
  end if;
  perform public.sutyem_dogrula(p_isletme, p_sifre);
  insert into public.sutyem_cihazlar (isletme, cihaz, ad, son_gorulme) values (p_isletme, p_cihaz, p_cihaz_ad, now())
  on conflict (isletme, cihaz) do update set ad = excluded.ad, son_gorulme = now();
  return json_build_object(
    'yeni', v_yeni,
    'kayit_sayisi', (select count(*) from public.sutyem_kayitlar where isletme = p_isletme),
    'son_sira', (select coalesce(max(sira), 0) from public.sutyem_kayitlar where isletme = p_isletme),
    'sunucu_zamani', now()
  );
end $$;

-- ── Gönder ──────────────────────────────────────────────────────────────
-- p_kayitlar: [{ "t": tablo, "k": anahtar, "z": zaman, "c": cihaz, "s": silindi, "v": {...} }]
-- Yalnız daha YENİ (zaman, cihaz) olan değişiklik yazılır.
create or replace function public.sutyem_gonder(p_isletme text, p_sifre text, p_cihaz text, p_kayitlar jsonb)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare
  v_yazilan int := 0;
  v_k jsonb;
begin
  perform public.sutyem_dogrula(p_isletme, p_sifre);
  -- Aynı işletmenin gönderimleri SIRAYLA işlenir: "sira" numarası commit sırasıyla aynı olur.
  -- (Kilit olmasa A 100'ü alıp geç commit ederken B 101'i commit edebilir; 101'e kadar
  --  çeken cihaz 100'ü bir daha görmezdi.) Kilit işlem bitince kendiliğinden kalkar.
  perform pg_advisory_xact_lock(hashtext('sutyem_gonder:' || p_isletme));
  for v_k in select * from jsonb_array_elements(p_kayitlar) loop
    insert into public.sutyem_kayitlar as f (isletme, tablo, anahtar, veri, silindi, zaman, cihaz)
    values (p_isletme, v_k->>'t', v_k->>'k',
            case when coalesce((v_k->>'s')::boolean, false) then null else v_k->'v' end,
            coalesce((v_k->>'s')::boolean, false), v_k->>'z', coalesce(v_k->>'c', p_cihaz))
    on conflict (isletme, tablo, anahtar) do update
       set veri = excluded.veri, silindi = excluded.silindi, zaman = excluded.zaman, cihaz = excluded.cihaz,
           sira = nextval('public.sutyem_sira'), sunucu_zamani = now()
     where (excluded.zaman, excluded.cihaz) > (f.zaman, f.cihaz);
    if found then v_yazilan := v_yazilan + 1; end if;
  end loop;
  update public.sutyem_cihazlar set son_gorulme = now() where isletme = p_isletme and cihaz = p_cihaz;
  return json_build_object('yazilan', v_yazilan, 'son_sira', (select coalesce(max(sira), 0) from public.sutyem_kayitlar where isletme = p_isletme));
end $$;

-- ── Çek ─────────────────────────────────────────────────────────────────
-- p_sira'dan SONRAKİ değişiklikler (sıraya göre). Bu cihazın kendi yazdıkları hariç.
create or replace function public.sutyem_cek(p_isletme text, p_sifre text, p_cihaz text, p_sira bigint, p_limit int default 500)
returns table (t text, k text, z text, c text, s boolean, v jsonb, sira bigint)
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.sutyem_dogrula(p_isletme, p_sifre);
  return query
    select f.tablo, f.anahtar, f.zaman, f.cihaz, f.silindi, f.veri, f.sira
      from public.sutyem_kayitlar f
     where f.isletme = p_isletme and f.sira > p_sira
     order by f.sira
     limit greatest(1, least(coalesce(p_limit, 500), 2000));
end $$;

-- ── Cihaz listesi (uygulamadaki "Bağlı cihazlar") ───────────────────────
create or replace function public.sutyem_cihaz_listesi(p_isletme text, p_sifre text)
returns table (cihaz text, ad text, son_gorulme timestamptz)
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.sutyem_dogrula(p_isletme, p_sifre);
  return query select c.cihaz, c.ad, c.son_gorulme from public.sutyem_cihazlar c where c.isletme = p_isletme order by c.son_gorulme desc;
end $$;

-- Fonksiyonlar anon anahtarla çağrılabilir; tablolar çağrılamaz.
revoke all on function public.sutyem_dogrula(text, text) from public, anon, authenticated;
grant execute on function public.sutyem_baglan(text, text, text, text, text) to anon, authenticated;
grant execute on function public.sutyem_gonder(text, text, text, jsonb) to anon, authenticated;
grant execute on function public.sutyem_cek(text, text, text, bigint, int) to anon, authenticated;
grant execute on function public.sutyem_cihaz_listesi(text, text) to anon, authenticated;

-- ═════════════════════════════════════════════════════════════════════════
--  YARDIMCI SORGULAR (isteğe bağlı — SQL Editor'da tek tek çalıştırın)
-- ═════════════════════════════════════════════════════════════════════════
-- Bir işletmenin tablo bazında kayıt sayısı:
--   select tablo, count(*) filter (where not silindi) as kayit, count(*) filter (where silindi) as silinen
--     from public.sutyem_kayitlar where isletme = 'ISLETME_KODU' group by tablo order by tablo;
--
-- Cariler (okunur liste):
--   select veri->>'ad' as ad, veri->>'soyad' as soyad, veri->>'telefon' as telefon
--     from public.sutyem_kayitlar where isletme = 'ISLETME_KODU' and tablo = 'cariler' and not silindi;
--
-- Bir günün sütü (cari uuid | tarih anahtarlı):
--   select anahtar, veri->>'sabah' as sabah, veri->>'aksam' as aksam
--     from public.sutyem_kayitlar where isletme = 'ISLETME_KODU' and tablo = 'sutler'
--      and not silindi and veri->>'tarih' = '2026-11-12';
--
-- Bağlı cihazlar:
--   select * from public.sutyem_cihazlar where isletme = 'ISLETME_KODU';
--
-- İşletmenin TÜM bulut verisini silmek (geri alınamaz; telefonlardaki veri kalır):
--   delete from public.sutyem_isletmeler where kod = 'ISLETME_KODU';
