;;; esc-elixir.el --- Elixir-specific AST navigation for esc-mode -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "29.1") (esc-mode "0.1.0"))
;; Keywords: languages, tools
;; URL: https://github.com/diasbruno/emacs-esc

;;; Commentary:
;; Elixir-specific structured navigation for `esc-mode'.
;;
;; This file registers Elixir navigation handlers that `esc-mode' activates
;; automatically when the principal mode of the buffer is `elixir-ts-mode'
;; (or any mode derived from it).
;;
;; Navigation is aware of:
;;   - defmodule call nodes and their semantic parts
;;   - do_block children at module level
;;   - alias/use/import/require call nodes at module level
;;   - module_attribute nodes at module level
;;   - def/defp/defmacro/defmacrop function body do_blocks
;;
;; In Elixir's Tree-sitter grammar, constructs like `defmodule` are represented
;; as (call ...) nodes.  The semantic meaning is determined by the text of the
;; first (identifier) child.  Generic first-child/parent traversal does not map
;; to meaningful Elixir structure, so n/p are overridden to walk the logical
;; parts of a defmodule call.

;;; Code:

(require 'treesit)

(declare-function esc-register-language-handler "esc-mode")
(declare-function esc-register-edit-handler "esc-mode")
(declare-function esc--goto-node "esc-mode")

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

(defun esc--part-index (parts)
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

(defun esc--defmodule-next ()
  "Move forward through the semantic parts of the enclosing defmodule call.
Parts visited in order: identifier → module name → do_block → first body form."
  (let* ((call (esc--in-defmodule-call-p))
         (parts (esc--defmodule-parts call))
         (idx (esc--part-index parts)))
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

(defun esc--defmodule-prev ()
  "Move backward through the semantic parts of the enclosing defmodule call.
Falls back to generic parent navigation when already at the first part."
  (let* ((call (esc--in-defmodule-call-p))
         (parts (esc--defmodule-parts call))
         (idx (esc--part-index parts)))
    ;; idx is nil (outside parts) or 0 (at first part): fall back to parent
    (if (or (null idx) (= idx 0))
        (if-let ((parent (treesit-node-parent call)))
            (esc--goto-node parent)
          (message "No parent node"))
      ;; idx is a positive number: move to previous part
      (esc--goto-node (nth (1- idx) parts)))))

;;; Elixir do_block helpers

(defun esc--enclosing-do-block ()
  "Return the nearest ancestor node of type `do_block' at point, or nil.
Starts from the node at point and walks up the tree."
  (let ((node (treesit-node-at (point))))
    (while (and node (not (string= (treesit-node-type node) "do_block")))
      (setq node (treesit-node-parent node)))
    node))

(defun esc--do-block-current-child (do-block)
  "Return the direct named child of DO-BLOCK that contains point, or nil."
  (let ((pt (point))
        (n (treesit-node-child-count do-block t))
        result)
    (dotimes (i n)
      (let ((child (treesit-node-child do-block i t)))
        (when (and (<= (treesit-node-start child) pt)
                   (< pt (treesit-node-end child)))
          (setq result child))))
    result))

(defun esc--in-do-block-p ()
  "Return the enclosing module-level do_block if point is within a named child of it, else nil.
Only considers do_block nodes whose parent is a defmodule call, so that
navigation inside def/defp/macro bodies falls through to generic traversal."
  (when (esc--elixir-p)
    (let ((do-block (esc--enclosing-do-block)))
      (when (and do-block
                 (let ((parent (treesit-node-parent do-block)))
                   (and parent
                        (string= (treesit-node-type parent) "call")
                        (equal (esc--call-identifier-text parent) "defmodule")))
                 (esc--do-block-current-child do-block))
        do-block))))

(defun esc--do-block-next ()
  "Move to the next named sibling within the enclosing do_block."
  (let* ((do-block (esc--in-do-block-p))
         (current (esc--do-block-current-child do-block))
         (next (treesit-node-next-sibling current t)))
    (if next
        (esc--goto-node next)
      (message "No next form in do block"))))

(defun esc--do-block-prev ()
  "Move to the previous named sibling within the enclosing do_block.
Falls back to the do_block itself when already at the first child."
  (let* ((do-block (esc--in-do-block-p))
         (current (esc--do-block-current-child do-block))
         (prev (treesit-node-prev-sibling current t)))
    (if prev
        (esc--goto-node prev)
      (esc--goto-node do-block))))

;;; Elixir navigable call helpers (alias, use, import)

(defconst esc--navigable-call-identifiers '("alias" "use" "import" "require")
  "Identifiers of call nodes that are navigable at module level.
These nodes are treated as leaf nodes during n/p navigation; a future
smart-editing feature will expose their internal parts.")

(defun esc--in-navigable-call-p ()
  "Return the enclosing alias/use/import call if inside one at module level, else nil.
A navigable call is a call whose identifier is in `esc--navigable-call-identifiers'
and that is a direct named child of a module-level do_block."
  (when (esc--elixir-p)
    (let ((call (esc--enclosing-call-node)))
      (when (and call
                 (member (esc--call-identifier-text call)
                         esc--navigable-call-identifiers))
        (let* ((parent (treesit-node-parent call))
               (grandparent (when parent (treesit-node-parent parent))))
          (when (and parent
                     (string= (treesit-node-type parent) "do_block")
                     grandparent
                     (string= (treesit-node-type grandparent) "call")
                     (equal (esc--call-identifier-text grandparent) "defmodule"))
            call))))))

(defun esc--navigable-call-parts (call-node)
  "Return the navigable semantic parts of a navigable CALL-NODE.
Parts in order:
  1. identifier node (the call keyword, e.g. \"alias\")
  2. first argument node inside the arguments child (e.g. the aliased module)"
  (let ((id-node (treesit-node-child call-node 0 t))
        first-arg)
    (let ((n (treesit-node-child-count call-node t)))
      (dotimes (i n)
        (let* ((c (treesit-node-child call-node i t))
               (type (treesit-node-type c)))
          (when (string= type "arguments")
            (setq first-arg (treesit-node-child c 0 t))))))
    (delq nil (list id-node first-arg))))

(defun esc--navigable-call-next ()
  "Move forward through the semantic parts of the enclosing navigable call.
Parts visited in order: identifier -> first argument.
At the last part, advances to the next named sibling in the do_block."
  (let* ((call (esc--in-navigable-call-p))
         (parts (esc--navigable-call-parts call))
         (idx (esc--part-index parts)))
    (cond
     ((null parts) (message "No navigable parts"))
     ((null idx)   (esc--goto-node (car parts)))
     (t
      (let ((next (nth (1+ idx) parts)))
        (if next
            (esc--goto-node next)
          (let ((next-sibling (treesit-node-next-sibling call t)))
            (if next-sibling
                (esc--goto-node next-sibling)
              (message "No next form in do block")))))))))

(defun esc--navigable-call-prev ()
  "Move backward through the semantic parts of the enclosing navigable call.
Falls back to the previous named sibling in the do_block (or the do_block
itself) when already at the first part."
  (let* ((call (esc--in-navigable-call-p))
         (parts (esc--navigable-call-parts call))
         (idx (esc--part-index parts)))
    (if (or (null idx) (= idx 0))
        (let ((prev (treesit-node-prev-sibling call t)))
          (if prev
              (esc--goto-node prev)
            (esc--goto-node (treesit-node-parent call))))
      (esc--goto-node (nth (1- idx) parts)))))

;;; Elixir module_attribute helpers

(defun esc--enclosing-module-attribute ()
  "Return the nearest ancestor node of type `module_attribute' at point, or nil.
Starts from the node at point and walks up the tree."
  (let ((node (treesit-node-at (point))))
    (while (and node (not (string= (treesit-node-type node) "module_attribute")))
      (setq node (treesit-node-parent node)))
    node))

(defun esc--in-module-attribute-p ()
  "Return the enclosing module_attribute if inside one at module level, else nil.
A module-level module_attribute is a direct named child of a module-level do_block."
  (when (esc--elixir-p)
    (let ((attr (esc--enclosing-module-attribute)))
      (when attr
        (let* ((parent (treesit-node-parent attr))
               (grandparent (when parent (treesit-node-parent parent))))
          (when (and parent
                     (string= (treesit-node-type parent) "do_block")
                     grandparent
                     (string= (treesit-node-type grandparent) "call")
                     (equal (esc--call-identifier-text grandparent) "defmodule"))
            attr))))))

(defun esc--module-attribute-parts (attr-node)
  "Return the navigable semantic parts of a module_attribute ATTR-NODE.
Parts in order:
  1. identifier node (the attribute name, e.g. \"moduledoc\")
  2. value node (the attribute value expression, if present)"
  (let ((id-node (treesit-node-child attr-node 0 t))
        (val-node (treesit-node-child attr-node 1 t)))
    (delq nil (list id-node val-node))))

(defun esc--module-attribute-next ()
  "Move forward through the semantic parts of the enclosing module_attribute.
Parts visited in order: attribute name -> value.
At the last part, advances to the next named sibling in the do_block."
  (let* ((attr (esc--in-module-attribute-p))
         (parts (esc--module-attribute-parts attr))
         (idx (esc--part-index parts)))
    (cond
     ((null parts) (message "No navigable parts"))
     ((null idx)   (esc--goto-node (car parts)))
     (t
      (let ((next (nth (1+ idx) parts)))
        (if next
            (esc--goto-node next)
          (let ((next-sibling (treesit-node-next-sibling attr t)))
            (if next-sibling
                (esc--goto-node next-sibling)
              (message "No next form in do block")))))))))

(defun esc--module-attribute-prev ()
  "Move backward through the semantic parts of the enclosing module_attribute.
Falls back to the previous named sibling in the do_block (or the do_block
itself) when already at the first part."
  (let* ((attr (esc--in-module-attribute-p))
         (parts (esc--module-attribute-parts attr))
         (idx (esc--part-index parts)))
    (if (or (null idx) (= idx 0))
        (let ((prev (treesit-node-prev-sibling attr t)))
          (if prev
              (esc--goto-node prev)
            (esc--goto-node (treesit-node-parent attr))))
      (esc--goto-node (nth (1- idx) parts)))))

;;; Elixir function body helpers

(defconst esc--function-call-identifiers '("def" "defp" "defmacro" "defmacrop")
  "Identifiers of call nodes that define named functions in Elixir.
Their do_block children are treated as function bodies for navigation.")

(defun esc--in-function-do-block-p ()
  "Return the enclosing function-level do_block if inside a def/defp body, else nil.
Only matches do_block nodes whose parent call has an identifier that is a
member of `esc--function-call-identifiers', so that module-level do_blocks
owned by defmodule are not matched here."
  (when (esc--elixir-p)
    (let ((do-block (esc--enclosing-do-block)))
      (when (and do-block
                 (let ((parent (treesit-node-parent do-block)))
                   (and parent
                        (string= (treesit-node-type parent) "call")
                        (member (esc--call-identifier-text parent)
                                esc--function-call-identifiers)))
                 (esc--do-block-current-child do-block))
        do-block))))

(defun esc--function-do-block-next ()
  "Move to the next named expression within the enclosing function body."
  (let* ((do-block (esc--in-function-do-block-p))
         (current (when do-block (esc--do-block-current-child do-block)))
         (next (when current (treesit-node-next-sibling current t))))
    (if next
        (esc--goto-node next)
      (message "No next form in function body"))))

(defun esc--function-do-block-prev ()
  "Move to the previous named expression within the enclosing function body.
Falls back to the do_block node itself when already at the first expression."
  (let* ((do-block (esc--in-function-do-block-p))
         (current (when do-block (esc--do-block-current-child do-block)))
         (prev (when current (treesit-node-prev-sibling current t))))
    (if prev
        (esc--goto-node prev)
      (when do-block (esc--goto-node do-block)))))

;;; Elixir navigation entry points

(defun esc-elixir-next ()
  "Language-specific forward navigation for Elixir buffers.
Dispatches to the appropriate Elixir structure-aware navigation based on context.
Returns non-nil when navigation was handled, nil to fall back to generic navigation."
  (cond
   ((esc--in-function-do-block-p)  (esc--function-do-block-next) t)
   ((esc--in-navigable-call-p)     (esc--navigable-call-next) t)
   ((esc--in-module-attribute-p)   (esc--module-attribute-next) t)
   ((esc--in-do-block-p)           (esc--do-block-next) t)
   ((esc--in-defmodule-call-p)     (esc--defmodule-next) t)))

(defun esc-elixir-prev ()
  "Language-specific backward navigation for Elixir buffers.
Dispatches to the appropriate Elixir structure-aware navigation based on context.
Returns non-nil when navigation was handled, nil to fall back to generic navigation."
  (cond
   ((esc--in-function-do-block-p)  (esc--function-do-block-prev) t)
   ((esc--in-navigable-call-p)     (esc--navigable-call-prev) t)
   ((esc--in-module-attribute-p)   (esc--module-attribute-prev) t)
   ((esc--in-do-block-p)           (esc--do-block-prev) t)
   ((esc--in-defmodule-call-p)     (esc--defmodule-prev) t)))

;;; Elixir editing helpers

(defun esc--elixir-module-do-block ()
  "Return the module-level `do_block' node enclosing point, or nil.
Walks up from point until it finds a do_block whose parent is a
defmodule call, so function-body do_blocks are not matched."
  (when (esc--elixir-p)
    (let ((node (treesit-node-at (point))))
      (while (and node
                  (not (and (string= (treesit-node-type node) "do_block")
                            (let ((parent (treesit-node-parent node)))
                              (and parent
                                   (string= (treesit-node-type parent) "call")
                                   (equal (esc--call-identifier-text parent)
                                          "defmodule"))))))
        (setq node (treesit-node-parent node)))
      node)))

(defun esc--elixir-current-module-form ()
  "Return the direct named child of the module do_block that contains point.
Returns nil if point is not within any named child of a module-level do_block."
  (when-let ((do-block (esc--elixir-module-do-block)))
    (esc--do-block-current-child do-block)))

(defun esc--elixir-form-indentation (node)
  "Return the indentation string (spaces) used at NODE's start line."
  (save-excursion
    (goto-char (treesit-node-start node))
    (back-to-indentation)
    (make-string (current-column) ?\s)))

;;; Elixir editing operations

(defun esc--elixir-add-method ()
  "Insert a `def' template after the current module-level form.
Places point on the function name placeholder."
  (if-let ((current (esc--elixir-current-module-form)))
      (let* ((indent   (esc--elixir-form-indentation current))
             (end      (treesit-node-end current))
             ;; Offset of the placeholder within the inserted text:
             ;; \n + indent + "def "
             (name-pos (+ end 1 (length indent) (length "def "))))
        (esc--with-edit
         (goto-char end)
         (insert "\n" indent "def function_name do\n"
                 indent "  \n"
                 indent "end")
         (goto-char name-pos)))
    (message "Not in a module-level do block")))

(defun esc--elixir-add-module ()
  "Insert a `defmodule' template after the current module-level form.
Places point on the module name placeholder."
  (if-let ((current (esc--elixir-current-module-form)))
      (let* ((indent   (esc--elixir-form-indentation current))
             (end      (treesit-node-end current))
             ;; \n + indent + "defmodule "
             (name-pos (+ end 1 (length indent) (length "defmodule "))))
        (esc--with-edit
         (goto-char end)
         (insert "\n" indent "defmodule ModuleName do\n"
                 indent "end")
         (goto-char name-pos)))
    (message "Not in a module-level do block")))

(defun esc--elixir-add-attribute ()
  "Insert a module attribute template after the current module-level form.
Places point on the attribute name placeholder."
  (if-let ((current (esc--elixir-current-module-form)))
      (let* ((indent   (esc--elixir-form-indentation current))
             (end      (treesit-node-end current))
             ;; \n + indent + "@"
             (name-pos (+ end 1 (length indent) (length "@"))))
        (esc--with-edit
         (goto-char end)
         (insert "\n" indent "@attribute_name value")
         (goto-char name-pos)))
    (message "Not in a module-level do block")))

(defun esc--elixir-move-form-up ()
  "Swap the current module-level form with its previous sibling."
  (if-let* ((current    (esc--elixir-current-module-form))
            (prev       (treesit-node-prev-sibling current t)))
      (let* ((cur-start  (treesit-node-start current))
             (cur-end    (treesit-node-end current))
             (prev-start (treesit-node-start prev))
             (prev-end   (treesit-node-end prev))
             (cur-text   (buffer-substring-no-properties cur-start cur-end))
             (prev-text  (buffer-substring-no-properties prev-start prev-end))
             (gap        (buffer-substring-no-properties prev-end cur-start)))
        (esc--with-edit
         (delete-region prev-start cur-end)
         (goto-char prev-start)
         (insert cur-text gap prev-text)
         (goto-char prev-start)))
    (message "No previous form to swap with")))

(defun esc--elixir-move-form-down ()
  "Swap the current module-level form with its next sibling."
  (if-let* ((current    (esc--elixir-current-module-form))
            (next       (treesit-node-next-sibling current t)))
      (let* ((cur-start  (treesit-node-start current))
             (cur-end    (treesit-node-end current))
             (next-start (treesit-node-start next))
             (next-end   (treesit-node-end next))
             (cur-text   (buffer-substring-no-properties cur-start cur-end))
             (next-text  (buffer-substring-no-properties next-start next-end))
             (gap        (buffer-substring-no-properties cur-end next-start)))
        (esc--with-edit
         (delete-region cur-start next-end)
         (goto-char cur-start)
         (insert next-text gap cur-text)
         ;; Point lands on the current form in its new position
         (goto-char (+ cur-start (length next-text) (length gap)))))
    (message "No next form to swap with")))

(defun esc--elixir-delete-form ()
  "Delete the current module-level form, including any trailing whitespace line."
  (if-let* ((current  (esc--elixir-current-module-form)))
      (let* ((start     (treesit-node-start current))
             (end       (treesit-node-end current))
             (next      (treesit-node-next-sibling current t))
             (prev      (treesit-node-prev-sibling current t))
             ;; Capture sibling positions before deletion
             (next-pos  (when next (treesit-node-start next)))
             (prev-pos  (when prev (treesit-node-start prev)))
             ;; Consume the trailing newline (and any blank space) after the form
             (del-end   (save-excursion
                          (goto-char end)
                          (if (looking-at "[ \t]*\n")
                              (match-end 0)
                            end))))
        (esc--with-edit
         (delete-region start del-end)
         (cond
          ;; next was after the deleted region: adjust its position leftward
          (next-pos (goto-char (- next-pos (- del-end start))))
          ;; prev was before the deleted region: its position is unchanged
          (prev-pos (goto-char prev-pos)))))
    (message "Not in a module-level do block")))

;;; Elixir editing dispatcher

(defun esc-elixir-edit (operation)
  "Editing handler for Elixir buffers.
Dispatches OPERATION to the appropriate module-context implementation.
Supported operations: `add-method', `add-module', `add-attribute',
`move-up', `move-down', `delete'."
  (pcase operation
    ('add-method    (esc--elixir-add-method))
    ('add-module    (esc--elixir-add-module))
    ('add-attribute (esc--elixir-add-attribute))
    ('move-up       (esc--elixir-move-form-up))
    ('move-down     (esc--elixir-move-form-down))
    ('delete        (esc--elixir-delete-form))
    (_              (message "Unknown editing operation: %s" operation))))

;;; Register Elixir handlers with esc-mode

(esc-register-language-handler 'elixir-ts-mode
                                #'esc-elixir-next
                                #'esc-elixir-prev)

(esc-register-edit-handler 'elixir-ts-mode #'esc-elixir-edit)

(provide 'esc-elixir)
;;; esc-elixir.el ends here
