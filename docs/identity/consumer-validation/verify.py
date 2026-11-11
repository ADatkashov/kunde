import urllib.request as u, urllib.parse as p, urllib.error as e, http.cookiejar, html.parser, secrets, hashlib, base64, json

ISSUER = "http://localhost:8180/realms/kunde-consumer-check"


class NoRedirect(u.HTTPRedirectHandler):
    def redirect_request(self, *args):
        return None


class LoopbackCookiePolicy(http.cookiejar.DefaultCookiePolicy):
    def return_ok_secure(self, cookie, request):
        return p.urlparse(request.full_url).hostname in (
            "localhost",
            "127.0.0.1",
        ) or super().return_ok_secure(cookie, request)


browser = u.build_opener(
    u.ProxyHandler({}),
    u.HTTPCookieProcessor(http.cookiejar.CookieJar(policy=LoopbackCookiePolicy())),
    NoRedirect(),
)


def request(url, data=None, headers=None):
    try:
        return browser.open(
            u.Request(url, data=data, headers=headers or {}), timeout=20
        )
    except e.HTTPError as error:
        return error


def follow(response):
    for _ in range(12):
        if response.code not in [301, 302, 303, 307]:
            return response
        url = response.headers["Location"]
        if url.startswith("http://127.0.0.1:8765/callback"):
            return response
        response = request(url)
    raise AssertionError("Too many redirects")


class Form(html.parser.HTMLParser):
    def __init__(self, text):
        super().__init__()
        self.action = None
        self.inputs = {}
        self.feed(text)

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "form":
            self.action = a.get("action", self.action)
        if tag == "input" and a.get("name"):
            self.inputs[a["name"]] = a.get("value", "")


verifier = secrets.token_urlsafe(48)
state = secrets.token_urlsafe(24)
challenge = (
    base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest())
    .decode()
    .rstrip("=")
)
params = {
    "client_id": "kunde-consumer",
    "redirect_uri": "http://127.0.0.1:8765/callback",
    "response_type": "code",
    "scope": "openid profile kunde.consumer",
    "state": state,
    "nonce": secrets.token_urlsafe(24),
    "code_challenge": challenge,
    "code_challenge_method": "S256",
}
response = follow(
    request(ISSUER + "/protocol/openid-connect/registrations?" + p.urlencode(params))
)
form = Form(response.read().decode())
assert form.action, "Registration form missing"
name = "synthetic-" + secrets.token_hex(5)
password = secrets.token_urlsafe(24)
form.inputs.update(
    {
        "username": name,
        "email": name + "@example.invalid",
        "firstName": "Synthetic",
        "lastName": "Test",
        "password": password,
        "password-confirm": password,
    }
)
response = follow(request(form.action, p.urlencode(form.inputs).encode()))
assert response.code == 302 and response.headers.get("Location", "").startswith(
    params["redirect_uri"]
), "Registration did not return authorization callback"
callback = p.parse_qs(p.urlparse(response.headers["Location"]).query)
assert callback["state"] == [state]
code = callback["code"][0]


def token(data):
    response = request(
        ISSUER + "/protocol/openid-connect/token",
        p.urlencode({"client_id": "kunde-consumer", **data}).encode(),
    )
    return response.code, json.load(response)


status, tokens = token(
    {
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": params["redirect_uri"],
        "code_verifier": verifier,
    }
)
assert status == 200
access = tokens["access_token"]
refresh = tokens["refresh_token"]
claims = json.loads(base64.urlsafe_b64decode(access.split(".")[1] + "=="))
assert (
    claims["typ"] == "Bearer"
    and claims["azp"] == "kunde-consumer"
    and "kunde.consumer" in claims["scope"].split()
)


def profile(access, body=None):
    headers = {"Authorization": "Bearer " + access}
    if body is not None:
        headers["Content-Type"] = "application/json"
    req = u.Request(
        "http://localhost:8081/api/v1/me",
        headers=headers,
        data=json.dumps(body).encode() if body else None,
        method="PATCH" if body else "GET",
    )
    try:
        r = browser.open(req, timeout=20)
    except e.HTTPError as error:
        r = error
    return r.code, json.load(r)


status, me = profile(access)
assert status == 200
status, updated = profile(
    access,
    {"displayName": "Synthetic", "preferredLanguage": "kk", "version": me["version"]},
)
assert status == 200
assert (
    profile(
        access,
        {"displayName": "Stale", "preferredLanguage": "en", "version": me["version"]},
    )[0]
    == 409
)
status, rotated = token({"grant_type": "refresh_token", "refresh_token": refresh})
assert status == 200
assert profile(rotated["access_token"])[0] == 200
logout = request(
    ISSUER + "/protocol/openid-connect/logout",
    p.urlencode(
        {"client_id": "kunde-consumer", "refresh_token": rotated["refresh_token"]}
    ).encode(),
)
assert logout.code == 204
assert (
    token({"grant_type": "refresh_token", "refresh_token": rotated["refresh_token"]})[0]
    == 400
)
# A fresh browser login must show credentials after logout.
response = follow(
    request(ISSUER + "/protocol/openid-connect/auth?" + p.urlencode(params))
)
form = Form(response.read().decode())
assert form.action, "Login form missing after logout"
form.inputs.update({"username": name, "password": password})
response = follow(request(form.action, p.urlencode(form.inputs).encode()))
assert response.code == 302 and response.headers["Location"].startswith(
    params["redirect_uri"]
)
callback = p.parse_qs(p.urlparse(response.headers["Location"]).query)
assert callback["state"] == [state]
status, second = token(
    {
        "grant_type": "authorization_code",
        "code": callback["code"][0],
        "redirect_uri": params["redirect_uri"],
        "code_verifier": verifier,
    }
)
assert status == 200
status, secondRotated = token(
    {"grant_type": "refresh_token", "refresh_token": second["refresh_token"]}
)
assert status == 200
assert (
    token({"grant_type": "refresh_token", "refresh_token": second["refresh_token"]})[0]
    == 400
)
print(
    json.dumps(
        {
            "status": "PASS",
            "provider": "Keycloak 26.8.2",
            "registration": "authorization code + S256 PKCE",
            "apiProfile": 200,
            "profileUpdate": 200,
            "staleVersion": 409,
            "rotatedRefresh": 200,
            "refreshReplay": 400,
            "postLogoutRefresh": 400,
            "nativeCallback": "NOT_EXECUTED",
            "personalData": "synthetic only",
        }
    )
)
