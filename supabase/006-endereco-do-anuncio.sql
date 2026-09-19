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
