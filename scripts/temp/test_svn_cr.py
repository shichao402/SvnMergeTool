#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Test script for SVN Code Review API

Based on gongfeng-cli implementation:
- packages/cr/src/commands/cr/create.ts
- packages/cr/src/api-service.ts

Key API endpoint: POST /svn/projects/:id/merge_requests
"""

import json
import os
import subprocess
import urllib.parse
from pathlib import Path


def get_oauth_token():
    """Get OAuth token from config file"""
    token_file = Path.home() / '.svn_flow' / 'gongfeng_token.json'
    if token_file.exists():
        with open(token_file) as f:
            data = json.load(f)
            return data.get('access_token')
    return None


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
        print(f"Command failed: {e}")
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


def filter_diff_data(path: str, diff_lines: list[str]) -> tuple[list[str], list[str]]:
    """
    Filter diff data and convert absolute paths to relative paths.
    
    Based on gongfeng-cli's filterData function in util.ts
    """
    if not diff_lines:
        return [], []
    
    new_diff_lines = []
    current_files = []
    keep_line = False
    last_line = ""
    is_head_line_diff = False
    
    # Normalize path
    path = path.replace('\\', '/')
    if not path.endswith('/'):
        path_prefix = path + '/'
    else:
        path_prefix = path
    
    for line in diff_lines:
        if line.startswith('Index:'):
            # Extract file path from "Index: /path/to/file"
            index_pos = line.index(':')
            file_path = line[index_pos + 1:].strip().replace('\\', '/')
            
            # Get relative path
            if file_path.startswith(path_prefix):
                relative_path = file_path[len(path_prefix):]
            elif file_path.startswith(path):
                relative_path = file_path[len(path):].lstrip('/')
            else:
                relative_path = file_path
            
            if relative_path and relative_path not in current_files:
                current_files.append(relative_path)
                keep_line = True
                line = f"Index: {relative_path}"
        
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
    
    return new_diff_lines, current_files


def fix_relative_path(base_path: str, line: str) -> str:
    """Convert absolute path in diff line to relative path"""
    prefix = line[:4]  # "--- " or "+++ "
    suffix = line[4:]
    
    # Handle revision info like "(revision 6)" or "(working copy)"
    if '\t' in suffix:
        file_part, rev_part = suffix.split('\t', 1)
    else:
        parts = suffix.split('  ')
        if len(parts) >= 2:
            file_part = parts[0]
            rev_part = parts[1]
        else:
            file_part = suffix
            rev_part = ""
    
    file_part = file_part.replace('\\', '/').replace(base_path, '').lstrip('/')
    
    if rev_part:
        return f"{prefix}{file_part}\t{rev_part}"
    return f"{prefix}{file_part}"


def create_svn_cr(
    project_id: int,
    diff_content: str,
    target_path: str,
    title: str,
    description: str = "",
    reviewer_ids: str = "",
    diff_only_filename: bool = False,
):
    """
    Create SVN Code Review using the API.
    
    API: POST /svn/projects/:id/merge_requests
    
    Based on gongfeng-cli's createReview in api-service.ts
    """
    import urllib.request
    
    oauth_token = get_oauth_token()
    if not oauth_token:
        print("[ERROR] No OAuth token found")
        return None
    
    url = f"https://git.woa.com/api/v3/svn/projects/{project_id}/merge_requests"
    
    # Build form data (application/x-www-form-urlencoded)
    # Use qs.stringify format like the original implementation
    form_data = {
        'targetProjectId': str(project_id),
        'sourceProjectId': str(project_id),
        'diffContent': diff_content,
        'diffOnlyFileName': str(diff_only_filename).lower(),
        'targetPath': target_path,
        'sourcePath': target_path,
        'title': title,
        'description': description or '(created by GF CLI)',
    }
    
    if reviewer_ids:
        form_data['reviewerIds'] = reviewer_ids
    
    encoded_data = urllib.parse.urlencode(form_data).encode('utf-8')
    
    print(f"\n[DEBUG] API URL: {url}")
    print(f"[DEBUG] Target Path: {target_path}")
    print(f"[DEBUG] Diff Content Length: {len(diff_content)} bytes")
    
    req = urllib.request.Request(url, data=encoded_data, method='POST')
    req.add_header('OAUTH-TOKEN', oauth_token)
    req.add_header('Content-Type', 'application/x-www-form-urlencoded')
    
    try:
        with urllib.request.urlopen(req, timeout=125) as response:
            result = json.loads(response.read().decode('utf-8'))
            return result
    except urllib.error.HTTPError as e:
        error_body = e.read().decode('utf-8')
        print(f"[ERROR] HTTP {e.code}: {error_body}")
        return None
    except Exception as e:
        print(f"[ERROR] {e}")
        return None


def get_svn_project(svn_url: str):
    """
    Get SVN project info from gongfeng.
    
    API: GET /svn/project/cli/analyze_project
    """
    import urllib.request
    
    oauth_token = get_oauth_token()
    if not oauth_token:
        return None
    
    url = f"https://git.woa.com/api/v3/svn/project/cli/analyze_project?fullPath={urllib.parse.quote(svn_url)}"
    
    req = urllib.request.Request(url)
    req.add_header('OAUTH-TOKEN', oauth_token)
    
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            result = json.loads(response.read().decode('utf-8'))
            return result
    except urllib.error.HTTPError as e:
        error_body = e.read().decode('utf-8')
        print(f"[DEBUG] analyze_project failed: HTTP {e.code}: {error_body}")
        return None
    except Exception as e:
        print(f"[DEBUG] analyze_project failed: {e}")
        return None


def main():
    work_dir = '/Users/firoyang/workspace/b1'
    
    print("=" * 60)
    print("SVN Code Review API Test")
    print("Based on gongfeng-cli implementation")
    print("=" * 60)
    
    # Step 1: Check if SVN path
    print("\n[Step 1] Checking SVN path...")
    if not is_svn_path(work_dir):
        print(f"[ERROR] {work_dir} is not an SVN working directory")
        return
    print(f"[OK] {work_dir} is an SVN working directory")
    
    # Step 2: Get SVN base URL
    print("\n[Step 2] Getting SVN base URL...")
    svn_base = get_svn_base_url(work_dir)
    if not svn_base:
        print("[ERROR] Could not get SVN base URL")
        return
    print(f"[OK] SVN URL: {svn_base}")
    
    # Step 3: Try to get project info via analyze_project API
    print("\n[Step 3] Fetching project info...")
    project = get_svn_project(svn_base)
    
    if project:
        print(f"[OK] Project found via analyze_project")
        print(f"    Project ID: {project.get('id')}")
        print(f"    Project Path: {project.get('fullPath')}")
        project_id = project.get('id')
    else:
        # Fallback: use the known project ID
        print("[INFO] analyze_project API not available, using known project ID")
        project_id = 1618099  # firoyang/test
        print(f"[OK] Using Project ID: {project_id}")
    
    # Step 4: Get SVN diff
    print("\n[Step 4] Getting SVN diff...")
    diff_lines = get_svn_diff(work_dir)
    if not diff_lines:
        print("[WARN] No changes found in working directory")
        return
    print(f"[OK] Got {len(diff_lines)} lines of diff")
    
    # Step 5: Filter and convert diff
    print("\n[Step 5] Processing diff content...")
    filtered_lines, current_files = filter_diff_data(work_dir, diff_lines)
    
    if not filtered_lines:
        print("[WARN] No valid diff content after filtering")
        return
    
    print(f"[OK] Filtered diff: {len(filtered_lines)} lines")
    print(f"[OK] Changed files: {current_files}")
    
    diff_content = '\r\n'.join(filtered_lines)
    print(f"\n[DEBUG] Diff content preview:\n{diff_content[:500]}...")
    
    # Step 6: Create CR
    print("\n[Step 6] Creating Code Review...")
    title = f"[Test] SVN CR API Test"
    description = f"Test CR created via Python script.\n\nChanged files:\n" + "\n".join([f"- {f}" for f in current_files])
    
    print(f"    Title: {title}")
    print(f"    Target Path: {svn_base}")
    
    result = create_svn_cr(
        project_id=project_id,
        diff_content=diff_content,
        target_path=svn_base,
        title=title,
        description=description,
    )
    
    if result:
        print("\n[OK] Code Review created successfully!")
        print(f"    Review ID: {result.get('id')}")
        print(f"    Review IID: {result.get('iid')}")
        print(f"    State: {result.get('state')}")
        web_url = f"https://git.woa.com/firoyang/test/reviews/{result.get('iid')}"
        print(f"    Web URL: {web_url}")
    else:
        print("\n[ERROR] Failed to create Code Review")
    
    print("\n" + "=" * 60)
    print("Test Complete")
    print("=" * 60)


if __name__ == '__main__':
    main()
