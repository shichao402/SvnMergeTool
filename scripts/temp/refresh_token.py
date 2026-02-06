#!/usr/bin/env python3
import json
import urllib.parse
import urllib.request
from pathlib import Path
import time

OAUTH_CLIENT_ID = 'a8e6b05ee35f4aed956ed66df3c493fe'
OAUTH_CLIENT_SECRET = '16e99d24ce504dcb814e59c13a191ef8'
OAUTH_BASE_URL = 'https://git.woa.com'

token_file = Path.home() / '.svn_flow' / 'gongfeng_token.json'
with open(token_file) as f:
    data = json.load(f)

refresh_token = data.get('refresh_token')
print(f"Refresh token: {refresh_token[:20] if refresh_token else 'None'}...")

# 刷新 token
req_data = urllib.parse.urlencode({
    'client_id': OAUTH_CLIENT_ID,
    'client_secret': OAUTH_CLIENT_SECRET,
    'refresh_token': refresh_token,
    'grant_type': 'refresh_token',
}).encode()

req = urllib.request.Request(
    f'{OAUTH_BASE_URL}/oauth/token',
    data=req_data,
    method='POST',
    headers={'Content-Type': 'application/x-www-form-urlencoded'}
)

try:
    with urllib.request.urlopen(req, timeout=30) as resp:
        result = json.loads(resp.read().decode())
    
    # 保存新 token
    expires_in = result.get('expires_in', 7200)
    created_at = result.get('created_at', int(time.time()))
    
    save_data = {
        'access_token': result['access_token'],
        'refresh_token': result.get('refresh_token'),
        'expires_at': (created_at + expires_in) * 1000,
        'refresh_expires_at': (created_at + 30 * 24 * 3600) * 1000,
    }
    
    with open(token_file, 'w') as f:
        json.dump(save_data, f, indent=2)
    
    print(f"Token refreshed! New token: {result['access_token'][:20]}...")
except Exception as e:
    print(f"Error: {e}")
