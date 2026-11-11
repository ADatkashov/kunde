"""Allowlisted network diagnosis. Do not print proxy values or change resolver/TLS settings."""
import json, os, pathlib, socket, urllib.error, urllib.request
report={"proxyVariablePresence":{k:bool(os.environ.get(k)) for k in [
    "HTTP_PROXY","HTTPS_PROXY","NO_PROXY","http_proxy","https_proxy","no_proxy"]},"hosts":{}}
for host,path in [("archive.ubuntu.com","/ubuntu/dists/noble/InRelease"),
                  ("security.ubuntu.com","/ubuntu/dists/noble-security/InRelease"),
                  ("repo.maven.apache.org","/maven2/")]:
    evidence={}
    try: socket.getaddrinfo(host,443);evidence["directDns"]=True
    except OSError as error:evidence["directDns"]=False;evidence["dnsErrorType"]=type(error).__name__
    try:
        with urllib.request.urlopen(urllib.request.Request("https://"+host+path,method="HEAD"),timeout=8) as response:
            evidence["httpsStatus"]=response.status
    except urllib.error.HTTPError as error:evidence["httpsStatus"]=error.code
    except (OSError,urllib.error.URLError) as error:evidence["httpsErrorType"]=type(error).__name__
    report["hosts"][host]=evidence
pathlib.Path("reports").mkdir(exist_ok=True)
pathlib.Path("reports/container-network.json").write_text(json.dumps(report,indent=2)+"\n")
print("CONTAINER_NETWORK",json.dumps(report))
