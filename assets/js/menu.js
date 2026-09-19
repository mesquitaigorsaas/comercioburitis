/* ==========================================================
   MENU SANDUÍCHE — abre e fecha o cabeçalho no celular
   ==========================================================
   Uma classe só, .menu-aberto, no <header>. Quem desenha o
   menu aberto é o assets/css/header.css; aqui só se decide
   quando essa classe entra e quando sai.

   A classe fica no <header>, e não no <nav>, porque no
   celular os links e os botões (Entrar / Cadastrar Anúncio)
   descem juntos. Marcando o pai, os dois obedecem à mesma
   chave sem precisar de um <div> em volta em cada página.
   ========================================================== */

document.addEventListener('DOMContentLoaded', function () {

    const header = document.querySelector('.main-header');
    const botao = document.getElementById('menuToggle');

    // Painel, login e cadastro não têm esse cabeçalho.
    if (!header || !botao) return;

    const icone = botao.querySelector('i');

    function pintarBotao(aberto) {
        botao.setAttribute('aria-expanded', aberto);
        botao.setAttribute('aria-label', aberto ? 'Fechar menu' : 'Abrir menu');
        if (icone) {
            icone.classList.toggle('fa-bars', !aberto);
            icone.classList.toggle('fa-xmark', aberto);
        }
    }

    function fechar() {
        header.classList.remove('menu-aberto');
        pintarBotao(false);
    }

    botao.addEventListener('click', function () {
        const aberto = header.classList.toggle('menu-aberto');
        pintarBotao(aberto);
    });

    // Clicou num link, o menu sai da frente.
    header.querySelectorAll('.nav-links a, .header-actions a').forEach(function (link) {
        link.addEventListener('click', fechar);
    });

    document.addEventListener('keydown', function (e) {
        if (e.key === 'Escape') fechar();
    });

    // Virou o celular para a horizontal e o desktop voltou: o
    // menu precisa sair aberto do caminho, senão a classe fica
    // presa e o cabeçalho volta torto quando girar de novo.
    window.addEventListener('resize', function () {
        if (window.innerWidth > 900) fechar();
    });

    pintarBotao(false);
});
