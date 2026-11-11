"""Consolidate downloaded baseline reports. Do not equate matches, instances and advisories."""
import collections, datetime, hashlib, json, pathlib, urllib.request
root=pathlib.Path("baseline")
out=pathlib.Path("reports"); out.mkdir(exist_ok=True)
entries={}
details={}
def advisory(identifier):
    if identifier not in details:
        with urllib.request.urlopen("https://api.osv.dev/v1/vulns/"+identifier,timeout=30) as r: details[identifier]=json.load(r)
    return details[identifier]
def add(category, identifier, package, version, path, severity, fixed, path_status, **extra):
    key=(identifier,package,version,tuple(path))
    if key not in entries:
        entries[key]={"advisory":identifier,"package":package,"version":version,"dependencyPath":path,
            "severity":severity,"fixedVersions":fixed,"pathStatus":path_status,"categories":[]}
        entries[key].update(extra)
    if category not in entries[key]["categories"]: entries[key]["categories"].append(category)
def load(name): return json.loads((root/name).read_text())
maven=load("dependencies/maven.json")
paths=collections.defaultdict(list)
def walk(node,path):
    coord=node["groupId"]+":"+node["artifactId"]+":"+node["version"]
    path=path+[coord]; paths[(node["groupId"]+":"+node["artifactId"],node["version"])].append(path)
    for child in node.get("children",[]): walk(child,path)
walk(maven,[])
raw={}
for category,file in [("maven-pub","dependencies/dependencies-osv.json"),("android-gradle","android-audit/android-osv.json")]:
    report=load(file); raw[category]=len(report["findings"])
    for f in report["findings"]:
        eco,name,version=f["coordinate"]; detail=advisory(f["id"])
        canonical=next((x for x in detail.get("aliases",[]) if x.startswith("CVE-")),f["id"])
        fixed=sorted({event["fixed"] for affected in detail.get("affected",[])
            if affected.get("package",{}).get("name")==name
            for interval in affected.get("ranges",[]) for event in interval.get("events",[]) if "fixed" in event})
        package=eco+":"+name
        observed=paths.get((name,version),[]) if category=="maven-pub" and eco=="Maven" else []
        if observed:
            for path in observed: add("maven",canonical,package,version,path,f["severity"],fixed,"observed",sourceAdvisory=f["id"])
        elif eco=="Pub":
            add("flutter-dart",canonical,package,version,["hosted-pub:"+name],f["severity"],fixed,
                "flat-pub-dependency-path-unavailable",sourceAdvisory=f["id"])
        else:
            add(category,canonical,package,version,["baseline-flat-native-graph:"+name],f["severity"],fixed,
                "native-configuration/path-unavailable-in-old-artifact",sourceAdvisory=f["id"])
for category,file in [("runtime-container","containers/runtime-os.json"),("build-container","containers/build-os.json")]:
    report=load(file); digest=report.get("Metadata",{}).get("RepoDigests",[]) or [report.get("ArtifactName","unknown-image")]
    matches=[(result,v) for result in report.get("Results",[]) for v in result.get("Vulnerabilities",[])]
    raw[category]=len(matches)
    for result,v in matches:
        package="OS:"+v["PkgName"]
        add(category,v["VulnerabilityID"],package,v["InstalledVersion"],
            [digest[0],result.get("Target","unknown-target"),v["PkgName"]],
            v["Severity"],[v["FixedVersion"]] if v.get("FixedVersion") else [],"image/package",
            os=report.get("Metadata",{}).get("OS"),packagePurl=v.get("PkgIdentifier",{}).get("PURL"))
items=list(entries.values())
summary={"utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"baselineCommit":"6c1962a7653419a057c473eab86c3600483aa087",
    "baselineRuns":[43032030110,43032030047],
    "inputSha256":{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in root.rglob("*.json")},"rawScannerMatches":raw,
    "uniqueAdvisories":len({x["advisory"] for x in items}),"deduplicatedInstances":len(items),
    "deduplicationKey":["canonicalAdvisory","ecosystem/package","resolvedVersion","observableDependencyPath"],
    "categories":{},"pathLimitations":["Original Maven tree is nonverbose; only visible paths are reconstructed",
        "Original native graph is flat; do not invent ownership/runtime paths","Original Pub graph does not encode complete transitive paths"],
    "unverified":["Flutter SDK included builds","Android SDK/NDK binaries","JDK archive CVEs","action runtimes"]}
for category in ["maven","flutter-dart","android-gradle","runtime-container","build-container"]:
    xs=[x for x in items if category in x["categories"]]
    summary["categories"][category]={"uniqueAdvisories":len({x["advisory"] for x in xs}),
        "instances":len(xs),"severities":dict(collections.Counter(x["severity"] for x in xs))}
rank={"CRITICAL":4,"HIGH":3,"MODERATE":2,"MEDIUM":2,"LOW":1}
worst={}
for item in items:
    key=item["advisory"]
    severity=item["severity"]
    if rank.get(severity,0)>rank.get(worst.get(key,""),-1): worst[key]=severity
summary["uniqueAdvisoriesByMaxObservedSeverity"]=dict(collections.Counter(worst.values()))
(out/"baseline-ledger.json").write_text(json.dumps({"summary":summary,"instances":items},indent=2)+"\n")
(out/"baseline-advisory-details.json").write_text(json.dumps(details,indent=2)+"\n")
print("BASELINE_SUMMARY",json.dumps(summary))
for x in items:
    if x["severity"] in ["CRITICAL","HIGH"] and any(c in x["categories"] for c in ["maven","android-gradle"]):
        print("BASELINE_ACTIONABLE",json.dumps(x))
