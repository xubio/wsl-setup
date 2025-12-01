;;(setq load-path (append (list "~/lisp/emigo" ) load-path ))
;; key: 
;; openrouter:
(setq or-api-key (getenv "OPENROUTER_API_KEY"))
;; anthropic:
(setq anthropic-api-key (getenv "ANTHROPIC_API_KEY"))
(require 'gptel)
(require 'transient)
(require 'gptel-transient)
(require 'my-gptel-tools)
;; Add Claude backend
(gptel-make-anthropic
 "Claude"
 :stream t
 :key 'anthropic-api-key)

(gptel-make-openai
    "OpenRouter"
  :host "openrouter.ai"
  :endpoint "/api/v1/chat/completions"
  :stream t
  :key 'or-api-key       ;can be a function that returns the key
  :models '(x-ai/grok-code-fast-1
            mistralai/codestral-2508
            minimax/minimax-m2
            google/gemini-2.5-flash))

;; Set as default
(setq gptel-backend (gptel-get-backend "OpenRouter"))
(setq gptel-model 'x-ai/grok-code-fast-1)
;;(setq gptel-model "claude-3-5-haiku-latest")
;;(setq gptel-model "google/gemini-2.5-flash")
(setq gpt-use-tools t)


(defun gptel-send-current-line ()
  "Select the current line and send to gptel."
  (interactive)
  (save-excursion
    (beginning-of-line)
    (set-mark (point))
    (end-of-line)
    (gptel-send nil))) ;; nil means send the active region

;; Keybindings
(global-set-key (kbd "M-s s") 'gptel-send)
(global-set-key (kbd "M-s g") 'gptel-menu)
(global-set-key (kbd "M-s a") 'gptel-add)
(global-set-key (kbd "M-s C") 'gptel-context-remove-all)
(global-set-key (kbd "M-s l") 'gptel-send-current-line)
(global-set-key (kbd "M-s p") 'gptel-send-current-paragraph)
(global-set-key (kbd "M-s r") 'gptel-rewrite)

(provide 'ai)
