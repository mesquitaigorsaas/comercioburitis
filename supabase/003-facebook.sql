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
