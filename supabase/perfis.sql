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
