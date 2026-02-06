#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Temporary test script for Gongfeng CR API

Test scenarios:
1. Create a Code Review
2. Check CR status
3. Approve CR (self-approve for testing)

SVN working directory: /Users/firoyang/workspace/b1
Repository: https://cd.svn.woa.com/firoyang/test
Branch: b1
"""

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path

# Add parent directory to import gongfeng_cr module
sys.path.insert(0, str(Path(__file__).parent.parent / 'nodes'))

from gongfeng_cr import (
    GongfengCRClient,
    get_oauth_token,
    get_svn_info,
    get_svn_changed_files,
    parse_gongfeng_project_from_svn_url,
    parse_branch_from_svn_url,
)


def test_create_and_approve_cr():
    """Test creating and approving a Code Review"""
    
    work_dir = '/Users/firoyang/workspace/b1'
    base_url = 'https://git.woa.com'
    
    print("=" * 60)
    print("Gongfeng CR API Test")
    print("=" * 60)
    
    # Step 1: Get OAuth token
    print("\n[Step 1] Getting OAuth token...")
    oauth_token = get_oauth_token()
    if not oauth_token:
        print("[ERROR] No OAuth token found. Please run OAuth authorization first.")
        return False
    print(f"[OK] OAuth token retrieved: {oauth_token[:20]}...")
    
    # Step 2: Get SVN info
    print("\n[Step 2] Getting SVN info...")
    svn_info = get_svn_info(work_dir)
    if not svn_info:
        print(f"[ERROR] Failed to get SVN info for {work_dir}")
        return False
    
    svn_url = svn_info.get('URL', '')
    repo_root = svn_info.get('Repository Root', '')
    print(f"[OK] SVN URL: {svn_url}")
    print(f"[OK] Repository Root: {repo_root}")
    
    # Step 3: Parse project ID and branch
    print("\n[Step 3] Parsing project ID and branch...")
    project_id = parse_gongfeng_project_from_svn_url(repo_root)
    current_branch = parse_branch_from_svn_url(svn_url)
    
    print(f"[OK] Project ID: {project_id}")
    print(f"[OK] Current Branch: {current_branch}")
    
    if not project_id:
        print("[ERROR] Could not parse project ID from SVN URL")
        return False
    
    # Step 4: Get changed files
    print("\n[Step 4] Getting changed files...")
    changed_files = get_svn_changed_files(work_dir)
    print(f"[OK] Found {len(changed_files)} changed files:")
    for status, file_path in changed_files:
        print(f"    [{status}] {file_path}")
    
    if not changed_files:
        print("[WARN] No changed files found. Creating CR may fail.")
    
    # Step 5: Create API client
    print("\n[Step 5] Creating API client...")
    client = GongfengCRClient(
        base_url=base_url,
        oauth_token=oauth_token,
    )
    print("[OK] API client created")
    
    # Step 6: Create Code Review
    print("\n[Step 6] Creating Code Review...")
    
    # For testing, we create a CR from b1 branch to trunk
    source_branch = current_branch  # b1
    target_branch = 'trunk'
    title = f"[Test] CR API Test - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
    description = f"""Test CR created by automated script.

Changed files ({len(changed_files)}):
""" + "\n".join([f"- [{s}] {f}" for s, f in changed_files])
    
    print(f"    Title: {title}")
    print(f"    Source: {source_branch} -> Target: {target_branch}")
    
    try:
        review = client.create_review(
            project_id=project_id,
            title=title,
            source_branch=source_branch,
            target_branch=target_branch,
            description=description,
            reviewer_ids='',  # No specific reviewer
            approver_rule=1,  # Any one reviewer can approve
        )
        print("[OK] Code Review created successfully!")
        print(f"    Review ID: {review.get('id')}")
        print(f"    Review IID: {review.get('iid')}")
        print(f"    Web URL: {review.get('web_url')}")
        print(f"    State: {review.get('state')}")
        
        review_id = review.get('id')
        review_iid = review.get('iid')
        
    except Exception as e:
        print(f"[ERROR] Failed to create Code Review: {e}")
        return False
    
    # Step 7: Get Review details
    print("\n[Step 7] Getting Review details...")
    try:
        review_detail = client.get_review(project_id, review_id)
        print(f"[OK] Review state: {review_detail.get('state')}")
        print(f"[OK] Author: {review_detail.get('author', {}).get('name', 'N/A')}")
        print(f"[OK] Created at: {review_detail.get('created_at')}")
    except Exception as e:
        print(f"[WARN] Failed to get review details: {e}")
    
    # Step 8: Try to approve the CR (self-approve)
    print("\n[Step 8] Attempting to approve the CR...")
    print("[INFO] Note: Self-approval may not be allowed depending on project settings.")
    
    try:
        # The approve API endpoint
        encoded_project = client.encode_project_path(project_id)
        approve_endpoint = f"/projects/{encoded_project}/review/{review_id}/approve"
        
        approve_result = client._request('POST', approve_endpoint, {})
        print("[OK] Approve request sent!")
        print(f"    Result: {json.dumps(approve_result, indent=2, ensure_ascii=False)}")
    except Exception as e:
        print(f"[INFO] Approve result: {e}")
        print("[INFO] This is expected if self-approval is not allowed.")
    
    # Step 9: Check final state
    print("\n[Step 9] Checking final state...")
    try:
        final_review = client.get_review(project_id, review_id)
        final_state = final_review.get('state')
        print(f"[OK] Final state: {final_state}")
        print(f"[OK] Is approved: {client.is_approved(final_review)}")
        print(f"[OK] Is pending: {client.is_pending(final_review)}")
        print(f"[OK] Is rejected: {client.is_rejected(final_review)}")
    except Exception as e:
        print(f"[WARN] Failed to check final state: {e}")
    
    # Summary
    print("\n" + "=" * 60)
    print("Test Summary")
    print("=" * 60)
    print(f"Project ID: {project_id}")
    print(f"Review ID: {review_id}")
    print(f"Review IID: {review_iid}")
    print(f"Web URL: {base_url}/{project_id}/reviews/{review_iid}")
    print("\n[INFO] Please visit the Web URL above to manually approve the CR if needed.")
    
    return True


def test_list_reviews():
    """Test listing existing reviews"""
    
    base_url = 'https://git.woa.com'
    project_id = 'firoyang/test'
    
    print("\n" + "=" * 60)
    print("List Existing Reviews")
    print("=" * 60)
    
    oauth_token = get_oauth_token()
    if not oauth_token:
        print("[ERROR] No OAuth token found.")
        return
    
    client = GongfengCRClient(
        base_url=base_url,
        oauth_token=oauth_token,
    )
    
    # List reviews
    try:
        encoded_project = client.encode_project_path(project_id)
        endpoint = f"/projects/{encoded_project}/reviews"
        reviews = client._request('GET', endpoint, {'state': 'opened', 'per_page': 10})
        
        print(f"\n[OK] Found {len(reviews)} open reviews:")
        for r in reviews:
            print(f"    - [{r.get('iid')}] {r.get('title')} (state: {r.get('state')})")
    except Exception as e:
        print(f"[ERROR] Failed to list reviews: {e}")


def test_close_review(review_id: int):
    """Test closing a review"""
    
    base_url = 'https://git.woa.com'
    project_id = 'firoyang/test'
    
    print(f"\n[INFO] Closing review {review_id}...")
    
    oauth_token = get_oauth_token()
    if not oauth_token:
        print("[ERROR] No OAuth token found.")
        return
    
    client = GongfengCRClient(
        base_url=base_url,
        oauth_token=oauth_token,
    )
    
    try:
        encoded_project = client.encode_project_path(project_id)
        endpoint = f"/projects/{encoded_project}/review/{review_id}/close"
        result = client._request('POST', endpoint, {})
        print(f"[OK] Review closed: {result}")
    except Exception as e:
        print(f"[ERROR] Failed to close review: {e}")


if __name__ == '__main__':
    import argparse
    
    parser = argparse.ArgumentParser(description='Test Gongfeng CR API')
    parser.add_argument('--action', choices=['create', 'list', 'close'], default='create',
                        help='Action to perform (default: create)')
    parser.add_argument('--review-id', type=int, help='Review ID for close action')
    
    args = parser.parse_args()
    
    if args.action == 'create':
        test_create_and_approve_cr()
    elif args.action == 'list':
        test_list_reviews()
    elif args.action == 'close':
        if args.review_id:
            test_close_review(args.review_id)
        else:
            print("[ERROR] --review-id is required for close action")
