/* =====================================================================
   Localização: "o que está perto de mim".

   O guia não separa por bairro. Quem está na divisa do Buritis com o
   Estoril quer o que está a 500 metros, e não o que por acaso tem o
   mesmo nome de bairro no cadastro.

   São duas pontas:

   1. A LOJA ganha um ponto no mapa quando se cadastra. O endereço
      digitado vai ao Nominatim (OpenStreetMap), que devolve latitude e
      longitude, e elas ficam gravadas junto do anúncio. É uma consulta
      por loja, na hora do cadastro — dentro do uso gratuito, que pede
      no máximo uma por segundo e crédito ao OpenStreetMap (está no
      rodapé da página inicial).

   2. QUEM PROCURA é localizado pelo próprio navegador, com a permissão
      dele. A conta de distância acontece aqui dentro, na máquina da
      pessoa: a localização dela não é enviada para o nosso banco nem
      para lugar nenhum. Isso importa — a maior parte de quem recusa a
      permissão recusa por desconfiança, e o site diz isso na tela.

   Nada aqui é obrigatório para o site funcionar. Sem permissão, sem
   coordenada na loja ou com o Nominatim fora do ar, a vitrine volta a
   ser a de sempre.
   ===================================================================== */
window.GEO = {

    // Meia hora. A pessoa que abre o guia de novo na mesma sessão não
    // é perguntada outra vez, e uma localização velha de manhã não
    // ordena a busca da noite.
    VALIDADE_MS: 30 * 60 * 1000,

    CHAVE: 'guia:local',

    // Até aqui, o destaque pago continua vindo na frente. Passou disso,
    // vale a distância: um destaque a 5 km na frente da loja da esquina
    // faz o guia parecer errado para quem procura.
    RAIO_DESTAQUE_KM: 2,

    /**
     * Distância em linha reta, em quilômetros (fórmula de Haversine).
     *
     * Linha reta, e não distância de rua: para ordenar uma lista de
     * bairro vizinho ela erra pouco, e não depende de serviço nenhum.
     */
    distanciaKm(lat1, lon1, lat2, lon2) {
        const R = 6371;
        const rad = (g) => (g * Math.PI) / 180;
        const dLat = rad(lat2 - lat1);
        const dLon = rad(lon2 - lon1);
        const a = Math.sin(dLat / 2) ** 2
            + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLon / 2) ** 2;
        return 2 * R * Math.asin(Math.sqrt(a));
    },

    /** "450 m", "1,2 km" — metros até 1 km, porque "0,45 km" ninguém lê. */
    formatarDistancia(km) {
        if (km === null || km === undefined || !isFinite(km)) return '';
        if (km < 1) return `${Math.round(km * 100) * 10} m`;
        return `${km.toFixed(1).replace('.', ',')} km`;
    },

    /* ----------------------------------------------------------------
       Onde está quem procura
       ---------------------------------------------------------------- */

    guardado() {
        try {
            const bruto = sessionStorage.getItem(this.CHAVE);
            if (!bruto) return null;
            const local = JSON.parse(bruto);
            if (!local || Date.now() - local.em > this.VALIDADE_MS) return null;
            return local;
        } catch {
            // Aba anônima, armazenamento bloqueado: segue sem memória.
            return null;
        }
    },

    guardar(local) {
        try {
            sessionStorage.setItem(this.CHAVE, JSON.stringify({ ...local, em: Date.now() }));
        } catch {
            /* sem memória entre páginas, e o site continua igual */
        }
    },

    esquecer() {
        try { sessionStorage.removeItem(this.CHAVE); } catch { /* idem */ }
    },

    /**
     * Pede a localização ao navegador. Devolve {lat, lon, origem} ou
     * lança um erro com o motivo já traduzido para a tela.
     *
     * Só funciona em HTTPS (e em localhost, para testar). No GitHub
     * Pages isso já vem pronto.
     */
    pedirLocalizacaoDoNavegador() {
        return new Promise((resolve, reject) => {
            if (!navigator.geolocation) {
                reject(new Error('Seu navegador não sabe informar a localização.'));
                return;
            }

            navigator.geolocation.getCurrentPosition(
                (pos) => resolve({
                    lat: pos.coords.latitude,
                    lon: pos.coords.longitude,
                    origem: 'navegador'
                }),
                (erro) => {
                    // Negada é o caso comum, e não é falha: a pessoa
                    // decidiu. Os outros dois são problema de sinal.
                    const recado = erro.code === erro.PERMISSION_DENIED
                        ? 'Você não permitiu o acesso à localização.'
                        : 'Não consegui achar onde você está agora.';
                    reject(new Error(recado));
                },
                { enableHighAccuracy: true, timeout: 10000, maximumAge: 5 * 60 * 1000 }
            );
        });
    },

    /* ----------------------------------------------------------------
       De endereço para coordenada (Nominatim / OpenStreetMap)
       ---------------------------------------------------------------- */

    /**
     * Procura a coordenada de um endereço. Devolve {lat, lon} ou null.
     *
     * Duas tentativas: a primeira com número e complemento, a segunda
     * só com rua e bairro. Rua nova, ou número que o mapa não conhece,
     * devolve vazio na primeira e acerta na segunda — e a rua certa no
     * bairro certo já ordena bem uma lista de vizinhança.
     */
    async buscarCoordenadas({ logradouro, numero, bairro, cidade = 'Belo Horizonte', uf = 'MG' }) {
        const tentativas = [
            [logradouro, numero].filter(Boolean).join(', '),
            logradouro
        ].filter(Boolean);

        for (const [posicao, rua] of tentativas.entries()) {
            // O uso gratuito do Nominatim pede no máximo uma consulta
            // por segundo. Duas seguidas em milissegundos voltam com
            // 429 e a loja salvaria sem ponto sem motivo nenhum — a
            // segunda tentativa espera.
            if (posicao > 0) await new Promise((r) => setTimeout(r, 1100));

            const endereco = [rua, bairro, cidade, uf, 'Brasil'].filter(Boolean).join(', ');
            const url = 'https://nominatim.openstreetmap.org/search'
                + `?format=json&limit=1&countrycodes=br&q=${encodeURIComponent(endereco)}`;

            try {
                const resposta = await fetch(url, { headers: { 'Accept-Language': 'pt-BR' } });
                if (!resposta.ok) continue;

                const achados = await resposta.json();
                if (!achados || !achados.length) continue;

                const lat = parseFloat(achados[0].lat);
                const lon = parseFloat(achados[0].lon);
                if (isFinite(lat) && isFinite(lon)) return { lat, lon };
            } catch {
                // Serviço fora do ar ou sem internet: o cadastro segue
                // sem coordenada, e a loja aparece na vitrine do mesmo
                // jeito — só não entra na ordem por distância.
                return null;
            }
        }

        return null;
    },

    /**
     * O caminho de quem não quis dar a localização: digita o CEP.
     * ViaCEP devolve rua e bairro, o Nominatim devolve o ponto.
     */
    async coordenadasDoCep(cep) {
        const digitos = (cep || '').replace(/\D/g, '');
        if (digitos.length !== 8) throw new Error('Digite um CEP com 8 números.');

        let endereco;
        try {
            const resposta = await fetch(`https://viacep.com.br/ws/${digitos}/json/`);
            endereco = await resposta.json();
        } catch {
            throw new Error('Não consegui consultar o CEP agora.');
        }

        if (!endereco || endereco.erro) throw new Error('CEP não encontrado.');

        const ponto = await this.buscarCoordenadas({
            logradouro: endereco.logradouro,
            bairro: endereco.bairro,
            cidade: endereco.localidade,
            uf: endereco.uf
        });

        if (!ponto) throw new Error('Não achei esse CEP no mapa.');

        return { ...ponto, origem: 'cep', rotulo: endereco.bairro || endereco.localidade };
    },

    /* ----------------------------------------------------------------
       A ordem da vitrine
       ---------------------------------------------------------------- */

    /**
     * Ordena os anúncios em relação a um ponto, e marca cada um com a
     * distância (em `_distanciaKm`) para o card poder mostrá-la.
     *
     * A ordem:
     *   1. destaques pagos que estejam dentro do raio, do mais perto
     *      ao mais longe;
     *   2. todo o resto, do mais perto ao mais longe;
     *   3. quem não tem coordenada, no fim, na ordem em que veio do
     *      banco — some da conta, mas não some da vitrine.
     */
    ordenarPorDistancia(anuncios, local) {
        const comDistancia = anuncios.map((anuncio, posicao) => {
            const lat = parseFloat(anuncio.latitude);
            const lon = parseFloat(anuncio.longitude);
            const temPonto = isFinite(lat) && isFinite(lon);

            anuncio._distanciaKm = temPonto
                ? this.distanciaKm(local.lat, local.lon, lat, lon)
                : null;

            return { anuncio, posicao };
        });

        const faixa = ({ anuncio }) => {
            if (anuncio._distanciaKm === null) return 2;
            if (anuncio.destaque && anuncio._distanciaKm <= this.RAIO_DESTAQUE_KM) return 0;
            return 1;
        };

        return comDistancia
            .sort((a, b) => {
                const fa = faixa(a);
                const fb = faixa(b);
                if (fa !== fb) return fa - fb;
                if (fa === 2) return a.posicao - b.posicao;
                return a.anuncio._distanciaKm - b.anuncio._distanciaKm;
            })
            .map(({ anuncio }) => anuncio);
    }
};
