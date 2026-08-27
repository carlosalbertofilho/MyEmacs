#!/usr/bin/env python3
"""bench-code-repair.py — Bateria de benchmark Code-Repair (F7-ben).

Avalia como modelos locais diagnosticam e corrigem código quebrado em
função do *profile* do agente e da linguagem. Orquesta a matriz
Modelo × Profile × Linguagem via `bin/magent-cli run` e valida cada
correção rodando o teste da linguagem (go test / npm test / pytest).

Uso:
  python3 bin/bench-code-repair.py                 # toda a matriz
  python3 bin/bench-code-repair.py --model "LM Studio Local/nvidia/nemotron-3-nano-4b" --profile coder
  python3 bin/bench-code-repair.py --lang go --profiles coder qa auditor
  python3 bin/bench-code-repair.py --dry-run       # mostra o plano sem rodar
  python3 bin/bench-code-repair.py --results /tmp/bench-results

Saída: JSON (resumo) + JSONL (por run) em /tmp/bench-results/ (ou --results).

Cada caso tem código-fonte quebrado (bugs conhecidos) + comando de validação
(go test / npm test / pytest). Acurácia = teste passa após correção.
"""
import argparse
import datetime
import json
import os
import shutil
import subprocess
import sys
import time

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAGENT_CLI = os.path.join(REPO_ROOT, "bin", "magent-cli")

DEFAULT_RESULTS_DIR = "/tmp/bench-results"

# ── Modelos (7): 4 novos LM Studio + 3 baseline MLX ──────────────────
# Formato: "BACKEND/MODEL" — o mesmo aceito por `magent-cli run --model`.
# O nome do modelo deve ser o ID exato servido pelo backend local
# (checar `curl <host>/v1/models`). Ajuste os IDs após o download na GUI.
# Modelos já baixados no LM Studio (checar `lms ls` / `/v1/models`):
#   nvidia/nemotron-3-nano-4b (4B) e prism-ml/bonsai-27b (27B)
MODELS = [
    # LM Studio Local (127.0.0.1:1234 /v1/models) — baixados
    "LM Studio Local/nvidia/nemotron-3-nano-4b",
    "LM Studio Local/prism-ml/bonsai-27b",
    # MLX Local (127.0.0.1:8081) — baseline já instalado
    "MLX Local/mlx-community/Qwen3.5-9B-MLX-4bit",
    "MLX Local/mlx-community/gemma-4-e2b-it-4bit",
    "MLX Local/mlx-community/DeepSeek-R1-Distill-Qwen-14B-4bit",
]

# ── Profiles (9) ──────────────────────────────────────────────────────
ALL_PROFILES = ["explore", "general", "coder", "sysadmin", "planner",
                "tech-writer", "auditor", "sec-ops", "qa"]
DEFAULT_PROFILES = ["coder", "qa", "auditor", "explore"]

LANGS = ["go", "react", "python"]


def parse_args():
    ap = argparse.ArgumentParser(description="Benchmark de code-repair (F7-ben).")
    ap.add_argument("--model", action="append", default=None, dest="models",
                    help="Modelo a testar 'BACKEND|MODEL'. Repetível. Default: 7.")
    ap.add_argument("--profiles", nargs="*", default=DEFAULT_PROFILES,
                    help="Profiles a testar (default: %(default)s).")
    ap.add_argument("--lang", choices=LANGS, default=None,
                    help="Filtrar por linguagem.")
    ap.add_argument("--dry-run", action="store_true",
                    help="Mostra o plano sem executar.")
    ap.add_argument("--results", default=DEFAULT_RESULTS_DIR,
                    help="Dir de saída dos resultados.")
    ap.add_argument("--timeout", type=int, default=600,
                    help="Timeout por run (segundos, default: 600).")
    return ap.parse_args()


# ── Código quebrado (fixtures embutidas) ─────────────────────────────
# Cada fixture: dict com arquivos {path: content}, comando de validação,
# e descrição dos bugs.
FIXTURES = {
    "go": {
        "validate": ["go", "test", "./..."],
        "files": {
            "go.mod": "module benchmark/broker\n\ngo 1.21\n",
            "broker.go": '''package broker

import (
	"fmt"
	"sync"
)

// Broker distribui mensagens entre consumidores.
// BUG-1: data race — `chans` lido/escrito sem lock.
// BUG-2: goroutine leak — `Send` bloqueia para canal sem receiver pronto.
// BUG-3: nil deref implícito — itera mapa e envia sem tratar fila cheia.
type Broker struct {
	chans map[string]chan string
}

func NewBroker() *Broker {
	return &Broker{chans: make(map[string]chan string)}
}

// Register cria um canal para o consumidor name.
func (b *Broker) Register(name string) chan string {
	// BUG-1: escreve em chans sem lock. Concorrente entre Register e Send.
	b.chans[name] = make(chan string, 0)
	return b.chans[name]
}

// Send entrega msg para todos os consumidores.
func (b *Broker) Send(msg string) {
	// BUG-3: send bloqueia (buffer 0) sem receiver pronto.
	for name, ch := range b.chans {
		ch <- msg
		_ = name
	}
}
''',
            "broker_test.go": '''package broker

import (
	"fmt"
	"sync"
	"testing"
)

func TestBrokerSendDelivers(t *testing.T) {
	b := NewBroker()
	ch := b.Register("consumer-1")
	var got string
	done := make(chan struct{})
	go func() {
		got = <-ch
		close(done)
	}()
	b.Send("hello")
	<-done
	if got != "hello" {
		t.Errorf("got %q, want %q", got, "hello")
	}
}

func TestBrokerRegisterConcurrent(t *testing.T) {
	b := NewBroker()
	var wg sync.WaitGroup
	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			_ = b.Register(fmt.Sprintf("c%d", i))
		}(i)
	}
	wg.Wait()
}
''',
        },
    },
    "react": {
        "validate": ["npm", "test", "--", "--watchAll=false"],
        "files": {
            "package.json": '''{
  "name": "bench-react",
  "version": "1.0.0",
  "private": true,
  "scripts": { "test": "react-scripts test" },
  "dependencies": { "react": "^18.2.0", "react-dom": "^18.2.0", "react-scripts": "5.0.1" },
  "devDependencies": {}
}
''',
            "src/Counter.js": '''import React, { useState, useEffect } from "react";

// BUG-1: stale closure — `count` no useEffect usa valor congelado.
// BUG-2: infinite loop — `count` no array de deps, increment a cada render.
// BUG-3: mutation de props/state — seta count + 1 no efeito.
export default function Counter() {
  const [count, setCount] = useState(0);
  useEffect(() => {
    const id = setInterval(() => {
      setCount(count + 1); // BUG-1: count é stale (captura 0 sempre)
    }, 1000);
    return () => clearInterval(id);
  }, [count]); // BUG-2: re-cria intervalo e loop
  return <div data-testid="count">{count}</div>;
}
''',
            "src/Counter.test.js": '''import { render, waitFor, screen } from "@testing-library/react";
import Counter from "./Counter";

test("counter increments over time", async () => {
  render(<Counter />);
  await waitFor(() => {
    expect(screen.getByTestId("count").textContent).toBe("3");
  }, { timeout: 5000 });
});
''',
        },
    },
    "python": {
        "validate": ["pytest"],
        "files": {
            "aoi.py": '''# BUG-1: O(n^2) — `find_all` percorre a lista para cada busca.
# BUG-2: resource leak — arquivo aberto nunca é fechado.
# BUG-3: wrong exception — levanta ValueError ao invés de KeyError.
class Index:
    def __init__(self, keys):
        self._keys = keys

    def find_all(self, target):
        # BUG-1: percorre toda a lista por busca (sem dict).
        result = []
        for k in self._keys:
            if k == target:
                result.append(k)
        return result

    def lookup(self, target):
        # BUG-3: levanta o tipo de exceção errado p/ chave faltante.
        try:
            return self._keys.index(target)
        except ValueError:
            raise ValueError(f"{target!r} not found")

    def save(self, path):
        # BUG-2: arquivo nunca é fechado.
        f = open(path, "w")
        f.write("\\n".join(self._keys))
''',
            "test_aoi.py": '''import pytest
from aoi import Index

def test_find_all_large():
    idx = Index(list(range(1000)))
    assert idx.find_all(500) == [500]

def test_lookup_missing_raises_keyerror():
    idx = Index(["a", "b"])
    with pytest.raises(KeyError):
        idx.lookup("missing")

def test_save_roundtrip(tmp_path):
    idx = Index(["x", "y"])
    p = tmp_path / "idx.txt"
    idx.save(str(p))
    assert p.exists()
''',
        },
    },
}


def get_fixture(lang, workdir):
    """Copia os fixtures da linguagem para workdir. Retorna (base, validate, prompt)."""
    fx = FIXTURES.get(lang)
    if not fx:
        raise ValueError(f"Sem fixture embutido para linguagem: {lang}")
    for path, content in fx["files"].items():
        target = os.path.join(workdir, path)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, "w") as f:
            f.write(content)
    prompt = (
        f"O diretório de trabalho contém código {lang} QUEBRADO. "
        f"Diagnostique os bugs e CORRIJA o código. "
        f"Depois rode o comando de validação: {' '.join(fx['validate'])}. "
        f"Responda com o que mudou."
    )
    return workdir, fx["validate"], prompt


def run_case(cli_args, workdir, timeout):
    """Roda magent-cli run num subprocess. Retorna (exit, stdout, elapsed)."""
    t0 = time.time()
    try:
        proc = subprocess.run(
            cli_args, capture_output=True, text=True,
            timeout=timeout,
            cwd=workdir,
        )
        return proc.returncode, proc.stdout + proc.stderr, time.time() - t0
    except subprocess.TimeoutExpired:
        return 124, "", time.time() - t0


def validate(validate_cmd, workdir, timeout=120):
    """Roda o comando de validação da linguagem. Retorna (True/False, output)."""
    try:
        proc = subprocess.run(
            validate_cmd, capture_output=True, text=True,
            timeout=timeout, cwd=workdir,
        )
        return proc.returncode == 0, proc.stdout + proc.stderr
    except subprocess.TimeoutExpired:
        return False, "TIMEOUT"
    except FileNotFoundError:
        return False, "cmd not found"


def main():
    args = parse_args()
    models = args.models or MODELS

    # Build plano
    plan = []
    langs = [args.lang] if args.lang else LANGS
    for model in models:
        if "/" in model:
            backend, modelname = model.split("/", 1)
        else:
            backend, modelname = "LM Studio Local", model
        for profile in args.profiles:
            for lang in langs:
                plan.append((backend, modelname, profile, lang))

    print("== Bench Code-Repair (F7-ben) ==")
    print(f"Total de runs planejados: {len(plan)}")
    for b, m, p, l in plan:
        print(f"  {b} | {m} | profile={p} | lang={l}")

    if args.dry_run:
        print("\n--dry-run: nenhum run executado.")
        return

    os.makedirs(args.results, exist_ok=True)
    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    results_jsonl = os.path.join(args.results, f"bench-{ts}.jsonl")
    results = []

    for idx, (backend, modelname, profile, lang) in enumerate(plan, 1):
        # workdir próprio por run
        workdir = os.path.join(args.results, "work", f"{idx:03d}-{lang}-{profile}")
        shutil.rmtree(workdir, ignore_errors=True)
        os.makedirs(workdir, exist_ok=True)

        # Prepara fixture
        try:
            base, validate_cmd, prompt = get_fixture(lang, workdir)
        except ValueError as e:
            print(f"[{idx}/{len(plan)}] SKIP {lang}: {e}")
            continue

        # magent-cli run --model "backend|model" --profile p --prompt ...
        cli_args = [
            MAGENT_CLI, "run",
            "--model", f"{backend}/{modelname}",
            "--profile", profile,
            "--prompt", prompt,
            "--run-timeout", str(args.timeout),
        ]
        print(f"[{idx}/{len(plan)}] {backend}|{modelname} :: {profile} :: {lang} ...")
        exit_code, output, elapsed = run_case(cli_args, workdir, args.timeout)
        print(f"    exit={exit_code} elapsed={elapsed:.1f}s")

        # Valida
        ok, val_output = validate(validate_cmd, workdir)

        rec = {
            "run": idx,
            "backend": backend,
            "model": modelname,
            "profile": profile,
            "lang": lang,
            "exit_code": exit_code,
            "elapsed_s": round(elapsed, 2),
            "test_ok": ok,
            "test_output": val_output[:2000],
            "agent_output": output[:2000],
        }
        results.append(rec)
        with open(results_jsonl, "a") as f:
            f.write(json.dumps(rec) + "\n")

        print(f"    test_ok={ok}")

    # Resumo
    summary_file = os.path.join(args.results, f"bench-{ts}.json")
    with open(summary_file, "w") as f:
        json.dump({"timestamp": ts, "runs": results, "summary": {
            "total": len(results),
            "passed": sum(1 for r in results if r["test_ok"]),
            "failed": sum(1 for r in results if not r["test_ok"]),
        }}, f, indent=2, ensure_ascii=False)

    passed = sum(1 for r in results if r["test_ok"])
    print(f"\n== Resumo: {passed}/{len(results)} testes passaram ==")
    print(f"Resultados: {results_jsonl} + {summary_file}")


if __name__ == "__main__":
    main()
