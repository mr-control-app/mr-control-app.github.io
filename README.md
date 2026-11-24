# Mr. Control

Controle de consumo de suplemento a pasto. Endereço: https://mr-control-app.github.io

App de uma página (index.html) com a lógica do BI Consumo v2. Lê as planilhas "Folha Suplementação"
no próprio navegador. Nenhum dado sai do computador ou celular de quem usa, e nada fica gravado no GitHub.

## Publicação
O site é o repositório `mr-control-app/mr-control-app.github.io` (GitHub Pages, branch main, pasta raiz).
Para atualizar: substitua o `index.html` no repositório (Add file > Upload files > Commit). Em 1 a 2 minutos
a versão nova está no ar. O Mr. Control é independente do Mr. Report: outro endereço, sem cache ou armazenamento compartilhado.

## Usar
- **Abrir planilhas**: selecione uma ou várias "Folha Suplementação" (.xlsx), de meses e anos diferentes.
  No celular, os arquivos podem vir do OneDrive ou do Google Drive pelo seletor de arquivos.
- **Ajustes**: produtos (% do peso vivo, peso do saco, preço R$/kg), tolerância da meta, limites de alerta
  e meses de seca. Ficam salvos no navegador de quem usa.
- **Baixar base calculada**: gera um Excel com todos os lançamentos já calculados.

## Regras de cálculo (iguais ao BI v2)
- Consumo do trato = kg ÷ cabeças-dia até o próximo trato do mesmo Retiro + Pasto, mesmo que esteja na planilha
  do mês ou ano seguinte. Na virada do mês, os dias de cada mês usam as cabeças daquele mês.
- Consumo de um grupo = soma dos kg ÷ soma das cabeças-dia. Intervalo acima do limite (30 dias) = pasto vazio.
- Meta = peso estimado × % do produto; faixa = meta ± tolerância (25%).
- Ano vem da data do trato; o mês aparece como "Setembro/2026".

## Formato esperado da planilha
Uma aba por retiro. B3 = retiro; B4 = mês; linha 5 = saída de fábrica (B) e animais por produto
(F MUB, G Adensado, H a L = 0.1 a 0.5); linha 7 = cabeçalho (Pasto, Quant. Animais, Peso Estimado, Categoria,
Tipo de sal, Área Retiro e uma coluna por data); a partir da linha 8, sacos fornecidos em cada data.
