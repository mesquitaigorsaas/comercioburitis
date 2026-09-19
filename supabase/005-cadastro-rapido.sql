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
