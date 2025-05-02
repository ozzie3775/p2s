
## 使い方

1. このコードを `p2s.el` として保存し、ロードパスに配置
2. 設定ファイルに以下を追加:

```elisp
(require 'p2s)
;; 任意: 推奨キーバインドをセットアップ
(p2s-setup-keybindings)
```

3. または use-package を使用:

```elisp
(use-package p2s
  :load-path "~/path/to/p2s"
  :bind (("C-c p r" . p2s-post-region-to-all-services)
         ("C-c p m" . p2s-post-from-minibuffer-to-all)
         ("C-c p c" . p2s-configure-services))
  :config
  (setq p2s-max-length 500))  ;; 必要に応じて文字数制限を変更
```

## 主な機能

- **`p2s-post-region-to-all-services`**: 選択範囲を全サービスに投稿（300 文字超で警告）
- **`p2s-post-from-minibuffer-to-all`**: ミニバッファから投稿（300 文字超で警告）
- **`p2s-configure-services`**: 投稿するサービスを選択
- **`p2s-setup-keybindings`**: 推奨キーバインドの設定

なお、300 文字を超える投稿は `user-error` でブロックされ、投稿処理は実行されません。
