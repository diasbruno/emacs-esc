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
;; Step 2: Tree-sitter node navigation inspector (`esc-inspect-node', bound to `?').

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
    (define-key map (kbd "?") #'esc-inspect-node)
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

;;; Inspector

(defconst esc-inspector-preview-length 60
  "Maximum number of characters to show as a text preview for a node.")

(defvar-local esc-inspector--source-buffer nil
  "The source buffer the inspector was opened from.")

(defun esc--node-preview (node)
  "Return a short preview of NODE's text (up to `esc-inspector-preview-length' chars)."
  (let* ((start (treesit-node-start node))
         (end   (treesit-node-end node))
         (limit (min (+ start esc-inspector-preview-length) end))
         (text  (buffer-substring-no-properties start limit)))
    (if (< limit end) (concat text "...") text)))

(defun esc--format-node-line (label node source-buf)
  "Return a propertized line string for NODE with LABEL, reading text from SOURCE-BUF."
  (with-current-buffer source-buf
    (let* ((type    (treesit-node-type node))
           (start   (treesit-node-start node))
           (end     (treesit-node-end node))
           (named   (and (fboundp 'treesit-node-check)
                         (treesit-node-check node 'named)))
           (preview (replace-regexp-in-string
                     "\n" "↵" (esc--node-preview node))))
      (propertize
       (format "%-20s %-20s %-5s [%d-%d] %s\n"
               label type (if named "named" "anon") start end preview)
       'esc-node-start start))))

(defun esc--collect-ancestors (node)
  "Return a list of ancestors of NODE, ordered from immediate parent to root."
  (let ((ancestors '())
        (current (treesit-node-parent node)))
    (while current
      (push current ancestors)
      (setq current (treesit-node-parent current)))
    (nreverse ancestors)))

(defun esc-inspector-jump ()
  "Jump to the node on the current line in the source buffer."
  (interactive)
  (let ((pos (get-text-property (line-beginning-position) 'esc-node-start)))
    (if (and pos (buffer-live-p esc-inspector--source-buffer))
        (progn
          (pop-to-buffer esc-inspector--source-buffer)
          (goto-char pos))
      (message "No node on this line"))))

(defun esc-inspector-refresh ()
  "Refresh the inspector buffer from the current position in the source buffer."
  (interactive)
  (if (buffer-live-p esc-inspector--source-buffer)
      (with-current-buffer esc-inspector--source-buffer
        (esc-inspect-node))
    (message "Source buffer no longer live")))

(defvar esc-inspector-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'esc-inspector-jump)
    (define-key map (kbd "g")   #'esc-inspector-refresh)
    map)
  "Keymap for `esc-inspector-mode'.")

(define-derived-mode esc-inspector-mode special-mode "esc-inspector"
  "Major mode for the esc node inspector buffer.
\\{esc-inspector-mode-map}"
  :group 'esc)

(defun esc-inspect-node ()
  "Open the *esc-nodes* inspector showing Tree-sitter nodes around point."
  (interactive)
  (unless (and (fboundp 'treesit-available-p)
               (treesit-available-p)
               (treesit-parser-list))
    (user-error "esc-inspect-node requires Tree-sitter with a parser for this buffer"))
  (let* ((source-buf (current-buffer))
         (node       (esc--current-node))
         (buf        (get-buffer-create "*esc-nodes*")))
    (with-current-buffer buf
      (setq esc-inspector--source-buffer source-buf)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "=== esc Node Inspector ===\n\n")
        ;; Current node
        (insert "-- Current --\n")
        (insert (esc--format-node-line "current" node source-buf))
        ;; Parent
        (insert "\n-- Parent --\n")
        (let ((parent (treesit-node-parent node)))
          (if parent
              (insert (esc--format-node-line "parent" parent source-buf))
            (insert "(no parent)\n")))
        ;; Ancestors (immediate parent → root)
        (insert "\n-- Ancestors (parent → root) --\n")
        (let ((ancestors (esc--collect-ancestors node)))
          (if ancestors
              (dolist (anc ancestors)
                (insert (esc--format-node-line "ancestor" anc source-buf)))
            (insert "(no ancestors)\n")))
        ;; Children
        (insert "\n-- Children --\n")
        (let ((child-count (treesit-node-child-count node)))
          (if (> child-count 0)
              (dotimes (i child-count)
                (insert (esc--format-node-line
                         (format "child[%d]" i)
                         (treesit-node-child node i)
                         source-buf)))
            (insert "(no children)\n")))
        ;; Siblings
        (insert "\n-- Siblings --\n")
        (let ((prev (treesit-node-prev-sibling node))
              (next (treesit-node-next-sibling node)))
          (if prev
              (insert (esc--format-node-line "prev-sibling" prev source-buf))
            (insert "(no previous sibling)\n"))
          (if next
              (insert (esc--format-node-line "next-sibling" next source-buf))
            (insert "(no next sibling)\n"))))
      (esc-inspector-mode)
      (goto-char (point-min)))
    (pop-to-buffer buf)))

;;; Minor mode

;;;###autoload
(define-minor-mode esc-mode
  "Toggle esc-mode for Tree-sitter AST navigation.
When enabled: h (prev sibling), l (next sibling),
j (first child), k (parent), ? (inspect node)."
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
