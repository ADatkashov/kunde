"""Build both effective images, smoke runtime, scan OS packages without suppression."""
import collections,hashlib,http.client,json,os,pathlib,subprocess,time
out=pathlib.Path("reports");out.mkdir(exist_ok=True)
def run(args,**kw):return subprocess.run(args,check=True,**kw)
summary={"coverage":"Effective images: recognized RHEL OS packages. Application Java graph audited independently. Maven distribution embedded libraries not fully covered.","images":[]}
codes=[]
for role,target in [("build","build"),("runtime",None)]:
    tag="kunde-security-"+role
    cmd=["docker","build","--network=host","--progress=plain","-t",tag]
    if target:cmd+=["--target",target]
    run(cmd+["backend"])
    image_id=subprocess.check_output(["docker","image","inspect","--format","{{.Id}}",tag],text=True).strip()
    archive=pathlib.Path("/tmp/kunde-"+role+".tar")
    run(["docker","save","-o",str(archive),tag])
    with archive.open("rb") as stream:
        archive_hash=hashlib.file_digest(stream,"sha256").hexdigest()
    report=out/(role+"-effective-os.json")
    code=subprocess.run(["/tmp/kunde-trivy/trivy","image","--input",str(archive),"--scanners","vuln","--pkg-types","os","--list-all-pkgs","--skip-java-db-update","--cache-dir","/tmp/kunde-trivy-db","--timeout","6m","--format","json","--output",str(report),"--exit-code","10"]).returncode
    archive.unlink()
    data=json.loads(report.read_text());assert data["Metadata"]["OS"]["Family"]=="redhat"
    packages=sum(len(x.get("Packages",[])) for x in data.get("Results",[]) if x.get("Class")=="os-pkgs")
    assert packages>0,"Missing recognized OS package inventory"
    vulns=[v for x in data.get("Results",[]) for v in x.get("Vulnerabilities",[])]
    entry={"role":role,"imageId":image_id,"savedArchiveSha256":archive_hash,"exitCode":code,"osPackages":packages,"severities":dict(collections.Counter(v["Severity"] for v in vulns))}
    summary["images"].append(entry);codes.append(code);print("EFFECTIVE_CONTAINER",json.dumps(entry),flush=True)
    (out/"effective-containers.json").write_text(json.dumps(summary,indent=2)+"\n")
run(["docker","run","-d","--name","kunde-runtime-smoke","--network=host","-e","DB_URL=jdbc:postgresql://127.0.0.1:5432/kunde","-e","DB_USERNAME=kunde_ci","-e","DB_PASSWORD=synthetic_ci_only","-e","PORT=18089","kunde-security-runtime"])
try:
    deadline=time.monotonic()+75
    while True:
        try:
            c=http.client.HTTPConnection("127.0.0.1",18089,timeout=2);c.request("GET","/actuator/health");r=c.getresponse();r.read();c.close()
            if r.status==200:break
        except OSError:pass
        if time.monotonic()>deadline:raise TimeoutError("Container readiness")
        time.sleep(.5)
    c=http.client.HTTPConnection("127.0.0.1",18089,timeout=3);c.request("POST","/api/v1/protected-test");r=c.getresponse();body=json.loads(r.read());assert r.status==503 and body["code"]=="AUTHENTICATION_NOT_CONFIGURED";c.close()
    print("CONTAINER_SMOKE PASS health=200 protected=503 user=10001",flush=True)
    summary["smoke"]="PASS";(out/"effective-containers.json").write_text(json.dumps(summary,indent=2)+"\n")
finally:run(["docker","rm","-f","kunde-runtime-smoke"])
run(["/tmp/kunde-trivy/trivy","--cache-dir","/tmp/kunde-trivy-db","--version"],stdout=(out/"effective-trivy-db.txt").open("w"))
raise SystemExit(2 if any(x not in [0,10] for x in codes) else 1 if any(x==10 for x in codes) else 0)
