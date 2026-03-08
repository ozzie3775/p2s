# p2s.el --- Post to multiple SNS services simultaneously

`p2s.el` is an Emacs Lisp package for posting content to multiple social media services (Bluesky, Mastodon, etc.) simultaneously. It also supports automatic logging of your posts using `org-capture`.

## Features

- **Simultaneous Posting**: Execute multiple CLI commands (like `bsky` or `toot`) at once.
- **Efficient Compose Buffer**: Reuses a dedicated `*p2s-compose*` buffer with automated window management.
- **Length Validation**: Checks character length before posting to prevent API errors (default: 300 chars).
- **Org-capture Integration**: Automatically logs posts into Org files using templates.

## Installation

1. Place `p2s.el` in your load path.
2. Add the following to your `init.el`:

```elisp
(require 'p2s)

;; Enable recommended keybindings (C-c p ...)
(p2s-setup-keybindings)

;; Enable logging (set your preferred capture template key)
(setq p2s-org-capture-key "s")
```

## Configuration

### Customizing Commands

By default, it uses `bsky` and `toot` CLI commands.

```elisp
(setq p2s-service-commands
      '((bsky . ("bsky" "post" "--stdin"))
        (toot . ("toot" "post"))))

;; Select which services to post to
(setq p2s-services '(bsky toot))
```

### Org-capture Logging

When `p2s-org-capture-key` is set, `org-capture` is triggered upon posting. The post content is passed to the `%i` template variable.

To avoid extra empty lines, we recommend a template structure like **`* %U\n%i`**.

```elisp
(setq p2s-org-capture-key "s")

;; Example org-capture-templates
(setq org-capture-templates
      '(("s" "SNS Post Log" entry (file+olp+datetree "~/org/posts.org")
         "* %U\n%i" :immediate-finish t :prepend t)))
```

## Usage

### Commands

- **`p2s-compose-post` (`C-c p p`)**:
  Opens the `*p2s-compose*` buffer to write your post.
  - `C-c C-c`: Post and close the window.
  - `C-c C-k`: Cancel and close the window.
- **`p2s-post-region-to-all-services` (`C-c p r`)**:
  Posts the active region.
- **`p2s-post-from-minibuffer-to-all` (`C-c p m`)**:
  Post directly from the minibuffer.
- **`p2s-post-buffer-to-all-services` (`C-c p b`)**:
  Posts the entire current buffer.
- **`p2s-configure-services` (`C-c p c`)**:
  Interactively switch active services.

## Requirements

- External CLI tools (e.g., `bsky`, `toot`) must be installed and available in your PATH.
- Posts exceeding `p2s-max-length` will be blocked with a `user-error`.
- Trailing whitespace/newlines are automatically trimmed before logging to Org-mode.
