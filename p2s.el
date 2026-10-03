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
  "Maximum character length for a post."
  :type 'integer
  :group 'p2s)

(defun p2s-check-length (text)
  "Check if TEXT length is within `p2s-max-length'.
Throw `user-error' if the limit is exceeded."
  (let ((len (length text)))
    (if (> len p2s-max-length)
        (user-error "Post is too long (%d chars).  Limit is %d"
                    len p2s-max-length)
      t)))

(defcustom p2s-save-file (locate-user-emacs-file "p2s-last-post-ids")
  "File to save `p2s-last-post-ids' for persistence across sessions.
If nil, persistence is disabled."
  :type '(choice (const :tag "Disable persistence" nil)
                 file)
  :group 'p2s)

(defvar p2s-last-post-ids nil
  "Alist of the last post IDs for each service.
Example: ((bsky . \"at://did:...\") (toot . \"12345\"))")

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
  (when (and p2s-save-file (file-exists-p p2s-save-file))
    (condition-case err
        (with-temp-buffer
          (insert-file-contents p2s-save-file)
          (setq p2s-last-post-ids (read (current-buffer))))
      (error
       (message "p2s: Failed to load last post IDs: %s"
                (error-message-string err))))))

;; Load saved IDs immediately when the package is loaded
(p2s-load-last-post-ids)

(defun p2s-reset-last-post-ids ()
  "Reset the stored last post IDs for all services."
  (interactive)
  (setq p2s-last-post-ids nil)
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
       ;; Use JSON parsing if possible
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
           (and (string-match "\\`[^{]*{[^}]*?\"id\":[ \t]*\"?\\([0-9]+\\)\"?" trimmed-out)
                (match-string 1 trimmed-out))
           (and (string-match "\"id\":[ \t]*\"?\\([0-9]+\\)\"?" trimmed-out)
                (match-string 1 trimmed-out))
           (and (string-match "id:[ \t]*\\([0-9]+\\)" trimmed-out)
                (match-string 1 trimmed-out))
           (and (string-match "\\([0-9]\\{15,\\}\\)" trimmed-out)
                (match-string 1 trimmed-out))
           ;; Last resort: any sequence of digits if it's the only thing or at the end
           (and (string-match "\\([0-9]+\\)\\'" trimmed-out)
                (match-string 1 trimmed-out))
           (and (string-match "^\"?\\([0-9]+\\)\"?$" trimmed-out)
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
  (let ((buf (process-buffer process)))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (let ((output (buffer-string)))
          (cond
           ((and (string-match-p "finished" event)
                 (zerop (process-exit-status process)))
            (funcall success-callback service output))
           ((string-match-p "finished\\|exited\\|error" event)
            (funcall failure-callback service event output))))))))

;;;###autoload
(defun p2s-post-text-to-all-services (text &optional images)
  "Post TEXT to all services defined in `p2s-services'.
Optional IMAGES is a list of file paths to attach.
If TEXT contains #+IMAGE: lines, they are extracted and added to IMAGES.
If TEXT contains #+REPLY: t, it will reply to the last post if available."
  (pcase-let* ((`(,clean-text ,extracted-images ,is-reply) (p2s--parse-post-content text))
               (all-images (append images extracted-images))
               (success-count 0)
               (total-services (length p2s-services)))

    (when (string-blank-p clean-text)
      (user-error "Content is empty, nothing to post"))

    (p2s-check-length clean-text)

    (dolist (service p2s-services)
      (let* ((svc service)
             (command (p2s--build-command svc all-images is-reply))
             (process-connection-type nil)
             (proc-name (format "p2s-%s-process" svc))
             (buffer-name (format " *p2s-%s-output*" svc)))

        (if (not command)
            (message "p2s: Unknown or misconfigured service: %s" svc)
          (with-current-buffer (get-buffer-create buffer-name)
            (erase-buffer))
          (let ((proc (apply #'start-process proc-name buffer-name command)))
            (message "p2s: [%s] Executing: %s" svc (mapconcat #'identity command " "))
            (process-send-string proc clean-text)
            (process-send-eof proc)
            (set-process-sentinel
             proc
             (lambda (p e)
               (p2s--post-sentinel
                p e svc
                (lambda (s out)
                  (cl-incf success-count)
                  (let ((id (p2s--extract-id s out)))
                    (if id
                        (progn
                          (setq p2s-last-post-ids
                                (cons (cons s id)
                                      (cl-remove s p2s-last-post-ids :key #'car)))
                          (p2s-save-last-post-ids)
                          (message "p2s: [%s] Successfully extracted and stored ID: %s" s id))
                      (message "p2s: [%s] Warning: Could not extract post ID from output\nOutput: %s" s out)))
                  (message "p2s: [%s] Posted successfully (%d/%d)" s success-count total-services)
                  (when (= success-count total-services)
                    (message "p2s: Successfully posted to all %d services" total-services)))
                (lambda (s ev out)
                  (message "p2s: [%s] Failed: %s\nOutput: %s" s (string-trim ev) (string-trim out))))))))))
    (message "p2s: Sending post to %d services..." (length p2s-services))))

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

(defun p2s--update-header-line ()
  "Update the header line with character count."
  (let* ((text (buffer-substring-no-properties (point-min) (point-max))))
    (pcase-let ((`(,clean-text _ ,is-reply) (p2s--parse-post-content text)))
      (let* ((len (length clean-text))
             (limit p2s-max-length)
             (color (if (> len limit) "red" "green")))
        (setq header-line-format
              (list
               (substitute-command-keys
                "Edit post (C-c C-c: Post, C-c C-k: Cancel) | ")
               (propertize (format "Length: %d/%d" len limit)
                           'face `(:foreground ,color :weight bold))
               (when is-reply
                 (propertize " [REPLY MODE]" 'face '(:foreground "orange" :weight bold)))))))))

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

(defun p2s-post-mode-finish ()
  "Finish editing and post the content."
  (interactive)
  (let ((text (buffer-substring-no-properties (point-min) (point-max))))
    (p2s-post-text-to-all-services text)
    (set-buffer-modified-p nil)
    (quit-window t)))

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
        (set-buffer-modified-p nil)))
    (switch-to-buffer-other-window buf)))

;;;###autoload
(defun p2s-compose-reply ()
  "Open a buffer to compose a reply to the last post."
  (interactive)
  (unless p2s-last-post-ids
    (user-error "No previous post found to reply to"))
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
