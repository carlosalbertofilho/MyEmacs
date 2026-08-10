;;; early-init.el --- Early Init -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Carlos Alberto Filho
;; Author: Carlos Alberto Filho
;; Based on: Emacs Bedrock (https://codeberg.org/ashton314/emacs-bedrock)

;;; Commentary:
;; Early initialization: runs before init.el and before package/UI init.
;; Optimizes startup speed and sets frame defaults.

;;; Code:

;; ── Startup performance ─────────────────────────────────────────────
(setq bedrock--initial-gc-threshold gc-cons-threshold)
(setq gc-cons-threshold (* 50 1000 1000))  ; 50 MB during init
(setq byte-compile-warnings '(not obsolete))
(setq warning-suppress-log-types '((comp) (bytecomp)))
(setq native-comp-async-report-warnings-errors 'silent)

;; Prefer loading newer source files over outdated compiled files
(setq load-prefer-newer-source t)

;; ── Native compilation (Emacs 29+) ──────────────────────────────────
;; Parallel async compilation using all available cores
(when (and (fboundp 'native-comp-available-p)
           (native-comp-available-p))
  ;; Number of parallel compilation jobs (use all CPU cores)
  (setq native-comp-async-jobs-number (num-processors))
  ;; DESATIVAR load-time native-comp dos nossos lisp/custom-*.el (default é t
  ;; no Emacs 30). O subprocesso async compila a partir do SOURCE sem o macro
  ;; `elpaca`, gerando .eln com `(elpaca vertico)` como funcall →
  ;; void-variable vertico no boot seguinte. Pacotes continuam nativizados via
  ;; package-native-compile; custom-*.el ficam só em byte-code (.elc).
  (setq native-comp-deferred-compilation nil)
  ;; Compile packages natively on install (not just byte-compile)
  (setq package-native-compile t))

;; ── Silence startup noise ───────────────────────────────────────────
(setq inhibit-startup-echo-area-message (user-login-name))
(setq inhibit-splash-screen t)

;; ── Frame defaults (before GUI init) ────────────────────────────────
(setq frame-resize-pixelwise t)
(tool-bar-mode -1)
(scroll-bar-mode -1)
(menu-bar-mode -1)

(setq default-frame-alist
      '((vertical-scroll-bars . nil)
        (horizontal-scroll-bars . nil)
        (background-color . "#000000")
        (foreground-color . "#ffffff")
        (ns-appearance . dark)
        (ns-transparent-titlebar . t)))

;; ── Package: don't initialize here, init.el handles it ──────────────
(setq package-enable-at-startup nil)

(provide 'early-init)
;;; early-init.el ends here
