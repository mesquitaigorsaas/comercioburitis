-- =====================================================================
-- Guia Comercial Buritis e Região — estrutura do banco
--
-- Rode este arquivo inteiro no SQL Editor do Supabase, uma vez só,
-- num projeto novo e vazio.
--
-- Ele cria:
--   1. a tabela de anúncios (uma loja por anunciante)
--   2. as regras de segurança (quem pode ler, criar e alterar o quê)
--   3. as duas funções de contagem (visualizações e cliques no zap)
--   4. o depósito de imagens (logos e fotos das lojas)
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. A TABELA
--
-- Uma linha = uma loja anunciando no guia.
-- ---------------------------------------------------------------------
create table if not exists public.anuncios (
    id uuid primary key default gen_random_uuid(),

    -- Dono do anúncio. Se a conta for apagada, o anúncio vai junto.
    -- O "unique" é a regra de negócio: cada anunciante tem uma loja só.
    -- O site já avisa isso na tela, mas quem garante é o banco.
    user_id uuid not null unique references auth.users(id) on delete cascade,

    -- Identificação da loja
    titulo text not null,
    categoria text not null,
    descricao text,

    -- Cidade fica sempre em minúsculas: é assim que o formulário grava
    -- e é assim que a busca da página inicial procura. Sem isso,
    -- "Belo Horizonte" e "belo horizonte" seriam duas cidades diferentes.
    cidade text not null,

    -- Contato e endereço
    endereco text,
    telefone text,
    whatsapp text,
    instagram text,
    site text,

    -- Horário de funcionamento, um dia da semana por chave:
    -- {"segunda": {"aberto": true, "abre": "08:00", "fecha": "18:00"}}
    horarios jsonb not null default '{}'::jsonb,

    -- Logomarca e galeria. Aqui ficam só os endereços das imagens —
    -- os arquivos moram no depósito criado na parte 4.
    imagem_url text,
    fotos text[] not null default '{}',

    status text not null default 'ABERTO AGORA',

    -- Plano contratado: trimestral, semestral ou anual.
    -- É ele que vai definir quantas fotos a loja pode ter.
    plano text,

    -- Contadores. Nunca são escritos direto pelo site: só pelas
    -- funções da parte 3.
    visualizacoes integer not null default 0,
    cliques_whatsapp integer not null default 0,

    criado_em timestamptz not null default now(),
    atualizado_em timestamptz not null default now()
);

-- A página inicial filtra por cidade e por categoria. Sem estes índices
-- o banco leria a tabela inteira a cada busca.
create index if not exists anuncios_cidade_idx on public.anuncios (cidade);
create index if not exists anuncios_categoria_idx on public.anuncios (categoria);


-- Mantém "atualizado_em" em dia sozinho, sem o site precisar lembrar.
create or replace function public.tocar_atualizado_em()
returns trigger
language plpgsql
as $funcao$
begin
    new.atualizado_em = now();
    return new;
end;
$funcao$;

drop trigger if exists trg_anuncios_atualizado_em on public.anuncios;
create trigger trg_anuncios_atualizado_em
    before update on public.anuncios
    for each row execute function public.tocar_atualizado_em();


-- ---------------------------------------------------------------------
-- 2. SEGURANÇA
--
-- Com RLS ligado, ninguém enxerga nem mexe em nada por padrão. O que
-- vale é só o que estiver escrito abaixo.
-- ---------------------------------------------------------------------
alter table public.anuncios enable row level security;

-- LER: qualquer visitante, sem login. É um guia comercial — os
-- anúncios existem justamente para serem vistos por quem passa.
drop policy if exists "anuncios sao publicos" on public.anuncios;
create policy "anuncios sao publicos"
    on public.anuncios for select
    to anon, authenticated
    using (true);

-- CRIAR: só quem está logado, e só em nome de si mesmo. O
-- "user_id = auth.uid()" impede alguém de cadastrar uma loja no nome
-- de outra pessoa.
drop policy if exists "anunciante cria a propria loja" on public.anuncios;
create policy "anunciante cria a propria loja"
    on public.anuncios for insert
    to authenticated
    with check (user_id = auth.uid());

-- ALTERAR: só o dono, e ele continua sendo o dono depois. O "using"
-- diz quais linhas ele alcança; o "with check" impede que ele passe a
-- loja para outra conta na hora de salvar.
drop policy if exists "anunciante edita a propria loja" on public.anuncios;
create policy "anunciante edita a propria loja"
    on public.anuncios for update
    to authenticated
    using (user_id = auth.uid())
    with check (user_id = auth.uid());

-- APAGAR: só o dono.
drop policy if exists "anunciante apaga a propria loja" on public.anuncios;
create policy "anunciante apaga a propria loja"
    on public.anuncios for delete
    to authenticated
    using (user_id = auth.uid());


-- ---------------------------------------------------------------------
-- 3. OS CONTADORES
--
-- A página de detalhes precisa somar 1 nas visualizações e nos cliques
-- do WhatsApp — e quem visita não está logado.
--
-- Dar permissão de alteração ao visitante resolveria, mas abriria a
-- porta para qualquer um reescrever qualquer anúncio. Então o visitante
-- não altera nada: ele chama uma destas funções, que sabem fazer uma
-- coisa só e não deixam tocar em mais nada.
--
-- Somar dentro do banco (visualizacoes + 1) também evita perder
-- contagem quando duas pessoas abrem a mesma página no mesmo segundo.
-- ---------------------------------------------------------------------
create or replace function public.registrar_visualizacao(p_anuncio uuid)
returns void
language sql
security definer
set search_path = public
as $funcao$
    update public.anuncios
       set visualizacoes = visualizacoes + 1
     where id = p_anuncio;
$funcao$;

create or replace function public.registrar_clique_whatsapp(p_anuncio uuid)
returns void
language sql
security definer
set search_path = public
as $funcao$
    update public.anuncios
       set cliques_whatsapp = cliques_whatsapp + 1
     where id = p_anuncio;
$funcao$;

grant execute on function public.registrar_visualizacao(uuid) to anon, authenticated;
grant execute on function public.registrar_clique_whatsapp(uuid) to anon, authenticated;


-- ---------------------------------------------------------------------
-- 4. O DEPÓSITO DE IMAGENS
--
-- Um balde chamado "anuncios", com duas pastas por dentro:
-- logos/ e fotos/. Público na leitura, porque as imagens aparecem
-- para quem visita o guia sem ter conta.
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('anuncios', 'anuncios', true)
on conflict (id) do update set public = true;

-- VER as imagens: qualquer um.
drop policy if exists "imagens de anuncios sao publicas" on storage.objects;
create policy "imagens de anuncios sao publicas"
    on storage.objects for select
    to anon, authenticated
    using (bucket_id = 'anuncios');

-- ENVIAR imagem: só quem está logado.
drop policy if exists "anunciante envia imagem" on storage.objects;
create policy "anunciante envia imagem"
    on storage.objects for insert
    to authenticated
    with check (bucket_id = 'anuncios');

-- TROCAR ou APAGAR imagem: só quem enviou aquele arquivo.
drop policy if exists "anunciante troca a propria imagem" on storage.objects;
create policy "anunciante troca a propria imagem"
    on storage.objects for update
    to authenticated
    using (bucket_id = 'anuncios' and owner = auth.uid());

drop policy if exists "anunciante apaga a propria imagem" on storage.objects;
create policy "anunciante apaga a propria imagem"
    on storage.objects for delete
    to authenticated
    using (bucket_id = 'anuncios' and owner = auth.uid());
