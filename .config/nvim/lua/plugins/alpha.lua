return {
  "goolord/alpha-nvim",
  dependencies = {
    "nvim-tree/nvim-web-devicons",
  },

  config = function()
    local alpha = require("alpha")
    local dashboard = require("alpha.themes.startify")
    local devicons = require("nvim-web-devicons")

    -- Time-based greeting
    local function get_greeting()
      local hour = tonumber(os.date("%H"))
      local greeting = "Good evening"
      
      if hour >= 5 and hour < 12 then
        greeting = "Good morning"
      elseif hour >= 12 and hour < 17 then
        greeting = "Good afternoon"
      end

      -- Get username and check if it should be displayed
      local username = os.getenv("USER") or os.getenv("USERNAME")
      local excluded_names = {
        user = true,
        admin = true,
        administrator = true,
        root = true,
        ["ec2-user"] = true
      }
      
      if username and not excluded_names[string.lower(username)] then
        greeting = greeting .. " " .. username .. "!"
      else
        greeting = greeting .. "!"
      end
      
      return greeting
    end

    -- Menu items with icons
    local function get_icon(filetype)
      local icon, _ = devicons.get_icon_by_filetype(filetype, { default = true })
      return icon
    end

    dashboard.section.top_buttons = {
      type = "group",
      val = {
        dashboard.button("e", get_icon("default") .. " New file", ":ene <BAR> startinsert <CR>"),
        dashboard.button("f", get_icon("finder") .. " Find file", ":Telescope find_files<CR>"),
        dashboard.button("r", get_icon("recent") .. " Recent files", ":Telescope oldfiles<CR>"),
        dashboard.button("q", get_icon("quit") .. " Quit", ":qa<CR>"),
      }
    }

    -- Header with logo
    dashboard.section.header.val = {
      [[                                                                       ]],
      [[                                                                       ]],
      [[                                                                       ]],
      [[                                                                       ]],
      [[                                                                     ]],
      [[       ████ ██████           █████      ██                     ]],
      [[      ███████████             █████                             ]],
      [[      █████████ ███████████████████ ███   ███████████   ]],
      [[     █████████  ███    █████████████ █████ ██████████████   ]],
      [[    █████████ ██████████ █████████ █████ █████ ████ █████   ]],
      [[  ███████████ ███    ███ █████████ █████ █████ ████ █████  ]],
      [[ ██████  █████████████████████ ████ █████ █████ ████ ██████ ]],
      [[                                                                       ]],
      [[                                                                       ]],
      [[                                                                       ]],
    }

    -- Dynamic greeting
    dashboard.section.greeting = {
      type = "text",
      val = get_greeting(),
      opts = {
        position = "left",
        hl = "String",
        shrink_margin = false,
      }
    }

    -- Plugin statistics in footer
    local function get_plugin_stats()
      local stats = require("lazy").stats()
      local ms = (math.floor(stats.startuptime * 100 + 0.5) / 100)
      return string.format("⚡ Neovim loaded %d plugins in %dms", stats.count, ms)
    end

    dashboard.section.footer = {
      type = "text",
      val = get_plugin_stats(),
      opts = {
        position = "center",
        hl = "Comment",
      }
    }

    -- Set layout order
    dashboard.config.layout = {
      { type = "padding", val = 2 },
      dashboard.section.header,
      { type = "padding", val = 2 },
      dashboard.section.greeting,
      { type = "padding", val = 1 },
      dashboard.section.top_buttons,
      { type = "padding", val = 1 },
      dashboard.section.footer,
    }

    -- Configure options
    dashboard.opts.layout = dashboard.config.layout
    dashboard.opts.opts.margin = 5  -- Add left margin for the entire layout

    alpha.setup(dashboard.opts)
  end,
}