-- =====================================================================
-- 014 — O ponto de cada loja no mapa
--
-- Rode no SQL Editor do Supabase do Buritis, depois do 013.
--
-- POR QUE
--
-- O guia não separa por bairro. Quem procura está numa esquina, e o
-- que interessa é o que está perto dela — a divisa entre Buritis e
-- Estoril é linha no mapa da prefeitura, não é distância a pé.
--
-- Para ordenar por distância é preciso um ponto, e endereço em texto
-- não é ponto. Estas duas colunas guardam esse ponto.
--
-- DE ONDE VEM
--
-- Do Nominatim (OpenStreetMap), consultado pelo navegador na hora em
-- que a loja é cadastrada (assets/js/geo.js). Uma consulta por loja.
--
-- FICAM VAZIAS QUANDO o endereço é novo demais para o mapa, ou o
-- serviço está fora do ar. Loja sem coordenada continua aparecendo na
-- vitrine: ela só vai para o fim da lista quando a busca for "perto de
-- mim". Dá para preencher à mão depois, pelo formulário do anúncio.
--
-- NÃO GUARDAMOS a localização de quem visita o site. A distância é
-- calculada dentro do navegador da pessoa e nunca é enviada para cá.
-- =====================================================================

alter table public.anuncios
    add column if not exists latitude  double precision,
    add column if not exists longitude double precision;

-- A trava é contra engano de digitação, e não contra endereço errado:
-- latitude e longitude fora destas faixas não existem em lugar nenhum
-- do planeta, e um par trocado de lugar (longitude na latitude) cai
-- aqui em vez de virar uma loja no meio do oceano.
--
-- Um dos dois em branco também não serve: meio ponto não localiza nada.
do $$
begin
    if not exists (
        select 1 from pg_constraint where conname = 'anuncios_coordenada_valida'
    ) then
        alter table public.anuncios
            add constraint anuncios_coordenada_valida check (
                (latitude is null and longitude is null)
                or (
                    latitude  between -90  and 90
                    and longitude between -180 and 180
                )
            );
    end if;
end $$;

comment on column public.anuncios.latitude  is
    'Latitude da loja, do Nominatim/OpenStreetMap. Nula quando o mapa não achou o endereço.';
comment on column public.anuncios.longitude is
    'Longitude da loja, do Nominatim/OpenStreetMap. Nula quando o mapa não achou o endereço.';

-- Confira: quantas lojas já têm ponto no mapa.
select count(*) filter (where latitude is not null) as com_mapa,
       count(*) filter (where latitude is null)     as sem_mapa
  from public.anuncios;
