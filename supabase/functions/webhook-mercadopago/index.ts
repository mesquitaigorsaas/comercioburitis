// ============================================================
// supabase/functions/webhook-mercadopago/index.ts
//
// O aviso do Mercado Pago de que um pagamento mudou. É por aqui que
// o plano e o destaque do Guia Comercial são liberados: a pessoa paga
// na página do Mercado Pago, e o aviso chega aqui logo depois.
//
// Copiada da do Achei Água & Gás, que usa a mesma conta do Mercado
// Pago. As duas convivem: cada uma só mexe nos pagamentos que
// encontra na própria tabela, e ignora o resto.
//
// Este endereço é público, e por isso nunca acredita no que recebe:
//
//   1. Quando o aviso vem assinado, confere a assinatura com o
//      segredo do painel do Mercado Pago.
//   2. Sempre pergunta ao Mercado Pago o que aconteceu de verdade,
//      em vez de ler status e valor do corpo do aviso.
//   3. Confere o valor que caiu contra o valor que a nossa linha de
//      pagamento esperava.
//
// A segunda barreira é a que decide. Um aviso sem assinatura também
// é processado, porque o Mercado Pago manda os do notification_url
// de cada cobrança sem ela; o pior que um aviso forjado consegue é
// fazer a gente consultar um pagamento real e gravar a verdade.
//
// Suba com --no-verify-jwt: quem chama é o Mercado Pago, sem conta.
//
// Segredos: MERCADOPAGO_ACCESS_TOKEN e MERCADOPAGO_WEBHOOK_SECRET.
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const MP_TOKEN = Deno.env.get("MERCADOPAGO_ACCESS_TOKEN") ?? "";
const MP_SEGREDO = Deno.env.get("MERCADOPAGO_WEBHOOK_SECRET") ?? "";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
    // O Mercado Pago às vezes testa o endereço com um GET.
    if (req.method !== "POST") return json({ ok: true });

    const url = new URL(req.url);
    let corpo: { type?: string; action?: string; data?: { id?: string | number } } = {};
    try {
        corpo = await req.json();
    } catch {
        // Os avisos antigos vêm só com parâmetros na URL.
    }

    const tipo = corpo.type ?? url.searchParams.get("type") ?? url.searchParams.get("topic") ?? "";
    const ehPagamento = tipo === "payment" || String(corpo.action ?? "").startsWith("payment.");
    const idPagamento = String(url.searchParams.get("data.id") ?? corpo.data?.id ?? url.searchParams.get("id") ?? "");

    // 200 de propósito para o que não interessa: responder erro faria o
    // Mercado Pago reenviar o mesmo aviso por dias.
    if (!ehPagamento || !/^\d+$/.test(idPagamento)) return json({ ignorado: true });

    if (!(await assinaturaConfere(req, idPagamento))) {
        console.warn("[webhook] assinatura inválida para o pagamento", idPagamento);
        return json({ erro: "assinatura inválida" }, 401);
    }

    const mp = await fetch(`https://api.mercadopago.com/v1/payments/${idPagamento}`, {
        headers: { Authorization: `Bearer ${MP_TOKEN}` }
    });

    if (!mp.ok) {
        console.error("[webhook] não consegui consultar", idPagamento, await mp.text());
        // 500 faz o Mercado Pago tentar de novo mais tarde, que é o certo
        // quando a falha foi nossa.
        return json({ erro: "consulta falhou" }, 500);
    }

    const real = await mp.json();
    const referencia = String(real.external_reference ?? "");

    // Pagamento de outro produto da mesma conta do Mercado Pago.
    if (!UUID.test(referencia)) return json({ ignorado: true });

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    const { data: pagamento } = await supabase
        .from("pagamentos")
        .select("id, valor, status, creditado_em")
        .eq("id", referencia)
        .maybeSingle();

    if (!pagamento) {
        console.warn("[webhook] referência sem pagamento nosso:", referencia);
        return json({ ignorado: true });
    }

    let situacao = situacaoDe(String(real.status));

    // Caiu menos do que custa: não libera. Só acontece se alguém mexer
    // na cobrança por fora, e aí quem decide é o administrador.
    const valorPago = Number(real.transaction_amount);
    if (situacao === "pago" && (real.currency_id !== "BRL" || !(valorPago + 0.001 >= Number(pagamento.valor)))) {
        console.error("[webhook] valor diferente do plano:", referencia, valorPago, pagamento.valor);
        situacao = "pendente";
    }

    const { error } = await supabase
        .from("pagamentos")
        .update({
            gateway_id: String(real.id),
            metodo: real.payment_type_id ?? null,
            status: situacao,
            retorno: real,
            atualizado_em: new Date().toISOString()
        })
        .eq("id", pagamento.id);

    if (error) {
        console.error("[webhook] não gravou o pagamento:", error);
        return json({ erro: "falha ao gravar" }, 500);
    }

    if (situacao === "pago" && !pagamento.creditado_em) {
        const { error: erroCredito } = await supabase.rpc("creditar_pagamento", { p_pagamento: pagamento.id });
        if (erroCredito) {
            console.error("[webhook] não creditou:", erroCredito);
            return json({ erro: "falha ao creditar" }, 500);
        }
    }

    // Estorno e contestação ficam gravados, e o anúncio continua no ar
    // até o administrador decidir. Tirar sozinho puniria quem pediu o
    // estorno de uma cobrança duplicada.
    if (situacao === "estornado" && pagamento.creditado_em) {
        console.warn("[webhook] pagamento creditado foi estornado:", referencia);
    }

    return json({ ok: true, status: situacao });
});


/**
 * A assinatura HMAC do Mercado Pago, quando existe.
 *
 * O manifesto é "id:<data.id>;request-id:<x-request-id>;ts:<ts>;", e
 * a assinatura vem no cabeçalho x-signature como "ts=...,v1=...".
 */
async function assinaturaConfere(req: Request, idPagamento: string): Promise<boolean> {
    const assinatura = req.headers.get("x-signature");
    if (!MP_SEGREDO || !assinatura) return true;

    const partes = Object.fromEntries(
        assinatura.split(",").map((p) => {
            const [chave, valor] = p.split("=");
            return [chave?.trim(), valor?.trim()];
        })
    );
    if (!partes.ts || !partes.v1) return false;

    const manifesto = `id:${idPagamento};request-id:${req.headers.get("x-request-id") ?? ""};ts:${partes.ts};`;

    const chave = await crypto.subtle.importKey(
        "raw",
        new TextEncoder().encode(MP_SEGREDO),
        { name: "HMAC", hash: "SHA-256" },
        false,
        ["sign"]
    );
    const assinado = await crypto.subtle.sign("HMAC", chave, new TextEncoder().encode(manifesto));
    const esperado = Array.from(new Uint8Array(assinado)).map((b) => b.toString(16).padStart(2, "0")).join("");

    // Comparação em tempo constante: comparar com === vazaria, pelo tempo
    // de resposta, quantos caracteres iniciais estavam certos.
    if (esperado.length !== partes.v1.length) return false;
    let diferenca = 0;
    for (let i = 0; i < esperado.length; i++) {
        diferenca |= esperado.charCodeAt(i) ^ partes.v1.charCodeAt(i);
    }
    return diferenca === 0;
}

function situacaoDe(status: string): string {
    if (status === "approved") return "pago";
    if (status === "rejected" || status === "cancelled") return "cancelado";
    if (status === "refunded" || status === "charged_back") return "estornado";
    return "pendente";
}

function json(corpo: unknown, status = 200) {
    return new Response(JSON.stringify(corpo), {
        status,
        headers: { "Content-Type": "application/json" }
    });
}
