-- =====================================================================
-- MONTAR O BANCO DO BURITIS, DE UMA VEZ SÓ
--
-- Os 14 arquivos de supabase/, na ordem certa, colados num arquivo só:
-- num banco novo dá o mesmo resultado que rodar um por um, e não há
-- como trocar a ordem sem querer (várias partes dependem da anterior).
--
-- COMO USAR
--   Supabase do Buritis > SQL Editor > New query > cole isto > Run.
--   Demora alguns segundos. No fim, as últimas consultas mostram o
--   resultado (nenhuma loja ainda, o que é o esperado num banco novo).
--
-- DEPOIS, FALTA UMA COISA: dizer quem é o administrador. Isso só
-- funciona depois que você criar a sua conta no próprio site, em
-- auth/cadastro.html — o comando está no fim deste arquivo.
--
-- Este arquivo é gerado a partir dos outros. Mudou algum deles, gere
-- de novo em vez de editar aqui.
-- =====================================================================



-- =====================================================================
-- >>> schema.sql
-- =====================================================================

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


-- =====================================================================
-- >>> perfis.sql
-- =====================================================================

-- =====================================================================
-- Dados de cadastro do anunciante
--
-- Rode este arquivo no SQL Editor do Supabase, depois do schema.sql.
--
-- A tabela "anuncios" guarda a loja: nome fantasia, fotos, horário.
-- Esta aqui guarda quem responde por ela: nome, CPF ou CNPJ, contato e
-- endereço. São coisas diferentes — a loja aparece para o público, o
-- responsável não aparece para ninguém.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. CPF E CNPJ DE VERDADE
--
-- Não basta contar os dígitos: 111.111.111-11 tem onze e não existe.
-- Os dois últimos dígitos de um CPF (e de um CNPJ) são calculados a
-- partir dos anteriores — é uma conta fechada, e é ela que separa um
-- documento real de um número digitado no susto.
--
-- A mesma conta roda na tela de cadastro, para a pessoa ser avisada na
-- hora. Esta versão aqui é a que garante: a da tela pode ser
-- contornada por quem falar direto com o banco, esta não.
-- ---------------------------------------------------------------------
create or replace function public.documento_valido(p_documento text)
returns boolean
language plpgsql
immutable
as $funcao$
declare
    d text;
    n int[];
    soma int;
    resto int;
    peso int;
    i int;
begin
    if p_documento is null then
        return false;
    end if;

    -- Guarda só os números: pontos, barras e traços não entram na conta
    d := regexp_replace(p_documento, '\D', '', 'g');

    if length(d) not in (11, 14) then
        return false;
    end if;

    -- 00000000000, 11111111111 e afins fecham a conta por acaso,
    -- mas nenhum deles é documento de alguém.
    if d = repeat(substr(d, 1, 1), length(d)) then
        return false;
    end if;

    -- Cada dígito vira um número numa lista, para a conta ficar legível
    select array_agg(c::int order by ord)
      into n
      from unnest(string_to_array(d, null)) with ordinality as t(c, ord);

    -- ----- CPF: 11 dígitos -----
    if length(d) = 11 then
        -- Primeiro dígito verificador: pesos 10, 9, 8 ... 2
        soma := 0;
        for i in 1..9 loop
            soma := soma + n[i] * (11 - i);
        end loop;
        resto := (soma * 10) % 11;
        if resto = 10 then resto := 0; end if;
        if resto <> n[10] then
            return false;
        end if;

        -- Segundo: pesos 11, 10, 9 ... 2, já contando o primeiro
        soma := 0;
        for i in 1..10 loop
            soma := soma + n[i] * (12 - i);
        end loop;
        resto := (soma * 10) % 11;
        if resto = 10 then resto := 0; end if;

        return resto = n[11];
    end if;

    -- ----- CNPJ: 14 dígitos -----
    -- Os pesos vão de 5 para baixo até 2 e então voltam para 9.
    soma := 0;
    peso := 5;
    for i in 1..12 loop
        soma := soma + n[i] * peso;
        peso := case when peso = 2 then 9 else peso - 1 end;
    end loop;
    resto := soma % 11;
    if (case when resto < 2 then 0 else 11 - resto end) <> n[13] then
        return false;
    end if;

    -- No segundo dígito a régua começa em 6 e segue a mesma volta
    soma := 0;
    peso := 6;
    for i in 1..13 loop
        soma := soma + n[i] * peso;
        peso := case when peso = 2 then 9 else peso - 1 end;
    end loop;
    resto := soma % 11;

    return (case when resto < 2 then 0 else 11 - resto end) = n[14];
end;
$funcao$;


-- ---------------------------------------------------------------------
-- 2. A TABELA DE PERFIS
-- ---------------------------------------------------------------------
create table if not exists public.perfis (
    -- Mesmo código da conta de login. Apagou a conta, some o perfil.
    id uuid primary key references auth.users(id) on delete cascade,

    nome_completo text not null check (length(trim(nome_completo)) >= 5),

    -- Guardado só com números, sem ponto nem traço. Assim
    -- "123.456.789-09" e "12345678909" não viram dois cadastros.
    --
    -- O "unique" é a trava contra abuso: na promoção o anúncio é de
    -- graça, e sem isso uma pessoa poderia abrir dez contas com dez
    -- e-mails e ocupar o guia inteiro sozinha.
    documento text not null unique check (public.documento_valido(documento)),

    -- Preenchido sozinho a partir do tamanho: 11 é CPF, 14 é CNPJ.
    tipo_documento text generated always as (
        case when length(documento) = 11 then 'cpf' else 'cnpj' end
    ) stored,

    telefone text not null check (length(regexp_replace(telefone, '\D', '', 'g')) between 10 and 11),

    -- Endereço do responsável. Separado em campos porque é assim que
    -- vai ser preciso na hora de emitir cobrança, e juntar tudo numa
    -- linha só agora daria trabalho para desmontar depois.
    cep text not null check (length(regexp_replace(cep, '\D', '', 'g')) = 8),
    logradouro text not null,
    numero text not null,
    complemento text,
    bairro text not null,
    cidade text not null,
    uf char(2) not null,

    criado_em timestamptz not null default now(),
    atualizado_em timestamptz not null default now()
);

drop trigger if exists trg_perfis_atualizado_em on public.perfis;
create trigger trg_perfis_atualizado_em
    before update on public.perfis
    for each row execute function public.tocar_atualizado_em();


-- ---------------------------------------------------------------------
-- 3. SEGURANÇA
--
-- Aqui tem CPF e endereço de casa. Diferente dos anúncios, isto não é
-- público: cada um enxerga o próprio perfil e nada mais.
-- ---------------------------------------------------------------------
alter table public.perfis enable row level security;

drop policy if exists "cada um ve o proprio perfil" on public.perfis;
create policy "cada um ve o proprio perfil"
    on public.perfis for select
    to authenticated
    using (id = auth.uid());

drop policy if exists "cada um corrige o proprio perfil" on public.perfis;
create policy "cada um corrige o proprio perfil"
    on public.perfis for update
    to authenticated
    using (id = auth.uid())
    with check (id = auth.uid());

-- Não existe política de INSERT de propósito: o perfil nasce junto com
-- a conta, pelo gatilho da parte 4. Ninguém cria perfil na mão.


-- ---------------------------------------------------------------------
-- 4. O PERFIL NASCE COM A CONTA
--
-- Quando alguém se cadastra, o site manda nome, documento, telefone e
-- endereço junto com o e-mail e a senha. Este gatilho pega esses dados
-- e monta o perfil na mesma hora.
--
-- Se algo estiver errado (CPF inválido, documento repetido), o cadastro
-- inteiro é desfeito — não fica conta de login órfã, sem perfil.
-- ---------------------------------------------------------------------
create or replace function public.criar_perfil_do_novo_usuario()
returns trigger
language plpgsql
security definer
set search_path = public
as $funcao$
begin
    insert into public.perfis (
        id, nome_completo, documento, telefone,
        cep, logradouro, numero, complemento, bairro, cidade, uf
    )
    values (
        new.id,
        trim(new.raw_user_meta_data ->> 'nome_completo'),
        regexp_replace(coalesce(new.raw_user_meta_data ->> 'documento', ''), '\D', '', 'g'),
        trim(new.raw_user_meta_data ->> 'telefone'),
        regexp_replace(coalesce(new.raw_user_meta_data ->> 'cep', ''), '\D', '', 'g'),
        trim(new.raw_user_meta_data ->> 'logradouro'),
        trim(new.raw_user_meta_data ->> 'numero'),
        nullif(trim(coalesce(new.raw_user_meta_data ->> 'complemento', '')), ''),
        trim(new.raw_user_meta_data ->> 'bairro'),
        trim(new.raw_user_meta_data ->> 'cidade'),
        upper(trim(new.raw_user_meta_data ->> 'uf'))
    );

    return new;
end;
$funcao$;

drop trigger if exists trg_criar_perfil on auth.users;
create trigger trg_criar_perfil
    after insert on auth.users
    for each row execute function public.criar_perfil_do_novo_usuario();


-- ---------------------------------------------------------------------
-- 5. AVISAR ANTES, NÃO DEPOIS
--
-- Se o CPF já estiver cadastrado, o erro do banco chega na tela como
-- "Database error saving new user" — que não diz nada para quem está
-- se cadastrando.
--
-- Esta função deixa a tela perguntar antes de enviar: "esse documento
-- já existe?". Ela responde só sim ou não. Não devolve nome, e-mail
-- nem nada de quem já está cadastrado — de propósito: qualquer um pode
-- chamá-la, e ela não pode virar uma forma de descobrir quem tem conta
-- no site a partir de um CPF.
-- ---------------------------------------------------------------------
create or replace function public.documento_ja_cadastrado(p_documento text)
returns boolean
language sql
security definer
set search_path = public
as $funcao$
    select exists (
        select 1
          from public.perfis
         where documento = regexp_replace(coalesce(p_documento, ''), '\D', '', 'g')
    );
$funcao$;

grant execute on function public.documento_ja_cadastrado(text) to anon, authenticated;


-- =====================================================================
-- >>> 003-facebook.sql
-- =====================================================================

-- =====================================================================
-- Facebook no anúncio
--
-- Rode no SQL Editor, depois do schema.sql e do perfis.sql.
--
-- Muita loja da região tem fanpage e não tem site. Para essas, o
-- Facebook é o endereço na internet — deixar de fora seria tirar do
-- anúncio justamente o link que a pessoa usa.
--
-- "if not exists": rodar de novo não dá erro nem apaga nada.
-- =====================================================================
alter table public.anuncios
    add column if not exists facebook text;


-- =====================================================================
-- >>> 004-admin.sql
-- =====================================================================

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


-- =====================================================================
-- >>> 005-cadastro-rapido.sql
-- =====================================================================

-- =====================================================================
-- CPF/CNPJ deixa de ser obrigatório no cadastro
--
-- Rode no SQL Editor, depois dos anteriores.
--
-- POR QUÊ
--
-- O cadastro foi feito pensando em quem chega ao site sozinho, com
-- tempo. Só que as primeiras lojas do guia entram de outro jeito: a
-- visita ao comércio, com o dono no meio do expediente. Pedir o
-- documento de alguém numa primeira conversa, antes de a pessoa te
-- conhecer, é o pedido mais desconfortável do formulário — e é um dado
-- que só faz falta em 01/11, quando a cobrança começar.
--
-- O ENDEREÇO CONTINUA OBRIGATÓRIO. Ele custa dois campos digitados: o
-- CEP preenche rua, bairro, cidade e estado sozinho. E cadastro sem
-- endereço nenhum seria cadastro pela metade.
--
-- O QUE NÃO MUDA: quem informar o documento continua tendo ele
-- conferido pelos dígitos e continua não podendo repetir o de outro. A
-- trava contra a mesma pessoa ocupar o guia com dez contas segue
-- valendo para todo mundo que preencher.
--
-- A ORDEM DOS PASSOS IMPORTA: a trava sai, os dados são limpos, e só
-- então a trava nova entra. Invertendo, a regra nova barraria a
-- própria limpeza.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. A COLUNA CALCULADA SAI NA FRENTE
--
-- "tipo_documento" é calculada a partir do documento e não pode ser
-- alterada no lugar. Ela também responderia errado para documento
-- vazio: o tamanho não seria 11, cairia no "else", e um cadastro sem
-- documento nenhum apareceria como CNPJ no painel. Some agora e volta
-- no fim, sabendo dizer "não informado".
-- ---------------------------------------------------------------------
alter table public.perfis drop column if exists tipo_documento;


-- ---------------------------------------------------------------------
-- 2. A TRAVA ANTIGA SAI
--
-- Sobre o "unique" continuar de pé: no Postgres, valores nulos não
-- brigam entre si num índice único. Mil cadastros sem documento
-- convivem em paz; dois com o mesmo CPF continuam sendo recusados.
-- ---------------------------------------------------------------------
alter table public.perfis alter column documento drop not null;

alter table public.perfis drop constraint if exists perfis_documento_check;


-- ---------------------------------------------------------------------
-- 3. CAMPO VAZIO VIRA NULO
--
-- Texto vazio é um valor como outro qualquer para o banco: se dois
-- cadastros gravassem '' no documento, o segundo seria recusado por
-- "documento repetido". Nulo é o que significa "não informado", e é
-- ele que o índice único ignora.
--
-- Precisa acontecer aqui no meio: depois que o "not null" saiu, antes
-- da regra nova entrar.
-- ---------------------------------------------------------------------
update public.perfis
   set documento = nullif(trim(documento), '')
 where documento is null or trim(documento) = '';


-- ---------------------------------------------------------------------
-- 4. A REGRA NOVA: VALE PARA QUEM PREENCHEU
-- ---------------------------------------------------------------------
alter table public.perfis add constraint perfis_documento_check
    check (documento is null or public.documento_valido(documento));


-- ---------------------------------------------------------------------
-- 5. A COLUNA CALCULADA, DE VOLTA
-- ---------------------------------------------------------------------
alter table public.perfis add column tipo_documento text
    generated always as (
        case
            when documento is null then null
            when length(documento) = 11 then 'cpf'
            else 'cnpj'
        end
    ) stored;


-- ---------------------------------------------------------------------
-- 6. O GATILHO QUE CRIA O PERFIL
--
-- Ele gravava texto vazio quando o documento não vinha preenchido. Com
-- o documento único, o primeiro cadastro sem CPF gravaria '' e o
-- segundo seria recusado — e o erro chegaria na tela como "Database
-- error saving new user", sem dizer o motivo a ninguém.
--
-- "nullif(x, '')" resolve: se o que sobrou depois da limpeza for
-- vazio, grava nulo.
--
-- Os campos de endereço seguem como estavam: são obrigatórios no
-- formulário, e se um dia chegarem vazios é melhor o banco recusar do
-- que guardar cadastro pela metade.
-- ---------------------------------------------------------------------
create or replace function public.criar_perfil_do_novo_usuario()
returns trigger
language plpgsql
security definer
set search_path = public
as $funcao$
begin
    insert into public.perfis (
        id, nome_completo, documento, telefone,
        cep, logradouro, numero, complemento, bairro, cidade, uf
    )
    values (
        new.id,
        trim(new.raw_user_meta_data ->> 'nome_completo'),
        nullif(regexp_replace(coalesce(new.raw_user_meta_data ->> 'documento', ''), '\D', '', 'g'), ''),
        trim(new.raw_user_meta_data ->> 'telefone'),
        regexp_replace(coalesce(new.raw_user_meta_data ->> 'cep', ''), '\D', '', 'g'),
        trim(new.raw_user_meta_data ->> 'logradouro'),
        trim(new.raw_user_meta_data ->> 'numero'),
        nullif(trim(coalesce(new.raw_user_meta_data ->> 'complemento', '')), ''),
        trim(new.raw_user_meta_data ->> 'bairro'),
        trim(new.raw_user_meta_data ->> 'cidade'),
        upper(trim(new.raw_user_meta_data ->> 'uf'))
    );

    return new;
end;
$funcao$;

drop trigger if exists trg_criar_perfil on auth.users;
create trigger trg_criar_perfil
    after insert on auth.users
    for each row execute function public.criar_perfil_do_novo_usuario();


-- ---------------------------------------------------------------------
-- 7. A CONSULTA DE DOCUMENTO REPETIDO
--
-- O site pergunta isto antes de criar a conta, para dar um recado que
-- se entenda em vez do erro cru do banco. Sem documento não há o que
-- perguntar: responde "não existe" e deixa o cadastro seguir.
-- ---------------------------------------------------------------------
create or replace function public.documento_ja_cadastrado(p_documento text)
returns boolean
language sql
stable
security definer
set search_path = public
as $funcao$
    select case
        when coalesce(trim(p_documento), '') = '' then false
        else exists (select 1 from public.perfis where documento = p_documento)
    end;
$funcao$;

grant execute on function public.documento_ja_cadastrado(text) to anon, authenticated;


-- =====================================================================
-- >>> 006-endereco-do-anuncio.sql
-- =====================================================================

-- =====================================================================
-- O endereço da loja deixa de ser uma linha solta
--
-- Rode no SQL Editor, depois dos anteriores, no projeto
-- guia-comercio-buritis.
--
-- POR QUÊ
--
-- Até aqui o endereço do anúncio era um campo de texto livre: o
-- anunciante escrevia o que quisesse, do jeito que quisesse. Isso custa
-- em três lugares:
--
--   O mapa. A página da loja monta o Google Maps a partir dessa linha.
--   "Rua Cel. Jose Justino 123" e "R. Coronel José Justino, 123" levam
--   a lugares diferentes, e às vezes a lugar nenhum.
--
--   A busca por bairro. O guia promete que o morador acha pelo bairro,
--   e não dá para filtrar por bairro que está no meio de uma frase.
--
--   O balcão. Digitar o endereço inteiro à mão, no celular, com o dono
--   esperando, é lento. Com CEP, ele digita oito números e o resto se
--   preenche sozinho.
--
-- O CAMPO ANTIGO CONTINUA. "endereco" segue existindo e passa a ser
-- montado pelo site a partir das partes. Quem já lê esse campo — a
-- página da loja, o mapa, a página do anunciante — não precisa mudar
-- nada, e o anúncio que já existe não perde o que tinha escrito.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. AS PARTES DO ENDEREÇO
--
-- Todas aceitam nulo. O anúncio que já está no ar foi cadastrado antes
-- destes campos existirem, e exigir preenchimento agora deixaria uma
-- loja publicada em desacordo com a própria tabela. Quem manda no que
-- é obrigatório é o formulário, na hora de cadastrar.
--
-- A cidade não entra aqui: ela já é coluna da tabela desde o começo, e
-- é por ela que a busca do site filtra.
-- ---------------------------------------------------------------------
alter table public.anuncios
    add column if not exists cep         text,
    add column if not exists logradouro  text,
    add column if not exists numero      text,
    add column if not exists complemento text,
    add column if not exists bairro      text;


-- ---------------------------------------------------------------------
-- 2. O CEP GUARDADO SÓ COM NÚMEROS
--
-- "37130-000" e "37130000" são o mesmo CEP, e guardados diferente
-- viram dois. Como já acontece com o documento no perfil, aqui vale o
-- mesmo: o site grava só os dígitos, e o banco confere.
--
-- Nulo passa: é endereço ainda não preenchido, não endereço errado.
-- ---------------------------------------------------------------------
alter table public.anuncios drop constraint if exists anuncios_cep_check;

alter table public.anuncios add constraint anuncios_cep_check
    check (cep is null or cep ~ '^[0-9]{8}$');


-- ---------------------------------------------------------------------
-- 3. BUSCA POR BAIRRO
--
-- Índice pensado para a pergunta que o guia promete responder: "o que
-- tem no meu bairro?". Sem ele, cada busca leria a tabela inteira —
-- o que não pesa com dez lojas e pesa com mil.
--
-- Em minúsculas porque é assim que a cidade já é guardada, e por isso
-- "Centro" e "centro" não podem virar dois bairros.
-- ---------------------------------------------------------------------
create index if not exists idx_anuncios_bairro
    on public.anuncios (cidade, lower(bairro));


-- =====================================================================
-- >>> 007-excluir-anunciante.sql
-- =====================================================================

-- =====================================================================
-- EXCLUIR UM ANUNCIANTE PELO PAINEL
--
-- O painel precisava de um jeito de tirar um cadastro do guia por
-- inteiro: conta de login, cadastro do responsável e anúncio. Isso não
-- dá para fazer do navegador. A chave pública que o site usa não tem
-- permissão sobre auth.users, e a chave que teria nunca pode aparecer
-- no código de uma página — quem abrisse o painel a levaria embora.
--
-- A saída é esta função. Ela roda no banco com a permissão de quem a
-- criou, e antes de apagar qualquer coisa confere três condições. Se
-- alguma falhar, ela recusa e nada acontece.
--
-- Apagar a conta em auth.users basta: tanto o perfil quanto o anúncio
-- apontam para ela com "on delete cascade", então saem junto. Não é
-- preciso apagar em três lugares e torcer para nenhum falhar no meio.
-- =====================================================================

create or replace function public.admin_excluir_anunciante(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $funcao$
begin
    -- 1. Só administrador. Sem isto, qualquer pessoa logada poderia
    --    chamar a função direto pela API e apagar quem quisesse.
    if not public.eh_admin() then
        raise exception 'Apenas administradores podem excluir anunciantes.';
    end if;

    -- 2. Ninguém apaga a própria conta. É o clique de que mais se
    --    arrepende: o administrador se tranca para fora do painel e
    --    não há tela nenhuma para desfazer.
    if p_id = auth.uid() then
        raise exception 'Você não pode excluir a sua própria conta.';
    end if;

    -- 3. Um administrador não apaga outro por engano no meio da lista
    --    de anunciantes. Para tirar um administrador, tira-se antes o
    --    registro dele em public.admins — uma decisão consciente, e não
    --    um clique numa linha parecida com as outras.
    if exists (select 1 from public.admins where id = p_id) then
        raise exception 'Este cadastro é de um administrador. Remova-o de admins antes de excluir.';
    end if;

    delete from auth.users where id = p_id;

    -- Nada encontrado é erro, e não silêncio: se a linha já tinha sido
    -- apagada em outra aba, o painel precisa saber para não dizer que
    -- deu certo.
    if not found then
        raise exception 'Cadastro não encontrado.';
    end if;
end;
$funcao$;

grant execute on function public.admin_excluir_anunciante(uuid) to authenticated;


-- ---------------------------------------------------------------------
-- Conferência rápida, depois de rodar:
--
--   select public.eh_admin();
--   -- deve responder true quando você estiver logado como admin
--
-- A função em si só pode ser testada apagando alguém de verdade, então
-- não há consulta de teste inofensiva para ela.
-- ---------------------------------------------------------------------


-- =====================================================================
-- >>> 008-documentos-queimados.sql
-- =====================================================================

-- =====================================================================
-- DOCUMENTO USADO NÃO VOLTA PARA A FILA
--
-- O anunciante passou a poder corrigir o próprio CPF/CNPJ. Isso abriu
-- um caminho que o "unique" da tabela não fecha sozinho:
--
--   1. cria a conta com o CPF X e pega o anúncio grátis
--   2. troca o CPF para Y — e o X fica livre outra vez
--   3. cria outra conta com o CPF X e pega mais um anúncio grátis
--
-- O "unique" impede duas contas com o mesmo documento ao mesmo tempo.
-- Não impede a mesma pessoa reciclar o documento à vontade.
--
-- Aqui o guia passa a lembrar de todo documento que já entrou. Uma vez
-- registrado, ele não serve para uma conta nova, mesmo que ninguém
-- esteja usando no momento.
--
-- Isso mora no banco, e não na tela: no navegador qualquer pessoa
-- contorna, e a API do Supabase aceita chamada direta.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. A LISTA
-- ---------------------------------------------------------------------
create table if not exists public.documentos_usados (
    -- Só os números, sem ponto nem traço, como na tabela de perfis.
    documento text primary key,

    -- Quem usou por último e quando. Serve para você entender um caso
    -- estranho depois, sem precisar adivinhar.
    perfil_id uuid references auth.users(id) on delete set null,
    registrado_em timestamptz not null default now()
);

comment on table public.documentos_usados is
    'Todo CPF/CNPJ que já entrou no guia. Um documento aqui não pode ser usado por uma conta nova, mesmo que nenhum perfil o esteja usando agora.';

-- Ninguém lê nem escreve esta tabela pelo site. Quem mexe nela é o
-- gatilho abaixo, que roda com a permissão do dono da função.
alter table public.documentos_usados enable row level security;


-- ---------------------------------------------------------------------
-- 2. O GATILHO
-- ---------------------------------------------------------------------
create or replace function public.registrar_documento()
returns trigger
language plpgsql
security definer
set search_path = public
as $funcao$
declare
    d text;
    dono uuid;
begin
    d := regexp_replace(new.documento, '\D', '', 'g');

    -- Numa correção de digitação o documento não muda de verdade.
    if tg_op = 'UPDATE' and d = regexp_replace(old.documento, '\D', '', 'g') then
        return new;
    end if;

    select perfil_id into dono
      from public.documentos_usados
     where documento = d;

    -- Já passou pelo guia na mão de outra pessoa: barra.
    --
    -- O dono ser o próprio perfil é o caso de quem volta atrás — trocou
    -- para Y, se arrependeu e voltou para X. Não há abuso nisso: o
    -- documento nunca saiu da mesma conta.
    if found and dono is distinct from new.id then
        raise exception 'Este CPF/CNPJ já foi usado no guia e não pode ser cadastrado de novo.'
            using errcode = 'unique_violation';
    end if;

    insert into public.documentos_usados (documento, perfil_id)
         values (d, new.id)
    on conflict (documento) do update
        set perfil_id = excluded.perfil_id,
            registrado_em = now();

    return new;
end;
$funcao$;

drop trigger if exists trg_perfis_documento on public.perfis;
create trigger trg_perfis_documento
    before insert or update of documento on public.perfis
    for each row execute function public.registrar_documento();


-- ---------------------------------------------------------------------
-- 3. OS QUE JÁ ESTÃO NO GUIA
--
-- Sem isto a lista nasce vazia, e os documentos de quem já se cadastrou
-- ficariam de fora da regra até a primeira alteração.
-- ---------------------------------------------------------------------
insert into public.documentos_usados (documento, perfil_id)
select regexp_replace(documento, '\D', '', 'g'), id
  from public.perfis
on conflict (documento) do nothing;


-- ---------------------------------------------------------------------
-- Para conferir depois de rodar:
--
--   select * from public.documentos_usados;
--   -- deve listar um documento por perfil já cadastrado
--
-- Para liberar um documento à mão, quando você decidir que foi engano:
--
--   delete from public.documentos_usados where documento = '04947864699';
-- ---------------------------------------------------------------------


-- =====================================================================
-- >>> 009-entrega.sql
-- =====================================================================

-- =====================================================================
-- A loja entrega?
--
-- Rode no SQL Editor, depois dos anteriores, no projeto
-- guia-comercio-buritis.
--
-- POR QUÊ
--
-- Quem procura no guia às sete da noite quase sempre quer saber duas
-- coisas antes de qualquer outra: está aberto, e leva até mim. A
-- primeira o guia já sabia responder, a partir do horário de
-- funcionamento. A segunda não existia em lugar nenhum — nem no
-- cadastro, nem no anúncio, nem no card da vitrine.
--
-- Sem campo próprio, quem entrega escrevia isso no meio da descrição,
-- e quem procura tinha de ler o texto de cada loja para descobrir.
-- Numa lista com vinte lanchonetes, isso é vinte leituras para uma
-- pergunta de sim ou não.
--
-- O PADRÃO É "NÃO"
--
-- Falso, e não nulo. O card mostra o selo de entrega só para quem
-- marcou sim; um nulo obrigaria as telas a distinguir "não entrega" de
-- "não respondeu", e as duas terminam no mesmo lugar: sem selo.
--
-- As lojas cadastradas antes de hoje entram como "não entrega", que é
-- o que o guia sabe sobre elas. Quem entrega marca na primeira edição
-- do anúncio.
--
-- SEGURANÇA
--
-- Nada a fazer. As regras de RLS de schema.sql valem para a linha
-- inteira: o anúncio é público para leitura e só o dono escreve nele.
-- Uma coluna nova nasce coberta pelas mesmas regras.
-- =====================================================================

alter table public.anuncios
    add column if not exists entrega boolean not null default false;

comment on column public.anuncios.entrega is
    'A loja faz entrega/delivery. Marcado pelo anunciante no cadastro; '
    'vira selo no card da vitrine e na página da loja.';


-- =====================================================================
-- >>> 010-servicos-gerais.sql
-- =====================================================================

-- =====================================================================
-- "Serviços Gerais e Manutenção" passa a ser só "Serviços Gerais"
--
-- Rode no SQL Editor, depois dos anteriores, no projeto
-- guia-comercio-buritis.
--
-- POR QUÊ
--
-- Entrou no guia a categoria "Limpeza e Manutenção". Ao lado da que já
-- existia, "Serviços Gerais e Manutenção", as duas terminavam na mesma
-- palavra e diziam quase a mesma coisa. Isso custa nas duas pontas:
--
--   No cadastro. A empresa de limpeza de sofá olha as duas e não tem
--   como saber qual é a dela. Escolhe no chute.
--
--   Na busca. Quem procura por uma não encontra quem chutou a outra. A
--   loja está cadastrada, está no ar, e mesmo assim some do resultado.
--
-- Tirando "e Manutenção" da segunda, cada uma passa a dizer uma coisa
-- só: limpeza de um lado, conserto e serviço geral do outro.
--
-- POR QUE PRECISA DE SQL
--
-- A categoria do anúncio é guardada como texto, e não como referência a
-- uma lista. Renomear a opção no site não alcança o que já está gravado:
-- a loja continuaria com o texto antigo no banco, e a busca pelo nome
-- novo não a encontraria — some do guia sem ninguém ter mexido nela.
--
-- Hoje isso vale para a R&J MAQUINAS, a única cadastrada na categoria.
-- O update abaixo vale para ela e para qualquer outra que entre antes
-- de você rodar isto.
--
-- SEGURANÇA
--
-- Nada a fazer: nenhuma coluna nova, nenhuma regra nova. As de
-- schema.sql continuam valendo.
--
-- CUIDADO PARA A PRÓXIMA VEZ
--
-- Toda vez que uma categoria for renomeada no site, um update como este
-- precisa vir junto — senão as lojas que estavam nela desaparecem da
-- busca. Rodar os dois no mesmo dia; a ordem entre eles quase não
-- importa, mas rodar o SQL primeiro é o mais seguro: uma loja fora do
-- menu por dois minutos incomoda menos que uma loja fora da busca.
-- =====================================================================

update public.anuncios
   set categoria = 'Serviços Gerais'
 where categoria = 'Serviços Gerais e Manutenção';

-- Confere o resultado. Deve sobrar zero linha com o nome antigo.
select categoria, count(*) as lojas
  from public.anuncios
 group by categoria
 order by categoria;


-- =====================================================================
-- >>> 011-servicos-gerais-volta.sql
-- =====================================================================

-- =====================================================================
-- "Serviços Gerais" volta a ser "Serviços Gerais e Manutenção"
--
-- Rode no SQL Editor, depois dos anteriores, no projeto
-- guia-comercio-buritis.
--
-- POR QUÊ
--
-- Desfaz o 010. Lá o nome foi encurtado para afastá-lo de "Limpeza e
-- Manutenção"; visto no ar, o nome curto ficou vago demais — "Serviços
-- Gerais" sozinho não diz que a loja faz manutenção, que é o serviço
-- pelo qual as pessoas procuram.
--
-- As duas voltam a terminar em "Manutenção", e a decisão de conviver
-- assim é consciente: o incômodo de dois nomes parecidos é menor que o
-- de um nome que não descreve o serviço.
--
-- O 010 fica no repositório em vez de ser apagado. Ele já rodou no
-- banco de produção, e um arquivo que sumiu não explica por que o dado
-- mudou duas vezes.
--
-- POR QUE PRECISA DE SQL DE NOVO
--
-- Pelo mesmo motivo do 010: a categoria é texto gravado dentro do
-- anúncio. A R&J MAQUINAS está hoje em "Serviços Gerais", e sem este
-- update ela sumiria da busca pelo nome longo.
-- =====================================================================

update public.anuncios
   set categoria = 'Serviços Gerais e Manutenção'
 where categoria = 'Serviços Gerais';

-- Confere. Não deve sobrar linha com o nome curto.
select categoria, count(*) as lojas
  from public.anuncios
 group by categoria
 order by categoria;


-- =====================================================================
-- >>> 012-cadastro-sem-documento.sql
-- =====================================================================

-- =====================================================================
-- O CADASTRO SEM CPF VOLTA A FUNCIONAR
--
-- Rode no SQL Editor do projeto, de uma vez, de cima para baixo.
--
-- O QUE ESTAVA ACONTECENDO
--
-- Desde a migração 008, criar conta sem informar CPF/CNPJ era
-- impossível. A tela dizia "Opcional" no campo, a validação do
-- navegador deixava passar em branco, e o banco recusava.
--
-- O gatilho registrar_documento(), da 008, roda em toda inserção na
-- tabela de perfis — inclusive nas que vêm sem documento. Nessas:
--
--   d := regexp_replace(new.documento, ...)   ->  d fica nulo
--   insert into documentos_usados (documento, ...) values (d, ...)
--
-- e "documento" é a chave primária de documentos_usados. Chave
-- primária não aceita nulo: a inserção estourava, o gatilho derrubava
-- a criação do perfil, e o Supabase devolvia "Database error saving
-- new user".
--
-- Do lado de quem estava cadastrando, isso chegava como "Não foi
-- possível concluir o cadastro. Confira o CPF/CNPJ e o endereço" — uma
-- mensagem que manda conferir justamente o campo que a pessoa tinha
-- deixado em branco de propósito.
--
-- POR QUE PASSOU DESPERCEBIDO
--
-- A 008 foi escrita para resolver o CPF reciclado, e todo cadastro que
-- existia na hora de testá-la tinha documento. O caminho sem documento
-- nasceu na 005 e nunca voltou a ser percorrido depois da 008.
--
-- A CORREÇÃO
--
-- Uma linha: sem documento, o gatilho não tem o que registrar e sai
-- antes de tentar. A regra do documento reciclado continua valendo
-- inteira para quem informa o documento.
-- =====================================================================

create or replace function public.registrar_documento()
returns trigger
language plpgsql
security definer
set search_path = public
as $funcao$
declare
    d text;
    dono uuid;
begin
    d := nullif(regexp_replace(coalesce(new.documento, ''), '\D', '', 'g'), '');

    -- Cadastro sem documento. Não há o que registrar na lista, e não há
    -- o que reciclar: quem não informou documento não ocupa lugar
    -- nenhum. Sai antes de tocar em documentos_usados.
    --
    -- É esta a linha que faltava. Sem ela, o "Opcional" do formulário
    -- era mentira — e mentira que só aparecia depois de a pessoa
    -- preencher a tela inteira e apertar o botão.
    if d is null then
        return new;
    end if;

    -- Numa correção de digitação o documento não muda de verdade.
    if tg_op = 'UPDATE'
       and d = nullif(regexp_replace(coalesce(old.documento, ''), '\D', '', 'g'), '') then
        return new;
    end if;

    select perfil_id into dono
      from public.documentos_usados
     where documento = d;

    -- Já passou pelo guia na mão de outra pessoa: barra.
    --
    -- O dono ser o próprio perfil é o caso de quem volta atrás — trocou
    -- para Y, se arrependeu e voltou para X. Não há abuso nisso: o
    -- documento nunca saiu da mesma conta.
    if found and dono is distinct from new.id then
        raise exception 'Este CPF/CNPJ já foi usado no guia e não pode ser cadastrado de novo.'
            using errcode = 'unique_violation';
    end if;

    insert into public.documentos_usados (documento, perfil_id)
         values (d, new.id)
    on conflict (documento) do update
        set perfil_id = excluded.perfil_id,
            registrado_em = now();

    return new;
end;
$funcao$;


-- ---------------------------------------------------------------------
-- A MESMA FALHA, NA CARGA INICIAL DA 008
--
-- A parte 3 da 008 copiava para documentos_usados o documento de todo
-- perfil que já existia, sem filtrar os nulos. Ela passou na época
-- porque todo perfil de então tinha documento — mas num banco montado
-- do zero hoje, com um perfil sem documento, aquela carga falharia do
-- mesmo jeito.
--
-- Rodar de novo, agora filtrando. É seguro repetir: o "on conflict do
-- nothing" ignora o que já está lá.
-- ---------------------------------------------------------------------
insert into public.documentos_usados (documento, perfil_id)
select nullif(regexp_replace(documento, '\D', '', 'g'), ''), id
  from public.perfis
 where nullif(regexp_replace(coalesce(documento, ''), '\D', '', 'g'), '') is not null
on conflict (documento) do nothing;


-- ---------------------------------------------------------------------
-- Para conferir depois de rodar:
--
--   -- 1. Nenhum nulo entrou na lista (deve devolver zero linhas):
--   select * from public.documentos_usados where documento is null;
--
--   -- 2. A lista bate com os perfis que têm documento:
--   select
--       (select count(*) from public.perfis where documento is not null) as perfis_com_documento,
--       (select count(*) from public.documentos_usados)                  as na_lista;
--
-- E o teste que importa: criar uma conta no site deixando o campo
-- CPF/CNPJ em branco. Antes disto, dava erro.
-- ---------------------------------------------------------------------


-- =====================================================================
-- >>> 013-pagamento.sql
-- =====================================================================

-- =====================================================================
-- 013 — A cobrança dos planos
--
-- Rode no SQL Editor, depois dos anteriores. Pode rodar mais de uma vez.
--
-- Até agora o anúncio ficava no ar para sempre e o plano era só um
-- rótulo. A partir daqui:
--
--   1. Cada anúncio tem um vencimento (vence_em). Passou do dia, sai
--      da busca sozinho — sem ninguém apertar botão.
--   2. Quem se cadastrou na promoção (até 30/09/2026) ganha o vencimento
--      que o painel já mostrava: 3 meses a partir do cadastro. É a
--      promessa da promoção, e ela é cumprida.
--   3. Quem se cadastra depois disso nasce sem vencimento, fora do ar,
--      até pagar.
--   4. Plano, vencimento e destaque deixam de ser editáveis pelo dono.
--      Antes, qualquer anunciante logado podia gravar plano = 'anual'
--      ou destaque = true direto pela API, sem pagar nada.
--   5. A tabela de pagamentos e a única função que credita.
--
-- Táxi e Moto Táxi continuam grátis e sem vencimento, como sempre.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. AS COLUNAS NOVAS
-- ---------------------------------------------------------------------
alter table public.anuncios
    -- Último dia em que o anúncio aparece. Nulo = ainda não pagou
    -- (ou é táxi, que nunca vence).
    add column if not exists vence_em date,

    -- Último dia do destaque comprado (R$ 120 por 15 dias). Nulo no
    -- destaque que o administrador marca à mão, que não vence sozinho.
    add column if not exists destaque_ate date;


-- O dia de hoje no Brasil. O banco roda em UTC: às 22h de Brasília já
-- seria amanhã, e quem vence hoje sairia do ar duas horas antes.
create or replace function public.hoje_no_brasil()
returns date
language sql
stable
as $funcao$
    select (now() at time zone 'America/Sao_Paulo')::date;
$funcao$;


-- Os mesmos dados de assets/js/regras.js. Os de lá desenham a tela;
-- os daqui decidem.
create or replace function public.eh_categoria_gratuita(p_categoria text)
returns boolean
language sql
immutable
as $funcao$
    -- Buritis: nenhuma categoria é gratuita.
    select false;
$funcao$;

create or replace function public.promocao_valendo()
returns boolean
language sql
stable
as $funcao$
    -- Buritis: sem promoção de cadastro grátis.
    select false;
$funcao$;


-- ---------------------------------------------------------------------
-- 2. OS ANÚNCIOS QUE JÁ EXISTEM
--
-- Todos entraram pela promoção. Ganham o vencimento que o painel deles
-- já mostrava: cadastro + meses do plano (3, se não tinha plano).
-- Só preenche quem ainda está sem vencimento, então rodar de novo não
-- estraga um prazo que já foi pago.
-- ---------------------------------------------------------------------
update public.anuncios a
   set plano = coalesce(a.plano, 'trimestral'),
       vence_em = ((a.criado_em at time zone 'America/Sao_Paulo')::date
                   + (case coalesce(a.plano, 'trimestral')
                        when 'anual'     then interval '12 months'
                        when 'semestral' then interval '6 months'
                        else                  interval '3 months'
                      end))::date
 where a.vence_em is null
   and not public.eh_categoria_gratuita(a.categoria)
   and a.criado_em < timestamptz '2026-10-01 00:00:00-03';


-- ---------------------------------------------------------------------
-- 3. O QUE O DONO NÃO PODE MUDAR
--
-- Um gatilho só, na criação e na edição. Pelo navegador o papel é
-- 'authenticated'; as funções do banco (security definer) e as Edge
-- Functions (service_role) não caem aqui. O administrador também passa.
--
-- Em vez de dar erro, o gatilho devolve o valor certo em silêncio: o
-- formulário do anúncio manda o plano junto com o resto, e travar o
-- salvamento por causa disso puniria quem só queria trocar uma foto.
-- ---------------------------------------------------------------------
create or replace function public.proteger_cobranca()
returns trigger
language plpgsql
as $funcao$
begin
    if current_user not in ('authenticated', 'anon') or public.eh_admin() then
        return new;
    end if;

    if tg_op = 'INSERT' then
        new.destaque := false;
        new.destaque_ate := null;
        new.ativo := true;

        if public.eh_categoria_gratuita(new.categoria) then
            -- Táxi: grátis e sem prazo.
            new.plano := null;
            new.vence_em := null;
        elsif public.promocao_valendo() then
            -- Promoção: 3 meses, gravado como trimestral (o combinado).
            new.plano := 'trimestral';
            new.vence_em := (public.hoje_no_brasil() + interval '3 months')::date;
        else
            -- Depois da promoção: nasce fora do ar e entra quando pagar.
            -- O plano escolhido fica guardado só como intenção; quem
            -- grava o plano de verdade é o pagamento.
            new.plano := null;
            new.vence_em := null;
        end if;

        return new;
    end if;

    -- UPDATE
    new.plano := old.plano;
    new.vence_em := old.vence_em;
    new.destaque := old.destaque;
    new.destaque_ate := old.destaque_ate;
    return new;
end;
$funcao$;

drop trigger if exists trg_anuncios_proteger_cobranca on public.anuncios;
create trigger trg_anuncios_proteger_cobranca
    before insert or update on public.anuncios
    for each row execute function public.proteger_cobranca();


-- ---------------------------------------------------------------------
-- 4. QUEM APARECE NA BUSCA
--
-- No ar = ativo e (táxi ou vencimento de hoje em diante).
--
-- O dono continua vendo o dele fora do ar (é assim que o painel mostra
-- "falta pagar"), e o administrador vê todos.
-- ---------------------------------------------------------------------
create or replace function public.anuncio_no_ar(p_ativo boolean, p_categoria text, p_vence_em date)
returns boolean
language sql
stable
as $funcao$
    select p_ativo
       and (public.eh_categoria_gratuita(p_categoria)
            or (p_vence_em is not null and p_vence_em >= public.hoje_no_brasil()));
$funcao$;

drop policy if exists "anuncios sao publicos" on public.anuncios;
create policy "anuncios sao publicos"
    on public.anuncios for select
    to anon, authenticated
    using (
        public.anuncio_no_ar(ativo, categoria, vence_em)
        or user_id = auth.uid()
        or public.eh_admin()
    );


-- ---------------------------------------------------------------------
-- 5. OS PAGAMENTOS
--
-- A linha nasce antes de o Mercado Pago ser chamado, e o id dela vai
-- como external_reference. Quando o aviso chega, é por ela que se sabe
-- qual anúncio, o que foi comprado e quanto devia ter caído — nada
-- disso é lido do que o navegador mandou.
-- ---------------------------------------------------------------------
create table if not exists public.pagamentos (
    id              uuid primary key default gen_random_uuid(),
    anuncio_id      uuid not null references public.anuncios (id) on delete cascade,
    user_id         uuid not null references auth.users (id) on delete cascade,

    -- 'plano' estende o vencimento; 'destaque' compra 15 dias na frente.
    tipo            text not null check (tipo in ('plano', 'destaque')),
    plano           text check (plano in ('trimestral', 'semestral', 'anual')),
    valor           numeric(10, 2) not null check (valor > 0),

    -- O id da preferência (a página de pagamento do Mercado Pago) e o
    -- do pagamento em si. Este é único: o aviso chega repetido, e o
    -- segundo não pode virar um segundo crédito.
    preferencia_id  text,
    gateway_id      text unique,

    -- 'credit_card', 'debit_card' ou 'bank_transfer' (o Pix).
    metodo          text,

    status          text not null default 'pendente'
                    check (status in ('pendente', 'pago', 'cancelado', 'estornado')),

    -- Preenchido uma vez só, pela creditar_pagamento(): é a trava que
    -- impede o mesmo pagamento de estender o prazo duas vezes.
    creditado_em    timestamptz,
    vale_ate        date,

    retorno         jsonb,
    criado_em       timestamptz not null default now(),
    atualizado_em   timestamptz not null default now(),

    check ((tipo = 'plano') = (plano is not null))
);

create index if not exists pagamentos_anuncio_idx on public.pagamentos (anuncio_id, criado_em desc);

alter table public.pagamentos enable row level security;

-- O dono vê os dele (é assim que o painel descobre que o pagamento
-- caiu); o administrador vê todos. Ninguém escreve pelo navegador.
drop policy if exists "dono ve os proprios pagamentos" on public.pagamentos;
create policy "dono ve os proprios pagamentos"
    on public.pagamentos for select
    to authenticated
    using (user_id = auth.uid() or public.eh_admin());


-- ---------------------------------------------------------------------
-- 6. CREDITAR
--
-- A única porta que estende vencimento e destaque. O prazo conta do
-- vencimento que ainda não passou, ou de hoje: quem renova adiantado
-- não perde os dias que já tinha.
-- ---------------------------------------------------------------------
create or replace function public.creditar_pagamento(p_pagamento uuid)
returns date
language plpgsql
volatile
security definer
set search_path = public
as $funcao$
declare
    v_pag public.pagamentos;
    v_anuncio public.anuncios;
    v_base date;
    v_novo date;
begin
    select * into v_pag from public.pagamentos where id = p_pagamento for update;

    if not found then
        raise exception 'Pagamento não encontrado.';
    end if;
    if v_pag.status <> 'pago' then
        raise exception 'Este pagamento não está pago.';
    end if;
    if v_pag.creditado_em is not null then
        return v_pag.vale_ate;
    end if;

    select * into v_anuncio from public.anuncios where id = v_pag.anuncio_id for update;

    if v_pag.tipo = 'plano' then
        v_base := greatest(public.hoje_no_brasil(), coalesce(v_anuncio.vence_em, public.hoje_no_brasil()));
        v_novo := (v_base + (case v_pag.plano
                                when 'anual'     then interval '12 months'
                                when 'semestral' then interval '6 months'
                                else                  interval '3 months'
                             end))::date;

        update public.anuncios
           set vence_em = v_novo,
               plano = v_pag.plano
         where id = v_pag.anuncio_id;
    else
        v_base := greatest(public.hoje_no_brasil(), coalesce(v_anuncio.destaque_ate, public.hoje_no_brasil()));
        v_novo := v_base + 15;

        update public.anuncios
           set destaque = true,
               destaque_ate = v_novo
         where id = v_pag.anuncio_id;
    end if;

    update public.pagamentos
       set creditado_em = now(),
           vale_ate = v_novo,
           atualizado_em = now()
     where id = p_pagamento;

    return v_novo;
end;
$funcao$;

revoke all on function public.creditar_pagamento(uuid) from public, anon, authenticated;
grant execute on function public.creditar_pagamento(uuid) to service_role;


-- ---------------------------------------------------------------------
-- 7. O DESTAQUE COMPRADO VENCE SOZINHO
--
-- Todo dia às 00:05 de Brasília (03:05 UTC). Só desliga o destaque que
-- foi comprado (destaque_ate preenchido); o que o administrador marcou
-- à mão continua até ele desmarcar.
--
-- O vencimento do plano não precisa disto: a regra da parte 4 olha a
-- data na hora da busca.
-- ---------------------------------------------------------------------
create or replace function public.vencer_destaques()
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $funcao$
declare
    v_total integer;
begin
    update public.anuncios
       set destaque = false
     where destaque
       and destaque_ate is not null
       and destaque_ate < public.hoje_no_brasil();

    get diagnostics v_total = row_count;
    return v_total;
end;
$funcao$;

revoke all on function public.vencer_destaques() from public, anon, authenticated;

create extension if not exists pg_cron with schema pg_catalog;

select cron.schedule('vencer-destaques', '5 3 * * *', $$select public.vencer_destaques()$$);


-- ---------------------------------------------------------------------
-- 8. O ADMINISTRADOR
--
-- A lista dele ganha o vencimento. O tipo de retorno mudou, e por isso
-- a função é apagada e criada de novo (o Postgres não deixa trocar as
-- colunas de uma função que já existe).
--
-- E ganha a porta para liberar à mão quem pagou por fora (Pix direto,
-- dinheiro): admin_definir_vencimento.
-- ---------------------------------------------------------------------
drop function if exists public.admin_listar_anunciantes();

create function public.admin_listar_anunciantes()
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
    anuncio_criado_em timestamptz,
    vence_em date,
    destaque_ate date
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
            p.id, p.nome_completo, p.documento, p.tipo_documento, u.email::text,
            p.telefone, p.cep, p.logradouro, p.numero, p.complemento, p.bairro,
            p.cidade, p.uf::text, p.criado_em,
            a.id, a.titulo, a.cidade, a.categoria, a.plano, a.destaque, a.ativo,
            a.visualizacoes, a.cliques_whatsapp, a.criado_em, a.vence_em, a.destaque_ate
        from public.perfis p
        join auth.users u on u.id = p.id
        left join public.anuncios a on a.user_id = p.id
        order by a.cidade nulls last, a.destaque desc nulls last, a.criado_em nulls last;
end;
$funcao$;

grant execute on function public.admin_listar_anunciantes() to authenticated;


create or replace function public.admin_definir_vencimento(p_anuncio uuid, p_plano text, p_vence_em date)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $funcao$
begin
    if not public.eh_admin() then
        raise exception 'Acesso restrito ao administrador do guia.'
            using errcode = '42501';
    end if;

    update public.anuncios
       set plano = coalesce(p_plano, plano),
           vence_em = p_vence_em
     where id = p_anuncio;
end;
$funcao$;

grant execute on function public.admin_definir_vencimento(uuid, text, date) to authenticated;


-- ---------------------------------------------------------------------
-- Conferência: quantos anúncios estão no ar e até quando.
-- ---------------------------------------------------------------------
select titulo, categoria, plano, vence_em,
       public.anuncio_no_ar(ativo, categoria, vence_em) as no_ar
  from public.anuncios
 order by vence_em nulls first;


-- =====================================================================
-- >>> 014-localizacao.sql
-- =====================================================================

-- =====================================================================
-- 014 — O ponto de cada loja no mapa
--
-- Rode no SQL Editor do Supabase do Buritis, depois do 013.
--
-- POR QUE
--
-- O guia não separa por bairro. Quem procura está numa esquina, e o
-- que interessa é o que está perto dela — a divisa entre Buritis e
-- Estoril é linha no mapa da prefeitura, não é distância a pé.
--
-- Para ordenar por distância é preciso um ponto, e endereço em texto
-- não é ponto. Estas duas colunas guardam esse ponto.
--
-- DE ONDE VEM
--
-- Do Nominatim (OpenStreetMap), consultado pelo navegador na hora em
-- que a loja é cadastrada (assets/js/geo.js). Uma consulta por loja.
--
-- FICAM VAZIAS QUANDO o endereço é novo demais para o mapa, ou o
-- serviço está fora do ar. Loja sem coordenada continua aparecendo na
-- vitrine: ela só vai para o fim da lista quando a busca for "perto de
-- mim". Dá para preencher à mão depois, pelo formulário do anúncio.
--
-- NÃO GUARDAMOS a localização de quem visita o site. A distância é
-- calculada dentro do navegador da pessoa e nunca é enviada para cá.
-- =====================================================================

alter table public.anuncios
    add column if not exists latitude  double precision,
    add column if not exists longitude double precision;

-- A trava é contra engano de digitação, e não contra endereço errado:
-- latitude e longitude fora destas faixas não existem em lugar nenhum
-- do planeta, e um par trocado de lugar (longitude na latitude) cai
-- aqui em vez de virar uma loja no meio do oceano.
--
-- Um dos dois em branco também não serve: meio ponto não localiza nada.
do $$
begin
    if not exists (
        select 1 from pg_constraint where conname = 'anuncios_coordenada_valida'
    ) then
        alter table public.anuncios
            add constraint anuncios_coordenada_valida check (
                (latitude is null and longitude is null)
                or (
                    latitude  between -90  and 90
                    and longitude between -180 and 180
                )
            );
    end if;
end $$;

comment on column public.anuncios.latitude  is
    'Latitude da loja, do Nominatim/OpenStreetMap. Nula quando o mapa não achou o endereço.';
comment on column public.anuncios.longitude is
    'Longitude da loja, do Nominatim/OpenStreetMap. Nula quando o mapa não achou o endereço.';

-- Confira: quantas lojas já têm ponto no mapa.
select count(*) filter (where latitude is not null) as com_mapa,
       count(*) filter (where latitude is null)     as sem_mapa
  from public.anuncios;


-- =====================================================================
-- >>> POR ÚLTIMO: QUEM É O ADMINISTRADOR
--
-- Só depois de criar a conta no site (auth/cadastro.html) com o e-mail
-- abaixo. Tire os dois tracinhos das três linhas do insert e rode.
--
-- O administrador é sempre mesquitaigor.saas@gmail.com, o mesmo
-- dos outros guias: quem entra no painel é o dono do projeto, e não a
-- conta de serviço do guia (comercioburitisbh@gmail.com), que existe
-- para o Supabase e para os e-mails do site.
--
-- Sem isso ninguém entra no painel de administração — nem você.
-- =====================================================================

-- insert into public.admins (id)
-- select id from auth.users where email = 'mesquitaigor.saas@gmail.com'
-- on conflict (id) do nothing;

-- select u.email from public.admins a join auth.users u on u.id = a.id;
