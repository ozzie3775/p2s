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
  ;; The top-level status ID, not the account ID
  (let ((output "{\"account\": {\"id\": \"1\"}, \"id\": \"112490000000000000\"}"))
    (should (string= (p2s--extract-id 'toot output) "112490000000000000")))
  (let ((output "{\"id\": 123456789}"))
    (should (string= (p2s--extract-id 'toot output) "123456789")))
  ;; Status URL printed without --json
  (let ((output "Toot posted: https://mastodon.example/@user/112490000000000001"))
    (should (string= (p2s--extract-id 'toot output) "112490000000000001")))
  ;; Unrelated numbers are not taken as an ID
  (let ((output "Error 500: try again in 30 seconds"))
    (should-not (p2s--extract-id 'toot output))))

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
         (p2s--loaded-save-file nil)
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

(defmacro p2s-test-with-services (commands &rest body)
  "Run BODY with fake services defined by COMMANDS.
COMMANDS is an alist of (SERVICE . COMMAND-LIST)."
  (declare (indent 1))
  `(let* ((p2s-service-commands ,commands)
          (p2s-services (mapcar #'car p2s-service-commands))
          (p2s-service-image-flags nil)
          (p2s-service-reply-flags nil)
          (p2s-last-post-ids nil)
          (p2s-save-file nil)
          (p2s--loaded-save-file nil))
     ,@body))

(defun p2s-test-wait-for (pred)
  "Process subprocess output until PRED returns non-nil (5 sec timeout)."
  (with-timeout (5 (error "Timed out waiting for p2s processes"))
    (while (not (funcall pred))
      (accept-process-output nil 0.05))))

(defconst p2s-test-ok-command
  '("sh" "-c" "cat >/dev/null; echo '{\"id\": \"111\"}'"))

(defconst p2s-test-ng-command
  '("sh" "-c" "cat >/dev/null; echo boom; exit 1"))

(ert-deftest p2s-test-post-on-done ()
  "Test that ON-DONE receives succeeded and failed services."
  (p2s-test-with-services `((toot . ,p2s-test-ok-command)
                            (ng . ,p2s-test-ng-command)
                            (missing . ("p2s-test-no-such-command")))
    (let (result)
      (p2s-post-text-to-all-services
       "hello" nil (lambda (s f) (setq result (list s f))))
      (p2s-test-wait-for (lambda () result))
      (should (equal result '((toot) (ng missing))))
      (should (equal (cdr (assq 'toot p2s-last-post-ids)) "111")))))

(ert-deftest p2s-test-compose-finish-success ()
  "Test that the compose buffer is cleared after a successful post."
  (p2s-test-with-services `((ok . ,p2s-test-ok-command))
    (let ((buf (generate-new-buffer "*p2s-test-compose*")))
      (unwind-protect
          (with-current-buffer buf
            (p2s-post-mode)
            (insert "hello")
            (cl-letf (((symbol-function 'quit-window) #'ignore))
              (p2s-post-mode-finish))
            (should (buffer-live-p buf))
            (p2s-test-wait-for (lambda () (= (buffer-size buf) 0)))
            (should-not p2s--retry-services))
        (kill-buffer buf)))))

(ert-deftest p2s-test-compose-finish-failure-and-retry ()
  "Test that the text is kept on failure and only failed services are retried."
  (p2s-test-with-services `((ok . ,p2s-test-ok-command)
                            (ng . ,p2s-test-ng-command))
    (let ((buf (generate-new-buffer "*p2s-test-compose*"))
          (posted nil))
      (unwind-protect
          (with-current-buffer buf
            (p2s-post-mode)
            (insert "hello")
            (cl-letf (((symbol-function 'quit-window) #'ignore)
                      ((symbol-function 'pop-to-buffer) #'ignore))
              (p2s-post-mode-finish)
              (p2s-test-wait-for (lambda () p2s--retry-services))
              (should (equal p2s--retry-services '(ng)))
              (should (string= (buffer-string) "hello"))
              ;; Retry posts only to the failed service.
              (setq p2s-service-commands `((ok . ,p2s-test-ok-command)
                                           (ng . ,p2s-test-ok-command)))
              (cl-letf* ((orig (symbol-function 'p2s-post-text-to-all-services))
                         ((symbol-function 'p2s-post-text-to-all-services)
                          (lambda (&rest args)
                            (setq posted p2s-services)
                            (apply orig args))))
                (p2s-post-mode-finish))
              (should (equal posted '(ng)))
              (p2s-test-wait-for (lambda () (= (buffer-size) 0)))
              (should-not p2s--retry-services)))
        (kill-buffer buf)))))

(ert-deftest p2s-test-compose-keeps-edits-made-while-posting ()
  "Test that text edited after sending is not cleared on success."
  (p2s-test-with-services `((ok . ,p2s-test-ok-command))
    (let* ((buf (generate-new-buffer "*p2s-test-compose*"))
           (done nil)
           (orig (symbol-function 'p2s--compose-post-done)))
      (unwind-protect
          (with-current-buffer buf
            (p2s-post-mode)
            (insert "hello")
            (cl-letf (((symbol-function 'quit-window) #'ignore)
                      ((symbol-function 'p2s--compose-post-done)
                       (lambda (&rest args)
                         (apply orig args)
                         (setq done t))))
              (p2s-post-mode-finish)
              (insert " next")
              (p2s-test-wait-for (lambda () done)))
            (should (string= (buffer-string) "hello next")))
        (kill-buffer buf)))))

(ert-deftest p2s-test-lazy-load ()
  "Test that IDs are loaded from the current `p2s-save-file' on first use."
  (let* ((temp-file (make-temp-file "p2s-test-ids"))
         (p2s-save-file temp-file)
         (p2s--loaded-save-file nil)
         (p2s-last-post-ids nil))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (prin1 '((bsky . "at://saved")) (current-buffer)))
          (p2s--ensure-last-post-ids-loaded)
          (should (equal p2s-last-post-ids '((bsky . "at://saved"))))
          ;; Not reloaded once loaded, so new IDs in memory are kept.
          (setq p2s-last-post-ids '((bsky . "at://new")))
          (p2s--ensure-last-post-ids-loaded)
          (should (equal p2s-last-post-ids '((bsky . "at://new")))))
      (delete-file temp-file))))

(ert-deftest p2s-test-services-unable-to-reply ()
  "Test detection of services that cannot reply."
  (let ((p2s-service-reply-flags '((bsky . "-r") (toot . "--reply-last")))
        (p2s-last-post-ids nil))
    (should (equal (p2s--services-unable-to-reply '(bsky toot other))
                   '(bsky other)))
    (setq p2s-last-post-ids '((bsky . "at://x")))
    (should (equal (p2s--services-unable-to-reply '(bsky toot other))
                   '(other)))))

(ert-deftest p2s-test-reply-without-id-is-rejected ()
  "Test that a reply is not posted when a service has no ID to reply to."
  (p2s-test-with-services `((bsky . ,p2s-test-ok-command)
                            (toot . ,p2s-test-ok-command))
    (let ((p2s-service-reply-flags '((bsky . "-r") (toot . "--reply-last")))
          (started nil))
      (cl-letf (((symbol-function 'start-process)
                 (lambda (&rest _) (setq started t) nil)))
        (should-error (p2s-post-text-to-all-services "#+REPLY: t\nhello")
                      :type 'user-error)
        (should-error (p2s-compose-reply) :type 'user-error))
      (should-not started))))

(ert-deftest p2s-test-count-graphemes ()
  "Test grapheme counting."
  (should (= (p2s-count-graphemes "hello") 5))
  (should (= (p2s-count-graphemes "日本語") 3))
  ;; e + combining acute accent
  (should (= (p2s-count-graphemes "é") 1))
  ;; Thumbs up + skin tone
  (should (= (p2s-count-graphemes "\U0001F44D\U0001F3FD") 1))
  ;; Family: man ZWJ woman ZWJ girl
  (should (= (p2s-count-graphemes "\U0001F468‍\U0001F469‍\U0001F467") 1))
  ;; Heart + variation selector
  (should (= (p2s-count-graphemes "❤️") 1))
  ;; Two flags (JP, US)
  (should (= (p2s-count-graphemes "\U0001F1EF\U0001F1F5\U0001F1FA\U0001F1F8") 2)))

(ert-deftest p2s-test-count-mastodon-length ()
  "Test Mastodon length counting."
  (should (= (p2s-count-mastodon-length "hi") 2))
  ;; A URL counts as 23 characters
  (should (= (p2s-count-mastodon-length
              "see https://example.com/a/very/long/path/that/goes/on")
             (+ 4 23)))
  ;; A remote mention counts only the @user part
  (should (= (p2s-count-mastodon-length "@alice@mastodon.example hi")
             (length "@alice hi"))))

(ert-deftest p2s-test-check-length ()
  "Test per-service length checks."
  (let ((p2s-service-max-lengths '((bsky . 300) (toot . 500)))
        (p2s-service-length-functions '((bsky . p2s-count-graphemes)
                                        (toot . p2s-count-mastodon-length)))
        (p2s-max-length 10)
        (text (make-string 400 ?a)))
    (should (p2s-check-length text '(toot)))
    (should-error (p2s-check-length text '(bsky toot)) :type 'user-error)
    ;; Services not in the alist use `p2s-max-length'
    (should-error (p2s-check-length "hello world" '(other)) :type 'user-error)
    ;; A long URL fits Mastodon's limit
    (should (p2s-check-length
             (concat (make-string 470 ?a) " https://example.com/"
                     (make-string 100 ?b))
             '(toot)))))

(provide 'p2s-test)
