--[[ 
    Header: center = Author — Title, right = time
    - Reflowable docs only (e.g., EPUB), not PDFs/CBZ.
    - Centers within page margins and adapts to rotation (uses bb width).
--]]

local Blitbuffer = require("ffi/blitbuffer")
local TextWidget = require("ui/widget/textwidget")
local BD         = require("ui/bidi")
local Size       = require("ui/size")
local Geom       = require("ui/geometry")
local Device     = require("device")
local Font       = require("ui/font")
local util       = require("util")
local datetime   = require("datetime")
local _          = require("gettext")
local T          = require("ffi/util").template

local ReaderView = require("apps/reader/modules/readerview")
local _ReaderView_paintTo_orig = ReaderView.paintTo

-- Use footer settings for font defaults if present
local header_settings = G_reader_settings:readSetting("footer")

ReaderView.paintTo = function(self, bb, x, y)
    _ReaderView_paintTo_orig(self, bb, x, y)

    -- Only for reflowable docs (exclude fixed-layout like PDF/CBZ)
    if self.render_mode ~= nil then return end

    ----------------------------------------------------------------------
    -- Config
    ----------------------------------------------------------------------
    local header_font_face   = "ffont" -- same as KOReader footer
    local header_font_size   = header_settings.text_font_size or 14
    local header_font_bold   = header_settings.text_font_bold or false
    local header_font_color  = Blitbuffer.COLOR_BLACK
    local header_top_padding = (Size and Size.padding and Size.padding.large) or 8
    local header_use_book_margins = true
    local header_margin      = (Size and Size.padding and Size.padding.large) or 8

    -- Max width caps (percent of *available* width between margins)
    local center_max_width_pct = 60  -- Author — Title
    local right_max_width_pct  = 24  -- Time

    -- Use an en dash; switch to "-" if you prefer ASCII
    local separator = { en_dash = "–" }

    ----------------------------------------------------------------------
    -- Data
    ----------------------------------------------------------------------
    local book_title  = self.ui.doc_props.display_title or ""
    local book_author = self.ui.doc_props.authors or ""
    if book_author:find("\n") then
        book_author = T(_("%1 et al."), util.splitToArray(book_author, "\n")[1] .. ",")
    end

    -- Time (24h/12h follows KOReader setting)
    local time = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))

    ----------------------------------------------------------------------
    -- Layout (use live buffer width so landscape is correct)
    ----------------------------------------------------------------------
    local view_w = bb:getWidth()

    local left_margin  = header_margin
    local right_margin = header_margin
    if header_use_book_margins then
        local pm = self.document:getPageMargins() or {}
        left_margin  = pm.left  or header_margin
        right_margin = pm.right or header_margin
    end

    local avail_width = view_w - (left_margin + right_margin)
    local face = Font:getFace(header_font_face, header_font_size)

    local function getFittedText(text, max_width_pct, face_, bold_)
        if not text or text == "" then return "" end
        local tw = TextWidget:new{
            text = text:gsub(" ", "\u{00A0}"),
            max_width = avail_width * (max_width_pct/100),
            face = face_,
            bold = bold_,
            padding = 0,
        }
        local fitted, add_ellipsis = tw:getFittedText()
        tw:free()
        if add_ellipsis then fitted = fitted .. "…" end
        return BD.auto(fitted)
    end

    -- Compose strings
    local center_str = getFittedText(
        string.format("%s %s %s", book_author, separator.en_dash, book_title),
        center_max_width_pct, face, header_font_bold
    )
    local right_str  = getFittedText(time, right_max_width_pct, face, header_font_bold)

    -- Widgets
    local center_text = TextWidget:new{
        text = center_str, face = face, bold = header_font_bold,
        fgcolor = header_font_color, padding = 0
    }
    local right_text  = TextWidget:new{
        text = right_str,  face = face, bold = header_font_bold,
        fgcolor = header_font_color, padding = 0
    }

    -- Measurements
    local mid_w   = center_text:getSize().w
    local right_w = right_text:getSize().w
    local line_h  = math.max(center_text:getSize().h, right_text:getSize().h)

    -- Positions within the content area (between margins)
    local y_text  = y + header_top_padding
    local x_content_left = x + left_margin
    local x_center = x_content_left + math.floor((avail_width - mid_w) / 2)
    local x_right  = x_content_left + (avail_width - right_w)

    -- Paint
    center_text:paintTo(bb, x_center, y_text)
    right_text:paintTo(bb, x_right,  y_text)

    -- Free
    center_text:free()
    right_text:free()
end
