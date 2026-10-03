;;; p2s.el --- Post to multiple SNS services simultaneously -*- lexical-binding: t -*-

;; Author: @ozzie3775
;; URL: https://github.com/ozzie3775/p2s
;; Version: 0.1
;; Keywords: convenience
;; Package-Requires: ((emacs "25.1"))

;;; Commentary:
;; This package provides functions to post content to multiple social network
;; services simultaneously, such as Bluesky and Mastodon.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'dnd)
(require 'crm)
(require 'json)

(defgroup p2s nil
  "Post to multiple SNS services simultaneously."
  :group 'communication
  :prefix "p2s-")

(defcustom p2s-services '(bsky toot)
  "List of social media services to post to."
  :type '(repeat symbol)
  :group 'p2s)

(defcustom p2s-service-commands
  '((bsky . ("bsky" "post" "--stdin"))
    (toot . ("toot" "post" "--json")))
  "Commands for each service."
  :type '(alist :key-type symbol :value-type (repeat string))
  :group 'p2s)

(defcustom p2s-service-image-flags
  '((bsky . "--image")
    (toot . "--media"))
  "Flags for attaching images for each service."
  :type '(alist :key-type symbol :value-type string)
  :group 'p2s)

(defcustom p2s-service-reply-flags
  '((bsky . "-r")
    (toot . "--reply-last"))
  "Flags for replying to a post for each service.
If the flag is \"--reply-last\", it will be used without an ID argument."
  :type '(alist :key-type symbol :value-type string)
  :group 'p2s)

(defcustom p2s-max-length 300
  "Maximum length of a post for services not in `p2s-service-max-lengths'."
  :type 'integer
  :group 'p2s)

(defcustom p2s-service-max-lengths
  '((bsky . 300)
    (toot . 500))
  "Maximum length of a post for each service.
Change the value for `toot' if your Mastodon instance has another limit."
  :type '(alist :key-type symbol :value-type integer)
  :group 'p2s)

(defcustom p2s-service-length-functions
  '((bsky . p2s-count-graphemes)
    (toot . p2s-count-mastodon-length))
  "Functions that count the length of a post for each service.
Services not listed here use `p2s-count-graphemes'."
  :type '(alist :key-type symbol :value-type function)
  :group 'p2s)

(defun p2s--grapheme-extend-p (char)
  "Return non-nil if CHAR is part of the preceding grapheme cluster."
  (or (memq (get-char-code-property char 'general-category) '(Mn Me))
      (<= #xFE00 char #xFE0F)           ; Variation selectors
      (<= #xE0100 char #xE01EF)         ; Variation selectors supplement
      (<= #x1F3FB char #x1F3FF)         ; Emoji skin tone modifiers
      (<= #xE0020 char #xE007F)))       ; Tags (subdivision flags)

(defun p2s-count-graphemes (text)
  "Return the approximate number of grapheme clusters in TEXT.
Combining marks, variation selectors, emoji modifiers, ZWJ sequences
and regional indicator pairs (flags) are counted as one character."
  (let ((count 0)
        (join-next nil)
        (pending-ri nil))
    (dolist (char (string-to-list text))
      (cond
       (join-next (setq join-next nil))
       ((= char #x200D) (setq join-next t)) ; Zero width joiner
       ((p2s--grapheme-extend-p char))
       ((<= #x1F1E6 char #x1F1FF)           ; Regional indicators
        (if pending-ri
            (setq pending-ri nil)
          (setq pending-ri t)
          (cl-incf count)))
       (t (cl-incf count)))
      (unless (<= #x1F1E6 char #x1F1FF)
        (setq pending-ri nil)))
    count))

(defconst p2s--mastodon-url-length 23
  "Length that Mastodon counts for every URL.")

(defun p2s-count-mastodon-length (text)
  "Return the length of TEXT as counted by Mastodon.
Each URL counts as `p2s--mastodon-url-length' characters, and a mention
of a remote account (@user@domain) counts only the @user part."
  (let ((url-placeholder (make-string p2s--mastodon-url-length ?x)))
    (p2s-count-graphemes
     (replace-regexp-in-string
      "@\\([[:alnum:]_]+\\)@[[:alnum:]-]+\\(?:\\.[[:alnum:]-]+\\)+" "@\\1"
      (replace-regexp-in-string "https?://[^ \t\n]+" url-placeholder text t t)
      t))))

(defun p2s--post-lengths (text services)
  "Return a list of (SERVICE LENGTH LIMIT) of TEXT for each of SERVICES."
  (mapcar (lambda (svc)
            (list svc
                  (funcall (or (cdr (assq svc p2s-service-length-functions))
                               #'p2s-count-graphemes)
                           text)
                  (or (cdr (assq svc p2s-service-max-lengths))
                      p2s-max-length)))
          services))

(defun p2s-check-length (text &optional services)
  "Check that TEXT fits the length limit of every service in SERVICES.
SERVICES defaults to `p2s-services'.
Throw `user-error' if any limit is exceeded."
  (let ((over (cl-remove-if-not
               (lambda (entry) (> (nth 1 entry) (nth 2 entry)))
               (p2s--post-lengths text (or services p2s-services)))))
    (when over
      (user-error "Post is too long: %s"
                  (mapconcat (lambda (entry)
                               (apply #'format "%s %d/%d" entry))
                             over ", ")))
    t))

(defcustom p2s-save-file (locate-user-emacs-file "p2s-last-post-ids")
  "File to save `p2s-last-post-ids' for persistence across sessions.
If nil, persistence is disabled."
  :type '(choice (const :tag "Disable persistence" nil)
                 file)
  :group 'p2s)

(defvar p2s-last-post-ids nil
  "Alist of the last post IDs for each service.
Example: ((bsky . \"at://did:...\") (toot . \"12345\"))")

(defvar p2s--loaded-save-file nil
  "The value of `p2s-save-file' that `p2s-last-post-ids' was loaded from.")

(defun p2s-save-last-post-ids ()
  "Save `p2s-last-post-ids' to `p2s-save-file'."
  (when p2s-save-file
    (condition-case err
        (let ((dir (file-name-directory p2s-save-file)))
          (when dir
            (make-directory dir t))
          (with-temp-file p2s-save-file
            (let ((print-length nil)
                  (print-level nil))
              (insert ";; -*- lisp-data -*-\n")
              (prin1 p2s-last-post-ids (current-buffer)))))
      (error
       (message "p2s: Failed to save last post IDs: %s"
                (error-message-string err))))))

(defun p2s-load-last-post-ids ()
  "Load `p2s-last-post-ids' from `p2s-save-file'."
  (interactive)
  (setq p2s--loaded-save-file p2s-save-file)
  (when (and p2s-save-file (file-exists-p p2s-save-file))
    (condition-case err
        (with-temp-buffer
          (insert-file-contents p2s-save-file)
          (setq p2s-last-post-ids (read (current-buffer))))
      (error
       (message "p2s: Failed to load last post IDs: %s"
                (error-message-string err))))))

(defun p2s--ensure-last-post-ids-loaded ()
  "Load `p2s-last-post-ids' unless it is already loaded from `p2s-save-file'.
Loading lazily lets users set `p2s-save-file' after `require'."
  (when (and p2s-save-file
             (not (equal p2s-save-file p2s--loaded-save-file)))
    (p2s-load-last-post-ids)))

(defun p2s-reset-last-post-ids ()
  "Reset the stored last post IDs for all services."
  (interactive)
  (setq p2s-last-post-ids nil)
  (setq p2s--loaded-save-file p2s-save-file)
  (p2s-save-last-post-ids)
  (message "p2s: Last post IDs have been reset."))

(defun p2s--extract-id (service output)
  "Extract post ID for SERVICE from command OUTPUT."
  (let ((case-fold-search t)
        (trimmed-out (string-trim output)))
    (pcase service
      ('bsky
       ;; Bluesky needs at:// URI.
       (or (and (string-match "\"uri\":[ \t]*\"\\(at://[^ \t\n\r\"]+\\)\"" trimmed-out)
                (match-string 1 trimmed-out))
           (and (string-match "uri:[ \t]*\\(at://[^ \t\n\r]+\\)" trimmed-out)
                (match-string 1 trimmed-out))
           (and (string-match "\\(at://[^ \t\n\r\"]+\\)" trimmed-out)
                (match-string 1 trimmed-out))))
      ('toot
       ;; `toot post --json' prints the status as JSON.  Read the
       ;; top-level "id", since the output also contains the account ID.
       (or (condition-case nil
               (let ((json-object-type 'alist)
                     (start (string-match "{" trimmed-out)))
                 (when start
                   (let* ((data (json-read-from-string (substring trimmed-out start)))
                          (id (cdr (assoc 'id data))))
                     (cond
                      ((numberp id) (number-to-string id))
                      ((stringp id) id)))))
             (error nil))
           ;; Without --json, toot prints the URL of the status.
           (and (string-match "https?://[^ \t\n]+/\\([0-9]+\\)\\b" trimmed-out)
                (match-string 1 trimmed-out)))))))

(defun p2s--parse-post-content (text)
  "Extract metadata and image paths from TEXT.
Returns (clean-text images is-reply)."
  (let (images clean-lines is-reply)
    (dolist (line (split-string text "\n"))
      (cond
       ((string-match "^[ \t]*#\\+IMAGE\\(?::[ \t]*\\(.*?\\)\\)?[ \t]*$" line)
        (let ((path (match-string 1 line)))
          (when (and path (not (string-empty-p (string-trim path))))
            (push (string-trim path) images))))
       ((string-match "^[ \t]*#\\+REPLY:[ \t]*t" line)
        (setq is-reply t))
       (t (push line clean-lines))))
    (list (string-trim (mapconcat #'identity (nreverse clean-lines) "\n"))
          (nreverse images)
          is-reply)))

(defun p2s--services-unable-to-reply (services)
  "Return the members of SERVICES that cannot reply to the last post.
A service cannot reply if it has no reply flag, or if its flag needs
a post ID and no ID is stored in `p2s-last-post-ids'."
  (cl-remove-if
   (lambda (svc)
     (let ((reply-flag (cdr (assq svc p2s-service-reply-flags))))
       (and reply-flag
            (or (string= reply-flag "--reply-last")
                (cdr (assq svc p2s-last-post-ids))))))
   services))

(defun p2s--build-command (svc images is-reply)
  "Build the command list for SVC.
IMAGES is a list of image paths.
IS-REPLY is a boolean indicating if it's a reply."
  (let* ((base-command (cdr (assq svc p2s-service-commands)))
         (img-flag (cdr (assq svc p2s-service-image-flags)))
         (reply-flag (cdr (assq svc p2s-service-reply-flags)))
         (last-id (cdr (assq svc p2s-last-post-ids)))
         (img-args (when (and images img-flag)
                     (cl-loop for img in images
                              append (list img-flag img))))
         (reply-args (when (and is-reply reply-flag)
                       (if (string= reply-flag "--reply-last")
                           (progn
                             (message "p2s: [%s] Replying using --reply-last" svc)
                             (list reply-flag))
                         (when last-id
                           (message "p2s: [%s] Replying to: %s" svc last-id)
                           (list reply-flag last-id))))))
    (when base-command
      (append base-command img-args reply-args))))

(defun p2s--post-sentinel (process event service success-callback failure-callback)
  "Sentinel for p2s processes.
PROCESS is the process, EVENT is the event string.
SERVICE is the symbol of the service.
SUCCESS-CALLBACK is called with (service output) on success.
FAILURE-CALLBACK is called with (service event output) on failure."
  (let* ((buf (process-buffer process))
         (output (if (buffer-live-p buf)
                     (with-current-buffer buf (buffer-string))
                   "")))
    (pcase (process-status process)
      ('exit
       (if (zerop (process-exit-status process))
           (funcall success-callback service output)
         (funcall failure-callback service event output)))
      ('signal
       (funcall failure-callback service event output)))))

;;;###autoload
(defun p2s-post-text-to-all-services (text &optional images on-done)
  "Post TEXT to all services defined in `p2s-services'.
Optional IMAGES is a list of file paths to attach.
If TEXT contains #+IMAGE: lines, they are extracted and added to IMAGES.
If TEXT contains #+REPLY: t, it will reply to the last post if available.
Optional ON-DONE is called with (SUCCEEDED FAILED) after every service
has finished, where both are lists of service symbols."
  (pcase-let* ((`(,clean-text ,extracted-images ,is-reply) (p2s--parse-post-content text))
               (all-images (append images extracted-images))
               (services p2s-services)
               (total-services (length services))
               (succeeded nil)
               (failed nil))

    (when (string-blank-p clean-text)
      (user-error "Content is empty, nothing to post"))

    (p2s-check-length clean-text services)

    (p2s--ensure-last-post-ids-loaded)
    (when is-reply
      (let ((unable (p2s--services-unable-to-reply services)))
        (when unable
          (user-error "No previous post to reply to for %s; remove #+REPLY: t to post normally"
                      (mapconcat #'symbol-name unable ", ")))))

    (cl-flet ((finish (svc ok)
                (if ok (push svc succeeded) (push svc failed))
                (when (and on-done
                           (= (+ (length succeeded) (length failed)) total-services))
                  (funcall on-done
                           (cl-remove-if-not (lambda (s) (memq s succeeded)) services)
                           (cl-remove-if-not (lambda (s) (memq s failed)) services)))))
      (message "p2s: Sending post to %d services..." total-services)
      (dolist (service services)
        (let* ((svc service)
               (command (p2s--build-command svc all-images is-reply))
               (process-connection-type nil)
               (proc-name (format "p2s-%s-process" svc))
               (buffer-name (format " *p2s-%s-output*" svc)))

          (if (not command)
              (progn
                (message "p2s: Unknown or misconfigured service: %s" svc)
                (finish svc nil))
            (with-current-buffer (get-buffer-create buffer-name)
              (erase-buffer))
            (message "p2s: [%s] Executing: %s" svc (mapconcat #'identity command " "))
            (let ((proc (condition-case err
                            (apply #'start-process proc-name buffer-name command)
                          (error
                           (message "p2s: [%s] Failed to start: %s" svc (error-message-string err))
                           (finish svc nil)
                           nil))))
              (when proc
                (set-process-sentinel
                 proc
                 (lambda (p e)
                   (p2s--post-sentinel
                    p e svc
                    (lambda (s out)
                      (let ((id (p2s--extract-id s out)))
                        (if id
                            (progn
                              (setq p2s-last-post-ids
                                    (cons (cons s id)
                                          (cl-remove s p2s-last-post-ids :key #'car)))
                              (p2s-save-last-post-ids)
                              (message "p2s: [%s] Successfully extracted and stored ID: %s" s id))
                          (message "p2s: [%s] Warning: Could not extract post ID from output\nOutput: %s" s out)))
                      (message "p2s: [%s] Posted successfully (%d/%d)"
                               s (1+ (length succeeded)) total-services)
                      (when (= (1+ (length succeeded)) total-services)
                        (message "p2s: Successfully posted to all %d services" total-services))
                      (finish s t))
                    (lambda (s ev out)
                      (message "p2s: [%s] Failed: %s\nOutput: %s" s (string-trim ev) (string-trim out))
                      (finish s nil)))))
                ;; If the process dies early, sending fails; the sentinel
                ;; reports that failure, so it is not handled here.
                (ignore-errors
                  (process-send-string proc clean-text)
                  (process-send-eof proc))))))))))

;;;###autoload
(defun p2s-post-region-to-all-services (begin end)
  "Post the current region between BEGIN and END to all services."
  (interactive "r")
  (let ((text (buffer-substring-no-properties begin end)))
    (if (string-blank-p text)
        (user-error "Region is empty, nothing to post")
      (p2s-post-text-to-all-services text))))

;;;###autoload
(defun p2s-post-from-minibuffer-to-all ()
  "Read text from the minibuffer and post to all services."
  (interactive)
  (let ((text (read-string "Post: ")))
    (if (string-blank-p text)
        (message "p2s: Nothing to post")
      (p2s-post-text-to-all-services text))))

(defvar p2s-post-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'p2s-post-mode-finish)
    (define-key map (kbd "C-c C-k") #'p2s-post-mode-cancel)
    (define-key map (kbd "C-c C-a") #'p2s-attach-image)
    (define-key map (kbd "C-c C-y") #'p2s-attach-clipboard-image)
    map)
  "Keymap for `p2s-post-mode'.")

(defun p2s-dnd-func (url _action)
  "Handle drag and drop of a file URL in `p2s-post-mode'."
  (let ((file (dnd-get-local-file-name url)))
    (when (and file (file-exists-p file))
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))
      (insert (format "#+IMAGE: %s\n" (expand-file-name file))))))

(defvar-local p2s--retry-services nil
  "Services that failed on the last post from this compose buffer.
When non-nil, `p2s-post-mode-finish' posts only to these services.")

(defun p2s--update-header-line ()
  "Update the header line with character count."
  (let* ((text (buffer-substring-no-properties (point-min) (point-max))))
    (pcase-let ((`(,clean-text _ ,is-reply) (p2s--parse-post-content text)))
      (let ((lengths (p2s--post-lengths
                      clean-text (or p2s--retry-services p2s-services))))
        (setq header-line-format
              (list
               (substitute-command-keys
                "Edit post (C-c C-c: Post, C-c C-k: Cancel) |")
               (mapconcat
                (pcase-lambda (`(,svc ,len ,limit))
                  (propertize (format " %s %d/%d" svc len limit)
                              'face `(:foreground ,(if (> len limit) "red" "green")
                                                  :weight bold)))
                lengths "")
               (when is-reply
                 (propertize " [REPLY MODE]" 'face '(:foreground "orange" :weight bold)))
               (when p2s--retry-services
                 (propertize (format " [RETRY: %s]"
                                     (mapconcat #'symbol-name p2s--retry-services ", "))
                             'face '(:foreground "red" :weight bold)))))))))

(define-derived-mode p2s-post-mode text-mode "p2s-post"
  "Major mode for composing a post to multiple SNS services.
\\{p2s-post-mode-map}"
  (setq-local dnd-protocol-alist '(("^file:///" . p2s-dnd-func)
                                   ("^file:" . p2s-dnd-func)))
  (add-hook 'post-command-hook #'p2s--update-header-line nil t)
  (p2s--update-header-line))


(defun p2s-attach-image (file)
  "Attach an image FILE to the current post."
  (interactive "fImage file: ")
  (save-excursion
    (goto-char (point-max))
    (unless (bolp) (insert "\n"))
    (insert (format "#+IMAGE: %s\n" (expand-file-name file)))))

(defun p2s-attach-clipboard-image ()
  "Save image from clipboard and attach it."
  (interactive)
  (let* ((dir (expand-file-name "p2s-images" temporary-file-directory))
         (_ (make-directory dir t))
         (filename (format-time-string "p2s-%Y%m%d-%H%M%S.png"))
         (file (expand-file-name filename dir))
         (tool (cond ((executable-find "pngpaste") 'pngpaste)
                     ((executable-find "xclip") 'xclip)))
         (success nil))
    (pcase tool
      ('pngpaste
       (setq success (zerop (call-process "pngpaste" nil nil nil file))))
      ('xclip
       (setq success
             (zerop (call-process "xclip" nil nil nil
                                  "-selection" "clipboard"
                                  "-t" "image/png" "-o" file))))
      (_ (message "p2s: No clipboard image tool found (install pngpaste or xclip)")))

    (if success
        (p2s-attach-image file)
      (when tool
        (message "p2s: No image in clipboard")))))

(defun p2s--compose-post-done (buf tick succeeded failed)
  "Handle the result of a post sent from the compose buffer BUF.
TICK is the value of `buffer-chars-modified-tick' when the post was sent.
SUCCEEDED and FAILED are lists of service symbols.
On success, clear BUF unless it was edited after sending.
On failure, keep the text and show BUF so the failed services can be retried."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (if failed
          (progn
            (setq p2s--retry-services failed)
            (p2s--update-header-line)
            (pop-to-buffer buf)
            (message "p2s: Failed to post to %s%s.  Press C-c C-c to retry them"
                     (mapconcat #'symbol-name failed ", ")
                     (if succeeded
                         (format " (posted to %s)"
                                 (mapconcat #'symbol-name succeeded ", "))
                       "")))
        (setq p2s--retry-services nil)
        (when (= tick (buffer-chars-modified-tick))
          (erase-buffer)
          (set-buffer-modified-p nil))))))

(defun p2s-post-mode-finish ()
  "Post the content and hide the compose buffer.
The buffer is kept until every service has finished.  If any service
fails, the buffer is shown again and the next \\[p2s-post-mode-finish]
posts only to the failed services."
  (interactive)
  (let ((buf (current-buffer))
        (text (buffer-substring-no-properties (point-min) (point-max)))
        (tick (buffer-chars-modified-tick)))
    (let ((p2s-services (or p2s--retry-services p2s-services)))
      (p2s-post-text-to-all-services
       text nil
       (lambda (succeeded failed)
         (p2s--compose-post-done buf tick succeeded failed))))
    (quit-window)))

(defun p2s-post-mode-cancel ()
  "Cancel editing and discard the buffer."
  (interactive)
  (when (or (not (buffer-modified-p))
            (yes-or-no-p "Discard post? "))
    (set-buffer-modified-p nil)
    (quit-window t)
    (message "p2s: Post cancelled.")))

;;;###autoload
(defun p2s-compose-post ()
  "Open a buffer to compose a post to all services."
  (interactive)
  (let ((buf (get-buffer-create "*p2s-compose*")))
    (with-current-buffer buf
      (unless (derived-mode-p 'p2s-post-mode)
        (p2s-post-mode))
      (when (and (> (buffer-size) 0)
                 (yes-or-no-p "Clear existing content in *p2s-compose*? "))
        (erase-buffer)
        (setq p2s--retry-services nil)
        (set-buffer-modified-p nil)))
    (switch-to-buffer-other-window buf)))

;;;###autoload
(defun p2s-compose-reply ()
  "Open a buffer to compose a reply to the last post."
  (interactive)
  (p2s--ensure-last-post-ids-loaded)
  (let ((unable (p2s--services-unable-to-reply p2s-services)))
    (when unable
      (user-error "No previous post to reply to for %s"
                  (mapconcat #'symbol-name unable ", "))))
  (p2s-compose-post)
  (with-current-buffer (get-buffer "*p2s-compose*")
    (goto-char (point-min))
    (insert "#+REPLY: t\n")))

(defun p2s-configure-services ()
  "Set the social media services you want to post to."
  (interactive)
  (let* ((available (mapcar #'car p2s-service-commands))
         (initial (mapconcat #'symbol-name p2s-services ","))
         (chosen (completing-read-multiple
                  "Select services (comma separated): "
                  (mapcar #'symbol-name available) nil t initial)))
    (setq p2s-services (mapcar #'intern chosen))
    (message "p2s: Services updated to: %s" p2s-services)))

;;;###autoload
(defun p2s-post-buffer-to-all-services ()
  "Post the contents of current buffer to all services."
  (interactive)
  (p2s-post-region-to-all-services (point-min) (point-max)))

;;;###autoload
(defun p2s-post-below-point-to-all-services ()
  "Post contents from the next line to the end of buffer."
  (interactive)
  (let ((start (save-excursion
                 (forward-line 1)
                 (line-beginning-position))))
    (p2s-post-region-to-all-services start (point-max))))

;;;###autoload
(defvar p2s-prefix-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "r") #'p2s-post-region-to-all-services)
    (define-key map (kbd "m") #'p2s-post-from-minibuffer-to-all)
    (define-key map (kbd "p") #'p2s-compose-post)
    (define-key map (kbd "R") #'p2s-compose-reply)
    (define-key map (kbd "b") #'p2s-post-buffer-to-all-services)
    (define-key map (kbd "c") #'p2s-configure-services)
    (define-key map (kbd "C") #'p2s-reset-last-post-ids)
    map)
  "Prefix keymap for p2s commands.")

;;;###autoload
(defun p2s-setup-keybindings (&optional prefix)
  "Bind `p2s-prefix-map' globally to PREFIX.
PREFIX is a key description string for `kbd' and defaults to \"C-c p\"."
  (interactive)
  (let ((key (or prefix "C-c p")))
    (global-set-key (kbd key) p2s-prefix-map)
    (message "p2s: Keybindings are set up (%s ...)" key)))

(provide 'p2s)
;;; p2s.el ends here
