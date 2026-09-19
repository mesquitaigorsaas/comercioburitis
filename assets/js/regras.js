/* =====================================================================
   As regras comerciais do guia, num lugar só.

   Até 30/09/2026 o cadastro é grátis. A partir de 01/10/2026 quem quer
   anunciar escolhe e paga um plano.

   Essa data decide duas coisas em telas diferentes: se a faixa laranja
   da página inicial aparece, e quantas fotos o anunciante pode subir.
   Se cada tela guardasse a própria cópia da data, bastaria mudar de
   ideia uma vez para o site ficar dizendo duas coisas ao mesmo tempo —
   faixa no ar prometendo grátis, formulário cobrando plano.

   Mudou aqui, mudou no site inteiro.
   ===================================================================== */
window.REGRAS = {

    // Último instante da promoção. Depois disto a faixa some e o
    // pagamento entra no caminho do cadastro.
    gratisAte: new Date('2026-09-30T23:59:59'),

    promocaoValendo() {
        return new Date() <= this.gratisAte;
    },

    // Táxi e moto táxi não pagam, nem agora nem depois da promoção.
    // O guia banca essa categoria de propósito: transporte é o que o
    // morador procura com pressa, e ter os telefones desde o primeiro
    // dia vale mais para o guia do que a mensalidade de um taxista.
    //
    // Quem é dela não escolhe plano, não tem vencimento e não entra na
    // contagem dos três meses. O cadastro também é outro, mais curto:
    // nome, telefone e uma foto, porque taxista não tem vitrine, nem
    // horário de funcionamento, nem endereço para o cliente visitar.
    categoriaGratuita: 'Táxi e Moto Táxi',

    ehGratuita(categoria) {
        return categoria === this.categoriaGratuita;
    },

    // Uma foto, e opcional: costuma ser o carro ou o próprio motorista.
    fotosDaCategoriaGratuita: 1,

    // Durante a promoção: 1 logomarca + 5 fotos = 6 imagens por loja.
    // A logo é contada à parte porque tem lugar próprio no formulário.
    //
    // São 5, e não mais, porque quem entra na promoção já entra como
    // trimestral — e trimestral dá 5. Assim o número nunca muda: não
    // existe a sexta foto que a pessoa publica agora para vê-la sumir
    // quando a cobrança começar.
    fotosNaPromocao: 5,

    // Depois da promoção, quem manda é o plano contratado.
    fotosPorPlano: {
        trimestral: 5,
        semestral: 10,
        anual: 15
    },

    // "Anúncios em destaque", na página inicial, não tem teto: são
    // quatro por fileira e quantas fileiras forem precisas.
    //
    // Havia um limite de 8. Ele criava um problema que só apareceria
    // depois: com a nona loja cadastrada, alguém que também entrou de
    // graça ficaria fora da vitrine sem nunca ter sido avisado disso.
    // Numa promoção de lançamento, é o contrário do que se quer — cada
    // loja nova é uma razão a mais para o morador voltar ao guia.
    //
    // A ordem continua sendo a de cadastro, com os destacados na
    // frente: quem chegou primeiro aparece primeiro.

    /**
     * Quantas fotos esta loja pode ter (fora a logomarca).
     *
     * Enquanto a promoção vale, o limite é igual para todo mundo — não
     * existe plano escolhido para consultar.
     */
    limiteDeFotos(plano, categoria) {
        if (this.ehGratuita(categoria)) {
            return this.fotosDaCategoriaGratuita;
        }

        if (this.promocaoValendo()) {
            return this.fotosNaPromocao;
        }

        // Quem se cadastra na promoção é gravado como trimestral, então
        // depois de 01/10/2026 encontra aqui o próprio plano e continua
        // com as mesmas 5 fotos que já tinha. Nada muda para ele.
        //
        // O `??` ainda serve para anúncios antigos, gravados sem plano
        // nenhum antes desta regra existir: esses ficam com as fotos da
        // promoção em vez de cair para zero.
        return this.fotosPorPlano[plano] ?? this.fotosNaPromocao;
    },

    // Quanto tempo cada plano dura. A contagem começa na data em que o
    // anúncio foi cadastrado, não numa data única do guia: quem entrou
    // em 5 de setembro tem três meses a partir do dia 5, e não o resto
    // que sobrou de um prazo coletivo.
    mesesPorPlano: {
        trimestral: 3,
        semestral: 6,
        anual: 12
    },

    /**
     * Até quando o plano desta loja vale.
     *
     * Recebe a data de cadastro (o `criado_em` do anúncio) e o plano
     * gravado nele. Devolve uma data, ou null quando não há plano —
     * anúncio antigo, de antes desta regra existir.
     */
    validadeDoPlano(criadoEm, plano, categoria) {
        // Categoria gratuita não vence: não há plano correndo.
        if (this.ehGratuita(categoria)) {
            return null;
        }

        const meses = this.mesesPorPlano[plano];
        if (!criadoEm || !meses) {
            return null;
        }

        const fim = new Date(criadoEm);
        const diaOriginal = fim.getDate();
        fim.setMonth(fim.getMonth() + meses);

        // Cadastro em 31 de agosto + 3 meses cairia em 1º de dezembro,
        // porque novembro não tem dia 31 e o JavaScript transborda para
        // o mês seguinte. `setDate(0)` volta para o último dia do mês
        // pretendido — 30 de novembro, que é o que a pessoa entende por
        // "três meses depois".
        if (fim.getDate() < diaOriginal) {
            fim.setDate(0);
        }

        return fim;
    },

    /**
     * A validade escrita como a pessoa lê: "02/12/2026".
     * Devolve string vazia quando não há plano, para o chamador poder
     * jogar direto no HTML sem testar nada.
     */
    validadeEscrita(criadoEm, plano, categoria) {
        const fim = this.validadeDoPlano(criadoEm, plano, categoria);
        return fim ? fim.toLocaleDateString('pt-BR') : '';
    }
};
