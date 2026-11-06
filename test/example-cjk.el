;;; example-cjk.el --- CJK code specimen -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Bingshan Chang
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Open this file in Emacs Lisp mode to inspect code typography.
;; Read alongside example-cjk.org.  Loading only defines sample data
;; and functions.  Language labels do not select fonts automatically.

;;; Code:

(require 'cl-lib)
(require 'rx)

;;; A multilingual reading room

(defvar mbtype-test--cjk-catalogue
  '(( :language chinese
      :title "雨后的书店：字形、标点与留白"
      :author "林晓"
      :shelf "中文 / A-03"
      :pages 128
      :tags (正文 排版 阅读))
    ( :language chinese
      :title "午後的圖書館：閱讀與記憶"
      :author "陳明"
      :shelf "繁體 / B-12"
      :pages 96
      :tags (隨筆 書籍))
    ( :language japanese
      :title "雨の日の図書室――文字と余白"
      :author "佐藤葵"
      :shelf "日本語 / C-07"
      :pages 144
      :tags (本文 かな カタカナ))
    ( :language korean
      :title "비 오는 날의 도서관: 글자와 여백"
      :author "김하늘"
      :shelf "한국어 / D-21"
      :pages 112
      :tags (본문 글꼴 독서)))
  "Fictional records with Han, Kana, Hangul, and Latin text.")

;;; Chinese: simplified, traditional, and shared forms

;; 简体：清晨的书店还没有开门，窗边放着一本新书。
;; 繁體：午後的圖書館很安靜，窗邊放著一本舊書。
;; Mixed: 第 12 页 / page 12 / UTF-8 / λ = 0.94 / 18 px
;; Pairs: 汉 漢 / 书 書 / 国 國 / 云 雲 / 门 門 / 体 體
;; Shared Han: 骨 直 令 返 辻 葛 曜 海 道 羽 雨 雪
;; Bopomofo: ㄅ ㄆ ㄇ ㄈ ㄉ ㄊ ㄋ ㄌ / ㄓㄨㄥ ㄨㄣˊ

;;; Japanese: Kana, Kanji, marks, and halfwidth forms

;; ひらがな：あいうえお、かきくけこ、さしすせそ。
;; カタカナ：アイウエオ、カキクケコ、サシスセソ。
;; Small Kana: ぁぃぅぇぉっゃゅょ / ァィゥェォッャュョ
;; Voicing: がぎぐげご、ぱぴぷぺぽ、ガギグゲゴ、パピプペポ
;; Marks: コーヒー・ノート / きゃっと / 時々 / すゝめ
;; Halfwidth: ｶﾀｶﾅ / ｶﾞ ｷﾞ ｸﾞ ｹﾞ ｺﾞ / ﾊﾟ ﾋﾟ ﾌﾟ ﾍﾟ ﾎﾟ
;; Sentence: 図書室で新しい本を読み、ノートに記録する。

;;; Korean: syllables, Jamo, Hanja, and mixed text

;; 한글: 가 나 다 라 마 바 사 아 자 차 카 타 파 하
;; 받침: 각 간 갇 갈 감 갑 값 갓 강 / 읽다 앉다 없다
;; Double consonants: 까 따 빠 싸 짜 / 꺼 떠 뻐 써 쩌
;; Compatibility Jamo: ㄱ ㄴ ㄷ ㄹ ㅁ ㅂ ㅅ ㅇ ㅈ ㅎ
;; Conjoining Jamo: ᄀ ᄂ ᄃ / ᅡ ᅥ ᅩ / ᆨ ᆫ ᆯ
;; 한자: 韓國 文字 圖書館 學校 / 한글과 漢字를 함께 읽기
;; Sentence: 창가에서 책을 읽고 짧은 메모를 남긴다.

(defvar mbtype-test--cjk-sequences
  '((kana "が" "が")
    (katakana "パ" "パ")
    (hangul "한" "한")
    (hangul "글" "글")
    (different-codepoints "高" "髙")
    (different-codepoints "崎" "﨑")
    (variation-selector "辻" "辻󠄀"))
  "Literal sequence pairs; display depends on font support.
The final pair adds U+E0100.  No conversion is performed on load.")

(defvar mbtype-test--cjk-marks
  '( :chinese "，。！？；：、“”‘’（）【】《》〈〉"
     :japanese "「引用」『書名』【項目】〔補足〕・ー〜…"
     :korean "“인용” ‘강조’ (메모) [항목] · … —"
     :fullwidth "ＡＢＣ ａｂｃ ０１２３ ＋－＝ ％ ＆ ＠ ＃"
     :currency "¥100 / ￥１００ / ₩12,000 / €12.50"
     :rare "𠮷 𠀀 𠮷野 / U+20BB7 U+20000"
     :symbols "→ ← ↔ ⇒ ≤ ≥ ≠ × ÷ ± √ ∑ ∞ □ ■ ○ ●"
     :emoji "📚 ☕ 🧭 👩🏽‍💻 👨‍👩‍👧‍👦 🇨🇳 🇯🇵 🇰🇷"
     :presentation "text: ♥︎ / emoji: ♥️")
  "Punctuation and fallback specimens outside ordinary Latin text.")

;;; Unicode symbols, docstrings, and nested forms

(defun mbtype-test--cjk-select (records language)
  "Select RECORDS for LANGUAGE without changing their text.
Examples include \"雨后的书店\", \"雨の日の図書室\", and
\"비 오는 날의 도서관\".  LANGUAGE is a catalogue field, not a
font selection instruction."
  (cl-remove-if-not
   (lambda (record)
     (eq language (plist-get record :language)))
   records))

(defun mbtype-test--cjk-label (record)
  "Format RECORD with its shelf, author, title, and page count."
  (let ((書名 (plist-get record :title))
        (著者 (plist-get record :author))
        (쪽수 (plist-get record :pages)))
    (format "%s | %s — %s | %d"
            (plist-get record :shelf) 著者 書名 쪽수)))

(defun mbtype-test--cjk-page-count (records)
  "Return the total page count of RECORDS."
  (cl-loop for 項目 in records
           for 페이지 = (plist-get 項目 :pages)
           sum 페이지))

(defun mbtype-test--cjk-annotation (language)
  "Return a short margin note for LANGUAGE."
  (pcase language
    ('chinese "注意：汉字字形与标点间距。")
    ('japanese "注記：漢字の字形と約物の間隔。")
    ('korean "참고: 글자 모양과 문장 부호의 간격.")
    (_ "No language-specific note.")))

(defun mbtype-test--cjk-shelf-p (text)
  "Return non-nil when TEXT ends in a shelf code such as A-03."
  (string-match-p
   (rx "/ " (in "A-Z") "-" (= 2 digit) string-end)
   text))

;;; Code grid: every cell below occupies four nominal columns

;; |ABCD|中文|かな|한글|1234|
;; |1234|漢字|カナ|독서|ABCD|
;; |A中B|AあB|A한B|１２|x==y|
;; +----+----+----+----+----+
;; Nominal columns do not guarantee equal pixel advances.
;; Compare the boundaries at different text scales and frame sizes.

(defvar mbtype-test--cjk-literals
  '(?中 ?文 ?あ ?ア ?한 ?글 ?𠮷
        #x4E2D #x3042 #x30A2 #xD55C #x20BB7
        "中文\n日本語\t한국어"
        "C:\\書籍\\読書.txt"
        ["正文" "本文" "본문" "code_0123"]
        ((中文 . "阅读") (日本語 . "読書") (한국어 . "독서")))
  "Characters, numbers, strings, vectors, and association lists.")

;; ASCII operators must retain their ordinary code appearance:
;; != == <= >= -> => :: := && || ++ -- ** // [] {} () <>
;; Latin/CJK boundaries: foo中文bar  foo日本語bar  foo한국어bar
;; Names and paths: src/排版.el  docs/読書.org  notes/독서.txt

;; Evaluate individual expressions only when their results are wanted:
;; (mbtype-test--cjk-select mbtype-test--cjk-catalogue 'japanese)
;; (mapcar #'mbtype-test--cjk-label mbtype-test--cjk-catalogue)
;; (mbtype-test--cjk-page-count mbtype-test--cjk-catalogue)

(provide 'example-cjk)
;;; example-cjk.el ends here
