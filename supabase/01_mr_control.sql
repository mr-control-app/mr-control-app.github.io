-- =====================================================================================
-- Mr. Control – banco de dados (Supabase / PostgreSQL)
-- Rode este arquivo inteiro UMA vez no "SQL Editor" de um projeto Supabase PRÓPRIO do Mr. Control
-- (não use o projeto do Mr. Report). Pode rodar de novo sem perder dados.
-- No final, rode a linha de "primeiro administrador" com o seu nome, usuário e senha.
--
-- Hierarquia (igual ao Mr. Report):
--  * Administrador (usuário + senha): todas as fazendas; cadastra fazendas e pessoas; restaura ajustes.
--  * Técnico (usuário + senha): só as fazendas liberadas para ele; envia/apaga planilhas e edita os ajustes delas.
--  * Equipe da fazenda (só a senha da fazenda): vê a própria fazenda e envia planilhas.
-- Nenhuma tabela é acessível direto pelo app: tudo passa pelas funções abaixo, que conferem a sessão.
-- =====================================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------- tabelas ----------
create table if not exists public.fazendas (
  id         text primary key check (id ~ '^[a-z0-9][a-z0-9-]{1,39}$'),
  nome       text not null,
  senha_hash text not null,
  ativa      boolean not null default true,
  criada_em  timestamptz not null default now()
);
create table if not exists public.pessoas (
  id         serial primary key,
  nome       text not null,
  usuario    text not null unique check (usuario ~ '^[a-z0-9]+(\.[a-z0-9]+)+$'),
  senha_hash text not null,
  papel      text not null check (papel in ('adm', 'tecnico', 'capataz')),
  ativa      boolean not null default true,
  criado_em  timestamptz not null default now()
);
create table if not exists public.pessoa_fazendas (
  pessoa_id  int  not null references public.pessoas(id) on delete cascade,
  fazenda_id text not null references public.fazendas(id) on delete cascade,
  primary key (pessoa_id, fazenda_id)
);
create table if not exists public.sessoes (
  token      text primary key,
  fazenda_id text references public.fazendas(id) on delete cascade,   -- equipe da fazenda
  pessoa_id  int  references public.pessoas(id)  on delete cascade,   -- administrador ou técnico
  criado_em  timestamptz not null default now(),
  expira_em  timestamptz not null default now() + interval '180 days',
  check ((fazenda_id is null) <> (pessoa_id is null))
);
create table if not exists public.login_falhas (
  quando timestamptz not null default now(),
  ip     text
);
create index if not exists login_falhas_quando on public.login_falhas(quando);

-- uma linha por aba de planilha (um retiro num mês). Reenviar o mesmo retiro/mês/ano substitui.
create table if not exists public.abas (
  id          bigserial primary key,
  fazenda_id  text not null references public.fazendas(id) on delete cascade,
  retiro      text not null,
  ano         int  not null check (ano between 2000 and 2100),
  mes         int  not null check (mes between 1 and 12),
  arquivo     text not null,
  aba         text not null,
  dados       jsonb not null,
  n_tratos    int  not null default 0,
  enviado_por text not null,
  enviado_em  timestamptz not null default now(),
  unique (fazenda_id, retiro, ano, mes)
);
create table if not exists public.config (
  fazenda_id     text primary key references public.fazendas(id) on delete cascade,
  dados          jsonb not null,
  atualizado_em  timestamptz not null default now(),
  atualizado_por text
);
create table if not exists public.config_hist (
  id         bigserial primary key,
  fazenda_id text not null references public.fazendas(id) on delete cascade,
  quando     timestamptz not null default now(),
  autor      text not null,
  acao       text not null default 'salvou',
  dados      jsonb not null
);
create index if not exists config_hist_faz on public.config_hist(fazenda_id, quando desc);
create table if not exists public.registro (
  id         bigserial primary key,
  quando     timestamptz not null default now(),
  fazenda_id text references public.fazendas(id) on delete cascade,
  autor      text not null,
  acao       text not null,
  detalhe    text
);
create index if not exists registro_faz on public.registro(fazenda_id, quando desc);
-- papéis: adm, tecnico, capataz (este último lança só nos retiros liberados; ver pessoa_fazendas.retiros)
alter table public.pessoas drop constraint if exists pessoas_papel_check;
alter table public.pessoas add constraint pessoas_papel_check check (papel in ('adm', 'tecnico', 'capataz'));
alter table public.pessoa_fazendas add column if not exists retiros text[] not null default '{}';
-- lançamentos feitos direto no app (um trato: retiro + pasto + data). Lançar de novo o mesmo pasto e dia corrige.
create table if not exists public.lancamentos (
  id         bigserial primary key,
  fazenda_id text not null references public.fazendas(id) on delete cascade,
  retiro     text not null,
  pasto      text not null,
  data       date not null,
  qtd        int  not null check (qtd between 1 and 100000),
  tipo       text not null,
  sacos      numeric(8,2) not null check (sacos > 0 and sacos <= 2000),
  peso       numeric(7,1) check (peso is null or peso between 20 and 1500),
  cat        text,
  autor      text not null,
  criado_em  timestamptz not null default now(),
  unique (fazenda_id, retiro, pasto, data)
);

do $$ declare t text; begin
  foreach t in array array['fazendas','pessoas','pessoa_fazendas','sessoes','login_falhas','abas','config','config_hist','registro','lancamentos'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- ---------- quem é a sessão ----------
create or replace function public._ip()
returns text language sql stable as $$
  select coalesce(
    nullif(current_setting('request.headers', true)::jsonb ->> 'cf-connecting-ip', ''),
    nullif(trim(split_part(coalesce(current_setting('request.headers', true)::jsonb ->> 'x-forwarded-for', ''), ',', 1)), ''),
    'desconhecido');
$$;
create or replace function public._sessao(p_token text)
returns public.sessoes language sql stable security definer set search_path = public as $$
  select * from public.sessoes where token = p_token and expira_em > now();
$$;
-- 'adm' | 'tecnico' | 'leitor' (senha da fazenda) | null (sessão inválida, pessoa ou fazenda desativada)
create or replace function public._papel(s public.sessoes)
returns text language sql stable set search_path = public as $$
  select case when s.token is null then null
              when s.fazenda_id is not null then (select 'leitor' from public.fazendas where id = s.fazenda_id and ativa)
              else (select papel from public.pessoas where id = s.pessoa_id and ativa) end;
$$;
create or replace function public._acessa(s public.sessoes, p_fazenda text)
returns boolean language sql stable set search_path = public as $$
  select case public._papel(s)
           when 'adm' then exists (select 1 from public.fazendas where id = p_fazenda)
           when 'leitor' then s.fazenda_id = p_fazenda
           when 'tecnico' then exists (select 1 from public.pessoa_fazendas pf join public.fazendas f on f.id = pf.fazenda_id
                                       where pf.pessoa_id = s.pessoa_id and pf.fazenda_id = p_fazenda and f.ativa)
           when 'capataz' then exists (select 1 from public.pessoa_fazendas pf join public.fazendas f on f.id = pf.fazenda_id
                                       where pf.pessoa_id = s.pessoa_id and pf.fazenda_id = p_fazenda and f.ativa)
           else false end;
$$;
create or replace function public._autor(s public.sessoes)
returns text language sql stable set search_path = public as $$
  select case when s.fazenda_id is not null then 'equipe da ' || coalesce((select nome from public.fazendas where id = s.fazenda_id), s.fazenda_id)
              else coalesce((select nome from public.pessoas where id = s.pessoa_id), '?') end;
$$;
create or replace function public._exige(p_token text, p_papeis text[], p_fazenda text default null)
returns public.sessoes language plpgsql stable set search_path = public as $$
declare s public.sessoes;
begin
  s := public._sessao(p_token);
  if s.token is null or public._papel(s) is null then raise exception 'sessao_expirada' using errcode = '28000'; end if;
  if not (public._papel(s) = any(p_papeis)) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  if p_fazenda is not null and not public._acessa(s, p_fazenda) then raise exception 'sem_permissao' using errcode = '42501'; end if;
  return s;
end $$;
create or replace function public._fazendas_de(p_pessoa int, p_papel text)
returns jsonb language sql stable set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'nome', f.nome,
           'retiros', coalesce((select to_jsonb(pf.retiros) from public.pessoa_fazendas pf where pf.pessoa_id = p_pessoa and pf.fazenda_id = f.id), '[]'::jsonb)) order by f.nome), '[]')
  from public.fazendas f
  where f.ativa and (p_papel = 'adm' or exists (select 1 from public.pessoa_fazendas pf where pf.pessoa_id = p_pessoa and pf.fazenda_id = f.id));
$$;
create or replace function public._bloqueado(v_ip text)
returns boolean language sql stable set search_path = public as $$
  select (select count(*) from public.login_falhas where ip = v_ip and quando > now() - interval '15 minutes') >= 10
      or (select count(*) from public.login_falhas where quando > now() - interval '15 minutes') >= 150;
$$;
create or replace function public._registrar(p_fazenda text, p_autor text, p_acao text, p_detalhe text)
returns void language sql set search_path = public as $$
  insert into public.registro(fazenda_id, autor, acao, detalhe) values (p_fazenda, p_autor, p_acao, left(p_detalhe, 500));
$$;

-- ---------- login ----------
-- Equipe da fazenda: só a senha da fazenda.
drop function if exists public.entrar(text);
create or replace function public.entrar(p_senha text, p_lembrar boolean default true)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare f record; tok text; v_ip text := public._ip();
begin
  delete from public.login_falhas where quando < now() - interval '1 day';
  delete from public.sessoes where expira_em < now();
  if public._bloqueado(v_ip) then return jsonb_build_object('erro', 'muitas_tentativas'); end if;
  if coalesce(p_senha, '') <> '' and length(p_senha) <= 200 then
    select * into f from public.fazendas where ativa and senha_hash = crypt(p_senha, senha_hash) limit 1;
    if found then
      tok := encode(gen_random_bytes(24), 'hex');
      insert into public.sessoes(token, fazenda_id, expira_em)
      values (tok, f.id, now() + case when coalesce(p_lembrar, true) then interval '180 days' else interval '12 hours' end);
      return jsonb_build_object('token', tok, 'papel', 'leitor', 'nome', null,
        'fazendas', jsonb_build_array(jsonb_build_object('id', f.id, 'nome', f.nome)));
    end if;
  end if;
  insert into public.login_falhas(ip) values (v_ip);
  perform pg_sleep(1);
  return jsonb_build_object('erro', 'senha_invalida');
end $$;

-- Administradores, técnicos e capatazes: usuário (nome.sobrenome) + senha própria.
drop function if exists public.entrar_usuario(text, text);
create or replace function public.entrar_usuario(p_usuario text, p_senha text, p_lembrar boolean default true)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare p public.pessoas; tok text; v_ip text := public._ip();
begin
  delete from public.login_falhas where quando < now() - interval '1 day';
  delete from public.sessoes where expira_em < now();
  if public._bloqueado(v_ip) then return jsonb_build_object('erro', 'muitas_tentativas'); end if;
  select * into p from public.pessoas where usuario = lower(trim(coalesce(p_usuario, ''))) and ativa;
  if p.id is null or coalesce(p_senha, '') = '' or length(p_senha) > 200 or p.senha_hash <> crypt(p_senha, p.senha_hash) then
    insert into public.login_falhas(ip) values (v_ip);
    perform pg_sleep(1);
    return jsonb_build_object('erro', 'usuario_invalido');
  end if;
  tok := encode(gen_random_bytes(24), 'hex');
  insert into public.sessoes(token, pessoa_id, expira_em)
  values (tok, p.id, now() + case when coalesce(p_lembrar, true) then interval '180 days' else interval '12 hours' end);
  return jsonb_build_object('token', tok, 'papel', p.papel, 'nome', p.nome, 'usuario', p.usuario,
                            'fazendas', public._fazendas_de(p.id, p.papel));
end $$;

create or replace function public.sair(p_token text)
returns void language sql security definer set search_path = public as $$
  delete from public.sessoes where token = p_token;
$$;

-- fazendas da sessão (o app atualiza ao abrir: acesso dado ou retirado vale sem sair)
create or replace function public.minhas_fazendas(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.sessoes;
begin
  s := public._exige(p_token, array['adm', 'tecnico', 'capataz', 'leitor']);
  if public._papel(s) = 'leitor' then
    return (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'nome', nome)), '[]') from public.fazendas where id = s.fazenda_id and ativa);
  end if;
  return public._fazendas_de(s.pessoa_id, public._papel(s));
end $$;

create or replace function public.trocar_senha(p_token text, p_atual text, p_nova text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare s public.sessoes; p public.pessoas;
begin
  s := public._exige(p_token, array['adm', 'tecnico', 'capataz']);
  select * into p from public.pessoas where id = s.pessoa_id;
  if p.senha_hash <> crypt(coalesce(p_atual, ''), p.senha_hash) then raise exception 'senha_atual_errada' using errcode = 'P0001'; end if;
  if length(coalesce(p_nova, '')) < 6 + 2 * (public._papel(s) <> 'capataz')::int then raise exception 'senha_curta_pessoa' using errcode = 'P0001'; end if;
  update public.pessoas set senha_hash = crypt(p_nova, gen_salt('bf')) where id = p.id;
  delete from public.sessoes where pessoa_id = p.id and token <> p_token;   -- sai dos outros aparelhos
end $$;

-- ---------- dados da fazenda (planilhas + ajustes) ----------
create or replace function public.dados(p_token text, p_fazenda text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public._exige(p_token, array['adm', 'tecnico', 'capataz', 'leitor'], p_fazenda);
  return jsonb_build_object(
    'capatazes', (select coalesce(jsonb_agg(jsonb_build_object('nome', p.nome, 'retiros', to_jsonb(pf.retiros)) order by p.nome), '[]')
                  from public.pessoa_fazendas pf join public.pessoas p on p.id = pf.pessoa_id
                  where pf.fazenda_id = p_fazenda and p.papel = 'capataz' and p.ativa),
    'fazenda', (select jsonb_build_object('id', id, 'nome', nome) from public.fazendas where id = p_fazenda),
    'gerado_em', now(),
    'abas', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'retiro', a.retiro, 'ano', a.ano, 'mes', a.mes, 'arquivo', a.arquivo,
                                                          'aba', a.aba, 'n_tratos', a.n_tratos, 'enviado_por', a.enviado_por,
                                                          'enviado_em', a.enviado_em, 'dados', a.dados) order by a.ano, a.mes, a.retiro), '[]')
             from public.abas a where a.fazenda_id = p_fazenda),
    'lancamentos', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'retiro', l.retiro, 'pasto', l.pasto, 'data', l.data, 'qtd', l.qtd,
                                                                 'tipo', l.tipo, 'sacos', l.sacos, 'peso', l.peso, 'cat', l.cat, 'autor', l.autor,
                                                                 'criado_em', l.criado_em) order by l.data, l.retiro, l.pasto), '[]')
                    from public.lancamentos l where l.fazenda_id = p_fazenda),
    'config', (select dados from public.config where fazenda_id = p_fazenda),
    'config_atualizado_em', (select atualizado_em from public.config where fazenda_id = p_fazenda),
    'config_atualizado_por', (select atualizado_por from public.config where fazenda_id = p_fazenda)
  );
end $$;

-- Envio de abas já lidas pelo app. p_abas = [{retiro, ano, mes, aba, dados}]. Substitui o mesmo retiro/mês/ano.
create or replace function public.enviar_abas(p_token text, p_fazenda text, p_arquivo text, p_abas jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.sessoes; a jsonb; v_ret text; v_ano int; v_mes int; existia boolean; n_ins int := 0; n_sub int := 0; autor text; nt int;
begin
  s := public._exige(p_token, array['adm', 'tecnico'], p_fazenda);
  if jsonb_typeof(p_abas) <> 'array' or jsonb_array_length(p_abas) = 0 then raise exception 'envio_vazio' using errcode = 'P0001'; end if;
  if jsonb_array_length(p_abas) > 60 or length(p_abas::text) > 6 * 1024 * 1024 then raise exception 'envio_grande' using errcode = 'P0001'; end if;
  if (select count(*) from public.registro where fazenda_id = p_fazenda and acao = 'enviou' and quando > now() - interval '1 day') >= 400 then
    raise exception 'limite_envios' using errcode = 'P0001'; end if;
  if (select count(*) from public.abas where fazenda_id = p_fazenda) >= 5000 then raise exception 'limite_abas' using errcode = 'P0001'; end if;
  autor := public._autor(s);
  for a in select * from jsonb_array_elements(p_abas) loop
    v_ret := upper(trim(coalesce(a->>'retiro', '')));
    v_ano := (a->>'ano')::int; v_mes := (a->>'mes')::int;
    if v_ret = '' or length(v_ret) > 80 or v_ano is null or v_mes is null or jsonb_typeof(a->'dados') <> 'object'
       or jsonb_typeof(a->'dados'->'linhas') <> 'array' then
      raise exception 'aba_invalida' using errcode = 'P0001'; end if;
    select coalesce(sum(jsonb_array_length(l->'t')), 0) into nt from jsonb_array_elements(a->'dados'->'linhas') l where jsonb_typeof(l->'t') = 'array';
    select true into existia from public.abas where fazenda_id = p_fazenda and retiro = v_ret and ano = v_ano and mes = v_mes;
    insert into public.abas(fazenda_id, retiro, ano, mes, arquivo, aba, dados, n_tratos, enviado_por, enviado_em)
    values (p_fazenda, v_ret, v_ano, v_mes, left(coalesce(p_arquivo, '?'), 200), left(coalesce(a->>'aba', '?'), 100), a->'dados', nt, autor, now())
    on conflict (fazenda_id, retiro, ano, mes) do update
      set arquivo = excluded.arquivo, aba = excluded.aba, dados = excluded.dados, n_tratos = excluded.n_tratos,
          enviado_por = excluded.enviado_por, enviado_em = excluded.enviado_em;
    if existia then n_sub := n_sub + 1; else n_ins := n_ins + 1; end if;
    existia := null;
    perform public._registrar(p_fazenda, autor, 'enviou', v_ret || ' ' || lpad(v_mes::text, 2, '0') || '/' || v_ano || ' (' || left(coalesce(p_arquivo, '?'), 200) || ')');
  end loop;
  return jsonb_build_object('inseridas', n_ins, 'substituidas', n_sub);
end $$;

-- Apagar uma aba (planilha de um retiro num mês): administrador e técnico.
create or replace function public.apagar_aba(p_token text, p_fazenda text, p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare s public.sessoes; a public.abas;
begin
  s := public._exige(p_token, array['adm', 'tecnico'], p_fazenda);
  delete from public.abas where id = p_id and fazenda_id = p_fazenda returning * into a;
  if a.id is null then raise exception 'aba_inexistente' using errcode = 'P0001'; end if;
  perform public._registrar(p_fazenda, public._autor(s), 'apagou', a.retiro || ' ' || lpad(a.mes::text, 2, '0') || '/' || a.ano || ' (' || a.arquivo || ')');
end $$;

-- Lançar um trato pelo app: administrador e técnico (qualquer retiro) e capataz (só nos retiros liberados).
-- O login com a senha da fazenda é só observador: não lança.
-- Data só de hoje para trás (horário de Brasília). O mesmo retiro + pasto + dia substitui o anterior.
create or replace function public.lancar(p_token text, p_fazenda text, p_lanc jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.sessoes; autor text; v_ret text; v_pasto text; v_tipo text; v_cat text; v_data date; v_qtd int; v_sacos numeric; v_peso numeric;
        hoje date := (now() at time zone 'America/Sao_Paulo')::date; existia boolean; v_id bigint;
begin
  s := public._exige(p_token, array['adm', 'tecnico', 'capataz'], p_fazenda);
  if jsonb_typeof(p_lanc) <> 'object' or length(p_lanc::text) > 2000 then raise exception 'lancamento_invalido' using errcode = 'P0001'; end if;
  v_ret   := upper(trim(coalesce(p_lanc->>'retiro', '')));
  v_pasto := upper(trim(coalesce(p_lanc->>'pasto', '')));
  v_tipo  := upper(trim(coalesce(p_lanc->>'tipo', '')));
  v_cat   := nullif(upper(trim(coalesce(p_lanc->>'cat', ''))), '');
  if v_ret = '' or length(v_ret) > 80 or v_pasto = '' or length(v_pasto) > 40 then raise exception 'pasto_obrigatorio' using errcode = 'P0001'; end if;
  if v_tipo = '' or length(v_tipo) > 80 then raise exception 'tipo_obrigatorio' using errcode = 'P0001'; end if;
  if public._papel(s) = 'capataz' and not exists (select 1 from public.pessoa_fazendas
       where pessoa_id = s.pessoa_id and fazenda_id = p_fazenda and v_ret = any(retiros)) then
    raise exception 'retiro_nao_liberado' using errcode = '42501'; end if;
  begin
    v_data := (p_lanc->>'data')::date; v_qtd := (p_lanc->>'qtd')::int; v_sacos := (p_lanc->>'sacos')::numeric; v_peso := nullif(p_lanc->>'peso', '')::numeric;
  exception when others then raise exception 'lancamento_invalido' using errcode = 'P0001'; end;
  if v_data is null or v_data > hoje then raise exception 'data_futura' using errcode = 'P0001'; end if;
  if v_data < date '2020-01-01' then raise exception 'data_antiga' using errcode = 'P0001'; end if;
  if v_qtd is null or v_qtd < 1 or v_qtd > 100000 then raise exception 'animais_invalido' using errcode = 'P0001'; end if;
  if v_sacos is null or v_sacos <= 0 or v_sacos > 2000 then raise exception 'sacos_invalido' using errcode = 'P0001'; end if;
  if v_peso is not null and (v_peso < 20 or v_peso > 1500) then raise exception 'peso_invalido' using errcode = 'P0001'; end if;
  if (select count(*) from public.registro where fazenda_id = p_fazenda and acao = 'lançou' and quando > now() - interval '1 day') >= 1500 then
    raise exception 'limite_envios' using errcode = 'P0001'; end if;
  if (select count(*) from public.lancamentos where fazenda_id = p_fazenda) >= 100000 then raise exception 'limite_abas' using errcode = 'P0001'; end if;
  autor := public._autor(s);
  select true into existia from public.lancamentos where fazenda_id = p_fazenda and retiro = v_ret and pasto = v_pasto and data = v_data;
  insert into public.lancamentos(fazenda_id, retiro, pasto, data, qtd, tipo, sacos, peso, cat, autor)
  values (p_fazenda, v_ret, v_pasto, v_data, v_qtd, v_tipo, v_sacos, v_peso, left(v_cat, 80), autor)
  on conflict (fazenda_id, retiro, pasto, data) do update
    set qtd = excluded.qtd, tipo = excluded.tipo, sacos = excluded.sacos, peso = excluded.peso, cat = excluded.cat,
        autor = excluded.autor, criado_em = now()
  returning id into v_id;
  perform public._registrar(p_fazenda, autor, 'lançou', v_ret || ' pasto ' || v_pasto || ' ' || to_char(v_data, 'DD/MM/YYYY') || ': '
                                    || v_sacos || ' saco(s) ' || v_tipo || ', ' || v_qtd || ' cab.' || case when existia then ' (corrigiu)' else '' end);
  return jsonb_build_object('id', v_id, 'substituiu', coalesce(existia, false));
end $$;

-- Apagar um lançamento: administrador e técnico.
create or replace function public.apagar_lancamento(p_token text, p_fazenda text, p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare s public.sessoes; l public.lancamentos;
begin
  s := public._exige(p_token, array['adm', 'tecnico'], p_fazenda);
  delete from public.lancamentos where id = p_id and fazenda_id = p_fazenda returning * into l;
  if l.id is null then raise exception 'lancamento_inexistente' using errcode = 'P0001'; end if;
  perform public._registrar(p_fazenda, public._autor(s), 'apagou lançamento', l.retiro || ' pasto ' || l.pasto || ' ' || to_char(l.data, 'DD/MM/YYYY'));
end $$;

create or replace function public.registro_fazenda(p_token text, p_fazenda text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public._exige(p_token, array['adm', 'tecnico'], p_fazenda);
  return (select coalesce(jsonb_agg(jsonb_build_object('quando', quando, 'autor', autor, 'acao', acao, 'detalhe', detalhe) order by quando desc), '[]')
          from (select * from public.registro where fazenda_id = p_fazenda order by quando desc limit 200) r);
end $$;

-- ---------- ajustes (produtos, metas, regras) ----------
create or replace function public.salvar_config(p_token text, p_fazenda text, p_dados jsonb)
returns timestamptz language plpgsql security definer set search_path = public as $$
declare s public.sessoes; autor text; t timestamptz := now();
begin
  s := public._exige(p_token, array['adm', 'tecnico'], p_fazenda);
  if jsonb_typeof(p_dados) <> 'object' or length(p_dados::text) > 200000 then raise exception 'config_invalida' using errcode = 'P0001'; end if;
  autor := public._autor(s);
  insert into public.config(fazenda_id, dados, atualizado_em, atualizado_por) values (p_fazenda, p_dados, t, autor)
  on conflict (fazenda_id) do update set dados = excluded.dados, atualizado_em = t, atualizado_por = autor;
  insert into public.config_hist(fazenda_id, quando, autor, dados) values (p_fazenda, t, autor, p_dados);
  return t;
end $$;
create or replace function public.historico_config(p_token text, p_fazenda text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public._exige(p_token, array['adm', 'tecnico'], p_fazenda);
  return (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'quando', quando, 'autor', autor, 'acao', acao) order by quando desc), '[]')
          from (select * from public.config_hist where fazenda_id = p_fazenda order by quando desc limit 50) h);
end $$;
create or replace function public.restaurar_config(p_token text, p_fazenda text, p_id bigint)
returns timestamptz language plpgsql security definer set search_path = public as $$
declare s public.sessoes; d jsonb; autor text; t timestamptz := now();
begin
  s := public._exige(p_token, array['adm'], p_fazenda);
  select dados into d from public.config_hist where id = p_id and fazenda_id = p_fazenda;
  if d is null then raise exception 'versao_inexistente' using errcode = 'P0001'; end if;
  autor := public._autor(s);
  update public.config set dados = d, atualizado_em = t, atualizado_por = autor where fazenda_id = p_fazenda;
  insert into public.config_hist(fazenda_id, quando, autor, acao, dados) values (p_fazenda, t, autor, 'restaurou', d);
  return t;
end $$;

-- ---------- cadastros (só administrador) ----------
create or replace function public.adm_listar_fazendas(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public._exige(p_token, array['adm']);
  return (select coalesce(jsonb_agg(jsonb_build_object(
            'id', f.id, 'nome', f.nome, 'ativa', f.ativa, 'criada_em', f.criada_em,
            'n_abas', (select count(*) from public.abas a where a.fazenda_id = f.id),
            'ultimo_envio', (select max(enviado_em) from public.abas a where a.fazenda_id = f.id),
            'pessoas', (select coalesce(jsonb_agg(p.nome order by p.nome), '[]') from public.pessoa_fazendas pf join public.pessoas p on p.id = pf.pessoa_id
                        where pf.fazenda_id = f.id and p.ativa)) order by f.nome), '[]')
          from public.fazendas f);
end $$;

create or replace function public.adm_salvar_fazenda(p_token text, p_id text, p_nome text, p_senha text, p_ativa boolean default true)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare s public.sessoes; existe boolean; autor text;
begin
  s := public._exige(p_token, array['adm']);
  autor := public._autor(s);
  p_id := lower(trim(coalesce(p_id, '')));
  if p_id !~ '^[a-z0-9][a-z0-9-]{1,39}$' then raise exception 'codigo_invalido' using errcode = 'P0001'; end if;
  if coalesce(trim(p_nome), '') = '' then raise exception 'nome_obrigatorio' using errcode = 'P0001'; end if;
  if coalesce(p_senha, '') <> '' then
    if length(p_senha) < 6 then raise exception 'senha_curta' using errcode = 'P0001'; end if;
    if exists (select 1 from public.fazendas f where f.id <> p_id and f.senha_hash = crypt(p_senha, f.senha_hash)) then
      raise exception 'senha_repetida' using errcode = 'P0001'; end if;
  end if;
  select true into existe from public.fazendas where id = p_id;
  if existe is null then
    if coalesce(p_senha, '') = '' then raise exception 'senha_equipe_obrigatoria' using errcode = 'P0001'; end if;
    insert into public.fazendas(id, nome, senha_hash, ativa) values (p_id, trim(p_nome), crypt(p_senha, gen_salt('bf')), coalesce(p_ativa, true));
    perform public._registrar(p_id, autor, 'cadastrou a fazenda', trim(p_nome));
  else
    update public.fazendas set nome = trim(p_nome), ativa = coalesce(p_ativa, true) where id = p_id;
    if coalesce(p_senha, '') <> '' then
      update public.fazendas set senha_hash = crypt(p_senha, gen_salt('bf')) where id = p_id;
      delete from public.sessoes where fazenda_id = p_id;        -- troca de senha derruba a equipe logada
    end if;
    if not coalesce(p_ativa, true) then delete from public.sessoes where fazenda_id = p_id; end if;
    perform public._registrar(p_id, autor, 'alterou a fazenda', trim(p_nome) || case when coalesce(p_senha, '') <> '' then ' (nova senha)' else '' end
                                                                 || case when coalesce(p_ativa, true) then '' else ' (desativada)' end);
  end if;
  return jsonb_build_object('id', p_id, 'criada', existe is null);
end $$;

create or replace function public.adm_listar_pessoas(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public._exige(p_token, array['adm']);
  return (select coalesce(jsonb_agg(jsonb_build_object(
            'id', p.id, 'nome', p.nome, 'usuario', p.usuario, 'papel', p.papel, 'ativa', p.ativa,
            'fazendas', (select coalesce(jsonb_agg(pf.fazenda_id order by pf.fazenda_id), '[]') from public.pessoa_fazendas pf where pf.pessoa_id = p.id),
            'retiros', (select coalesce(jsonb_object_agg(pf.fazenda_id, to_jsonb(pf.retiros)), '{}') from public.pessoa_fazendas pf where pf.pessoa_id = p.id))
            order by p.ativa desc, p.nome), '[]')
          from public.pessoas p);
end $$;

drop function if exists public.adm_salvar_pessoa(text, int, text, text, text, text, boolean, text[]);
drop function if exists public.adm_salvar_pessoa(text, int, text, text, text, text, boolean, text[], text);   -- versão com e-mail (retirada)
-- p_retiros (só capataz): {"fazenda": ["RETIRO", ...]} = retiros liberados para lançar em cada fazenda
create or replace function public.adm_salvar_pessoa(p_token text, p_id int, p_nome text, p_usuario text, p_senha text,
                                                    p_papel text, p_ativa boolean, p_fazendas text[], p_retiros jsonb default null)
returns int language plpgsql security definer set search_path = public, extensions as $$
declare s public.sessoes; v_id int := p_id; autor text;
begin
  s := public._exige(p_token, array['adm']);
  autor := public._autor(s);
  p_usuario := lower(trim(coalesce(p_usuario, '')));
  if coalesce(trim(p_nome), '') = '' then raise exception 'nome_obrigatorio' using errcode = 'P0001'; end if;
  if p_usuario !~ '^[a-z0-9]+(\.[a-z0-9]+)+$' then raise exception 'usuario_invalido_formato' using errcode = 'P0001'; end if;
  if p_papel not in ('adm', 'tecnico', 'capataz') then raise exception 'papel_invalido' using errcode = 'P0001'; end if;
  if p_retiros is not null and (jsonb_typeof(p_retiros) <> 'object' or length(p_retiros::text) > 20000) then raise exception 'retiros_invalidos' using errcode = 'P0001'; end if;
  if exists (select 1 from public.pessoas where usuario = p_usuario and id is distinct from v_id) then
    raise exception 'usuario_repetido' using errcode = 'P0001'; end if;
  if coalesce(p_senha, '') <> '' and length(p_senha) < 6 + 2 * (p_papel <> 'capataz')::int then raise exception 'senha_curta_pessoa' using errcode = 'P0001'; end if;
  -- não deixa ficar sem nenhum administrador ativo
  if v_id is not null and (p_papel <> 'adm' or not coalesce(p_ativa, true))
     and exists (select 1 from public.pessoas where id = v_id and papel = 'adm' and ativa)
     and (select count(*) from public.pessoas where papel = 'adm' and ativa) <= 1 then
    raise exception 'ultimo_adm' using errcode = 'P0001'; end if;
  if v_id is null then
    if coalesce(p_senha, '') = '' then raise exception 'senha_obrigatoria' using errcode = 'P0001'; end if;
    insert into public.pessoas(nome, usuario, senha_hash, papel, ativa)
    values (trim(p_nome), p_usuario, crypt(p_senha, gen_salt('bf')), p_papel, coalesce(p_ativa, true)) returning id into v_id;
    perform public._registrar(null, autor, 'cadastrou a pessoa', trim(p_nome) || ' (' || p_papel || ')');
  else
    if not exists (select 1 from public.pessoas where id = v_id) then raise exception 'pessoa_inexistente' using errcode = 'P0001'; end if;
    update public.pessoas set nome = trim(p_nome), usuario = p_usuario, papel = p_papel, ativa = coalesce(p_ativa, true) where id = v_id;
    if coalesce(p_senha, '') <> '' then update public.pessoas set senha_hash = crypt(p_senha, gen_salt('bf')) where id = v_id; end if;
    if (coalesce(p_senha, '') <> '' or not coalesce(p_ativa, true)) and v_id is distinct from s.pessoa_id then
      delete from public.sessoes where pessoa_id = v_id; end if;    -- vale na hora
    perform public._registrar(null, autor, 'alterou a pessoa', trim(p_nome) || ' (' || p_papel || case when coalesce(p_ativa, true) then '' else ', desativada' end || ')');
  end if;
  delete from public.pessoa_fazendas where pessoa_id = v_id;
  if p_papel in ('tecnico', 'capataz') and p_fazendas is not null then
    insert into public.pessoa_fazendas(pessoa_id, fazenda_id, retiros)
    select v_id, f.id,
           case when p_papel = 'capataz' and jsonb_typeof(p_retiros -> f.id) = 'array' then
             (select coalesce(array_agg(distinct left(upper(trim(r)), 80)), '{}') from jsonb_array_elements_text(p_retiros -> f.id) r where trim(r) <> '')
           else '{}' end
    from public.fazendas f where f.id = any(p_fazendas) on conflict do nothing;
  end if;
  return v_id;
end $$;

-- retiros conhecidos de cada fazenda (planilhas, lançamentos e cadastro da aba Retiros) — para liberar capatazes
create or replace function public.adm_retiros(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public._exige(p_token, array['adm']);
  return (select coalesce(jsonb_object_agg(fazenda_id, rets), '{}') from (
    select fazenda_id, jsonb_agg(distinct retiro order by retiro) rets from (
      select fazenda_id, retiro from public.abas
      union select fazenda_id, retiro from public.lancamentos
      union select c.fazenda_id, upper(trim(r ->> 'nome')) from public.config c, jsonb_array_elements(case when jsonb_typeof(c.dados -> 'retiros') = 'array' then c.dados -> 'retiros' else '[]' end) r
            where coalesce(trim(r ->> 'nome'), '') <> ''
    ) x group by fazenda_id) y);
end $$;

-- ---------- manter o projeto ativo (o Supabase gratuito pausa após 7 dias sem uso) ----------
create or replace function public.manter_ativo()
returns timestamptz language sql security definer set search_path = public as $$
  select now();
$$;

-- ---------- primeiro administrador (rode no SQL Editor; não funciona pelo app) ----------
create or replace function public.definir_primeiro_adm(p_nome text, p_usuario text, p_senha text)
returns text language plpgsql security definer set search_path = public, extensions as $$
begin
  if exists (select 1 from public.pessoas where papel = 'adm' and ativa) then
    return 'Já existe administrador. Cadastre as próximas pessoas pelo app (aba Pessoas).';
  end if;
  if lower(trim(p_usuario)) !~ '^[a-z0-9]+(\.[a-z0-9]+)+$' then raise exception 'Usuário deve ser nome.sobrenome (minúsculas, sem acento)'; end if;
  if length(coalesce(p_senha, '')) < 8 then raise exception 'A senha precisa ter pelo menos 8 caracteres'; end if;
  insert into public.pessoas(nome, usuario, senha_hash, papel) values (trim(p_nome), lower(trim(p_usuario)), crypt(p_senha, gen_salt('bf')), 'adm')
  on conflict (usuario) do update set senha_hash = excluded.senha_hash, papel = 'adm', ativa = true, nome = excluded.nome;
  return 'Administrador criado. Entre no app com o usuário ' || lower(trim(p_usuario)) || '.';
end $$;

-- ---------- permissões: o app (chave pública "anon") só executa as funções abaixo ----------
revoke execute on all functions in schema public from public, anon, authenticated;
-- o app precisa enxergar o schema public para chamar as funções (vale mesmo se o projeto foi criado
-- com "Grant API access to new tables automatically" desmarcado). Tabelas continuam fechadas.
grant usage on schema public to anon;
grant execute on function
  public.entrar(text, boolean), public.entrar_usuario(text, text, boolean), public.sair(text), public.minhas_fazendas(text),
  public.trocar_senha(text, text, text), public.dados(text, text), public.enviar_abas(text, text, text, jsonb),
  public.apagar_aba(text, text, bigint), public.registro_fazenda(text, text),
  public.lancar(text, text, jsonb), public.apagar_lancamento(text, text, bigint),
  public.salvar_config(text, text, jsonb), public.historico_config(text, text), public.restaurar_config(text, text, bigint),
  public.adm_listar_fazendas(text), public.adm_salvar_fazenda(text, text, text, text, boolean),
  public.adm_listar_pessoas(text), public.adm_salvar_pessoa(text, int, text, text, text, text, boolean, text[], jsonb),
  public.adm_retiros(text),
  public.manter_ativo()
to anon;
notify pgrst, 'reload schema';

-- ============ DEPOIS DE RODAR TUDO ACIMA ============
-- Troque nome, usuário (nome.sobrenome) e senha (8+ caracteres) pelos seus e rode só esta linha:
-- select public.definir_primeiro_adm('Seu Nome Completo', 'nome.sobrenome', 'uma-senha-forte');
