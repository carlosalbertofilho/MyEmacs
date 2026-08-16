import re

def md_to_org(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    lines = content.split('\n')
    org_lines = []
    
    for line in lines:
        # Convert headings
        if line.startswith('#'):
            match = re.match(r'^(#+)\s+(.*)', line)
            if match:
                level = len(match.group(1))
                text = match.group(2)
                # If it's a D section (D1, D2... D9), make it a TODO
                if re.match(r'^D\d+\.', text):
                    org_lines.append(f"{'*' * level} TODO {text}")
                    org_lines.append("  :PROPERTIES:")
                    org_lines.append("  :STATUS: planning")
                    org_lines.append("  :TAGS: :magent:planning:")
                    org_lines.append("  :END:")
                else:
                    org_lines.append(f"{'*' * level} {text}")
            else:
                org_lines.append(line)
        # Convert blockquotes
        elif line.startswith('> '):
            org_lines.append(line.replace('> ', '#+BEGIN_QUOTE\n', 1) + '\n#+END_QUOTE')
        else:
            org_lines.append(line)
            
    # Fix blockquotes (remove consecutive BEGIN/END)
    final_org = []
    in_quote = False
    for line in org_lines:
        if line.startswith('#+BEGIN_QUOTE'):
            if not in_quote:
                final_org.append('#+BEGIN_QUOTE')
                in_quote = True
            final_org.append(line.replace('#+BEGIN_QUOTE\n', ''))
        elif in_quote and not line.strip():
            final_org.append('#+END_QUOTE')
            final_org.append(line)
            in_quote = False
        else:
            final_org.append(line)
    if in_quote:
        final_org.append('#+END_QUOTE')
        
    # Clean up the output string
    out = '\n'.join(final_org)
    out = out.replace('#+END_QUOTE\n#+END_QUOTE', '#+END_QUOTE')
    
    with open('TODO.org', 'w', encoding='utf-8') as f:
        f.write(out)

md_to_org('TODO.md')
