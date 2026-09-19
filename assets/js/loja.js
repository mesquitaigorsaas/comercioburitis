/* =====================================================================
   O que o guia sabe dizer sobre uma loja sem perguntar ao banco.

   Três respostas que a vitrine e a página da loja dão a partir do que
   já está gravado no anúncio: se está aberta agora, para onde vai o
   botão do WhatsApp e para onde vai o do mapa.

   Estavam escritas dentro da página do anúncio. Agora que o card da
   vitrine também precisa das três, ficam aqui — senão a vitrine diria
   "Aberto" e a página da loja diria "Fechado" no mesmo minuto, cada
   uma com a sua conta.
   ===================================================================== */
(function () {
    'use strict';

    // getDay() devolve 0 para domingo; o formulário grava 'dom'.
    const DIA_DA_SEMANA = ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sab'];

    function emMinutos(hhmm) {
        if (!hhmm) return null;
        const [h, m] = String(hhmm).split(':').map(Number);
        if (Number.isNaN(h) || Number.isNaN(m)) return null;
        return h * 60 + m;
    }

    // Um dia está aberto no minuto pedido?
    //
    // O expediente que fecha depois da meia-noite (um bar das 18:00 às
    // 02:00) chega aqui com o fechamento menor que a abertura. Nesse
    // caso a janela é partida em duas: do abre até o fim do dia, e do
    // começo do dia até o fecha.
    function dentroDaJanela(dia, minutos) {
        if (!dia || !dia.aberto) return false;

        const abre = emMinutos(dia.abre);
        const fecha = emMinutos(dia.fecha);
        if (abre === null || fecha === null) return false;

        if (fecha > abre) return minutos >= abre && minutos < fecha;
        return minutos >= abre || minutos < fecha;
    }

    /**
     * A loja está aberta neste instante?
     *
     * Devolve null — e não false — quando a loja não informou horário
     * nenhum. Táxi não abre nem fecha, e escrever "Fechado" na vitrine
     * dele seria mentir para quem procura corrida às três da manhã.
     */
    function estaAbertaAgora(horarios, quando) {
        if (!horarios || typeof horarios !== 'object') return null;
        if (Object.keys(horarios).length === 0) return null;

        const agora = quando || new Date();
        const minutos = agora.getHours() * 60 + agora.getMinutes();
        const hoje = DIA_DA_SEMANA[agora.getDay()];

        if (dentroDaJanela(horarios[hoje], minutos)) return true;

        // Uma da manhã de domingo ainda é o sábado do bar que fecha às
        // 02:00. Sem olhar para o dia anterior, ele apareceria fechado
        // justamente na hora de maior movimento.
        const ontem = DIA_DA_SEMANA[(agora.getDay() + 6) % 7];
        const diaDeOntem = horarios[ontem];
        if (diaDeOntem && diaDeOntem.aberto) {
            const abre = emMinutos(diaDeOntem.abre);
            const fecha = emMinutos(diaDeOntem.fecha);
            if (abre !== null && fecha !== null && fecha <= abre && minutos < fecha) {
                return true;
            }
        }

        return false;
    }

    /** O link do WhatsApp, com o 55 do Brasil na frente. */
    function linkWhatsapp(numero) {
        const so = String(numero || '').replace(/\D/g, '');
        return so ? 'https://wa.me/55' + so : '';
    }

    /**
     * O link do mapa.
     *
     * O endereço gravado vai até o bairro, sem a cidade — ela é coluna
     * própria do anúncio. Endereço sem cidade acha rua de nome parecido
     * em outro estado, então a cidade e o UF entram aqui, só na busca.
     */
    function linkMapa(endereco, cidade) {
        if (!endereco) return '';
        const busca = `${endereco}, ${cidade || ''} - MG`.replace(/\s+-\s+MG$/, ' - MG');
        return 'https://www.google.com/maps/search/?api=1&query=' + encodeURIComponent(busca);
    }

    window.LOJA = { estaAbertaAgora, linkWhatsapp, linkMapa };
}());
