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
;; Step 2: Elixir-aware semantic j/k navigation for `defmodule` call nodes.
;;
;; In Elixir's Tree-sitter grammar, constructs like `defmodule` are represented
;; as (call ...) nodes.  The semantic meaning is determined by the text of the
;; first (identifier) child.  Generic first-child/parent traversal does not map
;; to meaningful Elixir structure, so j/k are overridden to walk the logical
;; parts of a defmodule call.
;;
;; AST shape for:  defmodule A do ... end
;;
;;   (call
;;     (identifier)          <- named child 0: the "defmodule" keyword
;;     (arguments
;;       (alias))            <- named child 1: the module name "A"
;;     (do_block ...))       <- named child 2: the module body

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

;;; Elixir-specific helpers

(defun esc--elixir-p ()
  "Return non-nil when the current buffer uses the Elixir Tree-sitter parser."
  (or (and (fboundp 'treesit-language-at)
           (eq (treesit-language-at (point)) 'elixir))
      (derived-mode-p 'elixir-ts-mode)))

(defun esc--enclosing-call-node ()
  "Return the nearest ancestor node of type `call' at point, or nil.
Starts from the node at point and walks up the tree."
  (let ((node (treesit-node-at (point))))
    (while (and node (not (string= (treesit-node-type node) "call")))
      (setq node (treesit-node-parent node)))
    node))

(defun esc--call-identifier-text (call-node)
  "Return the text of the identifier child of CALL-NODE, or nil.
Returns nil if the first named child is not an identifier."
  (let ((id-node (treesit-node-child call-node 0 t)))
    (when (and id-node (string= (treesit-node-type id-node) "identifier"))
      (buffer-substring-no-properties
       (treesit-node-start id-node)
       (treesit-node-end id-node)))))

(defun esc--defmodule-parts (call-node)
  "Return the ordered list of navigable semantic nodes within a defmodule CALL-NODE.

Parts in order:
  1. identifier node (the \"defmodule\" keyword)
  2. alias node inside arguments (the module name)
  3. do_block node (the module body)
  4. First named child of do_block (if one exists)"
  (let ((id-node (treesit-node-child call-node 0 t))
        alias-node do-block do-first)
    ;; Scan named children of call-node for arguments and do_block
    (let ((n (treesit-node-child-count call-node t)))
      (dotimes (i n)
        (let* ((c (treesit-node-child call-node i t))
               (type (treesit-node-type c)))
          (cond
           ((string= type "arguments")
            (setq alias-node (treesit-node-child c 0 t)))
           ((string= type "do_block")
            (setq do-block c))))))
    (setq do-first (when do-block (treesit-node-child do-block 0 t)))
    (delq nil (list id-node alias-node do-block do-first))))

(defun esc--defmodule-part-index (parts)
  "Return the index in PARTS of the part that contains point.
Ranges are inclusive-start, exclusive-end: a point exactly at a node's
end position is considered outside that node.
When point falls within multiple overlapping parts (e.g. do_block and its
first child), the last (innermost) matching index is returned.
Returns nil if point is not within any part."
  (let ((pt (point))
        result)
    (dotimes (i (length parts))
      (let ((node (nth i parts)))
        (when (and (<= (treesit-node-start node) pt)
                   (< pt (treesit-node-end node)))
          (setq result i))))
    result))

(defun esc--in-defmodule-call-p ()
  "Return the enclosing defmodule call node if point is within one, else nil."
  (when (esc--elixir-p)
    (let ((call (esc--enclosing-call-node)))
      (when (and call (equal (esc--call-identifier-text call) "defmodule"))
        call))))

(defun esc--defmodule-j ()
  "Move forward through the semantic parts of the enclosing defmodule call.
Parts visited in order: identifier → module name → do_block → first body form."
  (let* ((call (esc--in-defmodule-call-p))
         (parts (esc--defmodule-parts call))
         (idx (esc--defmodule-part-index parts)))
    (cond
     ((null parts)  (message "No navigable parts in defmodule"))
     ((null idx)
      ;; Point is outside all known parts — jump to the first one
      (esc--goto-node (car parts)))
     (t
      (let ((next (nth (1+ idx) parts)))
        (if next
            (esc--goto-node next)
          (message "No next part in defmodule")))))))

(defun esc--defmodule-k ()
  "Move backward through the semantic parts of the enclosing defmodule call.
Falls back to generic parent navigation when already at the first part."
  (let* ((call (esc--in-defmodule-call-p))
         (parts (esc--defmodule-parts call))
         (idx (esc--defmodule-part-index parts)))
    ;; idx is nil (outside parts) or 0 (at first part): fall back to parent
    (if (or (null idx) (= idx 0))
        (if-let ((parent (treesit-node-parent call)))
            (esc--goto-node parent)
          (message "No parent node"))
      ;; idx is a positive number: move to previous part
      (esc--goto-node (nth (1- idx) parts)))))

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
In Elixir, when point is within a defmodule call, navigates forward
through the semantic parts of the defmodule instead of raw first child."
  (interactive)
  (if (esc--in-defmodule-call-p)
      (esc--defmodule-j)
    (if-let ((node (esc--current-node))
             (child (treesit-node-child node 0)))
        (esc--goto-node child)
      (message "No child node"))))

(defun esc-parent ()
  "Move up to the parent node in the AST.
In Elixir, when point is within a defmodule call, navigates backward
through the semantic parts of the defmodule instead of raw parent."
  (interactive)
  (if (esc--in-defmodule-call-p)
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
