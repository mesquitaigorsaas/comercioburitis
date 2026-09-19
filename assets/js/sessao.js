/* =====================================================================
   O cabeçalho sabe quem está logado.

   As páginas públicas não tinham por onde sair da conta: era preciso
   ir até o painel para achar o "Sair".

   Agora, com sessão aberta, um "Sair" aparece no cabeçalho. Sem
   sessão, nada muda.

   O estilo vem junto, injetado por este arquivo. Estes dois botões
   não existem no HTML de nenhuma página: nascem aqui, só quando há
   sessão. Guardá-los no assets/css/header.css junto com o resto do
   cabeçalho separaria o desenho de quem os cria, e quem mexesse num
   teria de lembrar do outro.

   Precisa de supabase-config.js e da biblioteca do Supabase antes.
   ===================================================================== */
(function () {
    'use strict';

    // Sem a biblioteca ou sem a configuração não há como perguntar se
    // existe sessão. A página continua funcionando como sempre.
    if (!window.supabase || !window.CONFIG_SUPABASE) {
        return;
    }

    const cliente = window.supabase.createClient(
        window.CONFIG_SUPABASE.url,
        window.CONFIG_SUPABASE.chavePublica
    );

    function injetarEstilo() {
        if (document.getElementById('estilo-sessao-topo')) return;

        const estilo = document.createElement('style');
        estilo.id = 'estilo-sessao-topo';
        estilo.textContent = `
            .btn-painel-topo,
            .btn-sair-topo {
                display: inline-flex;
                align-items: center;
                gap: 7px;
                height: 38px;
                padding: 0 14px;
                border: 1px solid #e2e8f0;
                border-radius: 6px;
                background: #ffffff;
                color: #475569;
                font-family: inherit;
                font-size: 0.78rem;
                font-weight: 700;
                letter-spacing: 0.4px;
                text-transform: uppercase;
                text-decoration: none;
                cursor: pointer;
                transition: all 0.2s;
                white-space: nowrap;
            }

            /* O painel é para onde se vai; o sair, de onde se vem. Um
               puxa para a cor da marca, o outro para o vermelho de quem
               encerra alguma coisa. */
            .btn-painel-topo:hover {
                border-color: #ff6600;
                color: #ff6600;
                background: #fff7ed;
            }

            .btn-sair-topo:hover {
                border-color: #e11d48;
                color: #e11d48;
                background: #fff1f2;
            }

            /* Em tela estreita ficam só os ícones: dois botões escritos
               por extenso não cabem ao lado do menu sanduíche. */
            @media (max-width: 600px) {
                .btn-painel-topo span,
                .btn-sair-topo span { display: none; }

                .btn-painel-topo,
                .btn-sair-topo { padding: 0 12px; }
            }
        `;
        document.head.appendChild(estilo);
    }

    async function sair(evento) {
        evento.preventDefault();
        await cliente.auth.signOut();

        // Recarrega em vez de só trocar os botões: se a pessoa estava
        // numa página que depende da sessão, ela precisa ser relida
        // como visitante.
        window.location.reload();
    }

    async function ajustarCabecalho() {
        const { data: { session } } = await cliente.auth.getSession();
        if (!session) return;

        const acoes = document.querySelector('.header-actions');
        if (!acoes || document.getElementById('btnSairTopo')) return;

        injetarEstilo();

        // Os dois botões de quem está de fora saem de cena. A chave
        // abre a tela de entrar, e quem já entrou não precisa dela; o
        // "+ CADASTRAR ANÚNCIO" leva a criar uma loja, e cada
        // anunciante só pode ter uma.
        acoes.querySelectorAll('.btn-icon-login, .btn-add-listing')
            .forEach((elemento) => elemento.remove());

        // No lugar deles, o caminho de volta. Sem este botão o painel
        // só seria alcançável digitando o endereço na barra.
        const painel = document.createElement('a');
        painel.id = 'btnPainelTopo';
        painel.className = 'btn-painel-topo';
        painel.href = 'dashboard/dashboard.html';
        painel.innerHTML = '<i class="fa-solid fa-gauge-high"></i> <span>Meu painel</span>';

        const botao = document.createElement('a');
        botao.id = 'btnSairTopo';
        botao.className = 'btn-sair-topo';
        botao.href = '#';
        botao.innerHTML = '<i class="fa-solid fa-right-from-bracket"></i> <span>Sair</span>';
        botao.addEventListener('click', sair);

        // O painel primeiro: é para onde a pessoa quer ir. Sair é uma
        // saída, e não deve ser a primeira coisa que o olho encontra.
        acoes.appendChild(painel);
        acoes.appendChild(botao);
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', ajustarCabecalho);
    } else {
        ajustarCabecalho();
    }
}());
