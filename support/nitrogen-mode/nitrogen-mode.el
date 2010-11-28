(define-derived-mode nitrogen-mode erlang-mode "Nitrogen!"
  "Major mode for editing Nitrogen files."
  ;;   (set (make-local-variable 'erlang-calculate-stack-indents) 'nitrogen-calculate-stack-indent)
  (set (make-local-variable 'indent-line-function) 'nitrogen-indent-line)
  (set (make-local-variable 'indent-region-function) 'nitrogen-indent-region)
  (setq erlang-indent-level 4))


(defun nitrogen-indent-line ()
  (let ((result))
    (fset 'old-erlang-calculate-stack-indent (symbol-function 'erlang-calculate-stack-indent))
    (fset 'old-erlang-comment-indent (symbol-function 'erlang-comment-indent))
    (fset 'erlang-calculate-stack-indent (symbol-function 'nitrogen-calculate-stack-indent))
    (fset 'erlang-comment-indent (symbol-function 'nitrogen-comment-indent))
    (setq result (erlang-indent-line))
    (fset 'erlang-calculate-stack-indent (symbol-function 'old-erlang-calculate-stack-indent))
    (fset 'erlang-comment-indent (symbol-function 'old-erlang-comment-indent))
    result))

(defun nitrogen-indent-region (beg end)
  (let ((result))
    (fset 'old-erlang-calculate-stack-indent (symbol-function 'erlang-calculate-stack-indent))
    (fset 'old-erlang-comment-indent (symbol-function 'erlang-comment-indent))
    (fset 'erlang-calculate-stack-indent (symbol-function 'nitrogen-calculate-stack-indent))
    (fset 'erlang-comment-indent (symbol-function 'nitrogen-comment-indent))
    (setq result (erlang-indent-region beg end))
    (fset 'erlang-calculate-stack-indent (symbol-function 'old-erlang-calculate-stack-indent))
    (fset 'erlang-comment-indent (symbol-function 'old-erlang-comment-indent))
    result))

(defun erlang-looking-at-closing-token ()
  "Returns t if currently positioned after a closing token, and moves to next token."
  (while (looking-at "[\s\t].*") (forward-char))
  (cond
   ((looking-at "[\]\)\}]$") (forward-char) t)
   ((looking-at "[\]\)\}].*") (forward-char) t)
   ((looking-at "catch$") (forward-char 5) t)   
   ((looking-at "catch[,\.; ].*") (forward-char 5) t)
   ((looking-at "after$") (forward-char 5) t)
   ((looking-at "after[,\.; ].*") (forward-char 5) t)
   ((looking-at "end$") (forward-char 3) t)
   ((looking-at "end[,\.;\) ]") (forward-char 3) t)
   ((looking-at "\|\|$") (forward-char 2) t)
   ((looking-at "\|\| ") (forward-char 3) t)
   (t nil)))


(defun nitrogen-calculate-stack-indent (indent-point state)
  (let* ((stack (and state (car state)))
	 (token (nth 1 state))
	 (stack-top (and stack (car stack))))
    (cond 
     ;; No state
     ((null state) 0)

     ;; First line of something, or a guard
     ((null stack)
      (if (looking-at "when[^_a-zA-Z0-9]")
	  erlang-indent-guard 0))

     ;; Inside of a block
     (t
      ;; Count the number of indention points on distinct lines
      (let 
	  ((incount 0)
	   (collapsed-incount 0)
	   (outcount 0))
	
	;; Count how many levels we are nested.
	;; Put into collapsed-incount
	(save-excursion 
	  (back-to-indentation)
	  (let ((last-line (line-number-at-pos))
		(tstack stack))    
	    (while (not (null tstack))
	      (let* 
		  ((current-pos (nth 1 (car tstack)))
		   (current-line (line-number-at-pos current-pos)))
		(if (not (= last-line current-line))
		    (setq collapsed-incount (1+ collapsed-incount)))
		(setq incount (1+ incount))
		(setq last-line current-line)
		(setq tstack (cdr tstack))))))
	  
	;; Move through outdention points. Increment the outdent 
	;; counter for each distinct line jump.
	(save-excursion
	  (back-to-indentation)
	  (let ((last-line (line-number-at-pos))
		(tstack stack))

	    (while (erlang-looking-at-closing-token)
	      (let* ((current-pos (nth 1 (car tstack)))
		     (current-line (line-number-at-pos current-pos)))
		;; If we've moved to a different physical line, then outdent one.
		(if (not (= last-line current-line))
		    (setq outcount (1+ outcount)))
		
		;; If the previous level is an 'icr, and it's on a different line, then 
		;; outdent one place
		(let ((one-back (car (cdr tstack))))
		  (if (and 
		       (or
			(eq 'icr (nth 0 one-back))
			(and			 
			 (eq 'try (nth 0 one-back))
			 (not (eq 'try (nth 0 (car tstack))))))
		       (not (= current-line (line-number-at-pos (nth 1 one-back)))))		      
		      (setq outcount (1+ outcount))))
	    
		(setq last-line current-line)
		(setq tstack (cdr tstack)))))
	  
	  ;; If this is a double pipe, then back up one.
	  (if (eq '|| (nth 0 (car stack)))
	      (setq outcount (1+ outcount))))
	
	;; Return indention
;; 	(message "Stack: %S collapsed-incount: %i incount: %i outcount: %i column: %i" stack collapsed-incount incount outcount (* erlang-indent-level (- collapsed-incount outcount)))
	(let 
	    ((indent (* erlang-indent-level (- collapsed-incount outcount))))
	  (back-to-indentation)
	  indent))))))



(defun nitrogen-comment-indent ()
  (cond ((looking-at "%%%") 0)
	(t
	 (or (erlang-calculate-indent)
	     (current-indentation)))))

;; (add-to-list 'auto-mode-alist '("\\.erl\\'" . nitrogen-mode))
;; (add-to-list 'auto-mode-alist '("\\.hrl\\'" . nitrogen-mode))

(defun nitrogen-node-running-p ()
  (let ((nitrogen-bin (nitrogen-locate-file
                       (buffer-file-name)
                       (concat (file-name-as-directory "bin") "nitrogen"))))
    (string-match-p
     "^pong"
     (shell-command-to-string (concat nitrogen-bin " ping")))))

(defun nitrogen-erlang-machine-options ()
  (let ((vm-args-file-name (nitrogen-locate-vm-args (buffer-file-name))))
    (if (and vm-args-file-name (nitrogen-node-running-p))
        (let ((vm-args (nitrogen-read-vm-args vm-args-file-name)))
          (list "-remsh"     (nitrogen-find-vm-arg "-name" vm-args)
                "-setcookie" (nitrogen-find-vm-arg "-setcookie" vm-args)
                "-name"      (format "emacs%d" (random t))))
      '())))

(defun nitrogen-locate-vm-args (dir)
  (nitrogen-locate-file dir  (concat (file-name-as-directory "etc") "vm.args")))

(defun nitrogen-locate-file (start-dir file-relname)
  (let* ((parent-dir (file-name-directory (directory-file-name start-dir)))
         (file-name  (concat (file-name-as-directory parent-dir) file-relname)))
    (cond ((string= parent-dir start-dir)
           nil)
          ((file-exists-p file-name)
           file-name)
          (t
           (nitrogen-locate-file parent-dir file-relname)))))

(defun nitrogen-read-vm-args (vm-args)
  (with-temp-buffer
    (insert-file-contents vm-args)
    (goto-char (point-min))
    (let ((args nil))
      (while (not (eobp))
        (if (looking-at "[-+]")
            (let ((line (buffer-substring (line-beginning-position)
                                          (line-end-position))))
              (setq args (append args (list (split-string line))))))
        (forward-line))
      args)))

(defun nitrogen-find-vm-arg (vm-arg-name vm-args)
  (if vm-args
      (let ((vm-arg-kv-pair (car vm-args)))
        (if (string= vm-arg-name (car vm-arg-kv-pair))
            (mapconcat (lambda (x) x) (cdr vm-arg-kv-pair) " ")
          (nitrogen-find-vm-arg vm-arg-name (cdr vm-args))))
    nil))

;;; Evaluate a command in an erlang buffer
(defun nitrogen-inferior-erlang-send-command (command)
  "Evaluate a command in an erlang buffer."
  (interactive "P")
  (inferior-erlang-prepare-for-input)
  (inferior-erlang-send-command command)
  (sit-for 0) ;; redisplay
  (inferior-erlang-wait-prompt))

(defun nitrogen-compile ()
  (interactive)
  (let ((inferior-erlang-machine-options
         (append inferior-erlang-machine-options
                 (nitrogen-erlang-machine-options))))
    (erlang-compile)))

(defun nitrogen-compile-all ()
  (interactive)
  (save-some-buffers)
  (let ((inferior-erlang-machine-options
         (append inferior-erlang-machine-options
                 (nitrogen-erlang-machine-options))))
    (nitrogen-inferior-erlang-send-command "sync:go().")))

(defun nitrogen-setup-keybindings-hook ()
  (local-set-key "\C-c\C-k" 'nitrogen-compile)
  (local-set-key "\C-c\C-nk" 'nitrogen-compile-all))

(add-hook 'nitrogen-mode-hook 'nitrogen-setup-keybindings-hook)

(provide 'nitrogen-mode)