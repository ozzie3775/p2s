# p2s.el --- Post to multiple SNS services simultaneously

`p2s.el` は、複数のソーシャルメディアサービス（Bluesky, Mastodon など）へ同時に投稿するための Emacs Lisp パッケージです。投稿内容は `org-capture` を利用して自動的にログとして保存できます。

## 特徴

- **複数サービス同時投稿**: `bsky` や `toot` などの外部 CLI コマンドを一括実行。
- **効率的な投稿バッファ**: `*p2s-compose*` バッファを再利用し、ウィンドウ管理も自動化。
- **文字数チェック**: 投稿前に文字数を検証し、制限超過を防止（デフォルト 300 文字）。
- **Org-capture 連携**: 投稿した内容を Org-mode のテンプレート（`%i`）に流し込み、日付ツリー等に自動記録。

## インストール

1. `p2s.el` をロードパスの通ったディレクトリに配置します。
2. `init.el` 等に以下の設定を追加します。

```elisp
(require 'p2s)

;; 推奨キーバインドを有効化 (C-c p ...)
(p2s-setup-keybindings)

;; 投稿ログを有効にする場合（例: "s" というテンプレートキーを使用）
(setq p2s-org-capture-key "s")
```

## 設定

### 投稿コマンド

デフォルトでは `bsky` と `toot` コマンドを使用するように設定されています。

```elisp
(setq p2s-service-commands
      '((bsky . ("bsky" "post" "--stdin"))
        (toot . ("toot" "post"))))

;; 実際に投稿する対象のサービスを指定
(setq p2s-services '(bsky toot))
```

### Org-capture ログの設定

`p2s-org-capture-key` を設定すると、投稿時に `org-capture` が実行されます。テンプレート内で `%i` を使うと、投稿内容が挿入されます。

空行を防ぐため、テンプレートの定義は以下のように **`\n%i`** とつなげるのがおすすめです。

```elisp
(setq p2s-org-capture-key "s")

;; org-capture-templates の設定例
(setq org-capture-templates
      '(("s" "SNS Post Log" entry (file+olp+datetree "~/org/posts.org")
         "* %U\n%i" :immediate-finish t :prepend t)))
```

## 使い方

### 主要コマンド

- **`p2s-compose-post` (`C-c p p`)**:
  専用の `*p2s-compose*` バッファを開いて投稿を作成します。バッファは再利用されるため、増え続けることはありません。
  - `C-c C-c`: 投稿を実行し、ウィンドウを閉じます。
  - `C-c C-k`: 投稿をキャンセルし、ウィンドウを閉じます。
- **`p2s-post-region-to-all-services` (`C-c p r`)**:
  選択中のリージョンを投稿します。
- **`p2s-post-from-minibuffer-to-all` (`C-c p m`)**:
  ミニバッファから手軽に投稿します。
- **`p2s-post-buffer-to-all-services` (`C-c p b`)**:
  現在のバッファ全体を投稿します。
- **`p2s-configure-services` (`C-c p c`)**:
  一時的に投稿対象のサービスを切り替えます。

## 注意事項

- 各サービスの外部コマンドがインストールされ、PATH が通っている必要があります。
- 文字数制限（`p2s-max-length`）を超えた場合、`user-error` で投稿がブロックされます。
- `org-capture` 連携時、投稿テキストの末尾の不要な改行は自動で削除（trim）されます。
