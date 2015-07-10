;;; go-dlv.el --- Go Delve - Debug Go programs interactively with the GUD.

;; Copyright (C) 2015 Marko Bencun

;; Author: Marko Bencun <mbencun@gmail.com>
;; URL: https://github.com/benma/go-dlv.el/
;; Version: 0.1
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

;; If you are using Emacs 24 or later, you can get go-dlv from [melpa](http://melpa.milkbox.net/) with the package manager.
;; Add the following code to your init file.
;; ----------------------------------------------------------
;; (add-to-list 'load-path "folder-in-which-go-dlv-files-are-in/") ;; if the files are not already in the load path
;; (require 'go-dlv)
;; ----------------------------------------------------------

;;; Code:

;; The code below is based on gud's pdb debugger, adapted to dlv:
;; https://github.com/emacs-mirror/emacs/blob/8badbad184c75d6a9b17b72900ca091a1bd11397/lisp/progmodes/gud.el#L1594-1698

(require 'gud)
;; History of argument lists passed to dlv.
(defvar gud-dlv-history nil)

;; Last group is for return value, e.g. "> test.py(2)foo()->None"
;; Either file or function name may be omitted: "> <string>(0)?()"
(defvar gud-dlv-marker-regexp
  "^current loc\\: .+?\\..+? \\(.+\\)\\:\\([0-9]+$\\)")
(defvar gud-dlv-marker-regexp-file-group 1)
(defvar gud-dlv-marker-regexp-line-group 2)

(defvar gud-dlv-marker-regexp-start "^current loc\: ")

;; There's no guarantee that Emacs will hand the filter the entire
;; marker at once; it could be broken up across several strings.  We
;; might even receive a big chunk with several markers in it.  If we
;; receive a chunk of text which looks like it might contain the
;; beginning of a marker, we save it here between calls to the
;; filter.
(defun gud-dlv-marker-filter (string)
  (setq gud-marker-acc (concat gud-marker-acc string))
  (let ((output ""))

    ;; Process all the complete markers in this chunk.
    (while (string-match gud-dlv-marker-regexp gud-marker-acc)
      (setq

       ;; Extract the frame position from the marker.
       gud-last-frame
       (let ((file (match-string gud-dlv-marker-regexp-file-group
                                 gud-marker-acc))
             (line (string-to-number
                    (match-string gud-dlv-marker-regexp-line-group
                                  gud-marker-acc))))
         (cons file line))

       ;; Output everything instead of the below
       output (concat output (substring gud-marker-acc 0 (match-end 0)))
       ;;	  ;; Append any text before the marker to the output we're going
       ;;	  ;; to return - we don't include the marker in this text.
       ;;	  output (concat output
       ;;		      (substring gud-marker-acc 0 (match-beginning 0)))

       ;; Set the accumulator to the remaining text.
       gud-marker-acc (substring gud-marker-acc (match-end 0))))

    ;; Does the remaining text look like it might end with the
    ;; beginning of another marker?  If it does, then keep it in
    ;; gud-marker-acc until we receive the rest of it.  Since we
    ;; know the full marker regexp above failed, it's pretty simple to
    ;; test for marker starts.
    (if (string-match gud-dlv-marker-regexp-start gud-marker-acc)
        (progn
          ;; Everything before the potential marker start can be output.
          (setq output (concat output (substring gud-marker-acc
                                                 0 (match-beginning 0))))

          ;; Everything after, we save, to combine with later input.
          (setq gud-marker-acc
                (substring gud-marker-acc (match-beginning 0))))

      (setq output (concat output gud-marker-acc)
            gud-marker-acc ""))

    output))

(defcustom gud-dlv-command-name "dlv"
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
   (list (gud-query-cmdline 'dlv "run")))

  (gud-common-init command-line nil 'gud-dlv-marker-filter)
  (set (make-local-variable 'gud-minor-mode) 'dlv)

  (gud-def gud-break  "break %d%f:%l"  "\C-b" "Set breakpoint at current line.")
  (gud-def gud-trace  "trace %d%f:%l"  "\C-t" "Set trace at current line.")
  (gud-def gud-remove "clear %d%f:%l"  "\C-d" "Remove breakpoint at current line")
  (gud-def gud-step   "step"         "\C-s" "Step one source line with display.")
  (gud-def gud-next   "next"         "\C-n" "Step one line (skip functions).")
  (gud-def gud-cont   "continue"     "\C-r" "Continue with display.")
  (gud-def gud-print  "print %e"         "\C-p" "Evaluate Python expression at point.")

  (setq comint-prompt-regexp "^(Dlv) *")
  (setq paragraph-start comint-prompt-regexp)
  (run-hooks 'dlv-mode-hook))

(provide 'go-dlv)

;;; go-dlv.el ends here
