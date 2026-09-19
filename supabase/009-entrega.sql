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
