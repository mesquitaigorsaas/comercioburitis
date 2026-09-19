/* =====================================================================
   Endereço do banco de dados — um lugar só.

   Antes, cada uma das 7 páginas do site carregava sua própria cópia
   destes dois valores. Quando o projeto do Supabase mudou de endereço,
   o site inteiro parou de funcionar de uma vez, e consertar era achar
   e trocar em 7 arquivos diferentes sem esquecer nenhum.

   Agora é aqui e pronto. Trocou aqui, trocou em todo o site.

   Estes dois valores são públicos de propósito: eles viajam dentro da
   página até o navegador de quem visita, então qualquer pessoa pode
   lê-los. Não é descuido, é como o Supabase foi feito. Quem decide o
   que cada visitante pode ver e mexer são as regras de segurança (RLS)
   escritas em supabase/schema.sql, do lado do banco.

   A senha do banco NÃO está aqui e nunca deve estar. Ela vive só no
   painel do Supabase, e de lá pode ser redefinida quando for preciso.
   ===================================================================== */
// PENDENTE: o Buritis precisa do PRÓPRIO projeto no Supabase. Estes dois
// valores ainda estão vazios de propósito — com os do guia de Alfenas,
// cada cadastro do Buritis cairia no banco de Alfenas.
// Crie o projeto, rode os SQLs de supabase/ e cole aqui a URL e a
// chave anon (Project Settings > API).
window.CONFIG_SUPABASE = {
    url: 'https://SEU-PROJETO.supabase.co',
    chavePublica: 'COLE-AQUI-A-CHAVE-ANON'
};
