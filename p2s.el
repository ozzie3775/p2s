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
(require 'dnd)

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

(defcustom p2s-service-image-flags
  '((bsky . "--image")
    (toot . "--media"))
  "Flags for attaching images for each service."
  :type '(alist :key-type symbol :value-type string)
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

(defun p2s--log-post (text &optional images)
  "Log TEXT and IMAGES using `org-capture' if `p2s-org-capture-key' is set."
  (when (and p2s-org-capture-key (fboundp 'org-capture))
    (with-temp-buffer
      (insert (string-trim text))
      (when images
        (insert "\n\nFiles:\n")
        (dolist (img images)
          (insert (format "- %s\n" img))))
      (set-mark (point-min))
      (goto-char (point-max))
      (activate-mark)
      (condition-case err
          (org-capture nil p2s-org-capture-key)
        (error (message "p2s: Org-capture failed: %s" (error-message-string err)))))))

(defun p2s--extract-images (text)
  "Extract image paths from TEXT and return (clean-text . images)."
  (let (images clean-lines)
    (dolist (line (split-string text "\n"))
      (if (string-match "^#\\+IMAGE:[\s\t]*\\(.+\\)$" line)
          (push (string-trim (match-string 1 line)) images)
        (push line clean-lines)))
    (cons (string-trim (mapconcat #'identity (nreverse clean-lines) "\n"))
          (nreverse images))))

;;;###autoload
(defun p2s-post-text-to-all-services (text &optional images)
  "Post TEXT to all services defined in `p2s-services'.
Optional IMAGES is a list of file paths to attach.
If TEXT contains #+IMAGE: lines, they are extracted and added to IMAGES."
  (let* ((extracted (p2s--extract-images text))
         (clean-text (car extracted))
         (all-images (append images (cdr extracted)))
         (success-count 0)
         (total-services (length p2s-services)))

    (when (string-blank-p clean-text)
      (user-error "Content is empty, nothing to post"))

    (p2s-check-length clean-text)
    (p2s--log-post clean-text all-images)

    (dolist (service p2s-services)
      (let* ((base-command (cdr (assq service p2s-service-commands)))
             (img-flag (cdr (assq service p2s-service-image-flags)))
             (img-args (when (and all-images img-flag)
                         (cl-loop for img in all-images
                                  append (list img-flag img))))
             (command (append base-command img-args))
             (process-connection-type nil)
             (proc-name (format "p2s-%s-process" service))
             (buffer-name (format " *p2s-%s-output*" service)))

        (if (not base-command)
            (message "p2s: Unknown service: %s" service)
          (let ((proc (apply #'start-process proc-name buffer-name command)))
            (process-send-string proc clean-text)
            (process-send-eof proc)
            (set-process-sentinel
             proc
             (lambda (process event)
               (let ((svc service)) ; capture service name
                 (cond
                  ((and (string-match-p "finished" event)
                        (zerop (process-exit-status process)))
                   (cl-incf success-count)
                   (message "p2s: [%s] Posted successfully (%d/%d)"
                            svc success-count total-services)
                   (when (= success-count total-services)
                     (message "p2s: Successfully posted to all %d services" total-services)))
                  ((string-match-p "finished\\|exited\\|error" event)
                   (message "p2s: [%s] Failed: %s (Status: %d)"
                            svc (string-trim event) (process-exit-status process)))))))))))
  (message "p2s: Sending post to %d services..." (length p2s-services)))

;;;###autoload
(defun p2s-post-region-to-all-services (begin end)
  "Post the current region to all services."
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
  (let* ((text (buffer-substring-no-properties (point-min) (point-max)))
         (extracted (p2s--extract-images text))
         (clean-text (car extracted))
         (len (length clean-text))
         (limit p2s-max-length)
         (color (if (> len limit) "red" "green")))
    (setq header-line-format
          (list
           (substitute-command-keys
            "Edit post (C-c C-c: Post, C-c C-k: Cancel) | ")
           (propertize (format "Length: %d/%d" len limit)
                       'face `(:foreground ,color :weight bold))))))

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
         (success nil))
    (cond
     ((executable-find "pngpaste")
      (setq success (zerop (call-process "pngpaste" nil nil nil file))))
     ((executable-find "xclip")
      (setq success (zerop (call-process "xclip" nil nil nil "-selection" "clipboard" "-t" "image/png" "-o" file))))
     (t (message "p2s: No clipboard image tool found (install pngpaste or xclip)")))
    (if success
        (p2s-attach-image file)
      (when (executable-find "pngpaste")
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
