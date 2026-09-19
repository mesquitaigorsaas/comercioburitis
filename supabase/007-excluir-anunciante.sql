-- =====================================================================
-- EXCLUIR UM ANUNCIANTE PELO PAINEL
--
-- O painel precisava de um jeito de tirar um cadastro do guia por
-- inteiro: conta de login, cadastro do responsável e anúncio. Isso não
-- dá para fazer do navegador. A chave pública que o site usa não tem
-- permissão sobre auth.users, e a chave que teria nunca pode aparecer
-- no código de uma página — quem abrisse o painel a levaria embora.
--
-- A saída é esta função. Ela roda no banco com a permissão de quem a
-- criou, e antes de apagar qualquer coisa confere três condições. Se
-- alguma falhar, ela recusa e nada acontece.
--
-- Apagar a conta em auth.users basta: tanto o perfil quanto o anúncio
-- apontam para ela com "on delete cascade", então saem junto. Não é
-- preciso apagar em três lugares e torcer para nenhum falhar no meio.
-- =====================================================================

create or replace function public.admin_excluir_anunciante(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $funcao$
begin
    -- 1. Só administrador. Sem isto, qualquer pessoa logada poderia
    --    chamar a função direto pela API e apagar quem quisesse.
    if not public.eh_admin() then
        raise exception 'Apenas administradores podem excluir anunciantes.';
    end if;

    -- 2. Ninguém apaga a própria conta. É o clique de que mais se
    --    arrepende: o administrador se tranca para fora do painel e
    --    não há tela nenhuma para desfazer.
    if p_id = auth.uid() then
        raise exception 'Você não pode excluir a sua própria conta.';
    end if;

    -- 3. Um administrador não apaga outro por engano no meio da lista
    --    de anunciantes. Para tirar um administrador, tira-se antes o
    --    registro dele em public.admins — uma decisão consciente, e não
    --    um clique numa linha parecida com as outras.
    if exists (select 1 from public.admins where id = p_id) then
        raise exception 'Este cadastro é de um administrador. Remova-o de admins antes de excluir.';
    end if;

    delete from auth.users where id = p_id;

    -- Nada encontrado é erro, e não silêncio: se a linha já tinha sido
    -- apagada em outra aba, o painel precisa saber para não dizer que
    -- deu certo.
    if not found then
        raise exception 'Cadastro não encontrado.';
    end if;
end;
$funcao$;

grant execute on function public.admin_excluir_anunciante(uuid) to authenticated;


-- ---------------------------------------------------------------------
-- Conferência rápida, depois de rodar:
--
--   select public.eh_admin();
--   -- deve responder true quando você estiver logado como admin
--
-- A função em si só pode ser testada apagando alguém de verdade, então
-- não há consulta de teste inofensiva para ela.
-- ---------------------------------------------------------------------
