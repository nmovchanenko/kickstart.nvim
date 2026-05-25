return {
  'folke/noice.nvim',
  event = 'VeryLazy',
  opts = {
    -- add any options here
    routes = {
      -- Rule 1: Send multi-line output (like :ls, :registers) to a
      -- persistent split that you must manually close with 'q'
      {
        filter = {
          event = 'msg_show',
          min_height = 2, -- catches anything 2+ lines tall
        },
        view = 'split', -- stays open until YOU close it
      },

      -- Rule 2: Keep short, single-line confirmations in the auto-dismiss mini
      {
        filter = {
          event = 'msg_show',
          max_height = 1,
        },
        view = 'mini', -- auto-dismisses as before
      },
    },

    -- Optional: tune the mini view's timeout (ms)
    views = {
      mini = {
        timeout = 5000, -- bumped from default ~3s to 5s
      },
    },
  },
}
