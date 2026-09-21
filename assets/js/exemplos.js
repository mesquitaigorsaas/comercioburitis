/* =====================================================================
   CINCO ANÚNCIOS DE EXEMPLO

   Para que servem: um guia com a vitrine vazia não se explica sozinho.
   Quem chega — e principalmente o lojista a quem o guia está sendo
   apresentado — precisa ver como a loja dele vai aparecer.

   Três decisões que evitam problema:

   1. As lojas são INVENTADAS. Nenhum nome, telefone ou endereço de
      comércio real entra aqui. Anúncio falso com dado de loja de
      verdade é problema para o guia e para ela.

   2. Cada card leva o selo EXEMPLO, e não tem WhatsApp nem página de
      detalhes. Ninguém liga para um número que não existe, e ninguém
      confunde a demonstração com um anunciante pagante.

   3. Eles só aparecem quando a busca não traz NENHUM anúncio de
      verdade, e nunca dentro de uma categoria. No dia em que o
      primeiro lojista pagar, os exemplos somem sozinhos.

   Como tirar de vez: apague este arquivo e a linha que o carrega no
   index.html. O resto do site não depende dele.
   ===================================================================== */

window.EXEMPLOS = [
    {
        id: 'exemplo-1',
        titulo: 'Padaria Pão do Morro',
        categoria: 'Supermercados e Padarias',
        descricao: 'Pão quente de duas em duas horas, bolo caseiro, salgados e café passado na hora. Atendemos o Buritis e o Estoril.',
        cidade: 'belo horizonte',
        imagem_url: 'assets/img/exemplos/padaria.jpg',
        entrega: true,
        aberto: true
    },
    {
        id: 'exemplo-2',
        titulo: 'Pet Shop Patas & Cia',
        categoria: 'Pet Shop e Veterinária',
        descricao: 'Banho e tosa com hora marcada, consulta veterinária, ração e acessórios. Leva e traz no bairro.',
        cidade: 'belo horizonte',
        imagem_url: 'assets/img/exemplos/petshop.jpg',
        entrega: true,
        aberto: true
    },
    {
        id: 'exemplo-3',
        titulo: 'Studio Corpo em Movimento',
        categoria: 'Academias, Pilates e Esportes',
        descricao: 'Pilates, funcional e musculação com turmas pequenas e acompanhamento de perto. Primeira aula experimental.',
        cidade: 'belo horizonte',
        imagem_url: 'assets/img/exemplos/studio.jpg',
        entrega: false,
        aberto: true
    },
    {
        id: 'exemplo-4',
        titulo: 'Cantina Nonna Rosa',
        categoria: 'Restaurantes e Gastronomia',
        descricao: 'Massas frescas, pizza na pedra e almoço executivo de segunda a sexta. Salão para famílias e delivery no bairro.',
        cidade: 'belo horizonte',
        imagem_url: 'assets/img/exemplos/cantina.jpg',
        entrega: true,
        aberto: false
    },
    {
        id: 'exemplo-5',
        titulo: 'Farmácia Vida Nova',
        categoria: 'Farmácias, Saúde',
        descricao: 'Manipulação, medicamentos de uso contínuo, aferição de pressão e aplicação de injetáveis. Entrega rápida.',
        cidade: 'belo horizonte',
        imagem_url: 'assets/img/exemplos/farmacia.jpg',
        entrega: true,
        aberto: true
    }
];
