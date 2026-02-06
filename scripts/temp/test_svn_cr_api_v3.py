#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SVN Code Review API Test - Using Official /api/v3 API
Based on: https://git.woa.com/help/menu/api/svn/cr/svn_review.html

API Endpoints:
- POST /api/v3/svn/projects/:id/reviews - Create review (code on server mode)
- GET /api/v3/svn/projects/:id/reviews - List reviews
- GET /api/v3/svn/projects/:id/reviews/:review_id - Get review by ID
- POST /api/v3/svn/projects/:id/review/:review_id/invite - Invite reviewers
- PUT /api/v3/svn/projects/:id/review/:review_id - Update review

Parameters for creating review (code on server mode):
- source_revision: Source SVN revision
- target_revision: Target SVN revision
- path: Path to review (optional, default is project root)
- title: Review title
- description: Review description
- reviewer_ids: Reviewer user IDs (comma separated)
"""

import json
import subprocess
import urllib.parse
import urllib.request
from pathlib import Path


# ==============================================================================
# Configuration
# ==============================================================================

GONGFENG_HOST = "git.woa.com"
API_BASE_URL = f"https://{GONGFENG_HOST}/api/v3"


def get_oauth_token() -> str:
    token_file = Path.home() / '.svn_flow' / 'gongfeng_token.json'
    with open(token_file) as f:
        return json.load(f).get('access_token')


def get_svn_info(path: str) -> dict:
    """Get SVN info including URL and revision"""
    result = subprocess.run(f'svn info "{path}"', shell=True, capture_output=True)
    info = {}
    for line in result.stdout.decode('utf-8').strip().split('\n'):
        if ':' in line:
            key, value = line.split(':', 1)
            info[key.strip()] = value.strip()
    return info


def get_svn_log(path: str, limit: int = 5) -> list:
    """Get recent SVN log entries"""
    result = subprocess.run(
        f'svn log -l {limit} --xml "{path}"',
        shell=True,
        capture_output=True
    )
    import xml.etree.ElementTree as ET
    root = ET.fromstring(result.stdout.decode('utf-8'))
    entries = []
    for entry in root.findall('.//logentry'):
        entries.append({
            'revision': entry.get('revision'),
            'author': entry.findtext('author', ''),
            'date': entry.findtext('date', ''),
            'msg': entry.findtext('msg', ''),
        })
    return entries


def api_request(token: str, method: str, endpoint: str, data: dict = None, timeout: int = 60):
    """Make API request to /api/v3"""
    url = f"{API_BASE_URL}{endpoint}"
    
    headers = {
        'OAUTH-TOKEN': token,  # Official API uses OAUTH-TOKEN
    }
    
    if data:
        encoded = urllib.parse.urlencode(data, doseq=True).encode('utf-8')
        headers['Content-Type'] = 'application/x-www-form-urlencoded'
    else:
        encoded = None
    
    req = urllib.request.Request(url, data=encoded, method=method, headers=headers)
    
    print(f"  [DEBUG] {method} {url}")
    if data:
        print(f"  [DEBUG] Params: {json.dumps(data, indent=2, ensure_ascii=False)[:500]}")
    
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            result = resp.read().decode('utf-8')
            if result:
                return json.loads(result)
            return {}
    except urllib.error.HTTPError as e:
        error_body = e.read().decode('utf-8')
        print(f"  [ERROR] HTTP {e.code}: {error_body}")
        try:
            return json.loads(error_body)
        except:
            return {'error': error_body}
    except Exception as e:
        print(f"  [ERROR] {e}")
        return {'error': str(e)}


def main():
    work_dir = '/Users/firoyang/workspace/b1'
    project_id = 1618099
    project_path = 'firoyang/test'
    
    print("=" * 70)
    print("SVN Code Review API Test - Official /api/v3 API")
    print("Reference: https://git.woa.com/help/menu/api/svn/cr/svn_review.html")
    print("=" * 70)
    
    # Get token
    token = get_oauth_token()
    print(f"[OK] Token loaded (len={len(token)})")
    
    # Get SVN info
    print("\n[Step 1] Getting SVN info...")
    svn_info = get_svn_info(work_dir)
    svn_url = urllib.parse.unquote(svn_info.get('URL', ''))
    current_rev = svn_info.get('Revision', '')
    print(f"  SVN URL: {svn_url}")
    print(f"  Current Revision: {current_rev}")
    
    # Get recent log
    print("\n[Step 2] Getting SVN log...")
    log = get_svn_log(work_dir, 5)
    for entry in log:
        print(f"  r{entry['revision']}: {entry['msg'][:50] if entry['msg'] else '(no message)'}")
    
    # Determine source and target revisions
    if len(log) >= 2:
        source_rev = log[0]['revision']  # Latest revision
        target_rev = log[1]['revision']  # Previous revision
    else:
        source_rev = current_rev
        target_rev = str(int(current_rev) - 1)
    
    print(f"\n  Source Revision (newer): r{source_rev}")
    print(f"  Target Revision (older): r{target_rev}")
    
    # Test 1: List existing reviews
    print("\n[Step 3] Listing existing reviews...")
    reviews = api_request(token, 'GET', f'/svn/projects/{project_id}/reviews')
    if isinstance(reviews, list):
        print(f"  Found {len(reviews)} review(s)")
        for r in reviews[:3]:
            print(f"    - #{r['iid']}: {r['title'][:40]}... [{r['state']}]")
    
    # Test 2: Create new review (code on server mode)
    print("\n[Step 4] Creating new review (code on server mode)...")
    title = f"[Test] API v3 Review r{target_rev}->r{source_rev}"
    description = f"Test review created via /api/v3 API.\n\nComparing r{target_rev} to r{source_rev}."
    
    result = api_request(
        token, 'POST',
        f'/svn/projects/{project_id}/reviews',
        {
            'source_revision': source_rev,
            'target_revision': target_rev,
            'title': title,
            'description': description,
            # 'path': svn_url,  # Optional, can be specific path
        },
        timeout=120
    )
    
    if 'error' in result:
        print(f"\n[WARNING] Create review returned error")
    elif result.get('id'):
        print(f"\n[SUCCESS] Review created!")
        review_id = result['id']
        review_iid = result['iid']
        state = result['state']
        print(f"  Review ID: {review_id}")
        print(f"  Review IID: {review_iid}")
        print(f"  State: {state}")
        print(f"  Type: {result.get('reviewable_type')}")
        print(f"  URL: https://{GONGFENG_HOST}/{project_path}/reviews/{review_iid}")
        
        # Test 3: Get review details
        print("\n[Step 5] Getting review details...")
        detail = api_request(token, 'GET', f'/svn/projects/{project_id}/reviews/{review_id}')
        if detail.get('id'):
            print(f"  Title: {detail['title']}")
            print(f"  Author: {detail['author']['username']}")
            print(f"  Created: {detail['created_at']}")
        
        # Test 4: Invite reviewer (optional)
        print("\n[Step 6] Testing invite reviewer API...")
        invite_result = api_request(
            token, 'POST',
            f'/svn/projects/{project_id}/review/{review_id}/invite',
            {'user_id': 3042}  # Self-invite as test
        )
        print(f"  Invite result: {invite_result}")
        
        # Test 5: Update review
        print("\n[Step 7] Testing update review API...")
        update_result = api_request(
            token, 'PUT',
            f'/svn/projects/{project_id}/review/{review_id}',
            {
                'title': title + ' (updated)',
                'description': description + '\n\n[Updated via API]'
            }
        )
        print(f"  Update result: {update_result.get('id') if isinstance(update_result, dict) else update_result}")
    else:
        print(f"  Unexpected result: {result}")
    
    # Final: List all reviews again
    print("\n[Step 8] Final review list...")
    reviews = api_request(token, 'GET', f'/svn/projects/{project_id}/reviews')
    if isinstance(reviews, list):
        print(f"  Total {len(reviews)} review(s):")
        for r in reviews[:5]:
            print(f"    - #{r['iid']}: {r['title'][:50]}... [{r['state']}] ({r['reviewable_type']})")
    
    print("\n" + "=" * 70)
    print("Test Complete!")
    print("=" * 70)


if __name__ == '__main__':
    main()
