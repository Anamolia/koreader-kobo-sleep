--[[
Sobreposição estilo Kobo na tela de descanso do KOReader.

Dois estilos, escolhidos em
Configurações → Tela → Tela de descanso → Papel de parede → Sobreposição na capa:

  - Faixa "Em repouso": caixa branca na borda esquerda com
        Em repouso
        2% lido · faltam 4 horas

  - Cartões de progresso: dois cartões na parte de baixo da tela com
        título e autor, progresso do livro, capítulo atual e progresso dele,
        meta diária de leitura (com marca de concluída) e sequência de dias.

Só aparece quando a tela de descanso mostra a capa do livro. O tempo restante, a meta diária
e a sequência vêm do plugin Estatísticas de leitura.

Instalação: copie este arquivo para koreader/patches/ e reinicie o KOReader.
]]

local Blitbuffer = require("ffi/blitbuffer")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local OverlapGroup = require("ui/widget/overlapgroup")
local ScreenSaverWidget = require("ui/widget/screensaverwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local Widget = require("ui/widget/widget")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local Screen = Device.screen

--============================ Ajustes =============================================
-- Idioma dos textos: nil segue o idioma do KOReader; ou "pt" / "en"
local IDIOMA = nil

-- Estilo "faixa": posição e tamanho, em fração da tela
local FAIXA_TOPO = 0.625         -- distância do topo até a caixa
local FAIXA_LARGURA = 0.36       -- largura mínima da caixa (cresce se o texto não couber)
local FAIXA_ALTURA = 0.15        -- altura da caixa
local FAIXA_MARGEM = 0.025       -- espaço à esquerda do texto, em fração da largura
local FAIXA_TAM_TITULO = 0.033   -- tamanho das letras, em fração da altura da tela
local FAIXA_TAM_LINHA = 0.019

-- Estilo "cartões": em fração da tela
local CARTAO_LARGURA = 0.68      -- largura dos cartões (centralizados)
local CARTAO_MARGEM_BAIXO = 0.049 -- distância do cartão de baixo até a borda inferior
local CARTAO_ESPACO = 0.018      -- espaço entre os dois cartões
local CARTAO_MARGEM = 0.047      -- margem interna esquerda e direita, em fração da largura
local CARTAO_TAM_TITULO = 0.024  -- tamanho das letras, em fração da altura da tela
local CARTAO_TAM_TEXTO = 0.020

local FONTE_SANS = "NotoSans-Regular.ttf"
local FONTE_SANS_NEGRITO = "NotoSans-Bold.ttf"
local FONTE_SERIFA = "NotoSerif-Regular.ttf"

local COR_TEXTO = Blitbuffer.COLOR_BLACK
local COR_TEXTO_SECUNDARIO = Blitbuffer.gray(0.80)  -- cinza escuro
local COR_BORDA = Blitbuffer.gray(0.30)             -- cinza claro (faixa)
local COR_BORDA_CARTAO = Blitbuffer.gray(0.75)      -- cinza escuro (cartões)
--==================================================================================

local CHAVE_ESTILO = "descanso_kobo_estilo"   -- "faixa", "cartoes" ou "nenhum"
local CHAVE_META = "descanso_kobo_meta_min"   -- meta diária, em minutos
local ESTILO_PADRAO = "faixa"
local META_PADRAO = 15

local TEXTOS = {
    pt = {
        repouso = "Em repouso",
        lido = "%d%% lido",
        hora = "falta 1 hora", horas = "faltam %d horas",
        minuto = "falta 1 minuto", minutos = "faltam %d minutos",
        progresso_livro = "Progresso do livro",
        capitulo_atual = "Capítulo atual",
        meta_diaria = "Meta diária",
        sequencia = "Sequência",
        dias = "%dd",
        menu = "Sobreposição na capa",
        menu_nenhuma = "Nenhuma",
        menu_faixa = "Faixa \"Em repouso\" (Kobo)",
        menu_cartoes = "Cartões de progresso (Kobo)",
        menu_meta = "Meta diária: %d min",
        menu_meta_titulo = "Meta diária de leitura",
    },
    en = {
        repouso = "Sleeping",
        lido = "%d%% read",
        hora = "1 hour to go", horas = "%d hours to go",
        minuto = "1 minute to go", minutos = "%d minutes to go",
        progresso_livro = "Book Progress",
        capitulo_atual = "Current Chapter",
        meta_diaria = "Daily Goal",
        sequencia = "Goal Streak",
        dias = "%dd",
        menu = "Cover overlay",
        menu_nenhuma = "None",
        menu_faixa = "\"Sleeping\" banner (Kobo)",
        menu_cartoes = "Progress cards (Kobo)",
        menu_meta = "Daily goal: %d min",
        menu_meta_titulo = "Daily reading goal",
    },
}

local function textos()
    local idioma = IDIOMA
    if not idioma then
        local atual = require("gettext").current_lang or G_reader_settings:readSetting("language") or ""
        idioma = atual:sub(1, 2) == "pt" and "pt" or "en"
    end
    return TEXTOS[idioma] or TEXTOS.en
end

local function estilo()
    return G_reader_settings:readSetting(CHAVE_ESTILO, ESTILO_PADRAO)
end

local function metaMinutos()
    return G_reader_settings:readSetting(CHAVE_META, META_PADRAO)
end

--------------------------------------------------------------------------------------
-- Dados do livro e das estatísticas
--------------------------------------------------------------------------------------

--- Tempo restante do jeito do Kobo: horas arredondadas, ou minutos com menos de 1 hora.
local function tempoRestante(T, segundos)
    if not segundos or segundos <= 0 then return end
    local horas = math.floor(segundos / 3600 + 0.5)
    if horas >= 2 then return string.format(T.horas, horas) end
    if horas == 1 then return T.hora end
    local minutos = math.max(1, math.ceil(segundos / 60))
    if minutos == 1 then return T.minuto end
    return string.format(T.minutos, minutos)
end

local function limparAutores(autores)
    if type(autores) ~= "string" or autores == "" then return end
    return (autores:gsub("%s*\n%s*", ", "))
end

--- Informações do livro aberto (ou do último livro, quando bloqueado na pasta de livros).
local function infoLivro(ui)
    local info = {}
    if ui and ui.document and ui.view and ui.view.footer then
        local footer = ui.view.footer
        local props = ui.doc_props or {}
        info.titulo = props.display_title or props.title
        info.autor = limparAutores(props.authors)
        info.percent = footer.percent_finished
        local pagina = footer.pageno
        if pagina and ui.toc then
            local capitulo = ui.toc:getTocTitleByPage(pagina)
            if capitulo and capitulo ~= "" then
                info.capitulo = capitulo
                local ok, progresso = pcall(footer.getChapterProgress, footer, true)
                if ok and type(progresso) == "number" then info.capitulo_percent = progresso end
            end
        end
        local stats = ui.statistics
        local media = stats and stats.settings and stats.settings.is_enabled and stats.avg_time
        if media and media == media and media > 0 and pagina then
            local paginas = ui.document:getTotalPagesLeft(pagina)
            if paginas then info.segundos_restantes = paginas * media end
        end
    else
        local arquivo = G_reader_settings:readSetting("lastfile")
        local BookList = require("ui/widget/booklist")
        if arquivo and BookList.hasBookBeenOpened(arquivo) then
            local livro = BookList.getBookInfo(arquivo)
            info.percent = livro and livro.percent_finished
            local doc_settings = BookList.getDocSettings(arquivo)
            local props = doc_settings and doc_settings:readSetting("doc_props") or {}
            info.titulo = props.display_title or props.title
            info.autor = limparAutores(props.authors)
        end
        if not info.titulo and arquivo then
            info.titulo = arquivo:match("([^/]+)$"):gsub("%.[^.]+$", "")
        end
    end
    return info
end

--- Segundos lidos por dia ("AAAA-MM-DD"), do banco de estatísticas mais a sessão atual
--- (que o KOReader só grava no banco depois de mostrar a tela de descanso).
local function leituraPorDia(ui)
    local por_dia = {}
    local banco = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    if lfs.attributes(banco, "mode") == "file" then
        local SQ3 = require("lua-ljsqlite3/init")
        local conn = SQ3.open(banco)
        local ok, resultado = pcall(conn.exec, conn, string.format([[
            SELECT date(start_time, 'unixepoch', 'localtime') AS dia, sum(duration)
            FROM   page_stat_data
            WHERE  start_time >= %d
            GROUP  BY dia;
        ]], os.time() - 400 * 86400))
        conn:close()
        if ok and resultado and resultado[1] then
            for i = 1, #resultado[1] do
                por_dia[resultado[1][i]] = tonumber(resultado[2][i]) or 0
            end
        end
    end
    -- Sessão atual, ainda na memória do plugin de estatísticas
    local stats = ui and ui.statistics
    if stats and stats.page_stat then
        for _, lista in pairs(stats.page_stat) do
            for _, dado in ipairs(lista) do
                local inicio, duracao = dado[1], dado[2]
                if inicio and duracao and duracao > 0 then
                    local dia = os.date("%Y-%m-%d", inicio)
                    por_dia[dia] = (por_dia[dia] or 0) + duracao
                end
            end
        end
    end
    return por_dia
end

--- Minutos lidos hoje e sequência de dias seguidos em que a meta foi cumprida.
local function infoMeta(ui)
    local ok, por_dia = pcall(leituraPorDia, ui)
    if not ok then
        logger.warn("descanso-kobo: estatísticas:", por_dia)
        return
    end
    local meta_seg = metaMinutos() * 60
    local agora = os.time()
    local hoje = por_dia[os.date("%Y-%m-%d", agora)] or 0
    local sequencia = 0
    local dia = 0
    if hoje < meta_seg then dia = 1 end -- hoje ainda não conta, mas não quebra a sequência
    while true do
        local data = os.date("%Y-%m-%d", agora - dia * 86400)
        if (por_dia[data] or 0) >= meta_seg then
            sequencia = sequencia + 1
            dia = dia + 1
        else
            break
        end
    end
    return { hoje_seg = hoje, meta_seg = meta_seg, cumprida = hoje >= meta_seg, sequencia = sequencia }
end

local function formatarDuracao(segundos)
    local minutos = math.floor(segundos / 60)
    if minutos >= 60 then
        local h, m = math.floor(minutos / 60), minutos % 60
        return m > 0 and string.format("%dh %dm", h, m) or string.format("%dh", h)
    end
    return string.format("%dm", minutos)
end

--------------------------------------------------------------------------------------
-- Desenho
--------------------------------------------------------------------------------------

local function face(arquivo, fracao, altura_tela)
    -- Font:getFace multiplica pelo fator de escala da tela; aqui o tamanho já está em pixels
    local escala = Screen:scaleBySize(1000) / 1000
    return Font:getFace(arquivo, math.max(8, math.floor(altura_tela * fracao / escala + 0.5)))
end

--- Estilo 1: faixa "Em repouso" na borda esquerda.
local Faixa = Widget:extend{}

function Faixa:init()
    local sw, sh = self.largura_tela, self.altura_tela
    self.margem = math.floor(sw * FAIXA_MARGEM + 0.5)
    self.borda = math.max(1, math.floor(sw / 600 + 0.5))
    self.titulo_w = TextWidget:new{
        text = self.titulo,
        face = face(FONTE_SANS, FAIXA_TAM_TITULO, sh),
        fgcolor = COR_TEXTO,
    }
    if self.linha then
        self.linha_w = TextWidget:new{
            text = self.linha,
            face = face(FONTE_SERIFA, FAIXA_TAM_LINHA, sh),
            fgcolor = COR_TEXTO_SECUNDARIO,
        }
    end
    local largura_texto = self.titulo_w:getSize().w
    if self.linha_w then
        largura_texto = math.max(largura_texto, self.linha_w:getSize().w)
    end
    local w = math.max(math.floor(sw * FAIXA_LARGURA + 0.5), largura_texto + 2 * self.margem)
    self.dimen = Geom:new{ x = 0, y = 0, w = math.min(w, sw), h = math.floor(sh * FAIXA_ALTURA + 0.5) }
end

function Faixa:getSize()
    return self.dimen
end

function Faixa:paintTo(bb, x, y)
    local w, h, b = self.dimen.w, self.dimen.h, self.borda
    self.dimen.x, self.dimen.y = x, y
    -- Fundo branco e borda fina em cima, à direita e embaixo (a esquerda encosta na tela)
    bb:paintRect(x, y, w, h, Blitbuffer.COLOR_WHITE)
    bb:paintRect(x, y, w, b, COR_BORDA)
    bb:paintRect(x, y + h - b, w, b, COR_BORDA)
    bb:paintRect(x + w - b, y, b, h, COR_BORDA)
    local h_titulo = self.titulo_w:getSize().h
    local h_linha = self.linha_w and self.linha_w:getSize().h or 0
    local espaco = self.linha_w and math.floor(h_linha * 0.15) or 0
    local ty = y + math.floor((h - h_titulo - espaco - h_linha) / 2)
    self.titulo_w:paintTo(bb, x + self.margem, ty)
    if self.linha_w then
        self.linha_w:paintTo(bb, x + self.margem, ty + h_titulo + espaco)
    end
end

function Faixa:free()
    if self.titulo_w then self.titulo_w:free() end
    if self.linha_w then self.linha_w:free() end
end

--- Estilo 2: cartão com linhas de texto, barras de progresso e separadores.
--- itens: { tipo = "texto", esquerda, direita, face, check } | { tipo = "barra", fracao }
---        | { tipo = "separador" } | { tipo = "espaco", h }
local Cartao = Widget:extend{}

function Cartao:init()
    local sw, sh = self.largura_tela, self.altura_tela
    self.w = math.floor(sw * CARTAO_LARGURA + 0.5)
    self.margem = math.floor(sw * CARTAO_MARGEM + 0.5)
    self.borda = math.max(1, math.floor(sw / 700 + 0.5))
    self.sombra = math.max(2, math.floor(sw / 160 + 0.5))
    self.linha_fina = math.max(1, math.floor(sh / 900 + 0.5))
    local interna = self.w - 2 * self.margem
    local h = 0
    for _, item in ipairs(self.itens) do
        if item.tipo == "texto" then
            local direita_w = 0
            if item.direita then
                item.direita_w = TextWidget:new{ text = item.direita, face = item.face, fgcolor = COR_TEXTO }
                direita_w = item.direita_w:getSize().w
            end
            if item.check ~= nil then
                item.check_tam = math.floor(sh * 0.018 + 0.5)
                direita_w = direita_w + item.check_tam + math.floor(sh * 0.008)
            end
            local espaco = direita_w > 0 and math.floor(sw * 0.03) or 0
            item.esquerda_w = TextWidget:new{
                text = item.esquerda,
                face = item.face,
                fgcolor = COR_TEXTO,
                max_width = interna - direita_w - espaco,
            }
            item.h = item.esquerda_w:getSize().h
        elseif item.tipo == "barra" then
            item.h = math.floor(sh * 0.0145 + 0.5)
        elseif item.tipo == "separador" then
            item.h = self.linha_fina
        elseif item.tipo == "espaco" then
            item.h = math.floor(sh * item.fracao + 0.5)
        end
        h = h + item.h
    end
    self.dimen = Geom:new{ x = 0, y = 0, w = self.w + self.sombra, h = h + self.sombra }
end

function Cartao:getSize()
    return self.dimen
end

local function pintarCheck(bb, x, y, tam, cumprida)
    local borda = math.max(1, math.floor(tam / 10))
    if cumprida then
        bb:paintRect(x, y, tam, tam, Blitbuffer.COLOR_BLACK)
        -- Marca de "feito" em branco, desenhada ponto a ponto
        local grossura = math.max(2, math.floor(tam / 7))
        local pontos = { { 0.22, 0.52 }, { 0.42, 0.72 }, { 0.80, 0.28 } }
        for i = 1, #pontos - 1 do
            local x1, y1 = pontos[i][1] * tam, pontos[i][2] * tam
            local x2, y2 = pontos[i + 1][1] * tam, pontos[i + 1][2] * tam
            local passos = math.max(1, math.floor(math.max(math.abs(x2 - x1), math.abs(y2 - y1))))
            for p = 0, passos do
                local px = x1 + (x2 - x1) * p / passos
                local py = y1 + (y2 - y1) * p / passos
                bb:paintRect(x + math.floor(px - grossura / 2), y + math.floor(py - grossura / 2),
                    grossura, grossura, Blitbuffer.COLOR_WHITE)
            end
        end
    else
        bb:paintRect(x, y, tam, borda, Blitbuffer.COLOR_BLACK)
        bb:paintRect(x, y + tam - borda, tam, borda, Blitbuffer.COLOR_BLACK)
        bb:paintRect(x, y, borda, tam, Blitbuffer.COLOR_BLACK)
        bb:paintRect(x + tam - borda, y, borda, tam, Blitbuffer.COLOR_BLACK)
    end
end

function Cartao:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local s, b = self.sombra, self.borda
    local cx, w = x + s, self.w                -- o cartão fica à direita da sombra
    local h = self.dimen.h - s
    -- Sombra à esquerda e embaixo, fundo branco e borda fina
    bb:paintRect(x, y + s, w, h, Blitbuffer.COLOR_BLACK)
    bb:paintRect(cx, y, w, h, Blitbuffer.COLOR_WHITE)
    bb:paintRect(cx, y, w, b, COR_BORDA_CARTAO)
    bb:paintRect(cx, y + h - b, w, b, COR_BORDA_CARTAO)
    bb:paintRect(cx, y, b, h, COR_BORDA_CARTAO)
    bb:paintRect(cx + w - b, y, b, h, COR_BORDA_CARTAO)

    local esquerda = cx + self.margem
    local interna = w - 2 * self.margem
    local cy = y
    for _, item in ipairs(self.itens) do
        if item.tipo == "texto" then
            item.esquerda_w:paintTo(bb, esquerda, cy)
            local direita = esquerda + interna
            if item.check ~= nil then
                direita = direita - item.check_tam
                pintarCheck(bb, direita, cy + math.floor(item.h * 0.05), item.check_tam, item.check)
                direita = direita - math.floor(self.altura_tela * 0.008)
            end
            if item.direita_w then
                item.direita_w:paintTo(bb, direita - item.direita_w:getSize().w, cy)
            end
        elseif item.tipo == "barra" then
            local fracao = math.max(0, math.min(1, item.fracao or 0))
            local bh = item.h
            local fina = self.linha_fina
            bb:paintRect(esquerda, cy, interna, fina, COR_BORDA_CARTAO)
            bb:paintRect(esquerda, cy + bh - fina, interna, fina, COR_BORDA_CARTAO)
            bb:paintRect(esquerda, cy, fina, bh, COR_BORDA_CARTAO)
            bb:paintRect(esquerda + interna - fina, cy, fina, bh, COR_BORDA_CARTAO)
            local recuo = fina + math.max(1, math.floor(bh / 6))
            local cheio = math.floor((interna - 2 * recuo) * fracao + 0.5)
            if cheio > 0 then
                bb:paintRect(esquerda + recuo, cy + recuo, cheio, bh - 2 * recuo, Blitbuffer.COLOR_BLACK)
            end
        elseif item.tipo == "separador" then
            bb:paintRect(esquerda, cy, interna, item.h, COR_BORDA_CARTAO)
        end
        cy = cy + item.h
    end
end

function Cartao:free()
    for _, item in ipairs(self.itens) do
        if item.esquerda_w then item.esquerda_w:free() end
        if item.direita_w then item.direita_w:free() end
    end
end

local function porcentagem(fracao)
    return string.format("%d%%", math.floor((fracao or 0) * 100 + 0.5))
end

local function criarFaixa(ui, sw, sh)
    local T = textos()
    local info = infoLivro(ui)
    local partes = {}
    if info.percent then
        table.insert(partes, string.format(T.lido, math.floor(info.percent * 100 + 0.5)))
    end
    local tempo = tempoRestante(T, info.segundos_restantes)
    if tempo then table.insert(partes, tempo) end
    local faixa = Faixa:new{
        largura_tela = sw,
        altura_tela = sh,
        titulo = T.repouso,
        linha = #partes > 0 and table.concat(partes, " · ") or nil,
    }
    faixa.overlap_offset = { 0, math.floor(sh * FAIXA_TOPO + 0.5) }
    return { faixa }
end

local function criarCartoes(ui, sw, sh)
    local T = textos()
    local info = infoLivro(ui)
    local f_titulo = face(FONTE_SANS_NEGRITO, CARTAO_TAM_TITULO, sh)
    local f_texto = face(FONTE_SANS, CARTAO_TAM_TEXTO, sh)

    -- Cartão do livro
    local itens = { { tipo = "espaco", fracao = 0.026 } }
    table.insert(itens, { tipo = "texto", esquerda = info.titulo or "?", face = f_titulo })
    if info.autor then
        table.insert(itens, { tipo = "espaco", fracao = 0.004 })
        table.insert(itens, { tipo = "texto", esquerda = info.autor, face = f_texto })
    end
    table.insert(itens, { tipo = "espaco", fracao = 0.004 })
    table.insert(itens, { tipo = "separador" })
    table.insert(itens, { tipo = "espaco", fracao = 0.024 })
    table.insert(itens, { tipo = "texto", esquerda = T.progresso_livro, direita = porcentagem(info.percent), face = f_texto })
    table.insert(itens, { tipo = "espaco", fracao = 0.004 })
    table.insert(itens, { tipo = "barra", fracao = info.percent })
    if info.capitulo then
        table.insert(itens, { tipo = "espaco", fracao = 0.026 })
        table.insert(itens, { tipo = "texto", esquerda = T.capitulo_atual, face = f_texto })
        table.insert(itens, { tipo = "espaco", fracao = 0.004 })
        table.insert(itens, { tipo = "texto", esquerda = info.capitulo, direita = porcentagem(info.capitulo_percent), face = f_texto })
        table.insert(itens, { tipo = "espaco", fracao = 0.004 })
        table.insert(itens, { tipo = "barra", fracao = info.capitulo_percent })
    end
    table.insert(itens, { tipo = "espaco", fracao = 0.012 })
    local cartao_livro = Cartao:new{ largura_tela = sw, altura_tela = sh, itens = itens }

    -- Cartão da meta diária (só com estatísticas disponíveis)
    local cartao_meta
    local meta = infoMeta(ui)
    if meta then
        local feito = math.min(meta.hoje_seg, meta.meta_seg)
        cartao_meta = Cartao:new{
            largura_tela = sw,
            altura_tela = sh,
            itens = {
                { tipo = "espaco", fracao = 0.024 },
                { tipo = "texto", esquerda = T.meta_diaria, face = f_texto,
                  direita = formatarDuracao(feito) .. "/" .. formatarDuracao(meta.meta_seg),
                  check = meta.cumprida },
                { tipo = "espaco", fracao = 0.012 },
                { tipo = "texto", esquerda = T.sequencia, direita = string.format(T.dias, meta.sequencia), face = f_texto },
                { tipo = "espaco", fracao = 0.016 },
            },
        }
    end

    -- Empilhados de baixo para cima, centralizados na horizontal
    local widgets = {}
    local base = sh - math.floor(sh * CARTAO_MARGEM_BAIXO + 0.5)
    local function colocar(cartao)
        local tam = cartao:getSize()
        -- A sombra fica à esquerda: centraliza o cartão em si, não o conjunto
        local x = math.floor((sw - (tam.w - cartao.sombra)) / 2) - cartao.sombra
        cartao.overlap_offset = { x, base - tam.h }
        base = base - tam.h - math.floor(sh * CARTAO_ESPACO + 0.5)
        table.insert(widgets, cartao)
    end
    if cartao_meta then colocar(cartao_meta) end
    colocar(cartao_livro)
    return widgets
end

--------------------------------------------------------------------------------------
-- Tela de descanso
--------------------------------------------------------------------------------------

local init_original = ScreenSaverWidget.init

function ScreenSaverWidget:init()
    local ok, erro = pcall(function()
        local Screensaver = require("ui/screensaver")
        local qual = estilo()
        if qual == "nenhum" then return end
        -- Só na capa do livro, e não nas telas de desligar/reiniciar
        if not (self.widget and Screensaver.screensaver_type == "cover" and (Screensaver.prefix or "") == "") then
            return
        end
        local sw, sh = Screen:getWidth(), Screen:getHeight()
        local sobreposicao = qual == "cartoes" and criarCartoes(Screensaver.ui, sw, sh)
            or criarFaixa(Screensaver.ui, sw, sh)
        local grupo = OverlapGroup:new{ dimen = Geom:new{ w = sw, h = sh }, self.widget }
        for _, w in ipairs(sobreposicao) do
            table.insert(grupo, w)
        end
        self.widget = grupo
    end)
    if not ok then
        logger.warn("descanso-kobo:", erro)
    end
    return init_original(self)
end

--------------------------------------------------------------------------------------
-- Menu: Tela de descanso → Papel de parede → Sobreposição na capa
--------------------------------------------------------------------------------------

local function itemEstilo(texto_func, valor, separador)
    return {
        text_func = texto_func,
        checked_func = function() return estilo() == valor end,
        callback = function() G_reader_settings:saveSetting(CHAVE_ESTILO, valor) end,
        radio = true,
        separator = separador,
    }
end

--- Acrescenta o item ao menu da tela de descanso (sub_item_table do "Papel de parede").
local function acrescentarAoMenu(menu)
    local _ = require("gettext")
    local papel = menu and menu[1]
    if not (papel and papel.sub_item_table) then return end
    for _, item in ipairs(papel.sub_item_table) do
        if item._descanso_kobo then return end -- já adicionado
    end
    local posicao = #papel.sub_item_table + 1
    for i, item in ipairs(papel.sub_item_table) do
        if item.text == _("Border fill, rotation, and fit") then
            posicao = i + 1
            break
        end
    end
    table.insert(papel.sub_item_table, posicao, {
        _descanso_kobo = true,
        text_func = function() return textos().menu end,
        enabled_func = function()
            local tipo = G_reader_settings:readSetting("screensaver_type")
            return tipo == "cover" or tipo == "document_cover"
        end,
        sub_item_table = {
            itemEstilo(function() return textos().menu_nenhuma end, "nenhum"),
            itemEstilo(function() return textos().menu_faixa end, "faixa"),
            itemEstilo(function() return textos().menu_cartoes end, "cartoes", true),
            {
                text_func = function() return string.format(textos().menu_meta, metaMinutos()) end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local SpinWidget = require("ui/widget/spinwidget")
                    UIManager:show(SpinWidget:new{
                        title_text = textos().menu_meta_titulo,
                        value = metaMinutos(),
                        value_min = 1,
                        value_max = 600,
                        value_step = 5,
                        value_hold_step = 15,
                        unit = "min",
                        default_value = META_PADRAO,
                        callback = function(spin)
                            G_reader_settings:saveSetting(CHAVE_META, spin.value)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    })
                end,
            },
        },
    })
end

-- O KOReader monta esse menu com dofile() cada vez que o menu principal é criado
-- (no leitor e na pasta de livros), então o item é acrescentado na hora.
local MENU_DESCANSO = "frontend/ui/elements/screensaver_menu.lua"
local dofile_original = dofile
dofile = function(caminho, ...) -- luacheck: ignore
    local resultado = dofile_original(caminho, ...)
    if caminho == MENU_DESCANSO then
        local ok, erro = pcall(acrescentarAoMenu, resultado)
        if not ok then logger.warn("descanso-kobo: menu:", erro) end
    end
    return resultado
end
