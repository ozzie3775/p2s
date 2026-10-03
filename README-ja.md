# p2s.el --- 複数 SNS サービスへの同時投稿

`p2s.el` は、Bluesky や Mastodon などの複数のソーシャルメディアサービスへ Emacs から同時に投稿するためのパッケージです。

## 主な機能

- **同時投稿**: `bsky` や `toot` などの外部 CLI コマンドを一括実行。
- **効率的な投稿バッファ**: 専用の `*p2s-compose*` バッファを再利用。ウィンドウ管理の自動化に加え、リアルタイムの文字数カウントを表示。
- **スレッド・リプライ**: `#+REPLY: t` 記法や `p2s-compose-reply` を使用した、直前の投稿への返信（スレッド作成）に対応。
- **文字数チェック**: 投稿前に文字数を検証し、エラーを防止（デフォルト 300 文字）。
- **画像投稿**: `#+IMAGE:` 記法、ドラッグ＆ドロップ、クリップボードからの貼り付けによる画像添付に対応。

## インストール

1. `p2s.el` をロードパスの通ったディレクトリに配置します。
2. `init.el` 等に以下の設定を追加します。

```elisp
(require 'p2s)

;; 推奨キーバインドを有効化 (C-c p ...)
(p2s-setup-keybindings)

;; 別の接頭キーを使う場合
;; (p2s-setup-keybindings "C-c s")
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

## 使い方

### 主要コマンド（デフォルト接頭辞: `C-c p`）

- **`p2s-compose-post` (`p`)**:
  `*p2s-compose*` バッファを開いて投稿を作成します。
  - `C-c C-c`: 投稿を実行し、ウィンドウを閉じます。投稿に失敗したサービスがあると、本文を残したままバッファを再表示します。もう一度 `C-c C-c` を押すと、失敗したサービスにだけ再投稿します。
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

1.  **自動**: `M-x p2s-compose-reply` (`C-c p R`) を使用します。バッファの先頭に自動で `#+REPLY: t` が挿入されます。
2.  **手動**: 投稿内容のどこかに `#+REPLY: t` という行を含めます。

`p2s` は、各サービスへの投稿が成功した際の ID/URI を `p2s-last-post-ids` に保存して管理します。この ID は `p2s-save-file`（デフォルト: `~/.emacs.d/p2s-last-post-ids`）にも保存され、Emacs を再起動しても引き継がれます。`p2s-save-file` を `nil` にすると保存しません。

返信先の投稿がないサービスがある場合（`p2s-reset-last-post-ids` の直後の Bluesky など）、どのサービスにも投稿しません。通常の投稿にするには `#+REPLY: t` の行を削除してください。

## 画像投稿

`#+IMAGE:` 記法を使用して、投稿に画像を添付できます。`#+IMAGE:` で始まる行は添付ファイルとして抽出され、送信前に本文から自動的に削除されます。

### ドラッグ＆ドロップ
`*p2s-compose*` バッファに画像ファイルをドラッグ＆ドロップすると、`#+IMAGE: /path/to/image` という行が自動的に挿入されます。

### クリップボードからの貼り付け
`C-c C-y` (or `M-x p2s-attach-clipboard-image`) を実行すると、クリップボードにある画像を一時ファイルとして保存し、`#+IMAGE:` 行を挿入します。
- macOS では `pngpaste` が必要です。
- Linux では `xclip` が必要です。

### ファイル選択
`C-c C-a` (or `M-x p2s-attach-image`) でファイルを選択して添付できます。

## 注意事項

- 各サービスの外部コマンド（`bsky`, `toot` など）がインストールされ、PATH が通っている必要があります。
- 文字数制限（`p2s-max-length`）を超えた場合、`user-error` で投稿がブロックされます。
