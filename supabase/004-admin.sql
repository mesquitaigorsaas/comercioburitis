-- =====================================================================
-- Painel do administrador
--
-- Rode no SQL Editor, depois dos anteriores.
--
-- Cria a noção de "administrador do guia" — que até agora não existia —
-- e o que o painel precisa: ver todos os anunciantes, mudar plano,
-- marcar destaque e tirar do ar sem apagar nada.
--
-- IMPORTANTE: no fim do arquivo tem um comando comentado para dizer
-- quem é o administrador. Sem ele, ninguém entra no painel — nem você.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. QUEM É ADMINISTRADOR
--
-- Uma tabela, e não um e-mail escrito dentro do site: o código do site
-- vai inteiro para o navegador de quem visita, então qualquer pessoa
-- leria a lista. E, mais importante, o banco não olharia para ela — as
-- regras de segurança rodam do lado de cá.
-- ---------------------------------------------------------------------
create table if not exists public.admins (
    id uuid primary key references auth.users(id) on delete cascade,
    criado_em timestamptz not null default now()
);

-- Ligada, e de propósito sem nenhuma política: assim a tabela é
-- invisível pela API do site. Só as funções abaixo enxergam, e elas
-- respondem apenas sim ou não.
alter table public.admins enable row level security;


-- "Quem está pedindo isto é administrador?"
--
-- É "security definer": roda com a permissão de quem a criou, e por
-- isso consegue ler a tabela acima mesmo estando ela fechada. É a
-- única porta para aquela informação.
create or replace function public.eh_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $funcao$
    select exists (
        select 1 from public.admins where id = auth.uid()
    );
$funcao$;

grant execute on function public.eh_admin() to authenticated;


-- ---------------------------------------------------------------------
-- 2. AS DUAS COLUNAS NOVAS DO ANÚNCIO
-- ---------------------------------------------------------------------
alter table public.anuncios
    -- Aparece antes dos outros na vitrine da página inicial. Hoje quem
    -- marca é o administrador; mais para frente é o que o anunciante
    -- compra na caixa de R$ 120 por 15 dias.
    add column if not exists destaque boolean not null default false,

    -- Fora do ar sem perder o cadastro. Serve para o comércio que
    -- fechou para reforma, para quem não renovou o plano e para tirar
    -- do site um anúncio com problema, sem apagar o trabalho da pessoa.
    add column if not exists ativo boolean not null default true;

-- A vitrine busca por cidade, mostra só quem está no ar e coloca os
-- destaques primeiro. Este índice atende essa consulta inteira.
create index if not exists anuncios_vitrine_idx
    on public.anuncios (cidade, ativo, destaque desc, criado_em);


-- ---------------------------------------------------------------------
-- 3. O QUE O ADMINISTRADOR PODE FAZER
--
-- Estas regras se somam às que já existem. O anunciante continua
-- mexendo só no que é dele; o administrador alcança tudo.
-- ---------------------------------------------------------------------
drop policy if exists "admin edita qualquer anuncio" on public.anuncios;
create policy "admin edita qualquer anuncio"
    on public.anuncios for update
    to authenticated
    using (public.eh_admin())
    with check (public.eh_admin());

drop policy if exists "admin ve todos os perfis" on public.perfis;
create policy "admin ve todos os perfis"
    on public.perfis for select
    to authenticated
    using (public.eh_admin());

drop policy if exists "admin edita qualquer perfil" on public.perfis;
create policy "admin edita qualquer perfil"
    on public.perfis for update
    to authenticated
    using (public.eh_admin())
    with check (public.eh_admin());


-- ---------------------------------------------------------------------
-- 4. A LISTA DO PAINEL
--
-- Uma linha por anunciante, com o cadastro e o anúncio juntos.
--
-- É uma função, e não uma consulta feita pelo site, por dois motivos:
-- o e-mail mora em auth.users, que a API do site não alcança; e assim
-- a checagem de administrador acontece aqui dentro, uma vez só, em vez
-- de depender de o site lembrar de fazê-la.
--
-- "left join" nos anúncios: quem criou a conta e ainda não montou a
-- loja também precisa aparecer — é justamente quem talvez precise de
-- uma ajuda sua.
-- ---------------------------------------------------------------------
create or replace function public.admin_listar_anunciantes()
returns table (
    perfil_id uuid,
    nome_completo text,
    documento text,
    tipo_documento text,
    email text,
    telefone text,
    cep text,
    logradouro text,
    numero text,
    complemento text,
    bairro text,
    cidade_responsavel text,
    uf text,
    cadastrado_em timestamptz,

    anuncio_id uuid,
    titulo text,
    cidade text,
    categoria text,
    plano text,
    destaque boolean,
    ativo boolean,
    visualizacoes integer,
    cliques_whatsapp integer,
    anuncio_criado_em timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $funcao$
begin
    if not public.eh_admin() then
        raise exception 'Acesso restrito ao administrador do guia.'
            using errcode = '42501';
    end if;

    return query
        select
            p.id,
            p.nome_completo,
            p.documento,
            p.tipo_documento,
            u.email::text,
            p.telefone,
            p.cep,
            p.logradouro,
            p.numero,
            p.complemento,
            p.bairro,
            p.cidade,
            p.uf::text,
            p.criado_em,

            a.id,
            a.titulo,
            a.cidade,
            a.categoria,
            a.plano,
            a.destaque,
            a.ativo,
            a.visualizacoes,
            a.cliques_whatsapp,
            a.criado_em
        from public.perfis p
        join auth.users u on u.id = p.id
        left join public.anuncios a on a.user_id = p.id
        order by a.cidade nulls last, a.destaque desc nulls last, a.criado_em nulls last;
end;
$funcao$;

grant execute on function public.admin_listar_anunciantes() to authenticated;


-- ---------------------------------------------------------------------
-- 5. DIGA QUEM É O ADMINISTRADOR
--
-- Tire o comentário da linha abaixo, troque pelo e-mail da conta que
-- você usa PARA ENTRAR NO SITE (não a do Supabase) e rode.
--
-- Precisa ser uma conta já criada em auth/cadastro.html. Se o e-mail
-- não existir, o comando não faz nada e não avisa — por isso vem o
-- select logo depois, para você conferir.
-- ---------------------------------------------------------------------

-- insert into public.admins (id)
-- select id from auth.users where email = 'troque@pelo.seu.email'
-- on conflict (id) do nothing;

-- select u.email, a.criado_em from public.admins a join auth.users u on u.id = a.id;
