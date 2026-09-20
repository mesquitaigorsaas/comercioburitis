# Guia Comercial Buritis e Região

Guia de comércios e prestadores de serviço do Buritis e dos bairros
vizinhos, em Belo Horizonte (MG). Quem procura acha pelo bairro e pela categoria; quem tem
loja cadastra a dela e aparece.

Cópia do Guia Comercial Alfenas, adaptada para o Buritis (BH). Ainda
não está no ar — veja as pendências abaixo.

## Pendências para colocar no ar

1. **Supabase próprio:** criar um projeto novo, rodar os SQLs de
   `supabase/` na ordem e colar URL + chave anon em
   `assets/js/supabase-config.js`. Trocar também o `--project-ref` dos
   comandos de deploy mais abaixo.
2. **Repositório / GitHub Pages:** criar o repositório `comercioburitis`.
3. **Domínio:** se houver, criar o arquivo `CNAME` com ele e conferir as
   origens liberadas em `supabase/functions/criar-pagamento/index.ts`
   (hoje: comercioburitis.com.br e mesquitaigorsaas.github.io/comercioburitis).
4. **Nada de graça:** promoção e categoria gratuita já estão desligadas
   (ver "Sem nada de graça" abaixo).
5. **Imagens:** capa da página de planos (hoje é só texto) e o card do
   plano trimestral, que ainda mostra a igreja de Alfenas.
6. **Banner da home:** hoje é um "anuncie aqui" em HTML; banner pago
   entra em 2188x718 no lugar dele, em `index.html`.

### Como a região funciona

Todas as lojas gravam cidade = `belo horizonte`; o bairro fica no
endereço. O foco agora são Buritis, Estoril, Palmeiras, Havaí e Betânia.

---

## Como funciona

Site estático — HTML, CSS e JavaScript, sem framework e sem build. É
só abrir os arquivos. O GitHub Pages publica sozinho a cada `push` na
branch `main`.

Os dados ficam no **Supabase**: banco, contas de acesso e as imagens
dos anúncios.

### Rodando na sua máquina

Não basta abrir o arquivo com duplo clique: o navegador bloqueia
parte do JavaScript em páginas abertas direto do disco. Suba um
servidor local na pasta do projeto:

```bash
npx serve .
```

E abra o endereço que ele mostrar.

---

## Onde fica cada coisa

| Pasta / arquivo | O que é |
|---|---|
| `index.html` | Página inicial: busca e a vitrine de destaques |
| `planos.html` | Preços dos planos |
| `sobrenos.html`, `fale-conosco.html` | Páginas institucionais |
| `anuncio-detalhes.html` | A página de uma loja |
| `auth/` | Criar conta, entrar e recuperar senha |
| `dashboard/` | Painel do anunciante e o formulário do anúncio |
| `assets/css/header.css` | O cabeçalho e o menu sanduíche, para o site inteiro |
| `assets/js/menu.js` | Abre e fecha esse menu no celular |
| `assets/js/supabase-config.js` | Endereço e chave pública do banco |
| `assets/js/regras.js` | Datas e limites da promoção |
| `assets/js/menu-promocao.js` | Para onde aponta o botão de cadastrar |
| `supabase/` | Os SQLs que montam o banco |

### Os dois arquivos de configuração

Vale conhecer, porque quase toda mudança de regra passa por eles.

**`supabase-config.js`** guarda o endereço do projeto no Supabase e a
chave pública. Antes, esses dois valores estavam copiados dentro de
cada uma das sete páginas — quando o projeto do banco mudou de
endereço, o site inteiro parou e o conserto seria trocar a mesma coisa
em sete arquivos sem esquecer nenhum.

**`regras.js`** guarda a data do fim da promoção e os limites de foto.
A mesma data decide se as faixas laranja aparecem, quantas fotos o
anunciante pode subir e para onde vai o botão de cadastrar. Separadas,
essas telas podiam passar a discordar entre si — faixa prometendo
grátis enquanto o formulário já cobrasse plano.

---

## Sem nada de graça

No Buritis não há promoção de lançamento nem categoria isenta (em
Alfenas havia cadastro grátis até 30/09/2026 e táxi grátis). Toda loja
escolhe e paga um plano para entrar no ar; as fotos dependem do plano
(5, 10 ou 15).

Os interruptores ficam em `assets/js/regras.js` (`gratisAte` e
`categoriaGratuita`, ambos `null`) e, no banco, nas funções
`promocao_valendo()` e `eh_categoria_gratuita()` do `013-pagamento.sql`,
que devolvem `false`.

---

## Cobrança dos planos

Pix ou cartão (até 12x), pela página de pagamento do Mercado Pago
(Checkout Pro), na mesma conta do Achei Água & Gás.

- **Toda loja nova** nasce fora do ar. O cadastro termina na caixa de
  pagamento do painel, com o plano escolhido já marcado. Pagou, entra
  no ar sozinha. Táxi e Moto Táxi também pagam.
- **Destaque (R$ 120 / 15 dias)**: compra no painel, só para quem está
  no ar. Desliga sozinho de madrugada quando os 15 dias acabam.
- **Pagou por fora** (Pix direto, dinheiro): no painel do
  administrador, mude a data de vencimento da loja. Libera na hora.

Como funciona por dentro:

| Peça | O que faz |
|---|---|
| `supabase/013-pagamento.sql` | Vencimento (`vence_em`), tabela `pagamentos`, a regra de quem aparece na busca e a trava que impede o dono de mudar plano/vencimento/destaque pela API |
| `supabase/functions/criar-pagamento` | Cria a cobrança no Mercado Pago com o preço daqui (nunca o da tela) e devolve o link |
| `supabase/functions/webhook-mercadopago` | Recebe o aviso, confere no Mercado Pago e credita |
| `dashboard/dashboard.html` | A caixa "Plano e pagamento" e o recado da volta do Mercado Pago |

### Colocar no ar (nesta ordem)

1. **SQL:** no Supabase do Guia → SQL Editor → cole `supabase/013-pagamento.sql` → Run.
   A última consulta mostra cada loja com o vencimento que ganhou.
2. **Token do Mercado Pago:** Supabase do Guia → Edge Functions → Secrets →
   `MERCADOPAGO_ACCESS_TOKEN` = o mesmo *Access Token de produção* usado no
   Água & Gás (Mercado Pago → Suas integrações → Credenciais de produção).
3. **Funções:** na pasta do projeto, com o Supabase CLI logado:

   ```
   npx supabase functions deploy criar-pagamento --no-verify-jwt --project-ref REF-DO-PROJETO-BURITIS
   npx supabase functions deploy webhook-mercadopago --no-verify-jwt --project-ref REF-DO-PROJETO-BURITIS
   ```

4. **Só depois dos três passos acima**, publique o site (`git push`). O
   site novo lê a coluna `vence_em`: publicado antes do SQL, a vitrine
   da página inicial fica vazia.
5. **Teste:** pague o plano trimestral de uma loja de teste com Pix
   (no painel do administrador, apague o vencimento dela antes, para
   ela aparecer como "aguardando pagamento").

---

## Banco de dados

Os arquivos em `supabase/` devem ser rodados no SQL Editor do
Supabase, **nesta ordem**, num projeto novo:

1. `schema.sql` — tabela `anuncios`, segurança e o depósito de imagens
2. `perfis.sql` — dados do responsável, com CPF/CNPJ conferido
3. `003-facebook.sql` — coluna do Facebook
4. `004-admin.sql` — quem é administrador e o que o painel enxerga
5. `005-cadastro-rapido.sql` — CPF/CNPJ deixa de ser obrigatório

O `004` tem, no fim do arquivo, um comando comentado que diz quem é o
administrador. Sem rodá-lo, ninguém entra no painel de administração —
nem você.

### Como a segurança funciona

Todo acesso passa por *Row Level Security*: sem regra escrita, ninguém
lê nem escreve nada. O que vale é:

- **Anúncios** são públicos para leitura — é um guia, existem para
  serem vistos. Só o dono cria, edita e apaga o dele.
- **Perfis** (nome, CPF/CNPJ, endereço) só são visíveis para o próprio
  dono. Nem visitantes nem outros anunciantes alcançam.
- **Visualizações e cliques no WhatsApp** são somados por funções do
  banco, não por escrita direta. Liberar alteração da tabela para o
  visitante anônimo — que é quem dispara essa contagem — deixaria
  qualquer um reescrever o anúncio de qualquer loja.
- **CPF/CNPJ é opcional**, porque as primeiras lojas do guia entram por
  visita ao comércio, e pedir o documento de alguém numa primeira
  conversa trava a conversa. Quem informar tem os dígitos conferidos
  duas vezes — na tela, para avisar na hora, e no banco, que é o que
  garante — e não pode repetir o de outro, para uma pessoa não abrir
  várias contas e ocupar o guia sozinha enquanto o cadastro é grátis.
  Quem não informar fica com o campo em branco, e o administrador
  completa depois pelo painel. Em branco o valor é *nulo*, nunca texto
  vazio: dois textos vazios brigariam entre si na regra de "não pode
  repetir", e o segundo cadastro sem documento seria recusado.

### A chave que aparece no código

A chave em `supabase-config.js` é pública de propósito: ela viaja até
o navegador de quem visita, e qualquer um pode lê-la. Não é descuido —
é assim que o Supabase funciona. Quem decide o que cada pessoa pode
ver e mexer são as regras acima, do lado do banco.

**A senha do banco não está no repositório e não deve entrar nele.**
Ela vive só no painel do Supabase, e de lá pode ser redefinida quando
for preciso, em *Project Settings → Database*. Se um dia for guardá-la
num arquivo aqui, use um nome que o `.gitignore` já cubra.
