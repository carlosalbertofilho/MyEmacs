;;; custom-magent-tool-rfc.el --- Magent RFC tools -*- lexical-binding: t; -*-

;;; Commentary:
;; Native RFC reading tools for magent.

;;; Code:

;; ── Section ──────────────────────────────────────────────────────────
(defun +carlos/magent-tool-rfc-search-topic (query &optional _reason)
  "Ferramenta Magent: buscar RFCs por tópico no índice oficial IETF.
QUERY é case-insensitive; retorna número + snippet de cada entrada."
  (condition-case err
      (let* ((index-text (+carlos/magent-rfc--fetch-text
                          "-index" "https://www.rfc-editor.org/rfc/rfc%s.txt"))
             (hits (+carlos/magent-rfc-search-index-text index-text query)))
        (+carlos/magent-tool-result
         (list (cons "query" query)
               (cons "count" (length hits))
               (cons "results"
                     (apply #'vector
                            (mapcar (lambda (h)
                                      (list (cons "number" (plist-get h :number))
                                            (cons "snippet" (plist-get h :snippet))))
                                    hits))))))
    (error (+carlos/magent-tool-result
            nil (format "Índice IETF indisponível: %s"
                        (error-message-string err))))))

(with-eval-after-load 'gptel
  (when (fboundp 'gptel-make-tool)
    (setq +carlos/magent-tool-rfc-search-topic
          (gptel-make-tool
           :name "rfc_search_topic"
           :description "Search the official IETF RFC index by topic keywords (case-insensitive). Returns RFC numbers plus snippets so you can pick the right document without hallucinating references."
           :args '((:name "query" :type string)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-rfc-search-topic
           :category "magent"))))


(defun +carlos/magent-tool-rfc-read-section (number-str section &optional _reason)
  "Ferramenta Magent: extrair SEÇÃO de um RFC (economia de tokens).
NUMBER-STR aceita \"9000\"/\"RFC 9000\"; SECTION é o número da seção
\\(ex.: \"7.2\").  Cache local respeitado (rfc-mode)."
  (condition-case err
      (let* ((num (+carlos/magent-rfc-normalize-number number-str))
             (_ (unless num (error "Número inválido: %S" number-str)))
             (text (+carlos/magent-rfc--fetch-text
                    num "https://www.rfc-editor.org/rfc/rfc%s.txt"))
             (found (+carlos/magent-rfc-extract-section text section)))
        (if found
            (+carlos/magent-tool-result
             (list (cons "rfc" (string-to-number num))
                   (cons "section" section)
                   (cons "title" (plist-get found :title))
                   (cons "chars" (length (plist-get found :text)))
                   (cons "text" (plist-get found :text))))
          (+carlos/magent-tool-result
           (list (cons "rfc" (string-to-number num))
                 (cons "sections"
                       (apply #'vector
                              (mapcar (lambda (s) (plist-get s :num))
                                      (+carlos/magent-rfc-parse-sections text)))))
           (format "Seção %s não encontrada" section))))
    (error (+carlos/magent-tool-result
            nil (format "RFC indisponível: %s" (error-message-string err))))))

(with-eval-after-load 'gptel
  (when (fboundp 'gptel-make-tool)
    (setq +carlos/magent-tool-rfc-read-section
          (gptel-make-tool
           :name "rfc_read_section"
           :description "Read ONE numbered section of an official RFC from ietf.org with local cache, partitioned by headings for token economy. Prefer this over reading whole documents."
           :args '((:name "number" :type string)
                   (:name "section" :type string)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-rfc-read-section
           :category "magent"))))

(provide 'custom-magent-tool-rfc)
;;; custom-magent-tool-rfc.el ends here
