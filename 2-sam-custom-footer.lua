local ReaderFooter = require("apps/reader/modules/readerfooter")
local Size = require("ui/size")

local cycle_setting_key = "sam_custom_footer_cycle_mode"
local cycle_modes = {
    "page_progress",
    "pages_left_chapter",
    "percentage",
}
local footer_bar_gap = Size.span.vertical_default * 2

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
            return ("%s // %s"):format(
                footer.ui.pagemap:getCurrentPageLabel(true),
                footer.ui.pagemap:getLastPageLabel(true)
            )
        end
        return ("%d // %d"):format(footer.pageno, footer.pages)
    end

    if mode == "pages_left_chapter" then
        local left = footer.ui.toc:getChapterPagesLeft(footer.pageno) or footer.ui.document:getTotalPagesLeft(footer.pageno)
        local total = left
        if footer.ui.toc and footer.ui.toc.getChapterPageCount then
            total = footer.ui.toc:getChapterPageCount(footer.pageno) or left
        end
        local current = math.max(1, total - left)
        return ("%d / %d"):format(current, total)
    end

    return ("%." .. footer.settings.progress_pct_format .. "f%%"):format(footer.percent_finished * 100)
end

local function ensure_custom_footer_layout(footer)
    footer.settings.disable_progress_bar = false
    footer.settings.progress_bar_position = "below"
    footer.settings.progress_style_thin = true
    footer.settings.items_separator = "bar"
    footer.settings.align = "center"
    footer.settings.all_at_once = true

    footer.settings.page_progress = false
    footer.settings.pages_left_book = false
    footer.settings.pages_left = false
    footer.settings.percentage = false
    footer.settings.book_title = false
    footer.settings.book_author = false
    footer.settings.bookmark_count = false
    footer.settings.time = false
    footer.settings.battery = false
    footer.settings.book_time_to_read = false
    footer.settings.chapter_time_to_read = false
    footer.settings.frontlight = false
    footer.settings.mem_usage = false
    footer.settings.wifi_status = false
    footer.settings.page_turning_inverted = false
    footer.settings.chapter_progress = false
    footer.settings.custom_text = false

    footer.settings.book_chapter = true
    footer.settings.dynamic_filler = true
    footer.settings.additional_content = true
    footer.settings.book_chapter_max_width_pct = 72
    footer.settings.text_font_size = 14
    footer.settings.progress_margin_width = 30
    footer.settings.container_bottom_padding = 20
    footer.settings.bottom_horizontal_separator = false
    footer.settings.order = {
        [0] = "book_chapter",
        [1] = "dynamic_filler",
        [2] = "additional_content",
    }

    if not footer._sam_custom_footer_content then
        footer._sam_custom_footer_content = function()
            return get_right_text(footer)
        end
        footer:addAdditionalFooterContent(footer._sam_custom_footer_content)
    end

    footer:set_mode_index()
    footer:set_has_no_mode()
    footer:updateFooterTextGenerator()
    footer:applyFooterMode(footer.mode_list.book_chapter)
end

local function apply_custom_vertical_gap(footer)
    if footer.settings.progress_bar_position ~= "below" then
        return
    end

    if footer.vertical_frame and footer.vertical_frame[2] and footer.vertical_frame[2].width then
        footer.vertical_frame[2].width = footer_bar_gap
    end
end

local orig_init = ReaderFooter.init
function ReaderFooter:init(...)
    orig_init(self, ...)
    ensure_custom_footer_layout(self)
end

local orig_onReaderReady = ReaderFooter.onReaderReady
function ReaderFooter:onReaderReady(...)
    orig_onReaderReady(self, ...)
    ensure_custom_footer_layout(self)
    self:updateFooterContainer()
    apply_custom_vertical_gap(self)
    self:resetLayout(true)
    self:onUpdateFooter(true)
end

local orig_updateFooterContainer = ReaderFooter.updateFooterContainer
function ReaderFooter:updateFooterContainer(...)
    orig_updateFooterContainer(self, ...)
    apply_custom_vertical_gap(self)
end

local orig_TapFooter = ReaderFooter.TapFooter
function ReaderFooter:TapFooter(ges)
    if self.view.flipping_visible and ges then
        return orig_TapFooter(self, ges)
    end

    if not ges or not ges.pos then
        return true
    end

    if ges.pos.x >= (self._saved_screen_width or 0) * 0.65 then
        local next_index = (get_cycle_index() % #cycle_modes) + 1
        save_cycle_index(next_index)
        self:onUpdateFooter(true)
        return true
    end

    return true
end
