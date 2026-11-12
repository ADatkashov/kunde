"""KUNDE OSV audit v2: actual graph/root coordinates; exit0 scoped clear,1 findings,2 unavailable."""
import argparse, datetime, hashlib, json, pathlib, re, sys, urllib.request
import xml.etree.ElementTree as ET

def request(path, body=None):
    req = urllib.request.Request("https://api.osv.dev/v1/"+path,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Content-Type":"application/json"})
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.load(response)

def python_requirements(path):
    coordinates = set()
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"): continue
        match = re.fullmatch(r"([A-Za-z0-9][A-Za-z0-9_.-]*)==([A-Za-z0-9_.+!-]+) --hash=sha256:[a-f0-9]{64}", line)
        if not match: raise ValueError("Python requirement must have an exact version and SHA-256")
        coordinates.add(("PyPI", re.sub(r"[-_.]+", "-", match[1]).lower(), match[2]))
    if not coordinates: raise ValueError("Empty Python requirements")
    return coordinates


def main():
    p=argparse.ArgumentParser()
    p.add_argument("--python-requirements", type=pathlib.Path)
    p.add_argument("--maven", type=pathlib.Path)
    p.add_argument("--pub", type=pathlib.Path)
    p.add_argument("--effective", type=pathlib.Path)
    p.add_argument("--settings", type=pathlib.Path)
    p.add_argument("--output", type=pathlib.Path, required=True)
    a=p.parse_args()
    report={"scanner":"KUNDE OSV audit v2","utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "database":"https://api.osv.dev/v1/","databaseSnapshot":"not supplied by API",
        "status":"UNVERIFIED","findings":[],"inputSha256":{},"coverageExclusions":[
            "JDK runtime","Flutter/Dart SDK and engine","Android SDK/NDK binaries","Gradle distribution",
            "unobserved included-build/plugin transitives","container/OS packages","Git history secrets"]}
    code=2
    try:
        coordinates=set()
        for file in [a.maven,a.pub,a.effective,a.settings,a.python_requirements]:
            if file: report["inputSha256"][str(file)]=hashlib.sha256(file.read_bytes()).hexdigest()
        def visit(node):
            version=node["version"]
            if "$" in version: raise ValueError("Unresolved Maven version")
            coordinates.add(("Maven",node["groupId"]+":"+node["artifactId"],version))
            for child in node.get("children",[]): visit(child)
        if a.maven:
            for child in json.loads(a.maven.read_text()).get("children",[]): visit(child)
        if a.pub:
            report["unverifiedPub"]=[]
            for pkg in json.loads(a.pub.read_text())["packages"]:
                if pkg.get("kind")=="root": continue
                if pkg.get("source")=="hosted": coordinates.add(("Pub",pkg["name"],pkg["version"]))
                else: report["unverifiedPub"].append({"name":pkg["name"],"source":pkg.get("source")})
        if a.effective:
            root=ET.parse(a.effective).getroot()
            namespace={"m":"http://maven.apache.org/POM/4.0.0"}
            for plugin in root.findall("./m:build/m:plugins/m:plugin",namespace):
                name=plugin.findtext("m:artifactId",namespaces=namespace)
                group=plugin.findtext("m:groupId",default="org.apache.maven.plugins",namespaces=namespace)
                version=plugin.findtext("m:version",namespaces=namespace)
                if not version or "$" in version: raise ValueError("Unresolved plugin version")
                coordinates.add(("Maven",group+":"+name,version))
        if a.settings:
            text=a.settings.read_text()
            for identifier,name in [("com.android.application","com.android.tools.build:gradle"),
                                    ("org.jetbrains.kotlin.android","org.jetbrains.kotlin:kotlin-gradle-plugin")]:
                match=re.search(r'id\("'+re.escape(identifier)+r'"\)\s+version\s+"([^"]+)"',text)
                if not match or "$" in match[1]: raise ValueError("Missing explicit plugin version")
                coordinates.add(("Maven",name,match[1]))
        if a.python_requirements: coordinates.update(python_requirements(a.python_requirements))
        coordinates=sorted(coordinates)
        if not coordinates: raise ValueError("Empty audit graph")
        report["coordinates"]=[{"ecosystem":e,"name":n,"version":v} for e,n,v in coordinates]
        queries=[{"package":{"ecosystem":e,"name":n},"version":v} for e,n,v in coordinates]
        results=request("querybatch",{"queries":queries})["results"]
        if len(results)!=len(coordinates): raise ValueError("Incomplete OSV response")
        details={}
        for coordinate,result in zip(coordinates,results):
            for vuln in result.get("vulns",[]):
                identifier=vuln["id"]
                if identifier not in details: details[identifier]=request("vulns/"+identifier)
                detail=details[identifier]
                if detail.get("withdrawn"): continue
                report["findings"].append({"coordinate":coordinate,"id":identifier,
                    "severity":detail.get("database_specific",{}).get("severity","UNSPECIFIED"),
                    "summary":detail.get("summary"),"modified":detail.get("modified")})
        report["status"]="SCANNED_WITH_FINDINGS" if report["findings"] else "NO_KNOWN_FINDINGS_IN_SCOPE"
        code=1 if report["findings"] else 0
    except Exception as error:
        report["errorType"]=type(error).__name__
    report["exitCode"]=code
    a.output.parent.mkdir(parents=True,exist_ok=True)
    a.output.write_text(json.dumps(report,indent=2)+"\n")
    print(json.dumps({"status":report["status"],"exitCode":code,"findings":len(report["findings"])}))
    if code == 1:
        import collections
        print("SEVERITIES",dict(collections.Counter(v["severity"] for v in report["findings"])))
        for finding in report["findings"]:
            print("FINDING",json.dumps(finding))
    return code
if __name__=="__main__": sys.exit(main())
