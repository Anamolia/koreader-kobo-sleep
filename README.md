# Faixa estilo Kobo na tela de descanso do KOReader

User patch do KOReader que imita a tela de descanso do **Kobo**: por cima da capa do livro, na borda esquerda da tela, aparece uma caixa branca com o estado do aparelho e o progresso da leitura.

```
┌──────────────────────────┐
│ Em repouso               │
│ 2% lido · faltam 4 horas │
└──────────────────────────┘
```

Em inglês, fica igual ao Kobo: **Sleeping** / **2% read · 4 hours to go**.

## ✅ Aparelhos testados

| Aparelho | Firmware | KOReader | Resultado |
|---|---|---|---|
| **Kindle Colorsoft Signature Edition** | 5.20.1 | v2026.07.2 | ✅ Caixa por cima da capa na tela de descanso, com a capa esticada para preencher a tela |

*Teste feito em novembro de 2026.*

## Instalação

1. Copie `patches/2-faixa-descanso-kobo.lua` para a pasta `koreader/patches/` do aparelho (crie a pasta se ela não existir). No Kindle, o caminho é `/mnt/us/koreader/patches/`.
2. Reinicie o KOReader (**Menu → Sair → Reiniciar KOReader**).
3. Confira que a tela de descanso mostra a capa do livro: **Configurações → Tela → Tela de descanso → Papel de parede → Capa do livro**.

Para ficar como no Kobo, com a capa ocupando a tela toda, ative também **Tela de descanso → Papel de parede → Ajuste, rotação e preenchimento da borda → Esticar capa para preencher a tela → Esticamento completo**.

## O que aparece

- **Primeira linha:** "Em repouso" (ou "Sleeping").
- **Segunda linha:** a porcentagem lida e o tempo que falta para terminar o livro.
- **Tempo restante:** vem do plugin **Estatísticas de leitura**, com base no seu ritmo de leitura. Como no Kobo, mostra horas arredondadas, ou minutos quando falta menos de 1 hora. Sem o plugin, a linha mostra só a porcentagem.
- **Bloqueando na pasta de livros:** mostra só a porcentagem do último livro, porque o tempo restante só existe com o livro aberto.
- **Telas de desligar e reiniciar, imagens aleatórias e outros modos:** a caixa não aparece. Ela só aparece quando a tela de descanso mostra a capa do livro.

## Ajustes

Tudo fica no começo do arquivo:

- `IDIOMA`: `"pt"` (padrão) ou `"en"`.
- `TOPO`, `LARGURA`, `ALTURA`, `MARGEM_TEXTO`: posição e tamanho da caixa, em fração da tela. A caixa cresce sozinha se o texto não couber.
- `TAMANHO_TITULO`, `TAMANHO_LINHA`: tamanho das letras, em fração da altura da tela.
- `FONTE_TITULO`, `FONTE_LINHA`: fontes (qualquer fonte da pasta `fonts` do KOReader).
- `COR_TITULO`, `COR_LINHA`, `COR_BORDA`: cores.

## Desinstalar

Apague `koreader/patches/2-faixa-descanso-kobo.lua` e reinicie o KOReader.

## English summary

KOReader user patch that mimics Kobo's sleep screen: a white box on the left edge of the book cover showing **Sleeping** and **2% read · 4 hours to go**. Set `IDIOMA = "en"` at the top of the file for the English labels (the default is Portuguese). The time left comes from the Reading statistics plugin (rounded to hours, or minutes under one hour, like Kobo). It wraps `ScreenSaverWidget.init` and only draws when the sleep screen shows the book cover. Copy `patches/2-faixa-descanso-kobo.lua` to `koreader/patches/` and restart KOReader. Tested on a Kindle Colorsoft Signature Edition (FW 5.20.1, KOReader v2026.07.2).
