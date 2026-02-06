#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Extract detailed API documentation from HTML"""

import sys
import re
import html
import urllib.request

url = "https://git.woa.com/help/menu/api/svn/cr/svn_review.html"

req = urllib.request.Request(url)
with urllib.request.urlopen(req, timeout=30) as resp:
    content = resp.read().decode('utf-8')

# Remove script and style tags
content = re.sub(r"<script[^>]*>.*?</script>", "", content, flags=re.DOTALL)
content = re.sub(r"<style[^>]*>.*?</style>", "", content, flags=re.DOTALL)

def clean_html(text):
    text = re.sub(r'<[^>]+>', ' ', text)
    text = html.unescape(text)
    text = re.sub(r'\s+', ' ', text)
    return text.strip()

# Find table rows for parameters
tables = re.findall(r'<table>(.*?)</table>', content, re.DOTALL)

print("=" * 80)
print("SVN Review API - Detailed Documentation")
print("=" * 80)

# Find sections
sections = re.split(r'<h[1-4][^>]*>', content)

for section in sections:
    # Get section title
    title_match = re.match(r'[^<]*', section)
    if title_match:
        title = clean_html(title_match.group())
        if not title or len(title) < 3:
            continue
        
        # Check if this is a relevant section
        if any(kw in title for kw in ['新建', '评审', 'SVN', '邀请', '更新', '获取']):
            print(f"\n{'=' * 80}")
            print(f"## {title}")
            print('=' * 80)
            
            # Find API endpoint in this section
            endpoints = re.findall(r'<pre[^>]*><code[^>]*>(.*?)</code></pre>', section, re.DOTALL)
            for ep in endpoints:
                cleaned = clean_html(ep)
                print(f"\nEndpoint: {cleaned}")
            
            # Find parameter tables
            table_match = re.search(r'<table>(.*?)</table>', section, re.DOTALL)
            if table_match:
                table_content = table_match.group(1)
                # Extract rows
                rows = re.findall(r'<tr>(.*?)</tr>', table_content, re.DOTALL)
                if rows:
                    print("\nParameters:")
                    for row in rows:
                        cells = re.findall(r'<t[dh][^>]*>(.*?)</t[dh]>', row, re.DOTALL)
                        if cells:
                            cleaned_cells = [clean_html(c) for c in cells]
                            if cleaned_cells and cleaned_cells[0] != '参数':
                                print(f"  - {' | '.join(cleaned_cells)}")