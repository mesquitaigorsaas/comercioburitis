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
// Projeto do Buritis, na conta comercioburitisbh@gmail.com — separado
// do guia de Alfenas de propósito: com os valores de lá, cada cadastro
// do Buritis cairia no banco de Alfenas.
//
// A chave abaixo é a "anon public", de Project Settings > API Keys.
window.CONFIG_SUPABASE = {
    url: 'https://bjldjnucabkfmebazqxk.supabase.co',
    chavePublica: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJqbGRqbnVjYWJrZm1lYmF6cXhrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk5MTQ1MTQsImV4cCI6MjEwNTQ5MDUxNH0.74hRwo7uGnbIT-Hf0mqiNTsuhDCK8q_GIGfZ6XhkKw8'
};
