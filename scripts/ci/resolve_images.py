"""Anonymous registry metadata only; no layers/DB downloaded, not a vulnerability scan."""
import datetime, hashlib, json, pathlib, re, urllib.parse, urllib.request
source=pathlib.Path("backend/Dockerfile").read_bytes()
bases=re.findall(r"(?im)^FROM\s+(\S+)",source.decode())
if len(bases)!=2: raise ValueError("Expected the reviewed two-stage Dockerfile; update coverage explicitly")
images=[]
# Retain runtime-first ordering expected by the scan job.
for image in [bases[1],bases[0]]:
    repository,tag=image.split(":")
    if repository not in ["eclipse-temurin","maven"]: raise ValueError("Unsupported registry/base; do not silently scan another image")
    name="library/"+repository
    query=urllib.parse.urlencode({"service":"registry.docker.io","scope":"repository:"+name+":pull"})
    with urllib.request.urlopen("https://auth.docker.io/token?"+query,timeout=20) as r: token=json.load(r)["token"]
    req=urllib.request.Request("https://registry-1.docker.io/v2/"+name+"/manifests/"+tag,
        headers={"Authorization":"Bearer "+token,"Accept":"application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json"})
    with urllib.request.urlopen(req,timeout=20) as r:
        index=r.headers["Docker-Content-Digest"]; data=json.load(r)
    manifests=[m["digest"] for m in data["manifests"] if m.get("platform",{}).get("os")=="linux" and m.get("platform",{}).get("architecture")=="amd64"]
    if len(manifests)!=1 or not index.startswith("sha256:"): raise ValueError("Immutable platform manifest unavailable")
    images.append({"image":image,"indexDigest":index,"platformDigest":manifests[0],"reference":repository+"@"+manifests[0]})
pathlib.Path("reports").mkdir(exist_ok=True)
pathlib.Path("reports/images.json").write_text(json.dumps({"utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"dockerfileSha256":hashlib.sha256(source).hexdigest(),"coverage":"metadata only","images":images},indent=2)+"\n")
