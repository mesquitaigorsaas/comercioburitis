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
