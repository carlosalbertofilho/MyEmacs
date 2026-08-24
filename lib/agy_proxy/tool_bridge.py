import asyncio
import json
import logging
import os
import subprocess

logger = logging.getLogger(__name__)

# List of native Emacs tools exposed to the LLM
EMACS_TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "org_smart_edit",
            "description": "Edita de forma estruturada um arquivo .org mantendo a integridade da AST. Exclusivo para arquivos .org (TODO.org, docs/ etc.).",
            "parameters": {
                "type": "object",
                "properties": {
                    "file_path": {"type": "string", "description": "Caminho relativo do arquivo (ex: TODO.org)"},
                    "action": {"type": "string", "enum": ["insert_snippet", "refactor_symbol", "validate_buffer", "toggle_checkbox"]},
                    "arg1": {"type": "string", "description": "Primeiro argumento da acao (ex: header para insert_snippet, ou old_text new_text para refatorar)"},
                    "arg2": {"type": "string", "description": "Segundo argumento opcional"}
                },
                "required": ["file_path", "action"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "elisp_smart_edit",
            "description": "Edita arquivos .el (Emacs Lisp) de forma transacional e balanceando parênteses.",
            "parameters": {
                "type": "object",
                "properties": {
                    "file_path": {"type": "string", "description": "Caminho relativo do arquivo lisp/"},
                    "action": {"type": "string", "enum": ["insert_snippet", "refactor_symbol", "validate_buffer"]},
                    "arg1": {"type": "string"},
                    "arg2": {"type": "string"}
                },
                "required": ["file_path", "action"]
            }
        }
    }
]

def inject_tools(body: dict) -> dict:
    """Injeta as ferramentas nativas do Emacs no payload da API."""
    if "tools" not in body:
        body["tools"] = []
    
    # Adiciona apenas se nao existir para evitar duplicatas
    existing_tools = {t.get("function", {}).get("name") for t in body.get("tools", [])}
    for t in EMACS_TOOLS:
        if t["function"]["name"] not in existing_tools:
            body["tools"].append(t)
            
    return body

async def execute_tool(tool_call: dict) -> dict:
    """Executa a chamada da ferramenta usando o bin/magent-cli."""
    call_id = tool_call.get("id")
    func = tool_call.get("function", {})
    name = func.get("name")
    
    # Parse arguments
    try:
        args = json.loads(func.get("arguments", "{}"))
    except Exception:
        args = {}
        
    logger.info(f"Executing Emacs tool {name} with args {args}")
    
    # Remapeia o nome do LLM para o formato lisp (ex: org_smart_edit -> org-smart-edit)
    lisp_tool_name = name.replace("_", "-")
    
    cli_args = [
        "bin/magent-cli",
        lisp_tool_name
    ]
    
    # Ordem dos args (file_path, action, arg1, arg2)
    # Assumindo que o magent-cli espera posicionalmente
    if "file_path" in args:
        cli_args.append(str(args["file_path"]))
    if "action" in args:
        cli_args.append(str(args["action"]))
    if "arg1" in args:
        cli_args.append(str(args["arg1"]))
    if "arg2" in args:
        cli_args.append(str(args["arg2"]))

    try:
        proc = await asyncio.create_subprocess_exec(
            *cli_args,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        stdout, stderr = await proc.communicate()
        
        if proc.returncode == 0:
            result_str = stdout.decode().strip()
        else:
            result_str = f"Error: {stderr.decode().strip()}"
            
        logger.info(f"Tool {name} result: {result_str}")
        
    except Exception as e:
        result_str = f"Exception executing tool: {str(e)}"
        logger.error(result_str)
        
    return {
        "tool_call_id": call_id,
        "role": "tool",
        "name": name,
        "content": result_str
    }

async def handle_tool_calls(response_message: dict) -> list[dict]:
    """Processa todas as tool calls de uma resposta do LLM."""
    tool_calls = response_message.get("tool_calls", [])
    if not tool_calls:
        return []
        
    tasks = [execute_tool(tc) for tc in tool_calls]
    results = await asyncio.gather(*tasks)
    return results
