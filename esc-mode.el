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
;; Step 2: Elixir-aware semantic navigation for `defmodule' call nodes.

;;; Code:

(require 'treesit)
(require 'seq)

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

;;; Elixir-specific semantic navigation for `defmodule' call nodes.
;;
;; In Elixir's Tree-sitter grammar many constructs are represented as
;; (call ...) nodes whose semantic meaning is determined by an (identifier)
;; child.  For `defmodule', the tree shape is:
;;
;;   (call
;;     (identifier)          ; the literal text "defmodule"
;;     (arguments (alias))   ; the module name, e.g. "A"
;;     (do_block ...))       ; the module body
;;
;; When point is anywhere inside such a call, `j' and `k' step through
;; these semantic parts instead of using raw first-child / parent moves.

(defun esc--elixir-p ()
  "Return non-nil if the current buffer uses Elixir Tree-sitter parsing."
  (or (and (fboundp 'treesit-language-at)
           (eq (treesit-language-at (point)) 'elixir))
      (derived-mode-p 'elixir-ts-mode)))

(defun esc--enclosing-call-node (node)
  "Walk up from NODE and return the nearest ancestor (inclusive) of type `call'."
  (let ((n node))
    (while (and n (not (string= (treesit-node-type n) "call")))
      (setq n (treesit-node-parent n)))
    n))

(defun esc--call-identifier-text (call-node)
  "Return the text of the identifier child of CALL-NODE, or nil if absent."
  (when call-node
    (let ((first (treesit-node-child call-node 0 t)))
      (when (and first (string= (treesit-node-type first) "identifier"))
        (treesit-node-text first t)))))

(defun esc--defmodule-parts (call-node)
  "Return ordered semantic navigation parts for a defmodule CALL-NODE.
The list contains: identifier, alias (inside arguments), do_block, and
optionally the first named child of do_block.  Missing nodes are omitted."
  (let* ((named (treesit-node-children call-node t))
         (id-node (car named))
         (args-node (seq-find (lambda (n)
                                (string= (treesit-node-type n) "arguments"))
                              named))
         (alias-node (when args-node
                       (seq-find (lambda (n)
                                   (string= (treesit-node-type n) "alias"))
                                 (treesit-node-children args-node t))))
         (do-node (seq-find (lambda (n)
                              (string= (treesit-node-type n) "do_block"))
                            named))
         (do-first (when do-node
                     (car (treesit-node-children do-node t)))))
    (delq nil (list id-node alias-node do-node do-first))))

(defun esc--defmodule-part-index (parts)
  "Return the index in PARTS whose range contains point, or nil.
When multiple parts overlap (do_block and its first child), the innermost
(last matching) part wins."
  (let ((pos (point))
        (idx 0)
        found)
    (dolist (part parts)
      (when (and part
                 (>= pos (treesit-node-start part))
                 (<= pos (treesit-node-end part)))
        (setq found idx))
      (setq idx (1+ idx)))
    found))

(defun esc--in-defmodule-call-p ()
  "Return non-nil when point is within a `defmodule' call node."
  (when-let* ((node (esc--current-node))
              (call (esc--enclosing-call-node node))
              (text (esc--call-identifier-text call)))
    (string= text "defmodule")))

(defun esc--defmodule-j ()
  "Semantic j (down) inside a defmodule: advance to the next structural part."
  (let* ((node (esc--current-node))
         (call (esc--enclosing-call-node node))
         (parts (esc--defmodule-parts call))
         (idx (esc--defmodule-part-index parts))
         (next (if idx (1+ idx) 0)))
    (if (< next (length parts))
        (esc--goto-node (nth next parts))
      (message "No next part"))))

(defun esc--defmodule-k ()
  "Semantic k (up) inside a defmodule: move to the previous structural part.
Falls back to generic parent navigation when already at the first part."
  (let* ((node (esc--current-node))
         (call (esc--enclosing-call-node node))
         (parts (esc--defmodule-parts call))
         (idx (esc--defmodule-part-index parts)))
    (cond
     ((and idx (> idx 0))
      (esc--goto-node (nth (1- idx) parts)))
     (t
      ;; Already at (or before) the first part: fall back to generic parent.
      (if-let ((parent (treesit-node-parent (esc--current-node))))
          (esc--goto-node parent)
        (message "No parent node"))))))

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
  "Move down into the first child node in the AST.
In Elixir, when point is inside a `defmodule' call, uses semantic navigation
to step through the call's structural parts instead of the raw first child."
  (interactive)
  (if (and (esc--elixir-p) (esc--in-defmodule-call-p))
      (esc--defmodule-j)
    (if-let ((node (esc--current-node))
             (child (treesit-node-child node 0)))
        (esc--goto-node child)
      (message "No child node"))))

(defun esc-parent ()
  "Move up to the parent node in the AST.
In Elixir, when point is inside a `defmodule' call, uses semantic navigation
to step backward through the call's structural parts instead of moving to the
raw parent."
  (interactive)
  (if (and (esc--elixir-p) (esc--in-defmodule-call-p))
      (esc--defmodule-k)
    (if-let ((node (esc--current-node))
             (parent (treesit-node-parent node)))
        (esc--goto-node parent)
      (message "No parent node"))))

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
