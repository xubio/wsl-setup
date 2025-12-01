;;################################################
(gptel-make-tool
 :function (lambda (buffer)
             (with-temp-message (format "Reading buffer: %s" buffer)
               (condition-case err
                   (if (buffer-live-p (get-buffer buffer))
                       (with-current-buffer buffer
                         (buffer-substring-no-properties (point-min) (point-max)))
                     (format "Error: buffer %s is not live." buffer))
                 (error (format "Error reading buffer %s: %s" 
                                buffer (error-message-string err))))))
 :name "read_buffer"
 :description "Return the contents of an Emacs buffer"
 :args (list '(:name "buffer"
                     :type string
                     :description "The name of the buffer whose contents are to be retrieved"))
 :category "emacs"
 :include t)

;;################################################
;; Replace buffer contents
(gptel-make-tool
 :function (lambda (buffer_name content)
             (with-temp-message (format "Replacing buffer contents: `%s`" buffer_name)
               (if (get-buffer buffer_name)
                   (with-current-buffer buffer_name
                     (erase-buffer)
                     (insert content)
                     (format "Buffer contents replaced: %s" buffer_name))
                 (format "Error: Buffer '%s' not found" buffer_name))))
 :name "replace_buffer"
 :description "Completely overwrites buffer contents with the provided content."
 :args (list
        '(:name "buffer_name"
                :type string
                :description "The name of the buffer whose contents will be replaced.")
        '(:name "content"
                :type string
                :description "The new content to write to the buffer, replacing all existing content."))
 :category "emacs"
 :include t)

;;################################################
;; interactive buffer editing
(defun munen-gptel--edit-buffer-interactive (orig-buffer buf-edits)
  "Edit ORIG-BUFFER by applying BUF-EDITS with interactive review using ediff.

This function applies the specified edits to the buffer and then opens an ediff
session to review changes before saving. Each edit in BUF-EDITS should specify:
- :line_number - The 1-based line number where the edit occurs  
- :old_string - The exact string to find and replace
- :new_string - The replacement string

EDITING RULES:
- The old_string must EXACTLY MATCH the existing buffer content at the specified line
- Include enough context in old_string to uniquely identify the location
- Keep edits concise and focused on the specific change requested
- Do not include long runs of unchanged lines

After applying edits, opens ediff to compare original vs modified versions,
allowing user to review and selectively apply changes before saving.
Returns a success/failure message indicating whether edits were applied."
  (if (and orig-buffer (not (string= orig-buffer "")) buf-edits)
      (let ((buffer-name (format "*edit-buf-%s-%d*" (format-time-string "%Y%m%d-%H%M%S") (random 10000))))
        (with-current-buffer (get-buffer-create buffer-name)
        (erase-buffer)
        (when-let ((source-buffer (get-buffer orig-buffer)))
          (insert (with-current-buffer source-buffer
                    (buffer-substring-no-properties (point-min) (point-max)))))
        (let ((inhibit-read-only t)
              (case-fold-search nil)
              (file-name (expand-file-name orig-buffer))
              (edit-success nil))
          ;; apply changes
          (dolist (buf-edit (seq-into buf-edits 'list))
            (when-let ((line-number (plist-get buf-edit :line_number))
                       (old-string (plist-get buf-edit :old_string))
                       (new-string (plist-get buf-edit :new_string))
                       (is-valid-old-string (not (string= old-string ""))))
              (goto-char (point-min))
              (forward-line (1- line-number))
              (when (search-forward old-string nil t)
                (replace-match new-string t t)
                (setq edit-success t))))
          ;; return result to gptel
          (if edit-success
              (progn
                ;; show diffs
                (ediff-buffers orig-buffer (current-buffer))
                (format "Successfully edited %s" orig-buffer))
            (format "Failed to edit %s" orig-buffer))))
    (format "Failed to edited %s" orig-buffer))))

(gptel-make-tool
 :function #'munen-gptel--edit-buffer-interactive
 :name "edit_buffer_interactive"
 :description "Modify a buffer interactively by applying a list of edits with review via ediff.

This tool applies the specified edits and opens an ediff session for review.
Each edit specifies a line number, old string to find, and new string replacement.

After applying edits, ediff opens to compare original vs modified versions,
allowing interactive review and selective application of changes before saving.
This provides a safe way to review changes before committing them to disk."
 :args (list '(:name "orig-buffer"
                     :type string
                     :description "The name of the buffer to modifyx")
             '(:name "buf-edits"
                     :type array
                     :items (:type object
                                   :properties
                                   (:line_number
                                    (:type integer :description "The line number of the buffer where edit starts.")
                                    :old_string
                                    (:type string :description "The old-string to be replaced.")
                                    :new_string
                                    (:type string :description "The new-string to replace old-string.")))
                     :description "The list of edits to apply on the buffer"))
 :category "emacs")

;;##########################################################################

;; run shell command
(gptel-make-tool
 :function (lambda (command &optional working_dir)
             (with-temp-message (format "Executing command: `%s`" command)
               (let ((default-directory (if (and working_dir (not (string= working_dir "")))
                                            (expand-file-name working_dir)
                                          default-directory)))
                 (shell-command-to-string command))))
 :name "shell_cmd_command"
 :description "Executes a shell command and returns the output as a string. IMPORTANT: This tool allows execution of arbitrary code; user confirmation will be required before any command is run."
 :args (list
        '(:name "command"
                :type string
                :description "The complete shell command to execute.")
        '(:name "working_dir"
                :type string
                :description "Optional: The directory in which to run the command. Defaults to the current directory if not specified."))
 :category "command"
 :confirm t
 :include t)

;;############################################################################

(defun gptel-git-checkpoint (buffer)
  "Commit specified buffer to .gptel-git, with incrementing checkpoint number."
  (let* ((buf (get-buffer buffer))
         (file (buffer-file-name buf))
         (dir (file-name-directory file))
         (default-directory dir)
         (git-dir (expand-file-name ".git" dir))
         (checkpoint-num))
    
    ;; Initialize .gptel-git if it doesn't exist
    (unless (file-exists-p git-dir)
      (shell-command (format "git init")))
    
    ;; Find previous checkpoint number
    (with-temp-buffer
      (call-process-shell-command 
       (format "git log --follow --pretty=format:'%%s' %s" file)
       nil t)
      (goto-char (point-min))
      (setq checkpoint-num 
            (if (re-search-forward "checkpoint \\([0-9]+\\)" nil t)
                (format "%04d" (1+ (string-to-number (match-string 1))))
              "0001")))
    
    ;; Stage and commit
    (shell-command 
     (format "git add %s" file))
    (shell-command 
     (format "git commit -m 'checkpoint %s' --allow-empty" checkpoint-num))))

(gptel-make-tool 
  :function #'gptel-git-checkpoint
  :name "git_checkpoint"
  :description "Checkpoint a buffer using git"
  :args (list
         '(:name "file"
                 :type string
                 :description "The name of buffer/file to checkpoint"))
  :category "emacs")


(provide 'my-gptel-tools)

