"""Drive only the disposable fixture's real Chrome login form through DevTools."""
import json
import urllib.parse
import urllib.request

FIXTURE_ORIGIN = ("http", "localhost", 8180)
REALM_PATH = "/realms/kunde-consumer-check/"


def fixture_page(url):
    parsed = urllib.parse.urlparse(url)
    return ((parsed.scheme, parsed.hostname, parsed.port) == FIXTURE_ORIGIN
            and parsed.path.startswith(REALM_PATH) and not parsed.username and not parsed.password)


def connect():
    import websocket  # Installed with a pinned wheel hash in the native-only venv.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open("http://127.0.0.1:19222/json/list", timeout=3) as response:
        targets = json.load(response)
    pages = [p for p in targets if p.get("type") == "page" and fixture_page(p.get("url", ""))]
    if len(pages) != 1:
        raise ValueError("Expected one fixture browser page")
    address = pages[0]["webSocketDebuggerUrl"]
    parsed = urllib.parse.urlparse(address)
    if parsed.scheme != "ws" or parsed.hostname not in {"localhost", "127.0.0.1"} or parsed.port != 19222:
        raise ValueError("Expected loopback Chrome debugger")
    return websocket.create_connection(address, timeout=5, suppress_origin=True, http_no_proxy=["localhost", "127.0.0.1"])


def evaluate(connection, expression):
    connection.send(json.dumps({"id": 1, "method": "Runtime.evaluate", "params": {
        "expression": expression, "returnByValue": True}}))
    for _ in range(30):
        response = json.loads(connection.recv())
        if response.get("id") == 1:
            if "error" in response or "exceptionDetails" in response.get("result", {}):
                raise RuntimeError("Browser evaluation failed")
            return response["result"]["result"].get("value")
    raise RuntimeError("Browser response not received")


FORM = "!!(document.querySelector('#username') && document.querySelector('#password[type=password]') && document.querySelector('#kc-login'))"


def form_present():
    connection = connect()
    try:
        return evaluate(connection, FORM) is True
    finally:
        connection.close()


def submit(username, password):
    connection = connect()
    try:
        # Recheck origin inside the renderer before injecting the synthetic account.
        values = json.dumps({"username": username, "password": password})
        script = """(() => {
          if (location.origin !== 'http://localhost:8180' ||
              !location.pathname.startsWith('/realms/kunde-consumer-check/')) return false;
          const values = VALUES;
          for (const id of ['username', 'password']) {
            const field = document.getElementById(id);
            if (!field || (id === 'password' && field.type !== 'password')) return false;
            field.value = values[id];
            field.dispatchEvent(new Event('input', {bubbles: true}));
            field.dispatchEvent(new Event('change', {bubbles: true}));
          }
          return !!document.getElementById('kc-login');
        })()""".replace("VALUES", values)
        if evaluate(connection, script) is not True:
            raise RuntimeError("Fixture credential form unavailable")
        # Navigation may destroy the debugger before its response. The native callback
        # and verified API profile are the success criterion, not a debugger reply.
        connection.send(json.dumps({"id": 2, "method": "Runtime.evaluate", "params": {
            "expression": "document.getElementById('kc-login').click()", "userGesture": True}}))
    finally:
        connection.close()


def page_state():
    connection = connect()
    try:
        return evaluate(connection, """(() => {
          const text = (document.body?.innerText || '').toLowerCase();
          return {ready: ['loading','interactive','complete'].includes(document.readyState) ? document.readyState : 'unknown',
            inputCount: Math.min(document.querySelectorAll('input').length, 1000),
            errorLabels: ['invalid parameter','cookie not found','we are sorry','enable javascript','page has expired']
              .filter(label => text.includes(label))};
        })()""")
    finally:
        connection.close()


def registration_state():
    connection = connect()
    try:
        return evaluate(connection, """(() => ({
          form: !!document.querySelector('#kc-register-form'),
          invalid: !!document.querySelector('[aria-invalid="true"], .kc-feedback-text, #input-error')
        }))()""")
    finally:
        connection.close()


def register(username, password, confirmation):
    connection = connect()
    try:
        values = json.dumps({'username': username, 'email': username + '@example.invalid',
                             'firstName': 'Synthetic', 'lastName': 'Consumer',
                             'password': password, 'password-confirm': confirmation})
        script = """(() => {
          if (location.origin !== 'http://localhost:8180' ||
              !location.pathname.startsWith('/realms/kunde-consumer-check/')) return false;
          const form = document.getElementById('kc-register-form');
          if (!form || new URL(form.action).origin !== location.origin) return false;
          const values = VALUES;
          for (const id of Object.keys(values)) {
            const field = document.getElementById(id);
            if (!field || (id.startsWith('password') && field.type !== 'password')) return false;
          }
          for (const [id, value] of Object.entries(values)) {
            const field = document.getElementById(id);
            field.value = value;
            field.dispatchEvent(new Event('input', {bubbles: true}));
            field.dispatchEvent(new Event('change', {bubbles: true}));
          }
          return !!form.querySelector('[type=submit]');
        })()""".replace('VALUES', values)
        if evaluate(connection, script) is not True:
            raise RuntimeError('Fixture registration form unavailable')
        connection.send(json.dumps({'id': 2, 'method': 'Runtime.evaluate', 'params': {
            'expression': "document.querySelector('#kc-register-form [type=submit]').click()",
            'userGesture': True}}))
    finally:
        connection.close()
