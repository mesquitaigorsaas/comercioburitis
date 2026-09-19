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
