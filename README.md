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
| **Técnico** | usuário + senha | só as fazendas marcadas para ele; envia e apaga planilhas e lançamentos; edita ajustes, fórmulas e retiros |
| **Capataz** | usuário + senha própria (6+ caracteres) | vê todos os resultados das fazendas marcadas; **lança só nos retiros liberados** pelo administrador; não envia planilhas nem altera ajustes |
| **Observador** | só a senha da fazenda | vê tudo da própria fazenda; não lança, não envia planilhas, não altera nada |

O banco confere cada permissão (não só a tela): capataz lançando fora dos retiros liberados é recusado.
**Lembrar de mim** (tela de entrada, vem marcado): fica conectado no aparelho por até 6 meses e o usuário já vem
preenchido. Desmarcado: a sessão dura 12 horas e acaba ao fechar o navegador (bom para aparelho compartilhado).
Liberar capataz: aba **Pessoas** → papel Capataz → marque a fazenda → aparecem os retiros dela → marque os liberados.
A lista de Pessoas fica agrupada por fazenda.

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

### Atualizações do banco (rodar de novo sempre que o arquivo SQL mudar)
Supabase → **SQL Editor → New query** → cole o arquivo `supabase/01_mr_control.sql` inteiro → **Run**.
Pode rodar quantas vezes quiser: ele cria o que falta e atualiza as funções, **sem apagar dados**.
Se aparecer o aviso "destructive operation", é só a troca de funções antigas por novas: confirme.
Última mudança: papel Capataz (retiros liberados), login da fazenda como observador e "Lembrar de mim".

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
- **Quem lança**: administrador e técnico (qualquer retiro) e capataz (só os retiros liberados para ele).
  **Quem apaga**: administrador e técnico (fica no registro). O login com a senha da fazenda só consulta.
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

## Aba Retiros
- Lista os retiros que aparecem nas planilhas e lançamentos. No primeiro acesso, a **área útil** vem do cabeçalho da
  planilha mais recente: confira e clique em **Salvar retiros**.
- **Área dos pastos** (opcional): os pastos vêm dos lançamentos (nome fixo, só informativo); preencha a área de cada.
  Com todos preenchidos, a área do retiro passa a ser a soma.
- Mostra lotação (UA/ha) com a área cadastrada, pastos com trato no último mês, ocupação e capatazes liberados.
- O cadastro **não muda** os pastos dos lançamentos. Fica salvo com os Ajustes da fazenda.

## Sem banco configurado
Com `config.js` vazio, o app funciona em **modo local**: as planilhas inseridas ficam salvas só naquele aparelho.

## Regras de cálculo (iguais ao BI Consumo v2)
- Consumo do trato = kg ÷ cabeças-dia até o próximo trato do mesmo Retiro + Pasto, mesmo que esteja na planilha
  do mês ou ano seguinte. Na virada do mês, os dias de cada mês usam as cabeças daquele mês.
- Consumo de um grupo = soma dos kg ÷ soma das cabeças-dia.
- **Saída presumida do lote** (a fazenda não tem lotes fixos por pasto): se o pasto fica mais dias sem fornecimento
  do que o limite do suplemento, entende-se que o lote saiu depois do último trato, e esse trato é calculado com o
  **intervalo médio de fornecimento** daquele suplemento, em vez dos dias até o próximo trato.
  - Limite: "Máx. sem fornecimento (dias)" do produto em **Ajustes**; em branco = média do intervalo + 50%,
    nunca menos que 7 dias.
  - Média: do retiro no mês (5+ intervalos); senão da fazenda no mês; senão da fazenda nos 3 meses anteriores.
    Intervalos acima de 30 dias nunca entram na média.
  - Se o trato seguinte tem **exatamente o mesmo nº de cabeças**, é o mesmo lote atrasado: vale o intervalo real
    (até 15 dias; MUB até 30).
  - O último trato de cada pasto também vira saída presumida se a data mais recente do retiro já passou do limite.
- Meta = peso estimado × % do produto; faixa = meta ± tolerância (25%). Produtos, metas, preços e regras ficam na aba
  **Ajustes**, por fazenda.
- O ano vem da data do trato; o mês aparece como "Setembro/2026".

## Formato esperado da planilha
Uma aba por retiro. B3 = retiro; B4 = mês; linha 5 = saída de fábrica (B) e animais por produto
(F MUB, G Adensado, H a L = 0.1 a 0.5); linha 7 = cabeçalho (Pasto, Quant. Animais, Peso Estimado, Categoria,
Tipo de sal, Área Retiro e uma coluna por data); a partir da linha 8, sacos fornecidos em cada data.
