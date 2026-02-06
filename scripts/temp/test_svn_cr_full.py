#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SVN Code Review API Test Script

This script mimics gongfeng-cli's implementation for SVN CR operations.
Based on:
- packages/cr/src/api-service.ts
- packages/cr/src/commands/cr/create.ts
- packages/cr/src/util.ts
- packages/base/src/shell.ts

Key APIs:
- GET  /svn/project/cli/analyze_project - Get project info by SVN URL
- POST /svn/projects/:id/path_rules/code_review/preset_config - Get preset reviewers
- POST /svn/projects/:id/merge_requests - Create SVN CR (code-in-local mode)
- GET  /projects/:id/reviews/:iid - Get review details
- PATCH /projects/:id/reviews/:iid/summary - Approve/Close/Comment on review

IMPORTANT: The SVN CR API requires the project to have "code_in_local_review" enabled.
This must be configured in the Gongfeng Web Interface:
  Settings -> Code Review -> Enable "代码在本地"评审模式
"""

import json
import os
import subprocess
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Optional


# ==============================================================================
# Configuration
# ==============================================================================

GONGFENG_HOST = "git.woa.com"
API_BASE_URL = f"https://{GONGFENG_HOST}/api/v3"
MAX_UPLOAD_SIZE = 5 * 1024 * 1024  # 5MB

# Binary file extensions that should be handled differently
BINARY_EXTENSIONS = [
    'jar', 'class', 'svn', 'dll', 'bmp', 'jpeg', 'jpg', 'png', 'gif', 'pic',
    'tif', 'iso', 'rar', 'zip', 'exe', 'pdf', 'rm', 'avi', 'wav', 'aif', 'au',
    'mp3', 'ram', 'mpg', 'mov', 'swf', 'xls', 'xlsx', 'doc', 'docx', 'mid',
    'ppt', 'pptx', 'mmap', 'msi', 'lib', 'ilk', 'obj', 'aps', 'def', 'dep',
    'pdb', 'tlb', 'res', 'manifest', 'hlp', 'wps', 'arj', 'gz', 'z', 'adt',
    'com', 'a', 'bin', '3ds', 'drw', 'dxf', 'eps', 'psd', 'wmf', 'pcd', 'pcx',
    'psp', 'rle', 'raw', 'sct', 'tga', 'tiff', 'u3d', 'xbm',
]


# ==============================================================================
# OAuth Token Management
# ==============================================================================

def get_oauth_token() -> Optional[str]:
    """Get OAuth token from config file"""
    token_file = Path.home() / '.svn_flow' / 'gongfeng_token.json'
    if token_file.exists():
        with open(token_file) as f:
            data = json.load(f)
            return data.get('access_token')
    return None


# ==============================================================================
# Shell Utilities (mimics packages/base/src/shell.ts)
# ==============================================================================

def exec_command(cmd: str, encoding: str = 'utf-8') -> str:
    """Execute shell command and return output"""
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            env={**os.environ, 'LC_ALL': 'en_US.UTF-8'},
        )
        return result.stdout.decode(encoding)
    except Exception as e:
        print(f"[DEBUG] Command failed: {e}")
        return ""


def is_svn_path(path: str) -> bool:
    """Check if path is an SVN working directory"""
    svn_dir = Path(path) / '.svn'
    if svn_dir.exists() and svn_dir.is_dir():
        return True
    try:
        exec_command(f'svn info "{path}"')
        return True
    except:
        return False


def get_svn_base_url(path: str) -> str:
    """Get SVN repository URL for the working directory"""
    output = exec_command(f'svn info "{path}"')
    for line in output.strip().split('\n'):
        if line.startswith('URL:'):
            url = line.split(' ', 1)[1].strip()
            return urllib.parse.unquote(url)
    return ""


def get_svn_diff(path: str) -> list[str]:
    """Get SVN diff output"""
    output = exec_command(f'svn diff "{path}"')
    if not output.strip():
        return []
    return output.split('\n')


def get_filenames_from_diff(diffs: list[str]) -> list[str]:
    """Extract filenames from diff output"""
    filenames = []
    for diff in diffs:
        if diff.startswith('Index:') or diff.startswith('Property changes on:'):
            index = diff.index(':')
            name = diff[index + 1:].strip().replace('\\', '/')
            if name and name not in filenames:
                filenames.append(name)
    return filenames


def get_svn_status(path: str) -> list[str]:
    """Get SVN status output"""
    output = exec_command(f'svn status -q --ignore-externals "{path}"')
    if not output.strip():
        return []
    return [line for line in output.split('\n') if line.strip()]


# ==============================================================================
# Diff Processing (mimics packages/cr/src/util.ts)
# ==============================================================================

def is_binary_file(filename: str) -> bool:
    """Check if file is binary based on extension"""
    extension = filename.split('.')[-1].lower() if '.' in filename else ''
    return extension in BINARY_EXTENSIONS


def remove_file_base(base_path: str, file_path: str) -> str:
    """Remove base path from file path to get relative path"""
    base_path = base_path.replace('\\', '/')
    file_path = file_path.replace('\\', '/')
    if file_path.startswith(base_path):
        relative = file_path[len(base_path):]
        if relative.startswith('/'):
            relative = relative[1:]
        return relative
    return file_path.split('/')[-1]


def fix_relative_path(base_path: str, line: str) -> str:
    """Convert absolute path in diff line to relative path"""
    prefix = line[:4]  # "--- " or "+++ "
    suffix = line[4:].replace('\\', '/').replace(base_path, '')
    if suffix.startswith('/'):
        suffix = suffix[1:]
    return f"{prefix}{suffix}"


def filter_data(path: str, diff_lines: list[str], diff_files: list[str]) -> tuple[list[str], list[str]]:
    """
    Filter diff data and convert absolute paths to relative paths.
    Mimics gongfeng-cli's filterData function in util.ts
    """
    if not diff_lines or not diff_files:
        return [], []
    
    path = path.replace('\\', '/')
    new_diff_lines = []
    curr_files = []
    keep_line = False
    last_line = ''
    is_head_line_diff = False
    
    for line in diff_lines:
        if line.startswith('Index:'):
            index = line.index(':')
            name = line[index + 1:].strip().replace('\\', '/')
            filepath = name
            
            if filepath in diff_files and filepath not in curr_files:
                if is_binary_file(filepath):
                    keep_line = False
                    # Add binary file handling if needed
                else:
                    keep_line = True
                
                filename = remove_file_base(path, filepath)
                curr_files.append(filename)
                line = f"Index: {filename}"
            else:
                keep_line = False
        
        if keep_line:
            # Convert absolute paths to relative in --- and +++ lines
            if line.startswith('--- ') and last_line.strip() == '=' * 67:
                line = fix_relative_path(path, line)
                is_head_line_diff = True
            
            if line.startswith('+++ ') and is_head_line_diff:
                line = fix_relative_path(path, line)
                is_head_line_diff = False
            
            new_diff_lines.append(line)
        
        last_line = line
    
    return new_diff_lines, curr_files


# ==============================================================================
# API Service (mimics packages/cr/src/api-service.ts)
# ==============================================================================

class GongfengApiService:
    """Gongfeng API Service for SVN CR operations"""
    
    def __init__(self, oauth_token: str):
        self.oauth_token = oauth_token
    
    def _request(
        self,
        method: str,
        endpoint: str,
        data: Optional[dict] = None,
        timeout: int = 30,
    ) -> Optional[dict]:
        """Make HTTP request to Gongfeng API"""
        url = f"{API_BASE_URL}{endpoint}"
        
        headers = {
            'OAUTH-TOKEN': self.oauth_token,
        }
        
        if data:
            # Use application/x-www-form-urlencoded like qs.stringify
            encoded_data = urllib.parse.urlencode(data, doseq=True).encode('utf-8')
            headers['Content-Type'] = 'application/x-www-form-urlencoded'
        else:
            encoded_data = None
        
        req = urllib.request.Request(url, data=encoded_data, method=method, headers=headers)
        
        try:
            with urllib.request.urlopen(req, timeout=timeout) as response:
                result = json.loads(response.read().decode('utf-8'))
                return result
        except urllib.error.HTTPError as e:
            error_body = e.read().decode('utf-8')
            print(f"[ERROR] HTTP {e.code}: {error_body}")
            return None
        except Exception as e:
            print(f"[ERROR] Request failed: {e}")
            return None
    
    def get_project(self, project_id: int) -> Optional[dict]:
        """
        Get project info by ID.
        API: GET /projects/:id
        """
        endpoint = f"/projects/{project_id}"
        return self._request('GET', endpoint)
    
    def get_svn_project(self, svn_url: str) -> Optional[dict]:
        """
        Get SVN project info by URL.
        API: GET /svn/project/cli/analyze_project
        """
        endpoint = f"/svn/project/cli/analyze_project?fullPath={urllib.parse.quote(svn_url)}"
        return self._request('GET', endpoint)
    
    def get_preset_config(self, project_id: int, file_paths: list[str]) -> Optional[dict]:
        """
        Get preset reviewers by file paths.
        API: POST /svn/projects/:id/path_rules/code_review/preset_config
        """
        endpoint = f"/svn/projects/{project_id}/path_rules/code_review/preset_config"
        data = {'filePaths': file_paths}
        return self._request('POST', endpoint, data)
    
    def create_review(
        self,
        project_id: int,
        diff_content: str,
        diff_only_filename: bool,
        target_path: str,
        title: str,
        description: str = "(created by Python script)",
        reviewer_ids: str = "",
        cc_user_ids: Optional[list[int]] = None,
        author: Optional[str] = None,
    ) -> Optional[dict]:
        """
        Create SVN Code Review (code-in-local mode).
        API: POST /svn/projects/:id/merge_requests
        
        This is the core API for creating SVN CR!
        
        IMPORTANT: This API requires the project to have "code_in_local_review" enabled.
        """
        endpoint = f"/svn/projects/{project_id}/merge_requests"
        
        data = {
            'targetProjectId': str(project_id),
            'sourceProjectId': str(project_id),
            'diffContent': diff_content,
            'diffOnlyFileName': 'true' if diff_only_filename else 'false',
            'targetPath': target_path,
            'sourcePath': target_path,
            'title': title,
            'description': description,
        }
        
        if reviewer_ids:
            data['reviewerIds'] = reviewer_ids
        if cc_user_ids:
            data['ccUserIds'] = cc_user_ids
        if author:
            data['author'] = author
        
        return self._request('POST', endpoint, data, timeout=125)
    
    def get_review(self, project_id: int, review_iid: int) -> Optional[dict]:
        """
        Get review details.
        API: GET /projects/:id/reviews/:iid
        """
        endpoint = f"/projects/{project_id}/reviews/{review_iid}"
        return self._request('GET', endpoint)
    
    def patch_review_summary(
        self,
        project_id: int,
        review_iid: int,
        reviewer_event: str,
        summary: str = "",
    ) -> bool:
        """
        Update review status (approve, close, comment, etc.)
        API: PATCH /projects/:id/reviews/:iid/summary
        
        reviewer_event values:
        - 'approve': Approve the review
        - 'comment': Add a comment
        - 'deny': Deny the review
        - 'requireChange': Request changes
        - 'close': Close the review
        - 'reopen': Reopen the review
        """
        data = {'reviewerEvent': reviewer_event}
        if summary:
            data['summary'] = summary
        
        params = urllib.parse.urlencode(data)
        endpoint = f"/projects/{project_id}/reviews/{review_iid}/summary?{params}"
        
        # Use PATCH method
        url = f"{API_BASE_URL}{endpoint}"
        headers = {'OAUTH-TOKEN': self.oauth_token}
        
        req = urllib.request.Request(url, method='PATCH', headers=headers)
        
        try:
            with urllib.request.urlopen(req, timeout=30) as response:
                return response.status == 200
        except urllib.error.HTTPError as e:
            error_body = e.read().decode('utf-8')
            print(f"[ERROR] HTTP {e.code}: {error_body}")
            return False
        except Exception as e:
            print(f"[ERROR] {e}")
            return False
    
    def approve_review(self, project_id: int, review_iid: int, comment: str = "") -> bool:
        """Approve a review"""
        return self.patch_review_summary(project_id, review_iid, 'approve', comment)
    
    def close_review(self, project_id: int, review_iid: int) -> bool:
        """Close a review"""
        return self.patch_review_summary(project_id, review_iid, 'close')
    
    def comment_review(self, project_id: int, review_iid: int, comment: str) -> bool:
        """Add comment to a review"""
        return self.patch_review_summary(project_id, review_iid, 'comment', comment)


# ==============================================================================
# Diagnostic Functions
# ==============================================================================

def diagnose_project(api: GongfengApiService, project_id: int) -> dict:
    """Diagnose project settings for SVN CR compatibility"""
    print("\n" + "=" * 70)
    print("Project Diagnostic Report")
    print("=" * 70)
    
    project = api.get_project(project_id)
    if not project:
        print("[ERROR] Could not fetch project info")
        return {}
    
    print(f"\n[Project Info]")
    print(f"  ID:                  {project.get('id')}")
    print(f"  Name:                {project.get('name')}")
    print(f"  Path:                {project.get('path_with_namespace')}")
    print(f"  Type:                {project.get('type')}")
    print(f"  Visibility:          {project.get('visibility_level')}")
    
    print(f"\n[CR Settings]")
    print(f"  review_enabled:            {project.get('review_enabled')}")
    print(f"  merge_requests_enabled:    {project.get('merge_requests_enabled')}")
    print(f"  code_in_local_review:      {project.get('code_in_local_review')}")
    
    # Check compatibility
    print(f"\n[Compatibility Check]")
    
    is_svn = project.get('type') == 'SVN'
    print(f"  Is SVN project:      {'✓ Yes' if is_svn else '✗ No'}")
    
    review_enabled = project.get('review_enabled', False)
    print(f"  Review enabled:      {'✓ Yes' if review_enabled else '✗ No'}")
    
    code_in_local = project.get('code_in_local_review', False)
    print(f"  Code-in-local mode:  {'✓ Enabled' if code_in_local else '✗ NOT Enabled'}")
    
    if not code_in_local:
        print(f"\n[ACTION REQUIRED]")
        print(f"  The 'code_in_local_review' feature is NOT enabled for this project.")
        print(f"  To enable it, go to the Gongfeng Web Interface:")
        print(f"    1. Open: https://{GONGFENG_HOST}/{project.get('path_with_namespace')}/settings")
        print(f"    2. Navigate to: Settings -> Code Review (代码评审设置)")
        print(f"    3. Enable: '代码在本地'评审模式")
        print(f"    4. Save the settings")
        print(f"    5. Re-run this script")
    
    can_create_cr = is_svn and review_enabled and code_in_local
    print(f"\n[Result]")
    print(f"  Can create SVN CR:   {'✓ Yes' if can_create_cr else '✗ No'}")
    
    return {
        'project': project,
        'is_svn': is_svn,
        'review_enabled': review_enabled,
        'code_in_local': code_in_local,
        'can_create_cr': can_create_cr,
    }


# ==============================================================================
# Main Test Flow
# ==============================================================================

def main():
    work_dir = '/Users/firoyang/workspace/b1'
    project_id = 1618099  # firoyang/test
    
    print("=" * 70)
    print("SVN Code Review API Test")
    print("Based on gongfeng-cli implementation")
    print("=" * 70)
    
    # Step 1: Get OAuth token
    print("\n[Step 1] Getting OAuth token...")
    oauth_token = get_oauth_token()
    if not oauth_token:
        print("[ERROR] No OAuth token found in ~/.svn_flow/gongfeng_token.json")
        return
    print(f"[OK] OAuth token loaded (length: {len(oauth_token)})")
    
    # Initialize API service
    api = GongfengApiService(oauth_token)
    
    # Step 2: Run diagnostic
    print("\n[Step 2] Running project diagnostic...")
    diagnosis = diagnose_project(api, project_id)
    
    if not diagnosis.get('can_create_cr'):
        print("\n[ABORTED] Cannot proceed with CR creation due to missing requirements.")
        print("\nPlease enable 'code_in_local_review' in the project settings and try again.")
        return
    
    project = diagnosis['project']
    project_path = project.get('path_with_namespace')
    
    # Step 3: Check SVN path
    print("\n[Step 3] Checking SVN path...")
    if not is_svn_path(work_dir):
        print(f"[ERROR] {work_dir} is not an SVN working directory")
        return
    print(f"[OK] {work_dir} is a valid SVN working directory")
    
    # Step 4: Get SVN base URL
    print("\n[Step 4] Getting SVN base URL...")
    svn_base = get_svn_base_url(work_dir)
    if not svn_base:
        print("[ERROR] Could not get SVN base URL")
        return
    print(f"[OK] SVN URL: {svn_base}")
    
    # Step 5: Get SVN diff
    print("\n[Step 5] Getting SVN diff...")
    diff_lines = get_svn_diff(work_dir)
    if not diff_lines:
        print("[WARN] No changes found in working directory")
        print("[INFO] Creating a test file for demo...")
        
        # Create a test change
        test_file = Path(work_dir) / 'test_cr_demo.txt'
        test_file.write_text(f"Test change for CR demo at {__import__('datetime').datetime.now()}\n")
        print(f"[OK] Created test file: {test_file}")
        
        # Get diff again
        diff_lines = get_svn_diff(work_dir)
        if not diff_lines:
            print("[ERROR] Still no diff after creating test file")
            return
    
    print(f"[OK] Got {len(diff_lines)} lines of diff")
    
    # Step 6: Extract filenames and filter diff
    print("\n[Step 6] Processing diff content...")
    diff_files = get_filenames_from_diff(diff_lines)
    print(f"[DEBUG] Raw files from diff: {diff_files}")
    
    filtered_lines, current_files = filter_data(work_dir, diff_lines, diff_files)
    
    if not filtered_lines:
        print("[WARN] No valid diff content after filtering")
        return
    
    print(f"[OK] Filtered diff: {len(filtered_lines)} lines")
    print(f"[OK] Changed files: {current_files}")
    
    # Join with \r\n like gongfeng-cli does
    diff_content = '\r\n'.join(filtered_lines)
    
    if len(diff_content) > MAX_UPLOAD_SIZE:
        print(f"[ERROR] Diff too large: {len(diff_content)} bytes (max: {MAX_UPLOAD_SIZE})")
        return
    
    print(f"[OK] Diff content size: {len(diff_content)} bytes")
    print(f"\n[DEBUG] Diff preview (first 500 chars):\n{diff_content[:500]}...")
    
    # Step 7: Get preset reviewers (optional)
    print("\n[Step 7] Getting preset reviewers...")
    urls = [f"{svn_base}/{f}" for f in current_files if f]
    preset_config = api.get_preset_config(project_id, urls)
    
    default_reviewers = []
    if preset_config:
        if preset_config.get('reviewers'):
            default_reviewers.extend(preset_config['reviewers'])
        print(f"[OK] Preset reviewers: {[r.get('username') for r in default_reviewers]}")
    else:
        print("[WARN] Could not get preset reviewers")
    
    # Step 8: Create CR
    print("\n[Step 8] Creating Code Review...")
    title = "[Test] SVN CR via Python Script"
    description = f"Test CR created via Python script.\n\nChanged files:\n" + "\n".join([f"- {f}" for f in current_files if f])
    
    # Use default reviewers if available
    reviewer_ids = ",".join([str(r.get('id')) for r in default_reviewers]) if default_reviewers else ""
    
    print(f"    Title: {title}")
    print(f"    Target Path: {svn_base}")
    print(f"    Reviewer IDs: {reviewer_ids or '(none)'}")
    
    result = api.create_review(
        project_id=project_id,
        diff_content=diff_content,
        diff_only_filename=False,
        target_path=svn_base,
        title=title,
        description=description,
        reviewer_ids=reviewer_ids,
    )
    
    if not result:
        print("\n[ERROR] Failed to create Code Review")
        return
    
    print("\n[OK] Code Review created successfully!")
    review_id = result.get('id')
    review_iid = result.get('iid')
    review_state = result.get('state')
    
    print(f"    Review ID: {review_id}")
    print(f"    Review IID: {review_iid}")
    print(f"    State: {review_state}")
    
    web_url = f"https://{GONGFENG_HOST}/{project_path}/reviews/{review_iid}"
    print(f"    Web URL: {web_url}")
    
    # Step 9: Get review details
    print("\n[Step 9] Fetching review details...")
    review_details = api.get_review(project_id, review_iid)
    if review_details:
        print(f"[OK] Review details fetched")
        print(f"    Title: {review_details.get('title')}")
        print(f"    State: {review_details.get('state')}")
        author = review_details.get('author', {})
        print(f"    Author: {author.get('username') if author else 'N/A'}")
    
    # Step 10: Test approve/close operations
    print("\n[Step 10] Testing review operations...")
    
    # Add a comment
    print("    Adding comment...")
    if api.comment_review(project_id, review_iid, "Test comment from Python script"):
        print("    [OK] Comment added")
    else:
        print("    [WARN] Failed to add comment")
    
    # Approve the review
    print("    Approving review...")
    if api.approve_review(project_id, review_iid, "LGTM - Auto approved by test script"):
        print("    [OK] Review approved")
    else:
        print("    [WARN] Failed to approve review")
    
    # Close the review
    print("    Closing review...")
    if api.close_review(project_id, review_iid):
        print("    [OK] Review closed")
    else:
        print("    [WARN] Failed to close review")
    
    # Summary
    print("\n" + "=" * 70)
    print("Test Complete!")
    print("=" * 70)
    print(f"\nCreated CR: {web_url}")
    print("\nAPI Endpoints Used:")
    print("  - GET  /projects/:id")
    print("  - GET  /svn/project/cli/analyze_project")
    print("  - POST /svn/projects/:id/path_rules/code_review/preset_config")
    print("  - POST /svn/projects/:id/merge_requests")
    print("  - GET  /projects/:id/reviews/:iid")
    print("  - PATCH /projects/:id/reviews/:iid/summary")


if __name__ == '__main__':
    main()
