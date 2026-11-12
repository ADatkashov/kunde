"""Exercise the packaged Java21 JAR against synthetic PostgreSQL, then stop it."""
import http.client, json, os, pathlib, subprocess, time, zipfile
jar=pathlib.Path("backend/target/kunde-api-0.1.0-SNAPSHOT.jar")
with zipfile.ZipFile(jar) as archive:
    assert "BOOT-INF/lib/spring-webmvc-7.0.10.jar" in archive.namelist()
out=pathlib.Path("reports");out.mkdir(exist_ok=True)
def call(method,path,body=None,chunked=False):
    client=http.client.HTTPConnection("127.0.0.1",18088,timeout=3)
    try:
        client.request(method,path,body=body,headers={"Content-Type":"application/json"} if body is not None else {},encode_chunked=chunked)
        response=client.getresponse()
        return response.status,dict(response.getheaders()),response.read()
    finally:client.close()
env=dict(os.environ,PORT="18088",OIDC_ISSUER_URI="",OIDC_AUDIENCE="",SPRING_PROFILES_ACTIVE="",API_MAX_BODY_BYTES="64")
with open("/tmp/kunde-jar-smoke.log","w") as log:
    app=subprocess.Popen(["java","-Xmx512m","-jar",str(jar.resolve()),"--server.address=127.0.0.1"],env=env,stdout=log,stderr=subprocess.STDOUT)
    try:
        deadline=time.monotonic()+60
        while True:
            if app.poll() is not None:raise RuntimeError("Packaged JAR exited")
            try:
                status,_,_=call("GET","/actuator/health")
                if status==200:break
            except OSError:pass
            if time.monotonic()>deadline:raise TimeoutError("Packaged JAR readiness")
            time.sleep(.25)
        protected,headers,body=call("POST","/api/v1/protected-test")
        assert protected==503
        data=json.loads(body);assert data["code"]=="AUTHENTICATION_NOT_CONFIGURED"
        assert isinstance(data["timestamp"],str) and "no-store" in headers["Cache-Control"]
        assert "Set-Cookie" not in headers
        openapi,_,document=call("GET","/api/v1/openapi.yaml")
        assert openapi==200 and b"openapi: 3.1.0" in document
        boundary,_,_=call("GET","/api/v1/categories",b"x"*64)
        assert boundary==200
        declared,_,body=call("GET","/api/v1/categories",b"x"*65)
        assert declared==413 and json.loads(body)["code"]=="PAYLOAD_TOO_LARGE"
        streamed,headers,body=call("GET","/%61pi/v1/categories",iter([b"x"*65]),True)
        assert streamed==413 and json.loads(body)["code"]=="PAYLOAD_TOO_LARGE"
        assert "no-store" in headers["Cache-Control"] and "Set-Cookie" not in headers
        result={"status":"PASS","health":status,"protectedWithoutIssuer":protected,"openapi":openapi,"bodyBoundary":boundary,"bodyOversize":declared,"chunkedOversize":streamed,"scope":"packaged JAR, synthetic DB, no native/provider E2E"}
        (out/"backend-smoke.json").write_text(json.dumps(result,indent=2)+"\n")
        print("JAR_SMOKE",json.dumps(result))
    finally:
        app.terminate()
        try:app.wait(timeout=25)
        except subprocess.TimeoutExpired:app.kill();app.wait()
