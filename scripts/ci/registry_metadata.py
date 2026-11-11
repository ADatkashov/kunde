"""Resolve official public Linux/amd64 bases. Tokens stay in memory; no layers downloaded."""
import argparse, datetime, hashlib, json, pathlib, re, urllib.parse, urllib.request
def resolve(image):
    source, separator, pinned=image.partition("@")
    repository,_,tag=source.partition(":")
    if repository not in ["eclipse-temurin","maven"]: raise ValueError("Unreviewed base repository")
    ref=pinned if separator else tag
    query=urllib.parse.urlencode({"service":"registry.docker.io","scope":"repository:library/"+repository+":pull"})
    with urllib.request.urlopen("https://auth.docker.io/token?"+query,timeout=30) as r: token=json.load(r)["token"]
    headers={"Authorization":"Bearer "+token,"Accept":"application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json"}
    def get(path):
        with urllib.request.urlopen(urllib.request.Request("https://registry-1.docker.io/v2/library/"+repository+"/"+path,headers=headers),timeout=30) as r:
            return r.read(),r.headers
    raw,meta=get("manifests/"+ref); manifest=json.loads(raw); digest=meta["Docker-Content-Digest"]
    if digest!="sha256:"+hashlib.sha256(raw).hexdigest(): raise ValueError("Manifest digest mismatch")
    if "manifests" in manifest:
        matches=[m["digest"] for m in manifest["manifests"] if m.get("platform",{}).get("os")=="linux" and m.get("platform",{}).get("architecture")=="amd64"]
        if len(matches)!=1: raise ValueError("Ambiguous platform manifest")
        platform_digest=matches[0]
    else:
        config,_=get("blobs/"+manifest["config"]["digest"]); config=json.loads(config)
        if (config.get("os"),config.get("architecture"))!=("linux","amd64"): raise ValueError("Wrong platform")
        platform_digest=digest
    if not re.fullmatch("sha256:[a-f0-9]{64}",platform_digest): raise ValueError("Invalid immutable digest")
    return {"image":image,"indexDigest":digest,"platformDigest":platform_digest,"reference":repository+"@"+platform_digest}
if __name__=="__main__":
    p=argparse.ArgumentParser();p.add_argument("--image",action="append",required=True);p.add_argument("--output",type=pathlib.Path,required=True);a=p.parse_args()
    report={"utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"images":[resolve(x) for x in a.image],"coverage":"manifest metadata only"}
    a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(report,indent=2)+"\n");print(json.dumps(report))
