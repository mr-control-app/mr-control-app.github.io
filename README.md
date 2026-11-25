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
| **Técnico** | usuário + senha | só as fazendas marcadas para ele; envia e apaga planilhas e lançamentos; edita ajustes |
| **Equipe da fazenda** | só a senha da fazenda | vê a própria fazenda, envia planilhas e lança tratos |

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
9. Escolha a fazenda, abra a aba **Planilhas** e clique em **Lançar planilhas**. Pode selecionar várias de uma vez.
   Reenviar o mesmo retiro e mês **substitui** a versão anterior (para correções).
10. No celular: abra o endereço e use "Adicionar à tela inicial".

### Atualização: aba Lançamentos (rodar uma vez se o banco já existia)
Supabase → **SQL Editor → New query** → cole o arquivo `supabase/01_mr_control.sql` inteiro → **Run**.
Ele só cria a tabela `lancamentos` e as funções `lancar` / `apagar_lancamento`; não apaga nada.
Antes disso, o app abre normalmente e só o botão **Lançar** avisa que falta atualizar o banco.

### 4. Manter ativo
O Supabase gratuito pausa o projeto depois de 7 dias sem uso. O robô `Manter ativo` (aba **Actions**) chama o banco
a cada 3 dias sozinho. Para testar: **Actions → Manter ativo → Run workflow** (deve terminar com ✅).

---

## Aba Lançamentos
As planilhas são enviadas na aba **Planilhas** (botão **Lançar planilhas**). Aqui se lança o consumo trato a trato.
- **Lançar consumo**: um trato por vez, pensado para o celular. Retiro → número do pasto → número de animais →
  tipo de sal → sacos → data. Ao escolher o pasto, animais, tipo de sal, peso e categoria vêm do último trato
  daquele pasto (dá para mudar). A data começa em **hoje** e só aceita datas passadas (o banco também recusa
  data futura, no horário de Brasília). Antes de lançar aparece um resumo; depois, o consumo do trato anterior do
  pasto, que o novo lançamento acabou de fechar.
- **Quem lança**: administrador, técnico e equipe da fazenda (como no envio de planilhas). **Quem apaga**:
  administrador e técnico. Tudo fica no registro (lançou / corrigiu / apagou lançamento).
- **Mesmo pasto e dia** lançado de novo **corrige** o anterior (não duplica).
- **Planilha x app**: se a planilha do mês trouxer o mesmo retiro, pasto e dia, vale a planilha e o lançamento do
  app aparece como "Já está na planilha", sem contar em dobro. Reenviar a planilha não apaga lançamentos do app.
- **Sem internet**: o lançamento fica guardado no aparelho, já entra nas contas e é enviado sozinho quando a
  conexão volta. Ao clicar em Sair com algo pendente, o app avisa antes.

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
