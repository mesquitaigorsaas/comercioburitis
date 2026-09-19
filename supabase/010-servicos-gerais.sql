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
