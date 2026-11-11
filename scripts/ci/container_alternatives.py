"""Audit maintained official Java21 alternatives; never substitute unmaintained images."""
import collections, json, pathlib, subprocess, sys
from registry_metadata import resolve
out=pathlib.Path("reports");out.mkdir(exist_ok=True)
summary={"candidates":[],"coverage":"OS packages only; immutable official Linux/amd64 vendor images"};codes=[]
candidates=[("runtime","eclipse-temurin:21-jre-ubi9-minimal"),("runtime","eclipse-temurin:21-jre-ubi10-minimal"),
            ("build","maven:3.10.0-amazoncorretto-21-al2023"),("build","maven:3.10.0-amazoncorretto-21-debian-trixie")]
for index,(role,image) in enumerate(candidates):
    entry={"role":role,"image":image}
    try:
        entry.update(resolve(image))
        file=out/("alternative-"+str(index)+".json")
        code=subprocess.run(["/tmp/kunde-trivy/trivy","image","--image-src","remote","--scanners","vuln",
            "--pkg-types","os","--skip-java-db-update","--cache-dir","/tmp/kunde-alternatives-db","--timeout","6m",
            "--format","json","--output",str(file),"--exit-code","10",entry["reference"]]).returncode
        entry["exitCode"]=code;codes.append(code)
        if code not in [0,10]:raise RuntimeError("Incomplete vendor scan")
        data=json.loads(file.read_text());vulns=[v for result in data.get("Results",[]) for v in result.get("Vulnerabilities",[])]
        entry["os"]=data.get("Metadata",{}).get("OS")
        entry["severities"]=dict(collections.Counter(v["Severity"] for v in vulns))
        entry["actionable"]=[{k:v.get(k) for k in ["VulnerabilityID","PkgName","InstalledVersion","FixedVersion","Severity"]} for v in vulns if v["Severity"] in ["CRITICAL","HIGH"]]
    except Exception as error:entry["errorType"]=type(error).__name__;codes.append(2)
    summary["candidates"].append(entry)
    print("MAINTAINED_CONTAINER_ALTERNATIVE",json.dumps(entry),flush=True)
(out/"container-alternatives.json").write_text(json.dumps(summary,indent=2)+"\n")
with (out/"trivy-alternatives-database.txt").open("w") as log:subprocess.run(["/tmp/kunde-trivy/trivy","--cache-dir","/tmp/kunde-alternatives-db","--version"],stdout=log)
sys.exit(2 if any(x not in [0,10] for x in codes) else 1 if any(x==10 for x in codes) else 0)
