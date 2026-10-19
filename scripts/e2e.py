"""OIDC credentials stay in this process; the one-off key reaches UI input over stdin."""
import json
import os
import subprocess
import urllib.error
import urllib.parse
import urllib.request


def request(url, data=None, token=None, form=False, method=None):
    headers = {}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    if data is not None:
        headers['Content-Type'] = 'application/x-www-form-urlencoded' if form else 'application/json'
        data = (urllib.parse.urlencode(data) if form else json.dumps(data)).encode()
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            body = response.read()
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as error:
        # Never print response bodies that could contain credentials.
        raise RuntimeError(f'{urllib.parse.urlsplit(url).path}: HTTP {error.code}') from None


def mask(value):
    print('::add-mask::' + value.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A'), flush=True)


def main():
    access = key_id = ''
    ts = os.path.join(os.environ['ProgramFiles'], 'Tailscale', 'tailscale.exe')
    try:
        audience = os.environ['TS_WIF_AUDIENCE']
        identity = request(os.environ['ACTIONS_ID_TOKEN_REQUEST_URL'] + '&audience=' + urllib.parse.quote(audience, safe=''), token=os.environ['ACTIONS_ID_TOKEN_REQUEST_TOKEN'])['value']
        mask(identity)
        access = request('https://api.tailscale.com/api/v2/oauth/token-exchange', {'client_id': os.environ['TS_WIF_CLIENT_ID'], 'jwt': identity}, form=True)['access_token']
        mask(access)
        identity = ''
        auth = request('https://api.tailscale.com/api/v2/tailnet/-/keys', {'capabilities': {'devices': {'create': {'reusable': False, 'ephemeral': True, 'preauthorized': True, 'tags': ['tag:gha-smoke-test-node']}}}, 'expirySeconds': 86400, 'description': 'onboarding-' + os.environ['GITHUB_RUN_ID']}, token=access)
        key_id = auth['id']
        mask(auth['key'])
        result = subprocess.run(['pwsh', '-NoProfile', '-File', 'scripts/drive-ui.ps1', '-E2E'], input=auth.pop('key') + '\n', text=True, timeout=2100)
        if result.returncode:
            raise RuntimeError('Packaged native UI E2E failed')
        state = json.loads(subprocess.check_output([ts, 'status', '--json'], text=True))
        assert state['BackendState'] == 'Running'
        assert 'tag:gha-smoke-test-node' in state['Self']['Tags']
        subprocess.run(['pwsh', '-NoProfile', '-File', 'scripts/check-ssh.ps1'], check=True, timeout=120)
        print('Packaged Rust GPUI → WIF one-off key → Tailscale + SSH: PASS')
    finally:
        errors = []
        if os.path.isfile(ts):
            try:
                result = subprocess.run([ts, 'logout'], timeout=30, capture_output=True)
                if result.returncode:
                    errors.append('Tailscale logout failed; check ephemeral node cleanup')
            except subprocess.TimeoutExpired:
                errors.append('Tailscale logout timed out; check ephemeral node cleanup')
        if access and key_id:
            try:
                request('https://api.tailscale.com/api/v2/tailnet/-/keys/' + urllib.parse.quote(key_id, safe=''), token=access, method='DELETE')
            except RuntimeError as error:
                if 'HTTP 404' not in str(error):
                    errors.append('Unused key revocation failed')
        if errors:
            raise RuntimeError('; '.join(errors))


if __name__ == '__main__':
    main()
