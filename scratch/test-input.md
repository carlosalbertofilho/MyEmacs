# RAG Document Ingestion Test

This document describes the validation of our new local RAG ingestion pipeline using the Microsoft MarkItDown tool and local GPU-accelerated model (MLX) on macOS Mini M2.

## Technical Stack
- **Ingestion Engine:** Microsoft MarkItDown (supporting PDF, docx, xlsx, zip, youtube)
- **Formatting Engine:** MLX Local API (model Qwen3.5 9B / Qwen3 14B) running on port 8081
- **Target Format:** Emacs Org-Mode structured document

## Table of Performance
| Step | Action | Duration | Cost |
|---|---|---|---|
| 1 | Extract raw markdown | 0.4s | $0.00 (Local) |
| 2 | Refine Org Structure | 1.8s | $0.00 (Local GPU) |
| 3 | Save to docs/ | 0.1s | $0.00 |

## Conclusion
The hybrid approach combining MarkItDown with local LLMs provides a reliable and cost-effective method to maintain our RAG knowledge base.
