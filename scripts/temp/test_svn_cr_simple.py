#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SVN Code Review API Test Script (CORRECTED VERSION)

IMPORTANT FINDINGS:
- API Base URL: /api/web/v1 (NOT /api/v3!)
- Auth Header: Authorization: Bearer ${token} (NOT OAUTH-TOKEN!)

Based on gongfeng-cli implementation:
- packages/cr/src/api-service.ts
- packages/base/src/vars.ts (apiUrl = /api/web/v1)
- packages/base/src/pre-auth.ts (Authorization: Bearer)
"""

import json
import subprocess
import urllib.parse
import urllib.request
from pathlib import Path


# ==============================================================================
# Configuration - CORRECTED!
# ==============================================================================

GONGFENG_HOST = "git.woa.com"
API_BASE_URL = f"https://{GONGFENG_HOST}/api/web/v1"  # IMPORTANT: /api/web/v1 not /api/v3!
MAX_UPLOAD_SIZE = 5 * 1024 * 1024  # 5MB


def get_oauth_token() -> str:
    token_file = Path.home() / '.svn_flow' / 'gongfeng_token.json'
    with open(token_file) as f:
        return json.load(f).get('access_token')


def get_svn_url(path: str) -> str:
    result = subprocess.run(f'svn info "{path}"', shell=True, capture_output=True)
    for line in result.stdout.decode('utf-8').strip().split('\n'):
        if line.startswith('URL:'):
            return urllib.parse.unquote(line.split(' ', 1)[1].strip())
    return ""


def get_svn_diff(path: str) -> str:
    result = subprocess.run(f'svn diff "{path}"', shell=True, capture_output=True)
    return result.stdout.decode('utf-8')


def filter_diff(work_dir: str, diff: str) -> tuple[str, list[str]]:
    """Filter diff content and convert absolute paths to relative paths"""
    lines = diff.split('\n')
    filtered = []
    files = []
    keep = False
    last_line = ''
    is_head = False
    
    work_dir = work_dir.replace('\\', '/')
    
    for line in lines:
        if line.startswith('Index:'):
            filepath = line.split(':', 1)[1].strip().replace('\\', '/')
            # Convert absolute path to relative
            if filepath.startswith(work_dir):
                rel_path = filepath[len(work_dir):].lstrip('/')
            else:
                rel_path = filepath.split('/')[-1]
            
            if rel_path and rel_path not in files:
                files.append(rel_path)
                line = f"Index: {rel_path}"
                keep = True
            else:
                keep = False
        
        if keep:
            # Fix --- and +++ lines
            if line.startswith('--- ') and last_line.strip() == '=' * 67:
                line = f"--- {line[4:].replace(work_dir, '').lstrip('/')}"
                is_head = True
            if line.startswith('+++ ') and is_head:
                line = f"+++ {line[4:].replace(work_dir, '').lstrip('/')}"
                is_head = False
            
            filtered.append(line)
        
        last_line = line
    
    return '\r\n'.join(filtered), files


def api_request(token: str, method: str, endpoint: str, data: dict = None, timeout: int = 30):
    """Make API request with correct authentication"""
    url = f"{API_BASE_URL}{endpoint}"
    
    headers = {
        'Authorization': f'Bearer {token}',  # IMPORTANT: Bearer token, not OAUTH-TOKEN!
        'User-Agent': 'GFCLI',
    }
    
    if data:
        encoded = urllib.parse.urlencode(data, doseq=True).encode('utf-8')
        headers['Content-Type'] = 'application/x-www-form-urlencoded'
    else:
        encoded = None
    
    req = urllib.request.Request(url, data=encoded, method=method, headers=headers)
    
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        error_body = e.read().decode('utf-8')
        print(f"[ERROR] HTTP {e.code}: {error_body}")
        return None
    except Exception as e:
        print(f"[ERROR] {e}")
        return None


def main():
    work_dir = '/Users/firoyang/workspace/b1'
    
    print("=" * 60)
    print("SVN Code Review API Test (CORRECTED)")
    print("API Base: " + API_BASE_URL)
    print("=" * 60)
    
    # Get token
    token = get_oauth_token()
    print(f"[OK] Token loaded (len={len(token)})")
    
    # Get SVN URL
    svn_url = get_svn_url(work_dir)
    print(f"[OK] SVN URL: {svn_url}")
    
    # Step 1: Get project info via analyze_project API
    print("\n[Step 1] Getting project info...")
    project = api_request(
        token, 'GET',
        f"/svn/project/cli/analyze_project?fullPath={urllib.parse.quote(svn_url)}"
    )
    
    if not project:
        print("[ERROR] Failed to get project info")
        return
    
    project_id = project.get('id')
    project_path = project.get('fullPath')
    print(f"[OK] Project ID: {project_id}")
    print(f"[OK] Project Path: {project_path}")
    
    # Step 2: Get SVN diff
    print("\n[Step 2] Getting SVN diff...")
    raw_diff = get_svn_diff(work_dir)
    if not raw_diff.strip():
        print("[ERROR] No changes found")
        return
    
    print(f"[OK] Raw diff: {len(raw_diff)} bytes")
    
    # Step 3: Filter diff
    print("\n[Step 3] Filtering diff...")
    diff_content, files = filter_diff(work_dir, raw_diff)
    
    if not diff_content:
        print("[ERROR] No valid diff after filtering")
        return
    
    print(f"[OK] Filtered diff: {len(diff_content)} bytes")
    print(f"[OK] Changed files: {files}")
    print(f"\n[DEBUG] Diff preview:\n{diff_content[:300]}...")
    
    # Step 4: Get preset reviewers (optional)
    print("\n[Step 4] Getting preset reviewers...")
    urls = [f"{svn_url}/{f}" for f in files if f]
    preset = api_request(
        token, 'POST',
        f"/svn/projects/{project_id}/path_rules/code_review/preset_config",
        {'filePaths': urls}
    )
    
    reviewers = []
    if preset and preset.get('reviewers'):
        reviewers = preset['reviewers']
        print(f"[OK] Preset reviewers: {[r.get('username') for r in reviewers]}")
    else:
        print("[WARN] No preset reviewers")
    
    # Step 5: Create CR
    print("\n[Step 5] Creating Code Review...")
    title = "[Test] SVN CR via Python (Corrected)"
    description = f"Test CR created via Python script.\n\nChanged files:\n" + "\n".join([f"- {f}" for f in files])
    reviewer_ids = ",".join([str(r.get('id')) for r in reviewers]) if reviewers else ""
    
    print(f"  Title: {title}")
    print(f"  Target Path: {svn_url}")
    print(f"  Reviewer IDs: {reviewer_ids or '(none)'}")
    
    result = api_request(
        token, 'POST',
        f"/svn/projects/{project_id}/merge_requests",
        {
            'targetProjectId': str(project_id),
            'sourceProjectId': str(project_id),
            'diffContent': diff_content,
            'diffOnlyFileName': 'false',
            'targetPath': svn_url,
            'sourcePath': svn_url,
            'title': title,
            'description': description,
            'reviewerIds': reviewer_ids,
        },
        timeout=125
    )
    
    if not result:
        print("\n[ERROR] Failed to create CR")
        return
    
    print("\n" + "=" * 60)
    print("SUCCESS! Code Review Created!")
    print("=" * 60)
    
    review_iid = result.get('iid')
    review_id = result.get('id')
    state = result.get('state')
    
    print(f"  Review ID: {review_id}")
    print(f"  Review IID: {review_iid}")
    print(f"  State: {state}")
    
    web_url = f"https://{GONGFENG_HOST}/{project_path}/reviews/{review_iid}"
    print(f"  Web URL: {web_url}")
    
    # Step 6: Test review operations
    print("\n[Step 6] Testing review operations...")
    
    # Get review details
    print("  Fetching review details...")
    review = api_request(token, 'GET', f"/projects/{project_id}/reviews/{review_iid}")
    if review:
        print(f"    Title: {review.get('title')}")
        print(f"    State: {review.get('state')}")
    
    # Add comment
    print("  Adding comment...")
    comment_result = api_request(
        token, 'PATCH',
        f"/projects/{project_id}/reviews/{review_iid}/summary?reviewerEvent=comment&summary=Test%20comment%20from%20Python"
    )
    print(f"    Result: {'OK' if comment_result is not False else 'Failed'}")
    
    # Approve
    print("  Approving review...")
    approve_result = api_request(
        token, 'PATCH',
        f"/projects/{project_id}/reviews/{review_iid}/summary?reviewerEvent=approve&summary=LGTM"
    )
    print(f"    Result: {'OK' if approve_result is not False else 'Failed'}")
    
    # Close
    print("  Closing review...")
    close_result = api_request(
        token, 'PATCH',
        f"/projects/{project_id}/reviews/{review_iid}/summary?reviewerEvent=close"
    )
    print(f"    Result: {'OK' if close_result is not False else 'Failed'}")
    
    print("\n" + "=" * 60)
    print("Test Complete!")
    print("=" * 60)
    print(f"\nCreated CR: {web_url}")


if __name__ == '__main__':
    main()
