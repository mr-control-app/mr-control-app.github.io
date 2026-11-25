# Mr. Control

Controle de consumo de suplemento a pasto. Endereço: **https://mr-control-app.github.io**

```
Planilhas "Folha Suplementação" ──► App (lê no navegador) ──► Banco (Supabase) ──► todos os usuários da fazenda
```

O app lê as planilhas no próprio aparelho e grava no banco só o conteúdo delas (retiro, mês, pastos, cabeças, sacos por data).
Quem tem acesso à fazenda vê tudo salvo, em qualquer aparelho. O Mr. Control é **independente do Mr. Report**:
outro endereço, outro banco e outro cadastro de pessoas.

| Pasta / arquivo | O que tem |
|---|---|
| `index.html` | o app |
| `config.js` | endereço e chave **pública** do banco |
| `sw.js` | funcionamento sem internet (só arquivos do app) |
| `supabase/01_mr_control.sql` | tabelas, login, permissões e funções do banco |
| `.github/workflows/manter-ativo.yml` | evita que o Supabase gratuito pause o banco |

Nenhum dado de fazenda e nenhuma senha ficam neste repositório.

---

## Quem vê o quê (igual ao Mr. Report)

| Papel | Como entra | Pode |
|---|---|---|
| **Administrador** | usuário (nome.sobrenome) + senha | todas as fazendas; cadastra fazendas e pessoas; apaga planilhas; edita e restaura ajustes |
| **Técnico** | usuário + senha | só as fazendas marcadas para ele; envia e apaga planilhas; edita ajustes |
| **Equipe da fazenda** | só a senha da fazenda | vê a própria fazenda e envia planilhas |

Segurança: senhas guardadas com criptografia; 10 senhas erradas em 15 minutos bloqueiam o endereço por 15 minutos;
sessão vale 180 dias no aparelho; trocar a senha de uma fazenda ou desativar uma pessoa desconecta na hora.
Cada envio, substituição e exclusão de planilha fica registrado com nome e horário (aba **Planilhas**).

---

## Instalação (uma vez)

### 1. Banco de dados (Supabase): projeto próprio do Mr. Control
1. Em **supabase.com**, crie um projeto novo chamado `mr-control`, na região *South America (São Paulo)*.
   **Não use o projeto do Mr. Report.** O plano gratuito permite 2 projetos ativos.
2. Abra **SQL Editor → New query**, cole todo o conteúdo de `supabase/01_mr_control.sql` e clique em **Run**.
3. Abra outra query, troque nome, usuário e senha pelos seus e rode:
   ```sql
   select public.definir_primeiro_adm('Seu Nome Completo', 'nome.sobrenome', 'uma-senha-forte');
   ```
   A senha precisa ter pelo menos 8 caracteres. As próximas pessoas são cadastradas pelo app.
4. Anote:
   - **URL do projeto**: Project Settings → Data API (formato `https://xxxx.supabase.co`);
   - **Chave pública**: Project Settings → API Keys, a *publishable* (`sb_publishable_...`) ou *anon*.
     **Nunca** use a chave *secret* / *service_role*.

### 2. Ligar o app ao banco
5. No GitHub, abra `config.js` → ícone de lápis → preencha `url` e `chave` → **Commit changes**.
   Essas duas informações podem ficar visíveis: o banco só aceita as funções com login.
6. Em 1 a 2 minutos, abra **https://mr-control-app.github.io**. Deve aparecer a tela de login.

### 3. Primeiro uso
7. Entre com o seu usuário. Na aba **Fazendas**, cadastre cada fazenda: código (ex.: `mafra`), nome e **senha da equipe**.
8. Na aba **Pessoas**, cadastre os técnicos e marque as fazendas de cada um.
9. Escolha a fazenda e clique em **Inserir planilhas**. Pode selecionar várias de uma vez.
   Reenviar o mesmo retiro e mês **substitui** a versão anterior (para correções).
10. No celular: abra o endereço e use "Adicionar à tela inicial".

### 4. Manter ativo
O Supabase gratuito pausa o projeto depois de 7 dias sem uso. O robô `Manter ativo` (aba **Actions**) chama o banco
a cada 3 dias sozinho. Para testar: **Actions → Manter ativo → Run workflow** (deve terminar com ✅).

### 5. Backup semanal por e-mail
Toda **segunda-feira ~07:17** (Brasília) o robô `Backup semanal por e-mail` manda aos **administradores ativos que
têm e-mail** (aba **Pessoas**) um anexo `mr-control-backup-AAAA-MM-DD.json.gz` com todas as fazendas, planilhas,
ajustes, históricos e o registro. **Sem senhas** (nem criptografadas) e sem sessões. O backup não fica guardado
no GitHub (o repositório é público): só vai por e-mail, e o log do robô mostra apenas contagens.

**a) Atualizar o banco (uma vez).** Supabase → **SQL Editor → New query** → cole o arquivo
`supabase/01_mr_control.sql` inteiro de novo → **Run**. Ele só acrescenta o campo de e-mail e as funções do backup;
não apaga nada. (Se aparecer aviso de "destructive operation", é só a troca da função de salvar pessoa: confirme.)

**b) E-mail dos administradores.** No app, aba **Pessoas** → **Editar** cada administrador → preencha **E-mail** → Salvar.

**c) Endereço de conexão do banco.** Supabase → botão **Connect** (topo) → aba **Connection string** →
em *Method* escolha **Session pooler** → copie o endereço que começa com `postgresql://postgres.`…
Troque `[YOUR-PASSWORD]` pela senha do banco criada junto com o projeto. Esqueceu? **Project Settings → Database →
Reset database password** (não afeta o app, que usa a chave publicável).

**d) Senha de app do Gmail** (a conta que vai *enviar*; pode ser a mesma do Mr. Report). Precisa ter verificação em
duas etapas ligada. Abra https://myaccount.google.com/apppasswords → nome `Mr Control` → **Criar** → copie as 16 letras.

**e) Segredos no GitHub.** Repositório → **Settings → Secrets and variables → Actions → New repository secret**,
crie os três:

| Nome | Valor |
|---|---|
| `DATABASE_URL` | o endereço do passo c, já com a senha |
| `GMAIL_USUARIO` | o Gmail que envia, ex.: `mrcontrol.app@gmail.com` |
| `GMAIL_SENHA_APP` | as 16 letras do passo d |

**f) Testar.** **Actions → Backup semanal por e-mail → Run workflow**. Em ~1 min deve ficar ✅ e o e-mail chega
(confira o spam na primeira vez). Se ficar ❌, abra a execução: a mensagem diz o que faltou (segredo, senha do Gmail
ou nenhum adm com e-mail). Cada envio também aparece no **registro** do app como "backup enviado".

**Abrir o backup:** é um JSON compactado. No Windows, o 7-Zip descompacta o `.gz`; o `.json` abre em qualquer editor.

---

## Sem banco configurado
Com `config.js` vazio, o app funciona em **modo local**: as planilhas inseridas ficam salvas só naquele aparelho.

## Regras de cálculo (iguais ao BI Consumo v2)
- Consumo do trato = kg ÷ cabeças-dia até o próximo trato do mesmo Retiro + Pasto, mesmo que esteja na planilha
  do mês ou ano seguinte. Na virada do mês, os dias de cada mês usam as cabeças daquele mês.
- Consumo de um grupo = soma dos kg ÷ soma das cabeças-dia. Intervalo acima do limite (30 dias) = pasto vazio.
- Meta = peso estimado × % do produto; faixa = meta ± tolerância (25%). Produtos, metas, preços e regras ficam na aba
  **Ajustes**, por fazenda.
- O ano vem da data do trato; o mês aparece como "Setembro/2026".

## Formato esperado da planilha
Uma aba por retiro. B3 = retiro; B4 = mês; linha 5 = saída de fábrica (B) e animais por produto
(F MUB, G Adensado, H a L = 0.1 a 0.5); linha 7 = cabeçalho (Pasto, Quant. Animais, Peso Estimado, Categoria,
Tipo de sal, Área Retiro e uma coluna por data); a partir da linha 8, sacos fornecidos em cada data.
