(defun ledger-get-xact-date ()
  "Read the effective date (before =) of a transaction. Returns the date as a time value."
  (save-excursion
    (ledger-navigate-beginning-of-xact)
    (re-search-forward ledger-iso-date-regexp)
    (encode-time 0 0 0 (string-to-number (match-string 4))
                 (string-to-number (match-string 3))
                 (string-to-number (match-string 2)))))


(defun ledger-line-replace (command-script &optional arg)
  "Return shell command output using date from ledger transaction.
COMMAND-SCRIPT is the shell script to execute with the transaction date."
  (save-excursion
    (message command-script)
    (beginning-of-defun)
    (let* ((date (buffer-substring-no-properties
                  (point)
                  (save-excursion
                    (re-search-forward "[ \t]" (line-end-position) t)
                    (or (match-beginning 0) (line-end-position)))))
           (command (if arg
                        (format "./%s %s %s" command-script date arg)
                      (format "./%s %s" command-script date)))
           (command-output (shell-command-to-string command)))
      (message command-output)
      )))

(defun ledger-mort-replace (&optional arg)
  "Replace current line with mortgage transaction for Greenbury or Meadowview."
  (interactive "P")
  (let* ((line (buffer-substring-no-properties (line-beginning-position) (line-end-position)))
         (script-map '((":Meadowview" . "mv_mort.sh")
                       (":Greenbury" . "gb_mort.sh")
                       (":Chappelle" . "gb_mort.sh")
                       ("Garneau" . "gg_mort.sh")))
         (matching-script (cl-find-if (lambda (pair) (string-match (car pair) line)) script-map)))
    (if matching-script
        (progn
          (delete-region (line-beginning-position) (line-end-position))
          (insert (ledger-line-replace (cdr matching-script) arg))
          (delete-char 1))
      (message "No valid property (Greenbury Meadowview or Garneau) found in current line")))
  (ledger-post-align-dwim))

(defun ledger-fix-garneau-mortgage-transactions ()
  "Fix mortgage transactions by calling ledger-mort-replace with property suffixes."
  (interactive)
  (save-excursion
    (dotimes (i 3)
      (ledger-navigate-end-of-xact)
      (beginning-of-line)
      (ledger-mort-replace (format "%d" (+ 142 (* 2 i))))
      (ledger-navigate-next-xact))
    ))


(defun ledger-epcor-insert ()
  (interactive)
  (let* ((transaction (ledger-line-replace "epcor_pdf_parse.py")))
    (beginning-of-line)
    (delete-region (line-beginning-position) (line-end-position))
    (insert transaction)
    (ledger-post-align-dwim)))

(defun ledger-add-eff-date ()
  "Add the effective date as the first of the next month to end of the line of cursor, with the string format ;[=YYYY/MM/DD]"
  (interactive)
  (let ((current-date (current-time))
        (next-month-date (time-add (current-time) (days-to-time 30))))
    (save-excursion
      (end-of-line)
      (insert (format-time-string " ;[=%Y/%m/01]" next-month-date))))
  )

(add-hook 'ledger-mode-hook
          (lambda ()
            (setq-local tab-always-indent 'complete)
            (setq-local completion-cycle-threshold t)
            (setq-local ledger-complete-in-steps t)
            ;; Set ledger-accounts-file
            (when (buffer-file-name)
              (let* ((base-name (file-name-sans-extension (buffer-file-name)))
                     (accounts-file (concat base-name ".accounts")))
                (setq-local ledger-accounts-file accounts-file)))

            (define-key ledger-mode-map (kbd "S-<up>") nil)
            (define-key ledger-mode-map (kbd "S-<down>") nil)
            (define-key ledger-mode-map (kbd "C-c a") #'ledger-post-align-dwim)
            (define-key ledger-mode-map (kbd "C-c C-v") #'ledger-add-eff-date)
            (define-key ledger-mode-map (kbd "C-c m") #'ledger-mort-replace)
            (define-key ledger-mode-map (kbd "C-j") #'completion-at-point)
            ))


