;;; esc-mode.el --- Emacs Structured Coding (AST navigation) -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "29.1"))
;; Version: 0.1.0
;; Keywords: languages, tools
;; URL: https://github.com/diasbruno/emacs-esc

;;; Commentary:
;; esc-mode is a minor mode for structured code navigation and editing
;; using Emacs built-in Tree-sitter integration (treesit).
;;
;; Step 0 only: skeleton, no AST navigation yet.

;;; Code:

(defgroup esc nil
  "Emacs Structured Coding."
  :group 'tools
  :prefix "esc-")

(defvar esc-mode-map
  (let ((map (make-sparse-keymap)))
    map)
  "Keymap for `esc-mode'.")

;;;###autoload
(define-minor-mode esc-mode
  "Toggle esc-mode."
  :lighter " esc"
  :keymap esc-mode-map)

(provide 'esc-mode)
;;; esc-mode.el ends here
