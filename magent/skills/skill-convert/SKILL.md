---
name: skill-convert
description: Guides the agent on how to convert existing skills to Magent format using the local Python script `bin/skill-convert`.
type: instruction
capability: true
---

# Skill Convert

This skill provides instructions on how to use the `bin/skill-convert` utility script to migrate agent skills between platforms (OpenCode, Gemini/Antigravity, and Magent).

## Usage

When you need to migrate or convert a skill to the Magent format, use the local Python script located at `bin/skill-convert` in the MyEmacs repository.

### Command Line Interface

Run the script from the root of the MyEmacs repository (`/Users/carlosfilho/Projects/Github/MyEmacs`):

```bash
python3 bin/skill-convert [options]
```

### Options

*   `--sources <paths>`: List of source paths to recursively search for `SKILL.md` files (default: `~/.agents/skills` and `~/.gemini/config/plugins`).
*   `--dest <path>`: Destination directory for Magent skills (default: `magent/skills`).
*   `--backend <mlx|ollama|auto>`: Force a specific AI backend (`auto` dynamically checks MLX first, then Ollama).
*   `--only <pattern>`: Only convert skills whose folder name or file path matches this regex pattern.

### Examples

1.  Convert only the `modern-web-guidance` skill using the local Ollama backend:
    ```bash
    python3 bin/skill-convert --only modern-web-guidance --backend ollama
    ```

2.  Convert all skills found under source paths using automatic backend detection:
    ```bash
    python3 bin/skill-convert --backend auto
    ```

## Magent Skill Format Requirements

The script automatically ensures that target skills conform to the Magent structure:
1.  Creates a directory: `magent/skills/<name_of_skill>/`.
2.  Writes a `SKILL.md` with Magent-compatible frontmatter:
    ```yaml
    ---
    name: <skill-name>
    description: <description>
    type: instruction
    capability: true
    ---
    ```
3.  Instructs the LLM to strip any executable blocks, shell scripts, or command line tool calls (since Magent skills are purely text-based instructions).
