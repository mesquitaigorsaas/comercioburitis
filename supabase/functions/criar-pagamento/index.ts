// ============================================================
// supabase/functions/criar-pagamento/index.ts
//
// Abre a página de pagamento do Mercado Pago (Checkout Pro) para o
// anunciante logado. Lá ele paga com Pix ou cartão.
//
// Quem chama é o painel (dashboard/dashboard.html), só com o que está
// sendo comprado: { tipo: 'plano', plano: 'anual' } ou
// { tipo: 'destaque' }. A resposta traz o endereço para onde mandar
// a pessoa.
//
// Duas coisas que o navegador poderia mandar são ignoradas de
// propósito:
//
//   - o valor: sai da tabela PRECOS, abaixo. Se viesse da tela,
//     bastaria alterar o campo para pagar um centavo;
//   - o anúncio: sai da sessão. Se viesse da tela, bastaria trocar o
//     id para pagar e liberar a loja de outra pessoa.
//
// Quem credita é a webhook-mercadopago, quando o aviso do pagamento
// aprovado chega.
//
// Suba com --no-verify-jwt: a sessão é conferida aqui dentro, com
// auth.getUser().
//
// Segredos: MERCADOPAGO_ACCESS_TOKEN.
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const MP_TOKEN = Deno.env.get("MERCADOPAGO_ACCESS_TOKEN") ?? "";

// Os mesmos valores de planos.html. Os de lá só desenham a tela;
// quem cobra são estes.
const PLANOS: Record<string, { valor: number; titulo: string }> = {
    trimestral: { valor: 29.7, titulo: "Guia Buritis — Plano Trimestral (3 meses) | Mesquita SaaS" },
    semestral: { valor: 53.46, titulo: "Guia Buritis — Plano Semestral (6 meses) | Mesquita SaaS" },
    anual: { valor: 100.98, titulo: "Guia Buritis — Plano Anual (12 meses) | Mesquita SaaS" }
};
const DESTAQUE = { valor: 120, titulo: "Guia Buritis — Destaque por 15 dias | Mesquita SaaS" };

// Para onde o Mercado Pago devolve a pessoa depois de pagar. Só estes
// endereços: se viesse livre do navegador, dava para usar o botão de
// pagamento do guia para mandar gente para qualquer site.
const SITES = [
    "https://comercioburitis.com.br",
    "https://www.comercioburitis.com.br",
    "https://mesquitaigorsaas.github.io/comercioburitis",
    "http://localhost:3000",
    "http://127.0.0.1:3000"
];

// Buritis: nenhuma categoria é gratuita (em Alfenas era "Táxi e Moto Táxi").
const CATEGORIA_GRATUITA: string | null = null;

const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type"
};

Deno.serve(async (req) => {
    if (req.method === "OPTIONS") {
        return new Response("ok", { headers: corsHeaders });
    }

    if (!MP_TOKEN) {
        return resposta({ erro: "O pagamento ainda não está configurado. Fale com a gente pelo WhatsApp." }, 503);
    }

    try {
        const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

        // --- quem está pagando ------------------------------------
        const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
        const { data: sessao } = await supabase.auth.getUser(token);
        if (!sessao?.user) {
            return resposta({ erro: "Sua sessão expirou. Entre de novo para pagar." }, 401);
        }

        const { data: anuncio } = await supabase
            .from("anuncios")
            .select("id, titulo, categoria, ativo, vence_em")
            .eq("user_id", sessao.user.id)
            .maybeSingle();

        if (!anuncio) {
            return resposta({ erro: "Cadastre a sua loja antes de escolher o plano." }, 400);
        }

        // Anúncio tirado do ar pelo administrador não volta pagando.
        // Cobrar e não liberar seria pegar o dinheiro e não entregar.
        if (!anuncio.ativo) {
            return resposta({ erro: "Este anúncio está fora do ar por decisão do guia. Fale com a gente pelo WhatsApp antes de pagar." }, 403);
        }

        // --- o que está sendo comprado ----------------------------
        const body = await req.json().catch(() => ({}));
        const tipo = body?.tipo === "destaque" ? "destaque" : "plano";

        let item: { valor: number; titulo: string };
        let plano: string | null = null;

        if (tipo === "plano") {
            if (anuncio.categoria === CATEGORIA_GRATUITA) {
                return resposta({ erro: "Táxi e moto táxi não pagam plano no guia." }, 400);
            }
            plano = String(body?.plano ?? "");
            if (!PLANOS[plano]) return resposta({ erro: "Escolha o plano." }, 400);
            item = PLANOS[plano];
        } else {
            // Destaque serve para quem já aparece. Comprar destaque para
            // um anúncio fora do ar seria pagar para não ser visto.
            const hoje = new Date().toLocaleDateString("sv-SE", { timeZone: "America/Sao_Paulo" });
            const noAr = anuncio.categoria === CATEGORIA_GRATUITA || (anuncio.vence_em && anuncio.vence_em >= hoje);
            if (!noAr) {
                return resposta({ erro: "Ative um plano antes de comprar o destaque." }, 400);
            }
            item = DESTAQUE;
        }

        const site = siteDeVolta(body?.voltar);

        // --- a linha do pagamento, antes de cobrar ----------------
        const { data: pagamento, error: erroPagamento } = await supabase
            .from("pagamentos")
            .insert({ anuncio_id: anuncio.id, user_id: sessao.user.id, tipo, plano, valor: item.valor })
            .select("id")
            .single();

        if (erroPagamento) throw erroPagamento;

        // --- a página de pagamento --------------------------------
        const painel = `${site}/dashboard/dashboard.html`;
        const preferencia = {
            items: [{
                id: plano ?? "destaque",
                title: item.titulo,
                description: anuncio.titulo,
                quantity: 1,
                currency_id: "BRL",
                unit_price: item.valor
            }],
            payer: { email: String(sessao.user.email ?? "") || undefined },
            external_reference: pagamento.id,
            notification_url: `${SUPABASE_URL}/functions/v1/webhook-mercadopago`,
            back_urls: {
                success: `${painel}?pagamento=aprovado`,
                pending: `${painel}?pagamento=pendente`,
                failure: `${painel}?pagamento=recusado`
            },
            auto_return: "approved",
            // Pix e cartão. Boleto fica de fora: leva dias para compensar,
            // e a loja ficaria fora do ar esperando.
            payment_methods: {
                excluded_payment_types: [{ id: "ticket" }, { id: "atm" }],
                installments: 12
            },
            // O que sai na fatura do cartão (limite de 22 caracteres).
            // É o nome da empresa, e não o do guia: quem vende é a mesma
            // empresa em todos os guias, e é esse nome que dá credibilidade.
            // Em compensação, o título do item acima leva os dois nomes —
            // quem não reconhecer a fatura acha o guia pelo e-mail da compra.
            statement_descriptor: "MESQUITA SAAS"
        };

        const mp = await fetch("https://api.mercadopago.com/checkout/preferences", {
            method: "POST",
            headers: {
                Authorization: `Bearer ${MP_TOKEN}`,
                "Content-Type": "application/json",
                "X-Idempotency-Key": pagamento.id
            },
            body: JSON.stringify(preferencia)
        });

        const criado = await mp.json().catch(() => null);

        if (!mp.ok || !criado?.init_point) {
            console.error("[criar-pagamento] o Mercado Pago recusou:", JSON.stringify(criado));
            await supabase.from("pagamentos")
                .update({ status: "cancelado", retorno: criado, atualizado_em: new Date().toISOString() })
                .eq("id", pagamento.id);
            return resposta({ erro: "Não foi possível abrir o pagamento. Tente de novo em instantes." }, 502);
        }

        await supabase.from("pagamentos")
            .update({ preferencia_id: String(criado.id), atualizado_em: new Date().toISOString() })
            .eq("id", pagamento.id);

        return resposta({ url: criado.init_point, pagamento: pagamento.id });

    } catch (erro) {
        console.error("[criar-pagamento] erro inesperado:", erro);
        return resposta({ erro: "Não foi possível abrir o pagamento. Tente de novo em instantes." }, 500);
    }
});


function siteDeVolta(pedido: unknown): string {
    const texto = String(pedido ?? "").replace(/\/+$/, "");
    return SITES.includes(texto) ? texto : SITES[0];
}

function resposta(corpo: unknown, status = 200) {
    return new Response(JSON.stringify(corpo), {
        status,
        headers: { ...corsHeaders, "Content-Type": "application/json" }
    });
}
