#!/usr/bin/env python3
"""bench-local-models.py — Benchmark de modelos locais (MLX agnes.local:8081 e Ollama).

Mede time-to-first-token, throughput (tok/s) e volume de content/reasoning
para comparar modelos locais — os mesmos usados pelo Magent/gptel.

Uso:
  python3 bin/bench-local-models.py                 # MLX (default)
  python3 bin/bench-local-models.py --ollama        # Ollama (host aa102-006l:11434)
  python3 bin/bench-local-models.py --url http://127.0.0.1:8081/v1/chat/completions
  python3 bin/bench-local-models.py --prompt "prompt" --max-tokens 1024

O prompt default é o mesmo usado no teste do magent
(`bin/magent-batch-test.el`) para comparabilidade.
"""
import argparse
import json
import sys
import time
import urllib.request

MLX_URL = "http://127.0.0.1:8081/v1/chat/completions"
OLLAMA_URL = "http://127.0.0.1:11434/v1/chat/completions"

MLX_MODELS = [
    "mlx-community/gemma-4-e2b-it-4bit",
    "mlx-community/Qwen3.5-9B-MLX-4bit",
    "mlx-community/Qwen3-14B-4bit",
    "mlx-community/DeepSeek-R1-Distill-Qwen-14B-4bit",
    "mlx-community/Qwen2.5-7B-Instruct-4bit",
]

OLLAMA_MODELS = [
    "qwen3:0.6b",
    "qwen2.5-coder:3b",
    "llama3.2:3b",
    "gemma3:4b",
]

DEFAULT_PROMPT = (
    "Analise o diretório do projeto atual e diga o que você entendeu, "
    "apontando para o MyEmacs. Seja objetivo."
)


def parse_args():
    ap = argparse.ArgumentParser(description="Benchmark de modelos locais.")
    ap.add_argument("--ollama", action="store_true",
                    help="Usa o servidor Ollama (aa102-006l) em vez de MLX.")
    ap.add_argument("--url", default=None,
                    help="URL do endpoint /v1/chat/completions.")
    ap.add_argument("--prompt", default=DEFAULT_PROMPT,
                    help="Prompt a usar em todos os modelos.")
    ap.add_argument("--max-tokens", type=int, default=256,
                    help="Limite de tokens por modelo (default: 256).")
    ap.add_argument("--models", nargs="*", default=None,
                    help="Lista de modelos a testar (default: lista do backend).")
    return ap.parse_args()


def bench(url, model, prompt, max_tokens):
    body = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "stream": True,
        "max_tokens": max_tokens,
    }).encode()
    req = urllib.request.Request(url, data=body,
                                 headers={"Content-Type": "application/json"})
    t0 = time.monotonic()
    first_token_t = None
    n_tokens = 0
    content_chars = 0
    reason_chars = 0
    in_reasoning = False
    with urllib.request.urlopen(req, timeout=180) as resp:
        for raw in resp:
            line = raw.decode(errors="replace").strip()
            if not line.startswith("data: "):
                continue
            payload = line[6:]
            if payload == "[DONE]":
                break
            try:
                obj = json.loads(payload)
            except json.JSONDecodeError:
                continue
            if first_token_t is None:
                first_token_t = time.monotonic() - t0
            delta = obj.get("choices", [{}])[0].get("delta", {})
            if "reasoning" in delta:
                in_reasoning = True
                reason_chars += len(delta["reasoning"])
            if "content" in delta and delta.get("content"):
                content_chars += len(delta["content"])
                if in_reasoning:
                    in_reasoning = False
            if "reasoning_content" in delta:
                reason_chars += len(delta["reasoning_content"])
            if ("content" in delta or "reasoning" in delta
                    or "reasoning_content" in delta):
                n_tokens += 1
    elapsed = time.monotonic() - t0
    return {
        "model": model,
        "ttft_s": round(first_token_t, 2) if first_token_t else None,
        "total_s": round(elapsed, 2),
        "tokens": n_tokens,
        "tok_s": round(n_tokens / elapsed, 2) if elapsed else 0,
        "content_chars": content_chars,
        "reason_chars": reason_chars,
    }


def main():
    args = parse_args()
    url = args.url or (OLLAMA_URL if args.ollama else MLX_URL)
    models = args.models or (OLLAMA_MODELS if args.ollama else MLX_MODELS)

    results = []
    for m in models:
        print(f"▶ {m}...", flush=True)
        try:
            r = bench(url, m, args.prompt, args.max_tokens)
            results.append(r)
            print(f"  ttft={r['ttft_s']}s total={r['total_s']}s "
                  f"tokens={r['tokens']} ({r['tok_s']} tok/s) "
                  f"content={r['content_chars']}c reasoning={r['reason_chars']}c")
        except Exception as e:
            print(f"  ERRO: {e}")
            results.append({"model": m, "error": str(e)})

    print("\n=== RESUMO (ordenado por tok/s) ===")
    ok = [r for r in results if "error" not in r]
    ok.sort(key=lambda r: r["tok_s"], reverse=True)
    for r in ok:
        print(f"{r['tok_s']:>7} tok/s | {r['total_s']:>7}s | ttft {r['ttft_s']:>5}s | "
              f"{r['model']:<45} content={r['content_chars']}c reasoning={r['reason_chars']}c")
    for r in results:
        if "error" in r:
            print(f"  FALHOU: {r['model']}: {r['error']}")
    return 0 if not any("error" in r for r in results) else 1


if __name__ == "__main__":
    sys.exit(main())
