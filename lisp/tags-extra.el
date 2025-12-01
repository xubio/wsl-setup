(defun tags-extra-get-all-tags-files ()
  "Return all, fully qualified, file names."
  (save-excursion
    (let ((first-time t))
      (while (visit-tags-table-buffer (not first-time))
        (setq first-time nil)
        (setq res (mapcar 'expand-file-name (tags-table-files))))))
  res)


(defun tags-extra-find-file (name)
  "Edit file named NAME that is part of the current tags table.
The file name should not include parts of the path."
  (interactive
   (list
    (icicle-completing-read "Name of file: "
                     ;; Make an a-list of all files without path.
                     (mapcar
                      (lambda (file)
                        (cons (file-name-nondirectory file) nil))
                      (tags-extra-get-all-tags-files)))))
  (let ((files (tags-extra-get-all-tags-files))
        (done nil)
        (name-re (concat "^" (regexp-quote name) "$")))
    (while (and (not done)
                files)
      (let ((case-fold-search t))
        (if (string-match name-re (file-name-nondirectory (car files)))
            (setq done t)
          (setq files (cdr files)))))
    (if files
        (find-file (car files))
      (error "File not found in the tags table."))))

(provide 'tags-extra)
