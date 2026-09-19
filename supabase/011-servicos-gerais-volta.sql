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
