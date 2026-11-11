"""Maintained pinned bases plus signed OS updates; no registry push or production deployment."""
import collections, hashlib, json, pathlib, subprocess, sys
from registry_metadata import resolve
out=pathlib.Path("reports");out.mkdir(exist_ok=True)
trivy="/tmp/kunde-trivy/trivy"
summary={"candidates":[],"scanner":"Trivy 0.76.2","status":"UNVERIFIED"};codes=[]
def scan(arguments,file):
    code=subprocess.run([trivy,"image","--scanners","vuln","--pkg-types","os","--skip-java-db-update",
        "--cache-dir","/tmp/kunde-probe-db","--timeout","6m","--format","json","--output",str(file),"--exit-code","10"]+arguments).returncode
    codes.append(code)
    if code not in [0,10]: raise RuntimeError("Scanner/database unavailable")
    data=json.loads(file.read_text())
    vulns=[v for result in data.get("Results",[]) for v in result.get("Vulnerabilities",[])]
    return {"exitCode":code,"severities":dict(collections.Counter(v["Severity"] for v in vulns)),
        "actionable":[{k:v.get(k) for k in ["VulnerabilityID","PkgName","InstalledVersion","FixedVersion","Severity"]}
                      for v in vulns if v["Severity"] in ["CRITICAL","HIGH"]]}
try:
    for role,image in [("runtime","eclipse-temurin:21-jre-noble"),("build","maven:3.10.0-eclipse-temurin-21-noble")]:
        entry={"role":role,**resolve(image)}
        entry["before"]=scan(["--image-src","remote",entry["reference"]],out/(role+"-vendor.json"))
        file=out/("candidate-"+role+".Dockerfile")
        file.write_text("FROM "+image+"@"+entry["platformDigest"]+"\n"
            "RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y --no-install-recommends && rm -rf /var/lib/apt/lists/*\n")
        subprocess.run(["docker","build","--pull","--platform","linux/amd64","-f",str(file),"-t","kunde-probe-"+role,"."],check=True)
        entry["rebuiltImageId"]=subprocess.check_output(["docker","image","inspect","kunde-probe-"+role,"--format","{{.Id}}"],text=True).strip()
        archive=pathlib.Path("/tmp/kunde-probe-"+role+".tar")
        subprocess.run(["docker","save","--output",str(archive),entry["rebuiltImageId"]],check=True)
        digest=hashlib.sha256()
        with archive.open("rb") as stream:
            for block in iter(lambda:stream.read(1024*1024),b""):digest.update(block)
        entry["archiveSha256"]=digest.hexdigest()
        entry["after"]=scan(["--input",str(archive)],out/(role+"-patched.json"))
        archive.unlink()
        summary["candidates"].append(entry)
        print("CONTAINER_CANDIDATE",json.dumps(entry),flush=True)
    summary["status"]="SCANNED_WITH_FINDINGS" if any(x==10 for x in codes) else "NO_KNOWN_FINDINGS_IN_SCOPE"
except Exception as error:
    summary["errorType"]=type(error).__name__
finally:
    with (out/"trivy-probe-database.txt").open("w") as log:subprocess.run([trivy,"--cache-dir","/tmp/kunde-probe-db","--version"],stdout=log)
    (out/"container-probe-summary.json").write_text(json.dumps(summary,indent=2)+"\n")
print("CONTAINER_PROBE_STATUS",summary["status"])
sys.exit(2 if summary["status"]=="UNVERIFIED" else 1 if any(x==10 for x in codes) else 0)
