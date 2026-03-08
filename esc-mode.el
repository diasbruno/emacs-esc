;;; esc-mode.el --- Emacs Structured Coding (AST navigation) -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "29.1"))
;; Version: 0.1.0
;; Keywords: languages, tools
;; URL: https://github.com/diasbruno/emacs-esc

;;; Commentary:
;; esc-mode is a minor mode for structured code navigation and editing
;; using Emacs built-in Tree-sitter integration (treesit).
;;
;; Generic navigation uses Tree-sitter to move between AST nodes:
;;   n   descends into the first child of the current node
;;   p   ascends to the parent of the current node
;;
;; Language-specific navigation can be registered via
;; `esc-register-language-handler'.  When `esc-mode' is enabled it checks the
;; buffer's principal major mode (including derived modes) and installs the
;; matching handler as the buffer-local forward/backward navigation functions.
;; The handler is called first; if it returns nil the generic AST navigation
;; is used as a fallback.
;;
;; Elixir support (elixir-ts-mode) is provided by `esc-elixir', which is
;; loaded automatically as part of this package.

;;; Code:

(require 'treesit)

(defgroup esc nil
  "Emacs Structured Coding."
  :group 'tools
  :prefix "esc-")

(defvar esc-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "n") #'esc-next)
    (define-key map (kbd "p") #'esc-prev)
    (define-key map (kbd "a") #'esc-add-method)
    (define-key map (kbd "A") #'esc-add-attribute)
    (define-key map (kbd "i") #'esc-add-module)
    (define-key map (kbd "d") #'esc-delete-form)
    (define-key map (kbd "J") #'esc-move-form-down)
    (define-key map (kbd "K") #'esc-move-form-up)
    map)
  "Keymap for `esc-mode'.")

;;; Language handler registry

(defvar esc-language-handlers '()
  "Alist mapping major-mode symbols to (NEXT-FN . PREV-FN) navigation handlers.
Each entry has the form (MODE . (NEXT-FN . PREV-FN)).
Use `esc-register-language-handler' to add entries.
When `esc-mode' is enabled, the first entry whose MODE satisfies
`derived-mode-p' is selected as the active handler for the buffer.")

(defun esc-register-language-handler (mode next-fn prev-fn)
  "Register language-specific navigation handlers for major MODE.
NEXT-FN is called for forward navigation and PREV-FN for backward navigation.
Each function should return non-nil when it handles the navigation, or nil to
fall back to the generic Tree-sitter AST navigation."
  (setf (alist-get mode esc-language-handlers) (cons next-fn prev-fn)))

(defvar-local esc--next-fn nil
  "Buffer-local forward navigation function installed by `esc-mode', or nil.")

(defvar-local esc--prev-fn nil
  "Buffer-local backward navigation function installed by `esc-mode', or nil.")

;;; Editing handler registry

(defvar esc-edit-handlers '()
  "Alist mapping major-mode symbols to editing handler functions.
Each entry has the form (MODE . EDIT-FN), where MODE is a major-mode symbol
such as `elixir-ts-mode'.
Use `esc-register-edit-handler' to add entries.
EDIT-FN is called with a single operation symbol argument.
Supported operations: `add-method', `add-module', `add-attribute',
`move-up', `move-down', `delete'.")

(defun esc-register-edit-handler (mode edit-fn)
  "Register a language-specific editing handler EDIT-FN for major MODE.
EDIT-FN is called with an operation symbol and should implement the
requested editing action in the current buffer context."
  (setf (alist-get mode esc-edit-handlers) edit-fn))

(defvar-local esc--edit-fn nil
  "Buffer-local editing handler installed by `esc-mode', or nil.")

(defmacro esc--with-edit (&rest body)
  "Execute BODY with the buffer temporarily writable.
Used by editing commands to bypass the read-only protection that
`esc-mode' applies to the buffer."
  `(let ((inhibit-read-only t))
     ,@body))

(defun esc--dispatch-edit (operation)
  "Call the buffer-local editing handler with OPERATION.
If no editing handler is installed, show a message."
  (if esc--edit-fn
      (funcall esc--edit-fn operation)
    (message "No editing handler registered for this buffer")))

;;; Internal helpers

(defun esc--current-node ()
  "Return the Tree-sitter node at point."
  (treesit-node-at (point)))

(defun esc--goto-node (node)
  "Move point to the start position of NODE."
  (when node
    (goto-char (treesit-node-start node))))

;;; Editing commands

(defun esc-add-method ()
  "Add a new method/function definition after the current form."
  (interactive)
  (esc--dispatch-edit 'add-method))

(defun esc-add-module ()
  "Add a new internal module definition after the current form."
  (interactive)
  (esc--dispatch-edit 'add-module))

(defun esc-add-attribute ()
  "Add a new module attribute after the current form."
  (interactive)
  (esc--dispatch-edit 'add-attribute))

(defun esc-move-form-up ()
  "Move the current form up, swapping it with its previous sibling."
  (interactive)
  (esc--dispatch-edit 'move-up))

(defun esc-move-form-down ()
  "Move the current form down, swapping it with its next sibling."
  (interactive)
  (esc--dispatch-edit 'move-down))

(defun esc-delete-form ()
  "Delete the current form."
  (interactive)
  (esc--dispatch-edit 'delete))

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

(defun esc-next ()
  "Move forward through the AST.
If a language-specific handler is active for this buffer (see
`esc-language-handlers'), it is called first.  When the handler returns
non-nil the navigation is considered handled.  When it returns nil, or when
no handler is registered, the generic fallback is used: descend into the
first child of the current node."
  (interactive)
  (unless (and esc--next-fn (funcall esc--next-fn))
    (if-let ((node (esc--current-node))
             (child (treesit-node-child node 0)))
        (esc--goto-node child)
      (message "No child node"))))

(defun esc-prev ()
  "Move backward through the AST.
If a language-specific handler is active for this buffer (see
`esc-language-handlers'), it is called first.  When the handler returns
non-nil the navigation is considered handled.  When it returns nil, or when
no handler is registered, the generic fallback is used: ascend to the
parent of the current node."
  (interactive)
  (unless (and esc--prev-fn (funcall esc--prev-fn))
    (if-let ((node (esc--current-node))
             (parent (treesit-node-parent node)))
        (esc--goto-node parent)
      (message "No parent node"))))

;;; Minor mode

(defvar-local esc--set-read-only nil
  "Non-nil if `esc-mode' made this buffer read-only (it was writable before enabling).")

(defun esc--install-language-handler ()
  "Set buffer-local navigation and editing functions from handler registries.
Walks the alists and selects the first entry whose mode key satisfies
`derived-mode-p' for the current buffer's major mode."
  (let ((nav-entry (seq-find (lambda (e) (derived-mode-p (car e)))
                             esc-language-handlers))
        (edit-entry (seq-find (lambda (e) (derived-mode-p (car e)))
                              esc-edit-handlers)))
    (when nav-entry
      (let ((handlers (cdr nav-entry)))
        (setq esc--next-fn (car handlers))
        (setq esc--prev-fn (cdr handlers))))
    (when edit-entry
      (setq esc--edit-fn (cdr edit-entry)))))

;;;###autoload
(define-minor-mode esc-mode
  "Toggle esc-mode for Tree-sitter AST navigation.
When enabled, the buffer is made read-only and the following keys
are bound for navigation:
  n   Move forward through the AST (next / into first child)
  p   Move backward through the AST (previous / up to parent)

Language-specific navigation is activated automatically based on the
buffer's principal major mode by consulting `esc-language-handlers'."
  :lighter " esc"
  :keymap esc-mode-map
  (if esc-mode
      (progn
        (unless (and (fboundp 'treesit-available-p)
                     (treesit-available-p)
                     (treesit-parser-list))
          (esc-mode -1)
          (user-error "esc-mode requires Tree-sitter with a parser for this buffer"))
        (esc--install-language-handler)
        (setq esc--set-read-only (not buffer-read-only))
        (read-only-mode 1))
    (setq esc--next-fn nil
          esc--prev-fn nil
          esc--edit-fn nil)
    (when esc--set-read-only
      (setq esc--set-read-only nil)
      (read-only-mode -1))))

;; Load Elixir navigation support (part of this package).
(require 'esc-elixir nil :noerror)

(provide 'esc-mode)
;;; esc-mode.el ends here
