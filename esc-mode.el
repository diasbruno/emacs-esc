;;; esc-mode.el --- Emacs Structured Coding (AST navigation) -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "29.1"))
;; Version: 0.1.0
;; Keywords: languages, tools
;; URL: https://github.com/diasbruno/emacs-esc

;;; Commentary:
;; esc-mode is a minor mode for structured code navigation and editing
;; using Emacs built-in Tree-sitter integration (treesit).
;;
;; Step 1: Tree-sitter availability check and AST-based h/j/k/l navigation.

;;; Code:

(require 'treesit)

(defgroup esc nil
  "Emacs Structured Coding."
  :group 'tools
  :prefix "esc-")

(defvar esc-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "h") #'esc-prev-sibling)
    (define-key map (kbd "l") #'esc-next-sibling)
    (define-key map (kbd "j") #'esc-first-child)
    (define-key map (kbd "k") #'esc-parent)
    map)
  "Keymap for `esc-mode'.")

;;; Internal helpers

(defun esc--current-node ()
  "Return the Tree-sitter node at point."
  (treesit-node-at (point)))

(defun esc--goto-node (node)
  "Move point to the start position of NODE."
  (when node
    (goto-char (treesit-node-start node))))

;;; Navigation commands

(defun esc-prev-sibling ()
  "Move to the previous sibling node in the AST."
  (interactive)
  (if-let ((node (esc--current-node))
           (sibling (treesit-node-prev-sibling node)))
      (esc--goto-node sibling)
    (message "No previous sibling")))

(defun esc-next-sibling ()
  "Move to the next sibling node in the AST."
  (interactive)
  (if-let ((node (esc--current-node))
           (sibling (treesit-node-next-sibling node)))
      (esc--goto-node sibling)
    (message "No next sibling")))

(defun esc-first-child ()
  "Move down into the first child node in the AST."
  (interactive)
  (if-let ((node (esc--current-node))
           (child (treesit-node-child node 0)))
      (esc--goto-node child)
    (message "No child node")))

(defun esc-parent ()
  "Move up to the parent node in the AST."
  (interactive)
  (if-let ((node (esc--current-node))
           (parent (treesit-node-parent node)))
      (esc--goto-node parent)
    (message "No parent node")))

;;; Minor mode

;;;###autoload
(define-minor-mode esc-mode
  "Toggle esc-mode for Tree-sitter AST navigation.
When enabled: h (prev sibling), l (next sibling),
j (first child), k (parent)."
  :lighter " esc"
  :keymap esc-mode-map
  (when esc-mode
    (unless (and (fboundp 'treesit-available-p)
                 (treesit-available-p)
                 (treesit-parser-list))
      (esc-mode -1)
      (user-error "esc-mode requires Tree-sitter with a parser for this buffer"))))

(provide 'esc-mode)
;;; esc-mode.el ends here
