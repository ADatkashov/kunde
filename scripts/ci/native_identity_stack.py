"""Disposable loopback-only Consumer fixture; never upload its private state/logs."""
import argparse
import json
import os
from pathlib import Path
import re
import secrets
import signal
import subprocess
import tempfile
import time
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[2]
ISSUER = "http://localhost:8180/realms/kunde-consumer-check"


def command(args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, text=True, **kwargs).stdout.strip()


def docker(*args):
    env = dict(os.environ)
    for key in ("DOCKER_HOST", "DOCKER_CONTEXT", "DOCKER_TLS", "DOCKER_TLS_VERIFY", "DOCKER_CERT_PATH"):
        env.pop(key, None)
    return command(["docker", "--host=unix:///var/run/docker.sock", *args], env=env)


def write_private(path, data):
    path.write_text(json.dumps(data, indent=2) + "\n")
    path.chmod(0o600)


def realm_fixture(username, password, subject):
    realm = json.loads((ROOT / "docs/identity/consumer-validation/realm.json").read_text())
    realm["users"] = [{"id": subject, "username": username, "enabled": True,
                       "email": username + "@example.invalid", "emailVerified": True,
                       "firstName": "Native", "lastName": "Consumer", "requiredActions": [],
                       "credentials": [{"type": "password", "value": password, "temporary": False}]}]
    return realm


def wait_http(url, seconds=180):
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            with opener.open(url, timeout=3) as response:
                if response.status == 200:
                    return json.load(response)
        except (OSError, ValueError):
            pass
        time.sleep(1)
    raise RuntimeError("Loopback fixture readiness timeout")


def stop(state_dir):
    state_dir = Path(state_dir)
    if not state_dir.name.startswith("kunde-native-"):
        raise ValueError("Not an owned native fixture directory")
    if not (state_dir / "fixture.json").is_file():
        return
    state = json.loads((state_dir / "fixture.json").read_text())
    marker = state["marker"]
    if not re.fullmatch(r"kunde-native-[a-f0-9]{12}", marker):
        raise ValueError("Invalid fixture marker")
    pid = state.get("backendPid")
    if pid:
        proc = Path(f"/proc/{pid}/cmdline")
        if proc.exists() and ("--kunde.fixture.id=" + marker).encode() in proc.read_bytes():
            os.kill(pid, signal.SIGTERM)
    for suffix in ("-idp", "-db"):
        try:
            docker("rm", "--force", "--volumes", marker + suffix)
        except subprocess.CalledProcessError:
            pass
    # Keep only job-local diagnostics; secrets are not needed after cleanup.
    (state_dir / "realm.json").unlink(missing_ok=True)
    (state_dir / "fixture.json").unlink(missing_ok=True)


def start():
    os.umask(0o077)
    state_dir = Path(tempfile.mkdtemp(prefix="kunde-native-", dir=os.environ.get("RUNNER_TEMP")))
    marker = "kunde-native-" + secrets.token_hex(6)
    state = {"marker": marker, "username": "native-" + secrets.token_hex(6),
             "password": "NativeA9" + secrets.token_hex(16), "subject": str(uuid.uuid4()),
             "dbPassword": secrets.token_hex(24), "issuer": ISSUER}
    write_private(state_dir / "fixture.json", state)
    write_private(state_dir / "realm.json", realm_fixture(state["username"], state["password"], state["subject"]))
    if os.environ.get("GITHUB_ENV"):
        for value in (state["password"], state["dbPassword"]):
            print("::add-mask::" + value, flush=True)
        with open(os.environ["GITHUB_ENV"], "a") as output:
            output.write("KUNDE_NATIVE_DIR=" + str(state_dir) + "\n")
    phase = "database"
    try:
        docker("run", "--detach", "--rm", "--name", marker + "-db",
               "--publish", "127.0.0.1:15432:5432", "--env", "POSTGRES_DB=kunde",
               "--env", "POSTGRES_USER=kunde_ci", "--env", "POSTGRES_PASSWORD=" + state["dbPassword"], "postgres:16")
        deadline = time.monotonic() + 60
        while True:
            try:
                docker("exec", marker + "-db", "pg_isready", "-U", "kunde_ci", "-d", "kunde")
                break
            except subprocess.CalledProcessError:
                if time.monotonic() > deadline:
                    raise RuntimeError("Database readiness timeout")
                time.sleep(1)
        phase = "keycloak"
        docker("run", "--detach", "--rm", "--name", marker + "-idp", "--memory", "1g",
               "--user", str(os.getuid()) + ":0",
               "--publish", "127.0.0.1:8180:8080", "--env", "KC_HOSTNAME=http://localhost:8180",
               "--mount", f"type=bind,src={state_dir / 'realm.json'},dst=/opt/keycloak/data/import/consumer.json,readonly",
               "quay.io/keycloak/keycloak:26.8.2", "start-dev", "--import-realm")
        discovery = wait_http(ISSUER + "/.well-known/openid-configuration")
        if discovery["issuer"] != ISSUER:
            raise RuntimeError("Fixture issuer mismatch")
        env = dict(os.environ, DB_URL="jdbc:postgresql://127.0.0.1:15432/kunde", DB_USERNAME="kunde_ci",
                   DB_PASSWORD=state["dbPassword"], OIDC_ISSUER_URI="", OIDC_AUDIENCE="",
                   SPRING_PROFILES_ACTIVE="", CONSUMER_IDENTITY_ENABLED="false")
        phase = "maven-verify"
        with open(state_dir / "maven.log", "w") as log:
            subprocess.run(["mvn", "--batch-mode", "--no-transfer-progress", "clean", "verify"],
                           cwd=ROOT / "backend", env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
        phase = "backend"
        env.update(PORT="8081", CONSUMER_IDENTITY_ENABLED="true", OIDC_ISSUER_URI=ISSUER,
                   OIDC_AUDIENCE="kunde-api", SPRING_PROFILES_ACTIVE="identity-poc", POC_ALLOW_HTTP_ISSUER="true")
        with open(state_dir / "backend.log", "w") as log:
            app = subprocess.Popen(["java", "-Xmx512m", "-jar", str(ROOT / "backend/target/kunde-api-0.1.0-SNAPSHOT.jar"),
                                    "--server.address=127.0.0.1", "--kunde.fixture.id=" + marker],
                                   env=env, stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                                   start_new_session=True)
        state["backendPid"] = app.pid
        write_private(state_dir / "fixture.json", state)
        wait_http("http://localhost:8081/actuator/health", 90)
        print(json.dumps({"status": "NATIVE_STACK_READY", "stateDir": str(state_dir),
                          "scope": "synthetic loopback, no production approval"}))
    except Exception as error:
        try:
            stop(state_dir)
        except Exception:
            pass
        # Exception text/argv can contain credentials; expose only stage and type.
        print(json.dumps({"status": "NATIVE_STACK_FAILED", "phase": phase, "errorClass": type(error).__name__}))
        raise SystemExit(1) from None


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("start", "stop"))
    parser.add_argument("--state-dir", default=os.environ.get("KUNDE_NATIVE_DIR"))
    args = parser.parse_args()
    if args.action == "start":
        start()
    elif args.state_dir:
        stop(args.state_dir)
