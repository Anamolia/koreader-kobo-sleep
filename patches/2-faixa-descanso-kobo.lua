--[[
Faixa estilo Kobo na tela de descanso do KOReader.

Desenha por cima da capa do livro, na borda esquerda da tela, uma caixa branca com:

    Em repouso
    2% lido · faltam 4 horas

Só aparece quando a tela de descanso mostra a capa do livro (Tela de descanso → Papel de
parede → Capa do livro). O tempo restante vem do plugin Estatísticas de leitura; sem ele,
ou com o KOReader na pasta de livros, a segunda linha mostra só a porcentagem lida.

Instalação: copie este arquivo para koreader/patches/ e reinicie o KOReader.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local OverlapGroup = require("ui/widget/overlapgroup")
local ScreenSaverWidget = require("ui/widget/screensaverwidget")
local TextWidget = require("ui/widget/textwidget")
local Widget = require("ui/widget/widget")
local logger = require("logger")
local Screen = Device.screen

--============================ Ajustes =============================================
local IDIOMA = "pt"   -- "pt" ou "en" (igual ao Kobo em inglês: "Sleeping", "2% read · 4 hours to go")

-- Posição e tamanho, em fração da tela (medidos numa tela de descanso do Kobo)
local TOPO = 0.625         -- distância do topo até a caixa
local LARGURA = 0.36       -- largura mínima da caixa (cresce se o texto não couber)
local ALTURA = 0.15        -- altura da caixa
local MARGEM_TEXTO = 0.025 -- espaço à esquerda do texto, em fração da largura da tela

-- Tamanho das letras, em fração da altura da tela
local TAMANHO_TITULO = 0.033
local TAMANHO_LINHA = 0.019

local FONTE_TITULO = "NotoSans-Regular.ttf"
local FONTE_LINHA = "NotoSerif-Regular.ttf"

local COR_TITULO = Blitbuffer.COLOR_BLACK
local COR_LINHA = Blitbuffer.gray(0.80)  -- cinza escuro
local COR_BORDA = Blitbuffer.gray(0.30)  -- cinza claro
--==================================================================================

local TEXTOS = {
    pt = {
        titulo = "Em repouso",
        lido = "%d%% lido",
        hora = "falta 1 hora", horas = "faltam %d horas",
        minuto = "falta 1 minuto", minutos = "faltam %d minutos",
    },
    en = {
        titulo = "Sleeping",
        lido = "%d%% read",
        hora = "1 hour to go", horas = "%d hours to go",
        minuto = "1 minute to go", minutos = "%d minutes to go",
    },
}
local T = TEXTOS[IDIOMA] or TEXTOS.pt

--- Tempo restante do jeito do Kobo: horas arredondadas, ou minutos quando falta menos de 1 hora.
local function tempoRestante(segundos)
    if not segundos or segundos <= 0 then return end
    local horas = math.floor(segundos / 3600 + 0.5)
    if horas >= 2 then return string.format(T.horas, horas) end
    if horas == 1 then return T.hora end
    local minutos = math.max(1, math.ceil(segundos / 60))
    if minutos == 1 then return T.minuto end
    return string.format(T.minutos, minutos)
end

--- Porcentagem lida (0 a 1) e segundos que faltam, do livro aberto ou do último livro.
local function infoLeitura(ui)
    local percent, segundos
    if ui and ui.document and ui.view and ui.view.footer then
        local footer = ui.view.footer
        percent = footer.percent_finished
        local stats = ui.statistics
        local media = stats and stats.settings and stats.settings.is_enabled and stats.avg_time
        if media and media == media and media > 0 and footer.pageno then
            local paginas = ui.document:getTotalPagesLeft(footer.pageno)
            if paginas then segundos = paginas * media end
        end
    else
        local arquivo = G_reader_settings:readSetting("lastfile")
        local BookList = require("ui/widget/booklist")
        if arquivo and BookList.hasBookBeenOpened(arquivo) then
            local info = BookList.getBookInfo(arquivo)
            percent = info and info.percent_finished
        end
    end
    return percent, segundos
end

local function face(arquivo, fracao, altura_tela)
    -- Font:getFace multiplica pelo fator de escala da tela; aqui o tamanho já está em pixels
    local escala = Screen:scaleBySize(1000) / 1000
    return Font:getFace(arquivo, math.max(8, math.floor(altura_tela * fracao / escala + 0.5)))
end

local Faixa = Widget:extend{
    largura_tela = nil,
    altura_tela = nil,
    titulo = nil,
    linha = nil,
}

function Faixa:init()
    local sw, sh = self.largura_tela, self.altura_tela
    self.margem = math.floor(sw * MARGEM_TEXTO + 0.5)
    self.borda = math.max(1, math.floor(sw / 600 + 0.5))
    self.titulo_w = TextWidget:new{
        text = self.titulo,
        face = face(FONTE_TITULO, TAMANHO_TITULO, sh),
        fgcolor = COR_TITULO,
    }
    if self.linha then
        self.linha_w = TextWidget:new{
            text = self.linha,
            face = face(FONTE_LINHA, TAMANHO_LINHA, sh),
            fgcolor = COR_LINHA,
        }
    end
    local largura_texto = self.titulo_w:getSize().w
    if self.linha_w then
        largura_texto = math.max(largura_texto, self.linha_w:getSize().w)
    end
    local w = math.max(math.floor(sw * LARGURA + 0.5), largura_texto + 2 * self.margem)
    self.dimen = Geom:new{ x = 0, y = 0, w = math.min(w, sw), h = math.floor(sh * ALTURA + 0.5) }
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
    -- Título e linha centralizados na vertical
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

local function criarFaixa(ui, sw, sh)
    local percent, segundos = infoLeitura(ui)
    local partes = {}
    if percent then
        table.insert(partes, string.format(T.lido, math.floor(percent * 100 + 0.5)))
    end
    local tempo = tempoRestante(segundos)
    if tempo then table.insert(partes, tempo) end
    return Faixa:new{
        largura_tela = sw,
        altura_tela = sh,
        titulo = T.titulo,
        linha = #partes > 0 and table.concat(partes, " · ") or nil,
        overlap_offset = { 0, math.floor(sh * TOPO + 0.5) },
    }
end

local init_original = ScreenSaverWidget.init

function ScreenSaverWidget:init()
    local ok, erro = pcall(function()
        local Screensaver = require("ui/screensaver")
        -- Só na capa do livro, e não nas telas de desligar/reiniciar
        if self.widget and Screensaver.screensaver_type == "cover" and (Screensaver.prefix or "") == "" then
            local sw, sh = Screen:getWidth(), Screen:getHeight()
            self.widget = OverlapGroup:new{
                dimen = Geom:new{ w = sw, h = sh },
                self.widget,
                criarFaixa(Screensaver.ui, sw, sh),
            }
        end
    end)
    if not ok then
        logger.warn("faixa-descanso-kobo:", erro)
    end
    return init_original(self)
end
