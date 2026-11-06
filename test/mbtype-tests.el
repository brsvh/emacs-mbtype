;;; mbtype-tests.el --- MBType behavior tests -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Bingshan Chang
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Run with nix run . -- -Q --batch -l test/mbtype-tests.el
;; -f ert-run-tests-batch-and-exit.  For graphical tests, use -Q
;; without --batch and set MBTYPE_TEST_DISPLAY to the display name.
;; Batch sessions cover terminal behavior and skip graphical tests.

;;; Code:

(require 'ert)
(require 'cl-lib)

(defun mbtype-test--attributes (frame)
  "Return the managed faces' attributes on FRAME."
  (mapcar (lambda (face)
            (cons face
                  (cons (cons :fontset
                              (face-attribute face :fontset frame))
                        (face-all-attributes face frame))))
          '(default fixed-pitch)))

(defvar mbtype-test--before-load
  (mbtype-test--attributes (selected-frame)))

(require 'mbtype)

(defvar mbtype-test--load-effects
  (list (equal mbtype-test--before-load
               (mbtype-test--attributes (selected-frame)))
        mbtype-mode
        (memq #'mbtype--new-frame after-make-frame-functions)
        (memq #'mbtype--delete-frame delete-frame-functions)
        (advice-member-p #'mbtype--around-theme 'enable-theme)
        (advice-member-p #'mbtype--around-theme 'disable-theme))
  "Face preservation and lifecycle state immediately after loading.")

(defun mbtype-test--make-frame (&optional font)
  "Create a temporary graphical frame using FONT."
  (let ((noninteractive nil))
    (make-frame-on-display
     (getenv "MBTYPE_TEST_DISPLAY")
     `((window-system . ,(if (featurep 'pgtk) 'pgtk 'x))
       (visibility . nil)
       (mbtype-test . t)
       (font . ,(or font "DejaVu Sans-12"))))))

(defmacro mbtype-test--with-frame (&rest body)
  "Run BODY with isolated typography settings and a temporary frame."
  (declare (indent 0) (debug t))
  `(progn
     (skip-unless (and (display-graphic-p)
                       (getenv "MBTYPE_TEST_DISPLAY")))
     (let* ((mbtype-mode nil)
            (mbtype--frames (make-hash-table :test #'eq))
            (mbtype-monospace-font "DejaVu Sans Mono")
            (mbtype-chinese-monospace-font "TsangerXuanSan02 W03")
            (mbtype-chinese-monospace-fallbacks
             '("LXGW Neo ZhiSong" "LXGW WenKai Mono"))
            (mbtype-frame-predicate
             (lambda (frame) (frame-parameter frame 'mbtype-test)))
            (frame (mbtype-test--make-frame)))
       (unwind-protect
           (with-selected-frame frame
             ,@body)
         (unwind-protect
             (mbtype-mode -1)
           (dolist (candidate (frame-list))
             (when (frame-parameter candidate 'mbtype-test)
               (delete-frame candidate t))))))))

(defun mbtype-test--family-at (text)
  "Return the actual font family displaying TEXT's first character."
  (with-temp-buffer
    (set-window-buffer (selected-window) (current-buffer))
    (insert text)
    (goto-char (point-min))
    (redisplay t)
    (font-get (font-at (point) (selected-window)) :family)))

(ert-deftest mbtype-load-is-passive ()
  (should (equal mbtype-test--load-effects
                 '(t nil nil nil nil nil))))

(ert-deftest mbtype-disabled-refresh-is-passive ()
  (let ((before (mbtype-test--attributes (selected-frame))))
    (mbtype-refresh)
    (should-not mbtype-mode)
    (should (equal before
                   (mbtype-test--attributes (selected-frame))))))

(ert-deftest mbtype-terminal-enable-is-safe ()
  (skip-unless (not (display-graphic-p)))
  (let ((before (mbtype-test--attributes (selected-frame))))
    (unwind-protect
        (progn
          (mbtype-mode 1)
          (mbtype-refresh)
          (should (equal before
                         (mbtype-test--attributes (selected-frame)))))
      (mbtype-mode -1))))

(ert-deftest mbtype-invalid-configuration-does-not-activate ()
  (let ((mbtype-monospace-font 17))
    (should-error (mbtype-mode 1) :type 'user-error)
    (should-not mbtype-mode)
    (should-not (advice-member-p #'mbtype--around-theme
                                 'enable-theme))))

(ert-deftest mbtype-applies-and-restores-fonts ()
  (mbtype-test--with-frame
    (let ((before (mbtype-test--attributes frame)))
      (mbtype-mode 1)
      (should (equal (face-attribute 'default :family frame)
                     "DejaVu Sans Mono"))
      (should (eq (mbtype-test--family-at "Latin")
                  'DejaVu\ Sans\ Mono))
      (mbtype-mode -1)
      (should (equal before (mbtype-test--attributes frame))))))

(ert-deftest mbtype-preserves-other-face-attributes ()
  (mbtype-test--with-frame
    (set-face-attribute 'fixed-pitch frame
                        :height 1.2
                        :weight 'bold
                        :foreground "red")
    (let ((height (face-attribute 'default :height frame)))
      (mbtype-mode 1)
      (should (= height (face-attribute 'default :height frame)))
      (dolist (pair '((:height . 1.2) (:weight . bold)
                      (:foreground . "red")))
        (should (equal (cdr pair)
                       (face-attribute 'fixed-pitch (car pair)
                                       frame)))))))

(ert-deftest mbtype-chinese-primary-and-fallback ()
  (mbtype-test--with-frame
    (mbtype-mode 1)
    (should (eq (mbtype-test--family-at "中文")
                'TsangerXuanSan02))
    (setq mbtype-chinese-monospace-font "MBType Missing Chinese"
          mbtype-chinese-monospace-fallbacks '("LXGW WenKai Mono"))
    (mbtype-refresh)
    (should (eq (mbtype-test--family-at "中文")
                'LXGW\ WenKai\ Mono))))

(ert-deftest mbtype-missing-fonts-preserve-the-existing-setup ()
  (mbtype-test--with-frame
    (setq mbtype-monospace-font "MBType Missing Latin"
          mbtype-chinese-monospace-font "MBType Missing Chinese"
          mbtype-chinese-monospace-fallbacks nil)
    (let ((before (mbtype-test--attributes frame)))
      (mbtype-mode 1)
      (should (equal before (mbtype-test--attributes frame)))
      (mbtype-mode -1)
      (should (equal before (mbtype-test--attributes frame))))))

(ert-deftest mbtype-refresh-does-not-accumulate-state ()
  (mbtype-test--with-frame
    (mbtype-mode 1)
    (let ((before (mbtype-test--attributes frame))
          (fontsets (fontset-list)))
      (dotimes (_ 3)
        (mbtype-mode 1)
        (mbtype-refresh))
      (should (equal before (mbtype-test--attributes frame)))
      (should (equal fontsets (fontset-list)))
      (mbtype-mode -1)
      (should-not (memq #'mbtype--new-frame
                        after-make-frame-functions))
      (should-not (advice-member-p #'mbtype--around-theme
                                   'disable-theme)))))

(ert-deftest mbtype-retains-a-later-family-change ()
  (mbtype-test--with-frame
    (mbtype-mode 1)
    (set-face-attribute 'fixed-pitch frame :family "DejaVu Serif")
    (mbtype-refresh)
    (should (equal (face-attribute 'fixed-pitch :family frame)
                   "DejaVu Serif"))
    (mbtype-mode -1)
    (should (equal (face-attribute 'fixed-pitch :family frame)
                   "DejaVu Serif"))))

(ert-deftest mbtype-retains-custom-fontsets ()
  (mbtype-test--with-frame
    (let ((name "-*-*-*-*-*-*-*-*-*-*-*-*-fontset-mbtypetest"))
      (new-fontset name nil)
      (set-fontset-font name #x2605
                        (font-spec :family "DejaVu Serif"))
      (set-face-attribute 'fixed-pitch frame :fontset name)
      (let ((mapping (fontset-font name #x2605 t)))
        (mbtype-mode 1)
        (mbtype-refresh)
        (should (equal (face-attribute 'fixed-pitch :fontset frame)
                       name))
        (should (equal mapping (fontset-font name #x2605 t)))
        (mbtype-mode -1)
        (should (equal (face-attribute 'fixed-pitch :fontset frame)
                       name))))))

(ert-deftest mbtype-retains-a-later-fontset-change ()
  (mbtype-test--with-frame
    (mbtype-mode 1)
    (let ((name "-*-*-*-*-*-*-*-*-*-*-*-*-fontset-mbtypelater"))
      (new-fontset name nil)
      (set-face-attribute 'fixed-pitch frame :fontset name)
      (mbtype-refresh)
      (mbtype-mode -1)
      (should (equal (face-attribute 'fixed-pitch :fontset frame)
                     name)))))

(ert-deftest mbtype-category-can-be-disabled ()
  (mbtype-test--with-frame
    (let ((binding (face-attribute 'default :fontset frame)))
      (mbtype-mode 1)
      (should-not (equal binding
                         (face-attribute 'default :fontset frame)))
      (setq mbtype-chinese-monospace-font nil)
      (mbtype-refresh)
      (should (equal binding
                     (face-attribute 'default :fontset frame)))
      (should (equal (face-attribute 'fixed-pitch :family frame)
                     "DejaVu Sans Mono")))))

(deftheme mbtype-test--theme "Theme for MBType acceptance tests.")

(defmacro mbtype-test--with-theme (family &rest body)
  "Run BODY with the test theme's default FAMILY, then disable it."
  (declare (indent 1) (debug t))
  `(unwind-protect
       (progn
         ;; Disabling a theme retains its definition.
         (put 'mbtype-test--theme 'theme-settings nil)
         (custom-theme-set-faces
          'mbtype-test--theme
          (list 'default (list (list t (list :family ,family)))))
         ,@body)
     (disable-theme 'mbtype-test--theme)))

(ert-deftest mbtype-theme-changes-update-the-restoration-baseline ()
  (dolist (family '("DejaVu Serif" "DejaVu Sans Mono"))
    (ert-info ((format "Theme family: %s" family))
      (mbtype-test--with-frame
        (mbtype-test--with-theme family
          (mbtype-mode 1)
          (enable-theme 'mbtype-test--theme)
          (should (equal (face-attribute 'default :family frame)
                         "DejaVu Sans Mono"))
          (mbtype-mode -1)
          (should (equal (face-attribute 'default :family frame)
                         family)))))))

(ert-deftest mbtype-theme-errors-leave-the-mode-consistent ()
  (mbtype-test--with-frame
    (mbtype-test--with-theme "DejaVu Serif"
      (mbtype-mode 1)
      (let ((enable-theme-functions
             (list (lambda (theme)
                     (when (eq theme 'mbtype-test--theme)
                       (error "Theme setup failed"))))))
        (should-error (enable-theme 'mbtype-test--theme)))
      (should mbtype-mode)
      (should (equal (face-attribute 'default :family frame)
                     "DejaVu Sans Mono"))
      (mbtype-mode -1)
      (should (equal (face-attribute 'default :family frame)
                     "DejaVu Serif")))))

(ert-deftest mbtype-can-be-disabled-during-a-theme-change ()
  (mbtype-test--with-frame
    (mbtype-test--with-theme "DejaVu Serif"
      (mbtype-mode 1)
      (let ((enable-theme-functions
             (list (lambda (theme)
                     (when (eq theme 'mbtype-test--theme)
                       (mbtype-mode -1))))))
        (enable-theme 'mbtype-test--theme))
      (should-not mbtype-mode)
      (should (equal (face-attribute 'default :family frame)
                     "DejaVu Serif")))))

(ert-deftest mbtype-failed-enabling-restores-earlier-writes ()
  (dolist (failed-face '(default fixed-pitch))
    (ert-info ((format "Failed face: %s" failed-face))
      (mbtype-test--with-frame
        (let ((before (mbtype-test--attributes frame))
              (setter (symbol-function 'set-face-attribute))
              (fail t))
          (cl-letf (((symbol-function 'set-face-attribute)
                     (lambda (face target &rest attributes)
                       (prog1 (apply setter face target attributes)
                         (when (and fail (eq target frame)
                                    (eq face failed-face))
                           (setq fail nil)
                           (error "Face setup failed"))))))
            (should-error (mbtype-mode 1)))
          (should-not mbtype-mode)
          (should (equal before (mbtype-test--attributes frame)))
          (should-not (advice-member-p #'mbtype--around-theme
                                       'enable-theme)))))))

(ert-deftest mbtype-does-not-change-the-global-fontset ()
  (mbtype-test--with-frame
    (let ((before (fontset-font "fontset-default" ?中 t)))
      (mbtype-mode 1)
      (mbtype-refresh)
      (should (equal before
                     (fontset-font "fontset-default" ?中 t)))
      (mbtype-mode -1)
      (should (equal before
                     (fontset-font "fontset-default" ?中 t))))))

(ert-deftest mbtype-new-frame-does-not-reset-existing-frames ()
  (mbtype-test--with-frame
    (mbtype-mode 1)
    (let* ((before (mbtype-test--attributes frame))
           (other (mbtype-test--make-frame "DejaVu Sans-16")))
      (should (equal before (mbtype-test--attributes frame)))
      (should (equal (face-attribute 'default :family other)
                     "DejaVu Sans Mono"))
      (should-not (= (face-attribute 'default :height frame)
                     (face-attribute 'default :height other))))))

(ert-deftest mbtype-refresh-releases-excluded-frames ()
  (mbtype-test--with-frame
    (let ((before (mbtype-test--attributes frame)))
      (mbtype-mode 1)
      (setq mbtype-frame-predicate #'ignore)
      (mbtype-refresh)
      (should (equal before (mbtype-test--attributes frame))))))

(ert-deftest mbtype-diagnostics-report-the-actual-font ()
  (mbtype-test--with-frame
    (mbtype-mode 1)
    (unwind-protect
        (with-temp-buffer
          (set-window-buffer (selected-window) (current-buffer))
          (insert "中文")
          (goto-char (point-min))
          (mbtype-describe-at-point)
          (with-current-buffer "*MBType*"
            (should (string-match-p ":family: TsangerXuanSan02"
                                    (buffer-string)))
            (should (string-match-p "U\\+4E2D"
                                    (buffer-string)))))
      (when (get-buffer "*MBType*")
        (kill-buffer "*MBType*")))))

(provide 'mbtype-tests)
;;; mbtype-tests.el ends here
