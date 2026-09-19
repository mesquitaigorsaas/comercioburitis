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
