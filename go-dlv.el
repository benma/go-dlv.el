;;; go-dlv.el --- Go Delve - Debug Go programs interactively with the GUD.

;; Copyright (C) 2015 Marko Bencun

;; Author: Marko Bencun <mbencun@gmail.com>
;; URL: https://github.com/benma/go-dlv.el/
;; Version: 0.1
;; Package-Requires: ((go-mode "1.3.1"))
;; Keywords: Go, debug, debugger, delve, interactive, gud

;; This file is part of go-dlv.

;; go-dlv is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; go-dlv is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with go-dlv.  If not, see <http://www.gnu.org/licenses/>.

;;; Installation

;; If you are using Emacs 24 or later, you can get go-dlv from [melpa](https://melpa.org/) with the package manager.
;; Add the following code to your init file.
;; ----------------------------------------------------------
;; (add-to-list 'load-path "folder-in-which-go-dlv-files-are-in/") ;; if the files are not already in the load path
;; (require 'go-dlv)
;; ----------------------------------------------------------

;;; Code:

;; The code below is based on gud's pdb debugger, adapted to dlv:
;; https://github.com/emacs-mirror/emacs/blob/8badbad184c75d6a9b17b72900ca091a1bd11397/lisp/progmodes/gud.el#L1594-1698

(require 'gud)
(require 'go-mode)
(require 'cl-lib)

;; Sample marker lines:
;;
;; Frame 2: ./main.go:76 (PC: e883c7)
;; > main.main() ./test.go:10 (hits goroutine(5):1 total:1)
(setq go-dlv-marker-regexps
  '("^Frame [0-9]+: \\([^:]+\\):\\([0-9]+\\)"
    "^> .+(.*) \\(.+\\)\\:\\([0-9]+\\)"))

(defvar go-dlv-marker-regexp-start "^\\(> \\|Frame [0-9]+:\\)")

(defvar go-dlv-marker-acc "")
(make-variable-buffer-local 'go-dlv-marker-acc)

(defun* go-dlv-extract-file-line (string)
  "Extract the first frame position found in the string. Returns (filename . line) or nil."
  (dolist (re go-dlv-marker-regexps)
    (if (string-match re string)
        (progn
          (return-from go-dlv-extract-file-line
            (cons (match-string 1 string) (string-to-number (match-string 2 string))))))))

;; There's no guarantee that Emacs will hand the filter the entire
;; marker at once; it could be broken up across several strings.  We
;; might even receive a big chunk with several markers in it.  If we
;; receive a chunk of text which looks like it might contain the
;; beginning of a marker, we save it here between calls to the
;; filter.
(defun go-dlv-marker-filter (string)
  (setq go-dlv-marker-acc (concat go-dlv-marker-acc string))
  (let ((output "") file-line)
    ;; Process all the complete markers in this chunk.
    (while (setq file-line (go-dlv-extract-file-line go-dlv-marker-acc))
      (setq
       gud-last-frame file-line
       ;; Output everything instead of the below
       output (concat output (substring go-dlv-marker-acc 0 (match-end 0)))
       ;;	  ;; Append any text before the marker to the output we're going
       ;;	  ;; to return - we don't include the marker in this text.
       ;;	  output (concat output
       ;;		      (substring go-dlv-marker-acc 0 (match-beginning 0)))

       ;; Set the accumulator to the remaining text.
       go-dlv-marker-acc (substring go-dlv-marker-acc (match-end 0))))

    ;; Does the remaining text look like it might end with the
    ;; beginning of another marker?  If it does, then keep it in
    ;; go-dlv-marker-acc until we receive the rest of it.  Since we
    ;; know the full marker regexp above failed, it's pretty simple to
    ;; test for marker starts.
    (if (string-match go-dlv-marker-regexp-start go-dlv-marker-acc)
        (progn
          ;; Everything before the potential marker start can be output.
          (setq output (concat output (substring go-dlv-marker-acc
                                                 0 (match-beginning 0))))

          ;; Everything after, we save, to combine with later input.
          (setq go-dlv-marker-acc
                (substring go-dlv-marker-acc (match-beginning 0))))

      (setq output (concat output go-dlv-marker-acc)
            go-dlv-marker-acc ""))
    output))

(defcustom go-dlv-command-name "dlv"
  "File name for executing the Go Delve debugger.
This should be an executable on your path, or an absolute file name."
  :type 'string
  :group 'gud)

;;;###autoload
(defun dlv (command-line)
  "Run dlv on program FILE in buffer `*gud-FILE*'.
The directory containing FILE becomes the initial working directory
and source-file directory for your debugger."
  (interactive
   (list (gud-query-cmdline 'dlv "debug")))

  (gud-common-init command-line nil 'go-dlv-marker-filter)
  (set (make-local-variable 'gud-minor-mode) 'dlv)

  (gud-def gud-break  "break %d%f:%l"  "\C-b" "Set breakpoint at current line.")
  (gud-def gud-trace  "trace %d%f:%l"  "\C-t" "Set trace at current line.")
  (gud-def gud-remove "clearall %d%f:%l"  "\C-d" "Remove breakpoint at current line")
  (gud-def gud-step   "step"         "\C-s" "Step one source line with display.")
  (gud-def gud-next   "next"         "\C-n" "Step one line (skip functions).")
  (gud-def gud-cont   "continue"     "\C-r" "Continue with display.")
  (gud-def gud-print  "print %e"         "\C-p" "Evaluate Go expression at point.")

  (setq comint-prompt-regexp "^(Dlv) *")
  (setq paragraph-start comint-prompt-regexp)
  (run-hooks 'go-dlv-mode-hook))

;;;###autoload
(defun dlv-current-func ()
  "Debug the current program or test stopping at the beginning of the current function."
  (interactive)
  (let (current-test-name current-func-loc)
    ;; find the location of the current function and (if it is a test function) its name
    (save-excursion
      (when (go-beginning-of-defun)
        (setq current-func-loc (format "%s:%d" buffer-file-name (line-number-at-pos)))
        ;; if we are looking at the test function populate current-test-name
        (when (looking-at go-func-regexp)
          (let ((func-name (match-string 1)))
            (when (and (string-match-p "_test\.go$" buffer-file-name)
                       (string-match-p "^Test\\|^Example" func-name))
              (setq current-test-name func-name))))))

    (if current-func-loc
        (let (gud-buffer-name dlv-command)
          (if current-test-name
              (progn
                (setq gud-buffer-name "*gud-test*")
                (setq dlv-command (concat go-dlv-command-name " test -- -test.run " current-test-name)))
            (progn
              (setq gud-buffer-name "*gud-debug*")
              (setq dlv-command (concat go-dlv-command-name " debug"))))

          ;; stop the current active dlv session if any
          (let ((gud-buffer (get-buffer gud-buffer-name)))
            (when gud-buffer (kill-buffer gud-buffer)))

          ;; run dlv and stop at the beginning of the current function
          (dlv dlv-command)
          (gud-call (format "break %s" current-func-loc))
          (gud-call "continue"))
      (error "Not in function"))))

(provide 'go-dlv)

;;; go-dlv.el ends here
