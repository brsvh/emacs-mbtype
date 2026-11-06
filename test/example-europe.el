;;; example-europe.el --- European code specimen -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Bingshan Chang
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Open this file in Emacs Lisp mode to inspect code typography.
;; Read alongside example-europe.org.  Loading only defines sample
;; data and functions; it does not configure fonts or open buffers.

;;; Code:

(require 'cl-lib)
(require 'rx)
(require 'ucs-normalize)

;;; A small multilingual reading catalogue

(defvar mbtype-test--europe-catalogue
  '(( :language french
      :title "À l'étage : lumière, cœur et façade"
      :author "Éloïse Noël"
      :city "Besançon"
      :pages 128
      :tags (prose café))
    ( :language german
      :title "Über Größe, Maß und äußere Form"
      :author "Jörg Weiß"
      :city "Düsseldorf"
      :pages 96
      :tags (essay straße))
    ( :language spanish
      :title "¿Qué cambió? El niño abrió la página."
      :author "Íñigo Muñoz"
      :city "Córdoba"
      :pages 144
      :tags (prose diseño))
    ( :language portuguese
      :title "A edição reúne ações, memória e informação."
      :author "João Simões"
      :city "Guimarães"
      :pages 112
      :tags (essay edição))
    ( :language polish
      :title "Łódź: żółć, źródło i ścieżka"
      :author "Małgorzata Wójcik"
      :city "Gdańsk"
      :pages 88
      :tags (prose książka))
    ( :language greek
      :title "Μια μικρή ιστορία για το φως"
      :author "Ελένη Παππά"
      :city "Αθήνα"
      :pages 120
      :tags (prose φως))
    ( :language ukrainian
      :title "Київ: світло, пам’ять і нові сторінки"
      :author "Ірина Коваль"
      :city "Львів"
      :pages 104
      :tags (essay світло)))
  "Fictional catalogue entries for inspecting code faces.")

;;; Letters in comments and strings

;; French:     À Â Æ Ç É È Ê Ë Î Ï Ô Œ Ù Û Ü Ÿ / œil, naïve, Noël
;; German:     Ä Ö Ü ẞ ä ö ü ß / Straße, größer, fünf
;; Spanish:    Á É Í Ñ Ó Ú Ü ¿ ¡ / mañana, pingüino, acción
;; Portuguese: Ã Õ Á Â À Ç É Ê Í Ó Ô Ú / coração, açúcar
;; Italian:    À È É Ì Ò Ó Ù / città, perché, più
;; Dutch:      Ĳ ĳ ë ï / ideeën, coöperatie, IJsselmeer
;; Nordic:     Å Ä Æ Ö Ø å ä æ ö ø / blåbær, smörgås, øy
;; Icelandic:  Þ Ð Æ Ö þ ð æ ö / Þór, við, fjörður
;; Polish:     Ą Ć Ę Ł Ń Ó Ś Ź Ż / łąka, śnieg, źródło
;; Czech:      Č Ď Ě Ň Ř Š Ť Ů Ž / příliš, město, kůň
;; Slovak:     Ď Ĺ Ľ Ň Ô Ŕ Ť / ľudia, kôň, dĺžka
;; Hungarian:  Ő Ű ő ű / tűz, erdő, gyűrű
;; Romanian:   Ă Â Î Ș Ț ă â î ș ț / țară, școală
;; Baltic:     Ā Č Ē Ė Ģ Ī Ķ Ļ Ņ Ų Ū Ž / Rīga, Klaipėda
;; Turkish:    Ç Ğ I İ Ö Ş Ü ç ğ ı i ö ş ü / Iğdır, İzmir
;; Welsh:      Ŵ Ŷ ŵ ŷ / dŵr, tŷ
;; Irish:      Á É Í Ó Ú á é í ó ú / fáilte, léamh
;; Greek:      ΑΒΓΔΕΖΗΘ αβγδεζηθ / ΐ ΰ ά έ ή ί ό ύ ώ ς σ
;; Cyrillic:   Д Ж Й Ц Щ Ы Э Ю Я / Ђ Љ Њ Ћ Џ / Ґ Є І Ї

(defvar mbtype-test--europe-pairs
  '((french "é" "é")
    (swedish "å" "å")
    (czech "č" "č")
    (greek "ά" "ά")
    (ukrainian "ї" "ї"))
  "Precomposed and decomposed spellings, stored without conversion.")

(defvar mbtype-test--europe-marks
  '( :quotes "'single' \"double\" ‘curly’ “curly” «guillemets»"
     :dashes "hyphen-minus - / en – / em — / minus −"
     :money "12,50 €; 1 234,56 €; £18.00; 25 CHF"
     :math "0 ≤ x < 10; α → β; ∑ x²; √2 ≈ 1.414; ±0.01"
     :shape "Il1| O0Q 8B rn m vv w fi fl ffi ffl"
     :spacing "plain space / nonbreaking: A B / narrow: A B"
     :emoji "☕ 🧭 👩🏽‍💻 🇪🇺; text: ♥︎; emoji: ♥️")
  "Punctuation, close letterforms, spacing, and fallback specimens.")

;;; Functions, arguments, keywords, and Unicode identifiers

(defun mbtype-test--europe-select (records language minimum-pages)
  "Select RECORDS matching LANGUAGE and MINIMUM-PAGES.
LANGUAGE may be nil to include every language.  Titles such as
\"À l'étage\", \"Über Größe\", and \"Μια μικρή ιστορία\" stay intact."
  (cl-remove-if-not
   (lambda (record)
     (and (or (null language)
              (eq language (plist-get record :language)))
          (>= (plist-get record :pages) minimum-pages)))
   records))

(defun mbtype-test--europe-label (record)
  "Format RECORD as a compact catalogue label."
  (let ((titre (plist-get record :title))
        (auteur (plist-get record :author))
        (ville (plist-get record :city)))
    (format "%s — %s (%s, %d pp.)"
            auteur titre ville (plist-get record :pages))))

(defun mbtype-test--europe-page-count (records)
  "Return the total page count of RECORDS."
  (cl-loop for entrée in records
           for größe = (plist-get entrée :pages)
           sum größe))

(defun mbtype-test--europe-initial (name)
  "Return the first letter in NAME, ignoring leading punctuation."
  (when (string-match (rx (group alpha)) name)
    (match-string 1 name)))

(defun mbtype-test--europe-normalization (text)
  "Return TEXT and its NFC and NFD forms without modifying TEXT."
  (list :original text
        :nfc (ucs-normalize-NFC-string text)
        :nfd (ucs-normalize-NFD-string text)))

(defun mbtype-test--europe-status (pages)
  "Classify a reading session with PAGES remaining."
  (pcase pages
    ((pred zerop) "Terminé · Fertig · Listo · Τέλος")
    ((pred minusp) (error "Invalid page count: %s" pages))
    ((pred (lambda (n) (< n 20))) "Bientôt · Bald · Pronto")
    (_ "En cours · In Arbeit · En curso")))

;;; Numbers, delimiters, escapes, and alignment

;; Compare equal-length ASCII groups without enabling ligatures:
;;   !=  ==  <=  >=  ->  =>  ::  :=  &&  ||  ++  --  **  //
;;   []  {}  ()  <>  /\  \/  #x  #o  #b  %s  %S  %04X
;;   0123456789  0123456789  0123456789  0123456789
;;   Il1|Il1|Il  O0QO0QO0Q0  rnmwrnmwrn  fiflffiffl

(defvar mbtype-test--europe-literals
  '(42 -17 3.141592653589793 6.022e23
       #x00E9 #x03B1 #x0416 #o755 #b101010
       ?é ?œ ?ß ?λ ?Ж ?\n ?\t ?\\
       "C:\\notes\\élève.txt"
       "First line\nDeuxième ligne\tΕπόμενη γραμμή"
       ["Český" "Magyar" "Ελληνικά" "Українська"])
  "Literal syntax displayed by the standard Lisp font lock rules.")

;; Evaluate individual expressions only when their results are wanted:
;; (mbtype-test--europe-select mbtype-test--europe-catalogue nil 120)
;; (mapcar #'mbtype-test--europe-label mbtype-test--europe-catalogue)
;; (mbtype-test--europe-normalization "café")

(provide 'example-europe)
;;; example-europe.el ends here
