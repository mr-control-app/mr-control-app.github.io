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
Tela centralizada, pensada para a equipe de campo no celular. As planilhas são enviadas na aba **Planilhas**.
1. **Retiro**: toque no botão do retiro (ou "+ Outro").
2. **Número do pasto**: toque no pasto (os pastos do retiro aparecem como botões; digitar filtra).
   Animais, tipo de sal, peso e categoria vêm do último trato daquele pasto.
3. **Número de animais** e 5. **Sacos**: número grande com botões − e +.
4. **Tipo de sal**: toque no produto (ou "+ Outro").
6. **Data**: Hoje, Ontem, Anteontem ou "Outra data" (só datas passadas; o banco também recusa data futura).

Cada etapa fica verde quando preenchida; antes de lançar aparece um resumo e, depois, o consumo do trato anterior.
- **Quem lança**: administrador, técnico e equipe da fazenda. **Quem apaga**: administrador e técnico (fica no registro).
- **Mesmo pasto e dia** lançado de novo **corrige** o anterior (não duplica).
- **Planilha x app**: se a planilha do mês trouxer o mesmo retiro, pasto e dia, vale a planilha ("Já está na planilha").
- **Sem internet**: fica guardado no aparelho, já entra nas contas e é enviado sozinho quando a conexão volta.

## Gráficos das abas de análise
Relatório, Pastos, Histórico, Logística e Auditoria abrem com gráficos-resumo; as tabelas completas ficam no fim,
em **Detalhamento**. Passe o mouse (ou toque) nas barras e pontos para ver os valores. Nos gráficos de pastos,
tocar abre os tratos do pasto; em Auditoria, tocar num tipo de alerta filtra a tabela.

## Aba Fórmulas e batidas
- **Insumos e preços**: nome, peso da embalagem e preço pago nela; o app calcula o R$/kg e guarda a data do preço.
- **Fórmulas**: cada fórmula é uma batida (kg de cada insumo). Mostra % de cada insumo, custo da batida, custo por kg
  e custo do saco. Ligue a fórmula a um produto (tipo de sal) dos Ajustes: o custo dela passa a ser o preço desse
  produto (aparece travado em Ajustes) e entra no custo da aba Logística.
- **Planejamento de batidas**: a previsão de sacos do próximo mês vira kg e número de batidas de cada fórmula, e a
  lista de **compra de insumos** (kg, embalagens e custo estimado).
- Técnico e administrador editam e clicam em **Salvar fórmulas e preços**; a equipe só consulta. Fica guardado com os
  Ajustes da fazenda (mesmo histórico de versões). Não precisa rodar nada novo no Supabase.

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
