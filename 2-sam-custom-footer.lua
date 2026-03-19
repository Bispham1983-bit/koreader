local Device = require("device")
local ReaderFooter = require("apps/reader/modules/readerfooter")
local TextWidget = require("ui/widget/textwidget")
local userpatch = require("userpatch")

local Screen = Device.screen
local footerTextGeneratorMap = userpatch.getUpValue(ReaderFooter.applyFooterMode, "footerTextGeneratorMap")

local cycle_setting_key = "sam_custom_footer_cycle_mode"
local cycle_modes = {
    "page_progress",
    "pages_left_chapter",
    "pages_left_book",
    "percentage",
}

local function get_cycle_index()
    local saved = tonumber(G_reader_settings:readSetting(cycle_setting_key)) or 1
    if saved < 1 or saved > #cycle_modes then
        return 1
    end
    return saved
end

local function save_cycle_index(index)
    G_reader_settings:saveSetting(cycle_setting_key, index)
end

local function get_right_text(footer)
    local mode = cycle_modes[get_cycle_index()]

    if mode == "page_progress" then
        if footer.ui.pagemap and footer.ui.pagemap:wantsPageLabels() then
            return ("%s/%s"):format(
                footer.ui.pagemap:getCurrentPageLabel(true),
                footer.ui.pagemap:getLastPageLabel(true)
            )
        end
        return ("%d/%d"):format(footer.pageno, footer.pages)
    end

    if mode == "pages_left_chapter" then
        local left = footer.ui.toc:getChapterPagesLeft(footer.pageno) or footer.ui.document:getTotalPagesLeft(footer.pageno)
        if footer.settings.pages_left_includes_current_page then
            left = left + 1
        end
        return ("%d left ch"):format(left)
    end

    if mode == "pages_left_book" then
        local left = footer.pages - footer.pageno
        if footer.settings.pages_left_includes_current_page then
            left = left + 1
        end
        return ("%d left"):format(left)
    end

    return ("%." .. footer.settings.progress_pct_format .. "f%%"):format(footer.percent_finished * 100)
end

local function build_custom_footer_text(footer)
    local max_width = math.floor(footer._saved_screen_width - 2 * footer.horizontal_margin)
    local right_text = get_right_text(footer)
    local title = footer.ui.doc_props.display_title or footer.ui.doc_props.title or ""

    local right_widget = TextWidget:new{
        text = right_text,
        face = footer.footer_text_face,
        bold = footer.settings.text_font_bold,
    }
    local right_width = right_widget:getSize().w
    right_widget:free()

    local space_widget = TextWidget:new{
        text = " ",
        face = footer.footer_text_face,
        bold = footer.settings.text_font_bold,
    }
    local space_width = space_widget:getSize().w
    space_widget:free()

    local title_limit = math.max(0, max_width - right_width - (space_width * 2))
    local title_limit_pct = math.max(10, math.floor((title_limit / max_width) * 100))
    local fitted_title = footer:getFittedText(title, title_limit_pct)

    local title_widget = TextWidget:new{
        text = fitted_title,
        face = footer.footer_text_face,
        bold = footer.settings.text_font_bold,
    }
    local title_width = title_widget:getSize().w
    title_widget:free()

    local filler_spaces = math.max(2, math.floor((max_width - title_width - right_width) / space_width))

    return fitted_title .. (" "):rep(filler_spaces) .. right_text
end

local orig_init = ReaderFooter.init
function ReaderFooter:init(...)
    orig_init(self, ...)

    self.settings.disable_progress_bar = false
    self.settings.progress_bar_position = "above"
    self.settings.progress_style_thin = true
    self.settings.items_separator = "none"
    self.settings.align = "left"
    self.settings.all_at_once = false
    self.settings.book_title = false
    self.settings.page_progress = true

    self:applyFooterMode(self.mode_list.page_progress)
end

local orig_genAllFooterText = ReaderFooter.genAllFooterText
function ReaderFooter:genAllFooterText(generator, ...)
    if generator == nil or generator == footerTextGeneratorMap.page_progress then
        return build_custom_footer_text(self), false
    end
    return orig_genAllFooterText(self, generator, ...)
end

local orig_TapFooter = ReaderFooter.TapFooter
function ReaderFooter:TapFooter(ges)
    if self.view.flipping_visible and ges then
        return orig_TapFooter(self, ges)
    end

    if not ges or not ges.pos then
        return true
    end

    if ges.pos.x >= Screen:getWidth() * 0.65 then
        local next_index = (get_cycle_index() % #cycle_modes) + 1
        save_cycle_index(next_index)
        self:onUpdateFooter(true)
        return true
    end

    return true
end
