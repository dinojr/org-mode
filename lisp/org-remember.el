;;; org-remember.el --- Fast note taking in Org-mode

;; Copyright (C) 2004, 2005, 2006, 2007, 2008, 2009
;;   Free Software Foundation, Inc.

;; Author: Carsten Dominik <carsten at orgmode dot org>
;; Keywords: outlines, hypermedia, calendar, wp
;; Homepage: http://orgmode.org
;; Version: 6.27trans
;;
;; This file is part of GNU Emacs.
;;
;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; Commentary:

;; This file contains the system to take fast notes with Org-mode.
;; This system is used together with John Wiegley's `remember.el'.

;;; Code:

(eval-when-compile
  (require 'cl))
(require 'org)

(declare-function remember-mode "remember" ())
(declare-function remember "remember" (&optional initial))
(declare-function remember-buffer-desc "remember" ())
(declare-function remember-finalize "remember" ())
(defvar remember-save-after-remembering)
(defvar remember-register)
(defvar remember-buffer)
(defvar remember-handler-functions)
(defvar remember-annotation-functions)
(defvar org-clock-heading)
(defvar org-clock-heading-for-remember)

(defgroup org-remember nil
  "Options concerning interaction with remember.el."
  :tag "Org Remember"
  :group 'org)

(defcustom org-remember-store-without-prompt t
  "Non-nil means, `C-c C-c' stores remember note without further prompts.
It then uses the file and headline specified by the template or (if the
template does not specify them) by the variables `org-default-notes-file'
and `org-remember-default-headline'.  To force prompting anyway, use
`C-u C-c C-c' to file the note.

When this variable is nil, `C-c C-c' gives you the prompts, and
`C-u C-c C-c' triggers the fasttrack."
  :group 'org-remember
  :type 'boolean)

(defcustom org-remember-interactive-interface 'refile
  "The interface to be used for interactive filing of remember notes.
This is only used when the interactive mode for selecting a filing
location is used (see the variable `org-remember-store-without-prompt').
Allowed values are:
outline                  The interface shows an outline of the relevant file
                         and the correct heading is found by moving through
                         the outline or by searching with incremental search.
outline-path-completion  Headlines in the current buffer are offered via
                         completion.
refile                   Use the refile interface, and offer headlines,
                         possibly from different buffers."
  :group 'org-remember
  :type '(choice
	  (const :tag "Refile" refile)
	  (const :tag "Outline" outline)
	  (const :tag "Outline-path-completion" outline-path-completion)))

(defcustom org-remember-default-headline ""
  "The headline that should be the default location in the notes file.
When filing remember notes, the cursor will start at that position.
You can set this on a per-template basis with the variable
`org-remember-templates'."
  :group 'org-remember
  :type 'string)

(defcustom org-remember-templates nil
  "Templates for the creation of remember buffers.
When nil, just let remember make the buffer.
When non-nil, this is a list of 5-element lists.  In each entry, the first
element is the name of the template, which should be a single short word.
The second element is a character, a unique key to select this template.
The third element is the template.

The fourth element is optional and can specify a destination file for
remember items created with this template.  The default file is given
by `org-default-notes-file'.  If the file name is not an absolute path,
it will be interpreted relative to `org-directory'.

An optional fifth element can specify the headline in that file that should
be offered first when the user is asked to file the entry.  The default
headline is given in the variable `org-remember-default-headline'.  When
this element is `top' or `bottom', the note will be placed as a level-1
entry at the beginning or end of the file, respectively.

An optional sixth element specifies the contexts in which the template
will be offered to the user.  This element can be a list of major modes
or a function, and the template will only be offered if `org-remember'
is called from a mode in the list, or if the function returns t.
Templates that specify t or nil for the context will be always be added
to the list of selectable templates.

The template specifies the structure of the remember buffer.  It should have
a first line starting with a star, to act as the org-mode headline.
Furthermore, the following %-escapes will be replaced with content:

  %^{prompt}  Prompt the user for a string and replace this sequence with it.
              A default value and a completion table ca be specified like this:
              %^{prompt|default|completion2|completion3|...}
  %t          time stamp, date only
  %T          time stamp with date and time
  %u, %U      like the above, but inactive time stamps
  %^t         like %t, but prompt for date.  Similarly %^T, %^u, %^U.
              You may define a prompt like %^{Please specify birthday
  %n          user name (taken from `user-full-name')
  %a          annotation, normally the link created with org-store-link
  %i          initial content, the region active.  If %i is indented,
              the entire inserted text will be indented as well.
  %c          current kill ring head
  %x          content of the X clipboard
  %^C         Interactive selection of which kill or clip to use
  %^L         Like %^C, but insert as link
  %k          title of currently clocked task
  %K          link to currently clocked task
  %^g         prompt for tags, with completion on tags in target file
  %^G         prompt for tags, with completion all tags in all agenda files
  %^{prop}p   Prompt the user for a value for property `prop'
  %:keyword   specific information for certain link types, see below
  %[pathname] insert the contents of the file given by `pathname'
  %(sexp)     evaluate elisp `(sexp)' and replace with the result
  %!          Store this note immediately after filling the template
  %&          Visit note immediately after storing it

  %?          After completing the template, position cursor here.

Apart from these general escapes, you can access information specific to the
link type that is created.  For example, calling `remember' in emails or gnus
will record the author and the subject of the message, which you can access
with %:author and %:subject, respectively.  Here is a complete list of what
is recorded for each link type.

Link type          |  Available information
-------------------+------------------------------------------------------
bbdb               |  %:type %:name %:company
vm, wl, mh, rmail  |  %:type %:subject %:message-id
                   |  %:from %:fromname %:fromaddress
                   |  %:to   %:toname   %:toaddress
                   |  %:fromto (either \"to NAME\" or \"from NAME\")
gnus               |  %:group, for messages also all email fields
w3, w3m            |  %:type %:url
info               |  %:type %:file %:node
calendar           |  %:type %:date"
  :group 'org-remember
  :get (lambda (var) ; Make sure all entries have at least 5 elements
	 (mapcar (lambda (x)
		   (if (not (stringp (car x))) (setq x (cons "" x)))
		   (cond ((= (length x) 4) (append x '(nil)))
			 ((= (length x) 3) (append x '(nil nil)))
			 (t x)))
		 (default-value var)))
  :type '(repeat
	  :tag "enabled"
	  (list :value ("" ?a "\n" nil nil nil)
		(string :tag "Name")
		(character :tag "Selection Key")
		(string :tag "Template")
		(choice :tag "Destination file"
		 (file :tag "Specify")
		 (function :tag "Function")
		 (const :tag "Use `org-default-notes-file'" nil))
		(choice :tag "Destin. headline"
		 (string :tag "Specify")
		 (const :tag "Use `org-remember-default-headline'" nil)
		 (const :tag "At beginning of file" top)
		 (const :tag "At end of file" bottom))
		(choice :tag "Context"
		 (const :tag "Use in all contexts" nil)
		 (const :tag "Use in all contexts" t)
		 (repeat :tag "Use only if in major mode"
			 (symbol :tag "Major mode"))
		 (function :tag "Perform a check against function")))))

(defcustom org-remember-before-finalize-hook nil
  "Hook that is run right before a remember process is finalized.
The remember buffer is still current when this hook runs."
  :group 'org-remember
  :type 'hook)

(defvar org-remember-mode-map (make-sparse-keymap)
  "Keymap for org-remember-mode, a minor mode.
Use this map to set additional keybindings for when Org-mode is used
for a Remember buffer.")
(defvar org-remember-mode-hook nil
  "Hook for the minor `org-remember-mode'.")

(define-minor-mode org-remember-mode
  "Minor mode for special key bindings in a remember buffer."
  nil " Rem" org-remember-mode-map
  (run-hooks 'org-remember-mode-hook))
(define-key org-remember-mode-map "\C-c\C-c" 'org-remember-finalize)
(define-key org-remember-mode-map "\C-c\C-k" 'org-remember-kill)

(defcustom org-remember-clock-out-on-exit 'query
  "Non-nil means, stop the clock when exiting a clocking remember buffer.
This only applies if the clock is running in the remember buffer.  If the
clock is not stopped, it continues to run in the storage location.
Instead of nil or t, this may also be the symbol `query' to prompt the
user each time a remember buffer with a running clock is filed away.  "
  :group 'org-remember
  :type '(choice
	  (const :tag "Never" nil)
	  (const :tag "Always" t)
	  (const :tag "Query user" query)))

(defcustom org-remember-backup-directory nil
  "Directory where to store all remember buffers, for backup purposes.
After a remember buffer has been stored successfully, the backup file
will be removed.  However, if you forget to finish the remember process,
the file will remain there.
See also `org-remember-auto-remove-backup-files'."
  :group 'org-remember
  :type '(choice
	  (const :tag "No backups" nil)
	  (directory :tag "Directory")))

(defcustom org-remember-auto-remove-backup-files t
  "Non-nil means, remove remember backup files after successfully storage.
When remember is finished successfully, with storing the note at the
desired target, remove the backup files related to this remember process
and show a message about remaining backup files, from previous, unfinished
remember sessions.
Backup files will only be made at all, when `org-remember-backup-directory'
is set."
  :group 'org-remember
  :type 'boolean)

(defvar annotation) ; from remember.el, dynamically scoped in `remember-mode'
(defvar initial)    ; from remember.el, dynamically scoped in `remember-mode'

;;;###autoload
(defun org-remember-insinuate ()
  "Setup remember.el for use with Org-mode."
  (org-require-remember)
  (setq remember-annotation-functions '(org-remember-annotation))
  (setq remember-handler-functions '(org-remember-handler))
  (add-hook 'remember-mode-hook 'org-remember-apply-template))

;;;###autoload
(defun org-remember-annotation ()
  "Return a link to the current location as an annotation for remember.el.
If you are using Org-mode files as target for data storage with
remember.el, then the annotations should include a link compatible with the
conventions in Org-mode.  This function returns such a link."
  (org-store-link nil))

(defconst org-remember-help
"Select a destination location for the note.
UP/DOWN=headline   TAB=cycle visibility  [Q]uit   RET/<left>/<right>=Store
RET on headline   -> Store as sublevel entry to current headline
RET at beg-of-buf -> Append to file as level 2 headline
<left>/<right>    -> before/after current headline, same headings level")

(defvar org-jump-to-target-location nil)
(defvar org-remember-previous-location nil)
(defvar org-force-remember-template-char) ;; dynamically scoped

;; Save the major mode of the buffer we called remember from
(defvar org-select-template-temp-major-mode nil)

;; Temporary store the buffer where remember was called from
(defvar org-select-template-original-buffer nil)

(defun org-select-remember-template (&optional use-char)
  (when org-remember-templates
    (let* ((pre-selected-templates
	    (mapcar
	     (lambda (tpl)
	       (let ((ctxt (nth 5 tpl))
		     (mode org-select-template-temp-major-mode)
		     (buf org-select-template-original-buffer))
		 (and (or (not ctxt) (eq ctxt t)
			  (and (listp ctxt) (memq mode ctxt))
			  (and (functionp ctxt)
			       (with-current-buffer buf
				 ;; Protect the user-defined function from error
				 (condition-case nil (funcall ctxt) (error nil)))))
		      tpl)))
	     org-remember-templates))
	   ;; If no template at this point, add the default templates:
	   (pre-selected-templates1
	    (if (not (delq nil pre-selected-templates))
		(mapcar (lambda(x) (if (not (nth 5 x)) x))
			org-remember-templates)
	      pre-selected-templates))
	   ;; Then unconditionally add template for any contexts
	   (pre-selected-templates2
	    (append (mapcar (lambda(x) (if (eq (nth 5 x) t) x))
			    org-remember-templates)
		    (delq nil pre-selected-templates1)))
	   (templates (mapcar (lambda (x)
				(if (stringp (car x))
				    (append (list (nth 1 x) (car x)) (cddr x))
				  (append (list (car x) "") (cdr x))))
			      (delq nil pre-selected-templates2)))
	   msg
	   (char (or use-char
		     (cond
		      ((= (length templates) 1)
		       (caar templates))
		      ((and (boundp 'org-force-remember-template-char)
			    org-force-remember-template-char)
		       (if (stringp org-force-remember-template-char)
			   (string-to-char org-force-remember-template-char)
			 org-force-remember-template-char))
		      (t
		       (setq msg (format
				  "Select template: %s"
				  (mapconcat
				   (lambda (x)
				     (cond
				      ((not (string-match "\\S-" (nth 1 x)))
				       (format "[%c]" (car x)))
				      ((equal (downcase (car x))
					      (downcase (aref (nth 1 x) 0)))
				       (format "[%c]%s" (car x)
					       (substring (nth 1 x) 1)))
				      (t (format "[%c]%s" (car x) (nth 1 x)))))
				   templates " ")))
		       (let ((inhibit-quit t) char0)
			 (while (not char0)
			   (message msg)
			   (setq char0 (read-char-exclusive))
			   (when (and (not (assoc char0 templates))
				      (not (equal char0 ?\C-g)))
			     (message "No suche template \"%c\"" char0)
			     (ding) (sit-for 1)
			     (setq char0 nil)))
			 (when (equal char0 ?\C-g)
			   (jump-to-register remember-register)
			   (kill-buffer remember-buffer)
			   (error "Abort"))
			 char0))))))
      (cddr (assoc char templates)))))

(defun org-get-x-clipboard (value)
  "Get the value of the x clipboard, compatible with XEmacs, and GNU Emacs 21."
  (if (eq window-system 'x)
      (let ((x (org-get-x-clipboard-compat value)))
	(if x (org-no-properties x)))))

;;;###autoload
(defun org-remember-apply-template (&optional use-char skip-interactive)
  "Initialize *remember* buffer with template, invoke `org-mode'.
This function should be placed into `remember-mode-hook' and in fact requires
to be run from that hook to function properly."
  (when (and (boundp 'initial) (stringp initial))
    (setq initial (org-no-properties initial))
    (remove-text-properties 0 (length initial) '(read-only t) initial))
  (if org-remember-templates
      (let* ((entry (org-select-remember-template use-char))
	     (ct (or org-overriding-default-time (org-current-time)))
	     (dct (decode-time ct))
	     (ct1
	      (if (< (nth 2 dct) org-extend-today-until)
		  (encode-time 0 59 23 (1- (nth 3 dct)) (nth 4 dct) (nth 5 dct))
		ct))
	     (tpl (car entry))
	     (plist-p (if org-store-link-plist t nil))
	     (file (if (and (nth 1 entry)
			    (or (and (stringp (nth 1 entry))
				     (string-match "\\S-" (nth 1 entry)))
				(functionp (nth 1 entry))))
		       (nth 1 entry)
		     org-default-notes-file))
	     (headline (nth 2 entry))
	     (v-c (and (> (length kill-ring) 0) (current-kill 0)))
	     (v-x (or (org-get-x-clipboard 'PRIMARY)
		      (org-get-x-clipboard 'CLIPBOARD)
		      (org-get-x-clipboard 'SECONDARY)))
	     (v-t (format-time-string (car org-time-stamp-formats) ct))
	     (v-T (format-time-string (cdr org-time-stamp-formats) ct))
	     (v-u (concat "[" (substring v-t 1 -1) "]"))
	     (v-U (concat "[" (substring v-T 1 -1) "]"))
	     ;; `initial' and `annotation' are bound in `remember'.
	     ;; But if the property list has them, we prefer those values
	     (v-i (or (plist-get org-store-link-plist :initial)
		      (and (boundp 'initial) initial)
		      ""))
	     (v-a (or (plist-get org-store-link-plist :annotation)
		      (and (boundp 'annotation) annotation)
		      ""))
	     ;; Is the link empty?  Then we do not want it...
	     (v-a (if (equal v-a "[[]]") "" v-a))
	     (clipboards (remove nil (list v-i
					   (org-get-x-clipboard 'PRIMARY)
					   (org-get-x-clipboard 'CLIPBOARD)
					   (org-get-x-clipboard 'SECONDARY)
					   v-c)))
	     (v-A (if (and v-a
			   (string-match "\\[\\(\\[.*?\\]\\)\\(\\[.*?\\]\\)?\\]" v-a))
		      (replace-match "[\\1[%^{Link description}]]" nil nil v-a)
		    v-a))
	     (v-n user-full-name)
	     (v-k (if (marker-buffer org-clock-marker)
		      (org-substring-no-properties org-clock-heading)))
	     (v-K (if (marker-buffer org-clock-marker)
		      (org-make-link-string
		       (buffer-file-name (marker-buffer org-clock-marker))
		       org-clock-heading)))
	     v-I
	     (org-startup-folded nil)
	     (org-inhibit-startup t)
	     org-time-was-given org-end-time-was-given x
	     prompt completions char time pos default histvar)

	(when (functionp file)
	  (setq file (funcall file)))
	(when (and file (not (file-name-absolute-p file)))
	  (setq file (expand-file-name file org-directory)))

	(setq org-store-link-plist
	      (plist-put org-store-link-plist :annotation v-a)
	      org-store-link-plist
	      (plist-put org-store-link-plist :initial v-i))

	(unless tpl (setq tpl "") (message "No template") (ding) (sit-for 1))
	(erase-buffer)
	(insert (substitute-command-keys
		 (format
"## %s  \"%s\" -> \"* %s\"
## C-u C-c C-c  like C-c C-c, and immediately visit note at target location
## C-0 C-c C-c  \"%s\" -> \"* %s\"
## %s  to select file and header location interactively.
## C-2 C-c C-c  as child of the currently clocked item
## To switch templates, use `\\[org-remember]'.  To abort use `C-c C-k'.\n\n"
		  (if org-remember-store-without-prompt "    C-c C-c" "    C-1 C-c C-c")
		  (abbreviate-file-name (or file org-default-notes-file))
		  (or headline "")
		  (or (car org-remember-previous-location) "???")
		  (or (cdr org-remember-previous-location) "???")
		  (if org-remember-store-without-prompt "C-1 C-c C-c" "        C-c C-c"))))
	(insert tpl)
	(goto-char (point-min))

	;; Simple %-escapes
	(while (re-search-forward "%\\([tTuUaiAcxkKI]\\)" nil t)
	  (when (and initial (equal (match-string 0) "%i"))
	    (save-match-data
	      (let* ((lead (buffer-substring
			    (point-at-bol) (match-beginning 0))))
		(setq v-i (mapconcat 'identity
				     (org-split-string initial "\n")
				     (concat "\n" lead))))))
	  (replace-match
	   (or (eval (intern (concat "v-" (match-string 1)))) "")
	   t t))

	;; %[] Insert contents of a file.
	(goto-char (point-min))
	(while (re-search-forward "%\\[\\(.+\\)\\]" nil t)
	  (let ((start (match-beginning 0))
		(end (match-end 0))
		(filename (expand-file-name (match-string 1))))
	    (goto-char start)
	    (delete-region start end)
	    (condition-case error
		(insert-file-contents filename)
	      (error (insert (format "%%![Couldn't insert %s: %s]"
				     filename error))))))
	;; %() embedded elisp
	(goto-char (point-min))
	(while (re-search-forward "%\\((.+)\\)" nil t)
	  (goto-char (match-beginning 0))
	  (let ((template-start (point)))
	    (forward-char 1)
	    (let ((result
		   (condition-case error
		       (eval (read (current-buffer)))
		     (error (format "%%![Error: %s]" error)))))
	      (delete-region template-start (point))
	      (insert result))))

	;; From the property list
	(when plist-p
	  (goto-char (point-min))
	  (while (re-search-forward "%\\(:[-a-zA-Z]+\\)" nil t)
	    (and (setq x (or (plist-get org-store-link-plist
					(intern (match-string 1))) ""))
		 (replace-match x t t))))

	;; Turn on org-mode in the remember buffer, set local variables
	(let ((org-inhibit-startup t)) (org-mode) (org-remember-mode 1))
	(if (and file (string-match "\\S-" file) (not (file-directory-p file)))
	    (org-set-local 'org-default-notes-file file))
	(if headline
	    (org-set-local 'org-remember-default-headline headline))
	;; Interactive template entries
	(goto-char (point-min))
	(while (re-search-forward "%^\\({\\([^}]*\\)}\\)?\\([gGtTuUCLp]\\)?" nil t)
	  (setq char (if (match-end 3) (match-string 3))
		prompt (if (match-end 2) (match-string 2)))
	  (goto-char (match-beginning 0))
	  (replace-match "")
	  (setq completions nil default nil)
	  (when prompt
	    (setq completions (org-split-string prompt "|")
		  prompt (pop completions)
		  default (car completions)
		  histvar (intern (concat
				   "org-remember-template-prompt-history::"
				   (or prompt "")))
		  completions (mapcar 'list completions)))
	  (cond
	   ((member char '("G" "g"))
	    (let* ((org-last-tags-completion-table
		    (org-global-tags-completion-table
		     (if (equal char "G") (org-agenda-files) (and file (list file)))))
		   (org-add-colon-after-tag-completion t)
		   (ins (org-ido-completing-read
			 (if prompt (concat prompt ": ") "Tags: ")
			 'org-tags-completion-function nil nil nil
			 'org-tags-history)))
	      (setq ins (mapconcat 'identity
				  (org-split-string ins (org-re "[^[:alnum:]_@]+"))
				  ":"))
	      (when (string-match "\\S-" ins)
		(or (equal (char-before) ?:) (insert ":"))
		(insert ins)
		(or (equal (char-after) ?:) (insert ":")))))
	   ((equal char "C")
	    (cond ((= (length clipboards) 1) (insert (car clipboards)))
		  ((> (length clipboards) 1)
		   (insert (read-string "Clipboard/kill value: "
					(car clipboards) '(clipboards . 1)
					(car clipboards))))))
	   ((equal char "L")
	    (cond ((= (length clipboards) 1)
		   (org-insert-link 0 (car clipboards)))
		  ((> (length clipboards) 1)
		   (org-insert-link 0 (read-string "Clipboard/kill value: "
						   (car clipboards)
						   '(clipboards . 1)
						   (car clipboards))))))
	   ((equal char "p")
	    (let*
		((prop (org-substring-no-properties prompt))
		 (pall (concat prop "_ALL"))
		 (allowed
		  (with-current-buffer
		      (get-buffer (file-name-nondirectory file))
		    (or (cdr (assoc pall org-file-properties))
			(cdr (assoc pall org-global-properties))
			(cdr (assoc pall org-global-properties-fixed)))))
		 (existing (with-current-buffer
			       (get-buffer (file-name-nondirectory file))
			     (mapcar 'list (org-property-values prop))))
		 (propprompt (concat "Value for " prop ": "))
		 (val (if allowed
			  (org-completing-read
			   propprompt
			   (mapcar 'list (org-split-string allowed "[ \t]+"))
			   nil 'req-match)
			(org-completing-read-no-ido propprompt existing nil nil
					     "" nil ""))))
	      (org-set-property prop val)))
	   (char
	    ;; These are the date/time related ones
	    (setq org-time-was-given (equal (upcase char) char))
	    (setq time (org-read-date (equal (upcase char) "U") t nil
				      prompt))
	    (org-insert-time-stamp time org-time-was-given
				   (member char '("u" "U"))
				   nil nil (list org-end-time-was-given)))
	   (t
	    (let (org-completion-use-ido)
	      (insert (org-completing-read-no-ido
		       (concat (if prompt prompt "Enter string")
			       (if default (concat " [" default "]"))
			       ": ")
		       completions nil nil nil histvar default))))))
	(goto-char (point-min))
	(if (re-search-forward "%\\?" nil t)
	    (replace-match "")
	  (and (re-search-forward "^[^#\n]" nil t) (backward-char 1))))
    (let ((org-inhibit-startup t)) (org-mode) (org-remember-mode 1)))
  (when (save-excursion
	  (goto-char (point-min))
	  (re-search-forward "%&" nil t))
    (replace-match "")
    (org-set-local 'org-jump-to-target-location t))
  (when org-remember-backup-directory
    (unless (file-directory-p org-remember-backup-directory)
      (make-directory org-remember-backup-directory))
    (org-set-local 'auto-save-file-name-transforms nil)
    (setq buffer-file-name
	  (expand-file-name
	   (format-time-string "remember-%Y-%m-%d-%H-%M-%S")
	   org-remember-backup-directory))
    (save-buffer)
    (org-set-local 'auto-save-visited-file-name t)
    (auto-save-mode 1))
  (when (save-excursion
	  (goto-char (point-min))
	  (re-search-forward "%!" nil t))
    (replace-match "")
    (add-hook 'post-command-hook 'org-remember-finish-immediately 'append)))

(defun org-remember-finish-immediately ()
  "File remember note immediately.
This should be run in `post-command-hook' and will remove itself
from that hook."
  (remove-hook 'post-command-hook 'org-remember-finish-immediately)
  (org-remember-finalize))

(defun org-remember-visit-immediately ()
  "File remember note immediately.
This should be run in `post-command-hook' and will remove itself
from that hook."
  (org-remember '(16))
  (goto-char (or (text-property-any
		  (point) (save-excursion (org-end-of-subtree t t))
		  'org-position-cursor t)
		 (point)))
  (message "%s"
	   (format
	    (substitute-command-keys
	     "Restore window configuration with \\[jump-to-register] %c")
	    remember-register)))

(defvar org-clock-marker) ; Defined in org.el
(defun org-remember-finalize ()
  "Finalize the remember process."
  (interactive)
  (unless org-remember-mode
    (error "This does not seem to be a remember buffer for Org-mode"))
  (run-hooks 'org-remember-before-finalize-hook)
  (unless (fboundp 'remember-finalize)
    (defalias 'remember-finalize 'remember-buffer))
  (when (and org-clock-marker
	     (equal (marker-buffer org-clock-marker) (current-buffer)))
    ;; the clock is running in this buffer.
    (when (and (equal (marker-buffer org-clock-marker) (current-buffer))
	       (or (eq org-remember-clock-out-on-exit t)
		   (and org-remember-clock-out-on-exit
			(y-or-n-p "The clock is running in this buffer.  Clock out now? "))))
      (let (org-log-note-clock-out) (org-clock-out))))
  (when buffer-file-name
    (save-buffer))
  (remember-finalize))

(defun org-remember-kill ()
  "Abort the current remember process."
  (interactive)
  (let ((org-note-abort t))
    (org-remember-finalize)))

;;;###autoload
(defun org-remember (&optional goto org-force-remember-template-char)
  "Call `remember'.  If this is already a remember buffer, re-apply template.
If there is an active region, make sure remember uses it as initial content
of the remember buffer.

When called interactively with a `C-u' prefix argument GOTO, don't remember
anything, just go to the file/headline where the selected template usually
stores its notes.  With a double prefix arg `C-u C-u', go to the last
note stored by remember.

Lisp programs can set ORG-FORCE-REMEMBER-TEMPLATE-CHAR to a character
associated with a template in `org-remember-templates'."
  (interactive "P")
  (org-require-remember)
  (cond
   ((equal goto '(4)) (org-go-to-remember-target))
   ((equal goto '(16)) (org-remember-goto-last-stored))
   (t
    ;; set temporary variables that will be needed in
    ;; `org-select-remember-template'
    (setq org-select-template-temp-major-mode major-mode)
    (setq org-select-template-original-buffer (current-buffer))
    (if org-remember-mode
	(progn
	  (when (< (length org-remember-templates) 2)
	    (error "No other template available"))
	  (erase-buffer)
	  (let ((annotation (plist-get org-store-link-plist :annotation))
		(initial (plist-get org-store-link-plist :initial)))
	    (org-remember-apply-template))
	  (message "Press C-c C-c to remember data"))
      (if (org-region-active-p)
	  (org-do-remember (buffer-substring (point) (mark)))
	(org-do-remember))))))

(defvar org-remember-last-stored-marker (make-marker)
  "Marker pointing to the entry most recently stored with `org-remember'.")

(defun org-remember-goto-last-stored ()
  "Go to the location where the last remember note was stored."
  (interactive)
  (org-goto-marker-or-bmk org-remember-last-stored-marker
			  "org-remember-last-stored")
  (message "This is the last note stored by remember"))

(defun org-go-to-remember-target (&optional template-key)
  "Go to the target location of a remember template.
The user is queried for the template."
  (interactive)
  (let* (org-select-template-temp-major-mode
	 (entry (org-select-remember-template template-key))
	 (file (nth 1 entry))
	 (heading (nth 2 entry))
	 visiting)
    (unless (and file (stringp file) (string-match "\\S-" file))
      (setq file org-default-notes-file))
    (when (and file (not (file-name-absolute-p file)))
      (setq file (expand-file-name file org-directory)))
    (unless (and heading (stringp heading) (string-match "\\S-" heading))
      (setq heading org-remember-default-headline))
    (setq visiting (org-find-base-buffer-visiting file))
    (if (not visiting) (find-file-noselect file))
    (switch-to-buffer (or visiting (get-file-buffer file)))
    (widen)
    (goto-char (point-min))
    (if (re-search-forward
	 (concat "^\\*+[ \t]+" (regexp-quote heading)
		 (org-re "\\([ \t]+:[[:alnum:]@_:]*\\)?[ \t]*$"))
	 nil t)
	(goto-char (match-beginning 0))
      (error "Target headline not found: %s" heading))))

;;;###autoload
(defun org-remember-handler ()
  "Store stuff from remember.el into an org file.
When the template has specified a file and a headline, the entry is filed
there, or in the location defined by `org-default-notes-file' and
`org-remember-default-headline'.

If no defaults have been defined, or if the current prefix argument
is 1 (so you must use `C-1 C-c C-c' to exit remember), an interactive
process is used to select the target location.

When the prefix is 0 (i.e. when remember is exited with `C-0 C-c C-c'),
the entry is filed to the same location as the previous note.

When the prefix is 2 (i.e. when remember is exited with `C-2 C-c C-c'),
the entry is filed as a subentry of the entry where the clock is
currently running.

When `C-u' has been used as prefix argument, the note is stored and emacs
moves point to the new location of the note, so that editing can be
continued there (similar to inserting \"%&\" into the template).

Before storing the note, the function ensures that the text has an
org-mode-style headline, i.e. a first line that starts with
a \"*\".  If not, a headline is constructed from the current date and
some additional data.

If the variable `org-adapt-indentation' is non-nil, the entire text is
also indented so that it starts in the same column as the headline
\(i.e. after the stars).

See also the variable `org-reverse-note-order'."
  (when (and (equal current-prefix-arg 2)
	     (not (marker-buffer org-clock-marker)))
    (error "No running clock"))
  (when (org-bound-and-true-p org-jump-to-target-location)
    (let* ((end (min (point-max) (1+ (point))))
	   (beg (point)))
      (if (= end beg) (setq beg (1- beg)))
      (put-text-property beg end 'org-position-cursor t)))
  (goto-char (point-min))
  (while (looking-at "^[ \t]*\n\\|^##.*\n")
    (replace-match ""))
  (goto-char (point-max))
  (beginning-of-line 1)
  (while (looking-at "[ \t]*$\\|##.*")
    (delete-region (1- (point)) (point-max))
    (beginning-of-line 1))
  (catch 'quit
    (if org-note-abort (throw 'quit nil))
    (let* ((visitp (org-bound-and-true-p org-jump-to-target-location))
	   (backup-file
	    (and buffer-file-name
		 (equal (file-name-directory buffer-file-name)
			(file-name-as-directory
			 (expand-file-name org-remember-backup-directory)))
		 (string-match "^remember-[0-9]\\{4\\}"
			       (file-name-nondirectory buffer-file-name))
		 buffer-file-name))
	   (previousp (and (member current-prefix-arg '((16) 0))
			   org-remember-previous-location))
	   (clockp (equal current-prefix-arg 2))
	   (fastp (org-xor (equal current-prefix-arg 1)
			   org-remember-store-without-prompt))
	   (file (cond
		  (fastp org-default-notes-file)
		  ((and (eq org-remember-interactive-interface 'refile)
			org-refile-targets)
		   org-default-notes-file)
		  ((not previousp)
		   (org-get-org-file))))
	   (heading org-remember-default-headline)
	   (visiting (and file (org-find-base-buffer-visiting file)))
	   (org-startup-folded nil)
	   (org-startup-align-all-tables nil)
	   (org-goto-start-pos 1)
	   spos exitcmd level reversed txt text-before-node-creation)
      (when (equal current-prefix-arg '(4))
	(setq visitp t))
      (when previousp
	(setq file (car org-remember-previous-location)
	      visiting (and file (org-find-base-buffer-visiting file))
	      heading (cdr org-remember-previous-location)
	      fastp t))
      (when clockp
	(setq file (buffer-file-name (marker-buffer org-clock-marker))
	      visiting (and file (org-find-base-buffer-visiting file))
	      heading org-clock-heading-for-remember
	      fastp t))
      (setq current-prefix-arg nil)
      ;; Modify text so that it becomes a nice subtree which can be inserted
      ;; into an org tree.
      (goto-char (point-min))
      (if (re-search-forward "[ \t\n]+\\'" nil t)
	  ;; remove empty lines at end
	  (replace-match ""))
      (goto-char (point-min))
      (unless (looking-at org-outline-regexp)
	;; add a headline
	(setq text-before-node-creation (buffer-string))
	(insert (concat "* " (current-time-string)
			" (" (remember-buffer-desc) ")\n"))
	(backward-char 1)
	(when org-adapt-indentation
	  (while (re-search-forward "^" nil t)
	    (insert "  "))))
      (goto-char (point-min))
      (if (re-search-forward "\n[ \t]*\n[ \t\n]*\\'" nil t)
	  (replace-match "\n\n")
	(if (re-search-forward "[ \t\n]*\\'")
	    (replace-match "\n")))
      (goto-char (point-min))
      (setq txt (buffer-string))
      (org-save-markers-in-region (point-min) (point-max))
      (set-buffer-modified-p nil)
      (when (and (eq org-remember-interactive-interface 'refile)
		 (not fastp))
	(org-refile nil (or visiting (find-file-noselect file)))
	(and visitp (run-with-idle-timer 0.01 nil 'org-remember-visit-immediately))
	(save-excursion
	  (bookmark-jump "org-refile-last-stored")
	  (bookmark-set "org-remember-last-stored")
	  (move-marker org-remember-last-stored-marker (point)))
	(throw 'quit t))
      ;; Find the file
      (with-current-buffer (or visiting (find-file-noselect file))
	(unless (or (org-mode-p) (member heading '(top bottom)))
	  (error "Target files for notes must be in Org-mode if not filing to top/bottom"))
	(save-excursion
	  (save-restriction
	    (widen)
	    (setq reversed (org-notes-order-reversed-p))

	    ;; Find the default location
	    (when heading
	      (cond
	       ((not (org-mode-p))
		(if (eq heading 'top)
		    (goto-char (point-min))
		  (goto-char (point-max))
		  (or (bolp) (newline)))
		(insert text-before-node-creation)
		(when remember-save-after-remembering
		  (save-buffer)
		  (if (not visiting) (kill-buffer (current-buffer))))
		(throw 'quit t))
	       ((eq heading 'top)
		(goto-char (point-min))
		(or (looking-at org-outline-regexp)
		    (re-search-forward org-outline-regexp nil t))
		(setq org-goto-start-pos (or (match-beginning 0) (point-min))))
	       ((eq heading 'bottom)
		(goto-char (point-max))
		(or (bolp) (newline))
		(setq org-goto-start-pos (point)))
	       ((and (stringp heading) (string-match "\\S-" heading))
		(goto-char (point-min))
		(if (re-search-forward
		     (concat "^\\*+[ \t]+" (regexp-quote heading)
			     (org-re "\\([ \t]+:[[:alnum:]@_:]*\\)?[ \t]*$"))
		     nil t)
		    (setq org-goto-start-pos (match-beginning 0))
		  (when fastp
		    (goto-char (point-max))
		    (unless (bolp) (newline))
		    (insert "* " heading "\n")
		    (setq org-goto-start-pos (point-at-bol 0)))))
	       (t (goto-char (point-min)) (setq org-goto-start-pos (point)
						heading 'top))))

	    ;; Ask the User for a location, using the appropriate interface
	    (cond
	     ((and fastp (memq heading '(top bottom)))
	      (setq spos org-goto-start-pos
			  exitcmd (if (eq heading 'top) 'left nil)))
	     (fastp (setq spos org-goto-start-pos
			  exitcmd 'return))
	     ((eq org-remember-interactive-interface 'outline)
	      (setq spos (org-get-location (current-buffer)
					   org-remember-help)
		    exitcmd (cdr spos)
		    spos (car spos)))
	     ((eq org-remember-interactive-interface 'outline-path-completion)
	      (let ((org-refile-targets '((nil . (:maxlevel . 10))))
		    (org-refile-use-outline-path t))
		(setq spos (org-refile-get-location "Heading: ")
		      exitcmd 'return
		      spos (nth 3 spos))))
	     (t (error "This should not happen")))
	    (if (not spos) (throw 'quit nil)) ; return nil to show we did
					; not handle this note
	    (and visitp (run-with-idle-timer 0.01 nil 'org-remember-visit-immediately))
	    (goto-char spos)
	    (cond ((org-on-heading-p t)
		   (org-back-to-heading t)
		   (setq level (funcall outline-level))
		   (cond
		    ((eq exitcmd 'return)
		     ;; sublevel of current
		     (setq org-remember-previous-location
			   (cons (abbreviate-file-name file)
				 (org-get-heading 'notags)))
		     (if reversed
			 (outline-next-heading)
		       (org-end-of-subtree t)
		       (if (not (bolp))
			   (if (looking-at "[ \t]*\n")
			       (beginning-of-line 2)
			     (end-of-line 1)
			     (insert "\n"))))
		     (org-paste-subtree (org-get-valid-level level 1) txt)
		     (and org-auto-align-tags (org-set-tags nil t))
		     (bookmark-set "org-remember-last-stored")
		     (move-marker org-remember-last-stored-marker (point)))
		    ((eq exitcmd 'left)
		     ;; before current
		     (org-paste-subtree level txt)
		     (and org-auto-align-tags (org-set-tags nil t))
		     (bookmark-set "org-remember-last-stored")
		     (move-marker org-remember-last-stored-marker (point)))
		    ((eq exitcmd 'right)
		     ;; after current
		     (org-end-of-subtree t)
		     (org-paste-subtree level txt)
		     (and org-auto-align-tags (org-set-tags nil t))
		     (bookmark-set "org-remember-last-stored")
		     (move-marker org-remember-last-stored-marker (point)))
		    (t (error "This should not happen"))))

		  ((eq heading 'bottom)
		   (org-paste-subtree 1 txt)
		   (and org-auto-align-tags (org-set-tags nil t))
		   (bookmark-set "org-remember-last-stored")
		   (move-marker org-remember-last-stored-marker (point)))

		  ((and (bobp) (not reversed))
		   ;; Put it at the end, one level below level 1
		   (save-restriction
		     (widen)
		     (goto-char (point-max))
		     (if (not (bolp)) (newline))
		     (org-paste-subtree (org-get-valid-level 1 1) txt)
		     (and org-auto-align-tags (org-set-tags nil t))
		     (bookmark-set "org-remember-last-stored")
		     (move-marker org-remember-last-stored-marker (point))))

		  ((and (bobp) reversed)
		   ;; Put it at the start, as level 1
		   (save-restriction
		     (widen)
		     (goto-char (point-min))
		     (re-search-forward "^\\*+ " nil t)
		     (beginning-of-line 1)
		     (org-paste-subtree 1 txt)
		     (and org-auto-align-tags (org-set-tags nil t))
		     (bookmark-set "org-remember-last-stored")
		     (move-marker org-remember-last-stored-marker (point))))
		  (t
		   ;; Put it right there, with automatic level determined by
		   ;; org-paste-subtree or from prefix arg
		   (org-paste-subtree
		    (if (numberp current-prefix-arg) current-prefix-arg)
		    txt)
		   (and org-auto-align-tags (org-set-tags nil t))
		   (bookmark-set "org-remember-last-stored")
		   (move-marker org-remember-last-stored-marker (point))))

	    (when remember-save-after-remembering
	      (save-buffer)
	      (if (and (not visiting)
		       (not (equal (marker-buffer org-clock-marker)
				   (current-buffer))))
		  (kill-buffer (current-buffer))))
	    (when org-remember-auto-remove-backup-files
	      (when backup-file
		(ignore-errors
		  (delete-file backup-file)
		  (delete-file (concat backup-file "~"))))
	      (when org-remember-backup-directory
		(let ((n (length
			  (directory-files
			   org-remember-backup-directory nil
			   "^remember-.*[0-9]$"))))
		  (when (> n 0)
		    (message
		     "%d backup files (unfinished remember calls) in %s"
		     n org-remember-backup-directory))))))))))

  t)    ;; return t to indicate that we took care of this note.

(defun org-do-remember (&optional initial)
  "Call remember."
  (remember initial))

(defun org-require-remember ()
  "Make sure remember is loaded, or install our own emergency version of it."
  (condition-case nil
      (require 'remember)
    (error
     ;; Lets install our own micro version of remember
     (defvar remember-register ?R)
     (defvar remember-mode-hook nil)
     (defvar remember-handler-functions nil)
     (defvar remember-buffer "*Remember*")
     (defvar remember-save-after-remembering t)
     (defvar remember-annotation-functions '(buffer-file-name))
     (defun remember-finalize ()
       (run-hook-with-args-until-success 'remember-handler-functions)
       (when (equal remember-buffer (buffer-name))
	 (kill-buffer (current-buffer))
	 (jump-to-register remember-register)))
     (defun remember-mode ()
       (fundamental-mode)
       (setq mode-name "Remember")
       (run-hooks 'remember-mode-hook))
     (defun remember (&optional initial)
       (window-configuration-to-register remember-register)
       (let* ((annotation (run-hook-with-args-until-success
			   'remember-annotation-functions)))
	 (switch-to-buffer-other-window (get-buffer-create remember-buffer))
	 (remember-mode)))
     (defun remember-buffer-desc ()
       (buffer-substring (point-min) (save-excursion (goto-char (point-min))
						     (point-at-eol)))))))

(provide 'org-remember)

;; arch-tag: 497f30d0-4bc3-4097-8622-2d27ac5f2698

;;; org-remember.el ends here

