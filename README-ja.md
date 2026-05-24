# p2s.el --- 複数 SNS サービスへの同時投稿

`p2s.el` は、Bluesky や Mastodon などの複数のソーシャルメディアサービスへ Emacs から同時に投稿するためのパッケージです。投稿内容は `org-capture` を利用して自動的にログとして保存することも可能です。

## 主な機能

- **同時投稿**: `bsky` や `toot` などの外部 CLI コマンドを一括実行。
- **効率的な投稿バッファ**: 専用の `*p2s-compose*` バッファを再利用。ウィンドウ管理の自動化に加え、リアルタイムの文字数カウントを表示。
- **スレッド・リプライ**: `#+REPLY: t` 記法や `p2s-compose-reply` を使用した、直前の投稿への返信（スレッド作成）に対応。
- **文字数チェック**: 投稿前に文字数を検証し、エラーを防止（デフォルト 300 文字）。
- **Org-capture 連携**: 投稿した内容を Org-mode のテンプレート（`%i`）に流し込み、日付ツリー等に自動記録。画像パスも記録に含まれます。
- **画像投稿**: `#+IMAGE:` 記法、ドラッグ＆ドロップ、クリップボードからの貼り付けによる画像添付に対応。

## インストール

1. `p2s.el` をロードパスの通ったディレクトリに配置します。
2. `init.el` 等に以下の設定を追加します。

```elisp
(require 'p2s)

;; 推奨キーバインドを有効化 (C-c C-p ...)
(p2s-setup-keybindings)

;; 投稿ログを有効にする場合（例: "s" というテンプレートキーを使用）
(setq p2s-org-capture-key "s")
```

## 設定

### 投稿コマンドのカスタマイズ

デフォルトでは `bsky` と `toot` コマンドを使用するように設定されています。

```elisp
(setq p2s-service-commands
      '((bsky . ("bsky" "post" "--stdin"))
        (toot . ("toot" "post" "--json"))))

;; 実際に投稿する対象のサービスを指定
(setq p2s-services '(bsky toot))

;; 画像添付用のフラグをカスタマイズ
(setq p2s-service-image-flags
      '((bsky . "--image")
        (toot . "--media")))

;; リプライ用のフラグをカスタマイズ
(setq p2s-service-reply-flags
      '((bsky . "-r")
        (toot . "--reply-last")))
```

### Org-capture ログの設定

`p2s-org-capture-key` を設定すると、投稿時に `org-capture` が実行されます。投稿内容はテンプレート変数 `%i` に渡されます。

空行を防ぐため、テンプレートの定義は **`* %U\n%i`** のように記述することをおすすめします。

```elisp
(setq p2s-org-capture-key "s")

;; org-capture-templates の設定例
(setq org-capture-templates
      '(("s" "SNS Post Log" entry (file+olp+datetree "~/org/posts.org")
         "* %U\n%i" :immediate-finish t :prepend t)))
```

## 使い方

### 主要コマンド（デフォルト接頭辞: `C-c C-p`）

- **`p2s-compose-post` (`p`)**:
  `*p2s-compose*` バッファを開いて投稿を作成します。
  - `C-c C-c`: 投稿を実行し、ウィンドウを閉じます。
  - `C-c C-k`: キャンセルし、ウィンドウを閉じます。
  - `C-c C-a`: 画像ファイルを添付します。
  - `C-c C-y`: クリップボードから画像を貼り付けます。
- **`p2s-compose-reply` (`R`)**:
  直前の投稿への返信（リプライ）用バッファを開きます。自動的に `#+REPLY: t` が挿入されます。
- **`p2s-post-region-to-all-services` (`r`)**:
  選択中のリージョンを投稿します。
- **`p2s-post-from-minibuffer-to-all` (`m`)**:
  ミニバッファから手軽に投稿します。
- **`p2s-post-buffer-to-all-services` (`b`)**:
  現在のバッファ全体を投稿します。
- **`p2s-configure-services` (`c`)**:
  一時的に投稿対象のサービスを切り替えます。
- **`p2s-reset-last-post-ids` (`C`)**:
  保存されている直前の投稿 ID をリセットします。

## スレッドとリプライ

自分自身の直前の投稿に対して返信を行い、スレッドを作成できます。

1.  **自動**: `M-x p2s-compose-reply` (`C-c C-p R`) を使用します。バッファの先頭に自動で `#+REPLY: t` が挿入されます。
2.  **手動**: 投稿内容のどこかに `#+REPLY: t` という行を含めます。

`p2s` は、各サービスへの投稿が成功した際の ID/URI を `p2s-last-post-ids` に保存して管理します。

## 画像投稿

`#+IMAGE:` 記法を使用して、投稿に画像を添付できます。`#+IMAGE:` で始まる行は添付ファイルとして抽出され、送信前に本文から自動的に削除されます。

### ドラッグ＆ドロップ
`*p2s-compose*` バッファに画像ファイルをドラッグ＆ドロップすると、`#+IMAGE: /path/to/image` という行が自動的に挿入されます。

### クリップボードからの貼り付け
`C-c C-y` (または `M-x p2s-attach-clipboard-image`) を実行すると、クリップボードにある画像を一時ファイルとして保存し、`#+IMAGE:` 行を挿入します。
- macOS では `pngpaste` が必要です。
- Linux では `xclip` が必要です。

### ファイル選択
`C-c C-a` (または `M-x p2s-attach-image`) でファイルを選択して添付できます。

## 注意事項

- 各サービスの外部コマンド（`bsky`, `toot` など）がインストールされ、PATH が通っている必要があります。
- 文字数制限（`p2s-max-length`）を超えた場合、`user-error` で投稿がブロックされます。
- `org-capture` 連携時、投稿テキストの末尾の不要な改行は自動で削除（trim）されます。
