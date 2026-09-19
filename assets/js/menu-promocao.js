/* =====================================================================
   Para onde aponta o "+ CADASTRAR ANÚNCIO" durante a promoção.

   O botão é de ação, não de informação: quem clica nele já decidiu
   anunciar. Enquanto o cadastro é grátis, mostrar uma tabela de preços
   antes é um desvio que só faz perder gente no caminho.

   O menu PLANOS não muda. Ali a pessoa vai de propósito, para saber
   quanto vai custar depois de 30/09 — e esconder isso durante uma
   promoção gratuita levanta a suspeita de cobrança escondida.

   Em 01/10/2026 esta troca deixa de acontecer sozinha e os botões
   voltam a levar para os planos, sem ninguém precisar mexer em nada.

   Precisa de regras.js carregado antes.
   ===================================================================== */
(function () {
    if (!window.REGRAS || !window.REGRAS.promocaoValendo()) {
        return;
    }

    // O caminho até a raiz do site sai do próprio endereço deste
    // arquivo: numa página da raiz ele é "assets/js/...", numa página
    // dentro de pasta é "../assets/js/...". Tirando o final, sobra o
    // prefixo certo para montar o link — sem cada página precisar
    // dizer em que nível está.
    const raiz = document.querySelector('script[src$="menu-promocao.js"]')
        .getAttribute('src')
        .replace('assets/js/menu-promocao.js', '');

    const destino = raiz + 'auth/cadastro.html';

    function trocarBotoes() {
        // Só os botões que hoje levam aos planos. Um "+ CADASTRAR
        // ANÚNCIO" que já aponte para outro lugar fica como está.
        document.querySelectorAll('a.btn-add-listing').forEach((botao) => {
            const href = botao.getAttribute('href') || '';
            if (href.endsWith('planos.html')) {
                botao.setAttribute('href', destino);
            }
        });
    }

    // Este arquivo é lido no <head>, quando os botões ainda não
    // existem. Por isso espera a página terminar de montar.
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', trocarBotoes);
    } else {
        trocarBotoes();
    }
}());
