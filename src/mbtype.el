;;; mbtype.el --- Typography for Emacs -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Bingshan Chang

;; Author: Bingshan Chang <chang@bingshan.org>
;; Keywords: faces
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))

;; This file is not part of GNU Emacs.

;; This file is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published
;; by the Free Software Foundation, either version 3 of the License,
;; or (at your option) any later version.

;; This file is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this file.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Enable `mbtype-mode' to set Latin and Chinese monospace fonts.
;; Configure font families before enabling, or call `mbtype-refresh'
;; after changing them.  Fonts must be installed separately.

;;; Code:

(require 'cl-lib)
(require 'fontset)
(require 'subr-x)

(defgroup mbtype nil
  "Typography with MB Type fonts."
  :group 'faces
  :prefix "mbtype-")

(defcustom mbtype-monospace-font "Triplicate A Code"
  "Latin monospace family, or nil to retain the existing family."
  :type '(choice (const nil) string)
  :group 'mbtype)

(defcustom mbtype-chinese-monospace-font "TsangerXuanSan02 W03"
  "Chinese monospace family, or nil to leave Chinese fonts alone."
  :type '(choice (const nil) string)
  :group 'mbtype)

(defcustom mbtype-chinese-monospace-fallbacks
  '("LXGW Neo ZhiSong" "LXGW WenKai Mono")
  "Chinese families to try after the primary family.
This list is inactive when `mbtype-chinese-monospace-font' is nil."
  :type '(repeat string)
  :group 'mbtype)

(defcustom mbtype-frame-predicate #'identity
  "Function accepting a graphical frame to manage.
Non-nil means manage that frame.  Terminal frames are always skipped.
Change this option and call `mbtype-refresh' to update the scope."
  :type 'function
  :group 'mbtype)

(defvar mbtype--faces '(default fixed-pitch)
  "Faces whose font families and fontsets MBType manages.")

(defvar mbtype--chinese-ranges
  '(han (#x3000 . #x303f) (#xff01 . #xff60) (#xffe0 . #xffe6))
  "Han, CJK punctuation, and fullwidth forms managed by MBType.")

(cl-defstruct (mbtype--slot (:constructor mbtype--make-slot))
  face attribute baseline applied status)

(cl-defstruct (mbtype--state (:constructor mbtype--make-state))
  slots issues)

(defvar mbtype--frames (make-hash-table :test #'eq)
  "Managed frames and their restoration records.")

(defvar mbtype--fontsets (make-hash-table :test #'equal)
  "Reusable fontsets indexed by their complete specifications.")

(defvar mbtype--fontset-number 0
  "Counter for owned fontset names.")

(defvar mbtype--theme-changing nil
  "Non-nil while a theme operation has suspended typography.")

(defvar mbtype-mode)

(defun mbtype--validate-options ()
  "Check configuration before changing any faces."
  (dolist (value (list mbtype-monospace-font
                       mbtype-chinese-monospace-font))
    (unless (or (null value)
                (and (stringp value) (> (length value) 0)))
      (user-error "Font family must be a nonempty string or nil")))
  (unless (and (proper-list-p mbtype-chinese-monospace-fallbacks)
               (cl-every (lambda (value)
                           (and (stringp value)
                                (> (length value) 0)))
                         mbtype-chinese-monospace-fallbacks))
    (user-error "Chinese fallbacks must be font family names"))
  (unless (functionp mbtype-frame-predicate)
    (user-error "Frame predicate must be a function")))

(defun mbtype--eligible-p (frame)
  "Return non-nil if FRAME is eligible for typography."
  (and (frame-live-p frame)
       (display-graphic-p frame)
       (funcall mbtype-frame-predicate frame)))

(defun mbtype--read (frame slot)
  "Read the raw attribute for SLOT on FRAME."
  (face-attribute (mbtype--slot-face slot)
                  (mbtype--slot-attribute slot) frame nil))

(defun mbtype--set-fontset (face frame name)
  "Bind NAME to FACE on FRAME without replacing its ASCII font."
  (if (not (eq face 'default))
      (set-face-attribute face frame :fontset name)
    ;; Redisplay overwrites default's :fontset from the frame.  The
    ;; native font parameter accepts (FONTSET . FONT-OBJECT), also
    ;; used by set-fontset-font when changing an ASCII mapping.
    (let ((font (face-attribute 'default :font frame))
          (parameter (frame-parameter frame 'font-parameter)))
      (unless (fontp font 'font-object)
        (error "The frame's ASCII font has not been realized"))
      (modify-frame-parameters
       frame (list (cons 'font (cons name font))
                   (cons 'font-parameter parameter))))))

(defun mbtype--state (frame)
  "Return the restoration state for FRAME, creating it if needed."
  (or (gethash frame mbtype--frames)
      (let (slots)
        (dolist (face mbtype--faces)
          (dolist (attribute '(:family :fontset))
            (push (mbtype--make-slot
                   :face face
                   :attribute attribute) slots)))
        (puthash frame (mbtype--make-state :slots (nreverse slots))
                 mbtype--frames))))

(defun mbtype--slot (state face attribute)
  "Find FACE's ATTRIBUTE record in STATE."
  (cl-find-if (lambda (slot)
                (and (eq face (mbtype--slot-face slot))
                     (eq attribute (mbtype--slot-attribute slot))))
              (mbtype--state-slots state)))

(defun mbtype--notice (state format-string &rest arguments)
  "Record FORMAT-STRING with ARGUMENTS in STATE."
  (cl-pushnew (apply #'format format-string arguments)
              (mbtype--state-issues state) :test #'equal))

(defun mbtype--check-ownership (frame state)
  "Capture baselines and release externally changed slots on FRAME.
Update STATE before writing any attributes."
  (dolist (slot (mbtype--state-slots state))
    (let ((value (mbtype--read frame slot)))
      (cond
       ((null (mbtype--slot-status slot))
        (setf (mbtype--slot-baseline slot) value))
       ((and (eq (mbtype--slot-status slot) 'owned)
             (not (equal value (mbtype--slot-applied slot))))
        (setf (mbtype--slot-status slot) 'released))))
    (when (eq (mbtype--slot-status slot) 'released)
      (mbtype--notice state "%s %s: changed outside MBType"
                      (mbtype--slot-face slot)
                      (mbtype--slot-attribute slot)))))

(defun mbtype--set (frame slot value)
  "Set SLOT on FRAME to VALUE if it differs."
  (unless (equal value (mbtype--read frame slot))
    (if (eq (mbtype--slot-attribute slot) :fontset)
        (mbtype--set-fontset (mbtype--slot-face slot) frame value)
      (set-face-attribute (mbtype--slot-face slot) frame
                          (mbtype--slot-attribute slot) value))))

(defun mbtype--write (frame slot value)
  "Write VALUE on FRAME using SLOT's captured baseline."
  (setf (mbtype--slot-status slot) 'owned)
  (unwind-protect
      (mbtype--set frame slot value)
    (setf (mbtype--slot-applied slot) (mbtype--read frame slot))))

(defun mbtype--update-face (frame state face family fontset)
  "Apply FAMILY and FONTSET to FACE on FRAME using STATE.
Nil values restore owned attributes.  Preserve external edits."
  (let* ((latin (mbtype--slot state face :family))
         (cjk (mbtype--slot state face :fontset))
         (binding (if (eq (mbtype--slot-status cjk) 'released)
                      (mbtype--read frame cjk)
                    (mbtype--slot-baseline cjk)))
         ready)
    (unwind-protect
        (progn
          (unless (eq (mbtype--slot-status latin) 'released)
            (cond
             (family (mbtype--write frame latin family))
             ((eq (mbtype--slot-status latin) 'owned)
              (mbtype--set frame latin (mbtype--slot-baseline latin))
              (setf (mbtype--slot-status latin) nil))))
          (setq ready t))
      ;; A family write can replace the frame fontset, even if it
      ;; signals.  Restore the binding before an outer rollback.
      (if (and ready fontset
               (not (eq (mbtype--slot-status cjk) 'released)))
          (mbtype--write frame cjk fontset)
        (mbtype--set frame cjk binding)
        (when (eq (mbtype--slot-status cjk) 'owned)
          (setf (mbtype--slot-status cjk) nil))))))

(defun mbtype--restore (frame state)
  "Restore still-owned values in STATE on FRAME."
  (when (frame-live-p frame)
    (mbtype--check-ownership frame state)
    (dolist (face mbtype--faces)
      (mbtype--update-face frame state face nil nil))))

(defun mbtype--resolve-font (family frame &optional face)
  "Resolve FAMILY on FRAME, respecting FACE's style when given.
Return FAMILY, or nil if no installed font matches it.
Keep family aliases: their canonical names may omit a chosen style."
  (when family
    (let ((spec (font-spec :family family)))
      (when face
        (dolist (attribute '(:weight :slant :width :foundry))
          (font-put spec attribute
                    (face-attribute face attribute frame 'default))))
      (and (list-fonts spec frame 1) family))))

(defun mbtype--native-fontset (name frame)
  "Describe an ordinary automatic fontset NAME on FRAME.
Return (t REGISTRY) for an automatic fontset, (t nil) for the
global default, and nil for unsupported custom fontsets.
Only automatic fontsets containing unrestricted registry specs are
supported.  The query API cannot export arbitrary specs losslessly."
  (let ((name (query-fontset name)))
    (cond
     ((equal name (query-fontset "fontset-default")) '(t nil))
     ((and name
           (string-match-p
            "fontset-\\(?:startup\\|auto[0-9]+\\)\\'" name))
      (let* ((info (fontset-info name frame))
             (fallback (char-table-range info nil))
             (pattern (caar fallback))
             (registry (and (stringp pattern)
                            (font-get (font-spec :name pattern)
                                      :registry)))
             (expected (and registry
                            (font-xlfd-name
                             (font-spec :registry registry))))
             (valid (and expected (equal pattern expected)
                         (= (length fallback) 1))))
        (map-char-table
         (lambda (_range value)
           (unless (and (= (length value) 1)
                        (equal (caar value) expected))
             (setq valid nil)))
         info)
        (and valid (list t registry)))))))

(defun mbtype--ensure-fontset (native families)
  "Return an owned fontset using NATIVE rules and Chinese FAMILIES."
  (let ((key (list native families)))
    (or (gethash key mbtype--fontsets)
        (let (name)
          (while (or (null name) (query-fontset name))
            (setq name
                  (format "-*-*-*-*-*-*-*-*-*-*-*-*-fontset-mbtype%d"
                          (cl-incf mbtype--fontset-number))))
          ;; The ordinary automatic fontset has Latin and catch-all
          ;; registry specs.  Preserve these, not a lossy query dump.
          (new-fontset
           name (when (cadr native)
                  (let ((spec (font-spec :registry (cadr native))))
                    (list (list 'latin spec) (list nil spec)))))
          (dolist (range mbtype--chinese-ranges)
            (let (append)
              (dolist (family families)
                (set-fontset-font name range
                                  (font-spec :family family)
                                  nil append)
                (setq append 'append))))
          (puthash key name mbtype--fontsets)))))

(defun mbtype--prepare (frame state)
  "Resolve desired settings for FRAME without changing its faces.
Record missing fonts and unsupported mappings in STATE."
  (let (chinese plans)
    (when mbtype-chinese-monospace-font
      (dolist (family
               (delete-dups
                (cons mbtype-chinese-monospace-font
                      (copy-sequence
                       mbtype-chinese-monospace-fallbacks))))
        (if (mbtype--resolve-font family frame)
            (push family chinese)
          (mbtype--notice state "Unavailable Chinese font: %s"
                          family))))
    (setq chinese (nreverse chinese))
    (dolist (face mbtype--faces)
      (let* ((family (mbtype--resolve-font
                      mbtype-monospace-font frame face))
             (cjk (mbtype--slot state face :fontset))
             (base (mbtype--slot-baseline cjk))
             fontset)
        (when (and mbtype-monospace-font (not family))
          (mbtype--notice state "%s: unavailable Latin font %s"
                          face mbtype-monospace-font))
        ;; An unspecified binding already inherits the frame fontset.
        ;; The native setter cannot restore an unspecified binding.
        (when (and chinese (stringp base)
                   (not (eq (mbtype--slot-status cjk) 'released)))
          (if-let* ((native (mbtype--native-fontset
                             base frame)))
              (setq fontset (mbtype--ensure-fontset native chinese))
            (mbtype--notice state "%s: custom fontset retained"
                            face)))
        (push (list face family fontset) plans)))
    (nreverse plans)))

(defun mbtype--apply (frame)
  "Apply typography to eligible FRAME, preserving external edits."
  (let ((state (mbtype--state frame)))
    (setf (mbtype--state-issues state) nil)
    (mbtype--check-ownership frame state)
    (condition-case error
        (dolist (plan (mbtype--prepare frame state))
          (apply #'mbtype--update-face frame state plan))
      ((error quit)
       (mbtype--restore frame state)
       (mbtype--notice state "Application failed: %s"
                       (error-message-string error))
       (signal (car error) (cdr error))))))

;;; Lifecycle

(defun mbtype--refresh-frames ()
  "Reconcile typography on existing frames."
  (maphash (lambda (frame state)
             (unless (mbtype--eligible-p frame)
               (mbtype--restore frame state)
               (remhash frame mbtype--frames)))
           mbtype--frames)
  (dolist (frame (frame-list))
    (when (mbtype--eligible-p frame)
      (mbtype--apply frame))))

;;;###autoload
(defun mbtype-refresh ()
  "Apply font configuration to eligible frames.
Keep externally changed attributes until the next mode enable cycle.
When the mode is disabled, do not change appearance."
  (interactive)
  (mbtype--validate-options)
  (if mbtype-mode
      (unless mbtype--theme-changing
        (mbtype--refresh-frames))
    (when (called-interactively-p 'interactive)
      (message "MBType mode is disabled"))))

(defun mbtype--new-frame (frame)
  "Set up FRAME without changing other frames."
  (when (and mbtype-mode (not mbtype--theme-changing)
             (mbtype--eligible-p frame))
    (condition-case error
        (mbtype--apply frame)
      (error
       (message "MBType: %s" (error-message-string error))))))

(defun mbtype--delete-frame (frame)
  "Forget restoration records for deleted FRAME."
  (remhash frame mbtype--frames))

(defun mbtype--around-theme (function &rest arguments)
  "Run theme FUNCTION with ARGUMENTS outside owned face settings."
  (if (or (not mbtype-mode) mbtype--theme-changing)
      (apply function arguments)
    (let ((mbtype--theme-changing t))
      (maphash #'mbtype--restore mbtype--frames)
      (unwind-protect
          (apply function arguments)
        (when mbtype-mode
          ;; Cleanup must not mask an error from the theme operation.
          (condition-case error
              (mbtype--refresh-frames)
            (error
             (message "MBType: %s"
                      (error-message-string error)))))))))

(defun mbtype--disable ()
  "Remove active typography and lifecycle registrations."
  (remove-hook 'after-make-frame-functions #'mbtype--new-frame)
  (remove-hook 'delete-frame-functions #'mbtype--delete-frame)
  (advice-remove 'enable-theme #'mbtype--around-theme)
  (advice-remove 'disable-theme #'mbtype--around-theme)
  (let (failure)
    (maphash
     (lambda (frame state)
       (condition-case error
           (progn
             (mbtype--restore frame state)
             (remhash frame mbtype--frames))
         (error (unless failure (setq failure error)))))
     mbtype--frames)
    ;; Keep failed records so another disable can retry restoration.
    (when failure
      (signal (car failure) (cdr failure)))))

;;;###autoload
(define-minor-mode mbtype-mode
  "Set Latin and Chinese monospace fonts on graphical frames.
Disabling restores still-owned settings and preserves later edits."
  :global t
  :group 'mbtype
  (if (not mbtype-mode)
      (mbtype--disable)
    (condition-case error
        (progn
          (mbtype-refresh)
          (add-hook 'after-make-frame-functions
                    #'mbtype--new-frame 90)
          (add-hook 'delete-frame-functions #'mbtype--delete-frame)
          (advice-add 'enable-theme :around #'mbtype--around-theme)
          (advice-add 'disable-theme :around #'mbtype--around-theme))
      ((error quit)
       (setq mbtype-mode nil)
       (condition-case cleanup
           (mbtype--disable)
         (error (message "MBType cleanup: %s"
                         (error-message-string cleanup))))
       (signal (car error) (cdr error))))))

;;; Diagnostics

;;;###autoload
(defun mbtype-describe-at-point ()
  "Describe the actual font at point in the selected window.
Glyph advance is an isolated font metric, not composition width."
  (interactive)
  (let* ((window (selected-window))
         (frame (window-frame window))
         (character (char-after))
         (graphic (display-graphic-p frame))
         (font (and graphic character (font-at (point) window)))
         (glyph (and font
                     (aref (font-get-glyphs font 0 1
                                            (string character)) 0)))
         (faces (get-char-property (point) 'face))
         (state (gethash frame mbtype--frames))
         (buffer-name (buffer-name)))
    (with-help-window "*MBType*"
      (princ (format "Buffer: %s\nFrame: %s\n" buffer-name
                     (frame-parameter frame 'name)))
      (princ (format "Mode: %s; frame: %s\n"
                     (if mbtype-mode "enabled" "disabled")
                     (if state "managed" "unmanaged")))
      (princ (format "Faces at point: %S\n" faces))
      (when character
        (princ (format "Character: %c (U+%04X); columns: %s\n"
                       character character (char-width character))))
      (if font
          (progn
            (princ (format "Actual font: %s\n" (font-xlfd-name font)))
            (dolist (property '(:family :weight :slant :size))
              (princ (format "%s: %s\n" property
                             (font-get font property))))
            (let* ((family (symbol-name (font-get font :family)))
                   (fallback (cl-position
                              family
                              mbtype-chinese-monospace-fallbacks
                              :test #'string-equal-ignore-case)))
              (cond
               ((and mbtype-chinese-monospace-font
                     (string-equal-ignore-case
                      family mbtype-chinese-monospace-font))
                (princ "Matches Chinese primary\n"))
               ((and mbtype-chinese-monospace-font fallback)
                (princ (format "Matches Chinese fallback %d\n"
                               (1+ fallback)))))))
        (princ (if graphic "Actual font: unavailable\n"
                 "Actual font: controlled by the terminal\n")))
      (when glyph
        (princ (format "Isolated glyph advance: %s px\n"
                       (aref glyph 4))))
      (when graphic
        (princ (format "Frame cell width: %s px\n"
                       (frame-char-width frame))))
      (princ (format "\nLatin choice: %S\nChinese choice: %S\n"
                     mbtype-monospace-font
                     mbtype-chinese-monospace-font))
      (princ (format "Chinese fallbacks: %S\n"
                     mbtype-chinese-monospace-fallbacks))
      (dolist (issue (and state (mbtype--state-issues state)))
        (princ (concat "\n" issue "\n"))))))

(provide 'mbtype)
;;; mbtype.el ends here
