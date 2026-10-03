;;; p2s-test.el --- Tests for p2s.el -*- lexical-binding: t -*-

(require 'ert)
(require 'p2s)

(ert-deftest p2s-test-parse-post-content ()
  "Test p2s--parse-post-content."
  (let ((text "Hello world\n#+IMAGE: /path/to/img1.png\nSome more text\n#+IMAGE: /path/to/img2.jpg\n#+REPLY: t"))
    (pcase-let ((`(,clean-text ,images ,is-reply) (p2s--parse-post-content text)))
      (should (string= clean-text "Hello world\nSome more text"))
      (should (equal images '("/path/to/img1.png" "/path/to/img2.jpg")))
      (should is-reply)))
  
  (let ((text "Just text"))
    (pcase-let ((`(,clean-text ,images ,is-reply) (p2s--parse-post-content text)))
      (should (string= clean-text "Just text"))
      (should (null images))
      (should (null is-reply)))))

(ert-deftest p2s-test-extract-id-bsky ()
  "Test p2s--extract-id for Bluesky."
  (let ((output "{\"uri\": \"at://did:plc:abc/app.bsky.feed.post/123\", \"cid\": \"...\"}"))
    (should (string= (p2s--extract-id 'bsky output) "at://did:plc:abc/app.bsky.feed.post/123")))
  (let ((output "uri: at://did:plc:abc/app.bsky.feed.post/456"))
    (should (string= (p2s--extract-id 'bsky output) "at://did:plc:abc/app.bsky.feed.post/456"))))

(ert-deftest p2s-test-extract-id-toot ()
  "Test p2s--extract-id for Mastodon (toot)."
  (let ((output "{\"id\": \"112490000000000000\", \"account\": {\"id\": \"1\", ...}}"))
    (should (string= (p2s--extract-id 'toot output) "112490000000000000")))
  (let ((output "{\"id\": 123456789}"))
    (should (string= (p2s--extract-id 'toot output) "123456789")))
  (let ((output "Post created with ID 987654321"))
    (should (string= (p2s--extract-id 'toot output) "987654321"))))

(ert-deftest p2s-test-build-command ()
  "Test p2s--build-command."
  (let ((p2s-service-commands '((test . ("testcmd" "post"))))
        (p2s-service-image-flags '((test . "--img")))
        (p2s-service-reply-flags '((test . "--reply")))
        (p2s-last-post-ids '((test . "last-id"))))
    ;; Basic post
    (should (equal (p2s--build-command 'test nil nil)
                   '("testcmd" "post")))
    ;; With images
    (should (equal (p2s--build-command 'test '("img1.png") nil)
                   '("testcmd" "post" "--img" "img1.png")))
    ;; With multiple images
    (should (equal (p2s--build-command 'test '("img1.png" "img2.png") nil)
                   '("testcmd" "post" "--img" "img1.png" "--img" "img2.png")))
    ;; With reply
    (should (equal (p2s--build-command 'test nil t)
                   '("testcmd" "post" "--reply" "last-id")))
    ;; With --reply-last (special case)
    (let ((p2s-service-reply-flags '((test . "--reply-last"))))
      (should (equal (p2s--build-command 'test nil t)
                     '("testcmd" "post" "--reply-last"))))))

(ert-deftest p2s-test-persistence ()
  "Test that last post IDs can be saved and loaded from a file."
  (let* ((temp-file (make-temp-file "p2s-test-ids"))
         (p2s-save-file temp-file)
         (p2s-last-post-ids '((bsky . "at://test1") (toot . "test2"))))
    (unwind-protect
        (progn
          ;; Save current IDs to temp file
          (p2s-save-last-post-ids)
          ;; Clear active variable
          (setq p2s-last-post-ids nil)
          ;; Load back
          (p2s-load-last-post-ids)
          ;; Check if restored correctly
          (should (equal p2s-last-post-ids '((bsky . "at://test1") (toot . "test2")))))
      (when (file-exists-p temp-file)
        (delete-file temp-file)))))

(ert-deftest p2s-test-setup-keybindings ()
  "Test that `p2s-setup-keybindings' binds the prefix map globally."
  (let ((orig-map (current-global-map))
        (test-map (make-sparse-keymap)))
    (use-global-map test-map)
    (unwind-protect
        (progn
          ;; Default prefix
          (p2s-setup-keybindings)
          (should (eq (lookup-key test-map (kbd "C-c p")) p2s-prefix-map))
          (should (eq (lookup-key test-map (kbd "C-c p p")) #'p2s-compose-post))
          ;; Custom prefix
          (p2s-setup-keybindings "C-c s")
          (should (eq (lookup-key test-map (kbd "C-c s")) p2s-prefix-map)))
      (use-global-map orig-map))))

(provide 'p2s-test)
