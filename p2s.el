;; p2s.el --- Post to multiple SNS services simultaneously -*- lexical-binding: t -*-

;; Author: @ozzie3775
;; Version: 0.1
;; Keywords: convenience
;; Package-Requires: ((emacs "25.1") (cl-lib "0.5"))

;;; Commentary:
;; This package provides functions to post content to multiple social network
;; services simultaneously, such as Bluesky and Mastodon.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

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
    (toot . ("toot" "post")))
  "Commands for each service."
  :type '(alist :key-type symbol :value-type (repeat string))
  :group 'p2s)

(defcustom p2s-max-length 300
  "Maximum character length for a post."
  :type 'integer
  :group 'p2s)

(defcustom p2s-org-capture-key nil
  "Org-capture template key for logging posts (e.g., \"s\").
If nil (default), logging is disabled."
  :type '(choice (const :tag "Disable logging" nil)
                 (string :tag "Capture template key"))
  :group 'p2s)

(defun p2s-check-length (text)
  "Check if TEXT length is within `p2s-max-length'.
Throw `user-error' if the limit is exceeded."
  (let ((len (length text)))
    (if (> len p2s-max-length)
        (user-error "Post is too long (%d chars). Limit is %d"
                    len p2s-max-length)
      t)))

(defun p2s--log-post (text)
  "Log TEXT using `org-capture' if `p2s-org-capture-key' is set."
  (when (and p2s-org-capture-key (fboundp 'org-capture))
    (with-temp-buffer
      (insert (string-trim text))
      (set-mark (point-min))
      (goto-char (point-max))
      (activate-mark)
      (condition-case err
          (org-capture nil p2s-org-capture-key)
        (error (message "p2s: Org-capture failed: %s" (error-message-string err)))))))

;;;###autoload
(defun p2s-post-text-to-all-services (text)
  "Post TEXT to all services defined in `p2s-services'."
  (let ((success-count 0)
        (service-count (length p2s-services)))

    (p2s--log-post text)

    (dolist (service p2s-services)
      (let* ((command (cdr (assq service p2s-service-commands)))
             (process-connection-type nil)
             (proc-name (format "p2s-%s-process" service))
             (buffer-name (format " *p2s-%s-output*" service))) ; Hidden buffer

        (if (not command)
            (message "p2s: Unknown service: %s" service)
          (let ((proc (apply #'start-process proc-name buffer-name command)))
            (process-send-string proc text)
            (process-send-eof proc)
            (set-process-sentinel
             proc
             (lambda (process event)
               (when (string-match-p "finished" event)
                 (cl-incf success-count)
                 (message "p2s: Posted to %s (%d/%d)"
                          service success-count service-count)
                 (when (= success-count service-count)
                   (message "p2s: Successfully posted to all %d services" service-count))))))))))
  (message "p2s: Sending post to all services..."))

;;;###autoload
(defun p2s-post-region-to-all-services (begin end)
  "Post the current region to all services."
  (interactive "r")
  (let ((text (buffer-substring-no-properties begin end)))
    (if (string-blank-p text)
        (user-error "Region is empty, nothing to post")
      (when (p2s-check-length text)
        (p2s-post-text-to-all-services text)))))

;;;###autoload
(defun p2s-post-from-minibuffer-to-all ()
  "Read text from the minibuffer and post to all services."
  (interactive)
  (let ((text (read-string "Post: ")))
    (if (string-blank-p text)
        (message "p2s: Nothing to post")
      (when (p2s-check-length text)
        (p2s-post-text-to-all-services text)))))

(defvar p2s-post-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'p2s-post-mode-finish)
    (define-key map (kbd "C-c C-k") #'p2s-post-mode-cancel)
    map)
  "Keymap for `p2s-post-mode'.")

(define-derived-mode p2s-post-mode text-mode "p2s-post"
  "Major mode for composing a post to multiple SNS services.
\\{p2s-post-mode-map}"
  (setq-local header-line-format
              (substitute-command-keys
               "Edit post and press \\[p2s-post-mode-finish] to post, \\[p2s-post-mode-cancel] to cancel.")))

(defun p2s-post-mode-finish ()
  "Finish editing and post the content."
  (interactive)
  (let ((text (buffer-substring-no-properties (point-min) (point-max))))
    (if (string-blank-p text)
        (user-error "Content is empty, nothing to post")
      (when (p2s-check-length text)
        (p2s-post-text-to-all-services text)
        (set-buffer-modified-p nil)
        (quit-window t)))))

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
(defun p2s-setup-keybindings ()
  "Setup recommended keybindings for p2s."
  (interactive)
  (global-set-key (kbd "C-c p r") #'p2s-post-region-to-all-services)
  (global-set-key (kbd "C-c p m") #'p2s-post-from-minibuffer-to-all)
  (global-set-key (kbd "C-c p p") #'p2s-compose-post)
  (global-set-key (kbd "C-c p b") #'p2s-post-buffer-to-all-services)
  (global-set-key (kbd "C-c p c") #'p2s-configure-services)
  (message "p2s: Recommended keybindings are set up (C-c p ...)"))

(provide 'p2s)
;;; p2s.el ends here
