# Sobreposição estilo Kobo na tela de descanso do KOReader

User patch do KOReader que imita a tela de descanso do **Kobo**, com dois estilos à escolha, desenhados por cima da capa do livro.

**Faixa "Em repouso"**: uma caixa branca na borda esquerda da tela.

```
┌──────────────────────────┐
│ Em repouso               │
│ 2% lido · faltam 4 horas │
└──────────────────────────┘
```

**Cartões de progresso**: dois cartões na parte de baixo da tela.

```
┌───────────────────────────────────┐
│ Gideon the Ninth                  │
│ Tamsyn Muir                       │
│ ───────────────────────────────── │
│ Progresso do livro            23% │
│ [███████                        ] │
│                                   │
│ Capítulo atual                    │
│ Chapter 11                     6% │
│ [██                             ] │
└───────────────────────────────────┘
┌───────────────────────────────────┐
│ Meta diária              15m/15m ■│
│ Sequência                     24d │
└───────────────────────────────────┘
```

Com o KOReader em inglês, os textos ficam como no Kobo: **Sleeping** / **2% read · 4 hours to go**, **Book Progress**, **Current Chapter**, **Daily Goal**, **Goal Streak**.

## ✅ Aparelhos testados

| Aparelho | Firmware | KOReader | Resultado |
|---|---|---|---|
| **Kindle Colorsoft Signature Edition** | 5.20.1 | v2026.07.2 | ✅ Os dois estilos por cima da capa esticada, menu de escolha e meta diária |

*Testes feitos em novembro de 2026.*

## Instalação

1. Copie `patches/2-faixa-descanso-kobo.lua` para a pasta `koreader/patches/` do aparelho (crie a pasta se ela não existir). No Kindle, o caminho é `/mnt/us/koreader/patches/`.
2. Reinicie o KOReader (**Menu → Sair → Reiniciar KOReader**).
3. Confira que a tela de descanso mostra a capa do livro: **Configurações → Tela → Tela de descanso → Papel de parede → Capa do livro**.

Para ficar como no Kobo, com a capa ocupando a tela toda, ative também **Tela de descanso → Papel de parede → Ajuste, rotação e preenchimento da borda → Esticar capa para preencher a tela → Esticamento completo**.

## Escolher o estilo

Em **Configurações → Tela → Tela de descanso → Papel de parede → Sobreposição na capa**:

- **Nenhuma**: só a capa.
- **Faixa "Em repouso" (Kobo)**: o padrão.
- **Cartões de progresso (Kobo)**.
- **Meta diária: 15 min**: toque para mudar a meta de leitura por dia, usada no cartão da meta.

## O que aparece

- **Faixa:** "Em repouso", a porcentagem lida e o tempo que falta para terminar o livro. Como no Kobo, o tempo aparece em horas arredondadas, ou em minutos quando falta menos de 1 hora.
- **Cartão do livro:** título, autor, progresso do livro e, se o livro tiver sumário, o capítulo atual com o progresso dele.
- **Cartão da meta:** quanto você leu hoje e a meta (com a marca preenchida quando a meta é cumprida) e a **sequência**: quantos dias seguidos você cumpriu a meta. Se a meta de hoje ainda não foi cumprida, a sequência conta até ontem.
- **De onde vêm os números:** o tempo restante, a leitura de hoje e a sequência vêm do plugin **Estatísticas de leitura**, incluindo a sessão que está aberta no momento.
- **Bloqueando na pasta de livros:** aparecem título, autor e porcentagem do último livro, mas não o capítulo nem o tempo restante, que só existem com o livro aberto.
- **Telas de desligar e reiniciar, imagens aleatórias e outros modos:** nada é desenhado. A sobreposição só aparece quando a tela de descanso mostra a capa do livro.

## Ajustes

No começo do arquivo:

- `IDIOMA`: `nil` segue o idioma do KOReader; ou `"pt"` / `"en"`.
- `FAIXA_*`: posição, tamanho e letras da faixa, em fração da tela.
- `CARTAO_*`: largura, posição, espaçamento e letras dos cartões, em fração da tela.
- `FONTE_*`: fontes (qualquer fonte da pasta `fonts` do KOReader).
- `COR_*`: cores.

## Desinstalar

Apague `koreader/patches/2-faixa-descanso-kobo.lua` e reinicie o KOReader.

## English summary

KOReader user patch that mimics Kobo's sleep screen with two selectable styles drawn over the book cover: a **"Sleeping" banner** (Sleeping / 2% read · 4 hours to go) and **progress cards** (title and author, book progress bar, current chapter with its progress bar, daily reading goal with a check mark, and goal streak). Pick the style under **Settings → Screen → Sleep screen → Wallpaper → Cover overlay**, where you can also set the daily goal in minutes. Labels follow KOReader's language (Portuguese or English). Time left, today's reading time and the streak come from the Reading statistics plugin, including the current unsaved session. It wraps `ScreenSaverWidget.init` and only draws when the sleep screen shows the book cover. Copy `patches/2-faixa-descanso-kobo.lua` to `koreader/patches/` and restart KOReader. Tested on a Kindle Colorsoft Signature Edition (FW 5.20.1, KOReader v2026.07.2).
