# gitnotes.nvim

Gitnotes is a simple note taking system for nvim, syncing the files via git.

---

I found that I wouldn't pick up note taking seriously as I would normally be on different machines though out the day. 
So i made gitnotes, it aims to be super simple with the least amount of setup to keep working on your notes on a new machine. 

You define a repo where your notes live on github and a folder and you are all good to go! If you already use a system like [Obsidian](https://obsidian.md) you can just point it to the same folder.

---
# installation

with lazyvim:

```lua
return {

  {
    dir = "~/gitnotes.nvim/",
    config = function()
      require("notes").setup({
        dir = vim.fn.expand("~") .. "/notes", -- default
        --sync_interval = 300, -- seconds, default 5min
        --pull_interval = 300, -- seconds
        remote = "git@github.com:user/notes.git",
      })
      -- Optional: Set keymaps manually (examples)
      local notes = require("notes")
      vim.keymap.set("n", "<leader>nn", function()
        local title = vim.fn.input("Note title (Enter for date): ")
        notes.new_note(title)
      end, { desc = "Notes: New note" })
      vim.keymap.set("n", "<leader>nl", function()
        notes.list_notes()
      end, { desc = "Notes: List notes" })
      vim.keymap.set("n", "<leader>nd", function()
        notes.delete_note()
      end, { desc = "Notes: Delete current note" })
      vim.keymap.set("n", "<leader>ns", function()
        notes.sync()
      end, { desc = "Notes: Sync (pull if needed + commit/push)" })
      vim.keymap.set("n", "<leader>np", function()
        notes.pull()
      end, { desc = "Notes: Pull" })
      vim.keymap.set("n", "<leader>ni", function()
        notes.init_repo()
      end, { desc = "Notes: Init repo" })
      vim.keymap.set("n", "<leader>nf", function()
        notes.follow_link()
      end, { desc = "Notes: follow link" })
    end,
  },
}
```
