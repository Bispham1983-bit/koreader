local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ReaderUI = require("apps/reader/readerui")
local ReaderView = require("apps/reader/modules/readerview")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local datetime = require("datetime")

local Screen = Device.screen
local screen_width = Screen:getWidth()

local header_font_face = "ffont"
local header_font_size = 20
local header_top_padding = Size.padding.small
local header_margin = Size.padding.large
local min_section_spacing = 10

local current_reader_ui = nil
local dimen_refresh = nil

local function create_text_widget(text)
    return TextWidget:new{
        text = text or "",
        face = Font:getFace(header_font_face, header_font_size),
        padding = 0,
    }
end

local _ReaderView_paintTo_orig = ReaderView.paintTo
ReaderView.paintTo = function(self, bb, x, y)
    _ReaderView_paintTo_orig(self, bb, x, y)

    local title = ""
    if self.ui and self.ui.doc_props then
        title = self.ui.doc_props.display_title or self.ui.doc_props.title or ""
    end

    local time_text = datetime.secondsToHour(
        os.time(),
        G_reader_settings:isTrue("twelve_hour_clock")
    )

    local title_widget = create_text_widget(title)
    local time_widget = create_text_widget(time_text)

    local title_width = title_widget:getSize().w
    local time_width = time_widget:getSize().w
    local available_width = screen_width - (header_margin * 2)
    local left_width = math.max(0, math.floor((available_width - title_width) / 2))
    local middle_width = math.max(
        min_section_spacing,
        available_width - left_width - title_width - time_width
    )

    dimen_refresh = Geom:new{
        w = screen_width,
        h = math.max(title_widget:getSize().h, time_widget:getSize().h) + header_top_padding,
    }

    local header = CenterContainer:new{
        dimen = dimen_refresh,
        VerticalGroup:new{
            VerticalSpan:new{width = header_top_padding},
            HorizontalGroup:new{
                HorizontalSpan:new{width = header_margin + left_width},
                title_widget,
                HorizontalSpan:new{width = middle_width},
                time_widget,
                HorizontalSpan:new{width = header_margin},
            },
        },
    }

    header:paintTo(bb, x, y)
end

local _ReaderUI_init_orig = ReaderUI.init
ReaderUI.init = function(self, ...)
    _ReaderUI_init_orig(self, ...)

    current_reader_ui = self

    local function schedule_header_refresh()
        local seconds = 61 - tonumber(os.date("%S"))
        UIManager:scheduleIn(seconds, function()
            if current_reader_ui
                and current_reader_ui.view
                and current_reader_ui.document
                and current_reader_ui.view.state
                and current_reader_ui.view.state.page
                and dimen_refresh
            then
                UIManager:setDirty(current_reader_ui, "fast", dimen_refresh)
            end
            schedule_header_refresh()
        end)
    end

    schedule_header_refresh()
end
