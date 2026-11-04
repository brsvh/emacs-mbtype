;;; Directory Local Variables            -*- no-byte-compile: t -*-
;;; For more information see (info "(emacs) Directory Variables")

((emacs-lisp-mode
  .
  ((eval
    .
    (let* ((root (locate-dominating-file
                  default-directory ".dir-locals.el"))
           (source (expand-file-name "src/" root)))
      (dolist (variable '(load-path
                          elisp-flymake-byte-compile-load-path))
        (make-local-variable variable)
        (add-to-list variable source))))))

 (nil . ((sentence-end-double-space . t))))
