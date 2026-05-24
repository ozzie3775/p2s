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

(provide 'p2s-test)
