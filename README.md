# p2s.el --- Post to multiple SNS services simultaneously

`p2s.el` is an Emacs Lisp package for posting content to multiple social media services (Bluesky, Mastodon, etc.) simultaneously.

## Features

- **Simultaneous Posting**: Execute multiple CLI commands (like `bsky` or `toot`) at once.
- **Efficient Compose Buffer**: Reuses a dedicated `*p2s-compose*` buffer with automated window management and real-time character count.
- **Threading & Replies**: Support for replying to your last post using `#+REPLY: t` or `p2s-compose-reply`.
- **Length Validation**: Checks the length for each service before posting, counted the way each service does (Bluesky: 300, Mastodon: 500 with URLs counted as 23 chars).
- **Image Attachments**: Support for attaching images via `#+IMAGE:` syntax, drag-and-drop, and clipboard integration.

## Installation

1. Place `p2s.el` in your load path.
2. Add the following to your `init.el`:

```elisp
(require 'p2s)

;; Enable recommended keybindings (C-c p ...)
(p2s-setup-keybindings)

;; Or use another prefix key
;; (p2s-setup-keybindings "C-c s")
```

## Configuration

### Customizing Commands

By default, it uses `bsky` and `toot` CLI commands.

```elisp
(setq p2s-service-commands
      '((bsky . ("bsky" "post" "--stdin"))
        (toot . ("toot" "post" "--json"))))

;; Select which services to post to
(setq p2s-services '(bsky toot))

;; Customize image attachment flags
(setq p2s-service-image-flags
      '((bsky . "--image")
        (toot . "--media")))

;; Customize reply flags
(setq p2s-service-reply-flags
      '((bsky . "-r")
        (toot . "--reply-last")))

;; Customize the length limit for each service
;; (e.g. if your Mastodon instance allows longer posts)
(setq p2s-service-max-lengths
      '((bsky . 300)
        (toot . 500)))
```

## Usage

### Commands (prefixed by `C-c p` by default)

- **`p2s-compose-post` (`p`)**:
  Opens the `*p2s-compose*` buffer to write your post.
  - `C-c C-c`: Post and close the window. If posting to any service fails, the buffer reappears with your text intact, and pressing `C-c C-c` again retries only the failed services.
  - `C-c C-k`: Cancel and close the window.
  - `C-c C-a`: Attach an image file.
  - `C-c C-y`: Attach an image from the clipboard.
- **`p2s-compose-reply` (`R`)**:
  Opens the compose buffer with `#+REPLY: t` to reply to the last successful post.
- **`p2s-post-region-to-all-services` (`r`)**:
  Posts the active region.
- **`p2s-post-from-minibuffer-to-all` (`m`)**:
  Post directly from the minibuffer.
- **`p2s-post-buffer-to-all-services` (`b`)**:
  Posts the entire current buffer.
- **`p2s-post-below-point-to-all-services` (`f`)**:
  Posts from the next line to the end of the buffer. Useful for posting the body under a heading or note line.
- **`p2s-configure-services` (`c`)**:
  Interactively switch active services.
- **`p2s-reset-last-post-ids` (`C`)**:
  Clear the stored last post IDs.

## Threading and Replies

You can create threads or reply to your previous posts.

1.  **Automatic**: Use `M-x p2s-compose-reply` (`C-c p R`). It automatically inserts `#+REPLY: t` at the top of the buffer.
2.  **Manual**: Add `#+REPLY: t` anywhere in your post content.

`p2s` stores the ID/URI of the last successful post for each service in `p2s-last-post-ids` and saves it to `p2s-save-file` (default: `~/.emacs.d/p2s-last-post-ids`) so it persists across sessions. Set `p2s-save-file` to `nil` to disable persistence.

If a service has no previous post to reply to (for example, Bluesky right after `p2s-reset-last-post-ids`), the reply is not sent to any service. Remove the `#+REPLY: t` line to post normally.

## Image Attachments

You can attach images to your posts using the `#+IMAGE:` syntax. Lines starting with `#+IMAGE:` are extracted as attachments and removed from the post body before sending.

### Drag and Drop
Drag an image file into the `*p2s-compose*` buffer. A `#+IMAGE: /path/to/image` line will be automatically inserted.

### Clipboard Support
Press `C-c C-y` (or `M-x p2s-attach-clipboard-image`) to save the image currently in your clipboard to a temporary file and insert the `#+IMAGE:` line.
- Requires `pngpaste` on macOS.
- Requires `xclip` on Linux.

### Manual Attachment
Press `C-c C-a` (or `M-x p2s-attach-image`) to select a file from your file system.

## Requirements

- External CLI tools (e.g., `bsky`, `toot`) must be installed and available in your PATH.
- Posts exceeding the limit of any service (`p2s-service-max-lengths`) will be blocked with a `user-error`. Services not listed there use `p2s-max-length`.
