# p2s.el --- Post to multiple SNS services simultaneously

`p2s.el` は、複数のソーシャルメディアサービス（Bluesky, Mastodon など）へ同時に投稿するための Emacs Lisp パッケージです。投稿内容は `org-capture` を使用してログとして保存することも可能です。

## 特徴

- **複数サービス同時投稿**: `bsky` や `toot` などの外部コマンドを利用して一括投稿
- **専用バッファでの作成**: `*p2s-compose*` バッファで内容を推敲して投稿
- **文字数制限**: 投稿前に文字数をチェック（デフォルト300文字）
- **投稿ログ**: `org-capture` と連携し、投稿内容を自動的に記録

## インストール

1. `p2s.el` をロードパスの通ったディレクトリに配置します。
2. `~/.emacs.d/init.el` 等に以下の設定を追加します。

```elisp
(require 'p2s)

;; 推奨キーバインドを有効化 (C-c p ...)
(p2s-setup-keybindings)

;; 投稿ログを有効にする場合（例: "s" というテンプレートキーを使用）
(setq p2s-org-capture-key "s")
```

`use-package` を使用する場合：

```elisp
(use-package p2s
  :load-path "~/path/to/p2s"
  :bind-keymap ("C-c p" . p2s-setup-keybindings) ;; または個別に bind
  :config
  (setq p2s-max-length 300)
  (setq p2s-org-capture-key "s"))
```

## 設定

### 投稿コマンドの設定

デフォルトでは `bsky` と `toot` コマンドを使用するように設定されています。

```elisp
(setq p2s-service-commands
      '((bsky . ("bsky" "post" "--stdin"))
        (toot . ("toot" "post"))))

;; 投稿対象のサービスを選択
(setq p2s-services '(bsky toot))
```

### Org-capture ログの設定

`p2s-org-capture-key` を設定すると、投稿時に自動的に `org-capture` が実行されます。テンプレート内で `%i` を使用すると、投稿内容が挿入されます。

```elisp
(setq p2s-org-capture-key "s")

;; org-capture-templates の例
(setq org-capture-templates
      '(("s" "SNS Post Log" entry (file "~/org/sns-log.org")
         "* %u\n%i\n" :immediate-finish t)))
```

## 使い方

### 主要コマンド

- **`p2s-compose-post` (`C-c p p`)**:
  専用の `*p2s-compose*` バッファを開いて投稿内容を作成します。
  - `C-c C-c`: 投稿してバッファを閉じる
  - `C-c C-k`: 投稿をキャンセルしてバッファを閉じる
- **`p2s-post-region-to-all-services` (`C-c p r`)**:
  選択中のリージョンを投稿します。
- **`p2s-post-from-minibuffer-to-all` (`C-c p m`)**:
  ミニバッファから手軽に投稿します。
- **`p2s-post-buffer-to-all-services` (`C-c p b`)**:
  現在のバッファ全体を投稿します。
- **`p2s-post-below-point-to-all-services`**:
  現在のカーソル位置より下の内容を投稿します。
- **`p2s-configure-services` (`C-c p c`)**:
  一時的に投稿対象のサービスを切り替えます。

## 注意事項

- 各サービスの外部コマンド（`bsky`, `toot` など）がインストールされており、パスが通っている必要があります。
- 文字数制限（`p2s-max-length`）を超えた場合、投稿は実行されません。
