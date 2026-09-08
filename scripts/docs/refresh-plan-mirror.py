#!/usr/bin/env python3
"""Refresh docs/product-plan.md from a saved BMemory get_doc result.

Usage: refresh-plan-mirror.py <get_doc result file>
The BMemory record specification/open-impact-product-plan.md is canonical; this
script strips its YAML frontmatter and writes the body as the repository mirror.
"""
import json
import re
import sys

raw = open(sys.argv[1]).read()
doc = json.loads(raw[raw.find('['):])[0]
content = doc['content']
match = re.match(r'^---\n.*?\n---\n\n?', content, re.S)
body = content[match.end():] if match else content
open('docs/product-plan.md', 'w').write(body)
print(f"{len(body.splitlines())} lines written; em dashes: {body.count(chr(8212))}")
